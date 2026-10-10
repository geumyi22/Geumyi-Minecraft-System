//go:build windows

package main

import (
	"crypto/sha256"
	_ "embed"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"geumyi/servercenter/internal/securestore"
	"io"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

const appVersion = "4.5.0"
const localPort = 8790

//go:embed dashboard.html
var dashboardHTML string

//go:embed app.ico
var appIcon []byte

type ClientConfig struct {
	HostURL string `json:"host_url"`
	Token   string `json:"token"`
}

type remoteGSCSelfUpdateStatus struct {
	Installed         string `json:"installed"`
	Latest            string `json:"latest"`
	Channel           string `json:"channel"`
	Release           string `json:"release"`
	File              string `json:"file"`
	SHA256            string `json:"sha256"`
	Size              int64  `json:"size"`
	SignatureVerified bool   `json:"signature_verified"`
}

type localClientUpdateStatus struct {
	Installed         string `json:"installed"`
	HostInstalled     string `json:"host_installed,omitempty"`
	Latest            string `json:"latest,omitempty"`
	Available         bool   `json:"available"`
	DowngradeBlocked  bool   `json:"downgrade_blocked"`
	TargetRelation    string `json:"target_relation,omitempty"`
	Channel           string `json:"channel,omitempty"`
	Release           string `json:"release,omitempty"`
	File              string `json:"file,omitempty"`
	SHA256            string `json:"sha256,omitempty"`
	Size              int64  `json:"size,omitempty"`
	SignatureVerified bool   `json:"signature_verified"`
	Staged            bool   `json:"staged"`
	StagedPath        string `json:"staged_path,omitempty"`
	Scope             string `json:"scope"`
	Message           string `json:"message"`
	Error             string `json:"error,omitempty"`
}

type POINT struct{ X, Y int32 }
type MSG struct {
	HWnd           uintptr
	Message        uint32
	WParam, LParam uintptr
	Time           uint32
	Pt             POINT
	LPrivate       uint32
}
type WNDCLASSEX struct {
	CbSize                                   uint32
	Style                                    uint32
	LpfnWndProc                              uintptr
	CbClsExtra, CbWndExtra                   int32
	HInstance, HIcon, HCursor, HbrBackground uintptr
	LpszMenuName, LpszClassName              *uint16
	HIconSm                                  uintptr
}
type NOTIFYICONDATA struct {
	CbSize               uint32
	HWnd                 uintptr
	UID                  uint32
	UFlags               uint32
	UCallbackMessage     uint32
	HIcon                uintptr
	SzTip                [128]uint16
	DwState, DwStateMask uint32
	SzInfo               [256]uint16
	UTimeoutOrVersion    uint32
	SzInfoTitle          [64]uint16
	DwInfoFlags          uint32
	GuidItem             [16]byte
	HBalloonIcon         uintptr
}

const (
	WM_DESTROY           = 0x0002
	WM_COMMAND           = 0x0111
	WM_CONTEXTMENU       = 0x007B
	WM_LBUTTONUP         = 0x0202
	WM_LBUTTONDBLCLK     = 0x0203
	WM_RBUTTONUP         = 0x0205
	WM_USER              = 0x0400
	NIN_SELECT           = WM_USER
	NIN_KEYSELECT        = WM_USER + 1
	WM_APP               = 0x8000
	WS_POPUP             = 0x80000000
	WS_EX_TOOLWINDOW     = 0x00000080
	NIM_ADD              = 0
	NIM_MODIFY           = 1
	NIM_DELETE           = 2
	NIM_SETVERSION       = 4
	NOTIFYICON_VERSION_4 = 4
	NIF_MESSAGE          = 1
	NIF_ICON             = 2
	NIF_TIP              = 4
	NIF_INFO             = 0x10
	NIIF_INFO            = 1
	NIIF_WARNING         = 2
	MF_STRING            = 0
	MF_SEPARATOR         = 0x800
	MF_POPUP             = 0x10
	TPM_RIGHTBUTTON      = 0x0002
	TPM_RETURNCMD        = 0x0100
	IMAGE_ICON           = 1
	LR_LOADFROMFILE      = 0x0010
	LR_DEFAULTSIZE       = 0x0040
	IDC_ARROW            = 32512
	CMD_DASH             = 1001
	CMD_SETTINGS         = 1002
	CMD_REFRESH          = 1003
	CMD_CONSOLE          = 1004
	CMD_EXIT             = 1099
	CMD_CLIENT_EXIT      = 1098
	CMD_WILD_START       = 1101
	CMD_WILD_RESTART     = 1102
	CMD_WILD_STOP        = 1103
	CMD_PLAY_START       = 1201
	CMD_PLAY_RESTART     = 1202
	CMD_PLAY_STOP        = 1203
	CMD_AGENT_START      = 1301
	CMD_AGENT_RESTART    = 1302
	CMD_AGENT_STOP       = 1303
)

var (
	user32               = syscall.NewLazyDLL("user32.dll")
	shell32              = syscall.NewLazyDLL("shell32.dll")
	kernel32             = syscall.NewLazyDLL("kernel32.dll")
	pRegisterClassEx     = user32.NewProc("RegisterClassExW")
	pCreateWindowEx      = user32.NewProc("CreateWindowExW")
	pDefWindowProc       = user32.NewProc("DefWindowProcW")
	pGetMessage          = user32.NewProc("GetMessageW")
	pTranslateMessage    = user32.NewProc("TranslateMessage")
	pDispatchMessage     = user32.NewProc("DispatchMessageW")
	pPostQuitMessage     = user32.NewProc("PostQuitMessage")
	pPostMessage         = user32.NewProc("PostMessageW")
	pShellExecute        = shell32.NewProc("ShellExecuteW")
	pSetForegroundWindow = user32.NewProc("SetForegroundWindow")
	pLoadCursor          = user32.NewProc("LoadCursorW")
	pLoadImage           = user32.NewProc("LoadImageW")
	pCreatePopupMenu     = user32.NewProc("CreatePopupMenu")
	pAppendMenu          = user32.NewProc("AppendMenuW")
	pTrackPopupMenu      = user32.NewProc("TrackPopupMenu")
	pDestroyMenu         = user32.NewProc("DestroyMenu")
	pGetCursorPos        = user32.NewProc("GetCursorPos")
	pGetModuleHandle     = kernel32.NewProc("GetModuleHandleW")
	pShellNotifyIcon     = shell32.NewProc("Shell_NotifyIconW")
	cfg                  ClientConfig
	clientConfigMu       sync.RWMutex
	clientUpdateApplyMu  sync.Mutex
	clientUpdateApplying bool
	cfgPath, localURL    string
	mainHWND, iconH      uintptr
	lastTrayOpen         time.Time
	clientHTTPServer     *http.Server
	clientProxyTransport = &http.Transport{
		Proxy:                 http.ProxyFromEnvironment,
		DialContext:           (&net.Dialer{Timeout: 5 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
		MaxIdleConns:          32,
		MaxIdleConnsPerHost:   8,
		MaxConnsPerHost:       16,
		IdleConnTimeout:       45 * time.Second,
		TLSHandshakeTimeout:   5 * time.Second,
		ResponseHeaderTimeout: 12 * time.Second,
		ForceAttemptHTTP2:     true,
	}
	clientLongProxyTransport = func() *http.Transport {
		t := clientProxyTransport.Clone()
		t.ResponseHeaderTimeout = 30 * time.Minute
		return t
	}()
)

func wptr(s string) *uint16 { p, _ := syscall.UTF16PtrFromString(s); return p }
func copyUTF16(dst []uint16, s string) {
	v, _ := syscall.UTF16FromString(s)
	if len(v) > len(dst) {
		v = v[:len(dst)]
	}
	copy(dst, v)
}
func loword(v uintptr) uint16 { return uint16(v & 0xffff) }

func main() {
	if len(os.Args) > 1 && os.Args[1] == "--start-host" {
		_ = runHostTask()
		return
	}
	cfgPath = clientConfigPath()
	cfg = loadClientConfig(cfgPath)
	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", localPort))
	if err != nil {
		openAppWindow(fmt.Sprintf("http://127.0.0.1:%d/", localPort))
		return
	}
	localURL = fmt.Sprintf("http://127.0.0.1:%d", localPort)
	mux := http.NewServeMux()
	mux.HandleFunc("/", serveDashboard)
	mux.HandleFunc("/client/config", clientConfigAPI)
	mux.HandleFunc("/client/update/status", clientUpdateStatusAPI)
	mux.HandleFunc("/client/update/stage", clientUpdateStageAPI)
	mux.HandleFunc("/client/update/apply", clientUpdateApplyAPI)
	mux.HandleFunc("/app.ico", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "image/x-icon")
		_, _ = w.Write(appIcon)
	})
	mux.HandleFunc("/api/", proxyAPI)
	clientHTTPServer = &http.Server{
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		IdleTimeout:       30 * time.Second,
		MaxHeaderBytes:    1 << 20,
	}
	go func() {
		if e := clientHTTPServer.Serve(ln); e != nil && e != http.ErrServerClosed && !clientExiting.Load() {
			showBalloon("관리 UI 오류", e.Error(), true)
		}
	}()
	go ensureLocalHost()
	runTray()
	shutdownClientRuntime()
}

func clientConfigPath() string {
	b := os.Getenv("APPDATA")
	if b == "" {
		b = os.Getenv("LOCALAPPDATA")
	}
	if b == "" {
		b = "."
	}
	return filepath.Join(b, "GeumyiServerCenter", "client.json")
}
func loadClientConfig(path string) ClientConfig {
	c := ClientConfig{HostURL: "http://127.0.0.1:8787"}
	if b, e := os.ReadFile(path); e == nil {
		_ = json.Unmarshal(b, &c)
		if plain, err := securestore.UnprotectString(c.Token); err == nil {
			c.Token = plain
		}
	}
	c.HostURL = strings.TrimRight(strings.TrimSpace(c.HostURL), "/")
	return c
}
func saveClientConfig() error {
	c := clientConfigSnapshot()
	if e := os.MkdirAll(filepath.Dir(cfgPath), 0755); e != nil {
		return e
	}
	disk := c
	if protected, err := securestore.ProtectString(c.Token, false); err == nil {
		disk.Token = protected
	} else {
		return err
	}
	b, _ := json.MarshalIndent(disk, "", "  ")
	return os.WriteFile(cfgPath, b, 0600)
}

func serveDashboard(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	html := strings.Replace(dashboardHTML, "</head>", `<link rel="icon" href="/app.ico"></head>`, 1)
	_, _ = io.WriteString(w, html)
}
func clientConfigAPI(w http.ResponseWriter, r *http.Request) {
	cfg := clientConfigSnapshot()
	if r.Method == "GET" {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"host_url": cfg.HostURL, "token": cfg.Token, "token_set": cfg.Token != "", "version": appVersion})
		return
	}
	if r.Method != "POST" {
		http.Error(w, "method not allowed", 405)
		return
	}
	var q ClientConfig
	if json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q) != nil {
		http.Error(w, "잘못된 JSON", 400)
		return
	}
	q.HostURL = strings.TrimRight(strings.TrimSpace(q.HostURL), "/")
	if q.HostURL == "" {
		http.Error(w, "Host URL이 비어 있습니다", 400)
		return
	}
	u, e := url.Parse(q.HostURL)
	if e != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		http.Error(w, "Host URL 형식 오류", 400)
		return
	}
	clientConfigMu.Lock()
	cfg = q
	setClientConfigLocked(q)
	clientConfigMu.Unlock()
	if e := saveClientConfig(); e != nil {
		http.Error(w, e.Error(), 500)
		return
	}
	w.WriteHeader(204)
}


