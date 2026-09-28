package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	_ "embed"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"geumyi/servercenter/internal/javaruntime"
	"geumyi/servercenter/internal/securestore"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const appVersion = "4.2.3"

type Config struct {
	Bind                string         `json:"bind"`
	Port                int            `json:"port"`
	APIToken            string         `json:"api_token"`
	AllowLoopbackNoAuth bool           `json:"allow_loopback_no_auth"`
	MobileEnabled       bool           `json:"mobile_enabled"`
	PairingTTLSeconds   int            `json:"pairing_ttl_seconds"`
	AutoStartAgent      bool           `json:"auto_start_agent"`
	Agent               AgentConfig    `json:"agent"`
	Update              UpdateConfig   `json:"update"`
	Servers             []ServerConfig `json:"servers"`
}

type AgentConfig struct {
	HealthURL    string `json:"health_url"`
	StateURL     string `json:"state_url"`
	StartCommand string `json:"start_command"` // legacy fallback
	WorkingDir   string `json:"working_dir"`
	JavaPath     string `json:"java_path"`
	JarName      string `json:"jar_name"`
}

type ServerConfig struct {
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

type HostStats struct {
	Hostname    string   `json:"hostname"`
	OS          string   `json:"os"`
	Uptime      string   `json:"uptime"`
	CPUPercent  float64  `json:"cpu_percent"`
	RAMUsedGB   float64  `json:"ram_used_gb"`
	RAMTotalGB  float64  `json:"ram_total_gb"`
	DiskFreeGB  float64  `json:"disk_free_gb"`
	DiskTotalGB float64  `json:"disk_total_gb"`
	IPv4        []string `json:"ipv4"`
}

type JavaStats struct {
	PID          int     `json:"pid"`
	CPUSeconds   float64 `json:"cpu_seconds"`
	WorkingSetMB float64 `json:"working_set_mb"`
	PrivateMB    float64 `json:"private_mb"`
	Threads      int     `json:"threads"`
	Handles      int     `json:"handles"`
	StartTime    string  `json:"start_time"`
}

type MCStatus struct {
	OK            bool     `json:"ok"`
	Version       string   `json:"version"`
	Protocol      int      `json:"protocol"`
	MOTD          string   `json:"motd"`
	Online        int      `json:"online"`
	Max           int      `json:"max"`
	ReportedMax   int      `json:"reported_max,omitempty"`
	ConfiguredMax int      `json:"configured_max,omitempty"`
	MaxSource     string   `json:"max_source,omitempty"`
	Players       []string `json:"players"`
	LatencyMS     int64    `json:"latency_ms"`
}

type ServerStatus struct {
	ID                  string                  `json:"id"`
	Name                string                  `json:"name"`
	Online              bool                    `json:"online"`
	JavaPortOpen        bool                    `json:"java_port_open"`
	RCONPortOpen        bool                    `json:"rcon_port_open"`
	BedrockUDPListening bool                    `json:"bedrock_udp_listening"`
	GDSAPIOnline        bool                    `json:"gds_api_online"`
	MC                  MCStatus                `json:"minecraft"`
	Java                JavaStats               `json:"java"`
	Dir                 string                  `json:"dir"`
	ConfiguredDir       string                  `json:"configured_dir"`
	DirValid            bool                    `json:"dir_valid"`
	PaperJar            string                  `json:"paper_jar"`
	PluginCount         int                     `json:"plugin_count"`
	WorldCount          int                     `json:"world_count"`
	Worlds              []string                `json:"worlds"`
	LogAgeSeconds       int64                   `json:"log_age_seconds"`
	LogSizeBytes        int64                   `json:"log_size_bytes"`
	WarnCount           int                     `json:"warn_count"`
	ErrorCount          int                     `json:"error_count"`
	DesiredRunning      bool                    `json:"desired_running"`
	RestartOnCrash      bool                    `json:"restart_on_crash"`
	Launch              LaunchStatus            `json:"launch"`
	LauncherRunning     bool                    `json:"launcher_running"`
	Schedule            LifecycleScheduleStatus `json:"schedule"`
	State               string                  `json:"state"`
}

type FullStatus struct {
	AppVersion  string         `json:"app_version"`
	Timestamp   string         `json:"timestamp"`
	Host        HostStats      `json:"host"`
	Agent       any            `json:"agent"`
	AgentOnline bool           `json:"agent_online"`
	AgentError  string         `json:"agent_error,omitempty"`
	AgentJava   string         `json:"agent_java,omitempty"`
	Servers     []ServerStatus `json:"servers"`
}

var (
	cfg                 Config
	configMu            sync.RWMutex
	configPath          string
	statusMu            sync.Mutex
	cachedHost          HostStats
	cachedHostAt        time.Time
	hostRefreshInFlight atomic.Bool
	javaCache           map[int]JavaStats = make(map[int]JavaStats)
	javaCacheAt         time.Time
	javaRefreshInFlight atomic.Bool
	udpCache            map[int]bool = make(map[int]bool)
	udpCacheAt          time.Time
	udpRefreshInFlight  atomic.Bool
	agentMu             sync.RWMutex
	agentStartMu        sync.Mutex
	lastAgentErr        string
	lastAgentJava       string
	desiredMu           sync.RWMutex
	desiredRun          = map[string]bool{}
	serverLocks         = map[string]*sync.Mutex{}
	lastAttempt         = map[string]time.Time{}
)

func defaultConfig() Config {
	token := make([]byte, 32)
	_, _ = rand.Read(token)
	pd := os.Getenv("PROGRAMDATA")
	if pd == "" {
		pd = `C:\ProgramData`
	}
	agentDir := filepath.Join(pd, "GeumyiServerCenter", "Runtime", "Agent")
	return Config{
		Bind: "127.0.0.1", Port: 8787, MobileEnabled: true, PairingTTLSeconds: 300,
		APIToken:            base64.RawURLEncoding.EncodeToString(token),
		AllowLoopbackNoAuth: true,
		AutoStartAgent:      true,
		Agent: AgentConfig{
			HealthURL:    "http://127.0.0.1:8877/health",
			StateURL:     "http://127.0.0.1:8877/state",
			StartCommand: "agent-start-hidden.cmd",
			WorkingDir:   agentDir,
			JarName:      "GeumyiStatusAgent-0.5.4.jar",
		},
		Update: defaultUpdateConfig(filepath.Join(pd, "GeumyiServerCenter")),
		Servers: []ServerConfig{
			{ID: "wild", Name: "금이 야생", JavaPort: 25565, RCONPort: 25575, BedrockPort: 19132, GDSAPIPort: 8766,
				PathFile: `C:\ProgramData\MinecraftServer\server_path.txt`, StartCommand: "start.bat", AutoStart: true, RestartOnCrash: true},
			{ID: "playground", Name: "금이 놀이터", JavaPort: 25566, RCONPort: 25576, BedrockPort: 19133, GDSAPIPort: 8765,
				PathFile: `C:\ProgramData\MinecraftPlaygroundServer\server_path.txt`, StartCommand: "start.bat", AutoStart: true, RestartOnCrash: true},
		},
	}
}

func main() {
	if serviceModeRequested() {
		if err := runWindowsService(runHostCore); err != nil {
			fmt.Fprintf(os.Stderr, "service error: %v\n", err)
		}
		return
	}
	if err := runHostCore(); err != nil {
		fmt.Fprintf(os.Stderr, "host error: %v\n", err)
		os.Exit(1)
	}
}

func runHostCore() error {
	configPath = flagValue("--config")
	if configPath == "" {
		pd := os.Getenv("PROGRAMDATA")
		if pd == "" {
			pd = `C:\ProgramData`
		}
		configPath = filepath.Join(pd, "GeumyiServerCenter", "server.json")
	}

	var err error
	cfg, err = loadOrCreateConfig(configPath)
	if err != nil {
		return fmt.Errorf("config error: %w", err)
	}

	fmt.Printf("Geumyi Server Host v%s\n", appVersion)
	fmt.Printf("Config: %s\n", configPath)
	fmt.Printf("Listening transport: http://0.0.0.0:%d (remote gate: %v)\n", cfg.Port, cfg.MobileEnabled)
	if cfg.MobileEnabled {
		fmt.Println("Mobile API allowed only from LAN/Tailscale with authentication.")
	}

	initRuntimeState()
	initV4Runtime()
	initV41Runtime()
	syncMobileFirewall(cfg.MobileEnabled)
	restoreLifecycleSchedules()
	// Reconcile the local Agent/GDS bridge before either side begins sending
	// heartbeats. This prevents a preserved/migrated config from leaving the
	// Agent and per-server GDS secrets or IDs out of sync after an upgrade.
	changedBridges, _ := reconcileLocalCompanionConfigs()
	startStatusTelemetry()
	go startupSupervisor()
	go reloadReconciledGDS(changedBridges)
	go v4MetricsLoop()
	go v4AutomationLoop()

	mux := http.NewServeMux()
	mux.HandleFunc("/", serveDashboard)
	mux.HandleFunc("/api/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, map[string]any{"ok": true, "version": appVersion, "service": serviceModeRequested(), "generation": 4})
	})
	mux.HandleFunc("/api/status", requireAuth(apiStatus))
	mux.HandleFunc("/api/log", requireAuth(apiLog))
	mux.HandleFunc("/api/server/action", requireAuth(apiAction))
	mux.HandleFunc("/api/server/schedule", requireAuth(apiSchedule))
	mux.HandleFunc("/api/server/command", requireAuth(apiCommand))
	mux.HandleFunc("/api/agent/start", requireAuth(apiAgentStart))
	mux.HandleFunc("/api/agent/action", requireAuth(apiAgentAction))
	mux.HandleFunc("/api/shutdown", requireAuth(apiShutdown))
	mux.HandleFunc("/api/shutdown/status", requireAuth(apiShutdownStatus))
	mux.HandleFunc("/api/shutdown/finish", requireAuth(apiShutdownFinish))
	mux.HandleFunc("/api/settings", requireAuth(apiSettings))
	mux.HandleFunc("/api/settings/public", requireAuth(apiPublicSettings))
	registerV4Routes(mux)
	registerControlAPIRoutes(mux)

	srv := &http.Server{
		Addr: fmt.Sprintf("0.0.0.0:%d", cfg.Port), Handler: securityHeaders(mobileNetworkGuard(mux)),
		ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 60 * time.Second,
	}
	go func() {
		<-hostQuit
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(ctx)
	}()
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		return fmt.Errorf("server error: %w", err)
	}
	return nil
}

