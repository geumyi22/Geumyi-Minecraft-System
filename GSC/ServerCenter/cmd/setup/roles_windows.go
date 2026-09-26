//go:build windows

package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const roleStateFile = "role.json"

type RoleState struct {
	Version                string `json:"version"`
	Role                   int    `json:"role"`
	RoleName               string `json:"role_name"`
	UpdatedAt              string `json:"updated_at"`
	DedicatedProfileActive bool   `json:"dedicated_profile_active"`
}

func roleName(role int) string {
	switch role {
	case 1:
		return "서버 PC"
	case 2:
		return "본컴 / 원격 관리 PC"
	case 3:
		return "둘 다"
	default:
		return "미확인"
	}
}

func hasServerRole(role int) bool { return role == 1 || role == 3 }
func hasClientRole(role int) bool { return role == 2 || role == 3 }

func detectInstalledRole(dataDir, installDir string) int {
	var st RoleState
	if b, err := os.ReadFile(filepath.Join(dataDir, roleStateFile)); err == nil {
		if json.Unmarshal(b, &st) == nil && st.Role >= 1 && st.Role <= 3 {
			return st.Role
		}
	}

	server := serviceExists(hostServiceName) || taskExists(hostTaskName)
	if !server {
		if _, err := os.Stat(filepath.Join(installDir, "GeumyiServerHost.exe")); err == nil {
			if _, err2 := os.Stat(filepath.Join(dataDir, "server.json")); err2 == nil {
				server = true
			}
		}
	}

	client := false
	cdir := filepath.Join(envOr("APPDATA", envOr("LOCALAPPDATA", ".")), "GeumyiServerCenter")
	if _, err := os.Stat(filepath.Join(cdir, "client.json")); err == nil {
		client = true
	}
	if !client {
		if _, err := os.Stat(filepath.Join(installDir, "GeumyiServerCenter.exe")); err == nil {
			client = true
		}
	}

	switch {
	case server && client:
		return 3
	case server:
		return 1
	case client:
		return 2
	default:
		return 0
	}
}

func taskExists(name string) bool {
	c := exec.Command("schtasks.exe", "/Query", "/TN", name)
	hideCmd(c)
	return c.Run() == nil
}

func writeRoleState(dataDir string, role int, dedicated bool) {
	writeJSON(filepath.Join(dataDir, roleStateFile), RoleState{
		Version: version, Role: role, RoleName: roleName(role),
		UpdatedAt: time.Now().Format(time.RFC3339), DedicatedProfileActive: dedicated,
	})
}

