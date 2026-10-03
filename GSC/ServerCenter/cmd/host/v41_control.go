package main

import (
	"bufio"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
	"unicode/utf8"
)

const controlAPIVersion = 1

type authPrincipal struct {
	Kind string `json:"kind"`
	ID   string `json:"id,omitempty"`
	Name string `json:"name,omitempty"`
}

type authContextKey struct{}

func authenticateRequest(r *http.Request) (authPrincipal, bool) {
	c := configSnapshot()
	if c.AllowLoopbackNoAuth && isLoopbackRemote(r.RemoteAddr) {
		return authPrincipal{Kind: "local", ID: "loopback", Name: "Local GSC"}, true
	}
	got := strings.TrimSpace(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer"))
	if got == "" {
		got = strings.TrimSpace(r.Header.Get("X-GSC-Token"))
	}
	if got == "" {
		return authPrincipal{}, false
	}
	if got == c.APIToken {
		return authPrincipal{Kind: "api_token", ID: "host-token", Name: "Host API Token"}, true
	}
	if d, ok := trustedDeviceForToken(got); ok {
		return authPrincipal{Kind: "device", ID: d.ID, Name: d.Name}, true
	}
	return authPrincipal{}, false
}

func principalFromRequest(r *http.Request) authPrincipal {
	if p, ok := r.Context().Value(authContextKey{}).(authPrincipal); ok {
		return p
	}
	return authPrincipal{Kind: "unknown", Name: "Unknown"}
}

// effectivePrincipal preserves the authenticated transport principal by default.
// A loopback-only trusted broker such as GeumyiStatusAgent may delegate the actual
// Discord actor so Control jobs/Audit remain attributable to a human operator.
// Delegation is intentionally ignored for non-loopback callers.
func effectivePrincipal(r *http.Request) authPrincipal {
	p := principalFromRequest(r)
	if !isLoopbackRemote(r.RemoteAddr) {
		return p
	}
	id := strings.TrimSpace(r.Header.Get("X-GSC-Actor-Id"))
	name := strings.TrimSpace(r.Header.Get("X-GSC-Actor"))
	if encoded := strings.TrimSpace(r.Header.Get("X-GSC-Actor-B64")); encoded != "" {
		if b, err := base64.RawURLEncoding.DecodeString(encoded); err == nil && utf8.Valid(b) {
			if decoded := strings.TrimSpace(string(b)); decoded != "" {
				name = decoded
			}
		}
	}
	if id == "" && name == "" {
		return p
	}
	if len(id) > 128 {
		id = id[:128]
	}
	if rr := []rune(name); len(rr) > 128 {
		name = string(rr[:128])
	}
	return authPrincipal{Kind: "delegated", ID: id, Name: name}
}

func requestControlSource(r *http.Request) string {
	if isLoopbackRemote(r.RemoteAddr) {
		s := strings.TrimSpace(r.Header.Get("X-GSC-Source"))
		if s != "" {
			if len(s) > 64 {
				s = s[:64]
			}
			return s
		}
	}
	return "control-api-v1"
}

func requestControlID(r *http.Request) string {
	if !isLoopbackRemote(r.RemoteAddr) {
		return ""
	}
	id := strings.TrimSpace(r.Header.Get("X-GSC-Request-Id"))
	if len(id) > 128 {
		id = id[:128]
	}
	return id
}

func principalLabel(p authPrincipal) string {
	if p.Kind == "device" {
		if p.Name != "" {
			return p.Name + " (" + p.ID + ")"
		}
		return p.ID
	}
	if p.Name != "" {
		return p.Name
	}
	return p.Kind
}

func requestIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return host
	}
	return r.RemoteAddr
}

// --- State machine ----------------------------------------------------------

type ControlServerView struct {
	ID                 string                  `json:"id"`
	Name               string                  `json:"name"`
	State              string                  `json:"state"`
	Online             bool                    `json:"online"`
	DesiredRunning     bool                    `json:"desired_running"`
	Minecraft          MCStatus                `json:"minecraft"`
	Java               JavaStats               `json:"java"`
	Launch             LaunchStatus            `json:"launch"`
	Schedule           LifecycleScheduleStatus `json:"schedule"`
	Operation          string                  `json:"operation,omitempty"`
	ActiveJob          *ControlJob             `json:"active_job,omitempty"`
	DirValid           bool                    `json:"dir_valid"`
	PluginCount        int                     `json:"plugin_count"`
	WorldCount         int                     `json:"world_count"`
	ServerTools        GSTDiagnostics          `json:"server_tools"`
	Bridge             map[string]any          `json:"bridge,omitempty"`
	DegradationReasons []string                `json:"degradation_reasons,omitempty"`
	ManagementWarnings []string                `json:"management_warnings,omitempty"`
	Updated            string                  `json:"updated"`
}

