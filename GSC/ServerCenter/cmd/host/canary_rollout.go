package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Day 11 canary rollout is intentionally policy-only. Promoting a target pins
// the verified canary release and enables managed update for that server, but
// it never restarts Minecraft by itself. The existing player-aware update flow
// remains the only path that can request a restart.
type canaryPolicySnapshot struct {
	Policy  string `json:"policy"`
	Channel string `json:"channel"`
	Pin     string `json:"pin,omitempty"`
}

type canaryRolloutState struct {
	Schema         int                             `json:"schema"`
	Active         bool                            `json:"active"`
	Completed      bool                            `json:"completed"`
	Release        string                          `json:"release"`
	ManifestSHA256 string                          `json:"manifest_sha256"`
	Order          []string                        `json:"order"`
	Promoted       []string                        `json:"promoted"`
	Previous       map[string]canaryPolicySnapshot `json:"previous,omitempty"`
	StartedAt      string                          `json:"started_at,omitempty"`
	UpdatedAt      string                          `json:"updated_at,omitempty"`
}

var canaryRolloutMu sync.Mutex

func canaryRolloutPath() string {
	return filepath.Join(v4Root(), "Updates", "canary-rollout.json")
}

func defaultCanaryRolloutOrder(c Config) []string {
	roles := []string{serverRolePlayground, serverRoleWild, serverRoleOther, serverRoleLobby}
	out := make([]string, 0, len(roles))
	used := map[string]bool{}
	for _, role := range roles {
		for _, raw := range c.Servers {
			s := normalizeServerConfig(raw)
			if s.Role == role && !used[s.ID] {
				out = append(out, s.ID)
				used[s.ID] = true
				break
			}
		}
	}
	return out
}

func loadCanaryRolloutStateUnlocked() (canaryRolloutState, error) {
	var st canaryRolloutState
	b, err := os.ReadFile(canaryRolloutPath())
	if os.IsNotExist(err) {
		return canaryRolloutState{Schema: 1, Previous: map[string]canaryPolicySnapshot{}}, nil
	}
	if err != nil {
		return st, err
	}
	if err := json.Unmarshal(b, &st); err != nil {
		return st, err
	}
	if st.Schema == 0 {
		st.Schema = 1
	}
	if st.Schema != 1 {
		return st, fmt.Errorf("unsupported canary rollout schema %d", st.Schema)
	}
	if st.Previous == nil {
		st.Previous = map[string]canaryPolicySnapshot{}
	}
	return st, nil
}

func saveCanaryRolloutStateUnlocked(st canaryRolloutState) error {
	st.Schema = 1
	st.UpdatedAt = time.Now().Format(time.RFC3339Nano)
	if err := os.MkdirAll(filepath.Dir(canaryRolloutPath()), 0755); err != nil {
		return err
	}
	b, err := json.MarshalIndent(st, "", "  ")
	if err != nil {
		return err
	}
	tmp := canaryRolloutPath() + ".tmp"
	if err := os.WriteFile(tmp, b, 0600); err != nil {
		return err
	}
	return os.Rename(tmp, canaryRolloutPath())
}

func rolloutContains(values []string, id string) bool {
	for _, v := range values {
		if strings.EqualFold(strings.TrimSpace(v), strings.TrimSpace(id)) {
			return true
		}
	}
	return false
}

func canaryServerIndex(c Config, id string) int {
	for i := range c.Servers {
		if strings.EqualFold(c.Servers[i].ID, id) {
			return i
		}
	}
	return -1
}

func applyCanaryTargetPolicy(c *Config, id, release string) (canaryPolicySnapshot, error) {
	if c == nil {
		return canaryPolicySnapshot{}, fmt.Errorf("nil config")
	}
	id = strings.ToLower(strings.TrimSpace(id))
	release = strings.TrimSpace(release)
	if release == "" {
		return canaryPolicySnapshot{}, fmt.Errorf("release is required")
	}
	i := canaryServerIndex(*c, id)
	if i < 0 {
		return canaryPolicySnapshot{}, fmt.Errorf("unknown server %s", id)
	}
	s := normalizeServerConfig(c.Servers[i])
	prev := canaryPolicySnapshot{Policy: s.UpdatePolicy, Channel: s.UpdateChannel, Pin: s.UpdatePin}
	s.UpdatePolicy = serverUpdateManaged
	s.UpdateChannel = serverUpdateChannelCanary
	s.UpdatePin = release
	c.Servers[i] = normalizeServerConfig(s)
	return prev, nil
}

