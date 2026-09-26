//go:build windows

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"
)

var clientExiting atomic.Bool

var (
	browserPIDMu sync.Mutex
	browserPIDs  = map[int]struct{}{}
)

func clientConfigSnapshot() ClientConfig {
	clientConfigMu.RLock()
	defer clientConfigMu.RUnlock()
	return cfg
}
func setClientConfigLocked(c ClientConfig) { cfg = c }
func browserProfile() string               { return filepath.Join(filepath.Dir(cfgPath), "DashboardProfile") }
func hiddenClientCommand(c *exec.Cmd) {
	c.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000}
}

// trackDashboardBrowser remembers every Edge root process started by this client.
// Chromium may replace its original root process, so shutdown also matches the
// isolated --user-data-dir and local --app URL as a fallback.
func trackDashboardBrowser(pid int) {
	if pid <= 0 {
		return
	}
	browserPIDMu.Lock()
	browserPIDs[pid] = struct{}{}
	browserPIDMu.Unlock()
}

func dashboardBrowserPIDs() []int {
	browserPIDMu.Lock()
	defer browserPIDMu.Unlock()
	out := make([]int, 0, len(browserPIDs))
	for pid := range browserPIDs {
		out = append(out, pid)
	}
	sort.Ints(out)
	return out
}

func runHostTask() error {
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	c := exec.CommandContext(ctx, "sc.exe", "start", "Geumyi Server Center Host")
	hiddenClientCommand(c)
	if err := c.Run(); err == nil {
		return nil
	}
	// v3 migration fallback until the v4 installer converts the Host task to a service.
	c = exec.CommandContext(ctx, "schtasks.exe", "/Run", "/TN", "Geumyi Server Center Host")
	hiddenClientCommand(c)
	return c.Run()
}
func ensureLocalHost() {
	c := clientConfigSnapshot()
	u, e := url.Parse(c.HostURL)
	if e != nil {
		return
	}
	host := u.Hostname()
	ip := net.ParseIP(host)
	if !strings.EqualFold(host, "localhost") && (ip == nil || !ip.IsLoopback()) {
		return
	}
	h := http.Client{Timeout: 2 * time.Second}
	r, e := h.Get(c.HostURL + "/api/health")
	if e == nil {
		r.Body.Close()
		return
	}
	if clientExiting.Load() {
		return
	}
	if runHostTask() != nil {
		exe, e := os.Executable()
		if e != nil {
			return
		}
		// Only the task-start helper elevates; the dashboard keeps the user's profile.
		pShellExecute.Call(0, uintptr(unsafe.Pointer(wptr("runas"))), uintptr(unsafe.Pointer(wptr(exe))), uintptr(unsafe.Pointer(wptr("--start-host"))), 0, 0)
	}
}

func beginClientShutdown() {
	if !clientExiting.CompareAndSwap(false, true) {
		return
	}
	showBalloon("전체 종료", "서버 저장이 끝나면 관리창을 먼저 닫고 Agent와 Host까지 종료합니다.", false)
	go func() {
		if _, e := hostRequest("POST", "/api/shutdown", "{}"); e != nil {
			shutdownClientFailed(e)
			return
		}
		deadline := time.Now().Add(420 * time.Second)
		for time.Now().Before(deadline) {
			b, e := hostRequest("GET", "/api/shutdown/status", "")
			if e != nil {
				shutdownClientFailed(e)
				return
			}
			var s struct {
				Phase, Message string
				Errors         []string
			}
			if e = json.Unmarshal(b, &s); e != nil {
				shutdownClientFailed(e)
				return
			}
			switch s.Phase {
			case "failed":
				shutdownClientFailed(fmt.Errorf("%s: %s", s.Message, strings.Join(s.Errors, "; ")))
				return
			case "ready":
				// Close the UI while the local/remote Host is still alive. This prevents
				// a surviving Edge app window from falling through to its network-error
				// page after Host/Client shutdown.
				if e = closeDashboardBrowsers(); e != nil {
					shutdownClientFailed(e)
					return
				}
				if _, e = hostRequest("POST", "/api/shutdown/finish", "{}"); e != nil {
					shutdownClientFailed(e)
					return
				}
				requestClientQuit()
				return
			}
			time.Sleep(time.Second)
		}
		shutdownClientFailed(fmt.Errorf("종료 확인 시간이 초과되었습니다. 실행 로그를 확인해 주세요"))
	}()
}
func shutdownClientFailed(e error) {
	clientExiting.Store(false)
	showBalloon("전체 종료 미완료", e.Error(), true)
}

