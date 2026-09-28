//go:build windows

package main

import (
	"crypto/rand"
	"embed"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"geumyi/servercenter/internal/javaruntime"
	"geumyi/servercenter/internal/securestore"
	"io"
	"io/fs"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

const version = "4.2.3"
const hostTaskName = "Geumyi Server Center Host"
const hostServiceName = "Geumyi Server Center Host"

//go:embed payload/* installer.html
var payload embed.FS

//go:embed installer.html
var installerHTML string

type AgentConfig struct {
	HealthURL    string `json:"health_url"`
	StateURL     string `json:"state_url"`
	StartCommand string `json:"start_command"`
	WorkingDir   string `json:"working_dir"`
	JavaPath     string `json:"java_path"`
	JarName      string `json:"jar_name"`
}
type UpdateConfig struct {
	Enabled        bool   `json:"enabled"`
	Repository     string `json:"repository"`
	Channel        string `json:"channel"`
	PublicKeyPath  string `json:"public_key_path"`
	TimeoutSeconds int    `json:"timeout_seconds"`
}
type ServerConfig struct {
	Bind                string      `json:"bind"`
	Port                int         `json:"port"`
	APIToken            string      `json:"api_token"`
	AllowLoopbackNoAuth bool        `json:"allow_loopback_no_auth"`
	MobileEnabled       bool        `json:"mobile_enabled"`
	PairingTTLSeconds   int         `json:"pairing_ttl_seconds"`
	AutoStartAgent      bool         `json:"auto_start_agent"`
	Agent               AgentConfig  `json:"agent"`
	Update              UpdateConfig `json:"update"`
	Servers             []Server     `json:"servers"`
}
type Server struct {
	ID             string `json:"id"`
	Name           string `json:"name"`
	JavaPort       int    `json:"java_port"`
	RCONPort       int    `json:"rcon_port"`
	BedrockPort    int    `json:"bedrock_port"`
	GDSAPIPort     int    `json:"gds_api_port"`
	Path           string `json:"path"`
	PathFile       string `json:"path_file"`
	StartCommand   string `json:"start_command"`
	AutoStart      bool   `json:"auto_start"`
	RestartOnCrash bool   `json:"restart_on_crash"`
}
type ClientConfig struct {
	HostURL string `json:"host_url"`
	Token   string `json:"token"`
}
type InstallOptions struct {
	Role              int    `json:"role"`
	InstallDir        string `json:"install_dir"`
	AutoStartClient   bool   `json:"autostart_client"`
	Remote            bool   `json:"remote"`
	DedicatedOptimize bool   `json:"dedicated_optimize"`
	WildPath          string `json:"wild_path"`
	PlayPath          string `json:"play_path"`
	HostURL           string `json:"host_url"`
	Token             string `json:"token"`
}
type ProgressState struct {
	Percent int    `json:"percent"`
	Status  string `json:"status"`
	Error   string `json:"error,omitempty"`
	Done    bool   `json:"done"`
	Started bool   `json:"started"`
}

var (
	shell32             = syscall.NewLazyDLL("shell32.dll")
	pShellExecute       = shell32.NewProc("ShellExecuteW")
	progressMu          sync.RWMutex
	installMu           sync.Mutex
	prog                = ProgressState{Status: "대기 중"}
	current             InstallOptions
	installing          bool
	installerProc       *os.Process
	installerProfileDir string
)

func wptr(s string) *uint16 { p, _ := syscall.UTF16PtrFromString(s); return p }
func hideCmd(c *exec.Cmd) {
	c.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000}
}

func main() {
	if hasArg("/uninstall") || hasArg("--uninstall") {
		if !isAdmin() {
			elevate("/uninstall")
			return
		}
		runUninstall()
		return
	}
	if !isAdmin() && !hasArg("--elevated") {
		elevate("--elevated")
		return
	}
	runWizard()
}
func hasArg(v string) bool {
	for _, a := range os.Args[1:] {
		if strings.EqualFold(a, v) {
			return true
		}
	}
	return false
}
func elevate(args string) {
	self, _ := os.Executable()
	r, _, _ := pShellExecute.Call(0, uintptr(unsafe.Pointer(wptr("runas"))), uintptr(unsafe.Pointer(wptr(self))), uintptr(unsafe.Pointer(wptr(args))), 0, 1)
	if r <= 32 {
		_ = exec.Command("rundll32.exe", "user32.dll,MessageBeep").Start()
	}
}