// When a machine stops being a server machine, ask the running Host to save and
// stop all managed Minecraft servers before the Host component is removed.
func gracefulHostShutdownForTransition() error {
	health := http.Client{Timeout: 1200 * time.Millisecond}
	pd := envOr("PROGRAMDATA", `C:\ProgramData`)
	token := readExistingServerConfig(filepath.Join(pd, "GeumyiServerCenter", "server.json")).APIToken
	auth := func(req *http.Request) {
		if token != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}
	}
	r, err := health.Get("http://127.0.0.1:8787/api/health")
	if err != nil {
		// If Host is down but a managed Minecraft port is still listening, do not
		// orphan a live server by removing the server role.
		old := readExistingServerConfig(filepath.Join(pd, "GeumyiServerCenter", "server.json"))
		for _, sv := range old.Servers {
			if sv.JavaPort > 0 && localTCPListening(sv.JavaPort) {
				return fmt.Errorf("Host는 응답하지 않지만 %s 서버 포트 %d가 열려 있습니다. 서버를 정상 종료한 뒤 역할을 전환하세요", sv.Name, sv.JavaPort)
			}
		}
		return nil // Host and managed server ports are both down.
	}
	_ = r.Body.Close()
	if r.StatusCode/100 != 2 {
		return nil
	}

	req, _ := http.NewRequest(http.MethodPost, "http://127.0.0.1:8787/api/shutdown", bytes.NewBufferString("{}"))
	req.Header.Set("Content-Type", "application/json")
	auth(req)
	r, err = health.Do(req)
	if err != nil {
		return fmt.Errorf("기존 Host에 정상 종료를 요청하지 못했습니다: %w", err)
	}
	_ = r.Body.Close()
	if r.StatusCode != http.StatusAccepted {
		return fmt.Errorf("기존 Host 정상 종료 요청이 거절되었습니다: HTTP %d", r.StatusCode)
	}

	deadline := time.Now().Add(195 * time.Second)
	for time.Now().Before(deadline) {
		time.Sleep(750 * time.Millisecond)
		statusReq, _ := http.NewRequest(http.MethodGet, "http://127.0.0.1:8787/api/shutdown/status", nil)
		auth(statusReq)
		rr, e := health.Do(statusReq)
		if e != nil {
			return nil // Host already exited.
		}
		var st struct {
			Phase   string   `json:"phase"`
			Message string   `json:"message"`
			Errors  []string `json:"errors"`
		}
		body, _ := io.ReadAll(io.LimitReader(rr.Body, 1<<20))
		_ = rr.Body.Close()
		if rr.StatusCode/100 != 2 {
			continue
		}
		if json.Unmarshal(body, &st) != nil {
			continue
		}
		switch st.Phase {
		case "failed":
			return fmt.Errorf("서버 저장/종료 실패: %s %s", st.Message, strings.Join(st.Errors, "; "))
		case "ready":
			q, _ := http.NewRequest(http.MethodPost, "http://127.0.0.1:8787/api/shutdown/finish", bytes.NewBufferString("{}"))
			q.Header.Set("Content-Type", "application/json")
			auth(q)
			if resp, e := health.Do(q); e == nil {
				_ = resp.Body.Close()
			}
			for i := 0; i < 20; i++ {
				time.Sleep(250 * time.Millisecond)
				if !healthOK("http://127.0.0.1:8787/api/health") {
					return nil
				}
			}
			return nil
		}
	}
	return fmt.Errorf("기존 서버를 195초 안에 정상 종료하지 못했습니다. 데이터 보호를 위해 역할 전환을 중단했습니다")
}

func localTCPListening(port int) bool {
	c, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), 450*time.Millisecond)
	if err != nil {
		return false
	}
	_ = c.Close()
	return true
}

func removeClientComponent(installDir string) {
	setClientAutostart("", false)
	removeShortcuts()
	_ = os.Remove(filepath.Join(installDir, "GeumyiServerCenter.exe"))
	setupLog("role transition: client component removed")
}

func removeServerComponent(installDir, dataDir string) {
	deleteHostService()
	for _, n := range []string{"Geumyi Server Host", hostTaskName} {
		c := exec.Command("schtasks.exe", "/End", "/TN", n)
		hideCmd(c)
		_ = c.Run()
		c = exec.Command("schtasks.exe", "/Delete", "/TN", n, "/F")
		hideCmd(c)
		_ = c.Run()
	}
	c := exec.Command("taskkill.exe", "/IM", "GeumyiServerHost.exe", "/F")
	hideCmd(c)
	_ = c.Run()
	stopIntegratedAgentProcess()
	removeFirewallRule()
	removeMinecraftFirewallRules()
	_ = os.Remove(filepath.Join(installDir, "GeumyiServerHost.exe"))

	// Keep agent.properties and agent data so a future server-role reinstall can
	// restore the same Discord/GDS identity, but remove the executable payload.
	agentDir := filepath.Join(dataDir, "Runtime", "Agent")
	for _, jar := range []string{"GeumyiStatusAgent-0.5.4.jar", "GeumyiStatusAgent-0.5.2.jar", "GeumyiStatusAgent-0.5.1.jar", "GeumyiStatusAgent-0.5.0.jar", "GeumyiStatusAgent-0.4.5.jar"} {
		_ = os.Remove(filepath.Join(agentDir, jar))
	}
	_ = os.Remove(filepath.Join(agentDir, "agent.pid"))
	setupLog("role transition: server Host/Agent runtime removed; Agent config/data preserved")
}

