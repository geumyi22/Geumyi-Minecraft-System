package main

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
)

// New profiles are intentionally separate from the installed Paper catalog.
// Importing a profile never installs plugins or rewrites server configuration.
type ManagedInstance struct {
	ID               string `json:"id"`
	Name             string `json:"name"`
	Kind             string `json:"kind"`
	ManagementMode   string `json:"management_mode"`
	ProxyBackend     bool   `json:"proxy_backend,omitempty"`
	Dir              string `json:"dir"`
	JavaPath         string `json:"java_path"`
	MemoryMB         int    `json:"memory_mb"`
	LaunchMode       string `json:"launch_mode"`
	LaunchFile       string `json:"launch_file"`
	MinecraftVersion string `json:"minecraft_version"`
	LoaderVersion    string `json:"loader_version"`
	JavaPort         int    `json:"java_port"`
	TaskName         string `json:"task_name,omitempty"`
	BridgePort       int    `json:"bridge_port,omitempty"`
}

type InstanceStatus struct {
	ManagedInstance
	Status   string `json:"status"`
	Message  string `json:"message"`
	PID      int    `json:"pid"`
	Players  int    `json:"players"`
	CanStart bool   `json:"can_start"`
	CanStop  bool   `json:"can_stop"`
	Busy     bool   `json:"busy"`
	Owner    string `json:"owner"`
}

type instanceCatalog struct {
	Schema    int               `json:"schema"`
	Instances []ManagedInstance `json:"instances"`
}