func runWizard() {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return
	}
	addr := "http://" + ln.Addr().String()
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = io.WriteString(w, installerHTML)
	})
	mux.HandleFunc("/app.ico", serveIcon)
	mux.HandleFunc("/api/discover", apiDiscover)
	mux.HandleFunc("/api/pick-folder", apiPickFolder)
	mux.HandleFunc("/api/install", apiInstall)
	mux.HandleFunc("/api/progress", apiProgress)
	mux.HandleFunc("/api/finish", apiFinish)
	mux.HandleFunc("/api/exit", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(204)
		go func() { time.Sleep(200 * time.Millisecond); os.Exit(0) }()
	})
	srv := &http.Server{Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	go srv.Serve(ln)
	openInstallerWindow(addr)
	select {}
}
func serveIcon(w http.ResponseWriter, r *http.Request) {
	b, e := fs.ReadFile(payload, "payload/GeumyiServerCenter.ico")
	if e != nil {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "image/x-icon")
	_, _ = w.Write(b)
}
func apiDiscover(w http.ResponseWriter, r *http.Request) {
	pd := envOr("PROGRAMDATA", `C:\ProgramData`)
	installDir := filepath.Join(envOr("ProgramFiles", `C:\Program Files`), "Geumyi Server Center")
	dataDir := filepath.Join(pd, "GeumyiServerCenter")
	cdir := filepath.Join(envOr("APPDATA", envOr("LOCALAPPDATA", ".")), "GeumyiServerCenter")
	existingClient := readExistingClientConfig(filepath.Join(cdir, "client.json"))
	d := map[string]any{"install_dir": installDir, "wild_path": discoverServerPath(25565, `C:\ProgramData\MinecraftServer\server_path.txt`), "play_path": discoverServerPath(25566, `C:\ProgramData\MinecraftPlaygroundServer\server_path.txt`), "data_dir": dataDir, "existing_role": detectInstalledRole(dataDir, installDir), "existing_client_host_url": existingClient.HostURL, "existing_client_token": existingClient.Token != ""}
	writeHTTPJSON(w, d)
}
func apiInstall(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "POST required", 405)
		return
	}
	var o InstallOptions
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&o); err != nil {
		setupLog("install request decode failed: " + err.Error())
		http.Error(w, "잘못된 설치 옵션", 400)
		return
	}
	if o.InstallDir == "" {
		o.InstallDir = filepath.Join(envOr("ProgramFiles", `C:\Program Files`), "Geumyi Server Center")
	}
	if o.Role < 1 || o.Role > 3 {
		http.Error(w, "설치 유형 오류", 400)
		return
	}

	installMu.Lock()
	if installing {
		installMu.Unlock()
		http.Error(w, "이미 설치 중입니다", 409)
		return
	}
	installing = true
	current = o
	progressMu.Lock()
	prog = ProgressState{Percent: 1, Status: "설치 요청 접수됨...", Started: true}
	progressMu.Unlock()
	installMu.Unlock()
	setupLog("install request accepted")

	// 먼저 브라우저에 202 응답을 확실히 보내고, 실제 설치는 약간 뒤에 시작한다.
	// 이렇게 하면 파일/작업 스케줄러 작업이 느려도 설치 UI가 '준비 중'에서 멈춰 보이지 않는다.
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(http.StatusAccepted)
	_ = json.NewEncoder(w).Encode(map[string]any{"ok": true, "accepted": true})
	if f, ok := w.(http.Flusher); ok {
		f.Flush()
	}
	go func(opt InstallOptions) {
		time.Sleep(120 * time.Millisecond)
		doInstall(opt)
	}(o)
}
func apiProgress(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store, no-cache, must-revalidate")
	progressMu.RLock()
	p := prog
	progressMu.RUnlock()
	writeHTTPJSON(w, p)
}
func apiFinish(w http.ResponseWriter, r *http.Request) {
	var q struct {
		Launch bool `json:"launch"`
	}
	_ = json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q)
	if q.Launch {
		if current.Role == 1 {
			_ = exec.Command("rundll32.exe", "url.dll,FileProtocolHandler", "http://127.0.0.1:8787").Start()
		} else {
			launchInstalled(current.InstallDir)
		}
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = io.WriteString(w, `{"ok":true,"closing":true}`)
	if f, ok := w.(http.Flusher); ok {
		f.Flush()
	}
	go func() {
		time.Sleep(350 * time.Millisecond)
		closeInstallerBrowser()
		time.Sleep(120 * time.Millisecond)
		os.Exit(0)
	}()
}

// closeInstallerBrowser closes only the dedicated Edge app instance used by
// Setup. Edge can detach the visible app window from the launcher PID, so we
// terminate both the original process tree and any msedge.exe process that is
// using Setup's unique --user-data-dir. The user's normal Edge profile is not touched.
func closeInstallerBrowser() {
	if installerProc != nil {
		c := exec.Command("taskkill.exe", "/PID", strconv.Itoa(installerProc.Pid), "/T", "/F")
		hideCmd(c)
		_ = c.Run()
	}
	if installerProfileDir != "" {
		ps := `$ErrorActionPreference='SilentlyContinue'; $needle='` + psQuote(installerProfileDir) + `'; Get-CimInstance Win32_Process | Where-Object { $_.Name -ieq 'msedge.exe' -and $_.CommandLine -and $_.CommandLine.Contains($needle) } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }`
		c := exec.Command("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps)
		hideCmd(c)
		_ = c.Run()
		_ = os.RemoveAll(installerProfileDir)
	}
}
func writeHTTPJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	_ = json.NewEncoder(w).Encode(v)
}
func setProgress(p int, status, errText string) {
	progressMu.Lock()
	prog.Percent = p
	prog.Status = status
	prog.Error = errText
	prog.Started = true
	prog.Done = false
	progressMu.Unlock()
}
func finishInstall(err error) {
	progressMu.Lock()
	prog.Done = true
	if err != nil {
		prog.Error = err.Error()
		prog.Status = "설치 실패"
	} else {
		prog.Percent = 100
		prog.Status = "설치 완료"
	}
	progressMu.Unlock()
	installMu.Lock()
	installing = false
	installMu.Unlock()
}
func openInstallerWindow(u string) {
	// Use a dedicated browser profile so the installer window owns its own
	// browser process. This lets the Finish button close only the installer
	// window instead of touching the user's normal Edge session.
	installerProfileDir = filepath.Join(os.TempDir(), fmt.Sprintf("GeumyiServerCenter-Installer-%d", os.Getpid()))
	_ = os.MkdirAll(installerProfileDir, 0700)
	candidates := []string{
		filepath.Join(os.Getenv("ProgramFiles(x86)"), "Microsoft", "Edge", "Application", "msedge.exe"),
		filepath.Join(os.Getenv("ProgramFiles"), "Microsoft", "Edge", "Application", "msedge.exe"),
		filepath.Join(os.Getenv("LOCALAPPDATA"), "Microsoft", "Edge", "Application", "msedge.exe"),
	}
	for _, p := range candidates {
		if p == "" {
			continue
		}
		if _, e := os.Stat(p); e != nil {
			continue
		}
		c := exec.Command(p,
			"--user-data-dir="+installerProfileDir,
			"--no-first-run", "--no-default-browser-check", "--disable-background-mode",
			"--app="+u, "--window-size=1180,800", "--disable-features=msEdgeSidebarV2")
		if c.Start() == nil {
			installerProc = c.Process
		}
		return
	}
	// Windows 11 ships with Edge, so this is only an emergency fallback.
	// The setup process itself still terminates on Finish even if a generic
	// browser tab cannot be programmatically closed safely.
	_ = exec.Command("rundll32.exe", "url.dll,FileProtocolHandler", u).Start()
}