func deriveServerState(s ServerConfig, st ServerStatus) string {
	if st.Launch.FailureCode != "" || st.Launch.FailureTitle != "" {
		return "BOOT_FAILED"
	}
	if job := activeControlJob(s.ID); job != nil {
		switch job.Action {
		case "start":
			return "STARTING"
		case "stop":
			return "STOPPING"
		case "restart":
			return "RESTARTING"
		}
	}
	if op := currentOperation(s.ID); op != "" {
		return "MAINTENANCE"
	}
	if st.Schedule.Active {
		switch strings.ToLower(st.Schedule.Action) {
		case "stop":
			return "STOPPING"
		case "restart":
			return "RESTARTING"
		}
	}
	switch strings.ToLower(st.Launch.Phase) {
	case "starting":
		return "STARTING"
	case "stopping":
		return "STOPPING"
	case "executing":
		if st.Schedule.Action == "restart" {
			return "RESTARTING"
		}
		if st.Schedule.Action == "stop" {
			return "STOPPING"
		}
	case "error":
		if st.DesiredRunning {
			return "CRASHED"
		}
	}
	if st.Online {
		// Server health and management capability are separate concerns.
		// RCON being unavailable limits management features, but does not mean the
		// Minecraft service itself is degraded when status/GDS/ServerTools are healthy.
		if !st.MC.OK || !st.GDSAPIOnline {
			return "DEGRADED"
		}
		return "ONLINE"
	}
	if st.DesiredRunning {
		if st.LauncherRunning || trackedServerAlive(s.ID) {
			return "STARTING"
		}
		return "RECOVERING"
	}
	return "OFFLINE"
}

func controlServerViewFromStatus(s ServerConfig, st ServerStatus) ControlServerView {
	gst := readGSTDiagnostics(s)
	state := st.State
	reasons := make([]string, 0, 3)
	mgmt := make([]string, 0, 2)
	if st.Online {
		if !st.MC.OK {
			reasons = append(reasons, "minecraft_status")
		}
		if !st.GDSAPIOnline {
			reasons = append(reasons, "gds_api")
		}
		if !st.RCONPortOpen {
			mgmt = append(mgmt, "rcon_unavailable")
		}
	}
	if state == "ONLINE" && gstDegraded(gst) {
		state = "DEGRADED"
		reasons = append(reasons, "servertools")
	}
	var bridge map[string]any
	if st.GDSAPIOnline {
		bridge = bridgeV4Status(s)
	}
	return ControlServerView{
		ID: s.ID, Name: s.Name, State: state, Online: st.Online,
		DesiredRunning: st.DesiredRunning, Minecraft: st.MC, Java: st.Java,
		Launch: st.Launch, Schedule: st.Schedule, Operation: currentOperation(s.ID),
		ActiveJob: activeControlJob(s.ID), DirValid: st.DirValid,
		PluginCount: st.PluginCount, WorldCount: st.WorldCount, ServerTools: gst, Bridge: bridge,
		DegradationReasons: reasons, ManagementWarnings: mgmt,
		Updated: time.Now().Format(time.RFC3339Nano),
	}
}

func controlServerView(s ServerConfig) ControlServerView {
	return controlServerViewFromStatus(s, getServerStatus(s))
}

// --- Job queue --------------------------------------------------------------

type ControlJob struct {
	ID               string `json:"id"`
	ServerID         string `json:"server_id"`
	Action           string `json:"action"`
	Status           string `json:"status"` // queued|running|completed|failed|cancelled|interrupted
	CountdownSeconds int    `json:"countdown_seconds,omitempty"`
	RequestedAt      string `json:"requested_at"`
	StartedAt        string `json:"started_at,omitempty"`
	FinishedAt       string `json:"finished_at,omitempty"`
	RequestedBy      string `json:"requested_by"`
	RequestedByID    string `json:"requested_by_id,omitempty"`
	Source           string `json:"source"`
	RequestID        string `json:"request_id,omitempty"`
	Message          string `json:"message,omitempty"`
	Error            string `json:"error,omitempty"`
}

var (
	controlJobSeq    atomic.Uint64
	controlJobMu     sync.RWMutex
	controlJobs      = map[string]*ControlJob{}
	controlJobOrder  []string
	controlJobQueues = map[string]chan string{}
)