var instanceCatalogMu sync.Mutex
var instanceReservations = map[string]bool{}
var instanceIDPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9_-]{0,47}$`)

func instanceCatalogPath() string { return filepath.Join(filepath.Dir(configPath), "instances.json") }

func instanceManagementMode(p ManagedInstance) string {
	mode := strings.ToLower(strings.TrimSpace(p.ManagementMode))
	if mode == "" {
		if strings.EqualFold(strings.TrimSpace(p.Kind), "velocity") {
			return "scheduler"
		}
		return "gsc"
	}
	return mode
}

// Missing mode preserves the existing Scheduler-owned Velocity profiles.
// New GSC-owned proxies must explicitly opt into management_mode="gsc".
func isScheduledProxy(p ManagedInstance) bool {
	return strings.EqualFold(strings.TrimSpace(p.Kind), "velocity") && instanceManagementMode(p) == "scheduler"
}

func readInstanceCatalogLocked() ([]ManagedInstance, error) {
	b, err := os.ReadFile(instanceCatalogPath())
	if os.IsNotExist(err) {
		return []ManagedInstance{}, nil
	}
	if err != nil {
		return nil, err
	}
	if len(b) > 2<<20 {
		return nil, errors.New("서버 목록 파일이 너무 큽니다")
	}
	var c instanceCatalog
	if err = json.Unmarshal(b, &c); err != nil {
		return nil, fmt.Errorf("서버 목록을 읽지 못했습니다: %w", err)
	}
	if c.Schema != 1 {
		return nil, errors.New("지원하지 않는 서버 목록 형식입니다")
	}
	if c.Instances == nil {
		c.Instances = []ManagedInstance{}
	}
	for i := range c.Instances {
		c.Instances[i].ManagementMode = instanceManagementMode(c.Instances[i])
		if c.Instances[i].ManagementMode != "gsc" && !isScheduledProxy(c.Instances[i]) {
			return nil, errors.New("서버 목록의 관리 방식이 올바르지 않습니다")
		}
	}
	return c.Instances, nil
}

func listManagedInstances() ([]ManagedInstance, error) {
	instanceCatalogMu.Lock()
	defer instanceCatalogMu.Unlock()
	return readInstanceCatalogLocked()
}

func saveInstanceCatalogLocked(profiles []ManagedInstance) error {
	b, err := json.MarshalIndent(instanceCatalog{Schema: 1, Instances: profiles}, "", "  ")
	if err != nil {
		return err
	}
	path := instanceCatalogPath()
	if err = os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	if old, e := os.ReadFile(path); e == nil {
		if err = os.WriteFile(path+".bak", old, 0600); err != nil {
			return fmt.Errorf("목록 백업 실패: %w", err)
		}
	} else if !os.IsNotExist(e) {
		return e
	}
	f, err := os.CreateTemp(filepath.Dir(path), "instances-*.tmp")
	if err != nil {
		return err
	}
	tmp := f.Name()
	defer os.Remove(tmp)
	if err = f.Chmod(0600); err == nil {
		_, err = f.Write(append(b, '\n'))
	}
	if err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// Resolve existing ancestors as well, preventing aliases/junctions from
// bypassing overlap protection when a new directory does not yet exist.
func canonicalInstanceDir(raw string) (string, error) {
	raw = strings.TrimSpace(raw)
	if !filepath.IsAbs(raw) {
		return "", errors.New("서버 폴더는 절대 경로여야 합니다")
	}
	p := filepath.Clean(raw)
	if filepath.Dir(p) == p {
		return "", errors.New("드라이브 루트를 서버 폴더로 사용할 수 없습니다")
	}
	var missing []string
	ancestor := p
	for {
		_, err := os.Lstat(ancestor)
		if err == nil {
			break
		}
		if !os.IsNotExist(err) {
			return "", err
		}
		parent := filepath.Dir(ancestor)
		if parent == ancestor {
			return "", err
		}
		missing = append(missing, filepath.Base(ancestor))
		ancestor = parent
	}
	resolved, err := filepath.EvalSymlinks(ancestor)
	if err != nil {
		return "", err
	}
	for i := len(missing) - 1; i >= 0; i-- {
		resolved = filepath.Join(resolved, missing[i])
	}
	return filepath.Clean(resolved), nil
}

func instancePathsOverlap(a, b string) bool {
	a = strings.ToLower(filepath.Clean(a))
	b = strings.ToLower(filepath.Clean(b))
	return a == b || strings.HasPrefix(a, b+string(filepath.Separator)) || strings.HasPrefix(b, a+string(filepath.Separator))
}

func validateInstanceShape(p ManagedInstance) (ManagedInstance, error) {
	p.ID = strings.ToLower(strings.TrimSpace(p.ID))
	p.Name = strings.TrimSpace(p.Name)
	p.Kind = strings.ToLower(strings.TrimSpace(p.Kind))
	p.ManagementMode = instanceManagementMode(p)
	if !instanceIDPattern.MatchString(p.ID) {
		return p, errors.New("ID는 영문 소문자·숫자·밑줄·하이픈 1~48자로 입력하세요")
	}
	if p.Name == "" || len([]rune(p.Name)) > 100 {
		return p, errors.New("서버 이름은 1~100자로 입력하세요")
	}
	switch p.Kind {
	case "paper", "spigot", "vanilla", "purpur", "fabric", "forge", "neoforge", "velocity":
	default:
		return p, errors.New("지원하지 않는 서버 종류입니다")
	}
	if p.ManagementMode != "gsc" && !isScheduledProxy(p) {
		return p, errors.New("관리 방식은 GSC 또는 기존 Velocity 예약 작업이어야 합니다")
	}
	if p.Kind == "velocity" && p.ProxyBackend {
		return p, errors.New("Velocity 프록시 자체는 백엔드 서버로 지정할 수 없습니다")
	}
	var err error
	p.Dir, err = canonicalInstanceDir(p.Dir)
	if err != nil {
		return p, err
	}
	if p.JavaPort < 1024 || p.JavaPort > 65535 {
		return p, errors.New("접속 포트는 1024~65535 범위여야 합니다")
	}
	if p.MemoryMB == 0 {
		p.MemoryMB = 2048
	}
	if p.MemoryMB < 256 || p.MemoryMB > 262144 {
		return p, errors.New("메모리는 256~262144 MB 범위여야 합니다")
	}
	p.JavaPath = strings.TrimSpace(p.JavaPath)
	if p.JavaPath != "" && !filepath.IsAbs(p.JavaPath) {
		return p, errors.New("Java 실행 파일은 절대 경로로 지정하세요")
	}
	if isScheduledProxy(p) {
		if strings.TrimSpace(p.TaskName) == "" {
			return p, errors.New("기존 Velocity 예약 작업 이름을 입력하세요")
		}
		if p.BridgePort < 1024 || p.BridgePort > 65535 || p.BridgePort == p.JavaPort {
			return p, errors.New("제어 포트는 접속 포트와 다른 1024~65535 값이어야 합니다")
		}
	} else if p.TaskName != "" || p.BridgePort != 0 {
		return p, errors.New("예약 작업·제어 포트는 기존 Scheduler 관리 Velocity 전용입니다")
	}
	if !isScheduledProxy(p) {
		if p.LaunchMode == "" {
			p.LaunchMode = "jar"
		}
		if p.LaunchMode != "jar" && p.LaunchMode != "script" {
			return p, errors.New("실행 방식은 jar 또는 script여야 합니다")
		}
		if p.Kind == "velocity" && p.LaunchMode != "jar" {
			return p, errors.New("GSC 관리 Velocity는 JAR 실행 방식을 사용하세요")
		}
		if p.LaunchFile == "" || filepath.IsAbs(p.LaunchFile) || strings.ContainsAny(p.LaunchFile, "\r\n\x00\"%!") {
			return p, errors.New("서버 폴더 안의 실행 파일을 지정하세요")
		}
		p.LaunchFile = filepath.Clean(p.LaunchFile)
		if p.LaunchFile == "." || p.LaunchFile == ".." || strings.HasPrefix(p.LaunchFile, ".."+string(filepath.Separator)) {
			return p, errors.New("실행 파일이 서버 폴더를 벗어납니다")
		}
		ext := strings.ToLower(filepath.Ext(p.LaunchFile))
		if (p.LaunchMode == "jar" && ext != ".jar") || (p.LaunchMode == "script" && ext != ".bat" && ext != ".cmd" && ext != ".sh") {
			return p, errors.New("실행 방식과 파일 확장자가 일치하지 않습니다")
		}
	}
	return p, nil
}

func validateInstanceAgainst(p ManagedInstance, profiles []ManagedInstance) error {
	c := configSnapshot()
	if !isScheduledProxy(p) {
		for _, target := range day11ExternalProxyTargets {
			protected, err := canonicalInstanceDir(filepath.Join(externalProxyRoot(), target.ID))
			if err != nil {
				return fmt.Errorf("기존 프록시 폴더 확인 실패: %w", err)
			}
			if instancePathsOverlap(p.Dir, protected) {
				return errors.New("기존 Scheduler 프록시 폴더를 GSC 관리 서버로 전환할 수 없습니다. 새 폴더를 선택하세요")
			}
		}
	}
	for _, s := range c.Servers {
		if p.ID == s.ID {
			return errors.New("기존 서버와 같은 ID는 사용할 수 없습니다")
		}
		if d := configuredServerDir(s); d != "" {
			if resolved, e := canonicalInstanceDir(d); e == nil && instancePathsOverlap(p.Dir, resolved) {
				return fmt.Errorf("기존 서버 %s의 폴더와 겹칩니다", s.Name)
			}
		}
		for _, port := range []int{s.JavaPort, s.RCONPort, s.GDSAPIPort} {
			if port > 0 && (p.JavaPort == port || p.BridgePort == port) {
				return fmt.Errorf("기존 서버 %s와 포트가 겹칩니다", s.Name)
			}
		}
	}
	if p.JavaPort == c.Port || p.BridgePort == c.Port || p.JavaPort == 8790 || p.BridgePort == 8790 {
		return errors.New("GSC 관리 포트와 겹칩니다")
	}
	for _, other := range profiles {
		if other.ID == p.ID {
			return errors.New("이미 등록된 서버 ID입니다")
		}
		if instancePathsOverlap(p.Dir, other.Dir) {
			return fmt.Errorf("%s 서버의 폴더와 겹칩니다", other.Name)
		}
		if p.TaskName != "" && strings.EqualFold(p.TaskName, other.TaskName) {
			return errors.New("이미 등록된 예약 작업입니다")
		}
		for _, port := range []int{other.JavaPort, other.BridgePort} {
			if port > 0 && (p.JavaPort == port || p.BridgePort == port) {
				return fmt.Errorf("%s 서버와 포트가 겹칩니다", other.Name)
			}
		}
	}
	for dir := range instanceReservations {
		if instancePathsOverlap(dir, p.Dir) {
			return errors.New("이 폴더에서 서버 설치가 진행 중입니다")
		}
	}
	return nil
}

func validateManagedInstance(p ManagedInstance) (ManagedInstance, error) {
	p, err := validateInstanceShape(p)
	if err != nil {
		return p, err
	}
	instanceCatalogMu.Lock()
	defer instanceCatalogMu.Unlock()
	profiles, err := readInstanceCatalogLocked()
	if err != nil {
		return p, err
	}
	return p, validateInstanceAgainst(p, profiles)
}

func addManagedInstance(p ManagedInstance) error {
	p, err := validateInstanceShape(p)
	if err != nil {
		return err
	}
	instanceCatalogMu.Lock()
	defer instanceCatalogMu.Unlock()
	profiles, err := readInstanceCatalogLocked()
	if err != nil {
		return err
	}
	if err = validateInstanceAgainst(p, profiles); err != nil {
		return err
	}
	return saveInstanceCatalogLocked(append(profiles, p))
}

func reserveInstanceDirectory(raw string) (func(), error) {
	dir, err := canonicalInstanceDir(raw)
	if err != nil {
		return nil, err
	}
	instanceCatalogMu.Lock()
	defer instanceCatalogMu.Unlock()
	profiles, err := readInstanceCatalogLocked()
	if err != nil {
		return nil, err
	}
	for _, p := range profiles {
		if instancePathsOverlap(dir, p.Dir) {
			return nil, errors.New("등록된 서버 폴더와 겹칩니다")
		}
	}
	for p := range instanceReservations {
		if instancePathsOverlap(dir, p) {
			return nil, errors.New("서버 설치가 이미 진행 중입니다")
		}
	}
	instanceReservations[dir] = true
	var once sync.Once
	return func() {
		once.Do(func() { instanceCatalogMu.Lock(); delete(instanceReservations, dir); instanceCatalogMu.Unlock() })
	}, nil
}

func instanceByID(id string) (ManagedInstance, error) {
	profiles, err := listManagedInstances()
	if err != nil {
		return ManagedInstance{}, err
	}
	for _, p := range profiles {
		if p.ID == id {
			return p, nil
		}
	}
	return ManagedInstance{}, errors.New("등록된 서버를 찾지 못했습니다")
}

// Unlike legacy read-only loopback access, writes always verify an explicit
// credential, including when the request came through the local Client proxy.
func withInstanceMutationAuth(fn http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !hostBrowserRequestAllowed(r) {
			http.Error(w, "허용되지 않는 요청 출처입니다", 403)
			return
		}
		got := strings.TrimSpace(r.Header.Get("X-GSC-Token"))
		if a := r.Header.Get("Authorization"); strings.HasPrefix(a, "Bearer ") {
			got = strings.TrimSpace(strings.TrimPrefix(a, "Bearer "))
		}
		principal := authPrincipal{}
		if got != "" && subtle.ConstantTimeCompare([]byte(got), []byte(configSnapshot().APIToken)) == 1 {
			principal = authPrincipal{Kind: "api_token", ID: "host-token", Name: "Host API Token"}
		} else if got != "" {
			if d, ok := trustedDeviceForToken(got); ok {
				principal = authPrincipal{Kind: "device", ID: d.ID, Name: d.Name}
			}
		}
		if principal.Kind == "" {
			http.Error(w, "인증된 GSC Client에서 실행하세요", 401)
			return
		}
		if shuttingDown.Load() {
			http.Error(w, "전체 종료 중입니다", 409)
			return
		}
		fn(w, r.WithContext(context.WithValue(r.Context(), authContextKey{}, principal)))
	}
}

func decodeInstanceRequest(w http.ResponseWriter, r *http.Request, v any) bool {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", 405)
		return false
	}
	r.Body = http.MaxBytesReader(w, r.Body, 64<<10)
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if err := d.Decode(v); err != nil {
		http.Error(w, "요청 형식이 올바르지 않습니다: "+err.Error(), 400)
		return false
	}
	if err := d.Decode(&struct{}{}); err != io.EOF {
		http.Error(w, "요청은 JSON 한 개여야 합니다", 400)
		return false
	}
	return true
}

func registerInstanceRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/api/v5/instances", requireAuth(apiManagedInstances))
	mux.HandleFunc("/api/v5/instances/import", withInstanceMutationAuth(apiImportInstance))
	mux.HandleFunc("/api/v5/instances/update", withInstanceMutationAuth(apiUpdateInstance))
	mux.HandleFunc("/api/v5/instances/action", withInstanceMutationAuth(apiInstanceAction))
	mux.HandleFunc("/api/v5/instances/prepare", withInstanceMutationAuth(apiInstancePrepare))
	mux.HandleFunc("/api/v5/instances/log", requireAuth(apiInstanceLog))
	mux.HandleFunc("/api/v5/instances/command", withInstanceMutationAuth(apiInstanceCommand))
	mux.HandleFunc("/api/v5/instances/remove", withInstanceMutationAuth(apiRemoveInstance))
}

func apiManagedInstances(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", 405)
		return
	}
	profiles, err := listManagedInstances()
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	states := make([]InstanceStatus, len(profiles))
	var wg sync.WaitGroup
	for i, p := range profiles {
		wg.Add(1)
		go func(i int, p ManagedInstance) { defer wg.Done(); states[i] = managedInstanceStatus(p) }(i, p)
	}
	wg.Wait()
	writeJSON(w, map[string]any{"instances": states, "capabilities": map[string]any{"kinds": []string{"paper", "spigot", "vanilla", "purpur", "velocity", "fabric", "forge", "neoforge"}, "legacy_servers_preserved": true, "automatic_restart": false}})
}

func apiImportInstance(w http.ResponseWriter, r *http.Request) {
	var p ManagedInstance
	if !decodeInstanceRequest(w, r, &p) {
		return
	}
	p, err := validateManagedInstance(p)
	if err == nil {
		err = verifyInstanceFiles(p)
	}
	if err == nil {
		err = addManagedInstance(p)
	}
	if err != nil {
		http.Error(w, err.Error(), 400)
		return
	}
	appendAudit(r, "instance.import", p.ID, "ok", "existing files preserved")
	writeJSON(w, map[string]any{"ok": true, "instance": p})
}

func apiUpdateInstance(w http.ResponseWriter, r *http.Request) {
	var p ManagedInstance
	if !decodeInstanceRequest(w, r, &p) {
		return
	}
	old, err := instanceByID(p.ID)
	if err != nil {
		http.Error(w, err.Error(), 404)
		return
	}
	if !beginInstanceOperation(p.ID, "update") {
		http.Error(w, "작업이 진행 중입니다", 409)
		return
	}
	defer endInstanceOperation(p.ID, nil)
	instanceRuntimeMu.Lock()
	proc := instanceRuntimeLocked(p.ID).process
	instanceRuntimeMu.Unlock()
	if instanceProcessAlive(proc) || instancePortOpen(old.JavaPort) {
		http.Error(w, "서버를 종료한 뒤 설정을 변경하세요", 409)
		return
	}
	if blocked, reason := instanceReceiptBlocks(old); blocked {
		http.Error(w, reason, 409)
		return
	}
	p, err = validateInstanceShape(p)
	if err == nil && p.ProxyBackend != old.ProxyBackend {
		err = errors.New("프록시 백엔드 여부는 설정 편집으로 변경할 수 없습니다. 서버 설정 파일과 연결 구성을 별도로 확인하세요")
	}
	if err == nil && isScheduledProxy(old) != isScheduledProxy(p) {
		err = errors.New("기존 프록시의 실행 소유권은 설정 편집으로 변경할 수 없습니다")
	}
	if err == nil {
		err = verifyInstanceFiles(p)
	}
	if err != nil {
		http.Error(w, err.Error(), 400)
		return
	}
	instanceCatalogMu.Lock()
	defer instanceCatalogMu.Unlock()
	profiles, err := readInstanceCatalogLocked()
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	others := make([]ManagedInstance, 0, len(profiles))
	index := -1
	for i, v := range profiles {
		if v.ID == p.ID {
			index = i
		} else {
			others = append(others, v)
		}
	}
	if index < 0 {
		http.Error(w, "서버 등록이 해제되었습니다", 409)
		return
	}
	if err = validateInstanceAgainst(p, others); err != nil {
		http.Error(w, err.Error(), 400)
		return
	}
	profiles[index] = p
	if err = saveInstanceCatalogLocked(profiles); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	appendAudit(r, "instance.update", p.ID, "ok", "profile only; server files retained")
	writeJSON(w, map[string]any{"ok": true, "instance": p})
}

func apiRemoveInstance(w http.ResponseWriter, r *http.Request) {
	var q struct {
		ID string `json:"id"`
	}
	if !decodeInstanceRequest(w, r, &q) {
		return
	}
	if !beginInstanceOperation(q.ID, "remove") {
		http.Error(w, "작업이 진행 중입니다", 409)
		return
	}
	defer endInstanceOperation(q.ID, nil)
	p, err := instanceByID(q.ID)
	if err != nil {
		http.Error(w, err.Error(), 404)
		return
	}
	s := managedInstanceStatus(p)
	if s.PID > 0 || s.Status == "online" || s.Status == "starting" || s.Status == "external" || instancePortOpen(p.JavaPort) {
		http.Error(w, "서버가 실행 중입니다. 종료한 뒤 등록을 해제하세요", 409)
		return
	}
	instanceCatalogMu.Lock()
	defer instanceCatalogMu.Unlock()
	profiles, err := readInstanceCatalogLocked()
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	out := make([]ManagedInstance, 0, len(profiles))
	for _, v := range profiles {
		if v.ID != q.ID {
			out = append(out, v)
		}
	}
	if err = saveInstanceCatalogLocked(out); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	appendAudit(r, "instance.remove", q.ID, "ok", "files retained")
	writeJSON(w, map[string]any{"ok": true, "message": "목록에서 해제했습니다. 서버 파일은 보존했습니다."})
}