func flagValue(name string) string {
	for i := 1; i < len(os.Args)-1; i++ {
		if os.Args[i] == name {
			return os.Args[i+1]
		}
	}
	return ""
}

func loadOrCreateConfig(path string) (Config, error) {
	if b, err := os.ReadFile(path); err == nil {
		c := defaultConfig()
		if err := json.Unmarshal(b, &c); err != nil {
			return c, err
		}
		plain, err := securestore.UnprotectString(c.APIToken)
		if err != nil {
			return c, fmt.Errorf("API token decrypt failed: %w", err)
		}
		c.APIToken = plain
		if c.Port == 0 {
			c.Port = 8787
		}
		if c.PairingTTLSeconds < 60 || c.PairingTTLSeconds > 3600 {
			c.PairingTTLSeconds = 300
		}
		c.Update = normalizeUpdateConfig(c.Update)
		return c, nil
	}
	c := defaultConfig()
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return c, err
	}
	disk := c
	protected, err := securestore.ProtectString(c.APIToken, true)
	if err != nil {
		return c, err
	}
	disk.APIToken = protected
	b, _ := json.MarshalIndent(disk, "", "  ")
	if err := os.WriteFile(path, b, 0600); err != nil {
		return c, err
	}
	return c, nil
}

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Cache-Control", "no-store")
		next.ServeHTTP(w, r)
	})
}

func isLoopbackRemote(remote string) bool {
	host, _, err := net.SplitHostPort(remote)
	if err != nil {
		host = remote
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

func requireAuth(fn http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		p, ok := authenticateRequest(r)
		if !ok {
			appendUnauthorizedAudit(r)
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		r = r.WithContext(context.WithValue(r.Context(), authContextKey{}, p))
		fn(w, r)
	}
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	_ = enc.Encode(v)
}

func apiPublicSettings(w http.ResponseWriter, r *http.Request) {
	cfg := configSnapshot()
	type s struct {
		ID, Name                                    string
		JavaPort, RCONPort, BedrockPort, GDSAPIPort int
	}
	out := make([]s, 0, len(cfg.Servers))
	for _, x := range cfg.Servers {
		out = append(out, s{x.ID, x.Name, x.JavaPort, x.RCONPort, x.BedrockPort, x.GDSAPIPort})
	}
	writeJSON(w, map[string]any{"bind": cfg.Bind, "port": cfg.Port, "mobile_enabled": cfg.MobileEnabled, "pairing_ttl_seconds": cfg.PairingTTLSeconds, "servers": out, "version": appVersion})
}

type settingsUpdate struct {
	AutoStartAgent *bool `json:"auto_start_agent"`
	Servers        []struct {
		ID             string `json:"id"`
		Path           string `json:"path"`
		StartCommand   string `json:"start_command"`
		AutoStart      bool   `json:"auto_start"`
		RestartOnCrash bool   `json:"restart_on_crash"`
	} `json:"servers"`
}

func apiSettings(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" && shuttingDown.Load() {
		http.Error(w, "전체 종료 중입니다", 409)
		return
	}
	cfg := configSnapshot()
	if r.Method == "GET" {
		type ss struct {
			ID             string `json:"id"`
			Name           string `json:"name"`
			Path           string `json:"path"`
			PathFile       string `json:"path_file"`
			StartCommand   string `json:"start_command"`
			AutoStart      bool   `json:"auto_start"`
			RestartOnCrash bool   `json:"restart_on_crash"`
			JavaPort       int    `json:"java_port"`
			RCONPort       int    `json:"rcon_port"`
			BedrockPort    int    `json:"bedrock_port"`
			GDSAPIPort     int    `json:"gds_api_port"`
		}
		out := make([]ss, 0, len(cfg.Servers))
		for _, x := range cfg.Servers {
			out = append(out, ss{ID: x.ID, Name: x.Name, Path: configuredServerDir(x), PathFile: x.PathFile, StartCommand: x.StartCommand, AutoStart: x.AutoStart, RestartOnCrash: x.RestartOnCrash, JavaPort: x.JavaPort, RCONPort: x.RCONPort, BedrockPort: x.BedrockPort, GDSAPIPort: x.GDSAPIPort})
		}
		writeJSON(w, map[string]any{"bind": cfg.Bind, "port": cfg.Port, "mobile_enabled": cfg.MobileEnabled, "pairing_ttl_seconds": cfg.PairingTTLSeconds, "auto_start_agent": cfg.AutoStartAgent, "servers": out, "version": appVersion})
		return
	}
	if r.Method != "POST" {
		http.Error(w, "POST required", 405)
		return
	}
	var q settingsUpdate
	if json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q) != nil {
		http.Error(w, "bad json", 400)
		return
	}
	if q.AutoStartAgent != nil {
		cfg.AutoStartAgent = *q.AutoStartAgent
		setAgentDesired(*q.AutoStartAgent)
	}
	for _, u := range q.Servers {
		for i := range cfg.Servers {
			if cfg.Servers[i].ID != u.ID {
				continue
			}
			if strings.TrimSpace(u.Path) != "" {
				cfg.Servers[i].Path = strings.TrimSpace(u.Path)
			}
			if strings.TrimSpace(u.StartCommand) != "" {
				cmd := strings.TrimSpace(u.StartCommand)
				if strings.ContainsAny(cmd, "\r\n\x00") {
					http.Error(w, "start_command에 허용되지 않는 문자가 있습니다", 400)
					return
				}
				cfg.Servers[i].StartCommand = cmd
			}
			cfg.Servers[i].AutoStart = u.AutoStart
			cfg.Servers[i].RestartOnCrash = u.RestartOnCrash
			if u.AutoStart {
				setDesired(u.ID, true)
			}
		}
	}
	if err := saveHostConfig(cfg); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	writeJSON(w, map[string]any{"ok": true, "message": "설정 저장 완료"})
}

