package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// GSC v4.2 mobile-management layer.
// The host always binds the transport on all interfaces, but this guard keeps
// remote management restricted to trusted local/Tailscale address space and
// the explicit mobile_enabled setting. Loopback remains available regardless.

func isTrustedPrivateIP(ip net.IP) bool {
	if ip == nil {
		return false
	}
	if ip.IsLoopback() || ip.IsPrivate() {
		return true
	}
	v4 := ip.To4()
	if v4 != nil {
		// Tailscale/CGNAT 100.64.0.0/10
		if v4[0] == 100 && v4[1] >= 64 && v4[1] <= 127 {
			return true
		}
		// IPv4 link-local is useful for direct LAN recovery only.
		if v4[0] == 169 && v4[1] == 254 {
			return true
		}
	}
	return ip.IsLinkLocalUnicast()
}

func remoteIP(remote string) net.IP {
	host, _, err := net.SplitHostPort(remote)
	if err != nil {
		host = remote
	}
	return net.ParseIP(strings.Trim(host, "[]"))
}

func mobileNetworkGuard(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := remoteIP(r.RemoteAddr)
		if ip != nil && ip.IsLoopback() {
			next.ServeHTTP(w, r)
			return
		}
		c := configSnapshot()
		if !c.MobileEnabled {
			http.Error(w, "GSC mobile access is disabled", http.StatusForbidden)
			return
		}
		if !isTrustedPrivateIP(ip) {
			appendUnauthorizedAudit(r)
			http.Error(w, "Remote address is outside LAN/Tailscale", http.StatusForbidden)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func effectivePairingTTL() time.Duration {
	c := configSnapshot()
	sec := c.PairingTTLSeconds
	if sec < 60 || sec > 3600 {
		sec = 300
	}
	return time.Duration(sec) * time.Second
}

func mobileAddressCandidates() []string {
	c := configSnapshot()
	port := c.Port
	if port <= 0 {
		port = 8787
	}
	type row struct {
		p int
		u string
	}
	rows := []row{}
	for _, raw := range localIPs() {
		ip := net.ParseIP(raw)
		if ip == nil || !isTrustedPrivateIP(ip) {
			continue
		}
		// GSCM advertises only routable IPv4 addresses. APIPA/link-local
		// (169.254/16) previously appeared first on some PCs and produced
		// a connection screen that could never work from a phone.
		v4 := ip.To4()
		if v4 == nil || ip.IsLoopback() || ip.IsLinkLocalUnicast() || (v4[0] == 169 && v4[1] == 254) {
			continue
		}
		p := 2
		if v4[0] == 100 && v4[1] >= 64 && v4[1] <= 127 {
			p = 0 // Tailscale / CGNAT first
		} else if ip.IsPrivate() {
			p = 1 // normal LAN second
		} else {
			continue
		}
		rows = append(rows, row{p: p, u: fmt.Sprintf("http://%s:%d", v4.String(), port)})
	}
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].p != rows[j].p {
			return rows[i].p < rows[j].p
		}
		return rows[i].u < rows[j].u
	})
	out := make([]string, 0, len(rows))
	seen := map[string]bool{}
	for _, r := range rows {
		if !seen[r.u] {
			out = append(out, r.u)
			seen[r.u] = true
		}
	}
	return out
}

func preferredMobileBaseURL() string {
	xs := mobileAddressCandidates()
	if len(xs) > 0 {
		return xs[0]
	}
	c := configSnapshot()
	port := c.Port
	if port <= 0 {
		port = 8787
	}
	return fmt.Sprintf("http://127.0.0.1:%d", port)
}

func pairingClaimURI(code string) string {
	base := preferredMobileBaseURL()
	return "gscm://pair?host=" + urlQueryEscape(base) + "&code=" + urlQueryEscape(code)
}