func controlJobsPath() string { return filepath.Join(v4Root(), "jobs", "control-jobs.jsonl") }

func newControlJobID() string {
	b := make([]byte, 4)
	_, _ = rand.Read(b)
	return fmt.Sprintf("job-%s-%06d-%s", time.Now().UTC().Format("20060102T150405"), controlJobSeq.Add(1)%1000000, hex.EncodeToString(b))
}

func cloneJob(j *ControlJob) *ControlJob {
	if j == nil {
		return nil
	}
	x := *j
	return &x
}

func persistControlJob(j *ControlJob) {
	b, _ := json.Marshal(j)
	p := controlJobsPath()
	_ = os.MkdirAll(filepath.Dir(p), 0755)
	if st, err := os.Stat(p); err == nil && st.Size() > 16<<20 {
		_ = os.Rename(p, p+".1")
	}
	if f, err := os.OpenFile(p, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644); err == nil {
		_, _ = f.Write(append(b, '\n'))
		_ = f.Close()
	}
}

func loadControlJobs() {
	f, err := os.Open(controlJobsPath())
	if err != nil {
		return
	}
	defer f.Close()
	latest := map[string]*ControlJob{}
	order := []string{}
	seen := map[string]bool{}
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 64<<10), 1<<20)
	for sc.Scan() {
		var j ControlJob
		if json.Unmarshal(sc.Bytes(), &j) != nil || j.ID == "" {
			continue
		}
		if !seen[j.ID] {
			order = append(order, j.ID)
			seen[j.ID] = true
		}
		x := j
		latest[j.ID] = &x
	}
	controlJobMu.Lock()
	controlJobs = latest
	controlJobOrder = order
	// Work cannot safely continue across a Host restart. Mark unfinished jobs.
	for _, id := range order {
		j := controlJobs[id]
		if j != nil && (j.Status == "queued" || j.Status == "running") {
			j.Status = "interrupted"
			j.FinishedAt = time.Now().Format(time.RFC3339Nano)
			j.Error = "GSC Host가 다시 시작되어 이전 작업을 중단 처리했습니다."
			persistControlJob(j)
		}
	}
	if len(controlJobOrder) > 500 {
		controlJobOrder = append([]string(nil), controlJobOrder[len(controlJobOrder)-500:]...)
	}
	controlJobMu.Unlock()
}

func initControlJobs() {
	_ = os.MkdirAll(filepath.Dir(controlJobsPath()), 0755)
	loadControlJobs()
	controlJobMu.Lock()
	defer controlJobMu.Unlock()
	for _, s := range configSnapshot().Servers {
		if controlJobQueues[s.ID] != nil {
			continue
		}
		q := make(chan string, 8)
		controlJobQueues[s.ID] = q
		go controlJobWorker(s.ID, q)
	}
}

func ensureControlQueue(id string) chan string {
	controlJobMu.Lock()
	defer controlJobMu.Unlock()
	if q := controlJobQueues[id]; q != nil {
		return q
	}
	q := make(chan string, 8)
	controlJobQueues[id] = q
	go controlJobWorker(id, q)
	return q
}

func activeControlJob(id string) *ControlJob {
	controlJobMu.RLock()
	defer controlJobMu.RUnlock()
	// A running job always represents the server's current state. If none is
	// running, return the oldest queued job because that is next to execute.
	for _, jobID := range controlJobOrder {
		j := controlJobs[jobID]
		if j != nil && j.ServerID == id && j.Status == "running" {
			return cloneJob(j)
		}
	}
	for _, jobID := range controlJobOrder {
		j := controlJobs[jobID]
		if j != nil && j.ServerID == id && j.Status == "queued" {
			return cloneJob(j)
		}
	}
	return nil
}

func activeControlJobCount() int {
	controlJobMu.RLock()
	defer controlJobMu.RUnlock()
	n := 0
	for _, j := range controlJobs {
		if j != nil && (j.Status == "queued" || j.Status == "running") {
			n++
		}
	}
	return n
}

func recentControlJobs(limit int, serverID string) []ControlJob {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	controlJobMu.RLock()
	defer controlJobMu.RUnlock()
	out := make([]ControlJob, 0, limit)
	for i := len(controlJobOrder) - 1; i >= 0 && len(out) < limit; i-- {
		j := controlJobs[controlJobOrder[i]]
		if j == nil || (serverID != "" && j.ServerID != serverID) {
			continue
		}
		out = append(out, *j)
	}
	return out
}