func saveHostConfig(next Config) error {
	configMu.Lock()
	defer configMu.Unlock()
	disk := next
	protected, err := securestore.ProtectString(next.APIToken, true)
	if err != nil {
		return err
	}
	disk.APIToken = protected
	b, err := json.MarshalIndent(disk, "", "  ")
	if err != nil {
		return err
	}
	if err = os.MkdirAll(filepath.Dir(configPath), 0755); err != nil {
		return err
	}
	tmp := configPath + ".tmp"
	if err = os.WriteFile(tmp, b, 0600); err != nil {
		return err
	}
	if err = os.Rename(tmp, configPath); err != nil {
		return err
	}
	cfg = next
	return nil
}

func apiAgentAction(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" && shuttingDown.Load() {
		http.Error(w, "전체 종료 중입니다", 409)
		return
	}
	if r.Method != "POST" {
		http.Error(w, "POST required", 405)
		return
	}
	var q agentActionReq
	if json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q) != nil {
		http.Error(w, "bad json", 400)
		return
	}
	switch strings.ToLower(strings.TrimSpace(q.Action)) {
	case "start":
		setAgentDesired(true)
		go func() { _, _ = startAgent() }()
		w.WriteHeader(http.StatusAccepted)
		writeJSON(w, map[string]any{"ok": true, "message": "Agent 시작/복구 요청됨"})
	case "restart":
		setAgentDesired(false)
		go func() {
			if e := stopAgent(); e != nil {
				setAgentDiag(e.Error(), resolveAgentJava())
				return
			}
			setAgentDesired(true)
			_, _ = startAgent()
		}()
		w.WriteHeader(http.StatusAccepted)
		writeJSON(w, map[string]any{"ok": true, "message": "Agent 재시작 요청됨"})
	case "stop":
		setAgentDesired(false)
		go func() {
			if e := stopAgent(); e != nil {
				setAgentDiag(e.Error(), resolveAgentJava())
			} else {
				setAgentDiag("Agent 수동 종료", resolveAgentJava())
			}
		}()
		w.WriteHeader(http.StatusAccepted)
		writeJSON(w, map[string]any{"ok": true, "message": "Agent 종료 요청됨"})
	default:
		http.Error(w, "unknown action", 400)
	}
}

func stopAgent() error { agentStartMu.Lock(); defer agentStartMu.Unlock(); return stopAgentLocked() }

func apiStatus(w http.ResponseWriter, r *http.Request) {
	c := configSnapshot()
	st := FullStatus{AppVersion: appVersion, Timestamp: time.Now().Format(time.RFC3339), Host: getHostStats()}
	// Agent and Minecraft probes are independent. Running them concurrently keeps
	// the dashboard responsive even while one component is still starting.
	var wg sync.WaitGroup
	var agent any
	var agentOK bool
	wg.Add(1)
	go func() {
		defer wg.Done()
		agent, agentOK = getJSONURL(c.Agent.StateURL)
	}()
	st.Servers = make([]ServerStatus, len(c.Servers))
	for i, server := range c.Servers {
		i, server := i, server
		wg.Add(1)
		go func() {
			defer wg.Done()
			st.Servers[i] = getServerStatus(server)
		}()
	}
	wg.Wait()
	if agentOK {
		st.Agent = agent
		st.AgentOnline = true
	}
	agentMu.RLock()
	st.AgentError = lastAgentErr
	st.AgentJava = lastAgentJava
	agentMu.RUnlock()
	writeJSON(w, st)
}

func apiLog(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Query().Get("id")
	lines, _ := strconv.Atoi(r.URL.Query().Get("lines"))
	if lines <= 0 || lines > 2000 {
		lines = 400
	}
	s, ok := serverByID(id)
	if !ok {
		http.Error(w, "unknown server", 400)
		return
	}
	dir := resolveServerDir(s)
	if dir == "" {
		http.Error(w, "server dir not found", 404)
		return
	}
	logPath := filepath.Join(dir, "logs", "latest.log")
	if r.URL.Query().Get("kind") == "launcher" {
		logPath = launcherLogPath(s.ID)
	}
	b, err := tailFile(logPath, lines)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	_, _ = w.Write(b)
}

type actionReq struct {
	ID     string `json:"id"`
	Action string `json:"action"`
}

func apiAction(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" && shuttingDown.Load() {
		http.Error(w, "전체 종료 중입니다", 409)
		return
	}
	if r.Method != "POST" {
		http.Error(w, "POST required", 405)
		return
	}
	var q actionReq
	if json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q) != nil {
		http.Error(w, "bad json", 400)
		return
	}
	s, ok := serverByID(q.ID)
	if !ok {
		http.Error(w, "unknown server", 400)
		return
	}
	if job := activeControlJob(s.ID); job != nil && strings.ToLower(q.Action) != "cancel" {
		http.Error(w, "Control API 작업 진행 중: "+job.ID, http.StatusConflict)
		return
	}
	if op := currentOperation(s.ID); op != "" && strings.ToLower(q.Action) != "cancel" {
		http.Error(w, "현재 작업 진행 중: "+op, http.StatusConflict)
		return
	}
	switch strings.ToLower(q.Action) {
	case "start":
		// Starting an already-running server also acts as a safe countdown cancel.
		_ = cancelLifecycleCountdown(s.ID)
		clearStartupFailure(s.ID)
		go func() { _, _ = startServer(s) }()
		w.WriteHeader(http.StatusAccepted)
		writeJSON(w, map[string]any{"ok": true, "message": s.Name + " 시작/유지 요청됨"})
	case "stop", "restart":
		msg, err := beginLifecycleCountdown(s, strings.ToLower(q.Action))
		if err != nil {
			w.WriteHeader(http.StatusConflict)
			writeJSON(w, map[string]any{"ok": false, "message": msg, "error": err.Error()})
			return
		}
		w.WriteHeader(http.StatusAccepted)
		writeJSON(w, map[string]any{"ok": true, "message": msg})
	case "cancel":
		if !cancelLifecycleCountdown(s.ID) {
			w.WriteHeader(http.StatusConflict)
			writeJSON(w, map[string]any{"ok": false, "message": s.Name + " 진행 중인 카운트다운이 없습니다"})
			return
		}
		writeJSON(w, map[string]any{"ok": true, "message": s.Name + " 종료/재시작 예약 취소됨"})
	case "force-stop":
		_ = cancelLifecycleCountdown(s.ID)
		msg, err := forceStopServer(s)
		if err != nil {
			w.WriteHeader(500)
			writeJSON(w, map[string]any{"ok": false, "message": msg, "error": err.Error()})
			return
		}
		writeJSON(w, map[string]any{"ok": true, "message": msg})
	case "force-stop-launcher":
		_ = cancelLifecycleCountdown(s.ID)
		msg, err := forceStopLauncher(s)
		if err != nil {
			w.WriteHeader(http.StatusConflict)
			writeJSON(w, map[string]any{"ok": false, "message": msg, "error": err.Error()})
			return
		}
		writeJSON(w, map[string]any{"ok": true, "message": msg})
	default:
		http.Error(w, "unknown action", 400)
	}
}