func urlQueryEscape(s string) string {
	// Enough for our generated http URLs and digits without importing net/url.
	r := strings.NewReplacer("%", "%25", ":", "%3A", "/", "%2F", "?", "%3F", "&", "%26", "=", "%3D", " ", "%20")
	return r.Replace(s)
}

func syncMobileFirewall(enabled bool) {
	if runtime.GOOS != "windows" {
		return
	}
	go func() {
		del := exec.Command("netsh.exe", "advfirewall", "firewall", "delete", "rule", "name=Geumyi Server Center Mobile API")
		hideProcess(del)
		_ = del.Run()
		// Remove the legacy name too so upgrades cannot leave a broader stale rule.
		old := exec.Command("netsh.exe", "advfirewall", "firewall", "delete", "rule", "name=Geumyi Server Center API")
		hideProcess(old)
		_ = old.Run()
		if !enabled {
			return
		}
		port := configSnapshot().Port
		if port <= 0 {
			port = 8787
		}
		c := exec.Command("netsh.exe", "advfirewall", "firewall", "add", "rule", "name=Geumyi Server Center Mobile API", "dir=in", "action=allow", "protocol=TCP", "localport="+strconv.Itoa(port), "remoteip=LocalSubnet,100.64.0.0/10", "profile=any")
		hideProcess(c)
		_ = c.Run()
	}()
}

func mobileStatus() map[string]any {
	c := configSnapshot()
	ps := pairingSummary()
	return map[string]any{
		"enabled":             c.MobileEnabled,
		"port":                c.Port,
		"listen":              "0.0.0.0",
		"addresses":           mobileAddressCandidates(),
		"preferred_url":       preferredMobileBaseURL(),
		"pairing_ttl_seconds": c.PairingTTLSeconds,
		"pairing":             ps,
		"trusted_devices":     sanitizedDevices(),
		"security": map[string]any{
			"remote_scope":  "LAN + Tailscale/CGNAT only",
			"auth_required": true,
			"rcon_exposed":  false,
			"gds_exposed":   false,
		},
	}
}

func sanitizedDevices() []TrustedDevice {
	d := loadDevices()
	if d == nil {
		d = []TrustedDevice{}
	}
	for i := range d {
		d[i].TokenHash = ""
	}
	return d
}

func apiV1Mobile(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, mobileStatus())
	case http.MethodPost:
		var q struct {
			Enabled           *bool `json:"enabled"`
			PairingTTLSeconds *int  `json:"pairing_ttl_seconds"`
		}
		if json.NewDecoder(io.LimitReader(r.Body, 64<<10)).Decode(&q) != nil {
			http.Error(w, "bad json", 400)
			return
		}
		c := configSnapshot()
		if q.Enabled != nil {
			c.MobileEnabled = *q.Enabled
		}
		if q.PairingTTLSeconds != nil {
			if *q.PairingTTLSeconds < 60 || *q.PairingTTLSeconds > 3600 {
				http.Error(w, "pairing_ttl_seconds must be 60..3600", 400)
				return
			}
			c.PairingTTLSeconds = *q.PairingTTLSeconds
		}
		if err := saveHostConfig(c); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		syncMobileFirewall(c.MobileEnabled)
		appendAudit(r, "mobile.settings", "host", "completed", fmt.Sprintf("enabled=%v ttl=%d", c.MobileEnabled, c.PairingTTLSeconds))
		wsPublish("mobile.updated", mobileStatus())
		writeJSON(w, map[string]any{"ok": true, "mobile": mobileStatus()})
	default:
		http.Error(w, "GET or POST required", 405)
	}
}

func apiV1Pairing(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet {
		writeJSON(w, pairingSummary())
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "GET or POST required", 405)
		return
	}
	apiV4PairingCode(w, r)
}

func apiV1Devices(w http.ResponseWriter, r *http.Request) { apiV4Devices(w, r) }