const defaultUpdateRepository = "geumyi22/Geumyi-Minecraft-System"

func clientUpdateHostJSON(path string, out any) error {
	cfg := clientConfigSnapshot()
	base := strings.TrimRight(strings.TrimSpace(cfg.HostURL), "/")
	if base == "" {
		return fmt.Errorf("Host URL이 설정되지 않았습니다")
	}
	req, err := http.NewRequest(http.MethodGet, base+path, nil)
	if err != nil {
		return err
	}
	if cfg.Token != "" {
		req.Header.Set("Authorization", "Bearer "+cfg.Token)
	}
	h := &http.Client{Timeout: 45 * time.Second}
	resp, err := h.Do(req)
	if err != nil {
		return fmt.Errorf("서버 PC 업데이트 정보 확인 실패: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
		msg := strings.TrimSpace(string(b))
		if msg == "" {
			msg = resp.Status
		}
		return fmt.Errorf("서버 PC 업데이트 정보 확인 실패: %s", msg)
	}
	if err = json.NewDecoder(io.LimitReader(resp.Body, 4<<20)).Decode(out); err != nil {
		return fmt.Errorf("서버 PC 업데이트 응답 해석 실패: %w", err)
	}
	return nil
}

func parseClientVersion(v string) ([]int, error) {
	v = strings.TrimSpace(strings.TrimPrefix(strings.TrimPrefix(v, "v"), "V"))
	if i := strings.IndexAny(v, "-+"); i >= 0 {
		v = v[:i]
	}
	parts := strings.Split(v, ".")
	if len(parts) < 2 || len(parts) > 4 {
		return nil, fmt.Errorf("지원하지 않는 버전 형식: %s", v)
	}
	out := make([]int, len(parts))
	for i, p := range parts {
		n, err := strconv.Atoi(p)
		if err != nil || n < 0 {
			return nil, fmt.Errorf("지원하지 않는 버전 형식: %s", v)
		}
		out[i] = n
	}
	return out, nil
}

// Keep the client-only self-update comparator consistent with the Host.
// Numeric core comparison alone incorrectly treated 4.3.9-rc.1 as equal to
// 4.3.9, preventing RC -> final upgrades on a secondary client PC.
func clientPrerelease(v string) (string, error) {
	v = strings.TrimSpace(strings.TrimPrefix(strings.TrimPrefix(v, "v"), "V"))
	if i := strings.IndexByte(v, '+'); i >= 0 {
		v = v[:i]
	}
	i := strings.IndexByte(v, '-')
	if i < 0 {
		return "", nil
	}
	pre := v[i+1:]
	if pre == "" {
		return "", fmt.Errorf("empty client prerelease identifier")
	}
	for _, part := range strings.Split(pre, ".") {
		if part == "" {
			return "", fmt.Errorf("empty client prerelease segment")
		}
		if len(part) > 1 && part[0] == '0' && clientNumericIdentifier(part) {
			return "", fmt.Errorf("numeric client prerelease segment has leading zeros")
		}
		for _, c := range part {
			if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'z' ||
				c >= 'A' && c <= 'Z' || c == '-') {
				return "", fmt.Errorf("invalid client prerelease segment")
			}
		}
	}
	return pre, nil
}
func clientNumericIdentifier(v string) bool {
	if v == "" {
		return false
	}
	for _, c := range v {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}
func compareClientPrerelease(a, b string) int {
	if a == b {
		return 0
	}
	if a == "" {
		return 1
	}
	if b == "" {
		return -1
	}
	left, right := strings.Split(a, "."), strings.Split(b, ".")
	for i := 0; i < len(left) && i < len(right); i++ {
		if left[i] == right[i] {
			continue
		}
		ln, rn := clientNumericIdentifier(left[i]), clientNumericIdentifier(right[i])
		if ln && !rn {
			return -1
		}
		if !ln && rn {
			return 1
		}
		if ln {
			a1, b1 := strings.TrimLeft(left[i], "0"), strings.TrimLeft(right[i], "0")
			if len(a1) < len(b1) {
				return -1
			}
			if len(a1) > len(b1) {
				return 1
			}
			if a1 < b1 {
				return -1
			}
			return 1
		}
		if left[i] < right[i] {
			return -1
		}
		return 1
	}
	if len(left) < len(right) {
		return -1
	}
	return 1
}
func compareClientVersions(a, b string) (int, error) {
	av, err := parseClientVersion(a)
	if err != nil {
		return 0, err
	}
	bv, err := parseClientVersion(b)
	if err != nil {
		return 0, err
	}
	// Validate both prereleases before comparing the numeric core; otherwise
	// a malformed target with a larger core would silently pass.
	ap, err := clientPrerelease(a)
	if err != nil {
		return 0, err
	}
	bp, err := clientPrerelease(b)
	if err != nil {
		return 0, err
	}
	n := len(av)
	if len(bv) > n {
		n = len(bv)
	}
	for i := 0; i < n; i++ {
		ai, bi := 0, 0
		if i < len(av) {
			ai = av[i]
		}
		if i < len(bv) {
			bi = bv[i]
		}
		if ai < bi {
			return -1, nil
		}
		if ai > bi {
			return 1, nil
		}
	}
	return compareClientPrerelease(ap, bp), nil
}

func safeClientUpdatePart(v string) string {
	v = strings.TrimSpace(v)
	var b strings.Builder
	for _, r := range v {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '.' || r == '-' || r == '_' {
			b.WriteRune(r)
		} else {
			b.WriteByte('_')
		}
	}
	if b.Len() == 0 {
		return "unknown"
	}
	return b.String()
}

func clientUpdateStagePath(st remoteGSCSelfUpdateStatus) string {
	root := os.Getenv("LOCALAPPDATA")
	if strings.TrimSpace(root) == "" {
		root = filepath.Dir(cfgPath)
	}
	return filepath.Join(root, "GeumyiServerCenter", "Staging", "Client", safeClientUpdatePart(st.Release), filepath.Base(st.File))
}

func clientFileSHA256(p string) (string, error) {
	f, err := os.Open(p)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err = io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func verifyClientUpdateStage(p string, st remoteGSCSelfUpdateStatus) bool {
	info, err := os.Stat(p)
	if err != nil || info.IsDir() {
		return false
	}
	if st.Size > 0 && info.Size() != st.Size {
		return false
	}
	sum, err := clientFileSHA256(p)
	return err == nil && len(st.SHA256) == 64 && strings.EqualFold(sum, st.SHA256)
}

func validGitHubRepository(repo string) bool {
	parts := strings.Split(strings.TrimSpace(repo), "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return false
	}
	for _, part := range parts {
		for _, r := range part {
			if !((r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '.' || r == '-' || r == '_') {
				return false
			}
		}
	}
	return true
}

func clientUpdateRepository() string {
	var overview struct {
		Settings struct {
			Repository string `json:"repository"`
		} `json:"settings"`
	}
	if err := clientUpdateHostJSON("/api/v4/update/status", &overview); err == nil && validGitHubRepository(overview.Settings.Repository) {
		return strings.TrimSpace(overview.Settings.Repository)
	}
	return defaultUpdateRepository
}

func queryClientUpdateTarget(fresh bool) (remoteGSCSelfUpdateStatus, error) {
	var st remoteGSCSelfUpdateStatus
	path := "/api/v4/update/self/status"
	if fresh {
		path += "?fresh=1"
	}
	if err := clientUpdateHostJSON(path, &st); err != nil {
		return st, err
	}
	if !st.SignatureVerified {
		return st, fmt.Errorf("서버 PC가 검증된 서명 정보를 제공하지 않았습니다")
	}
	if strings.TrimSpace(st.Latest) == "" || strings.TrimSpace(st.Release) == "" || strings.TrimSpace(st.File) == "" || len(st.SHA256) != 64 || st.Size <= 0 {
		return st, fmt.Errorf("검증된 GSC release metadata가 불완전합니다")
	}
	if filepath.Base(st.File) != st.File || !strings.HasSuffix(strings.ToLower(st.File), ".exe") {
		return st, fmt.Errorf("검증된 GSC 설치 파일명이 안전하지 않습니다")
	}
	return st, nil
}

func buildLocalClientUpdateStatus(fresh bool) localClientUpdateStatus {
	out := localClientUpdateStatus{Installed: appVersion, Scope: "local_client", Message: "이 PC의 GSC Client 업데이트 확인 중"}
	remote, err := queryClientUpdateTarget(fresh)
	if err != nil {
		out.Error = err.Error()
		out.Message = "이 PC Client 업데이트 확인 실패"
		return out
	}
	out.HostInstalled = remote.Installed
	out.Latest = remote.Latest
	out.Channel = remote.Channel
	out.Release = remote.Release
	out.File = remote.File
	out.SHA256 = remote.SHA256
	out.Size = remote.Size
	out.SignatureVerified = remote.SignatureVerified
	cmp, err := compareClientVersions(appVersion, remote.Latest)
	if err != nil {
		out.Error = err.Error()
		out.Message = "이 PC Client 버전 비교 실패"
		return out
	}
	switch {
	case cmp < 0:
		out.Available = true
		out.TargetRelation = "newer"
		out.Message = "이 PC의 GSC Client 업데이트 사용 가능"
	case cmp == 0:
		out.TargetRelation = "same"
		out.Message = "이 PC의 GSC Client가 현재 검증 release와 일치합니다"
	default:
		out.TargetRelation = "older"
		out.DowngradeBlocked = true
		out.Message = "이 PC의 GSC Client가 검증 release보다 최신입니다 · 다운그레이드 차단"
	}
	stage := clientUpdateStagePath(remote)
	if verifyClientUpdateStage(stage, remote) {
		out.Staged = true
		out.StagedPath = stage
	}
	return out
}

func clientUpdateStatusAPI(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", http.StatusMethodNotAllowed)
		return
	}
	force := r.URL.Query().Get("fresh") == "1"
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	_ = json.NewEncoder(w).Encode(buildLocalClientUpdateStatus(force))
}

func downloadClientUpdateArtifact(downloadURL, dst string, expectedSize int64, expectedSHA string) error {
	req, err := http.NewRequest(http.MethodGet, downloadURL, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "GeumyiServerCenter/"+appVersion)
	h := &http.Client{Timeout: 20 * time.Minute}
	resp, err := h.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		return fmt.Errorf("설치 파일 다운로드 HTTP %d", resp.StatusCode)
	}
	if err = os.MkdirAll(filepath.Dir(dst), 0700); err != nil {
		return err
	}
	tmp := dst + ".tmp"
	_ = os.Remove(tmp)
	f, err := os.OpenFile(tmp, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	hh := sha256.New()
	n, cpErr := io.Copy(io.MultiWriter(f, hh), resp.Body)
	closeErr := f.Close()
	if cpErr != nil {
		_ = os.Remove(tmp)
		return cpErr
	}
	if closeErr != nil {
		_ = os.Remove(tmp)
		return closeErr
	}
	if expectedSize > 0 && n != expectedSize {
		_ = os.Remove(tmp)
		return fmt.Errorf("설치 파일 크기 불일치: expected=%d actual=%d", expectedSize, n)
	}
	got := hex.EncodeToString(hh.Sum(nil))
	if !strings.EqualFold(got, expectedSHA) {
		_ = os.Remove(tmp)
		return fmt.Errorf("설치 파일 SHA-256 불일치")
	}
	_ = os.Remove(dst)
	if err = os.Rename(tmp, dst); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return nil
}

func clientUpdateStageAPI(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", http.StatusMethodNotAllowed)
		return
	}
	remote, err := queryClientUpdateTarget(true)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	cmp, err := compareClientVersions(appVersion, remote.Latest)
	if err != nil {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	if cmp >= 0 {
		http.Error(w, "이 PC의 GSC Client는 이미 검증 target 이상입니다", http.StatusConflict)
		return
	}
	repo := clientUpdateRepository()
	if !validGitHubRepository(repo) {
		http.Error(w, "GitHub repository 설정이 안전하지 않습니다", http.StatusConflict)
		return
	}
	downloadURL := "https://github.com/" + repo + "/releases/download/" + url.PathEscape(remote.Release) + "/" + url.PathEscape(remote.File)
	dst := clientUpdateStagePath(remote)
	if err = downloadClientUpdateArtifact(downloadURL, dst, remote.Size, remote.SHA256); err != nil {
		http.Error(w, "이 PC Client update staging 실패: "+err.Error(), http.StatusBadGateway)
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"ok": true, "scope": "local_client", "installed": appVersion, "target": remote.Latest,
		"host_installed": remote.Installed, "release": remote.Release, "sha256": remote.SHA256,
		"staged_path": dst, "host_modified": false, "minecraft_velocity_touched": false,
	})
}

func clientUpdateApplyAPI(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", http.StatusMethodNotAllowed)
		return
	}
	var q struct {
		Confirm string `json:"confirm"`
	}
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q); err != nil {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	if q.Confirm != "APPLY_LOCAL_GSC_CLIENT_UPDATE" {
		http.Error(w, "confirm must be APPLY_LOCAL_GSC_CLIENT_UPDATE", http.StatusBadRequest)
		return
	}
	remote, err := queryClientUpdateTarget(false)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	cmp, err := compareClientVersions(appVersion, remote.Latest)
	if err != nil || cmp >= 0 {
		http.Error(w, "이 PC의 GSC Client에 적용할 newer verified target이 없습니다", http.StatusConflict)
		return
	}
	stage := clientUpdateStagePath(remote)
	if !verifyClientUpdateStage(stage, remote) {
		http.Error(w, "검증된 이 PC Client staging 설치 파일이 필요합니다", http.StatusConflict)
		return
	}
	clientUpdateApplyMu.Lock()
	if clientUpdateApplying {
		clientUpdateApplyMu.Unlock()
		http.Error(w, "이 PC Client update helper가 이미 시작되었습니다", http.StatusConflict)
		return
	}
	clientUpdateApplying = true
	clientUpdateApplyMu.Unlock()
	cmd := exec.Command(stage, "--client-self-update")
	cmd.Dir = filepath.Dir(stage)
	if err = cmd.Start(); err != nil {
		clientUpdateApplyMu.Lock()
		clientUpdateApplying = false
		clientUpdateApplyMu.Unlock()
		http.Error(w, "이 PC Client update helper 시작 실패: "+err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"ok": true, "accepted": true, "scope": "local_client", "installed": appVersion,
		"target": remote.Latest, "host_modified": false, "minecraft_velocity_touched": false,
	})
	if f, ok := w.(http.Flusher); ok {
		f.Flush()
	}
}
func proxyAPI(w http.ResponseWriter, r *http.Request) {
	cfg := clientConfigSnapshot()
	base := strings.TrimRight(strings.TrimSpace(cfg.HostURL), "/")
	if base == "" {
		http.Error(w, "Host URL not configured", 503)
		return
	}
	target, e := url.Parse(base)
	if e != nil {
		http.Error(w, "bad host url", 500)
		return
	}
	p := httputil.NewSingleHostReverseProxy(target)
	transport := clientProxyTransport
	switch r.URL.Path {
	case "/api/v4/backup", "/api/v4/backup/verify", "/api/v4/restore",
		"/api/v4/update/external/apply-proxy", "/api/v4/update/canary-rollout":
		// These operations can legitimately spend minutes before the Host writes
		// response headers. External proxy apply performs rolling stop -> verified
		// JAR replace -> restart -> Java/Bedrock health gates for up to 3 proxies.
		// Keep the short timeout for ordinary UI/status calls, but never convert a
		// still-running safe transaction into a false "server PC connection failed".
		transport = clientLongProxyTransport
	}
	p.Transport = transport
	orig := p.Director
	p.Director = func(req *http.Request) {
		orig(req)
		if cfg.Token != "" {
			req.Header.Set("Authorization", "Bearer "+cfg.Token)
		}
		req.Host = target.Host
	}
	p.ErrorHandler = func(w http.ResponseWriter, r *http.Request, e error) {
		transport.CloseIdleConnections()
		http.Error(w, "서버 PC 연결 실패: "+e.Error(), 502)
	}
	p.ServeHTTP(w, r)
}