func doInstall(o InstallOptions) {
	setupLog("v" + version + " install start")
	defer func() {
		if r := recover(); r != nil {
			setupLog(fmt.Sprintf("panic: %v", r))
			finishInstall(fmt.Errorf("%v", r))
		}
	}()
	pd := envOr("PROGRAMDATA", `C:\ProgramData`)
	dataDir := filepath.Join(pd, "GeumyiServerCenter")
	_ = os.MkdirAll(dataDir, 0755)
	oldRole := detectInstalledRole(dataDir, o.InstallDir)
	setupLog(fmt.Sprintf("role transition: %s(%d) -> %s(%d)", roleName(oldRole), oldRole, roleName(o.Role), o.Role))

	if o.Role != 2 {
		setProgress(3, "서버 폴더 확인 중...", "")
		if !validServerDir(o.WildPath, 25565) {
			finishInstall(fmt.Errorf("야생 서버 폴더를 확인하지 못했습니다: %s", o.WildPath))
			return
		}
		if !validServerDir(o.PlayPath, 25566) {
			finishInstall(fmt.Errorf("놀이터 서버 폴더를 확인하지 못했습니다: %s", o.PlayPath))
			return
		}
	}

	// Server -> client-only is destructive to the running role, so drain the
	// Minecraft servers first. Never force-kill Java during a role transition.
	if hasServerRole(oldRole) && o.Role == 2 {
		backupLegacyTasks(dataDir)
		if data, e := os.ReadFile(filepath.Join(dataDir, "server.json")); e == nil {
			backupDir := filepath.Join(dataDir, "Backup")
			_ = os.MkdirAll(backupDir, 0755)
			_ = os.WriteFile(filepath.Join(backupDir, "server-before-client-role-"+time.Now().Format("20060102-150405")+".json"), data, 0600)
		}
		setProgress(5, "기존 서버를 저장하고 정상 종료하는 중...", "")
		if err := gracefulHostShutdownForTransition(); err != nil {
			finishInstall(err)
			return
		}
	}

	setProgress(8, "기존 Server Center 구성 정리 중...", "")
	prepareForUpgradeAll()

	// A dedicated Windows profile belongs only to the dedicated Server PC role.
	// Switching to Client-only or Both restores the user's previous Windows settings.
	if o.Role != 1 || !o.DedicatedOptimize {
		if restoreDedicatedServerProfile(dataDir) {
			setupLog("role transition restored dedicated Windows profile")
		}
	}

	// Remove role-exclusive components before adding the target role components.
	if o.Role == 1 {
		removeClientComponent(o.InstallDir)
	} else if o.Role == 2 {
		removeServerComponent(o.InstallDir, dataDir)
	}

	_ = os.MkdirAll(o.InstallDir, 0755)
	setProgress(18, "Geumyi Server Center v4 프로그램 설치 중...", "")
	mustExtract("payload/GeumyiServerCenter.ico", filepath.Join(o.InstallDir, "GeumyiServerCenter.ico"))
	mustExtract("payload/README-v4.2.3.txt", filepath.Join(o.InstallDir, "README-v4.2.3.txt"))
	if hasClientRole(o.Role) {
		mustExtract("payload/GeumyiServerCenter.exe", filepath.Join(o.InstallDir, "GeumyiServerCenter.exe"))
	}
	if hasServerRole(o.Role) {
		mustExtract("payload/GeumyiServerHost.exe", filepath.Join(o.InstallDir, "GeumyiServerHost.exe"))
	}
	if self, e := os.Executable(); e == nil {
		copyFile(self, filepath.Join(o.InstallDir, "GeumyiServerCenter-Setup.exe"))
	}

	existing := readExistingServerConfig(filepath.Join(dataDir, "server.json"))
	token := existing.APIToken
	if token == "" {
		token = randomToken()
	}
	hostURL := "http://127.0.0.1:8787"
	var cfg ServerConfig
	if hasServerRole(o.Role) {
		setProgress(31, "Discord / GDS Agent 설치 및 서버 구성 중...", "")
		agentDir := filepath.Join(dataDir, "Runtime", "Agent")
		installIntegratedAgent(agentDir)
		installManagedPlugins(dataDir)
		java := findJavaExecutable()
		cfg = ServerConfig{Bind: "127.0.0.1", Port: 8787, APIToken: token, AllowLoopbackNoAuth: true, MobileEnabled: o.Remote, PairingTTLSeconds: 300, AutoStartAgent: true, Agent: AgentConfig{HealthURL: "http://127.0.0.1:8877/health", StateURL: "http://127.0.0.1:8877/state", WorkingDir: agentDir, JavaPath: java, JarName: "GeumyiStatusAgent-0.5.4.jar"}, Update: defaultUpdateConfig(dataDir), Servers: []Server{{ID: "wild", Name: "금이 야생", JavaPort: 25565, RCONPort: 25575, BedrockPort: 19132, GDSAPIPort: 8766, Path: o.WildPath, PathFile: `C:\ProgramData\MinecraftServer\server_path.txt`, StartCommand: "start.bat", AutoStart: true, RestartOnCrash: true}, {ID: "playground", Name: "금이 놀이터", JavaPort: 25566, RCONPort: 25576, BedrockPort: 19133, GDSAPIPort: 8765, Path: o.PlayPath, PathFile: `C:\ProgramData\MinecraftPlaygroundServer\server_path.txt`, StartCommand: "start.bat", AutoStart: true, RestartOnCrash: true}}}
		if len(existing.Servers) > 0 {
			previous := existing
			previous.Servers = append([]Server(nil), existing.Servers...)
			for i := range previous.Servers {
				switch previous.Servers[i].ID {
				case "wild":
					previous.Servers[i].Path = o.WildPath
				case "playground":
					previous.Servers[i].Path = o.PlayPath
				}
			}
			previous.Agent.JavaPath = java
			previous.Agent.WorkingDir = agentDir
			previous.Agent.JarName = "GeumyiStatusAgent-0.5.4.jar"
			if previous.Port == 0 {
				previous.Port = 8787
			}
			previous.Bind = "127.0.0.1"
			previous.MobileEnabled = o.Remote
			if previous.PairingTTLSeconds < 60 || previous.PairingTTLSeconds > 3600 {
				previous.PairingTTLSeconds = 300
			}
			cfg = previous
			cfg.APIToken = token
		}
		cfgFile := filepath.Join(dataDir, "server.json")
		if data, e := os.ReadFile(cfgFile); e == nil {
			backupDir := filepath.Join(dataDir, "Backup")
			_ = os.MkdirAll(backupDir, 0755)
			if e = os.WriteFile(filepath.Join(backupDir, "server-before-v4.2.3-"+time.Now().Format("20060102-150405")+".json"), data, 0600); e != nil {
				finishInstall(e)
				return
			}
		}
		cfg.MobileEnabled = o.Remote
		if cfg.PairingTTLSeconds < 60 || cfg.PairingTTLSeconds > 3600 {
			cfg.PairingTTLSeconds = 300
		}
		cfg.Update = normalizeUpdateConfig(cfg.Update, dataDir)
		hostURL = fmt.Sprintf("http://127.0.0.1:%d", cfg.Port)
		writeServerConfig(filepath.Join(dataDir, "server.json"), cfg)

		setProgress(45, "방화벽 · Windows Service · 자동 복구 구성 중...", "")
		backupLegacyTasks(dataDir)
		deleteLegacyTasks()
		if e := createHostService(filepath.Join(o.InstallDir, "GeumyiServerHost.exe"), filepath.Join(dataDir, "server.json")); e != nil {
			finishInstall(e)
			return
		}
		if cfg.MobileEnabled {
			addFirewallRule()
		} else {
			removeFirewallRule()
		}
		addMinecraftFirewallRules(cfg)
		writePairingFile(dataDir, token)

		if o.Role == 1 && o.DedicatedOptimize {
			setProgress(58, "전용 서버 PC Windows 설정 최적화 중...", "")
			if _, e := applyDedicatedServerProfile(dataDir); e != nil {
				finishInstall(fmt.Errorf("전용 서버 Windows 설정 적용 실패: %w", e))
				return
			}
			writeDedicatedChecklist(dataDir, o)
		} else if o.Role == 1 {
			writeDedicatedChecklist(dataDir, o)
		}

		// Host owns Agent/server startup, avoiding installer/Host launch races.
		if e := startHostService(); e != nil {
			finishInstall(fmt.Errorf("Host 서비스 시작 실패: %w", e))
			return
		}
	}

	if o.Role == 2 {
		cdir := filepath.Join(envOr("APPDATA", envOr("LOCALAPPDATA", ".")), "GeumyiServerCenter")
		oldClient := readExistingClientConfig(filepath.Join(cdir, "client.json"))
		hostURL = strings.TrimRight(strings.TrimSpace(o.HostURL), "/")
		token = strings.TrimSpace(o.Token)
		if hostURL == "" {
			hostURL = oldClient.HostURL
		}
		if token == "" {
			token = oldClient.Token
		}
		if hostURL == "" || token == "" {
			finishInstall(fmt.Errorf("메인컴 연결 정보가 없습니다. 서버 Host URL과 API 토큰을 입력하세요"))
			return
		}
	}

	if hasClientRole(o.Role) {
		setProgress(72, "트레이 전용 Client 설정 중...", "")
		cdir := filepath.Join(envOr("APPDATA", envOr("LOCALAPPDATA", ".")), "GeumyiServerCenter")
		_ = os.MkdirAll(cdir, 0755)
		writeClientConfig(filepath.Join(cdir, "client.json"), ClientConfig{HostURL: hostURL, Token: token})
		createShortcuts(filepath.Join(o.InstallDir, "GeumyiServerCenter.exe"), filepath.Join(o.InstallDir, "GeumyiServerCenter.ico"))
		setClientAutostart(filepath.Join(o.InstallDir, "GeumyiServerCenter.exe"), o.AutoStartClient)
	} else {
		setClientAutostart("", false)
		removeShortcuts()
	}

	registerUninstall(o.InstallDir)
	setProgress(86, "역할 전환 · Host/Agent 상태 정리 완료", "")
	setupLog("Host/Agent readiness deferred to background watchdog")
	time.Sleep(250 * time.Millisecond)
	setProgress(95, "설정 백업 및 문서 마무리 중...", "")
	writeReadme(o.InstallDir, dataDir)
	dedicated := false
	if o.Role == 1 && o.DedicatedOptimize {
		dedicated = true
	}
	writeRoleState(dataDir, o.Role, dedicated)
	setupLog("install complete")
	time.Sleep(250 * time.Millisecond)
	finishInstall(nil)
}

