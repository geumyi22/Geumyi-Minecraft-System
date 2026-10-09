//go:build windows

package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type selfUpdateReport struct {
	Schema           int    `json:"schema"`
	TargetVersion    string `json:"target_version"`
	Status           string `json:"status"`
	Started          string `json:"started"`
	Finished         string `json:"finished,omitempty"`
	InstallDir       string `json:"install_dir"`
	BackupDir        string `json:"backup_dir,omitempty"`
	RolledBack       bool   `json:"rolled_back"`
	HostHealth       bool   `json:"host_health"`
	ClientRelaunched bool   `json:"client_relaunched"`
	ClientSessionID  uint32 `json:"client_session_id,omitempty"`
	ClientPID        uint32 `json:"client_pid,omitempty"`
	ClientLaunchMethod string `json:"client_launch_method,omitempty"`
	ClientRelaunchError string `json:"client_relaunch_error,omitempty"`
	Error            string `json:"error,omitempty"`
}

type selfUpdateFile struct {
	target  string
	backup  string
	existed bool
}

func selfUpdateDataDir() string {
	return filepath.Join(envOr("PROGRAMDATA", `C:\ProgramData`), "GeumyiServerCenter")
}

func selfUpdateReportPath() string {
	return filepath.Join(selfUpdateDataDir(), "Updates", "gsc-self-update-last.json")
}

func clientSelfUpdateReportPath() string {
	return filepath.Join(selfUpdateDataDir(), "Updates", "gsc-client-self-update-last.json")
}

func selfUpdateLockPath() string {
	return filepath.Join(selfUpdateDataDir(), "Updates", "gsc-self-update.lock")
}

func clientSelfUpdateLockPath() string {
	return filepath.Join(selfUpdateDataDir(), "Updates", "gsc-client-self-update.lock")
}

func writeSelfUpdateReportAt(p string, r selfUpdateReport) {
	r.Finished = time.Now().Format(time.RFC3339)
	b, _ := json.MarshalIndent(r, "", "  ")
	_ = os.MkdirAll(filepath.Dir(p), 0755)
	tmp := p + ".tmp"
	if os.WriteFile(tmp, append(b, '\n'), 0600) == nil {
		_ = os.Remove(p)
		_ = os.Rename(tmp, p)
	}
}

func writeSelfUpdateReport(r selfUpdateReport) {
	writeSelfUpdateReportAt(selfUpdateReportPath(), r)
}

func writeClientSelfUpdateReport(r selfUpdateReport) {
	writeSelfUpdateReportAt(clientSelfUpdateReportPath(), r)
}

func installedGSCDir() string {
	key := `HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\GeumyiServerCenter`
	c := exec.Command("reg.exe", "QUERY", key, "/v", "InstallLocation")
	hideCmd(c)
	if out, err := c.Output(); err == nil {
		for _, line := range strings.Split(string(out), "\n") {
			if !strings.Contains(line, "InstallLocation") || !strings.Contains(line, "REG_SZ") {
				continue
			}
			if parts := strings.SplitN(line, "REG_SZ", 2); len(parts) == 2 {
				if v := strings.TrimSpace(parts[1]); v != "" {
					return filepath.Clean(v)
				}
			}
		}
	}
	return filepath.Join(envOr("ProgramFiles", `C:\Program Files`), "Geumyi Server Center")
}

func copyFileStrict(src, dst string, mode os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	if err = os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return err
	}
	tmp := dst + ".gsc-new"
	_ = os.Remove(tmp)
	out, err := os.OpenFile(tmp, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, mode)
	if err != nil {
		return err
	}
	_, cpErr := io.Copy(out, in)
	closeErr := out.Close()
	if cpErr != nil {
		_ = os.Remove(tmp)
		return cpErr
	}
	if closeErr != nil {
		_ = os.Remove(tmp)
		return closeErr
	}
	_ = os.Remove(dst)
	if err = os.Rename(tmp, dst); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return nil
}

func writeEmbeddedStrict(name, dst string) error {
	b, err := payload.ReadFile("payload/" + name)
	if err != nil {
		return err
	}
	if len(b) < 100000 && strings.HasSuffix(strings.ToLower(name), ".exe") {
		return fmt.Errorf("embedded %s is suspiciously small", name)
	}
	if err = os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return err
	}
	tmp := dst + ".tmp"
	if err = os.WriteFile(tmp, b, 0755); err != nil {
		return err
	}
	_ = os.Remove(dst)
	if err = os.Rename(tmp, dst); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return nil
}