func controlJobByID(id string) *ControlJob {
	controlJobMu.RLock()
	defer controlJobMu.RUnlock()
	return cloneJob(controlJobs[id])
}

func setControlJob(id string, fn func(*ControlJob)) {
	controlJobMu.Lock()
	j := controlJobs[id]
	if j == nil {
		controlJobMu.Unlock()
		return
	}
	fn(j)
	snap := *j
	controlJobMu.Unlock()
	persistControlJob(&snap)
	wsPublish("job.updated", snap)
}

func enqueueControlJob(serverID, action string, countdown int, p authPrincipal, source, requestID string) (*ControlJob, error) {
	action = strings.ToLower(strings.TrimSpace(action))
	if action != "start" && action != "stop" && action != "restart" {
		return nil, errors.New("unsupported action")
	}
	if shuttingDown.Load() {
		return nil, errors.New("shutdown in progress")
	}
	if _, ok := serverByID(serverID); !ok {
		return nil, errors.New("unknown server")
	}
	if countdown < 0 || countdown > maxLifecycleCountdownSeconds {
		return nil, fmt.Errorf("countdown_seconds must be 0..%d", maxLifecycleCountdownSeconds)
	}
	q := ensureControlQueue(serverID)
	if len(q) >= cap(q) {
		return nil, errors.New("server job queue is full")
	}
	j := &ControlJob{
		ID: newControlJobID(), ServerID: serverID, Action: action, Status: "queued",
		CountdownSeconds: countdown, RequestedAt: time.Now().Format(time.RFC3339Nano),
		RequestedBy: principalLabel(p), RequestedByID: p.ID, Source: source, RequestID: requestID,
		Message: "작업 대기 중",
	}
	controlJobMu.Lock()
	controlJobs[j.ID] = j
	controlJobOrder = append(controlJobOrder, j.ID)
	if len(controlJobOrder) > 500 {
		old := controlJobOrder[0]
		controlJobOrder = controlJobOrder[1:]
		if x := controlJobs[old]; x != nil && x.Status != "queued" && x.Status != "running" {
			delete(controlJobs, old)
		}
	}
	controlJobMu.Unlock()
	persistControlJob(j)
	appendV4Event("info", "job", serverID, "제어 작업 대기", j.ID+" · "+action)
	wsPublish("job.created", *j)
	q <- j.ID
	return cloneJob(j), nil
}

func controlJobWorker(serverID string, q <-chan string) {
	for {
		select {
		case <-hostQuit:
			return
		case id := <-q:
			runControlJob(id)
		}
	}
}

func runControlJob(id string) {
	j := controlJobByID(id)
	if j == nil {
		return
	}
	s, ok := serverByID(j.ServerID)
	if !ok {
		setControlJob(id, func(x *ControlJob) {
			x.Status = "failed"
			x.FinishedAt = time.Now().Format(time.RFC3339Nano)
			x.Error = "unknown server"
		})
		return
	}
	if op := currentOperation(s.ID); op != "" {
		setControlJob(id, func(x *ControlJob) {
			x.Status = "failed"
			x.FinishedAt = time.Now().Format(time.RFC3339Nano)
			x.Error = "다른 유지관리 작업 진행 중: " + op
		})
		return
	}
	setControlJob(id, func(x *ControlJob) {
		x.Status = "running"
		x.StartedAt = time.Now().Format(time.RFC3339Nano)
		x.Message = "작업 실행 중"
	})
	appendV4Event("info", "job", s.ID, "제어 작업 시작", j.ID+" · "+j.Action)

	var msg string
	var err error
	switch j.Action {
	case "start":
		_ = cancelLifecycleCountdown(s.ID)
		msg, err = startServer(s)
	case "stop", "restart":
		if lifecycleScheduleStatus(s.ID).Active {
			err = errors.New("기존 종료/재시작 예약이 진행 중입니다")
			break
		}
		delay := j.CountdownSeconds
		executeAt := time.Now().Add(time.Duration(delay)*time.Second + time.Second)
		msg, err = createLifecycleSchedule(s, j.Action, executeAt, delay)
		if err == nil {
			setControlJob(id, func(x *ControlJob) { x.Message = msg })
			deadline := executeAt.Add(4 * time.Minute)
			for time.Now().Before(deadline) {
				if !lifecycleScheduleStatus(s.ID).Active {
					break
				}
				select {
				case <-hostQuit:
					err = errors.New("host stopped")
					break
				case <-time.After(500 * time.Millisecond):
				}
				if err != nil {
					break
				}
			}
			if err == nil && lifecycleScheduleStatus(s.ID).Active {
				err = errors.New("lifecycle job timeout")
			}
			ls := launchStatus(s.ID)
			if err == nil && strings.Contains(ls.Message, "예약 취소") {
				setControlJob(id, func(x *ControlJob) {
					x.Status = "cancelled"
					x.FinishedAt = time.Now().Format(time.RFC3339Nano)
					x.Message = ls.Message
				})
				appendV4Event("warn", "job", s.ID, "제어 작업 취소", j.ID+" · "+j.Action)
				return
			}
			if err == nil {
				if j.Action == "restart" {
					if !tcpOpen("127.0.0.1", s.JavaPort, 500*time.Millisecond) {
						if ls.Error != "" {
							err = errors.New(ls.Error)
						} else {
							err = errors.New("재시작 후 서버가 ONLINE 상태가 아닙니다")
						}
					} else {
						msg = s.Name + " 재시작 완료"
					}
				} else {
					if tcpOpen("127.0.0.1", s.JavaPort, 500*time.Millisecond) || trackedServerAlive(s.ID) {
						err = errors.New("종료 후 서버 프로세스가 아직 실행 중입니다")
					} else {
						msg = s.Name + " 정상 종료 완료"
					}
				}
			}
		}
	}
	if err != nil {
		setControlJob(id, func(x *ControlJob) {
			x.Status = "failed"
			x.FinishedAt = time.Now().Format(time.RFC3339Nano)
			x.Error = err.Error()
			x.Message = msg
		})
		appendV4Event("error", "job", s.ID, "제어 작업 실패", j.ID+" · "+j.Action+" · "+err.Error())
		return
	}
	setControlJob(id, func(x *ControlJob) {
		x.Status = "completed"
		x.FinishedAt = time.Now().Format(time.RFC3339Nano)
		x.Message = msg
	})
	appendV4Event("info", "job", s.ID, "제어 작업 완료", j.ID+" · "+j.Action)
}

