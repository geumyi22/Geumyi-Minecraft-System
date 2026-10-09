package main

import (
	"archive/zip"
	"bufio"
	"encoding/json"
	"fmt"
	"geumyi/servercenter/internal/javaruntime"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

type V4Event struct {
	Seq      uint64 `json:"seq"`
	Time     string `json:"time"`
	Level    string `json:"level"`
	Category string `json:"category"`
	ServerID string `json:"server_id,omitempty"`
	Message  string `json:"message"`
	Detail   string `json:"detail,omitempty"`
}

type V4Check struct {
	Key     string `json:"key"`
	Label   string `json:"label"`
	Status  string `json:"status"` // ok|warn|fail
	Message string `json:"message"`
}

type V4Health struct {
	ServerID    string          `json:"server_id"`
	Overall     string          `json:"overall"`
	Checks      []V4Check       `json:"checks"`
	Bridge      map[string]any  `json:"bridge,omitempty"`
	ServerTools *GSTDiagnostics `json:"server_tools,omitempty"`
	Operation   string          `json:"operation,omitempty"`
	Updated     string          `json:"updated"`
}

type PluginInventory struct {
	File    string `json:"file"`
	Name    string `json:"name"`
	Version string `json:"version"`
	Size    int64  `json:"size"`
	Managed bool   `json:"managed"`
	Enabled bool   `json:"enabled"`
}

type DatapackInventory struct {
	File        string `json:"file"`
	Format      int    `json:"pack_format"`
	Description string `json:"description"`
	Size        int64  `json:"size"`
	Enabled     bool   `json:"enabled"`
}

type ResourcePackInventory struct {
	JavaURL     string   `json:"java_url"`
	JavaSHA1    string   `json:"java_sha1"`
	Required    string   `json:"required"`
	GeyserPacks []string `json:"geyser_packs"`
}

var (
	v4Seq        atomic.Uint64
	v4EventMu    sync.Mutex
	v4OpMu       sync.Mutex
	v4Operations = map[string]string{}
)

func v4Root() string              { return filepath.Dir(configPath) }
func v4EventsPath() string        { return filepath.Join(v4Root(), "events", "host-events.jsonl") }
func v4ManagedPluginsDir() string { return filepath.Join(v4Root(), "ManagedPlugins") }

func initV4Runtime() {
	_ = os.MkdirAll(filepath.Join(v4Root(), "events"), 0755)
	_ = os.MkdirAll(filepath.Join(v4Root(), "metrics"), 0755)
	_ = os.MkdirAll(filepath.Join(v4Root(), "Backups"), 0755)
	_ = os.MkdirAll(filepath.Join(v4Root(), "Checkpoints"), 0755)
	_ = os.MkdirAll(v4ManagedPluginsDir(), 0755)
	appendV4Event("info", "host", "", "GSC v4 Host 시작", "")
}

func appendV4Event(level, category, serverID, message, detail string) {
	e := V4Event{Seq: v4Seq.Add(1), Time: time.Now().Format(time.RFC3339Nano), Level: level, Category: category, ServerID: serverID, Message: message, Detail: detail}
	b, _ := json.Marshal(e)
	v4EventMu.Lock()
	p := v4EventsPath()
	_ = os.MkdirAll(filepath.Dir(p), 0755)
	if st, err := os.Stat(p); err == nil && st.Size() > 8<<20 {
		_ = os.Rename(p, p+".1")
	}
	if f, err := os.OpenFile(p, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644); err == nil {
		_, _ = f.Write(append(b, '\n'))
		_ = f.Close()
	}
	v4EventMu.Unlock()

	// WebSocket clients are external consumers and may be slow. Never hold the
	// event-file mutex while publishing to them.
	wsPublish("event", e)
}

func recentV4Events(limit int, serverID string) []V4Event {
	if limit <= 0 || limit > 1000 {
		limit = 200
	}
	b, err := os.ReadFile(v4EventsPath())
	if err != nil {
		return nil
	}
	lines := strings.Split(strings.TrimSpace(string(b)), "\n")
	out := make([]V4Event, 0, limit)
	for i := len(lines) - 1; i >= 0 && len(out) < limit; i-- {
		var e V4Event
		if json.Unmarshal([]byte(lines[i]), &e) == nil && (serverID == "" || e.ServerID == serverID) {
			out = append(out, e)
		}
	}
	for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
		out[i], out[j] = out[j], out[i]
	}
	return out
}