func apiV1PairingQR(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", http.StatusMethodNotAllowed)
		return
	}
	pairMu.Lock()
	active := pair.Code != "" && time.Now().Before(pair.Expires)
	code := pair.Code
	pairMu.Unlock()
	if !active {
		http.Error(w, "pairing code is not active", http.StatusNotFound)
		return
	}
	claim := pairingClaimURI(code)
	svg, err := qrV6LSVG(claim)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "image/svg+xml; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store, max-age=0")
	w.Header().Set("Pragma", "no-cache")
	_, _ = io.WriteString(w, svg)
}

var pairRateMu sync.Mutex
var pairRate = map[string][]time.Time{}

func pairingRateAllowed(r *http.Request) bool {
	ip := remoteIP(r.RemoteAddr)
	key := "unknown"
	if ip != nil {
		key = ip.String()
	}
	now := time.Now()
	cutoff := now.Add(-1 * time.Minute)
	pairRateMu.Lock()
	defer pairRateMu.Unlock()
	xs := pairRate[key][:0]
	for _, t := range pairRate[key] {
		if t.After(cutoff) {
			xs = append(xs, t)
		}
	}
	if len(xs) >= 12 {
		pairRate[key] = xs
		return false
	}
	pairRate[key] = append(xs, now)
	return true
}

func apiV1PairingClaim(w http.ResponseWriter, r *http.Request) {
	if !pairingRateAllowed(r) {
		http.Error(w, "too many pairing attempts", 429)
		return
	}
	apiV4PairingClaim(w, r)
}

func apiV1Backups(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		apiV4Backups(w, r)
	case http.MethodPost:
		apiV4Backup(w, r)
	default:
		http.Error(w, "GET or POST required", 405)
	}
}

func apiV1BackupManage(w http.ResponseWriter, r *http.Request)  { apiV4BackupManage(w, r) }
func apiV1BackupVerify(w http.ResponseWriter, r *http.Request)  { apiV4BackupVerify(w, r) }
func apiV1BackupRestore(w http.ResponseWriter, r *http.Request) { apiV4Restore(w, r) }
func apiV1Automations(w http.ResponseWriter, r *http.Request)   { apiV4Automations(w, r) }
func apiV1Metrics(w http.ResponseWriter, r *http.Request)       { apiV4Metrics(w, r) }

func apiV1Console(w http.ResponseWriter, r *http.Request, s ServerConfig) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", 405)
		return
	}
	lines, _ := strconv.Atoi(r.URL.Query().Get("lines"))
	if lines <= 0 || lines > 2000 {
		lines = 500
	}
	kind := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("kind")))
	dir := resolveServerDir(s)
	if dir == "" {
		http.Error(w, "server dir not found", 404)
		return
	}
	path := filepath.Join(dir, "logs", "latest.log")
	if kind == "launcher" {
		path = launcherLogPath(s.ID)
	}
	b, err := tailFile(path, lines)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	writeJSON(w, map[string]any{"server_id": s.ID, "kind": kind, "lines": lines, "text": string(b), "timestamp": time.Now().Format(time.RFC3339Nano)})
}