// --- Audit log --------------------------------------------------------------

type AuditEntry struct {
	Seq       uint64 `json:"seq"`
	Time      string `json:"time"`
	ActorKind string `json:"actor_kind"`
	ActorID   string `json:"actor_id,omitempty"`
	ActorName string `json:"actor_name,omitempty"`
	SourceIP  string `json:"source_ip,omitempty"`
	Method    string `json:"method"`
	Path      string `json:"path"`
	Action    string `json:"action"`
	Target    string `json:"target,omitempty"`
	Result    string `json:"result"`
	Detail    string `json:"detail,omitempty"`
	Source    string `json:"source,omitempty"`
	RequestID string `json:"request_id,omitempty"`
}

var auditSeq atomic.Uint64
var auditMu sync.Mutex

func auditPath() string { return filepath.Join(v4Root(), "audit", "control-audit.jsonl") }

func initAuditSeq() {
	var maxSeq uint64
	for _, p := range []string{auditPath() + ".1", auditPath()} {
		f, err := os.Open(p)
		if err != nil {
			continue
		}
		scanner := bufio.NewScanner(f)
		// Audit entries are intentionally small, but allow room for future detail.
		scanner.Buffer(make([]byte, 64*1024), 1024*1024)
		for scanner.Scan() {
			var e AuditEntry
			if json.Unmarshal(scanner.Bytes(), &e) == nil && e.Seq > maxSeq {
				maxSeq = e.Seq
			}
		}
		_ = f.Close()
	}
	auditSeq.Store(maxSeq)
}

func appendAudit(r *http.Request, action, target, result, detail string) {
	p := effectivePrincipal(r)
	e := AuditEntry{
		Seq: auditSeq.Add(1), Time: time.Now().Format(time.RFC3339Nano),
		ActorKind: p.Kind, ActorID: p.ID, ActorName: p.Name, SourceIP: requestIP(r),
		Method: r.Method, Path: r.URL.Path, Action: action, Target: target, Result: result, Detail: detail,
		Source: requestControlSource(r), RequestID: requestControlID(r),
	}
	appendAuditEntry(e)
}

func appendUnauthorizedAudit(r *http.Request) {
	if !strings.HasPrefix(r.URL.Path, "/api/v1/") {
		return
	}
	e := AuditEntry{
		Seq: auditSeq.Add(1), Time: time.Now().Format(time.RFC3339Nano), ActorKind: "unauthorized",
		SourceIP: requestIP(r), Method: r.Method, Path: r.URL.Path, Action: "auth", Result: "denied",
	}
	appendAuditEntry(e)
}