func processImageRunning(name string) bool {
	c := exec.Command("tasklist.exe", "/FI", "IMAGENAME eq "+name, "/NH")
	hideCmd(c)
	out, err := c.Output()
	return err == nil && strings.Contains(strings.ToLower(string(out)), strings.ToLower(name))
}

func closeGSCClientForUpdate() {
	if !processImageRunning("GeumyiServerCenter.exe") {
		return
	}
	c := exec.Command("taskkill.exe", "/IM", "GeumyiServerCenter.exe", "/T")
	hideCmd(c)
	_ = c.Run()
	for i := 0; i < 8 && processImageRunning("GeumyiServerCenter.exe"); i++ {
		time.Sleep(250 * time.Millisecond)
	}
	if processImageRunning("GeumyiServerCenter.exe") {
		c = exec.Command("taskkill.exe", "/IM", "GeumyiServerCenter.exe", "/T", "/F")
		hideCmd(c)
		_ = c.Run()
	}
}

func serviceState() string {
	c := exec.Command("sc.exe", "query", hostServiceName)
	hideCmd(c)
	out, err := c.Output()
	if err != nil {
		return "UNKNOWN"
	}
	s := strings.ToUpper(string(out))
	for _, state := range []string{"STOPPED", "RUNNING", "STOP_PENDING", "START_PENDING", "PAUSED"} {
		if strings.Contains(s, state) {
			return state
		}
	}
	return "UNKNOWN"
}

func stopHostServiceStrict() error {
	if serviceState() == "STOPPED" {
		return nil
	}
	c := exec.Command("sc.exe", "stop", hostServiceName)
	hideCmd(c)
	_, _ = c.CombinedOutput()
	deadline := time.Now().Add(25 * time.Second)
	for time.Now().Before(deadline) {
		if serviceState() == "STOPPED" {
			return nil
		}
		time.Sleep(500 * time.Millisecond)
	}
	return errors.New("GSC Host service did not stop cleanly; self-update aborted without force-killing it")
}