func runTray() {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	inst, _, _ := pGetModuleHandle.Call(0)
	iconPath := ensureRuntimeIcon()
	if iconPath != "" {
		iconH, _, _ = pLoadImage.Call(0, uintptr(unsafe.Pointer(wptr(iconPath))), IMAGE_ICON, 32, 32, LR_LOADFROMFILE|LR_DEFAULTSIZE)
	}
	cur, _, _ := pLoadCursor.Call(0, IDC_ARROW)
	cls := wptr("GeumyiServerCenterTrayV4")
	wc := WNDCLASSEX{CbSize: uint32(unsafe.Sizeof(WNDCLASSEX{})), Style: 0x0008, LpfnWndProc: syscall.NewCallback(wndProc), HInstance: inst, HIcon: iconH, HCursor: cur, LpszClassName: cls, HIconSm: iconH}
	pRegisterClassEx.Call(uintptr(unsafe.Pointer(&wc)))
	mainHWND, _, _ = pCreateWindowEx.Call(WS_EX_TOOLWINDOW, uintptr(unsafe.Pointer(cls)), uintptr(unsafe.Pointer(wptr("Geumyi Server Center"))), WS_POPUP, 0, 0, 1, 1, 0, 0, inst, 0)
	addTrayIcon()
	bg := false
	for _, a := range os.Args[1:] {
		if strings.EqualFold(a, "--background") {
			bg = true
		}
	}
	if !bg {
		openDashboard("dashboard")
	} else {
		showBalloon("Geumyi Server Center", "시스템 트레이에서 서버 상태를 감시합니다.", false)
	}
	var msg MSG
	for {
		r, _, _ := pGetMessage.Call(uintptr(unsafe.Pointer(&msg)), 0, 0, 0)
		if int32(r) <= 0 {
			break
		}
		pTranslateMessage.Call(uintptr(unsafe.Pointer(&msg)))
		pDispatchMessage.Call(uintptr(unsafe.Pointer(&msg)))
	}
	removeTrayIcon()
}
func wndProc(hwnd uintptr, msg uint32, w, l uintptr) uintptr {
	switch msg {
	case WM_APP + 1:
		// NOTIFYICON_VERSION_4 packs the notification code into LOWORD(lParam)
		// and the icon ID into HIWORD(lParam). Comparing the full lParam makes
		// left/right-click handling silently fail on modern Windows.
		ev := uint32(loword(l))
		switch ev {
		case WM_LBUTTONUP, WM_LBUTTONDBLCLK, NIN_SELECT, NIN_KEYSELECT:
			openDashboardFromTray()
			return 0
		case WM_RBUTTONUP, WM_CONTEXTMENU:
			showTrayMenu(hwnd)
			return 0
		}
	case WM_COMMAND:
		handleTrayCommand(int(loword(w)))
		return 0
	case WM_APP + 2:
		pPostQuitMessage.Call(0)
		return 0
	case WM_DESTROY:
		pPostQuitMessage.Call(0)
		return 0
	}
	r, _, _ := pDefWindowProc.Call(hwnd, uintptr(msg), w, l)
	return r
}
func addTrayIcon() {
	var n NOTIFYICONDATA
	n.CbSize = uint32(unsafe.Sizeof(n))
	n.HWnd = mainHWND
	n.UID = 1
	n.UFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP
	n.UCallbackMessage = WM_APP + 1
	n.HIcon = iconH
	copyUTF16(n.SzTip[:], "Geumyi Server Center v4")
	pShellNotifyIcon.Call(NIM_ADD, uintptr(unsafe.Pointer(&n)))
	n.UTimeoutOrVersion = NOTIFYICON_VERSION_4
	pShellNotifyIcon.Call(NIM_SETVERSION, uintptr(unsafe.Pointer(&n)))
}
func removeTrayIcon() {
	var n NOTIFYICONDATA
	n.CbSize = uint32(unsafe.Sizeof(n))
	n.HWnd = mainHWND
	n.UID = 1
	pShellNotifyIcon.Call(NIM_DELETE, uintptr(unsafe.Pointer(&n)))
}
func koreanMessage(s string) string {
	r := strings.NewReplacer(
		"normal shutdown", "정상 종료", "Normal shutdown", "정상 종료",
		"planned shutdown", "예약 종료", "Planned shutdown", "예약 종료",
		"shutdown in progress", "종료 진행 중", "startup timeout", "시작 시간 초과",
		"OFFLINE", "오프라인", "ONLINE", "온라인", "Agent", "에이전트",
	)
	return r.Replace(strings.TrimSpace(s))
}
func showBalloon(title, text string, warn bool) {
	var n NOTIFYICONDATA
	n.CbSize = uint32(unsafe.Sizeof(n))
	n.HWnd = mainHWND
	n.UID = 1
	n.UFlags = NIF_INFO
	copyUTF16(n.SzInfoTitle[:], title)
	copyUTF16(n.SzInfo[:], koreanMessage(text))
	if warn {
		n.DwInfoFlags = NIIF_WARNING
	} else {
		n.DwInfoFlags = NIIF_INFO
	}
	pShellNotifyIcon.Call(NIM_MODIFY, uintptr(unsafe.Pointer(&n)))
}
func appendMenu(m uintptr, flags uintptr, id uintptr, text string) {
	pAppendMenu.Call(m, flags, id, uintptr(unsafe.Pointer(wptr(text))))
}
func openDashboardFromTray() {
	// A Windows double-click contains multiple click notifications. Debounce so
	// one user gesture opens only one dashboard window.
	now := time.Now()
	if !lastTrayOpen.IsZero() && now.Sub(lastTrayOpen) < 650*time.Millisecond {
		return
	}
	lastTrayOpen = now
	openDashboard("dashboard")
}