func currentOperation(id string) string {
	v4OpMu.Lock()
	defer v4OpMu.Unlock()
	return v4Operations[id]
}
func beginV4Operation(id, name string) (func(), error) {
	if job := activeControlJob(id); job != nil {
		return nil, fmt.Errorf("%s Control API 작업 진행 중: %s", id, job.ID)
	}
	v4OpMu.Lock()
	if x := v4Operations[id]; x != "" {
		v4OpMu.Unlock()
		return nil, fmt.Errorf("%s 작업 진행 중: %s", id, x)
	}
	v4Operations[id] = name
	v4OpMu.Unlock()
	appendV4Event("info", "operation", id, "작업 시작: "+name, "")
	return func() {
		v4OpMu.Lock()
		delete(v4Operations, id)
		v4OpMu.Unlock()
		appendV4Event("info", "operation", id, "작업 종료: "+name, "")
	}, nil
}

func registerV4Routes(mux *http.ServeMux) {
	mux.HandleFunc("/api/v4/health", requireAuth(apiV4Health))
	mux.HandleFunc("/api/v4/events", requireAuth(apiV4Events))
	mux.HandleFunc("/api/v4/fs", requireAuth(apiV4Filesystem))
	mux.HandleFunc("/api/v4/server-profile", requireAuth(apiV4ServerProfile))
	mux.HandleFunc("/api/v4/server-catalog", requireAuth(apiV4ServerCatalog))
	mux.HandleFunc("/api/v4/player-location", requireAuth(apiV4PlayerLocation))
	mux.HandleFunc("/api/v4/network/player-location", loopbackOnly(apiV4PlayerLocation))
	mux.HandleFunc("/api/v4/network/server-state", loopbackOnly(apiV4NetworkServerState))
	mux.HandleFunc("/api/v4/network/entry-status", requireAuth(apiV4NetworkEntryStatus))
	mux.HandleFunc("/api/v4/inventory", requireAuth(apiV4Inventory))
	mux.HandleFunc("/api/v4/companion/sync", requireAuth(apiV4CompanionSync))
	mux.HandleFunc("/api/v4/maintain/toggle", requireAuth(apiV4MaintainToggle))
	mux.HandleFunc("/api/v4/backup", requireAuth(apiV4Backup))
	mux.HandleFunc("/api/v4/backups", requireAuth(apiV4Backups))
	mux.HandleFunc("/api/v4/restore", requireAuth(apiV4Restore))
	mux.HandleFunc("/api/v4/backup/verify", requireAuth(apiV4BackupVerify))
	mux.HandleFunc("/api/v4/restore/preflight", requireAuth(apiV4RestorePreflight))
	mux.HandleFunc("/api/v4/backup/action", requireAuth(apiV4BackupAction))
	mux.HandleFunc("/api/v4/backup/retention/dry-run", requireAuth(apiV4BackupRetentionDryRun))
	mux.HandleFunc("/api/v4/backup/retention/apply", requireAuth(apiV4BackupRetentionApply))
	mux.HandleFunc("/api/v4/backups/trash", requireAuth(apiV4BackupTrash))
	mux.HandleFunc("/api/v4/metrics", requireAuth(apiV4Metrics))
	mux.HandleFunc("/api/v4/automations", requireAuth(apiV4Automations))
	mux.HandleFunc("/api/v4/pairing/code", requireAuth(apiV4PairingCode))
	mux.HandleFunc("/api/v4/pairing/claim", apiV4PairingClaim)
	mux.HandleFunc("/api/v4/devices", requireAuth(apiV4Devices))
	mux.HandleFunc("/api/v4/system", requireAuth(apiV4System))
	registerUpdateRoutes(mux)
}

func apiV4Events(w http.ResponseWriter, r *http.Request) {
	n, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	writeJSON(w, map[string]any{"events": recentV4Events(n, r.URL.Query().Get("id"))})
}