func appendAuditEntry(e AuditEntry) {
	b, _ := json.Marshal(e)
	auditMu.Lock()
	defer auditMu.Unlock()
	p := auditPath()
	_ = os.MkdirAll(filepath.Dir(p), 0755)
	if st, err := os.Stat(p); err == nil && st.Size() > 16<<20 {
		_ = os.Rename(p, p+".1")
	}
	if f, err := os.OpenFile(p, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644); err == nil {
		_, _ = f.Write(append(b, '\n'))
		_ = f.Close()
	}
}

func recentAudit(limit int) []AuditEntry {
	if limit <= 0 || limit > 1000 {
		limit = 200
	}
	b, err := os.ReadFile(auditPath())
	if err != nil {
		return nil
	}
	lines := strings.Split(strings.TrimSpace(string(b)), "\n")
	out := make([]AuditEntry, 0, limit)
	for i := len(lines) - 1; i >= 0 && len(out) < limit; i-- {
		var e AuditEntry
		if json.Unmarshal([]byte(lines[i]), &e) == nil {
			out = append(out, e)
		}
	}
	return out
}

// --- Control API v1 ---------------------------------------------------------

func registerControlAPIRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/api/v1/info", requireAuth(apiV1Info))
	mux.HandleFunc("/api/v1/snapshot", requireAuth(apiV1Snapshot))
	mux.HandleFunc("/api/v1/servers", requireAuth(apiV1Servers))
	mux.HandleFunc("/api/v1/servers/", requireAuth(apiV1ServerRoute))
	mux.HandleFunc("/api/v1/jobs", requireAuth(apiV1Jobs))
	mux.HandleFunc("/api/v1/jobs/", requireAuth(apiV1JobRoute))
	mux.HandleFunc("/api/v1/events", requireAuth(apiV1Events))
	mux.HandleFunc("/api/v1/audit", requireAuth(apiV1Audit))
	mux.HandleFunc("/api/v1/ws", requireAuth(apiV1WebSocket))
	mux.HandleFunc("/api/v1/mobile", requireAuth(apiV1Mobile))
	mux.HandleFunc("/api/v1/pairing", requireAuth(apiV1Pairing))
	mux.HandleFunc("/api/v1/pairing/qr", requireAuth(apiV1PairingQR))
	mux.HandleFunc("/api/v1/pairing/claim", apiV1PairingClaim)
	mux.HandleFunc("/api/v1/devices", requireAuth(apiV1Devices))
	mux.HandleFunc("/api/v1/backups", requireAuth(apiV1Backups))
	mux.HandleFunc("/api/v1/backups/verify", requireAuth(apiV1BackupVerify))
	mux.HandleFunc("/api/v1/backups/restore", requireAuth(apiV1BackupRestore))
	mux.HandleFunc("/api/v1/automations", requireAuth(apiV1Automations))
	mux.HandleFunc("/api/v1/metrics", requireAuth(apiV1Metrics))
}

func apiV1Info(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", 405)
		return
	}
	writeJSON(w, map[string]any{
		"ok": true, "gsc_version": appVersion, "api_version": controlAPIVersion,
		"generation": 4, "websocket": "/api/v1/ws",
		"features": []string{"server-state", "job-queue", "audit-log", "websocket", "pairing-v2", "device-management", "mobile-lan-tailscale", "console", "player-management", "backups", "restore", "automations", "metrics", "gst-diagnostics-v2", "gds-bridge-v4", "server-extensions"},
		"mobile":   mobileStatus(),
		"time":     time.Now().Format(time.RFC3339Nano),
	})
}

func apiV1Snapshot(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", 405)
		return
	}
	c := configSnapshot()
	servers := make([]ControlServerView, 0, len(c.Servers))
	for _, s := range c.Servers {
		servers = append(servers, controlServerView(s))
	}
	writeJSON(w, map[string]any{
		"gsc_version": appVersion, "api_version": controlAPIVersion, "timestamp": time.Now().Format(time.RFC3339Nano),
		"host": getHostStats(), "agent_online": agentOnlineNow(), "servers": servers,
		"jobs": recentControlJobs(30, ""), "active_jobs": activeControlJobCount(), "mobile": mobileStatus(),
	})
}

func agentOnlineNow() bool {
	c := configSnapshot()
	return httpOK(c.Agent.HealthURL)
}

func apiV1Servers(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/api/v1/servers" {
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", 405)
		return
	}
	c := configSnapshot()
	out := make([]ControlServerView, 0, len(c.Servers))
	for _, s := range c.Servers {
		out = append(out, controlServerView(s))
	}
	writeJSON(w, map[string]any{"servers": out, "timestamp": time.Now().Format(time.RFC3339Nano)})
}