type scheduleReq struct {
	ID               string `json:"id"`
	Action           string `json:"action"`
	ExecuteAt        string `json:"execute_at"`
	CountdownSeconds int    `json:"countdown_seconds"`
}

func apiSchedule(w http.ResponseWriter, r *http.Request) {
	if shuttingDown.Load() {
		http.Error(w, "전체 종료 중입니다", http.StatusConflict)
		return
	}
	if r.Method != "POST" {
		http.Error(w, "POST required", http.StatusMethodNotAllowed)
		return
	}
	var q scheduleReq
	if json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q) != nil {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	s, ok := serverByID(q.ID)
	if !ok {
		http.Error(w, "unknown server", http.StatusBadRequest)
		return
	}
	if job := activeControlJob(s.ID); job != nil {
		http.Error(w, "Control API 작업 진행 중: "+job.ID, http.StatusConflict)
		return
	}
	executeAt, err := time.Parse(time.RFC3339Nano, strings.TrimSpace(q.ExecuteAt))
	if err != nil {
		http.Error(w, "execute_at must be RFC3339 with timezone", http.StatusBadRequest)
		return
	}
	msg, err := createLifecycleSchedule(s, q.Action, executeAt, q.CountdownSeconds)
	if err != nil {
		w.WriteHeader(http.StatusConflict)
		writeJSON(w, map[string]any{"ok": false, "message": msg, "error": err.Error()})
		return
	}
	w.WriteHeader(http.StatusAccepted)
	writeJSON(w, map[string]any{"ok": true, "message": msg, "schedule": lifecycleScheduleStatus(s.ID)})
}

type commandReq struct {
	ID      string `json:"id"`
	Command string `json:"command"`
}

func apiCommand(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" && shuttingDown.Load() {
		http.Error(w, "전체 종료 중입니다", 409)
		return
	}
	if r.Method != "POST" {
		http.Error(w, "POST required", 405)
		return
	}
	var q commandReq
	if json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q) != nil {
		http.Error(w, "bad json", 400)
		return
	}
	if len(q.Command) == 0 || len(q.Command) > 2048 {
		http.Error(w, "invalid command", 400)
		return
	}
	s, ok := serverByID(q.ID)
	if !ok {
		http.Error(w, "unknown server", 400)
		return
	}
	pass, err := readServerProperty(resolveServerDir(s), "rcon.password")
	if err != nil || pass == "" {
		http.Error(w, "RCON password unavailable", 500)
		return
	}
	resp, err := rconCommand("127.0.0.1", s.RCONPort, pass, q.Command)
	if err != nil {
		w.WriteHeader(500)
		writeJSON(w, map[string]any{"ok": false, "error": err.Error()})
		return
	}
	writeJSON(w, map[string]any{"ok": true, "response": resp})
}

func apiAgentStart(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "POST required", 405)
		return
	}
	setAgentDesired(true)
	if r.Method != "GET" && shuttingDown.Load() {
		http.Error(w, "전체 종료 중입니다", 409)
		return
	}
	// Do not hold the HTTP request for Java/Discord startup.
	// The dashboard gets an immediate response while the watchdog performs the work.
	go func() { _, _ = startAgent() }()
	w.WriteHeader(http.StatusAccepted)
	writeJSON(w, map[string]any{"ok": true, "message": "Agent 백그라운드 시작/복구 요청됨"})
}

func serverByID(id string) (ServerConfig, bool) {
	cfg := configSnapshot()
	for _, s := range cfg.Servers {
		if s.ID == id {
			return s, true
		}
	}
	return ServerConfig{}, false
}

func initRuntimeState() {
	cfg := configSnapshot()
	desiredMu.Lock()
	defer desiredMu.Unlock()
	for _, s := range cfg.Servers {
		desiredRun[s.ID] = s.AutoStart
		serverLocks[s.ID] = &sync.Mutex{}
	}
}

func setDesired(id string, v bool) {
	desiredMu.Lock()
	if v && shuttingDown.Load() {
		v = false
	}
	desiredRun[id] = v
	desiredMu.Unlock()
}
func getDesired(id string) bool {
	desiredMu.RLock()
	defer desiredMu.RUnlock()
	return desiredRun[id]
}
func lockFor(id string) *sync.Mutex {
	desiredMu.Lock()
	defer desiredMu.Unlock()
	if serverLocks[id] == nil {
		serverLocks[id] = &sync.Mutex{}
	}
	return serverLocks[id]
}

func startupSupervisor() {
	select {
	case <-time.After(5 * time.Second):
	case <-hostQuit:
		return
	}
	if supervisionPaused.Load() {
		return
	}
	c := configSnapshot()
	setAgentDesired(c.AutoStartAgent)
	if c.AutoStartAgent {
		go func() { _, _ = startAgent() }()
	}
	for _, s := range c.Servers {
		if s.AutoStart {
			ss := s
			go func() { _, _ = startServer(ss) }()
		}
	}
	go agentWatchdog()
	go serverWatchdog()
}

func serverWatchdog() {
	t := time.NewTicker(12 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-hostQuit:
			return
		case <-t.C:
		}
		if supervisionPaused.Load() {
			continue
		}
		for _, s := range configSnapshot().Servers {
			if currentOperation(s.ID) != "" || activeControlJob(s.ID) != nil || !s.RestartOnCrash || !getDesired(s.ID) || tcpOpen("127.0.0.1", s.JavaPort, 350*time.Millisecond) || trackedServerAlive(s.ID) {
				continue
			}
			desiredMu.RLock()
			last := lastAttempt[s.ID]
			desiredMu.RUnlock()
			if time.Since(last) < 30*time.Second {
				continue
			}
			mu := lockFor(s.ID)
			if !mu.TryLock() {
				continue
			}
			go func(s ServerConfig) {
				defer mu.Unlock()
				msg, e := startServerLocked(s)
				recordResult(s.ID, "start", msg, e)
			}(s)
		}
	}
}

func markAttempt(id string) { desiredMu.Lock(); lastAttempt[id] = time.Now(); desiredMu.Unlock() }

func startServer(s ServerConfig) (string, error) {
	if shuttingDown.Load() {
		return "전체 종료 중", errors.New("shutdown in progress")
	}
	if op := currentOperation(s.ID); op != "" {
		return "다른 작업 진행 중", fmt.Errorf("operation locked: %s", op)
	}
	h := runV4Preflight(s)
	if h.Overall == "fail" {
		for _, c := range h.Checks {
			if c.Status == "fail" {
				appendV4Event("error", "preflight", s.ID, "시작 전 검사 실패", c.Label+": "+c.Message)
				return "시작 전 검사 실패: " + c.Label, errors.New(c.Message)
			}
		}
	}
	supervisionPaused.Store(false)
	clearStartupFailure(s.ID)
	setDesired(s.ID, true)
	mu := lockFor(s.ID)
	mu.Lock()
	defer mu.Unlock()
	msg, e := startServerLocked(s)
	recordResult(s.ID, "start", msg, e)
	return msg, e
}

func stopServer(s ServerConfig) (string, error) {
	setDesired(s.ID, false)
	mu := lockFor(s.ID)
	mu.Lock()
	defer mu.Unlock()
	msg, e := stopServerLocked(s)
	recordResult(s.ID, "stop", msg, e)
	return msg, e
}