func installIntegratedAgent(dir string) {
	_ = os.MkdirAll(filepath.Join(dir, "data"), 0755)
	_ = os.MkdirAll(filepath.Join(dir, "logs"), 0755)
	mustExtract("payload/GeumyiStatusAgent-0.5.4.jar", filepath.Join(dir, "GeumyiStatusAgent-0.5.4.jar"))
	_ = os.Remove(filepath.Join(dir, "GeumyiStatusAgent-0.5.2.jar"))
	_ = os.Remove(filepath.Join(dir, "GeumyiStatusAgent-0.5.1.jar"))
	_ = os.Remove(filepath.Join(dir, "GeumyiStatusAgent-0.5.0.jar"))
	_ = os.Remove(filepath.Join(dir, "GeumyiStatusAgent-0.4.5.jar"))
	cfgPath := filepath.Join(dir, "agent.properties")
	if _, e := os.Stat(cfgPath); os.IsNotExist(e) {
		migrated := false
		for _, old := range []string{
			filepath.Join(os.Getenv("USERPROFILE"), "Desktop", "agent", "agent.properties"),
			filepath.Join(envOr("APPDATA", ""), "GeumyiServerCenter", "agent.properties"),
		} {
			if old == "" {
				continue
			}
			if b, err := os.ReadFile(old); err == nil && len(b) > 0 {
				_ = os.WriteFile(cfgPath, b, 0600)
				migrated = true
				break
			}
		}
		if !migrated {
			mustExtract("payload/agent.properties.managed", cfgPath)
		}
	}
	st := filepath.Join(dir, "data", "agent-state.properties")
	if _, e := os.Stat(st); os.IsNotExist(e) {
		oldState := filepath.Join(os.Getenv("USERPROFILE"), "Desktop", "agent", "data", "agent-state.properties")
		if b, err := os.ReadFile(oldState); err == nil && len(b) > 0 {
			_ = os.WriteFile(st, b, 0600)
		} else {
			mustExtract("payload/agent-state.properties.managed", st)
		}
	}
}

