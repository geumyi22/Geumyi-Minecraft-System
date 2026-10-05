//go:build windows

package main

import (
	_ "embed"
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
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

const appVersion = "4.3.2"
const localPort = 8790

//go:embed dashboard.html
var dashboardHTML string

//go:embed app.ico
var appIcon []byte

type ClientConfig struct {
	HostURL string `json:"host_url"`
	Token   string `json:"token"`
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
		"/api/v4/update/external/apply-proxy":
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