func showTrayMenu(hwnd uintptr) {
	root, _, _ := pCreatePopupMenu.Call()
	defer pDestroyMenu.Call(root)
	wild, _, _ := pCreatePopupMenu.Call()
	play, _, _ := pCreatePopupMenu.Call()
	agent, _, _ := pCreatePopupMenu.Call()
	appendMenu(root, MF_STRING, CMD_DASH, "대시보드 열기")
	appendMenu(root, MF_STRING, CMD_SETTINGS, "설정")
	appendMenu(root, MF_STRING, CMD_REFRESH, "상태 새로고침")
	appendMenu(root, MF_SEPARATOR, 0, "")
	appendMenu(wild, MF_STRING, CMD_WILD_START, "시작")
	appendMenu(wild, MF_STRING, CMD_WILD_RESTART, "재시작")
	appendMenu(wild, MF_STRING, CMD_WILD_STOP, "정상 종료")
	appendMenu(play, MF_STRING, CMD_PLAY_START, "시작")
	appendMenu(play, MF_STRING, CMD_PLAY_RESTART, "재시작")
	appendMenu(play, MF_STRING, CMD_PLAY_STOP, "정상 종료")
	appendMenu(agent, MF_STRING, CMD_AGENT_START, "시작 / 복구")
	appendMenu(agent, MF_STRING, CMD_AGENT_RESTART, "재시작")
	appendMenu(agent, MF_STRING, CMD_AGENT_STOP, "종료")
	appendMenu(root, MF_POPUP, wild, "야생 서버")
	appendMenu(root, MF_POPUP, play, "놀이터 서버")
	appendMenu(root, MF_POPUP, agent, "Discord / GDS 에이전트")
	appendMenu(root, MF_STRING, CMD_CONSOLE, "콘솔 / Web RCON")
	appendMenu(root, MF_SEPARATOR, 0, "")
	appendMenu(root, MF_STRING, CMD_EXIT, "전체 종료 (서버 · Agent · Host)")
	appendMenu(root, MF_STRING, CMD_CLIENT_EXIT, "이 PC의 관리창만 종료")
	var pt POINT
	pGetCursorPos.Call(uintptr(unsafe.Pointer(&pt)))
	pSetForegroundWindow.Call(hwnd)
	cmd, _, _ := pTrackPopupMenu.Call(root, TPM_RIGHTBUTTON|TPM_RETURNCMD, uintptr(pt.X), uintptr(pt.Y), 0, hwnd, 0)
	if cmd != 0 {
		handleTrayCommand(int(cmd))
	}
}
func handleTrayCommand(id int) {
	switch id {
	case CMD_DASH:
		openDashboard("dashboard")
	case CMD_SETTINGS:
		openDashboard("settings")
	case CMD_CONSOLE:
		openDashboard("console")
	case CMD_REFRESH:
		go trayRefresh()
	case CMD_WILD_START:
		go trayServerAction("wild", "start")
	case CMD_WILD_RESTART:
		go trayServerAction("wild", "restart")
	case CMD_WILD_STOP:
		go trayServerAction("wild", "stop")
	case CMD_PLAY_START:
		go trayServerAction("playground", "start")
	case CMD_PLAY_RESTART:
		go trayServerAction("playground", "restart")
	case CMD_PLAY_STOP:
		go trayServerAction("playground", "stop")
	case CMD_AGENT_START:
		go trayAgentAction("start")
	case CMD_AGENT_RESTART:
		go trayAgentAction("restart")
	case CMD_AGENT_STOP:
		go trayAgentAction("stop")
	case CMD_EXIT:
		beginClientShutdown()
	case CMD_CLIENT_EXIT:
		go closeClientWindows()
	}
}
func hostRequest(method, path, body string) ([]byte, error) {
	cfg := clientConfigSnapshot()
	base := strings.TrimRight(cfg.HostURL, "/")
	req, e := http.NewRequest(method, base+path, strings.NewReader(body))
	if e != nil {
		return nil, e
	}
	if cfg.Token != "" {
		req.Header.Set("Authorization", "Bearer "+cfg.Token)
	}
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	c := http.Client{Timeout: 8 * time.Second}
	r, e := c.Do(req)
	if e != nil {
		return nil, e
	}
	defer r.Body.Close()
	b, _ := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if r.StatusCode/100 != 2 {
		return b, fmt.Errorf("HTTP %d: %s", r.StatusCode, strings.TrimSpace(string(b)))
	}
	return b, nil
}
func trayServerAction(id, action string) {
	b, e := hostRequest("POST", "/api/server/action", fmt.Sprintf(`{"id":%q,"action":%q}`, id, action))
	if e != nil {
		showBalloon("서버 제어 실패", e.Error(), true)
		return
	}
	var x map[string]any
	_ = json.Unmarshal(b, &x)
	m, _ := x["message"].(string)
	if m == "" {
		m = "요청 완료"
	}
	showBalloon("Geumyi Server Center", m, false)
}
func trayAgentAction(action string) {
	_, e := hostRequest("POST", "/api/agent/action", fmt.Sprintf(`{"action":%q}`, action))
	if e != nil {
		showBalloon("Agent 제어 실패", e.Error(), true)
		return
	}
	showBalloon("Discord / GDS 에이전트", koreanMessage(action+" 요청 완료"), false)
}
func trayRefresh() {
	b, e := hostRequest("GET", "/api/status", "")
	if e != nil {
		showBalloon("서버 PC 연결 실패", e.Error(), true)
		return
	}
	var s struct {
		AgentOnline bool `json:"agent_online"`
		Servers     []struct {
			Name      string `json:"name"`
			Online    bool   `json:"online"`
			Minecraft struct {
				Online int `json:"online"`
				Max    int `json:"max"`
			} `json:"minecraft"`
		} `json:"servers"`
	}
	_ = json.Unmarshal(b, &s)
	parts := []string{}
	for _, x := range s.Servers {
		st := "OFF"
		if x.Online {
			st = fmt.Sprintf("온라인 %d/%d", x.Minecraft.Online, x.Minecraft.Max)
		}
		parts = append(parts, x.Name+" "+st)
	}
	a := "에이전트 오프라인"
	if s.AgentOnline {
		a = "에이전트 온라인"
	}
	showBalloon("서버 상태", strings.Join(parts, " · ")+" · "+a, false)
}
func openDashboard(section string) {
	if section == "" {
		section = "dashboard"
	}
	openAppWindow(localURL + "/#" + section)
}
func openAppWindow(u string) {
	candidates := []string{filepath.Join(os.Getenv("ProgramFiles(x86)"), "Microsoft", "Edge", "Application", "msedge.exe"), filepath.Join(os.Getenv("ProgramFiles"), "Microsoft", "Edge", "Application", "msedge.exe")}
	for _, p := range candidates {
		if _, e := os.Stat(p); e != nil {
			continue
		}
		c := exec.Command(p, "--user-data-dir="+browserProfile(), "--no-first-run", "--no-default-browser-check", "--disable-background-mode", "--app="+u, "--start-maximized")
		if e := c.Start(); e == nil {
			trackDashboardBrowser(c.Process.Pid)
			go func() { _ = c.Wait() }()
			return
		}
	}
	c := exec.Command("rundll32.exe", "url.dll,FileProtocolHandler", u)
	if c.Start() == nil {
		go c.Wait()
	}
}

func ensureRuntimeIcon() string {
	exe, _ := os.Executable()
	p := filepath.Join(filepath.Dir(exe), "GeumyiServerCenter.ico")
	if _, e := os.Stat(p); e == nil {
		return p
	}
	tmp := filepath.Join(os.TempDir(), "GeumyiServerCenter.ico")
	_ = os.WriteFile(tmp, appIcon, 0644)
	return tmp
}