func psQuote(s string) string { return strings.ReplaceAll(s, "'", "''") }

func closeDashboardBrowsers() error {
	profile := psQuote(browserProfile())
	pids := dashboardBrowserPIDs()
	pidText := ""
	for i, pid := range pids {
		if i > 0 {
			pidText += ","
		}
		pidText += fmt.Sprintf("%d", pid)
	}
	// Kill only Edge processes belonging to the isolated GSC profile or roots
	// launched by this client. Never use taskkill /IM msedge.exe.
	ps := fmt.Sprintf(`$ErrorActionPreference='SilentlyContinue';
$profile='%s';$roots=@(%s);$app='--app=http://127.0.0.1:%d';
function Get-GSCTargets {
  @(Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | Where-Object {
    $cl=$_.CommandLine;
    ($roots -contains [int]$_.ProcessId) -or
    ($cl -and $cl.IndexOf('--user-data-dir='+$profile,[StringComparison]::OrdinalIgnoreCase) -ge 0) -or
    ($cl -and $cl.IndexOf('--user-data-dir="'+$profile+'"',[StringComparison]::OrdinalIgnoreCase) -ge 0) -or
    ($cl -and $cl.IndexOf($app,[StringComparison]::OrdinalIgnoreCase) -ge 0)
  })
}
$targets=@(Get-GSCTargets);
foreach($p in $targets){try{$gp=Get-Process -Id $p.ProcessId -ErrorAction Stop;if($gp.MainWindowHandle -ne 0){$null=$gp.CloseMainWindow()}}catch{}}
Start-Sleep -Milliseconds 700;
$targets=@(Get-GSCTargets);
foreach($p in $targets){& taskkill.exe /PID $p.ProcessId /T /F 1>$null 2>$null}
$until=(Get-Date).AddSeconds(5);
do { if(@(Get-GSCTargets).Count -eq 0){exit 0}; Start-Sleep -Milliseconds 120 } while((Get-Date) -lt $until);
exit 17`, profile, pidText, localPort)
	ctx, cancel := context.WithTimeout(context.Background(), 9*time.Second)
	defer cancel()
	c := exec.CommandContext(ctx, "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", ps)
	hiddenClientCommand(c)
	if out, e := c.CombinedOutput(); e != nil {
		if ctx.Err() != nil {
			return fmt.Errorf("관리창 종료 시간이 초과되었습니다")
		}
		msg := strings.TrimSpace(string(out))
		if msg != "" {
			return fmt.Errorf("관리창 종료 실패: %s", msg)
		}
		return fmt.Errorf("관리창 종료 실패: %w", e)
	}
	return nil
}

func requestClientQuit() {
	clientExiting.Store(true)
	// PostQuitMessage must run on the tray thread, not a worker goroutine.
	pPostMessage.Call(mainHWND, WM_APP+2, 0, 0)
}

func closeClientWindows() {
	if !clientExiting.CompareAndSwap(false, true) {
		return
	}
	if e := closeDashboardBrowsers(); e != nil {
		clientExiting.Store(false)
		showBalloon("관리창 종료 실패", e.Error(), true)
		return
	}
	requestClientQuit()
}

func shutdownClientRuntime() {
	// The dashboard process is already gone when this runs. Only now close the
	// loopback HTTP server, so no surviving app window can render a connection
	// error while shutdown is in progress.
	if clientHTTPServer != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		_ = clientHTTPServer.Shutdown(ctx)
		cancel()
	}
	if clientProxyTransport != nil {
		clientProxyTransport.CloseIdleConnections()
	}
}