func parseV1ServerPath(path string) (id, suffix string) {
	rest := strings.TrimPrefix(path, "/api/v1/servers/")
	rest = strings.Trim(rest, "/")
	if rest == "" {
		return "", ""
	}
	parts := strings.Split(rest, "/")
	id = parts[0]
	if len(parts) > 1 {
		suffix = strings.Join(parts[1:], "/")
	}
	return
}

func apiV1ServerRoute(w http.ResponseWriter, r *http.Request) {
	id, suffix := parseV1ServerPath(r.URL.Path)
	s, ok := serverByID(id)
	if !ok {
		http.Error(w, "unknown server", 404)
		return
	}
	switch suffix {
	case "":
		if r.Method != http.MethodGet {
			http.Error(w, "GET required", 405)
			return
		}
		st := getServerStatus(s)
		view := controlServerViewFromStatus(s, st)
		writeJSON(w, map[string]any{"server": st, "state": view.State, "server_tools": view.ServerTools, "bridge": view.Bridge, "extensions": serverExtensions(s), "health": runV4Preflight(s), "active_job": activeControlJob(id)})
	case "players":
		if r.Method != http.MethodGet {
			http.Error(w, "GET required", 405)
			return
		}
		mc := queryMinecraft("127.0.0.1", s.JavaPort)
		writeJSON(w, map[string]any{"server_id": id, "online": mc.OK, "count": mc.Online, "max": mc.Max, "players": mc.Players})
	case "health":
		if r.Method != http.MethodGet {
			http.Error(w, "GET required", 405)
			return
		}
		writeJSON(w, runV4Preflight(s))
	case "actions":
		apiV1ServerAction(w, r, s)
	case "command":
		apiV1ServerCommand(w, r, s)
	case "console":
		apiV1Console(w, r, s)
	case "player-action":
		apiV1PlayerAction(w, r, s)
	case "schedule":
		apiV1ServerSchedule(w, r, s)
	case "inventory":
		if r.Method != http.MethodGet {
			http.Error(w, "GET required", 405)
			return
		}
		writeJSON(w, map[string]any{"server_id": s.ID, "extensions": serverExtensions(s), "plugins": pluginInventory(resolveServerDir(s)), "datapacks": datapackInventory(resolveServerDir(s))})
	default:
		http.NotFound(w, r)
	}
}

func apiV1ServerAction(w http.ResponseWriter, r *http.Request, s ServerConfig) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", 405)
		return
	}
	var q struct {
		Action           string `json:"action"`
		CountdownSeconds *int   `json:"countdown_seconds,omitempty"`
	}
	if json.NewDecoder(io.LimitReader(r.Body, 64<<10)).Decode(&q) != nil {
		appendAudit(r, "server.action", s.ID, "rejected", "bad json")
		http.Error(w, "bad json", 400)
		return
	}
	action := strings.ToLower(strings.TrimSpace(q.Action))
	if action == "force-stop" || action == "force-stop-launcher" || action == "cancel-schedule" {
		var msg string
		var err error
		switch action {
		case "force-stop":
			_ = cancelLifecycleCountdown(s.ID)
			msg, err = forceStopServer(s)
		case "force-stop-launcher":
			_ = cancelLifecycleCountdown(s.ID)
			msg, err = forceStopLauncher(s)
		case "cancel-schedule":
			if cancelLifecycleCountdown(s.ID) {
				msg = "예약 취소 완료"
			} else {
				err = errors.New("진행 중인 예약이 없습니다")
			}
		}
		if err != nil {
			appendAudit(r, "server.action", s.ID+":"+action, "failed", err.Error())
			writeJSONStatus(w, http.StatusConflict, map[string]any{"ok": false, "error": err.Error(), "message": msg})
			return
		}
		appendAudit(r, "server.action", s.ID+":"+action, "completed", msg)
		writeJSON(w, map[string]any{"ok": true, "message": msg})
		return
	}
	countdown := 0
	if action == "stop" || action == "restart" {
		countdown = defaultLifecycleCountdownSeconds
	}
	if q.CountdownSeconds != nil {
		countdown = *q.CountdownSeconds
	}
	j, err := enqueueControlJob(s.ID, action, countdown, effectivePrincipal(r), requestControlSource(r), requestControlID(r))
	if err != nil {
		appendAudit(r, "server.action", s.ID+":"+action, "rejected", err.Error())
		writeJSONStatus(w, http.StatusConflict, map[string]any{"ok": false, "error": err.Error()})
		return
	}
	appendAudit(r, "server.action", s.ID+":"+action, "accepted", j.ID)
	writeJSONStatus(w, http.StatusAccepted, map[string]any{"ok": true, "job": j})
}

