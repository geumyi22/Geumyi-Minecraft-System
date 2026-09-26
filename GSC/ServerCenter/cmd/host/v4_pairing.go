package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type TrustedDevice struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	TokenHash string `json:"token_hash"`
	Created   string `json:"created"`
	LastSeen  string `json:"last_seen,omitempty"`
	Revoked   bool   `json:"revoked"`
	Role      string `json:"role,omitempty"`
}

type pairingState struct {
	Code    string
	Expires time.Time
}

var pairMu sync.Mutex
var pair pairingState
var deviceMu sync.Mutex

func devicesPath() string       { return filepath.Join(v4Root(), "trusted-devices.json") }
func hashToken(s string) string { h := sha256.Sum256([]byte(s)); return hex.EncodeToString(h[:]) }
func randomHex(n int) string    { b := make([]byte, n); _, _ = rand.Read(b); return hex.EncodeToString(b) }
func loadDevices() []TrustedDevice {
	deviceMu.Lock()
	defer deviceMu.Unlock()
	var d []TrustedDevice
	b, e := os.ReadFile(devicesPath())
	if e == nil {
		_ = json.Unmarshal(b, &d)
	}
	return d
}
func saveDevices(d []TrustedDevice) error {
	deviceMu.Lock()
	defer deviceMu.Unlock()
	b, e := json.MarshalIndent(d, "", "  ")
	if e != nil {
		return e
	}
	tmp := devicesPath() + ".tmp"
	if e = os.WriteFile(tmp, b, 0600); e != nil {
		return e
	}
	_ = os.Remove(devicesPath())
	return os.Rename(tmp, devicesPath())
}
func trustedDeviceForToken(tok string) (TrustedDevice, bool) {
	if strings.TrimSpace(tok) == "" {
		return TrustedDevice{}, false
	}
	h := hashToken(tok)
	d := loadDevices()
	now := time.Now().Format(time.RFC3339)
	for i := range d {
		if !d[i].Revoked && d[i].TokenHash == h {
			d[i].LastSeen = now
			if strings.TrimSpace(d[i].Role) == "" {
				d[i].Role = "admin"
			}
			out := d[i]
			_ = saveDevices(d)
			return out, true
		}
	}
	return TrustedDevice{}, false
}

func validDeviceToken(tok string) bool {
	_, ok := trustedDeviceForToken(tok)
	return ok
}
func pairingSummary() map[string]any {
	pairMu.Lock()
	defer pairMu.Unlock()
	active := pair.Code != "" && time.Now().Before(pair.Expires)
	code := ""
	expires := ""
	remain := int64(0)
	claim := ""
	if active {
		code = pair.Code
		expires = pair.Expires.Format(time.RFC3339)
		remain = int64(time.Until(pair.Expires).Seconds())
		if remain < 0 {
			remain = 0
		}
		claim = pairingClaimURI(code)
	}
	return map[string]any{"active": active, "code": code, "expires": expires, "remaining_seconds": remain, "claim_uri": claim, "trusted_devices": len(loadDevices())}
}

func apiV4PairingCode(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "POST required", 405)
		return
	}
	b := make([]byte, 4)
	_, _ = rand.Read(b)
	n := int(b[0])<<24 | int(b[1])<<16 | int(b[2])<<8 | int(b[3])
	if n < 0 {
		n = -n
	}
	code := fmt.Sprintf("%08d", n%100000000)
	pairMu.Lock()
	ttl := effectivePairingTTL()
	expires := time.Now().Add(ttl)
	pair = pairingState{Code: code, Expires: expires}
	pairMu.Unlock()
	appendV4Event("info", "security", "", "새 Pairing Code 생성", fmt.Sprintf("%d초 후 만료", int(ttl.Seconds())))
	writeJSON(w, map[string]any{"code": code, "expires": expires.Format(time.RFC3339), "remaining_seconds": int(ttl.Seconds()), "claim_uri": pairingClaimURI(code), "addresses": mobileAddressCandidates()})
}
func apiV4PairingClaim(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "POST required", 405)
		return
	}
	var q struct {
		Code     string `json:"code"`
		DeviceID string `json:"device_id"`
		Name     string `json:"name"`
	}
	if json.NewDecoder(io.LimitReader(r.Body, 64<<10)).Decode(&q) != nil {
		http.Error(w, "bad json", 400)
		return
	}
	pairMu.Lock()
	valid := pair.Code != "" && time.Now().Before(pair.Expires) && strings.TrimSpace(q.Code) == pair.Code
	if valid {
		pair = pairingState{}
	}
	pairMu.Unlock()
	if !valid {
		http.Error(w, "pairing code invalid or expired", 401)
		return
	}
	if strings.TrimSpace(q.DeviceID) == "" {
		q.DeviceID = randomHex(8)
	}
	if strings.TrimSpace(q.Name) == "" {
		q.Name = "GSC Client"
	}
	tok := "gscd_" + randomHex(32)
	d := loadDevices()
	d = append(d, TrustedDevice{ID: q.DeviceID, Name: q.Name, TokenHash: hashToken(tok), Created: time.Now().Format(time.RFC3339), Role: "admin"})
	if e := saveDevices(d); e != nil {
		http.Error(w, e.Error(), 500)
		return
	}
	appendV4Event("info", "security", "", "관리 장치 등록", q.Name+" / "+q.DeviceID)
	writeJSON(w, map[string]any{"ok": true, "device_id": q.DeviceID, "device_token": tok})
}
func apiV4Devices(w http.ResponseWriter, r *http.Request) {
	if r.Method == "GET" {
		d := loadDevices()
		for i := range d {
			d[i].TokenHash = ""
		}
		writeJSON(w, map[string]any{"devices": d})
		return
	}
	if r.Method != "POST" {
		http.Error(w, "POST required", 405)
		return
	}
	var q struct{ Action, ID string }
	if json.NewDecoder(io.LimitReader(r.Body, 64<<10)).Decode(&q) != nil {
		http.Error(w, "bad json", 400)
		return
	}
	d := loadDevices()
	found := false
	for i := range d {
		if d[i].ID == q.ID {
			switch q.Action {
			case "revoke":
				d[i].Revoked = true
			case "restore":
				d[i].Revoked = false
			case "delete":
				d = append(d[:i], d[i+1:]...)
			default:
				http.Error(w, "unknown action", 400)
				return
			}
			found = true
			break
		}
	}
	if !found {
		http.Error(w, "device not found", 404)
		return
	}
	if e := saveDevices(d); e != nil {
		http.Error(w, e.Error(), 500)
		return
	}
	appendV4Event("warn", "security", "", "관리 장치 변경", q.Action+" "+q.ID)
	writeJSON(w, map[string]any{"ok": true})
}