func restoreCanaryTargetPolicy(c *Config, id string, snap canaryPolicySnapshot) error {
	if c == nil {
		return fmt.Errorf("nil config")
	}
	i := canaryServerIndex(*c, id)
	if i < 0 {
		return fmt.Errorf("unknown server %s", id)
	}
	s := normalizeServerConfig(c.Servers[i])
	s.UpdatePolicy = snap.Policy
	s.UpdateChannel = snap.Channel
	s.UpdatePin = snap.Pin
	c.Servers[i] = normalizeServerConfig(s)
	return nil
}

func canaryUpdateStateReady(st UpdateStatus, release string) (bool, string) {
	if !strings.EqualFold(strings.TrimSpace(st.Release), strings.TrimSpace(release)) {
		return false, "대상 release의 업데이트 상태가 아직 확인되지 않았습니다"
	}
	switch strings.ToLower(strings.TrimSpace(st.Phase)) {
	case "applied":
		return true, "적용 + post-start health 검증 완료"
	case "current":
		return true, "대상 release 기준 이미 최신"
	case "rolled_back", "rollback_failed", "blocked", "error":
		return false, "업데이트 상태가 " + st.Phase
	default:
		return false, "업데이트/health 확인 대기: " + st.Phase
	}
}

func canaryPromotionHealth(s ServerConfig, release string) (bool, string) {
	s = normalizeServerConfig(s)
	st := getServerStatus(s)
	if !st.Online || !st.JavaPortOpen {
		return false, "서버가 ONLINE 상태가 아닙니다"
	}
	if strings.ToUpper(strings.TrimSpace(st.State)) != "ONLINE" {
		return false, "서버 상태가 " + st.State
	}
	if s.RCONPort > 0 && !st.RCONPortOpen {
		return false, "RCON health가 정상 상태가 아닙니다"
	}
	if s.GDSAPIPort > 0 && !st.GDSAPIOnline {
		return false, "GDS health가 정상 상태가 아닙니다"
	}
	if ok, reason := canaryUpdateStateReady(updateStatusFor(s.ID), release); !ok {
		return false, reason
	}
	return true, "ONLINE + RCON/GDS + release health gate PASS"
}

func canaryRolloutView(st canaryRolloutState) map[string]any {
	c := configSnapshot()
	stages := make([]map[string]any, 0, len(st.Order))
	for idx, id := range st.Order {
		i := canaryServerIndex(c, id)
		if i < 0 {
			stages = append(stages, map[string]any{
				"server_id": id,
				"index": idx,
				"missing": true,
				"promoted": rolloutContains(st.Promoted, id),
			})
			continue
		}
		s := normalizeServerConfig(c.Servers[i])
		us := updateStatusFor(s.ID)
		releaseReady, releaseReason := canaryUpdateStateReady(us, st.Release)
		stages = append(stages, map[string]any{
			"server_id": s.ID,
			"name": s.Name,
			"role": s.Role,
			"index": idx,
			"promoted": rolloutContains(st.Promoted, s.ID),
			"online": tcpOpen("127.0.0.1", s.JavaPort, 250*time.Millisecond),
			"policy": s.UpdatePolicy,
			"channel": s.UpdateChannel,
			"pin": s.UpdatePin,
			"update_phase": us.Phase,
			"update_release": us.Release,
			"release_ready": releaseReady,
			"release_reason": releaseReason,
		})
	}
	next := ""
	if st.Active && len(st.Promoted) < len(st.Order) {
		next = st.Order[len(st.Promoted)]
	}
	canPromote := false
	promotionReason := ""
	if st.Active && len(st.Promoted) > 0 && len(st.Promoted) < len(st.Order) {
		prevID := st.Promoted[len(st.Promoted)-1]
		if i := canaryServerIndex(c, prevID); i >= 0 {
			prev := normalizeServerConfig(c.Servers[i])
			us := updateStatusFor(prev.ID)
			if ok, reason := canaryUpdateStateReady(us, st.Release); ok {
				canPromote = tcpOpen("127.0.0.1", prev.JavaPort, 250*time.Millisecond)
				if canPromote {
					promotionReason = "이전 단계 release health 기록 + Java ONLINE"
				} else {
					promotionReason = "이전 단계 서버가 ONLINE이 아닙니다"
				}
			} else {
				promotionReason = reason
			}
		}
	}
	return map[string]any{
		"schema": 1,
		"active": st.Active,
		"completed": st.Completed,
		"release": st.Release,
		"manifest_sha256": st.ManifestSHA256,
		"order": st.Order,
		"promoted": st.Promoted,
		"next_server": next,
		"can_promote_preview": canPromote,
		"promotion_preview_reason": promotionReason,
		"started_at": st.StartedAt,
		"updated_at": st.UpdatedAt,
		"stages": stages,
		"policy_only": true,
		"server_restart_performed": false,
	}
}

