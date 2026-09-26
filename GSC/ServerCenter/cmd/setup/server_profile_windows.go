//go:build windows

package main

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const serverProfileStateFile = "server-pc-profile.json"

var powerGUIDRE = regexp.MustCompile(`(?i)([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})`)

type RegSnapshot struct {
	Key     string `json:"key"`
	Name    string `json:"name"`
	Exists  bool   `json:"exists"`
	Type    string `json:"type,omitempty"`
	Data    string `json:"data,omitempty"`
	NewData string `json:"new_data,omitempty"`
}

type ServerPCProfileState struct {
	Version             string        `json:"version"`
	Applied             bool          `json:"applied"`
	AppliedAt           string        `json:"applied_at,omitempty"`
	RestoredAt          string        `json:"restored_at,omitempty"`
	PreviousPowerScheme string        `json:"previous_power_scheme,omitempty"`
	DedicatedPowerGUID  string        `json:"dedicated_power_guid,omitempty"`
	Registry            []RegSnapshot `json:"registry"`
	Notes               []string      `json:"notes,omitempty"`
}

type regSetting struct {
	Key, Name, Data string
}

var dedicatedRegSettings = []regSetting{
	{`HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU`, "NoAutoRebootWithLoggedOnUsers", "1"},
	{`HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU`, "AUOptions", "3"},
	{`HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU`, "AlwaysAutoRebootAtScheduledTime", "0"},
	{`HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power`, "HiberbootEnabled", "0"},
	{`HKLM\SYSTEM\CurrentControlSet\Control\CrashControl`, "AutoReboot", "1"},
	{`HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling`, "PowerThrottlingOff", "1"},
	{`HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR`, "AllowGameDVR", "0"},
	{`HKCU\System\GameConfigStore`, "GameDVR_Enabled", "0"},
	{`HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR`, "AppCaptureEnabled", "0"},
}

func runHiddenOutput(name string, args ...string) ([]byte, error) {
	c := exec.Command(name, args...)
	hideCmd(c)
	return c.CombinedOutput()
}

func activePowerScheme() string {
	b, err := runHiddenOutput("powercfg.exe", "/getactivescheme")
	if err != nil {
		return ""
	}
	return firstPowerGUID(string(b))
}

func firstPowerGUID(s string) string {
	m := powerGUIDRE.FindStringSubmatch(s)
	if len(m) < 2 {
		return ""
	}
	return strings.ToLower(m[1])
}

func queryRegValue(key, name string) RegSnapshot {
	snap := RegSnapshot{Key: key, Name: name}
	b, err := runHiddenOutput("reg.exe", "QUERY", key, "/v", name)
	if err != nil {
		return snap
	}
	for _, ln := range strings.Split(string(b), "\n") {
		if !strings.Contains(strings.ToLower(ln), strings.ToLower(name)) {
			continue
		}
		f := strings.Fields(strings.TrimSpace(ln))
		if len(f) >= 3 && strings.EqualFold(f[0], name) {
			snap.Exists = true
			snap.Type = f[1]
			snap.Data = strings.Join(f[2:], " ")
			return snap
		}
	}
	return snap
}

func setRegDWORD(key, name, data string) error {
	b, err := runHiddenOutput("reg.exe", "ADD", key, "/v", name, "/t", "REG_DWORD", "/d", data, "/f")
	if err != nil {
		return fmt.Errorf("reg %s/%s: %w %s", key, name, err, strings.TrimSpace(string(b)))
	}
	return nil
}

func restoreRegValue(s RegSnapshot) {
	if !s.Exists {
		_, _ = runHiddenOutput("reg.exe", "DELETE", s.Key, "/v", s.Name, "/f")
		return
	}
	typ := s.Type
	if typ == "" {
		typ = "REG_DWORD"
	}
	_, _ = runHiddenOutput("reg.exe", "ADD", s.Key, "/v", s.Name, "/t", typ, "/d", s.Data, "/f")
}