func runV4Preflight(s ServerConfig) V4Health {
	checks := []V4Check{}
	add := func(k, l, st, msg string) { checks = append(checks, V4Check{k, l, st, msg}) }
	configuredDir := configuredServerDir(s)
	dir := resolveServerDir(s)
	if configuredDir == "" {
		add("path", "서버 폴더", "fail", "서버 폴더가 설정되지 않았습니다")
	} else if st, e := os.Stat(configuredDir); e != nil || !st.IsDir() {
		add("path", "서버 폴더", "fail", "설정은 저장되어 있지만 폴더를 찾을 수 없습니다: "+configuredDir)
	} else {
		add("path", "서버 폴더", "ok", configuredDir)
	}
	if configuredDir != "" {
		if _, e := os.Stat(filepath.Join(configuredDir, "server.properties")); e != nil {
			add("properties", "server.properties", "fail", "server.properties 없음")
		} else {
			add("properties", "server.properties", "ok", "확인됨")
			// Day12 fixed private Paper profiles must not launch after a
			// configuration drift to wildcard/public Java bind addresses.
			// This is preventative only: runtime listener/RCON gates remain separate.
			if bindStatus, bindMessage, check := day12ManagedJavaBindGuard(s, configuredDir); check {
				add("private_java_bind_config", "내부 Java 루프백 설정", bindStatus, bindMessage)
			}
			if v, e := readServerProperty(configuredDir, "server-port"); e == nil && strings.TrimSpace(v) != "" {
				if actual, e := strconv.Atoi(strings.TrimSpace(v)); e == nil && s.JavaPort > 0 && actual != s.JavaPort {
					add("server_port", "Java 포트 일치", "warn", fmt.Sprintf("server.properties=%d · GSC 프로필=%d — 모니터링 포트를 맞춰주세요", actual, s.JavaPort))
				} else if e == nil {
					add("server_port", "Java 포트 일치", "ok", fmt.Sprintf("%d", actual))
				}
			}
			role := normalizeServerConfig(s).Role
			if role == serverRoleWild || role == serverRolePlayground || role == serverRoleOther {
				v, e := readServerProperty(configuredDir, "accepts-transfers")
				if e != nil || !strings.EqualFold(strings.TrimSpace(v), "true") {
					add("accepts_transfers", "Lobby 전송 허용", "warn", "Day-10 backend는 accepts-transfers=true가 필요합니다 · 자동 변경하지 않았습니다")
				} else {
					add("accepts_transfers", "Lobby 전송 허용", "ok", "accepts-transfers=true")
				}
			}
		}
	}
	if dir != "" {
		cmd := strings.TrimSpace(s.StartCommand)
		if cmd == "" {
			cmd = "start.bat"
		}
		_, actual, launchErr := resolveLaunch(cmd, dir)
		if launchErr != nil {
			add("start", "시작 파일/명령", "fail", launchErr.Error())
		} else if actual != "" {
			add("start", "시작 파일", "ok", actual)
		} else {
			add("start", "시작 명령", "ok", cmd)
		}
	}
	jr, e := javaruntime.Resolve("")
	if e != nil {
		add("java", "Java", "warn", e.Error())
	} else {
		add("java", "Java", "ok", jr.Version+" · "+jr.Executable)
	}
	if s.JavaPort > 0 {
		open := tcpOpen("127.0.0.1", s.JavaPort, 250*time.Millisecond)
		if open && !getDesired(s.ID) && !cachedTCPListener(s.JavaPort) {
			add("port", "Java 포트", "warn", fmt.Sprintf("%d 포트가 다른 프로세스에서 사용 중일 수 있습니다", s.JavaPort))
		} else {
			add("port", "Java 포트", "ok", fmt.Sprintf("%d", s.JavaPort))
		}
	}
	if dir != "" {
		if st, e := os.Stat(filepath.Join(dir, "plugins")); e == nil && st.IsDir() {
			add("plugins", "Plugins", "ok", "플러그인 폴더 확인됨")
		} else {
			add("plugins", "Plugins", "warn", "plugins 폴더 없음")
		}
	}
	bridge := bridgeV4Status(s)
	if bridge != nil {
		add("bridge", "GSC Bridge", "ok", fmt.Sprint(bridge["plugin_version"]))
	} else if tcpOpen("127.0.0.1", s.JavaPort, 200*time.Millisecond) {
		add("bridge", "GSC Bridge", "warn", "서버는 실행 중이지만 GeumyiDiscordStatus v4 API 응답 없음")
	} else {
		add("bridge", "GSC Bridge", "ok", "서버 오프라인")
	}
	gst := readGSTDiagnostics(s)
	serverOnline := tcpOpen("127.0.0.1", s.JavaPort, 200*time.Millisecond)
	if gst.Available {
		status := "ok"
		msg := fmt.Sprintf("v%s · %s", gst.Version, gst.Grade)
		if !serverOnline {
			msg += " · 서버 오프라인 / 마지막 진단값"
		} else if gst.Stale {
			status = "warn"
			msg += fmt.Sprintf(" · telemetry stale %.0fs", gst.AgeSeconds)
		} else if gst.Grade == "DEGRADED" || gst.Grade == "CRITICAL" {
			status = "warn"
		}
		add("servertools", "ServerTools Diagnostics", status, msg)
	} else if serverOnline && gst.Installed {
		add("servertools", "ServerTools Diagnostics", "warn", "GeumyiServerTools는 감지됐지만 Diagnostics v2 응답 파일이 없습니다")
	} else if serverOnline && !gst.Installed {
		add("servertools", "ServerTools Diagnostics", "warn", "GeumyiServerTools가 감지되지 않았습니다")
	} else {
		add("servertools", "ServerTools Diagnostics", "ok", "서버 오프라인")
	}
	overall := "ok"
	for _, c := range checks {
		if c.Status == "fail" {
			overall = "fail"
			break
		}
		if c.Status == "warn" && overall == "ok" {
			overall = "warn"
		}
	}
	return V4Health{ServerID: s.ID, Overall: overall, Checks: checks, Bridge: bridge, ServerTools: &gst, Operation: currentOperation(s.ID), Updated: time.Now().Format(time.RFC3339)}
}