func apiV4CanaryRollout(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		canaryRolloutMu.Lock()
		st, err := loadCanaryRolloutStateUnlocked()
		canaryRolloutMu.Unlock()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		writeJSON(w, canaryRolloutView(st))
		return
	case http.MethodPost:
	default:
		http.Error(w, "GET or POST required", http.StatusMethodNotAllowed)
		return
	}

	var q struct {
		Action  string `json:"action"`
		Release string `json:"release"`
		Confirm string `json:"confirm"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&q); err != nil {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	q.Action = strings.ToLower(strings.TrimSpace(q.Action))
	q.Release = strings.TrimSpace(q.Release)
	q.Confirm = strings.TrimSpace(q.Confirm)

	canaryRolloutMu.Lock()
	defer canaryRolloutMu.Unlock()

	st, err := loadCanaryRolloutStateUnlocked()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	c := configSnapshot()

	switch q.Action {
	case "start":
		if q.Confirm != "START_CANARY_ROLLOUT" {
			http.Error(w, "confirm=START_CANARY_ROLLOUT required", http.StatusBadRequest)
			return
		}
		if st.Active {
			http.Error(w, "canary rollout already active", http.StatusConflict)
			return
		}
		order := defaultCanaryRolloutOrder(c)
		if len(order) == 0 {
			http.Error(w, "no rollout targets", http.StatusConflict)
			return
		}
		uc := normalizeUpdateConfig(c.Update)
		uc.Channel = serverUpdateChannelCanary
		var manifest DeploymentManifest
		var manifestHash, release string
		if q.Release == "" {
			manifest, manifestHash, release, err = fetchVerifiedManifestFresh(uc)
		} else {
			manifest, manifestHash, release, err = fetchVerifiedManifestPinned(uc, q.Release)
		}
		if err != nil {
			http.Error(w, "verified canary release lookup failed: "+err.Error(), http.StatusBadGateway)
			return
		}
		if !strings.EqualFold(strings.TrimSpace(manifest.Channel), serverUpdateChannelCanary) {
			http.Error(w, "selected release is not a canary manifest", http.StatusConflict)
			return
		}
		before := c
		before.Servers = append([]ServerConfig(nil), c.Servers...)
		prev := map[string]canaryPolicySnapshot{}
		for _, id := range order {
			i := canaryServerIndex(c, id)
			if i < 0 {
				continue
			}
			s := normalizeServerConfig(c.Servers[i])
			prev[id] = canaryPolicySnapshot{Policy: s.UpdatePolicy, Channel: s.UpdateChannel, Pin: s.UpdatePin}
		}
		if _, err := applyCanaryTargetPolicy(&c, order[0], release); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if err := saveHostConfig(c); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		now := time.Now().Format(time.RFC3339Nano)
		st = canaryRolloutState{
			Schema: 1,
			Active: true,
			Release: release,
			ManifestSHA256: manifestHash,
			Order: order,
			Promoted: []string{order[0]},
			Previous: prev,
			StartedAt: now,
			UpdatedAt: now,
		}
		if err := saveCanaryRolloutStateUnlocked(st); err != nil {
			_ = saveHostConfig(before)
			http.Error(w, "rollout state save failed; policy restored: "+err.Error(), http.StatusInternalServerError)
			return
		}
		if first, ok := serverByID(order[0]); ok {
			checkServerUpdates(first)
		}
		appendV4Event("info", "update", order[0], "Canary rollout 시작",
			"release="+release+" order="+strings.Join(order, "->")+" policy_only=true")
		appendAudit(r, "update.canary.start", order[0], "completed", "release="+release+" server_restart=false")

	case "promote":
		if q.Confirm != "PROMOTE_CANARY" {
			http.Error(w, "confirm=PROMOTE_CANARY required", http.StatusBadRequest)
			return
		}
		if !st.Active {
			http.Error(w, "no active canary rollout", http.StatusConflict)
			return
		}
		if len(st.Promoted) == 0 || len(st.Promoted) >= len(st.Order) {
			http.Error(w, "no next canary target", http.StatusConflict)
			return
		}
		prevID := st.Promoted[len(st.Promoted)-1]
		prev, ok := serverByID(prevID)
		if !ok {
			http.Error(w, "previous canary target missing", http.StatusConflict)
			return
		}
		if ok, reason := canaryPromotionHealth(prev, st.Release); !ok {
			appendV4Event("warn", "update", prevID, "Canary 승격 차단", reason)
			appendAudit(r, "update.canary.promote", prevID, "blocked", reason)
			http.Error(w, "previous canary health gate failed: "+reason, http.StatusConflict)
			return
		}
		nextID := st.Order[len(st.Promoted)]
		before := c
		before.Servers = append([]ServerConfig(nil), c.Servers...)
		if _, err := applyCanaryTargetPolicy(&c, nextID, st.Release); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if err := saveHostConfig(c); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		st.Promoted = append(st.Promoted, nextID)
		if err := saveCanaryRolloutStateUnlocked(st); err != nil {
			_ = saveHostConfig(before)
			http.Error(w, "rollout state save failed; policy restored: "+err.Error(), http.StatusInternalServerError)
			return
		}
		if next, ok := serverByID(nextID); ok {
			checkServerUpdates(next)
		}
		appendV4Event("info", "update", nextID, "Canary 다음 서버 승격",
			"release="+st.Release+" previous="+prevID+" policy_only=true")
		appendAudit(r, "update.canary.promote", nextID, "completed", "release="+st.Release+" previous="+prevID+" server_restart=false")

	case "complete":
		if q.Confirm != "COMPLETE_CANARY_ROLLOUT" {
			http.Error(w, "confirm=COMPLETE_CANARY_ROLLOUT required", http.StatusBadRequest)
			return
		}
		if !st.Active || len(st.Promoted) != len(st.Order) || len(st.Order) == 0 {
			http.Error(w, "rollout is not at final stage", http.StatusConflict)
			return
		}
		lastID := st.Promoted[len(st.Promoted)-1]
		last, ok := serverByID(lastID)
		if !ok {
			http.Error(w, "final canary target missing", http.StatusConflict)
			return
		}
		if ok, reason := canaryPromotionHealth(last, st.Release); !ok {
			appendV4Event("warn", "update", lastID, "Canary 완료 차단", reason)
			appendAudit(r, "update.canary.complete", lastID, "blocked", reason)
			http.Error(w, "final canary health gate failed: "+reason, http.StatusConflict)
			return
		}
		st.Active = false
		st.Completed = true
		if err := saveCanaryRolloutStateUnlocked(st); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		appendV4Event("info", "update", lastID, "Canary rollout 완료", "release="+st.Release)
		appendAudit(r, "update.canary.complete", lastID, "completed", "release="+st.Release)

	case "cancel":
		if q.Confirm != "CANCEL_CANARY_ROLLOUT" {
			http.Error(w, "confirm=CANCEL_CANARY_ROLLOUT required", http.StatusBadRequest)
			return
		}
		if !st.Active {
			http.Error(w, "no active canary rollout", http.StatusConflict)
			return
		}
		before := c
		before.Servers = append([]ServerConfig(nil), c.Servers...)
		for id, snap := range st.Previous {
			if err := restoreCanaryTargetPolicy(&c, id, snap); err != nil {
				http.Error(w, "restore policy failed: "+err.Error(), http.StatusConflict)
				return
			}
		}
		if err := saveHostConfig(c); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		st.Active = false
		st.Completed = false
		if err := saveCanaryRolloutStateUnlocked(st); err != nil {
			_ = saveHostConfig(before)
			http.Error(w, "rollout state save failed; policy restored to pre-cancel state: "+err.Error(), http.StatusInternalServerError)
			return
		}
		appendV4Event("warn", "update", "", "Canary rollout 취소", "release="+st.Release+" policy_restored=true")
		appendAudit(r, "update.canary.cancel", st.Release, "completed", "policy_restored=true")

	default:
		http.Error(w, "action must be start, promote, complete, or cancel", http.StatusBadRequest)
		return
	}

	writeJSON(w, canaryRolloutView(st))
}

func apiV4UpdateNotifications(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", http.StatusMethodNotAllowed)
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > 100 {
		limit = 25
	}
	all := recentV4Events(500, "")
	out := make([]V4Event, 0, limit)
	seen := map[string]bool{}
	for i := len(all) - 1; i >= 0 && len(out) < limit; i-- {
		e := all[i]
		if !strings.EqualFold(strings.TrimSpace(e.Category), "update") {
			continue
		}
		key := strings.Join([]string{e.Level, e.ServerID, e.Message, e.Detail}, "\x1f")
		if seen[key] {
			continue
		}
		seen[key] = true
		out = append(out, e)
	}
	for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
		out[i], out[j] = out[j], out[i]
	}
	writeJSON(w, map[string]any{
		"schema": 1,
		"deduped": true,
		"events": out,
	})
}