func applyDedicatedServerProfile(dataDir string) (ServerPCProfileState, error) {
	profileDir := filepath.Join(dataDir, "SystemProfile")
	_ = os.MkdirAll(profileDir, 0755)
	statePath := filepath.Join(profileDir, serverProfileStateFile)

	var old ServerPCProfileState
	if b, err := os.ReadFile(statePath); err == nil && json.Unmarshal(b, &old) == nil && old.Applied {
		// Re-apply desired values without overwriting the original baseline.
		for _, s := range dedicatedRegSettings {
			if err := setRegDWORD(s.Key, s.Name, s.Data); err != nil {
				setupLog("server profile reapply warning: " + err.Error())
			}
		}
		if old.DedicatedPowerGUID != "" {
			_, _ = runHiddenOutput("powercfg.exe", "/setactive", old.DedicatedPowerGUID)
		}
		old.Version = version
		old.AppliedAt = time.Now().Format(time.RFC3339)
		writeJSON(statePath, old)
		writeServerPCStatus(dataDir, old)
		return old, nil
	}

	st := ServerPCProfileState{Version: version, Applied: true, AppliedAt: time.Now().Format(time.RFC3339)}
	st.PreviousPowerScheme = activePowerScheme()
	for _, s := range dedicatedRegSettings {
		snap := queryRegValue(s.Key, s.Name)
		snap.NewData = s.Data
		st.Registry = append(st.Registry, snap)
	}

	b, err := runHiddenOutput("powercfg.exe", "/duplicatescheme", "SCHEME_MIN")
	if err == nil {
		st.DedicatedPowerGUID = firstPowerGUID(string(b))
	}
	if st.DedicatedPowerGUID == "" {
		st.Notes = append(st.Notes, "전용 전원 계획 복제 실패: 기존 활성 전원 계획은 변경하지 않음")
	} else {
		_, _ = runHiddenOutput("powercfg.exe", "/changename", st.DedicatedPowerGUID, "Geumyi Dedicated Server", "GSC가 관리하는 24/7 서버 전원 계획")
		powerSettings := [][]string{
			{"/setacvalueindex", st.DedicatedPowerGUID, "SUB_SLEEP", "STANDBYIDLE", "0"},
			{"/setacvalueindex", st.DedicatedPowerGUID, "SUB_SLEEP", "HIBERNATEIDLE", "0"},
			{"/setacvalueindex", st.DedicatedPowerGUID, "SUB_DISK", "DISKIDLE", "0"},
			{"/setacvalueindex", st.DedicatedPowerGUID, "SUB_USB", "USBSELECTIVE", "0"},
			{"/setacvalueindex", st.DedicatedPowerGUID, "SUB_PCIEXPRESS", "ASPM", "0"},
			{"/setacvalueindex", st.DedicatedPowerGUID, "SUB_PROCESSOR", "PROCTHROTTLEMAX", "100"},
		}
		for _, a := range powerSettings {
			if out, e := runHiddenOutput("powercfg.exe", a...); e != nil {
				setupLog("server profile power warning: " + strings.Join(a, " ") + " :: " + strings.TrimSpace(string(out)))
			}
		}
		if out, e := runHiddenOutput("powercfg.exe", "/setactive", st.DedicatedPowerGUID); e != nil {
			st.Notes = append(st.Notes, "전용 전원 계획 활성화 실패: "+strings.TrimSpace(string(out)))
		}
	}

	for _, s := range dedicatedRegSettings {
		if e := setRegDWORD(s.Key, s.Name, s.Data); e != nil {
			st.Notes = append(st.Notes, e.Error())
			setupLog("server profile registry warning: " + e.Error())
		}
	}

	// Time synchronization is useful on a long-running host. Best effort only.
	_, _ = runHiddenOutput("sc.exe", "config", "w32time", "start=", "auto")
	_, _ = runHiddenOutput("sc.exe", "start", "w32time")
	_, _ = runHiddenOutput("w32tm.exe", "/resync", "/nowait")

	writeJSON(statePath, st)
	writeServerPCStatus(dataDir, st)
	setupLog("dedicated server Windows profile applied")
	return st, nil
}

func restoreDedicatedServerProfile(dataDir string) bool {
	statePath := filepath.Join(dataDir, "SystemProfile", serverProfileStateFile)
	var st ServerPCProfileState
	b, err := os.ReadFile(statePath)
	if err != nil || json.Unmarshal(b, &st) != nil || !st.Applied {
		return false
	}
	for i := len(st.Registry) - 1; i >= 0; i-- {
		restoreRegValue(st.Registry[i])
	}
	if st.PreviousPowerScheme != "" {
		_, _ = runHiddenOutput("powercfg.exe", "/setactive", st.PreviousPowerScheme)
	}
	if st.DedicatedPowerGUID != "" && !strings.EqualFold(st.DedicatedPowerGUID, st.PreviousPowerScheme) {
		_, _ = runHiddenOutput("powercfg.exe", "/delete", st.DedicatedPowerGUID)
	}
	st.Applied = false
	st.RestoredAt = time.Now().Format(time.RFC3339)
	st.Version = version
	writeJSON(statePath, st)
	writeServerPCStatus(dataDir, st)
	setupLog("dedicated server Windows profile restored")
	return true
}