func safePlayerName(v string) bool {
	if len(v) < 1 || len(v) > 16 {
		return false
	}
	for _, r := range v {
		if !((r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '_') {
			return false
		}
	}
	return true
}

func apiV1PlayerAction(w http.ResponseWriter, r *http.Request, s ServerConfig) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", 405)
		return
	}
	var q struct {
		Action string `json:"action"`
		Player string `json:"player"`
		Reason string `json:"reason"`
	}
	if json.NewDecoder(io.LimitReader(r.Body, 64<<10)).Decode(&q) != nil {
		http.Error(w, "bad json", 400)
		return
	}
	q.Player = strings.TrimSpace(q.Player)
	q.Action = strings.ToLower(strings.TrimSpace(q.Action))
	if !safePlayerName(q.Player) {
		http.Error(w, "invalid player name", 400)
		return
	}
	reason := strings.TrimSpace(q.Reason)
	if len([]rune(reason)) > 120 {
		reason = string([]rune(reason)[:120])
	}
	var cmd string
	switch q.Action {
	case "kick":
		cmd = "kick " + q.Player
		if reason != "" {
			cmd += " " + reason
		}
	case "whitelist_add":
		cmd = "whitelist add " + q.Player
	case "whitelist_remove":
		cmd = "whitelist remove " + q.Player
	case "op":
		cmd = "op " + q.Player
	case "deop":
		cmd = "deop " + q.Player
	case "ban":
		cmd = "ban " + q.Player
		if reason != "" {
			cmd += " " + reason
		}
	case "pardon":
		cmd = "pardon " + q.Player
	default:
		http.Error(w, "unsupported player action", 400)
		return
	}
	pass, err := readServerProperty(resolveServerDir(s), "rcon.password")
	if err != nil || pass == "" {
		http.Error(w, "RCON password unavailable", 500)
		return
	}
	resp, err := rconCommand("127.0.0.1", s.RCONPort, pass, cmd)
	if err != nil {
		appendAudit(r, "player."+q.Action, s.ID+":"+q.Player, "failed", err.Error())
		http.Error(w, err.Error(), 500)
		return
	}
	appendAudit(r, "player."+q.Action, s.ID+":"+q.Player, "completed", resp)
	writeJSON(w, map[string]any{"ok": true, "response": resp})
}

func apiV1ServerSchedule(w http.ResponseWriter, r *http.Request, s ServerConfig) {
	if r.Method == http.MethodDelete {
		if !cancelLifecycleCountdown(s.ID) {
			writeJSONStatus(w, http.StatusConflict, map[string]any{"ok": false, "error": "no active schedule"})
			return
		}
		appendAudit(r, "server.schedule.cancel", s.ID, "completed", "")
		writeJSON(w, map[string]any{"ok": true, "schedule": lifecycleScheduleStatus(s.ID)})
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "POST or DELETE required", 405)
		return
	}
	var q struct {
		Action           string `json:"action"`
		ExecuteAt        string `json:"execute_at"`
		CountdownSeconds int    `json:"countdown_seconds"`
	}
	if json.NewDecoder(io.LimitReader(r.Body, 64<<10)).Decode(&q) != nil {
		http.Error(w, "bad json", 400)
		return
	}
	at, err := time.Parse(time.RFC3339Nano, strings.TrimSpace(q.ExecuteAt))
	if err != nil {
		http.Error(w, "execute_at must be RFC3339 with timezone", 400)
		return
	}
	msg, err := createLifecycleSchedule(s, q.Action, at, q.CountdownSeconds)
	if err != nil {
		writeJSONStatus(w, http.StatusConflict, map[string]any{"ok": false, "error": err.Error(), "message": msg})
		return
	}
	appendAudit(r, "server.schedule", s.ID+":"+q.Action, "accepted", at.Format(time.RFC3339Nano))
	writeJSONStatus(w, http.StatusAccepted, map[string]any{"ok": true, "message": msg, "schedule": lifecycleScheduleStatus(s.ID)})
}

func serverExtensions(s ServerConfig) map[string]any {
	inv := pluginInventory(resolveServerDir(s))
	names := map[string]string{}
	for _, p := range inv {
		if p.Enabled {
			names[strings.ToLower(p.Name)] = p.Version
		}
	}
	ext := map[string]any{
		"server_tools":   map[string]any{"installed": names["geumyiservertools"] != "", "version": names["geumyiservertools"]},
		"discord_status": map[string]any{"installed": names["geumyidiscordstatus"] != "", "version": names["geumyidiscordstatus"]},
	}
	if s.ID == "wild" {
		ext["technology"] = map[string]any{"installed": names["geumyitechnology"] != "", "version": names["geumyitechnology"]}
		ext["chemistry"] = map[string]any{"installed": names["geumyichemistry"] != "", "version": names["geumyichemistry"]}
	}
	return ext
}