func stopIntegratedAgentProcess() {
	// Agent 0.5+ owns a loopback-only graceful shutdown endpoint. Give it a
	// short chance to close Discord/HTTP itself before the identity-scoped
	// process fallback used for old or unhealthy installations.
	client := &http.Client{Timeout: 900 * time.Millisecond}
	if req, err := http.NewRequest(http.MethodPost, "http://127.0.0.1:8877/shutdown", strings.NewReader("{}")); err == nil {
		req.Header.Set("Content-Type", "application/json")
		if resp, err := client.Do(req); err == nil {
			_ = resp.Body.Close()
			time.Sleep(650 * time.Millisecond)
		}
	}
	ps := `$ErrorActionPreference='SilentlyContinue'; Get-CimInstance Win32_Process | Where-Object { ($_.Name -ieq 'java.exe' -or $_.Name -ieq 'javaw.exe') -and $_.CommandLine -match 'GeumyiStatusAgent[^ ]*\.jar' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }`
	c := exec.Command("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps)
	hideCmd(c)
	_ = c.Run()
}

func stopDashboardEdgeApp() {
	// Never kill the user's normal Edge windows. Match only the GSC app URL or
	// the dedicated DashboardProfile used by GeumyiServerCenter.exe.
	profile := filepath.Join(envOr("APPDATA", envOr("LOCALAPPDATA", ".")), "GeumyiServerCenter", "DashboardProfile")
	profile = strings.ReplaceAll(profile, "'", "''")
	ps := fmt.Sprintf(`$ErrorActionPreference='SilentlyContinue';$profile='%s'; Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | Where-Object { $cl=$_.CommandLine; $cl -and (($cl -match '--app=http://127\.0\.0\.1:8790') -or ($cl.IndexOf('--user-data-dir='+$profile,[StringComparison]::OrdinalIgnoreCase) -ge 0) -or ($cl.IndexOf('--user-data-dir="'+$profile+'"',[StringComparison]::OrdinalIgnoreCase) -ge 0)) } | ForEach-Object { try { $p=Get-Process -Id $_.ProcessId -ErrorAction Stop; if($p.MainWindowHandle -ne 0){$null=$p.CloseMainWindow()} } catch {} }; Start-Sleep -Milliseconds 450; Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | Where-Object { $cl=$_.CommandLine; $cl -and (($cl -match '--app=http://127\.0\.0\.1:8790') -or ($cl.IndexOf('--user-data-dir='+$profile,[StringComparison]::OrdinalIgnoreCase) -ge 0) -or ($cl.IndexOf('--user-data-dir="'+$profile+'"',[StringComparison]::OrdinalIgnoreCase) -ge 0)) } | ForEach-Object { & taskkill.exe /PID $_.ProcessId /T /F 1>$null 2>$null }`, profile)
	c := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", ps)
	hideCmd(c)
	_ = c.Run()
}

func removeShortcuts() {
	paths := []string{
		filepath.Join(os.Getenv("USERPROFILE"), "Desktop", "Geumyi Server Center.lnk"),
		filepath.Join(envOr("APPDATA", "."), `Microsoft\Windows\Start Menu\Programs\Geumyi Server Center.lnk`),
	}
	for _, p := range paths {
		_ = os.Remove(p)
	}
}

func prepareForUpgradeAll() {
	stopDashboardEdgeApp()
	c := exec.Command("taskkill.exe", "/IM", "GeumyiServerCenter.exe", "/F")
	hideCmd(c)
	_ = c.Run()
	stopHostService()
	for _, n := range []string{"Geumyi Server Host", hostTaskName} {
		c := exec.Command("schtasks.exe", "/End", "/TN", n)
		hideCmd(c)
		_ = c.Run()
	}
	c = exec.Command("taskkill.exe", "/IM", "GeumyiServerHost.exe", "/F")
	hideCmd(c)
	_ = c.Run()
	stopIntegratedAgentProcess()
	time.Sleep(700 * time.Millisecond)
}