func stopServerLocked(s ServerConfig) (string, error) {
	setLaunchPhase(s.ID, "stopping", s.Name+" 정상 종료 확인 중", "")
	deadline := time.Now().Add(180 * time.Second)
	sent := false
	for time.Now().Before(deadline) {
		online := tcpOpen("127.0.0.1", s.JavaPort, 300*time.Millisecond)
		if online && !sent {
			if e := rememberServerProcess(s); e != nil {
				return "서버 프로세스 확인 실패", e
			}
			pass, e := readServerProperty(resolveServerDir(s), "rcon.password")
			if e != nil || pass == "" {
				return "RCON 비밀번호를 읽지 못함", errors.New("rcon password unavailable")
			}
			if _, e = rconCommand("127.0.0.1", s.RCONPort, pass, "stop"); e != nil {
				return "stop 전송 실패", e
			}
			sent = true
			// Stop only our cmd.exe wrapper. The Java process continues saving normally;
			// this also prevents a batch 'goto restart' loop from relaunching Java.
			stopLaunchShell(s.ID)
		}
		if !online && !trackedServerAlive(s.ID) {
			if sent || !launchAlive(s.ID) {
				stopLaunchShell(s.ID)
				return s.Name + " 정상 종료", nil
			}
		}
		select {
		case <-time.After(500 * time.Millisecond):
		case <-hostQuit:
			return "Host 종료 중", errors.New("host stopped")
		}
	}
	return "서버 저장/종료가 180초 안에 끝나지 않았습니다. 강제 종료하지 않았습니다", errors.New("shutdown timeout")
}

func restartServer(s ServerConfig) (string, error) {
	if shuttingDown.Load() {
		return "전체 종료 중", errors.New("shutdown in progress")
	}
	setDesired(s.ID, false)
	mu := lockFor(s.ID)
	mu.Lock()
	defer mu.Unlock()
	if msg, e := stopServerLocked(s); e != nil {
		recordResult(s.ID, "restart", msg, e)
		return msg, e
	}
	if shuttingDown.Load() {
		return "전체 종료로 재시작 취소", errors.New("shutdown in progress")
	}
	clearStartupFailure(s.ID)
	setDesired(s.ID, true)
	msg, e := startServerLocked(s)
	recordResult(s.ID, "restart", msg, e)
	return msg, e
}

func forceStopServer(s ServerConfig) (string, error) {
	setDesired(s.ID, false)
	mu := lockFor(s.ID)
	mu.Lock()
	defer mu.Unlock()
	if runtime.GOOS != "windows" {
		return "Windows only", errors.New("unsupported")
	}

	// First kill the tracked start.bat tree when GSC launched the server. This
	// prevents restart-loop batch files from immediately spawning Java again.
	launcherKilled := false
	launcherWasAlive := launchAlive(s.ID)
	if launcherWasAlive {
		if err := forceStopLauncherTree(s.ID); err == nil {
			launcherKilled = true
			time.Sleep(250 * time.Millisecond)
		}
	}

	// Resolve the Java process using progressively broader sources. The old
	// implementation required the Java port to be open and the stats cache to
	// contain a PID, so a hung/startup-state server could not be force-stopped.
	pids := []int{}
	seen := map[int]bool{}
	addPID := func(pid int) {
		if pid > 0 && !seen[pid] {
			seen[pid] = true
			pids = append(pids, pid)
		}
	}
	if pid, err := portPID(s.JavaPort); err == nil {
		addPID(pid)
	}
	addPID(trackedServerPID(s.ID))
	refreshJavaCache()
	if js, ok := cachedJavaStats(s.JavaPort); ok {
		addPID(js.PID)
	}

	killed := []int{}
	failures := []string{}
	for _, pid := range pids {
		if err := killProcessTree(pid); err != nil {
			// A launcher-tree kill may already have terminated the same Java PID.
			// Treat a now-closed server port as success instead of surfacing a
			// misleading taskkill failure.
			if !tcpOpen("127.0.0.1", s.JavaPort, 180*time.Millisecond) {
				continue
			}
			failures = append(failures, fmt.Sprintf("PID %d: %v", pid, err))
			continue
		}
		killed = append(killed, pid)
	}

	// Give Windows a moment to release the listener, then make one final
	// listener-PID pass in case the batch wrapper relaunched Java during the
	// force-stop window.
	time.Sleep(250 * time.Millisecond)
	if pid, err := portPID(s.JavaPort); err == nil && pid > 0 && !seen[pid] {
		if err := killProcessTree(pid); err != nil {
			failures = append(failures, fmt.Sprintf("PID %d: %v", pid, err))
		} else {
			killed = append(killed, pid)
		}
	}

	if len(killed) == 0 && !launcherKilled {
		if !tcpOpen("127.0.0.1", s.JavaPort, 250*time.Millisecond) && trackedServerPID(s.ID) == 0 && !launchAlive(s.ID) {
			setLaunchPhase(s.ID, "stopped", s.Name+" 이미 OFFLINE", "")
			return s.Name + " 이미 OFFLINE", nil
		}
		if len(failures) == 0 {
			return "강제 종료 대상 PID를 찾지 못함", errors.New("force-stop target unavailable")
		}
	}
	if len(failures) > 0 && tcpOpen("127.0.0.1", s.JavaPort, 350*time.Millisecond) {
		return "강제 종료 실패: " + strings.Join(failures, " | "), errors.New("force-stop failed")
	}

	msg := s.Name + " 강제 종료 완료"
	if len(killed) > 0 {
		parts := make([]string, 0, len(killed))
		for _, pid := range killed {
			parts = append(parts, strconv.Itoa(pid))
		}
		msg += " · PID " + strings.Join(parts, ",")
	} else if launcherKilled {
		msg += " · start.bat 프로세스 트리"
	}
	setLaunchPhase(s.ID, "stopped", msg, "")
	return msg, nil
}

func forceStopLauncher(s ServerConfig) (string, error) {
	setDesired(s.ID, false)
	mu := lockFor(s.ID)
	mu.Lock()
	defer mu.Unlock()
	if err := forceStopLauncherTree(s.ID); err != nil {
		return s.Name + " start.bat 강제 종료 실패", err
	}
	setLaunchPhase(s.ID, "stopped", s.Name+" start.bat 프로세스 트리 강제 종료", "")
	return s.Name + " start.bat + 자식 프로세스 강제 종료 완료", nil
}

func agentWatchdog() {
	t := time.NewTicker(20 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-hostQuit:
			return
		case <-t.C:
		}
		if supervisionPaused.Load() || !getAgentDesired() {
			continue
		}
		c := configSnapshot()
		if _, ok := getTextURL(c.Agent.HealthURL); ok {
			continue
		}
		_, _ = startAgent()
	}
}