func writeServerPCStatus(dataDir string, st ServerPCProfileState) {
	dir := filepath.Join(dataDir, "SystemProfile")
	_ = os.MkdirAll(dir, 0755)
	status := "Geumyi Server Center v" + version + " — Server PC Windows Profile\r\n\r\n"
	if st.Applied {
		status += "상태: 적용됨\r\n"
	} else {
		status += "상태: 원복됨\r\n"
	}
	status += "\r\n자동 관리 항목\r\n"
	status += "- 전용 High Performance 전원 계획 생성/활성화\r\n"
	status += "- AC 절전/최대 절전/디스크 절전 OFF\r\n"
	status += "- USB 선택적 절전/PCIe 링크 절전 OFF (지원되는 시스템)\r\n"
	status += "- Windows Fast Startup OFF\r\n"
	status += "- 전원 스로틀링 OFF\r\n"
	status += "- Game DVR / 화면 캡처 비활성화\r\n"
	status += "- 시스템 장애 시 자동 재부팅 ON\r\n"
	status += "- Windows Update 자동 다운로드 + 설치 알림(AUOptions=3), 로그인 중 자동 재부팅 억제\r\n"
	status += "- Windows Time 자동 시작/재동기화 요청\r\n"
	status += "- 역할 변경 시 위 변경사항 자동 원복\r\n"
	if len(st.Notes) > 0 {
		status += "\r\n주의/부분 적용\r\n- " + strings.Join(st.Notes, "\r\n- ") + "\r\n"
	}
	_ = os.WriteFile(filepath.Join(dir, "SERVER-PC-WINDOWS-STATUS.txt"), []byte(status), 0644)
}

func addMinecraftFirewallRules(cfg ServerConfig) {
	removeMinecraftFirewallRules()
	var tcp, udp []string
	for _, s := range cfg.Servers {
		if s.JavaPort > 0 {
			tcp = append(tcp, fmt.Sprint(s.JavaPort))
		}
		if s.BedrockPort > 0 {
			udp = append(udp, fmt.Sprint(s.BedrockPort))
		}
	}
	if len(tcp) > 0 {
		c := exec.Command("netsh.exe", "advfirewall", "firewall", "add", "rule", "name=Geumyi Minecraft Java", "dir=in", "action=allow", "protocol=TCP", "localport="+strings.Join(tcp, ","), "profile=any")
		hideCmd(c)
		_ = c.Run()
	}
	if len(udp) > 0 {
		c := exec.Command("netsh.exe", "advfirewall", "firewall", "add", "rule", "name=Geumyi Minecraft Bedrock", "dir=in", "action=allow", "protocol=UDP", "localport="+strings.Join(udp, ","), "profile=any")
		hideCmd(c)
		_ = c.Run()
	}
}

func removeMinecraftFirewallRules() {
	for _, name := range []string{"Geumyi Minecraft Java", "Geumyi Minecraft Bedrock"} {
		c := exec.Command("netsh.exe", "advfirewall", "firewall", "delete", "rule", "name="+name)
		hideCmd(c)
		_ = c.Run()
	}
}

func preferredLANIPv4() string {
	if x := tailscaleIPv4(); x != "" {
		return x
	}
	ifaces, _ := net.Interfaces()
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, _ := iface.Addrs()
		for _, a := range addrs {
			ip, _, e := net.ParseCIDR(a.String())
			if e != nil {
				continue
			}
			v4 := ip.To4()
			if v4 == nil {
				continue
			}
			if v4[0] == 169 && v4[1] == 254 {
				continue
			}
			if v4[0] == 10 || (v4[0] == 172 && v4[1] >= 16 && v4[1] <= 31) || (v4[0] == 192 && v4[1] == 168) || (v4[0] == 100 && v4[1] >= 64 && v4[1] <= 127) {
				return v4.String()
			}
		}
	}
	return ""
}

func writeDedicatedChecklist(dataDir string, o InstallOptions) {
	warn := ""
	if strings.Contains(strings.ToLower(o.WildPath), "onedrive") || strings.Contains(strings.ToLower(o.PlayPath), "onedrive") {
		warn = "\r\n⚠ 현재 서버 경로에 OneDrive가 포함되어 있습니다. 실제 전용 서버 PC에서는 실시간 동기화 폴더 밖(C:\\MinecraftServers 등)으로 옮기는 것을 권장합니다.\r\n"
	}
	s := "Geumyi Dedicated Server PC — 마지막 수동 점검\r\n\r\n" +
		"GSC가 자동으로 처리하지 않는 하드웨어/네트워크 항목만 남았습니다.\r\n\r\n" +
		"1. BIOS/UEFI: Restore on AC Power Loss / After Power Failure = Power On 권장\r\n" +
		"2. 공유기: 서버 PC의 LAN IP를 DHCP 예약으로 고정 권장\r\n" +
		"3. 외부 접속 사용 시: 필요한 Minecraft 포트만 공유기에서 포트포워딩\r\n" +
		"4. 원격 관리: 가능하면 Tailscale 사용. RCON(25575/25576)은 인터넷에 직접 개방하지 않기\r\n" +
		"5. Windows Update는 비활성화하지 않았습니다. 보안 업데이트는 유지하며 로그인 중 자동 재부팅만 억제합니다.\r\n" +
		"6. Microsoft Defender는 끄거나 서버 폴더를 자동 예외 처리하지 않습니다.\r\n" +
		"7. 가능하면 유선 LAN + UPS 사용 권장\r\n" + warn
	_ = os.WriteFile(filepath.Join(dataDir, "SERVER-PC-CHECKLIST.txt"), []byte(s), 0644)
}