func commandName(s string) string {
	p := strings.Fields(strings.TrimSpace(s))
	if len(p) == 0 {
		return ""
	}
	if len(p[0]) > 64 {
		return p[0][:64]
	}
	return p[0]
}

func apiV1ServerCommand(w http.ResponseWriter, r *http.Request, s ServerConfig) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", 405)
		return
	}
	var q struct {
		Command string `json:"command"`
	}
	if json.NewDecoder(io.LimitReader(r.Body, 64<<10)).Decode(&q) != nil || len(q.Command) == 0 || len(q.Command) > 2048 {
		appendAudit(r, "server.command", s.ID, "rejected", "invalid command")
		http.Error(w, "invalid command", 400)
		return
	}
	pass, err := readServerProperty(resolveServerDir(s), "rcon.password")
	if err != nil || pass == "" {
		appendAudit(r, "server.command", s.ID, "failed", "rcon password unavailable")
		http.Error(w, "RCON password unavailable", 500)
		return
	}
	resp, err := runServerConsoleRCON(s, pass, q.Command)
	if err != nil {
		appendAudit(r, "server.command", s.ID, "failed", commandName(q.Command)+": "+err.Error())
		writeJSONStatus(w, 500, map[string]any{"ok": false, "error": err.Error()})
		return
	}
	appendAudit(r, "server.command", s.ID, "completed", commandName(q.Command))
	writeJSON(w, map[string]any{"ok": true, "response": resp})
}

func apiV1Jobs(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/api/v1/jobs" {
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", 405)
		return
	}
	n, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	writeJSON(w, map[string]any{"jobs": recentControlJobs(n, r.URL.Query().Get("id"))})
}

func apiV1JobRoute(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", 405)
		return
	}
	id := strings.Trim(strings.TrimPrefix(r.URL.Path, "/api/v1/jobs/"), "/")
	j := controlJobByID(id)
	if j == nil {
		http.Error(w, "job not found", 404)
		return
	}
	writeJSON(w, j)
}

func apiV1Events(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", 405)
		return
	}
	n, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	writeJSON(w, map[string]any{"events": recentV4Events(n, r.URL.Query().Get("id"))})
}

func apiV1Audit(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", 405)
		return
	}
	n, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	writeJSON(w, map[string]any{"audit": recentAudit(n)})
}

func writeJSONStatus(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	_ = enc.Encode(v)
}

func initV41Runtime() {
	_ = os.MkdirAll(filepath.Join(v4Root(), "audit"), 0755)
	_ = os.MkdirAll(filepath.Join(v4Root(), "jobs"), 0755)
	initAuditSeq()
	initControlJobs()
	initWebSocketHub()
	go controlStateLoop()
	appendV4Event("info", "host", "", "Control API v1 준비", "WebSocket + Job Queue + Audit Log")
}

func controlStateLoop() {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	last := map[string]string{}
	tick := 0
	for {
		select {
		case <-hostQuit:
			return
		case <-ticker.C:
			tick++
			servers := configSnapshot().Servers
			views := make([]ControlServerView, 0, len(servers))
			for _, s := range servers {
				st := getServerStatus(s)
				view := controlServerViewFromStatus(s, st)
				state := view.State
				if prev, ok := last[s.ID]; !ok || prev != state {
					last[s.ID] = state
					wsPublish("server.state", map[string]any{"server_id": s.ID, "name": s.Name, "state": state, "online": st.Online, "server_tools": view.ServerTools, "bridge": view.Bridge, "timestamp": time.Now().Format(time.RFC3339Nano)})
					if ok {
						appendV4Event("info", "state", s.ID, "서버 상태 변경", prev+" -> "+state)
					}
				}
				if tick%2 == 0 {
					views = append(views, view)
				}
			}
			// Every four seconds push the current operational snapshot so GSCM can
			// update players, Java memory and job progress without HTTP polling.
			if tick%2 == 0 {
				wsPublish("servers.status", map[string]any{"servers": views, "timestamp": time.Now().Format(time.RFC3339Nano)})
				wsPublish("host.status", map[string]any{"host": getHostStats(), "agent_online": agentOnlineNow(), "timestamp": time.Now().Format(time.RFC3339Nano)})
			}
		}
	}
}