func startAgent() (string, error) {
	cfg := configSnapshot()
	agentStartMu.Lock()
	defer agentStartMu.Unlock()
	if shuttingDown.Load() || !getAgentDesired() {
		return "Agent 시작 취소", errors.New("agent stopped")
	}
	if cfg.Agent.HealthURL != "" {
		if _, ok := getTextURL(cfg.Agent.HealthURL); ok {
			setAgentDiag("", resolveAgentJava())
			return "Agent 이미 실행 중", nil
		}
	}
	work := strings.TrimSpace(cfg.Agent.WorkingDir)
	if work == "" {
		err := errors.New("Agent working directory unavailable")
		setAgentDiag(err.Error(), "")
		return "Agent 시작 실패", err
	}
	jar := strings.TrimSpace(cfg.Agent.JarName)
	if jar == "" {
		jar = "GeumyiStatusAgent-0.5.4.jar"
	}
	if !filepath.IsAbs(jar) {
		jar = filepath.Join(work, jar)
	}
	if _, err := os.Stat(jar); err != nil {
		setAgentDiag("Agent JAR 없음: "+jar, "")
		return "Agent JAR을 찾지 못함", err
	}
	java := resolveAgentJava()
	if java == "" {
		err := errors.New("Java 실행 파일을 찾지 못했습니다. Java 21+ 또는 서버용 Java 설치를 확인하세요.")
		setAgentDiag(err.Error(), "")
		return "Agent Java를 찾지 못함", err
	}

	if err := stopAgentLocked(); err != nil {
		return "기존 Agent 확인 실패", err
	}
	pidFile := filepath.Join(work, "agent.pid")

	logDir := filepath.Join(work, "logs")
	_ = os.MkdirAll(logDir, 0755)
	logPath := filepath.Join(logDir, "agent-console.log")
	logf, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		setAgentDiag("Agent 로그 열기 실패: "+err.Error(), java)
		return "Agent 시작 실패", err
	}
	cmd := exec.Command(java, "-Dfile.encoding=UTF-8", "-jar", filepath.Base(jar), "agent.properties")
	cmd.Dir = work
	cmd.Stdout = logf
	cmd.Stderr = logf
	hideProcess(cmd)
	if err := cmd.Start(); err != nil {
		_ = logf.Close()
		setAgentDiag("Agent 프로세스 시작 실패: "+err.Error(), java)
		return "Agent 시작 실패", err
	}
	_ = os.WriteFile(pidFile, []byte(strconv.Itoa(cmd.Process.Pid)), 0600)
	activeAgent = cmd.Process
	setAgentDiag("Agent 기동 확인 중", java)
	go func() {
		_ = cmd.Wait()
		_ = logf.Close()
	}()

	deadline := time.Now().Add(25 * time.Second)
	for time.Now().Before(deadline) {
		if shuttingDown.Load() || !getAgentDesired() {
			_ = cmd.Process.Kill()
			return "Agent 시작 취소", errors.New("agent stopped")
		}
		if _, ok := getTextURL(cfg.Agent.HealthURL); ok {
			setAgentDiag("", java)
			return fmt.Sprintf("Agent ONLINE · PID %d", cmd.Process.Pid), nil
		}
		time.Sleep(700 * time.Millisecond)
	}
	tail := tailAgentLog(logPath, 8)
	err = errors.New("Agent가 시작됐지만 /health 응답이 없습니다")
	if tail != "" {
		err = fmt.Errorf("%w · 최근 로그: %s", err, tail)
	}
	setAgentDiag(err.Error(), java)
	return "Agent 시작 후 health 확인 실패 (로그: " + logPath + ")", err
}

func setAgentDiag(errText, java string) {
	agentMu.Lock()
	lastAgentErr = errText
	if java != "" {
		lastAgentJava = java
	}
	agentMu.Unlock()
}

func resolveAgentJava() string {
	r, e := javaruntime.Resolve(configSnapshot().Agent.JavaPath)
	if e != nil {
		setAgentDiag(e.Error(), "")
		return ""
	}
	return r.Executable
}

func tailAgentLog(path string, lines int) string {
	b, err := tailFile(path, lines)
	if err != nil || len(b) == 0 {
		return ""
	}
	s := strings.ReplaceAll(strings.TrimSpace(string(b)), "\r", "")
	s = strings.ReplaceAll(s, "\n", " | ")
	if len(s) > 700 {
		s = s[len(s)-700:]
	}
	return s
}

func envValue(env []string, key string) string {
	prefix := strings.ToUpper(key) + "="
	for _, kv := range env {
		if strings.HasPrefix(strings.ToUpper(kv), prefix) {
			if i := strings.IndexByte(kv, '='); i >= 0 {
				return kv[i+1:]
			}
		}
	}
	return ""
}

func setEnvValue(env []string, key, value string) []string {
	prefix := strings.ToUpper(key) + "="
	out := make([]string, 0, len(env)+1)
	replaced := false
	for _, kv := range env {
		if strings.HasPrefix(strings.ToUpper(kv), prefix) {
			if !replaced {
				out = append(out, key+"="+value)
				replaced = true
			}
			continue
		}
		out = append(out, kv)
	}
	if !replaced {
		out = append(out, key+"="+value)
	}
	return out
}

func pathListContains(list, want string) bool {
	want = strings.TrimSpace(strings.TrimRight(want, `\/`))
	for _, p := range filepath.SplitList(list) {
		p = strings.TrimSpace(strings.TrimRight(p, `\/`))
		if strings.EqualFold(p, want) {
			return true
		}
	}
	return false
}

func configuredServerDir(s ServerConfig) string {
	if p := strings.TrimSpace(s.Path); p != "" {
		return filepath.Clean(os.ExpandEnv(p))
	}
	if s.PathFile != "" {
		if b, err := os.ReadFile(os.ExpandEnv(s.PathFile)); err == nil {
			p := strings.TrimSpace(strings.TrimPrefix(string(b), "\ufeff"))
			if p != "" {
				return filepath.Clean(os.ExpandEnv(p))
			}
		}
	}
	return ""
}

func resolveServerDir(s ServerConfig) string {
	d := configuredServerDir(s)
	if validServerDir(d, s.JavaPort) {
		return d
	}
	return ""
}

// validServerDir intentionally validates the server folder itself, not the
// configured Java port. v4.0.2 coupled those two checks, so a perfectly valid
// selected folder disappeared from the UI whenever server.properties used a
// different port than the profile. Port mismatches are now reported separately
// by the v4 health/preflight checks instead of erasing the saved path.
func validServerDir(dir string, port int) bool {
	if strings.TrimSpace(dir) == "" {
		return false
	}
	st, err := os.Stat(dir)
	if err != nil || !st.IsDir() {
		return false
	}
	_, err = os.Stat(filepath.Join(dir, "server.properties"))
	return err == nil
}

func readServerProperty(dir, key string) (string, error) {
	if dir == "" {
		return "", errors.New("server dir not found")
	}
	f, err := os.Open(filepath.Join(dir, "server.properties"))
	if err != nil {
		return "", err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		ln := strings.TrimSpace(strings.TrimPrefix(sc.Text(), "\ufeff"))
		if strings.HasPrefix(ln, "#") || !strings.Contains(ln, "=") {
			continue
		}
		p := strings.SplitN(ln, "=", 2)
		if strings.TrimSpace(p[0]) == key {
			return strings.TrimSpace(p[1]), nil
		}
	}
	return "", sc.Err()
}

func getServerStatus(s ServerConfig) ServerStatus {
	st := ServerStatus{ID: s.ID, Name: s.Name}
	st.JavaPortOpen = tcpOpen("127.0.0.1", s.JavaPort, 400*time.Millisecond)
	st.Online = st.JavaPortOpen

	// Do not probe RCON with net.Dial here. Minecraft logs every TCP connect to
	// the RCON listener, so status polling must remain passive. Prefer the
	// background process cache, but fall back to the native Windows TCP table
	// Native TCP listener enumeration avoids shell/CIM probes under a service account.
	refreshJavaCache()
	st.RCONPortOpen = cachedTCPListener(s.RCONPort) || nativeTCPListener(s.RCONPort)

	st.BedrockUDPListening = udpListening(s.BedrockPort)
	st.GDSAPIOnline = httpOK(fmt.Sprintf("http://127.0.0.1:%d/health", s.GDSAPIPort))
	if st.JavaPortOpen {
		st.MC = queryMinecraft("127.0.0.1", s.JavaPort)
	}
	if js, ok := cachedJavaStats(s.JavaPort); ok {
		st.Java = js
	} else if js, ok := nativeJavaStats(s.JavaPort); ok {
		// Native fallback keeps PID/RAM visible even when PowerShell/CIM telemetry
		// is unavailable to the Windows service account.
		st.Java = js
	}
	st.ConfiguredDir = configuredServerDir(s)
	st.Dir = resolveServerDir(s)
	st.DirValid = st.Dir != ""
	if st.Dir != "" {
		fillFileMeta(&st)
		reconcileConfiguredMaxPlayers(st.Dir, &st.MC)
	}
	st.DesiredRunning = getDesired(s.ID)
	st.RestartOnCrash = s.RestartOnCrash
	st.Launch = launchStatus(s.ID)
	st.LauncherRunning = launchAlive(s.ID)
	st.Schedule = lifecycleScheduleStatus(s.ID)
	st.State = deriveServerState(s, st)
	return st
}