func apiV4Health(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Query().Get("id")
	if id != "" {
		s, ok := serverByID(id)
		if !ok {
			http.Error(w, "unknown server", 400)
			return
		}
		writeJSON(w, runV4Preflight(s))
		return
	}
	c := configSnapshot()
	out := make([]V4Health, 0, len(c.Servers))
	for _, s := range c.Servers {
		out = append(out, runV4Preflight(s))
	}
	writeJSON(w, map[string]any{"servers": out})
}

func bridgeV4Status(s ServerConfig) map[string]any {
	if s.GDSAPIPort <= 0 {
		return nil
	}
	c := http.Client{Timeout: 700 * time.Millisecond}
	resp, err := c.Get(fmt.Sprintf("http://127.0.0.1:%d/api/v4/status", s.GDSAPIPort))
	if err != nil {
		return nil
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		return nil
	}
	var m map[string]any
	if json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&m) != nil {
		return nil
	}
	return m
}

func apiV4Filesystem(w http.ResponseWriter, r *http.Request) {
	p := strings.TrimSpace(r.URL.Query().Get("path"))
	mode := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("mode")))
	if mode == "" {
		mode = "folder"
	}
	if mode != "folder" && mode != "file" {
		http.Error(w, "bad mode", 400)
		return
	}
	allowedExt := map[string]bool{}
	for _, x := range strings.Split(r.URL.Query().Get("ext"), ",") {
		x = strings.ToLower(strings.TrimSpace(x))
		if x == "" {
			continue
		}
		if !strings.HasPrefix(x, ".") {
			x = "." + x
		}
		allowedExt[x] = true
	}
	if p == "" {
		roots := []string{}
		if os.PathSeparator == '\\' {
			for ch := 'A'; ch <= 'Z'; ch++ {
				d := string(ch) + `:\`
				if st, e := os.Stat(d); e == nil && st.IsDir() {
					roots = append(roots, d)
				}
			}
		} else {
			roots = []string{"/"}
		}
		writeJSON(w, map[string]any{"roots": roots, "mode": mode})
		return
	}
	clean := filepath.Clean(p)
	st, e := os.Stat(clean)
	if e != nil {
		http.Error(w, "path not found", 404)
		return
	}
	// File mode accepts a selected file path and reports its parent directory so
	// the client can re-open the browser at the same location.
	if !st.IsDir() {
		if mode != "file" {
			http.Error(w, "folder required", 400)
			return
		}
		ext := strings.ToLower(filepath.Ext(clean))
		selectable := len(allowedExt) == 0 || allowedExt[ext]
		writeJSON(w, map[string]any{"path": filepath.Dir(clean), "selected": clean, "selectable": selectable, "mode": mode})
		return
	}
	es, e := os.ReadDir(clean)
	if e != nil {
		http.Error(w, e.Error(), 500)
		return
	}
	type ent struct {
		Name       string `json:"name"`
		Path       string `json:"path"`
		Kind       string `json:"kind"`
		Server     bool   `json:"server,omitempty"`
		Selectable bool   `json:"selectable,omitempty"`
		Size       int64  `json:"size,omitempty"`
	}
	out := []ent{}
	for _, x := range es {
		if strings.HasPrefix(x.Name(), ".") {
			continue
		}
		fp := filepath.Join(clean, x.Name())
		if x.IsDir() {
			_, e1 := os.Stat(filepath.Join(fp, "server.properties"))
			_, e2 := os.Stat(filepath.Join(fp, "start.bat"))
			out = append(out, ent{Name: x.Name(), Path: fp, Kind: "dir", Server: e1 == nil || e2 == nil})
			continue
		}
		if mode != "file" {
			continue
		}
		ext := strings.ToLower(filepath.Ext(x.Name()))
		selectable := len(allowedExt) == 0 || allowedExt[ext]
		if !selectable && len(allowedExt) > 0 {
			continue
		}
		st, _ := x.Info()
		size := int64(0)
		if st != nil {
			size = st.Size()
		}
		out = append(out, ent{Name: x.Name(), Path: fp, Kind: "file", Selectable: selectable, Size: size})
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Kind != out[j].Kind {
			return out[i].Kind == "dir"
		}
		return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name)
	})
	parent := filepath.Dir(clean)
	if parent == clean {
		parent = ""
	}
	_, sp := os.Stat(filepath.Join(clean, "server.properties"))
	_, sb := os.Stat(filepath.Join(clean, "start.bat"))
	serverPort := 0
	if sp == nil {
		if v, e := readServerProperty(clean, "server-port"); e == nil {
			serverPort, _ = strconv.Atoi(strings.TrimSpace(v))
		}
	}
	writeJSON(w, map[string]any{"path": clean, "parent": parent, "entries": out, "looks_like_server": sp == nil || sb == nil, "server_port": serverPort, "mode": mode})
}

var serverIDRE = regexp.MustCompile(`^[a-z0-9][a-z0-9_-]{1,31}$`)

type serverProfileReq struct {
	Action string       `json:"action"`
	Server ServerConfig `json:"server"`
}

func apiV4ServerProfile(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "POST required", 405)
		return
	}
	var q serverProfileReq
	if json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q) != nil {
		http.Error(w, "bad json", 400)
		return
	}
	q.Server.ID = strings.ToLower(strings.TrimSpace(q.Server.ID))
	q.Server.Name = strings.TrimSpace(q.Server.Name)
	q.Server.Path = strings.TrimSpace(q.Server.Path)
	q.Server.Role = strings.ToLower(strings.TrimSpace(q.Server.Role))
	q.Server.UpdatePolicy = strings.ToLower(strings.TrimSpace(q.Server.UpdatePolicy))
	if !serverIDRE.MatchString(q.Server.ID) {
		http.Error(w, "서버 ID는 영문 소문자/숫자/_/- 2~32자", 400)
		return
	}
	if q.Server.Role != "" && !validServerRole(q.Server.Role) {
		http.Error(w, "role must be lobby, wild, playground, or other", 400)
		return
	}
	switch q.Server.UpdatePolicy {
	case "", serverUpdateManaged, serverUpdateManual, serverUpdateHold:
	default:
		http.Error(w, "update_policy must be managed, manual, or hold", 400)
		return
	}
	c := configSnapshot()
	idx := -1
	for i := range c.Servers {
		if c.Servers[i].ID == q.Server.ID {
			idx = i
			break
		}
	}
	switch strings.ToLower(q.Action) {
	case "add":
		if idx >= 0 {
			http.Error(w, "이미 존재하는 ID", 409)
			return
		}
		if q.Server.Name == "" {
			q.Server.Name = q.Server.ID
		}
		if q.Server.StartCommand == "" {
			q.Server.StartCommand = "start.bat"
		}
		q.Server = normalizeServerConfig(q.Server)
		// Preserve the values submitted by the profile form. v4.0.1 forced
		// AutoStart=false and RestartOnCrash=true here, ignoring the user's choices.
		c.Servers = append(c.Servers, q.Server)
	case "update":
		if idx < 0 {
			http.Error(w, "unknown server", 404)
			return
		}
		old := c.Servers[idx]
		if q.Server.Name == "" {
			q.Server.Name = old.Name
		}
		if q.Server.Path == "" {
			q.Server.Path = old.Path
		}
		if q.Server.PathFile == "" {
			q.Server.PathFile = old.PathFile
		}
		if q.Server.StartCommand == "" {
			q.Server.StartCommand = old.StartCommand
		}
		if q.Server.Role == "" {
			q.Server.Role = old.Role
		}
		if q.Server.UpdatePolicy == "" {
			q.Server.UpdatePolicy = old.UpdatePolicy
		}
		q.Server = normalizeServerConfig(q.Server)
		c.Servers[idx] = q.Server
	case "delete":
		if idx < 0 {
			http.Error(w, "unknown server", 404)
			return
		}
		if tcpOpen("127.0.0.1", c.Servers[idx].JavaPort, 250*time.Millisecond) || launchAlive(q.Server.ID) {
			http.Error(w, "실행 중인 서버는 삭제할 수 없습니다", 409)
			return
		}
		c.Servers = append(c.Servers[:idx], c.Servers[idx+1:]...)
	default:
		http.Error(w, "unknown action", 400)
		return
	}
	if err := saveHostConfig(c); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	initRuntimeState()
	changedBridges, agentChanged := reconcileLocalCompanionConfigs()
	applyCompanionReconcile(changedBridges, agentChanged)
	appendV4Event("info", "settings", q.Server.ID, "서버 프로필 "+q.Action, "Agent/GDS 동기화 예약됨")
	writeJSON(w, map[string]any{"ok": true, "servers": c.Servers})
}

func jarPluginInfo(path string) (name, version string) {
	z, e := zip.OpenReader(path)
	if e != nil {
		return
	}
	defer z.Close()
	for _, fn := range []string{"paper-plugin.yml", "plugin.yml"} {
		for _, f := range z.File {
			if f.Name != fn {
				continue
			}
			rc, e := f.Open()
			if e != nil {
				continue
			}
			sc := bufio.NewScanner(io.LimitReader(rc, 128<<10))
			for sc.Scan() {
				ln := strings.TrimSpace(sc.Text())
				if strings.HasPrefix(ln, "name:") {
					name = strings.Trim(strings.TrimSpace(strings.TrimPrefix(ln, "name:")), "'\"")
				}
				if strings.HasPrefix(ln, "version:") {
					version = strings.Trim(strings.TrimSpace(strings.TrimPrefix(ln, "version:")), "'\"")
				}
			}
			_ = rc.Close()
			if name != "" || version != "" {
				return
			}
		}
	}
	return
}

func pluginInventory(dir string) []PluginInventory {
	pd := filepath.Join(dir, "plugins")
	es, _ := os.ReadDir(pd)
	out := []PluginInventory{}
	for _, e := range es {
		low := strings.ToLower(e.Name())
		enabled := strings.HasSuffix(low, ".jar")
		if e.IsDir() || (!enabled && !strings.HasSuffix(low, ".jar.disabled")) {
			continue
		}
		p := filepath.Join(pd, e.Name())
		st, _ := e.Info()
		n, v := jarPluginInfo(p)
		managed := strings.EqualFold(n, "GeumyiDiscordStatus") || strings.EqualFold(n, "GeumyiServerTools") || strings.Contains(low, "geumyidiscordstatus") || strings.Contains(low, "geumyiservertools")
		out = append(out, PluginInventory{File: e.Name(), Name: n, Version: v, Size: st.Size(), Managed: managed, Enabled: enabled})
	}
	sort.Slice(out, func(i, j int) bool { return strings.ToLower(out[i].File) < strings.ToLower(out[j].File) })
	return out
}

func readPackMeta(path string) (format int, desc string) {
	var b []byte
	if st, e := os.Stat(path); e == nil && st.IsDir() {
		b, _ = os.ReadFile(filepath.Join(path, "pack.mcmeta"))
	} else if z, e := zip.OpenReader(path); e == nil {
		defer z.Close()
		for _, f := range z.File {
			if f.Name == "pack.mcmeta" {
				rc, _ := f.Open()
				b, _ = io.ReadAll(io.LimitReader(rc, 256<<10))
				_ = rc.Close()
				break
			}
		}
	}
	var m struct {
		Pack struct {
			PackFormat  int `json:"pack_format"`
			Description any `json:"description"`
		} `json:"pack"`
	}
	if json.Unmarshal(b, &m) == nil {
		format = m.Pack.PackFormat
		desc = fmt.Sprint(m.Pack.Description)
	}
	return
}
func datapackInventory(dir string) []DatapackInventory {
	level := readServerPropertyDefault(dir, "level-name", "world")
	dd := filepath.Join(dir, level, "datapacks")
	es, _ := os.ReadDir(dd)
	out := []DatapackInventory{}
	for _, e := range es {
		p := filepath.Join(dd, e.Name())
		st, _ := e.Info()
		f, d := readPackMeta(p)
		enabled := !strings.HasSuffix(strings.ToLower(e.Name()), ".disabled")
		out = append(out, DatapackInventory{File: e.Name(), Format: f, Description: d, Size: st.Size(), Enabled: enabled})
	}
	sort.Slice(out, func(i, j int) bool { return strings.ToLower(out[i].File) < strings.ToLower(out[j].File) })
	return out
}
func readServerPropertyDefault(dir, key, def string) string {
	v, e := readServerProperty(dir, key)
	if e != nil || strings.TrimSpace(v) == "" {
		return def
	}
	return strings.TrimSpace(v)
}
func resourcePackInventory(dir string) ResourcePackInventory {
	r := ResourcePackInventory{JavaURL: readServerPropertyDefault(dir, "resource-pack", ""), JavaSHA1: readServerPropertyDefault(dir, "resource-pack-sha1", ""), Required: readServerPropertyDefault(dir, "require-resource-pack", "")}
	for _, g := range []string{filepath.Join(dir, "plugins", "Geyser-Spigot", "packs"), filepath.Join(dir, "plugins", "Geyser", "packs")} {
		es, _ := os.ReadDir(g)
		for _, e := range es {
			if !e.IsDir() {
				r.GeyserPacks = append(r.GeyserPacks, e.Name())
			}
		}
	}
	sort.Strings(r.GeyserPacks)
	return r
}
func managedAvailable() []PluginInventory {
	es, _ := os.ReadDir(v4ManagedPluginsDir())
	out := []PluginInventory{}
	for _, e := range es {
		if e.IsDir() || !strings.HasSuffix(strings.ToLower(e.Name()), ".jar") {
			continue
		}
		p := filepath.Join(v4ManagedPluginsDir(), e.Name())
		st, _ := e.Info()
		n, v := jarPluginInfo(p)
		out = append(out, PluginInventory{File: e.Name(), Name: n, Version: v, Size: st.Size(), Managed: true, Enabled: true})
	}
	return out
}
func apiV4Inventory(w http.ResponseWriter, r *http.Request) {
	s, ok := serverByID(r.URL.Query().Get("id"))
	if !ok {
		http.Error(w, "unknown server", 400)
		return
	}
	dir := resolveServerDir(s)
	writeJSON(w, map[string]any{"plugins": pluginInventory(dir), "datapacks": datapackInventory(dir), "resourcepacks": resourcePackInventory(dir), "managed_available": managedAvailable(), "bridge": bridgeV4Status(s)})
}

func apiV4CompanionSync(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "POST required", 405)
		return
	}
	var q struct {
		ID string `json:"id"`
	}
	if json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q) != nil {
		http.Error(w, "bad json", 400)
		return
	}
	s, ok := serverByID(q.ID)
	if !ok {
		http.Error(w, "unknown server", 400)
		return
	}
	if tcpOpen("127.0.0.1", s.JavaPort, 250*time.Millisecond) {
		http.Error(w, "플러그인 교체는 서버를 정상 종료한 뒤 실행하세요", 409)
		return
	}
	release, e := beginV4Operation(s.ID, "companion-sync")
	if e != nil {
		http.Error(w, e.Error(), 409)
		return
	}
	defer release()
	dir := resolveServerDir(s)
	pdir := filepath.Join(dir, "plugins")
	if err := os.MkdirAll(pdir, 0755); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	backupDir := filepath.Join(v4Root(), "PluginBackups", s.ID, time.Now().Format("20060102-150405"))
	_ = os.MkdirAll(backupDir, 0755)
	managed := managedAvailable()
	if len(managed) == 0 {
		http.Error(w, "관리되는 v4 플러그인 파일이 없습니다", 404)
		return
	}
	installed := pluginInventory(dir)
	replaced := []string{}
	for _, m := range managed {
		if m.Name != "GeumyiDiscordStatus" && m.Name != "GeumyiServerTools" {
			continue
		}
		for _, x := range installed {
			if strings.EqualFold(x.Name, m.Name) {
				src := filepath.Join(pdir, x.File)
				_ = copyFileV4(src, filepath.Join(backupDir, x.File))
				_ = os.Remove(src)
			}
		}
		src := filepath.Join(v4ManagedPluginsDir(), m.File)
		dst := filepath.Join(pdir, m.File)
		if err := copyFileV4(src, dst); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		replaced = append(replaced, m.Name+" "+m.Version)
	}
	// Keep the newly installed bridge JAR and its preserved config aligned with
	// the integrated Agent. This also covers arbitrary newly added server profiles,
	// not only the built-in wild/playground pair.
	changedBridges, agentChanged := reconcileLocalCompanionConfigs()
	applyCompanionReconcile(changedBridges, agentChanged)
	appendV4Event("info", "plugin", s.ID, "GSC v4 companion 동기화", strings.Join(replaced, ", "))
	writeJSON(w, map[string]any{"ok": true, "installed": replaced, "backup_dir": backupDir})
}
func copyFileV4(src, dst string) error {
	in, e := os.Open(src)
	if e != nil {
		return e
	}
	defer in.Close()
	if e = os.MkdirAll(filepath.Dir(dst), 0755); e != nil {
		return e
	}
	tmp := dst + ".tmp"
	out, e := os.Create(tmp)
	if e != nil {
		return e
	}
	_, e = io.Copy(out, in)
	ce := out.Close()
	if e == nil {
		e = ce
	}
	if e != nil {
		_ = os.Remove(tmp)
		return e
	}
	_ = os.Remove(dst)
	return os.Rename(tmp, dst)
}

func apiV4System(w http.ResponseWriter, r *http.Request) {
	c := configSnapshot()
	h := getHostStats()
	writeJSON(w, map[string]any{"version": appVersion, "host": h, "config_path": configPath, "data_root": v4Root(), "service_mode": serviceModeRequested(), "servers": len(c.Servers), "managed_plugins": managedAvailable(), "operations": operationSnapshot(), "pairing": pairingSummary(), "mobile": mobileStatus(), "control_api": map[string]any{"version": controlAPIVersion, "websocket": true, "websocket_clients": wsClientCount(), "active_jobs": activeControlJobCount(), "audit": true}})
}
func operationSnapshot() map[string]string {
	v4OpMu.Lock()
	defer v4OpMu.Unlock()
	m := map[string]string{}
	for k, v := range v4Operations {
		m[k] = v
	}
	return m
}

func apiV4MaintainToggle(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "POST required", 405)
		return
	}
	var q struct {
		ID     string `json:"id"`
		Kind   string `json:"kind"`
		File   string `json:"file"`
		Enable bool   `json:"enable"`
	}
	if json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q) != nil {
		http.Error(w, "bad json", 400)
		return
	}
	s, ok := serverByID(q.ID)
	if !ok {
		http.Error(w, "unknown server", 400)
		return
	}
	if tcpOpen("127.0.0.1", s.JavaPort, 250*time.Millisecond) {
		http.Error(w, "플러그인/데이터팩 활성화 변경은 서버를 종료한 뒤 실행하세요", 409)
		return
	}
	name := filepath.Base(q.File)
	if name == "." || name == "" {
		http.Error(w, "bad file", 400)
		return
	}
	var base string
	switch q.Kind {
	case "plugin":
		base = filepath.Join(resolveServerDir(s), "plugins")
	case "datapack":
		base = filepath.Join(resolveServerDir(s), readServerPropertyDefault(resolveServerDir(s), "level-name", "world"), "datapacks")
	default:
		http.Error(w, "bad kind", 400)
		return
	}
	src := filepath.Join(base, name)
	dst := src
	if q.Enable {
		if strings.HasSuffix(strings.ToLower(name), ".disabled") {
			dst = strings.TrimSuffix(src, ".disabled")
		}
	} else {
		if !strings.HasSuffix(strings.ToLower(name), ".disabled") {
			dst = src + ".disabled"
		}
	}
	if src == dst {
		writeJSON(w, map[string]any{"ok": true})
		return
	}
	if err := os.Rename(src, dst); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	appendV4Event("info", "maintain", s.ID, fmt.Sprintf("%s %s", q.Kind, func() string {
		if q.Enable {
			return "활성화"
		}
		return "비활성화"
	}()), filepath.Base(dst))
	writeJSON(w, map[string]any{"ok": true, "file": filepath.Base(dst)})
}