func startHostServiceStrict() error {
	c := exec.Command("sc.exe", "start", hostServiceName)
	hideCmd(c)
	out, err := c.CombinedOutput()
	if err != nil && !strings.Contains(strings.ToLower(string(out)), "already") {
		return fmt.Errorf("GSC Host service start failed: %w %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}

// A bare HTTP 2xx is not an update health check: an old/unrelated
// listener on 8787 could respond while the candidate Host never started.
// Require the actual GSC Host health JSON to match the requested version.
func gscHealthIsTarget(r io.Reader, expectedVersion string) bool {
	// Empty expectedVersion is ONLY used after rollback, to check that
	// a GSC v4 Host came back. The candidate commit always supplies the
	// exact intended version to avoid accepting a stale Host.
	var h struct {
		OK         bool   `json:"ok"`
		Version    string `json:"version"`
		Generation int    `json:"generation"`
		Service    bool   `json:"service"`
	}
	if err := json.NewDecoder(io.LimitReader(r, 32*1024)).Decode(&h); err != nil {
		return false
	}
	// A client process or unrelated HTTP app must not impersonate an
	// upgraded Windows Host service, even with an otherwise valid version.
	return h.OK && h.Service && h.Version != "" && h.Generation == 4 &&
		(expectedVersion == "" || h.Version == expectedVersion)
}

func waitGSCHealth(timeout time.Duration, expectedVersion string) bool {
	client := &http.Client{Timeout: 1500 * time.Millisecond}
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		resp, err := client.Get("http://127.0.0.1:8787/api/health")
		if err == nil {
			verified := resp.StatusCode == http.StatusOK && gscHealthIsTarget(resp.Body, expectedVersion)
			_ = resp.Body.Close()
			if verified {
				return true
			}
		}
		time.Sleep(750 * time.Millisecond)
	}
	return false
}

func backupSelfUpdateFile(target, backupDir string) (selfUpdateFile, error) {
	f := selfUpdateFile{target: target, backup: filepath.Join(backupDir, filepath.Base(target))}
	st, err := os.Stat(target)
	if os.IsNotExist(err) {
		return f, nil
	}
	if err != nil || st.IsDir() {
		if err == nil {
			err = fmt.Errorf("target is a directory: %s", target)
		}
		return f, err
	}
	f.existed = true
	if err = copyFileStrict(target, f.backup, 0755); err != nil {
		return f, err
	}
	return f, nil
}

// A rollback must NOT be reported successful when even one old executable
// could not be restored. Always attempt all targets; return a bounded,
// path-free error so reports do not disclose installation locations.
func restoreSelfUpdateFiles(files []selfUpdateFile) error {
	failed := false
	for _, f := range files {
		if f.existed {
			if err := copyFileStrict(f.backup, f.target, 0755); err != nil {
				failed = true
			}
		} else {
			if err := os.Remove(f.target); err != nil && !errors.Is(err, os.ErrNotExist) {
				failed = true
			}
		}
	}
	if failed {
		return errors.New("one or more GSC files could not be restored")
	}
	return nil
}

// Every path the self-update helper may replace or create belongs in the
// backup/rollback ledger, including a previously absent Setup.exe. The
// absent path gets selfUpdateFile.existed=false so rollback deletes it.
func selfUpdateTargetPaths(hostExists, clientExists bool, hostTarget, clientTarget, setupTarget string) []string {
	targets := make([]string, 0, 3)
	if hostExists {
		targets = append(targets, hostTarget)
	}
	if clientExists {
		targets = append(targets, clientTarget)
	}
	return append(targets, setupTarget)
}

func relaunchSelfUpdateClient(report *selfUpdateReport, clientTarget string) {
	launch, err := launchClientInInteractiveSession(clientTarget)
	if err != nil {
		report.ClientRelaunched = false
		report.ClientRelaunchError = err.Error()
		setupLog("self-update client relaunch failed: " + err.Error())
		return
	}
	report.ClientRelaunched = true
	report.ClientSessionID = launch.SessionID
	report.ClientPID = launch.PID
	report.ClientLaunchMethod = launch.Method
	setupLog(fmt.Sprintf("self-update client relaunched: session=%d pid=%d method=%s", launch.SessionID, launch.PID, launch.Method))
}

func runSelfUpdateMode() {
	runSelfUpdateModeScoped(false)
}

func runClientSelfUpdateMode() {
	runSelfUpdateModeScoped(true)
}

func runSelfUpdateModeScoped(clientOnly bool) {
	report := selfUpdateReport{
		Schema: 1,
		TargetVersion: version,
		Status: "running",
		Started: time.Now().Format(time.RFC3339),
	}
	defer func() {
		if clientOnly {
			_ = os.Remove(clientSelfUpdateLockPath())
			writeClientSelfUpdateReport(report)
		} else {
			_ = os.Remove(selfUpdateLockPath())
			writeSelfUpdateReport(report)
		}
	}()
	// Give the API response that launched this helper time to leave the old Host.
	time.Sleep(1500 * time.Millisecond)

	dataDir := selfUpdateDataDir()
	installDir := installedGSCDir()
	report.InstallDir = installDir
	hostTarget := filepath.Join(installDir, "GeumyiServerHost.exe")
	clientTarget := filepath.Join(installDir, "GeumyiServerCenter.exe")
	setupTarget := filepath.Join(installDir, "GeumyiServerCenter-Setup.exe")
	hostExists := false
	clientExists := false
	if !clientOnly {
		if st, err := os.Stat(hostTarget); err == nil && !st.IsDir() {
			hostExists = true
		}
	}
	if st, err := os.Stat(clientTarget); err == nil && !st.IsDir() {
		clientExists = true
	}
	if clientOnly && !clientExists {
		report.Status = "failed"
		report.Error = "installed GSC Client binary was not found"
		setupLog("client self-update failed: " + report.Error)
		return
	}
	if !clientOnly && !hostExists && !clientExists {
		report.Status = "failed"
		report.Error = "installed GSC Host/Client binaries were not found"
		setupLog("self-update failed: " + report.Error)
		return
	}

	clientWasRunning := clientExists && processImageRunning("GeumyiServerCenter.exe")
	stamp := time.Now().Format("20060102-150405")
	backupDir := filepath.Join(dataDir, "Backups", "Day11-GSCSelfUpdate-"+stamp)
	report.BackupDir = backupDir
	if err := os.MkdirAll(backupDir, 0700); err != nil {
		report.Status = "failed"
		report.Error = err.Error()
		return
	}

	// Include Setup even when it does not exist yet. The helper may create
	// GeumyiServerCenter-Setup.exe during replacement; a failed update must
	// remove that newly introduced binary, not leave an untracked RC behind.
	targets := selfUpdateTargetPaths(hostExists, clientExists, hostTarget, clientTarget, setupTarget)
	files := make([]selfUpdateFile, 0, len(targets))
	for _, p := range targets {
		f, err := backupSelfUpdateFile(p, backupDir)
		if err != nil {
			report.Status = "failed"
			report.Error = "GSC-only backup failed: " + err.Error()
			return
		}
		files = append(files, f)
	}
	if !clientOnly {
		if b, err := os.ReadFile(filepath.Join(dataDir, "server.json")); err == nil {
			_ = os.WriteFile(filepath.Join(backupDir, "server.json"), b, 0600)
		}
	}

	stageDir := filepath.Join(dataDir, "Staging", "GSC", "helper-"+stamp)
	if err := os.MkdirAll(stageDir, 0700); err != nil {
		report.Status = "failed"
		report.Error = err.Error()
		return
	}
	defer os.RemoveAll(stageDir)
	newHost := filepath.Join(stageDir, "GeumyiServerHost.exe")
	newClient := filepath.Join(stageDir, "GeumyiServerCenter.exe")
	if hostExists {
		if err := writeEmbeddedStrict("GeumyiServerHost.exe", newHost); err != nil {
			report.Status = "failed"
			report.Error = "embedded Host extraction failed: " + err.Error()
			return
		}
	}
	if clientExists {
		if err := writeEmbeddedStrict("GeumyiServerCenter.exe", newClient); err != nil {
			report.Status = "failed"
			report.Error = "embedded Client extraction failed: " + err.Error()
			return
		}
	}

	closeGSCClientForUpdate()
	if hostExists {
		if err := stopHostServiceStrict(); err != nil {
			report.Status = "failed"
			report.Error = err.Error()
			if clientWasRunning {
				relaunchSelfUpdateClient(&report, clientTarget)
			}
			return
		}
	}

	rollback := func(reason error) {
		if hostExists {
			_ = stopHostServiceStrict()
		}
		restoreErr := restoreSelfUpdateFiles(files)
		report.RolledBack = restoreErr == nil
		report.Status = "rolled_back"
		report.Error = reason.Error()
		if restoreErr != nil {
			report.Status = "rollback_failed"
			report.Error += "; " + restoreErr.Error()
		}
		if hostExists && restoreErr == nil {
			if err := startHostServiceStrict(); err != nil {
				report.RolledBack = false
				report.Status = "rollback_failed"
				report.Error += "; old Host service restart failed"
			} else {
				report.HostHealth = waitGSCHealth(30 * time.Second, "")
				if !report.HostHealth {
					report.RolledBack = false
					report.Status = "rollback_failed"
					report.Error += "; restored Host health not verified"
				}
			}
		}
		if clientWasRunning && restoreErr == nil {
			relaunchSelfUpdateClient(&report, clientTarget)
		}
	}

	if hostExists {
		if err := copyFileStrict(newHost, hostTarget, 0755); err != nil {
			rollback(fmt.Errorf("Host replacement failed: %w", err))
			return
		}
	}
	if clientExists {
		if err := copyFileStrict(newClient, clientTarget, 0755); err != nil {
			rollback(fmt.Errorf("Client replacement failed: %w", err))
			return
		}
	}
	if self, err := os.Executable(); err == nil {
		if err = copyFileStrict(self, setupTarget, 0755); err != nil {
			rollback(fmt.Errorf("Setup replacement failed: %w", err))
			return
		}
	}

	if hostExists {
		if err := startHostServiceStrict(); err != nil {
			rollback(err)
			return
		}
		if !waitGSCHealth(35 * time.Second, version) {
			rollback(errors.New("GSC "+version+" health gate timed out"))
			return
		}
		report.HostHealth = true
	}
	if clientWasRunning {
		relaunchSelfUpdateClient(&report, clientTarget)
	}
	report.Status = "success"
	if clientOnly {
		setupLog("client-only self-update success: target=" + version + " backup=" + backupDir + " host_touched=false")
	} else {
		setupLog("self-update success: target=" + version + " backup=" + backupDir)
	}
}