func reconcileConfiguredMaxPlayers(dir string, mc *MCStatus) {
	if mc == nil || strings.TrimSpace(dir) == "" {
		return
	}
	raw, err := readServerProperty(dir, "max-players")
	if err != nil {
		return
	}
	n, err := strconv.Atoi(strings.TrimSpace(raw))
	if err != nil || n <= 0 {
		return
	}
	mc.ConfiguredMax = n
	if !mc.OK {
		return
	}
	mc.ReportedMax = mc.Max
	// server.properties is the authoritative local configuration. Prefer it
	// when the server-list status response disagrees. Keep the reported value
	// in JSON so diagnostics can explain the mismatch instead of hiding it.
	mc.Max = n
	if mc.ReportedMax != 0 && mc.ReportedMax != n {
		mc.MaxSource = "server.properties (status mismatch)"
	} else {
		mc.MaxSource = "server.properties"
	}
}

func fillFileMeta(st *ServerStatus) {
	ents, _ := os.ReadDir(st.Dir)
	worlds := []string{}
	paper := ""
	for _, e := range ents {
		if e.IsDir() {
			if _, err := os.Stat(filepath.Join(st.Dir, e.Name(), "level.dat")); err == nil {
				worlds = append(worlds, e.Name())
			}
		} else if strings.HasPrefix(strings.ToLower(e.Name()), "paper") && strings.HasSuffix(strings.ToLower(e.Name()), ".jar") {
			paper = e.Name()
		}
	}
	sort.Strings(worlds)
	st.Worlds = worlds
	st.WorldCount = len(worlds)
	st.PaperJar = paper
	if pp := filepath.Join(st.Dir, "plugins"); true {
		if pe, err := os.ReadDir(pp); err == nil {
			for _, e := range pe {
				if !e.IsDir() && strings.HasSuffix(strings.ToLower(e.Name()), ".jar") {
					st.PluginCount++
				}
			}
		}
	}
	lp := filepath.Join(st.Dir, "logs", "latest.log")
	if info, err := os.Stat(lp); err == nil {
		st.LogSizeBytes = info.Size()
		st.LogAgeSeconds = int64(time.Since(info.ModTime()).Seconds())
		if b, err := tailFile(lp, 500); err == nil {
			for _, ln := range strings.Split(string(b), "\n") {
				u := strings.ToUpper(ln)
				if strings.Contains(u, "WARN") {
					st.WarnCount++
				}
				if strings.Contains(u, "ERROR") || strings.Contains(u, "SEVERE") {
					st.ErrorCount++
				}
			}
		}
	}
}