func startAgentImmediate(dir, java string) error {
	if healthOK("http://127.0.0.1:8877/health") {
		return nil
	}
	logf, e := os.OpenFile(filepath.Join(dir, "logs", "agent-console.log"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if e != nil {
		return e
	}
	c := exec.Command(java, "-Dfile.encoding=UTF-8", "-jar", "GeumyiStatusAgent-0.5.4.jar", "agent.properties")
	c.Dir = dir
	c.Stdout = logf
	c.Stderr = logf
	hideCmd(c)
	if e = c.Start(); e != nil {
		_ = logf.Close()
		return e
	}
	_ = os.WriteFile(filepath.Join(dir, "agent.pid"), []byte(strconv.Itoa(c.Process.Pid)), 0600)
	go func() { _ = c.Wait(); _ = logf.Close() }()
	return nil
}
func discoverServerPath(port int, pathFile string) string {
	pd := envOr("PROGRAMDATA", `C:\ProgramData`)
	var old ServerConfig
	if b, e := os.ReadFile(filepath.Join(pd, "GeumyiServerCenter", "server.json")); e == nil {
		_ = json.Unmarshal(b, &old)
		for _, sv := range old.Servers {
			if sv.JavaPort == port && strings.TrimSpace(sv.Path) != "" {
				return strings.TrimSpace(sv.Path)
			}
		}
	}
	if b, e := os.ReadFile(pathFile); e == nil {
		p := strings.TrimSpace(strings.TrimPrefix(string(b), "\ufeff"))
		if p != "" {
			return p
		}
	}
	launch := filepath.Join(filepath.Dir(pathFile), "launch.cmd")
	if b, e := os.ReadFile(launch); e == nil {
		for _, ln := range strings.Split(string(b), "\n") {
			low := strings.ToLower(strings.TrimSpace(ln))
			if i := strings.Index(low, "cd /d"); i >= 0 {
				p := strings.Trim(strings.TrimSpace(ln[i+len("cd /d"):]), "\" ")
				if p != "" {
					return p
				}
			}
		}
	}
	return ""
}
func validServerDir(dir string, port int) bool {
	if dir == "" {
		return false
	}
	b, e := os.ReadFile(filepath.Join(dir, "server.properties"))
	return e == nil && strings.Contains(string(b), fmt.Sprintf("server-port=%d", port))
}
func readExistingClientConfig(path string) ClientConfig {
	var c ClientConfig
	if b, e := os.ReadFile(path); e == nil {
		_ = json.Unmarshal(b, &c)
		if plain, err := securestore.UnprotectString(c.Token); err == nil {
			c.Token = plain
		}
	}
	c.HostURL = strings.TrimRight(strings.TrimSpace(c.HostURL), "/")
	return c
}

func readExistingServerConfig(path string) ServerConfig {
	var c ServerConfig
	if b, e := os.ReadFile(path); e == nil {
		_ = json.Unmarshal(b, &c)
		if plain, err := securestore.UnprotectString(c.APIToken); err == nil {
			c.APIToken = plain
		}
	}
	return c
}
func backupLegacyTasks(dataDir string) {
	stamp := time.Now().Format("20060102-150405")
	dir := filepath.Join(dataDir, "Backup", "LegacyTasks-"+stamp)
	_ = os.MkdirAll(dir, 0755)
	for _, name := range legacyTaskNames() {
		c := exec.Command("schtasks.exe", "/Query", "/TN", name, "/XML")
		hideCmd(c)
		if out, e := c.Output(); e == nil && len(out) > 0 {
			_ = os.WriteFile(filepath.Join(dir, safeName(name)+".xml"), out, 0644)
		}
	}
}
func deleteLegacyTasks() {
	for _, name := range legacyTaskNames() {
		c := exec.Command("schtasks.exe", "/Change", "/TN", name, "/DISABLE")
		hideCmd(c)
		_ = c.Run()
		c = exec.Command("schtasks.exe", "/Delete", "/TN", name, "/F")
		hideCmd(c)
		_ = c.Run()
	}
}
func legacyTaskNames() []string {
	return []string{"Minecraft Server", "MC Server Console", "MC Web Manager", "Minecraft Playground Server", "MC Playground Server Console", "MC Playground Web Manager", "Geumyi Status Agent", "GeumyiStatusAgent", "Geumyi Server Host", hostTaskName}
}
func safeName(s string) string {
	r := strings.NewReplacer("\\", "_", "/", "_", ":", "_", "*", "_", "?", "_", "\"", "_", "<", "_", ">", "_", "|", "_")
	return r.Replace(s)
}
func createHostTask(exe, cfg string) error {
	c := exec.Command("schtasks.exe", "/Delete", "/TN", hostTaskName, "/F")
	hideCmd(c)
	_ = c.Run()
	ps := fmt.Sprintf(`$a=New-ScheduledTaskAction -Execute '%s' -Argument '--config "%s"';$t=New-ScheduledTaskTrigger -AtStartup;$t.Delay='PT15S';$p=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest;$s=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries;Register-ScheduledTask -TaskName '%s' -Action $a -Trigger $t -Principal $p -Settings $s -Force|Out-Null`, psQuote(exe), psQuote(cfg), hostTaskName)
	c = exec.Command("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps)
	hideCmd(c)
	if out, e := c.CombinedOutput(); e != nil {
		return fmt.Errorf("Host 작업 등록 실패: %w %s", e, string(out))
	}
	return nil
}
func findJavaExecutable() string {
	pd := envOr("PROGRAMDATA", `C:\ProgramData`)
	old := readExistingServerConfig(filepath.Join(pd, "GeumyiServerCenter", "server.json"))
	r, e := javaruntime.Resolve(old.Agent.JavaPath)
	if e != nil {
		setupLog("Java probe: " + e.Error())
		return ""
	}
	return r.Executable
}

func addFirewallRule() {
	removeFirewallRule()
	c := exec.Command("netsh.exe", "advfirewall", "firewall", "add", "rule", "name=Geumyi Server Center Mobile API", "dir=in", "action=allow", "protocol=TCP", "localport=8787", "remoteip=LocalSubnet,100.64.0.0/10", "profile=any")
	hideCmd(c)
	_ = c.Run()
}
func removeFirewallRule() {
	for _, name := range []string{"Geumyi Server Center Mobile API", "Geumyi Server Center API"} {
		c := exec.Command("netsh.exe", "advfirewall", "firewall", "delete", "rule", "name="+name)
		hideCmd(c)
		_ = c.Run()
	}
}
func writePairingFile(dataDir, token string) {
	host := preferredLANIPv4()
	if host == "" {
		host = "SERVER_PC_IP"
	}
	tail := tailscaleIPv4()
	text := "Geumyi Server Center Pairing (PRIVATE)\r\nHostURL=http://" + host + ":8787\r\nToken=" + token + "\r\n"
	if tail != "" {
		text += "TailscaleURL=http://" + tail + ":8787\r\n"
	}
	_ = os.WriteFile(filepath.Join(dataDir, "PAIRING.txt"), []byte(text), 0600)
}
func tailscaleIPv4() string {
	if p, e := exec.LookPath("tailscale.exe"); e == nil {
		c := exec.Command(p, "ip", "-4")
		hideCmd(c)
		if b, e := c.Output(); e == nil {
			return strings.TrimSpace(string(b))
		}
	}
	return ""
}
func createShortcuts(exe, icon string) {
	desktop := filepath.Join(os.Getenv("USERPROFILE"), "Desktop", "Geumyi Server Center.lnk")
	start := filepath.Join(envOr("APPDATA", "."), `Microsoft\Windows\Start Menu\Programs\Geumyi Server Center.lnk`)
	for _, lnk := range []string{desktop, start} {
		ps := fmt.Sprintf(`$w=New-Object -ComObject WScript.Shell;$s=$w.CreateShortcut('%s');$s.TargetPath='%s';$s.WorkingDirectory='%s';$s.IconLocation='%s,0';$s.Description='Geumyi Server Center';$s.Save()`, psQuote(lnk), psQuote(exe), psQuote(filepath.Dir(exe)), psQuote(icon))
		c := exec.Command("powershell.exe", "-NoProfile", "-Command", ps)
		hideCmd(c)
		_ = c.Run()
	}
}
func setClientAutostart(exe string, on bool) {
	key := `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
	if on {
		c := exec.Command("reg.exe", "ADD", key, "/v", "Geumyi Server Center", "/t", "REG_SZ", "/d", `"`+exe+`" --background`, "/f")
		hideCmd(c)
		_ = c.Run()
	} else {
		c := exec.Command("reg.exe", "DELETE", key, "/v", "Geumyi Server Center", "/f")
		hideCmd(c)
		_ = c.Run()
	}
}
func registerUninstall(dir string) {
	key := `HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\GeumyiServerCenter`
	setup := filepath.Join(dir, "GeumyiServerCenter-Setup.exe")
	icon := filepath.Join(dir, "GeumyiServerCenter.ico")
	vals := [][]string{{"/v", "DisplayName", "/d", "Geumyi Server Center", "/f"}, {"/v", "DisplayVersion", "/d", version, "/f"}, {"/v", "Publisher", "/d", "Geumyi", "/f"}, {"/v", "DisplayIcon", "/d", icon, "/f"}, {"/v", "InstallLocation", "/d", dir, "/f"}, {"/v", "UninstallString", "/d", `"` + setup + `" /uninstall`, "/f"}}
	for _, v := range vals {
		c := exec.Command("reg.exe", append([]string{"ADD", key}, v...)...)
		hideCmd(c)
		_ = c.Run()
	}
}
func writeReadme(dir, dataDir string) {
	s := "Geumyi Server Center v" + version + "\r\n\r\n" +
		"- 설치 역할은 %ProgramData%\\GeumyiServerCenter\\role.json에 기록됩니다.\r\n" +
		"- 서버 PC: Host + Agent + 서버 자동시작 + Minecraft 방화벽 + 전용 Windows 프로필\r\n" +
		"- 관리 PC: Client만 유지하며 기존 Host/Agent/서버 방화벽/전용 Windows 프로필을 자동 제거·원복\r\n" +
		"- 둘 다: Host + Agent + Client. 전용 서버 Windows 프로필은 적용하지 않으며 이전 전용 프로필은 원복\r\n" +
		"- Host: Windows 부팅 시 SYSTEM 백그라운드 실행, 15초 지연 후 시작, Windows Service 장애 자동복구\r\n" +
		"- 서버 폴더의 기존 start.bat 사용 (SYSTEM 백그라운드 실행)\r\n" +
		"- Agent: %ProgramData%\\GeumyiServerCenter\\Runtime\\Agent 자동 설치/복구\r\n" +
		"- 관리 API/WebRCON: 8787/TCP. RCON 자체는 외부 방화벽에 열지 않습니다.\r\n" +
		"- 서버 PC 전환 해제 시 Windows 전원/레지스트리 변경을 설치 전 상태로 자동 원복합니다.\r\n" +
		"- Microsoft Defender와 Windows Update 자체는 끄지 않습니다.\r\n" +
		"- 실제 서버/월드/plugins는 삭제하지 않습니다.\r\n"
	_ = os.WriteFile(filepath.Join(dir, "README.txt"), []byte(s), 0644)
	_ = os.WriteFile(filepath.Join(dataDir, "MIGRATION-COMPLETE.txt"), []byte(s), 0644)
}

func runUninstall() {
	pd := envOr("PROGRAMDATA", `C:\ProgramData`)
	dataDir := filepath.Join(pd, "GeumyiServerCenter")
	dir := filepath.Join(envOr("ProgramFiles", `C:\Program Files`), "Geumyi Server Center")
	if self, e := os.Executable(); e == nil && strings.EqualFold(filepath.Base(self), "GeumyiServerCenter-Setup.exe") {
		dir = filepath.Dir(self)
	}
	oldRole := detectInstalledRole(dataDir, dir)
	if hasServerRole(oldRole) {
		// Best effort graceful drain. If it fails, never force-kill Minecraft Java.
		if e := gracefulHostShutdownForTransition(); e != nil {
			setupLog("uninstall aborted for data safety: " + e.Error())
			c := exec.Command("msg.exe", "*", "Geumyi Server Center 제거를 중단했습니다. Minecraft 서버 정상 종료에 실패했습니다. setup.log를 확인하세요.")
			hideCmd(c)
			_ = c.Run()
			return
		}
	}
	prepareForUpgradeAll()
	restoreDedicatedServerProfile(dataDir)
	removeServerComponent(dir, dataDir)
	removeClientComponent(dir)
	_ = os.Remove(filepath.Join(dataDir, roleStateFile))
	c := exec.Command("reg.exe", "DELETE", `HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\GeumyiServerCenter`, "/f")
	hideCmd(c)
	_ = c.Run()
	cmd := fmt.Sprintf(`timeout /t 2 /nobreak >nul & rmdir /s /q "%s"`, dir)
	_ = exec.Command("cmd.exe", "/C", "start", "", "cmd.exe", "/C", cmd).Start()
}

func launchInstalled(dir string) {
	_ = exec.Command(filepath.Join(dir, "GeumyiServerCenter.exe")).Start()
}
func healthOK(u string) bool {
	c := http.Client{Timeout: 900 * time.Millisecond}
	r, e := c.Get(u)
	if e != nil {
		return false
	}
	_ = r.Body.Close()
	return r.StatusCode/100 == 2
}
func mustExtract(name, dst string) {
	b, e := fs.ReadFile(payload, name)
	if e != nil {
		panic(e)
	}
	if e = os.MkdirAll(filepath.Dir(dst), 0755); e != nil {
		panic(e)
	}
	tmp := dst + ".new"
	_ = os.Remove(tmp)
	if e = os.WriteFile(tmp, b, 0755); e != nil {
		panic(e)
	}
	for i := 0; i < 12; i++ {
		_ = os.Remove(dst)
		if e = os.Rename(tmp, dst); e == nil {
			return
		}
		time.Sleep(350 * time.Millisecond)
	}
	panic(e)
}
func copyFile(src, dst string) {
	if b, e := os.ReadFile(src); e == nil {
		_ = os.WriteFile(dst, b, 0755)
	}
}
func writeJSON(path string, v any) {
	b, _ := json.MarshalIndent(v, "", "  ")
	_ = os.MkdirAll(filepath.Dir(path), 0755)
	if e := os.WriteFile(path, b, 0600); e != nil {
		panic(e)
	}
}
func randomToken() string {
	b := make([]byte, 32)
	_, _ = rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)
}
func envOr(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}
func isAdmin() bool           { c := exec.Command("net.exe", "session"); hideCmd(c); return c.Run() == nil }
func psQuote(s string) string { return strings.ReplaceAll(s, "'", "''") }
func setupLog(msg string) {
	pd := envOr("PROGRAMDATA", `C:\ProgramData`)
	dir := filepath.Join(pd, "GeumyiServerCenter", "logs")
	_ = os.MkdirAll(dir, 0755)
	f, e := os.OpenFile(filepath.Join(dir, "setup.log"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if e != nil {
		return
	}
	defer f.Close()
	_, _ = fmt.Fprintf(f, "%s  %s\r\n", time.Now().Format("2006-01-02 15:04:05"), msg)
}

// v4: interactive folder selection for installer. This is only used by the
// foreground installer process; the headless Host uses its own remote folder browser.
func apiPickFolder(w http.ResponseWriter, r *http.Request) {
	start := strings.TrimSpace(r.URL.Query().Get("start"))
	// FolderBrowserDialog without an owner can appear behind the Edge app-mode
	// installer. Give it an invisible TopMost owner and explicitly foreground
	// that owner before showing the dialog. AutoUpgradeEnabled requests the
	// modern Windows Explorer-style picker where supported.
	ps := `$ErrorActionPreference='Stop'; Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class GSCNative { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd); }'; $owner=New-Object System.Windows.Forms.Form; $owner.ShowInTaskbar=$false; $owner.TopMost=$true; $owner.FormBorderStyle=[System.Windows.Forms.FormBorderStyle]::FixedToolWindow; $owner.StartPosition=[System.Windows.Forms.FormStartPosition]::CenterScreen; $owner.Size=New-Object System.Drawing.Size(2,2); $owner.Opacity=0.01; $owner.Text='Geumyi Server Center'; $owner.Show(); $owner.Activate(); [GSCNative]::SetForegroundWindow($owner.Handle)|Out-Null; $d=New-Object System.Windows.Forms.FolderBrowserDialog; $d.Description='Minecraft 서버 폴더를 선택하세요. server.properties가 있는 폴더를 선택하면 됩니다.'; $d.ShowNewFolderButton=$false; try{$d.AutoUpgradeEnabled=$true}catch{};`
	if start != "" {
		ps += `$d.SelectedPath='` + psQuote(start) + `';`
	}
	ps += `$result=$d.ShowDialog($owner); if($result -eq [System.Windows.Forms.DialogResult]::OK){[Console]::OutputEncoding=[Text.Encoding]::UTF8; Write-Output $d.SelectedPath}; $owner.Close(); $owner.Dispose()`
	c := exec.Command("powershell.exe", "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-Command", ps)
	hideCmd(c)
	b, err := c.Output()
	if err != nil {
		http.Error(w, "폴더 선택 창을 열지 못했습니다: "+err.Error(), 500)
		return
	}
	path := strings.TrimSpace(string(b))
	writeHTTPJSON(w, map[string]any{"path": path})
}
func defaultUpdateConfig(dataDir string) UpdateConfig {
	return UpdateConfig{
		Enabled:        false,
		Repository:     "geumyi22/Geumyi-Minecraft-System",
		Channel:        "canary",
		PublicKeyPath:  filepath.Join(dataDir, "deployment-public.pem"),
		TimeoutSeconds: 12,
	}
}

func normalizeUpdateConfig(c UpdateConfig, dataDir string) UpdateConfig {
	if strings.TrimSpace(c.Repository) == "" {
		c.Repository = "geumyi22/Geumyi-Minecraft-System"
	}
	c.Channel = strings.ToLower(strings.TrimSpace(c.Channel))
	if c.Channel != "stable" && c.Channel != "beta" && c.Channel != "canary" {
		c.Channel = "canary"
	}
	if strings.TrimSpace(c.PublicKeyPath) == "" {
		c.PublicKeyPath = filepath.Join(dataDir, "deployment-public.pem")
	}
	if c.TimeoutSeconds < 3 || c.TimeoutSeconds > 60 {
		c.TimeoutSeconds = 12
	}
	return c
}

func writeServerConfig(path string, c ServerConfig) {
	disk := c
	protected, err := securestore.ProtectString(c.APIToken, true)
	if err != nil {
		panic(err)
	}
	disk.APIToken = protected
	writeJSON(path, disk)
}

func writeClientConfig(path string, c ClientConfig) {
	disk := c
	protected, err := securestore.ProtectString(c.Token, false)
	if err != nil {
		panic(err)
	}
	disk.Token = protected
	writeJSON(path, disk)
}

func installManagedPlugins(dataDir string) {
	dir := filepath.Join(dataDir, "ManagedPlugins")
	_ = os.MkdirAll(dir, 0755)
	// Keep exactly one managed companion JAR per plugin. Leaving older GDS JARs
	// here makes Companion Sync install duplicate plugin versions into Paper.
	if entries, err := os.ReadDir(dir); err == nil {
		for _, e := range entries {
			if e.IsDir() {
				continue
			}
			n := strings.ToLower(e.Name())
			if (strings.HasPrefix(n, "geumyidiscordstatus-") || strings.HasPrefix(n, "geumyiservertools-")) && strings.HasSuffix(n, ".jar") {
				_ = os.Remove(filepath.Join(dir, e.Name()))
			}
		}
	}
	mustExtract("payload/GeumyiDiscordStatus-1.1.1-SpigotPaper26.3.jar", filepath.Join(dir, "GeumyiDiscordStatus-1.1.1-SpigotPaper26.3.jar"))
	mustExtract("payload/GeumyiServerTools-1.1.1-SpigotPaper26.3-GSCv4.1-HOTFIX.jar", filepath.Join(dir, "GeumyiServerTools-1.1.1-SpigotPaper26.3-GSCv4.1-HOTFIX.jar"))
}

func serviceExists(name string) bool {
	c := exec.Command("sc.exe", "query", name)
	hideCmd(c)
	return c.Run() == nil
}

func stopHostService() {
	c := exec.Command("sc.exe", "stop", hostServiceName)
	hideCmd(c)
	_ = c.Run()
	for i := 0; i < 20; i++ {
		c = exec.Command("sc.exe", "query", hostServiceName)
		hideCmd(c)
		b, _ := c.Output()
		if !strings.Contains(string(b), "RUNNING") && !strings.Contains(string(b), "STOP_PENDING") {
			break
		}
		time.Sleep(250 * time.Millisecond)
	}
}

func deleteHostService() {
	stopHostService()
	c := exec.Command("sc.exe", "delete", hostServiceName)
	hideCmd(c)
	_ = c.Run()
}

func createHostService(exe, cfg string) error {
	deleteHostService()
	bin := fmt.Sprintf(`"%s" --service --config "%s"`, exe, cfg)
	c := exec.Command("sc.exe", "create", hostServiceName, "binPath=", bin, "start=", "auto", "DisplayName=", "Geumyi Server Center Host")
	hideCmd(c)
	if out, err := c.CombinedOutput(); err != nil {
		return fmt.Errorf("Windows Service 등록 실패: %w %s", err, strings.TrimSpace(string(out)))
	}
	c = exec.Command("sc.exe", "config", hostServiceName, "start=", "delayed-auto")
	hideCmd(c)
	_ = c.Run()
	c = exec.Command("sc.exe", "description", hostServiceName, "Geumyi Server Center v4 Host Service - Minecraft server management core")
	hideCmd(c)
	_ = c.Run()
	c = exec.Command("sc.exe", "failure", hostServiceName, "reset=", "86400", "actions=", "restart/5000/restart/15000/restart/30000")
	hideCmd(c)
	_ = c.Run()
	c = exec.Command("sc.exe", "failureflag", hostServiceName, "1")
	hideCmd(c)
	_ = c.Run()
	return nil
}

func startHostService() error {
	c := exec.Command("sc.exe", "start", hostServiceName)
	hideCmd(c)
	out, err := c.CombinedOutput()
	if err != nil && !strings.Contains(strings.ToLower(string(out)), "already") {
		return fmt.Errorf("sc start: %w %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}