func tcpOpen(host string, port int, timeout time.Duration) bool {
	if port <= 0 {
		return false
	}
	c, err := net.DialTimeout("tcp", net.JoinHostPort(host, strconv.Itoa(port)), timeout)
	if err != nil {
		return false
	}
	_ = c.Close()
	return true
}
func httpOK(url string) bool {
	if url == "" {
		return false
	}
	ctx, cancel := context.WithTimeout(context.Background(), 700*time.Millisecond)
	defer cancel()
	req, _ := http.NewRequestWithContext(ctx, "GET", url, nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	return resp.StatusCode >= 200 && resp.StatusCode < 500
}
func getTextURL(url string) (string, bool) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	req, _ := http.NewRequestWithContext(ctx, "GET", url, nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", false
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	return strings.TrimSpace(string(b)), resp.StatusCode >= 200 && resp.StatusCode < 300
}
func getJSONURL(url string) (any, bool) {
	if url == "" {
		return nil, false
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	req, _ := http.NewRequestWithContext(ctx, "GET", url, nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, false
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, false
	}
	var v any
	if json.NewDecoder(io.LimitReader(resp.Body, 4<<20)).Decode(&v) != nil {
		return nil, false
	}
	return v, true
}

func udpListening(port int) bool {
	if port <= 0 {
		return false
	}
	statusMu.Lock()
	v := udpCache[port]
	stale := udpCacheAt.IsZero() || time.Since(udpCacheAt) > 5*time.Second
	statusMu.Unlock()
	if stale {
		refreshUDPCacheAsync()
	}
	return v
}

// startStatusTelemetry keeps slow Windows probes off HTTP request goroutines.
// The dashboard may poll every few seconds; a slow PowerShell/CIM query must
// never be able to hold /api/status open until the Client proxy times out.
func startStatusTelemetry() {
	refreshHostStatsAsync()
	refreshJavaCache()
	refreshUDPCacheAsync()
	go func() {
		t := time.NewTicker(4 * time.Second)
		defer t.Stop()
		for {
			select {
			case <-hostQuit:
				return
			case <-t.C:
				refreshHostStatsAsync()
				refreshJavaCache()
				refreshUDPCacheAsync()
			}
		}
	}()
}

func refreshUDPCacheAsync() {
	if runtime.GOOS != "windows" || !udpRefreshInFlight.CompareAndSwap(false, true) {
		return
	}
	go func() {
		defer udpRefreshInFlight.Store(false)
		c := configSnapshot()
		result := make(map[int]bool)
		for _, srv := range c.Servers {
			if srv.BedrockPort > 0 {
				result[srv.BedrockPort] = nativeUDPListener(srv.BedrockPort)
			}
		}
		statusMu.Lock()
		udpCache = result
		udpCacheAt = time.Now()
		statusMu.Unlock()
	}()
}

func refreshJavaCache() {
	statusMu.Lock()
	fresh := !javaCacheAt.IsZero() && time.Since(javaCacheAt) < 5*time.Second
	statusMu.Unlock()
	if fresh || runtime.GOOS != "windows" || !javaRefreshInFlight.CompareAndSwap(false, true) {
		return
	}
	go func() {
		defer javaRefreshInFlight.Store(false)
		c := configSnapshot()
		result := map[int]JavaStats{}
		seenPorts := map[int]bool{}
		for _, srv := range c.Servers {
			for _, port := range []int{srv.JavaPort, srv.RCONPort} {
				if port <= 0 || seenPorts[port] {
					continue
				}
				seenPorts[port] = true
				if st, ok := nativeJavaStats(port); ok {
					result[port] = st
				}
			}
		}
		statusMu.Lock()
		javaCache = result
		javaCacheAt = time.Now()
		statusMu.Unlock()
	}()
}

func num(v any) float64 {
	switch x := v.(type) {
	case float64:
		return x
	case json.Number:
		f, _ := x.Float64()
		return f
	case string:
		f, _ := strconv.ParseFloat(x, 64)
		return f
	}
	return 0
}

func getHostStats() HostStats {
	statusMu.Lock()
	h := cachedHost
	stale := cachedHostAt.IsZero() || time.Since(cachedHostAt) > 8*time.Second
	statusMu.Unlock()
	if h.Hostname == "" {
		h = HostStats{OS: runtime.GOOS + "/" + runtime.GOARCH}
		h.Hostname, _ = os.Hostname()
		h.IPv4 = localIPs()
	}
	if stale {
		refreshHostStatsAsync()
	}
	return h
}

func refreshHostStatsAsync() {
	if !hostRefreshInFlight.CompareAndSwap(false, true) {
		return
	}
	go func() {
		defer hostRefreshInFlight.Store(false)
		h := HostStats{OS: runtime.GOOS + "/" + runtime.GOARCH}
		h.Hostname, _ = os.Hostname()
		h.IPv4 = localIPs()
		if runtime.GOOS == "windows" {
			if n, ok := nativeHostStats(); ok {
				h.CPUPercent = n.CPUPercent
				h.RAMUsedGB = n.RAMUsedGB
				h.RAMTotalGB = n.RAMTotalGB
				h.DiskFreeGB = n.DiskFreeGB
				h.DiskTotalGB = n.DiskTotalGB
				h.Uptime = n.Uptime
			}
		}
		statusMu.Lock()
		cachedHost = h
		cachedHostAt = time.Now()
		statusMu.Unlock()
	}()
}

func localIPs() []string {
	out := []string{}
	ifs, _ := net.Interfaces()
	for _, i := range ifs {
		addrs, _ := i.Addrs()
		for _, a := range addrs {
			ip, _, _ := net.ParseCIDR(a.String())
			if ip != nil && ip.To4() != nil && !ip.IsLoopback() {
				out = append(out, ip.String())
			}
		}
	}
	return out
}
func formatDuration(d time.Duration) string {
	if d < 0 {
		d = 0
	}
	days := int(d.Hours()) / 24
	h := int(d.Hours()) % 24
	m := int(d.Minutes()) % 60
	return fmt.Sprintf("%dd %dh %dm", days, h, m)
}

func tailFile(path string, n int) ([]byte, error) {
	if n <= 0 {
		return []byte{}, nil
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		return nil, err
	}
	if st.Size() == 0 {
		return []byte{}, nil
	}
	// latest.log can grow very large. The old implementation scanned it from
	// byte 0 on every 5-second dashboard refresh, eventually making /api/status
	// exceed the Client's response-header timeout. Read only a bounded tail and
	// expand backwards until enough lines are available.
	const minChunk int64 = 256 << 10
	const maxTail int64 = 16 << 20
	want := minChunk
	if st.Size() < want {
		want = st.Size()
	}
	var data []byte
	for {
		start := st.Size() - want
		data = make([]byte, want)
		read, e := f.ReadAt(data, start)
		if e != nil && e != io.EOF {
			return nil, e
		}
		data = data[:read]
		if bytes.Count(data, []byte{'\n'}) >= n || start == 0 || want >= maxTail {
			break
		}
		want *= 2
		if want > maxTail {
			want = maxTail
		}
		if want > st.Size() {
			want = st.Size()
		}
	}
	lines := bytes.Split(data, []byte{'\n'})
	if len(lines) > 0 && len(lines[len(lines)-1]) == 0 {
		lines = lines[:len(lines)-1]
	}
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return bytes.Join(lines, []byte{'\n'}), nil
}

// Minecraft Java status protocol.
func queryMinecraft(host string, port int) MCStatus {
	st := MCStatus{}
	start := time.Now()
	c, err := net.DialTimeout("tcp", net.JoinHostPort(host, strconv.Itoa(port)), 1200*time.Millisecond)
	if err != nil {
		return st
	}
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(2 * time.Second))
	var payload bytes.Buffer
	writeVarInt(&payload, 0)
	writeVarInt(&payload, 776)
	writeVarInt(&payload, len(host))
	payload.WriteString(host)
	_ = binary.Write(&payload, binary.BigEndian, uint16(port))
	writeVarInt(&payload, 1)
	sendPacket(c, payload.Bytes())
	sendPacket(c, []byte{0})
	br := bufio.NewReader(c)
	_, err = readVarInt(br)
	if err != nil {
		return st
	}
	pid, err := readVarInt(br)
	if err != nil || pid != 0 {
		return st
	}
	ln, err := readVarInt(br)
	if err != nil || ln < 0 || ln > 2<<20 {
		return st
	}
	b := make([]byte, ln)
	if _, err = io.ReadFull(br, b); err != nil {
		return st
	}
	var raw struct {
		Version struct {
			Name     string `json:"name"`
			Protocol int    `json:"protocol"`
		} `json:"version"`
		Players struct {
			Max    int `json:"max"`
			Online int `json:"online"`
			Sample []struct {
				Name string `json:"name"`
			} `json:"sample"`
		} `json:"players"`
		Description any `json:"description"`
	}
	if json.Unmarshal(b, &raw) != nil {
		return st
	}
	st.OK = true
	st.Version = raw.Version.Name
	st.Protocol = raw.Version.Protocol
	st.Max = raw.Players.Max
	st.Online = raw.Players.Online
	for _, p := range raw.Players.Sample {
		st.Players = append(st.Players, p.Name)
	}
	st.MOTD = flattenMOTD(raw.Description)
	st.LatencyMS = time.Since(start).Milliseconds()
	return st
}
func sendPacket(w io.Writer, p []byte) {
	var b bytes.Buffer
	writeVarInt(&b, len(p))
	b.Write(p)
	_, _ = w.Write(b.Bytes())
}
func writeVarInt(w io.Writer, v int) {
	u := uint32(v)
	for {
		if u&^0x7F == 0 {
			_, _ = w.Write([]byte{byte(u)})
			return
		}
		_, _ = w.Write([]byte{byte(u&0x7F | 0x80)})
		u >>= 7
	}
}
func readVarInt(r io.ByteReader) (int, error) {
	num := 0
	res := 0
	for {
		b, err := r.ReadByte()
		if err != nil {
			return 0, err
		}
		res |= int(b&0x7F) << (7 * num)
		num++
		if num > 5 {
			return 0, errors.New("varint too big")
		}
		if b&0x80 == 0 {
			return res, nil
		}
	}
}
func flattenMOTD(v any) string {
	switch x := v.(type) {
	case string:
		return x
	case map[string]any:
		s := fmt.Sprint(x["text"])
		if ex, ok := x["extra"].([]any); ok {
			for _, e := range ex {
				s += flattenMOTD(e)
			}
		}
		return s
	case []any:
		s := ""
		for _, e := range x {
			s += flattenMOTD(e)
		}
		return s
	}
	return ""
}

// RCON.
func rconCommand(host string, port int, password, command string) (string, error) {
	c, err := net.DialTimeout("tcp", net.JoinHostPort(host, strconv.Itoa(port)), 2*time.Second)
	if err != nil {
		return "", err
	}
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(5 * time.Second))
	if err = writeRCON(c, 100, 3, password); err != nil {
		return "", err
	}
	authenticated := false
	for i := 0; i < 4; i++ {
		id, typ, _, e := readRCON(c)
		if e != nil {
			return "", e
		}
		if id == -1 {
			return "", errors.New("RCON authentication failed")
		}
		if id == 100 && typ == 2 {
			authenticated = true
			break
		}
	}
	if !authenticated {
		return "", errors.New("RCON authentication response missing")
	}
	if err = writeRCON(c, 101, 2, command); err != nil {
		return "", err
	}
	if strings.EqualFold(strings.TrimSpace(command), "stop") {
		return "stop 전송 완료", nil
	}
	_, _, body, err := readRCON(c)
	return body, err
}
func writeRCON(w io.Writer, id, typ int32, body string) error {
	bb := []byte(body)
	ln := int32(4 + 4 + len(bb) + 2)
	buf := new(bytes.Buffer)
	_ = binary.Write(buf, binary.LittleEndian, ln)
	_ = binary.Write(buf, binary.LittleEndian, id)
	_ = binary.Write(buf, binary.LittleEndian, typ)
	buf.Write(bb)
	buf.Write([]byte{0, 0})
	_, err := w.Write(buf.Bytes())
	return err
}
func readRCON(r io.Reader) (int32, int32, string, error) {
	var ln int32
	if err := binary.Read(r, binary.LittleEndian, &ln); err != nil {
		return 0, 0, "", err
	}
	if ln < 10 || ln > 1<<20 {
		return 0, 0, "", errors.New("invalid RCON packet")
	}
	b := make([]byte, ln)
	if _, err := io.ReadFull(r, b); err != nil {
		return 0, 0, "", err
	}
	id := int32(binary.LittleEndian.Uint32(b[0:4]))
	typ := int32(binary.LittleEndian.Uint32(b[4:8]))
	body := string(bytes.TrimRight(b[8:len(b)-2], "\x00"))
	return id, typ, body, nil
}

//go:embed dashboard.html
var dashboardHTML string

func serveDashboard(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = io.WriteString(w, dashboardHTML)
}
