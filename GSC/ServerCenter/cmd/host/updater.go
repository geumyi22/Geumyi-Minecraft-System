package main

import (
	"crypto/ed25519"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

type UpdateConfig struct {
	Enabled        bool   `json:"enabled"`
	Repository     string `json:"repository"`
	Channel        string `json:"channel"`
	PublicKeyPath  string `json:"public_key_path"`
	TimeoutSeconds int    `json:"timeout_seconds"`
}

type DeploymentManifest struct {
	Schema      int                            `json:"schema"`
	Channel     string                         `json:"channel"`
	Release     string                         `json:"release"`
	GeneratedAt string                         `json:"generated_at"`
	Repository  string                         `json:"repository"`
	Components  map[string]DeploymentComponent `json:"components"`
}

type DeploymentComponent struct {
	Version         string   `json:"version"`
	Kind            string   `json:"kind"`
	PluginName      string   `json:"plugin_name,omitempty"`
	File            string   `json:"file"`
	URL             string   `json:"url"`
	SHA256          string   `json:"sha256"`
	Size            int64    `json:"size"`
	Targets         []string `json:"targets"`
	RequiresRestart bool     `json:"requires_restart"`
	MinPaper        string            `json:"min_paper,omitempty"`
	ReleaseGroup    string            `json:"release_group,omitempty"`
	Requires        map[string]string `json:"requires,omitempty"`
}

type UpdateStatus struct {
	ServerID  string   `json:"server_id"`
	Phase     string   `json:"phase"`
	Policy            string   `json:"policy"`
	Channel           string   `json:"channel"`
	ConfiguredChannel string   `json:"configured_channel"`
	Pin               string   `json:"pin,omitempty"`
	Release   string   `json:"release,omitempty"`
	Message   string   `json:"message"`
	Error     string   `json:"error,omitempty"`
	Available []string `json:"available,omitempty"`
	Applied       []string `json:"applied,omitempty"`
	Transaction   string   `json:"transaction,omitempty"`
	RollbackReason string  `json:"rollback_reason,omitempty"`
	BlockStart    bool     `json:"block_start,omitempty"`
	Updated       string   `json:"updated"`
}

type githubRelease struct {
	TagName     string `json:"tag_name"`
	Draft       bool   `json:"draft"`
	CreatedAt   string `json:"created_at"`
	PublishedAt string `json:"published_at"`
	Assets      []struct {
		Name               string `json:"name"`
		BrowserDownloadURL string `json:"browser_download_url"`
	} `json:"assets"`
}

func githubReleaseSortTime(r githubRelease) time.Time {
	for _, raw := range []string{r.PublishedAt, r.CreatedAt} {
		if t, err := time.Parse(time.RFC3339, strings.TrimSpace(raw)); err == nil {
			return t
		}
	}
	return time.Time{}
}

func sortGitHubReleasesNewestFirst(releases []githubRelease) {
	sort.SliceStable(releases, func(i, j int) bool {
		ti := githubReleaseSortTime(releases[i])
		tj := githubReleaseSortTime(releases[j])
		if ti.Equal(tj) {
			return releases[i].TagName > releases[j].TagName
		}
		return ti.After(tj)
	})
}

type updatePlanItem struct {
	Key       string
	Component DeploymentComponent
	Installed PluginInventory
}

type UpdateDryRunItem struct {
	Key             string `json:"key"`
	PluginName      string `json:"plugin_name"`
	InstalledVersion string `json:"installed_version"`
	TargetVersion   string `json:"target_version"`
	File            string `json:"file"`
	Size            int64  `json:"size"`
	RequiresRestart bool   `json:"requires_restart"`
}

type UpdateDryRunServer struct {
	ServerID         string             `json:"server_id"`
	Name             string             `json:"name"`
	Role             string             `json:"role"`
	Policy           string             `json:"policy"`
	Online           bool               `json:"online"`
	Players          int                `json:"players"`
	PlayerAwareBlock bool               `json:"player_aware_block"`
	RestartSafe      bool               `json:"restart_safe"`
	Items            []UpdateDryRunItem `json:"items"`
	Error            string             `json:"error,omitempty"`
}

type UpdateDryRunResult struct {
	DryRun           bool                 `json:"dry_run"`
	InstallPerformed bool                 `json:"install_performed"`
	RestartPerformed bool                 `json:"restart_performed"`
	SettingsEnabled  bool                 `json:"settings_enabled"`
	Channel          string               `json:"channel"`
	Release          string               `json:"release"`
	ManifestSHA256   string               `json:"manifest_sha256"`
	SignatureVerified bool                `json:"signature_verified"`
	Servers          []UpdateDryRunServer `json:"servers"`
	AvailableCount   int                  `json:"available_count"`
	BlockedServers   int                  `json:"blocked_servers"`
}


var (
	updateStateMu sync.Mutex
	updateStates  = map[string]UpdateStatus{}
	updateApplyMu sync.Mutex
)

func defaultUpdateConfig(dataRoot string) UpdateConfig {
	return UpdateConfig{
		Enabled:        false,
		Repository:     "geumyi22/Geumyi-Minecraft-System",
		Channel:        "canary",
		PublicKeyPath:  filepath.Join(dataRoot, "deployment-public.pem"),
		TimeoutSeconds: 12,
	}
}

func normalizeUpdateConfig(c UpdateConfig) UpdateConfig {
	c.Repository = strings.TrimSpace(c.Repository)
	if c.Repository == "" {
		c.Repository = "geumyi22/Geumyi-Minecraft-System"
	}
	c.Channel = strings.ToLower(strings.TrimSpace(c.Channel))
	switch c.Channel {
	case "stable", "beta", "canary":
	default:
		c.Channel = "canary"
	}
	c.PublicKeyPath = strings.TrimSpace(os.ExpandEnv(c.PublicKeyPath))
	if c.TimeoutSeconds < 3 || c.TimeoutSeconds > 60 {
		c.TimeoutSeconds = 12
	}
	return c
}

func effectiveUpdateConfigForServer(s ServerConfig) UpdateConfig {
	s = normalizeServerConfig(s)
	c := normalizeUpdateConfig(configSnapshot().Update)
	if s.UpdateChannel != serverUpdateChannelInherit {
		c.Channel = s.UpdateChannel
	}
	return c
}

func updateStatusPolicyFields(st UpdateStatus, s ServerConfig) UpdateStatus {
	s = normalizeServerConfig(s)
	st.Policy = s.UpdatePolicy
	st.ConfiguredChannel = s.UpdateChannel
	st.Pin = s.UpdatePin
	st.Channel = effectiveUpdateConfigForServer(s).Channel
	return st
}

func setUpdateStatus(st UpdateStatus) UpdateStatus {
	if st.Updated == "" {
		st.Updated = time.Now().Format(time.RFC3339)
	}
	updateStateMu.Lock()
	updateStates[st.ServerID] = st
	updateStateMu.Unlock()
	wsPublish("update", st)
	return st
}

func updateStatusFor(id string) UpdateStatus {
	updateStateMu.Lock()
	st, exists := updateStates[id]
	if exists {
		st.Available = append([]string(nil), st.Available...)
		st.Applied = append([]string(nil), st.Applied...)
	}
	updateStateMu.Unlock()
	s, ok := serverByID(id)
	if !ok {
		if exists {
			return st
		}
		c := normalizeUpdateConfig(configSnapshot().Update)
		return UpdateStatus{ServerID: id, Phase: "idle", Channel: c.Channel, Message: "아직 업데이트 확인 기록이 없습니다", Updated: time.Now().Format(time.RFC3339)}
	}
	if exists {
		return updateStatusPolicyFields(st, s)
	}
	st = UpdateStatus{ServerID: id, Phase: "idle", Message: "아직 업데이트 확인 기록이 없습니다", Updated: time.Now().Format(time.RFC3339)}
	return updateStatusPolicyFields(st, s)
}

func registerUpdateRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/api/v4/update/status", requireAuth(apiV4UpdateStatus))
	mux.HandleFunc("/api/v4/update/settings", requireAuth(apiV4UpdateSettings))
	mux.HandleFunc("/api/v4/update/check", requireAuth(apiV4UpdateCheck))
	mux.HandleFunc("/api/v4/update/dry-run", requireAuth(apiV4UpdateDryRun))
	mux.HandleFunc("/api/v4/update/decision", requireAuth(apiV4UpdateDecision))
	mux.HandleFunc("/api/v4/update/policy", requireAuth(apiV4UpdatePolicy))
	mux.HandleFunc("/api/v4/update/fleet", requireAuth(apiV4UpdateFleet))
	mux.HandleFunc("/api/v4/update/canary-rollout", requireAuth(apiV4CanaryRollout))
	mux.HandleFunc("/api/v4/update/notifications", requireAuth(apiV4UpdateNotifications))
	mux.HandleFunc("/api/v4/update/external/status", requireAuth(apiV4ExternalUpdateStatus))
	mux.HandleFunc("/api/v4/update/external/stage", requireAuth(apiV4ExternalUpdateStage))
	mux.HandleFunc("/api/v4/update/external/apply-proxy", requireAuth(apiV4ExternalUpdateApplyProxy))
	mux.HandleFunc("/api/v4/update/external/apply-via-offline", requireAuth(apiV4ExternalUpdateViaOffline))
	mux.HandleFunc("/api/v4/update/self/status", requireAuth(apiV4GSCSelfUpdateStatus))
	mux.HandleFunc("/api/v4/update/self/stage", requireAuth(apiV4GSCSelfUpdateStage))
	mux.HandleFunc("/api/v4/update/self/apply", requireAuth(apiV4GSCSelfUpdateApply))
}

func publicUpdateConfig(c Config) map[string]any {
	u := normalizeUpdateConfig(c.Update)
	return map[string]any{
		"enabled": u.Enabled,
		"repository": u.Repository,
		"channel": u.Channel,
		"public_key_path": u.PublicKeyPath,
		"timeout_seconds": u.TimeoutSeconds,
		"github_authenticated": strings.TrimSpace(c.GitHubToken) != "",
	}
}

func validateGitHubToken(token string) error {
	token = strings.TrimSpace(token)
	if len(token) < 20 || strings.ContainsAny(token, "\r\n\x00") {
		return errors.New("invalid GitHub token")
	}
	client := &http.Client{Timeout: 12 * time.Second}
	req, _ := http.NewRequest(http.MethodGet, "https://api.github.com/rate_limit", nil)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	req.Header.Set("User-Agent", "GeumyiServerCenter/"+appVersion)
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("GitHub token validation failed: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("GitHub token validation HTTP %d", resp.StatusCode)
	}
	return nil
}

func apiV4UpdateStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", http.StatusMethodNotAllowed)
		return
	}
	id := strings.TrimSpace(r.URL.Query().Get("id"))
	if id != "" {
		if _, ok := serverByID(id); !ok {
			http.Error(w, "unknown server", http.StatusBadRequest)
			return
		}
		writeJSON(w, updateStatusFor(id))
		return
	}
	c := configSnapshot()
	out := make([]UpdateStatus, 0, len(c.Servers))
	for _, s := range c.Servers {
		out = append(out, updateStatusFor(s.ID))
	}
	writeJSON(w, map[string]any{"settings": publicUpdateConfig(c), "servers": out})
}

func apiV4UpdateSettings(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, publicUpdateConfig(configSnapshot()))
		return
	case http.MethodPost:
	default:
		http.Error(w, "GET or POST required", http.StatusMethodNotAllowed)
		return
	}
	var q struct {
		Enabled        *bool   `json:"enabled"`
		Repository     *string `json:"repository"`
		Channel        *string `json:"channel"`
		PublicKeyPath  *string `json:"public_key_path"`
		TimeoutSeconds  *int    `json:"timeout_seconds"`
		GitHubToken     *string `json:"github_token"`
		ClearGitHubToken bool   `json:"clear_github_token"`
	}
	if json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q) != nil {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	c := configSnapshot()
	u := c.Update
	if q.ClearGitHubToken {
		c.GitHubToken = ""
	}
	if q.GitHubToken != nil {
		token := strings.TrimSpace(*q.GitHubToken)
		if token != "" {
			if err := validateGitHubToken(token); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			c.GitHubToken = token
		}
	}
	if q.Enabled != nil {
		u.Enabled = *q.Enabled
	}
	if q.Repository != nil {
		u.Repository = strings.TrimSpace(*q.Repository)
	}
	if q.Channel != nil {
		ch := strings.ToLower(strings.TrimSpace(*q.Channel))
		if ch != "stable" && ch != "beta" && ch != "canary" {
			http.Error(w, "channel must be stable, beta, or canary", http.StatusBadRequest)
			return
		}
		u.Channel = ch
	}
	if q.PublicKeyPath != nil {
		u.PublicKeyPath = strings.TrimSpace(*q.PublicKeyPath)
	}
	if q.TimeoutSeconds != nil {
		if *q.TimeoutSeconds < 3 || *q.TimeoutSeconds > 60 {
			http.Error(w, "timeout_seconds must be 3..60", http.StatusBadRequest)
			return
		}
		u.TimeoutSeconds = *q.TimeoutSeconds
	}
	u = normalizeUpdateConfig(u)
	parts := strings.Split(u.Repository, "/")
	if len(parts) != 2 || strings.TrimSpace(parts[0]) == "" || strings.TrimSpace(parts[1]) == "" {
		http.Error(w, "repository must be owner/name", http.StatusBadRequest)
		return
	}
	c.Update = u
	if err := saveHostConfig(c); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	appendV4Event("info", "update", "", "업데이트 설정 저장", fmt.Sprintf("enabled=%v channel=%s repository=%s", u.Enabled, u.Channel, u.Repository))
	writeJSON(w, map[string]any{"ok": true, "settings": publicUpdateConfig(c)})
}

func apiV4UpdatePolicy(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", http.StatusMethodNotAllowed)
		return
	}
	var q struct {
		ID      string  `json:"id"`
		Policy  *string `json:"policy"`
		Channel *string `json:"channel"`
		Pin     *string `json:"pin"`
	}
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q); err != nil {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	id := strings.ToLower(strings.TrimSpace(q.ID))
	c := configSnapshot()
	found := false
	for i := range c.Servers {
		if !strings.EqualFold(c.Servers[i].ID, id) {
			continue
		}
		found = true
		if q.Policy != nil {
			p := strings.ToLower(strings.TrimSpace(*q.Policy))
			if p != serverUpdateManaged && p != serverUpdateManual && p != serverUpdateHold {
				http.Error(w, "policy must be managed, manual, or hold", http.StatusBadRequest)
				return
			}
			c.Servers[i].UpdatePolicy = p
		}
		if q.Channel != nil {
			ch := strings.ToLower(strings.TrimSpace(*q.Channel))
			if ch != serverUpdateChannelInherit && ch != serverUpdateChannelStable && ch != serverUpdateChannelBeta && ch != serverUpdateChannelCanary {
				http.Error(w, "channel must be inherit, stable, beta, or canary", http.StatusBadRequest)
				return
			}
			c.Servers[i].UpdateChannel = ch
		}
		if q.Pin != nil {
			pin := strings.TrimSpace(*q.Pin)
			if len(pin) > 128 || strings.ContainsAny(pin, "\r\n\x00") {
				http.Error(w, "pin is invalid", http.StatusBadRequest)
				return
			}
			c.Servers[i].UpdatePin = pin
		}
		c.Servers[i] = normalizeServerConfig(c.Servers[i])
		break
	}
	if !found {
		http.Error(w, "unknown server", http.StatusBadRequest)
		return
	}
	if err := saveHostConfig(c); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	s, _ := serverByID(id)
	st := updateStatusFor(id)
	appendV4Event("info", "update", id, "서버 업데이트 정책 저장",
		fmt.Sprintf("policy=%s channel=%s pin=%s", s.UpdatePolicy, s.UpdateChannel, map[bool]string{true: "<set>", false: "<none>"}[s.UpdatePin != ""]))
	writeJSON(w, map[string]any{
		"ok": true,
		"server_id": id,
		"policy": s.UpdatePolicy,
		"channel": s.UpdateChannel,
		"effective_channel": effectiveUpdateConfigForServer(s).Channel,
		"pin": s.UpdatePin,
		"status": st,
		"server_restarted": false,
	})
}

func apiV4UpdateFleet(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", http.StatusMethodNotAllowed)
		return
	}
	c := configSnapshot()
	rows := make([]map[string]any, 0, len(c.Servers))
	for _, raw := range c.Servers {
		s := normalizeServerConfig(raw)
		st := updateStatusFor(s.ID)
		rows = append(rows, map[string]any{
			"server_id": s.ID,
			"name": s.Name,
			"role": s.Role,
			"policy": s.UpdatePolicy,
			"channel": s.UpdateChannel,
			"effective_channel": effectiveUpdateConfigForServer(s).Channel,
			"pin": s.UpdatePin,
			"online": tcpOpen("127.0.0.1", s.JavaPort, 250*time.Millisecond),
			"status": st,
		})
	}
	writeJSON(w, map[string]any{
		"schema": 1,
		"global": publicUpdateConfig(c),
		"servers": rows,
		"capabilities": map[string]any{
			"canary_promotion": true,
			"health_gated_promotion": true,
			"update_notifications": true,
			"policy_only_promotion": true,
		},
	})
}

func updateRestartSafety(online bool, players int) (blocked, safe bool) {
	blocked = online && players > 0
	safe = !online || players == 0
	return blocked, safe
}

func updateDryRunServer(s ServerConfig, manifest DeploymentManifest) UpdateDryRunServer {
	s = normalizeServerConfig(s)
	st := getServerStatus(s)
	blocked, restartSafe := updateRestartSafety(st.Online, st.MC.Online)
	preview := UpdateDryRunServer{
		ServerID: s.ID,
		Name: s.Name,
		Role: s.Role,
		Policy: normalizeServerUpdatePolicy(s.UpdatePolicy),
		Online: st.Online,
		Players: st.MC.Online,
		PlayerAwareBlock: blocked,
		RestartSafe: restartSafe,
	}
	plan, err := buildUpdatePlan(s, manifest)
	if err != nil {
		preview.Error = err.Error()
		return preview
	}
	preview.Items = make([]UpdateDryRunItem, 0, len(plan))
	for _, item := range plan {
		preview.Items = append(preview.Items, UpdateDryRunItem{
			Key: item.Key,
			PluginName: item.Component.PluginName,
			InstalledVersion: item.Installed.Version,
			TargetVersion: item.Component.Version,
			File: item.Component.File,
			Size: item.Component.Size,
			RequiresRestart: item.Component.RequiresRestart,
		})
	}
	return preview
}

func buildUpdateDryRun(c UpdateConfig, manifest DeploymentManifest, manifestHash, release, onlyID string) UpdateDryRunResult {
	c = normalizeUpdateConfig(c)
	result := UpdateDryRunResult{
		DryRun: true,
		InstallPerformed: false,
		RestartPerformed: false,
		SettingsEnabled: c.Enabled,
		Channel: c.Channel,
		Release: release,
		ManifestSHA256: manifestHash,
		SignatureVerified: true,
	}
	cfg := configSnapshot()
	for _, s := range cfg.Servers {
		if onlyID != "" && !strings.EqualFold(strings.TrimSpace(onlyID), s.ID) {
			continue
		}
		preview := updateDryRunServer(s, manifest)
		result.Servers = append(result.Servers, preview)
		result.AvailableCount += len(preview.Items)
		if preview.PlayerAwareBlock {
			result.BlockedServers++
		}
	}
	return result
}

// apiV4UpdateDryRun performs discovery and planning only. It never downloads
// an artifact, edits a server profile, stops/restarts Minecraft, or changes an
// update policy. The signed manifest is verified using the normal trust path.
func apiV4UpdateDryRun(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", http.StatusMethodNotAllowed)
		return
	}
	var q struct {
		ID string `json:"id"`
	}
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q); err != nil && !errors.Is(err, io.EOF) {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	q.ID = strings.ToLower(strings.TrimSpace(q.ID))
	if q.ID != "" {
		if _, ok := serverByID(q.ID); !ok {
			http.Error(w, "unknown server", http.StatusBadRequest)
			return
		}
	}
	uc := normalizeUpdateConfig(configSnapshot().Update)
	pin := ""
	if q.ID != "" {
		s, _ := serverByID(q.ID)
		s = normalizeServerConfig(s)
		uc = effectiveUpdateConfigForServer(s)
		pin = s.UpdatePin
	}
	manifest, manifestHash, release, err := fetchVerifiedManifestPinned(uc, pin)
	if err != nil {
		http.Error(w, "dry-run manifest verification failed: "+err.Error(), http.StatusBadGateway)
		return
	}
	writeJSON(w, buildUpdateDryRun(uc, manifest, manifestHash, release, q.ID))
}

func apiV4UpdateCheck(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", http.StatusMethodNotAllowed)
		return
	}
	var q struct {
		ID string `json:"id"`
	}
	if json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q) != nil {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	s, ok := serverByID(strings.TrimSpace(q.ID))
	if !ok {
		http.Error(w, "unknown server", http.StatusBadRequest)
		return
	}
	st := checkServerUpdates(s)
	if st.Error != "" {
		w.WriteHeader(http.StatusBadGateway)
	}
	writeJSON(w, st)
}

// updatePolicyForDecision only changes a server's future pre-start update policy.
// No running Minecraft process is stopped or restarted by this API.
func updatePolicyForDecision(decision string) (string, bool) {
	switch strings.ToLower(strings.TrimSpace(decision)) {
	case "defer":
		return serverUpdateHold, true
	case "manual":
		return serverUpdateManual, true
	case "enable-managed":
		return serverUpdateManaged, true
	default:
		return "", false
	}
}

func apiV4UpdateDecision(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", http.StatusMethodNotAllowed)
		return
	}
	var q struct {
		ID string `json:"id"`
		Decision string `json:"decision"`
	}
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q); err != nil {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	id := strings.ToLower(strings.TrimSpace(q.ID))
	policy, ok := updatePolicyForDecision(q.Decision)
	if !ok {
		http.Error(w, "decision must be defer, manual, or enable-managed", http.StatusBadRequest)
		return
	}
	c := configSnapshot()
	found := false
	for i := range c.Servers {
		if strings.EqualFold(c.Servers[i].ID, id) {
			c.Servers[i].UpdatePolicy = policy
			found = true
			break
		}
	}
	if !found {
		http.Error(w, "unknown server", http.StatusBadRequest)
		return
	}
	if err := saveHostConfig(c); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	appendV4Event("info", "update", id, "업데이트 실행 정책 변경", "policy="+policy)
	writeJSON(w, map[string]any{
		"ok": true,
		"server_id": id,
		"update_policy": policy,
		"requires_server_restart": policy == serverUpdateManaged,
		"server_restarted": false,
	})
}

func checkServerUpdates(s ServerConfig) UpdateStatus {
	s = normalizeServerConfig(s)
	c := effectiveUpdateConfigForServer(s)
	st := updateStatusPolicyFields(UpdateStatus{ServerID: s.ID, Phase: "checking", Message: "배포 manifest 확인 중"}, s)
	setUpdateStatus(st)
	if !c.Enabled {
		st.Phase = "disabled"
		st.Message = "자동 업데이트가 비활성화되어 있습니다"
		return setUpdateStatus(st)
	}
	manifest, _, release, err := fetchVerifiedManifestPinned(c, s.UpdatePin)
	if err != nil {
		st.Phase = "error"
		st.Message = "업데이트 확인 실패"
		st.Error = err.Error()
		return setUpdateStatus(st)
	}
	st.Release = release
	if rejected, reason := rejectedUpdateForRelease(s, release); rejected {
		st.Phase = "held"
		st.Message = "직전 health 실패 release 자동 보류 · 기존 버전으로 서버 시작"
		st.Error = reason
		appendV4Event("warn", "update", s.ID, st.Message, "release="+release+" reason="+reason)
		return setUpdateStatus(st)
	}
	plan, err := buildUpdatePlan(s, manifest)
	if err != nil {
		st.Phase = "error"
		st.Message = "업데이트 계획 생성 실패"
		st.Error = err.Error()
		return setUpdateStatus(st)
	}
	for _, item := range plan {
		st.Available = append(st.Available, item.Component.PluginName+" "+item.Installed.Version+" -> "+item.Component.Version)
	}
	if len(plan) == 0 {
		st.Phase = "current"
		st.Message = "설치된 자체 플러그인이 최신 상태입니다"
	} else {
		st.Phase = "available"
		st.Message = fmt.Sprintf("%d개 업데이트 가능", len(plan))
	}
	return setUpdateStatus(st)
}

// runPreStartUpdater is deliberately fail-open. It is called only while the
// Minecraft server is offline. Any discovery/download/signature/hash/install
// failure is recorded, but startServerLocked continues to the user's original
// start.bat so a GitHub/network problem cannot take the server offline.
func runPreStartUpdater(s ServerConfig) UpdateStatus {
	s = normalizeServerConfig(s)
	c := effectiveUpdateConfigForServer(s)
	st := updateStatusPolicyFields(UpdateStatus{ServerID: s.ID, Phase: "checking", Message: "서버 시작 전 업데이트 확인 중"}, s)
	if !c.Enabled {
		st.Phase = "disabled"
		st.Message = "자동 업데이트 비활성화"
		return setUpdateStatus(st)
	}

	updateApplyMu.Lock()
	defer updateApplyMu.Unlock()

	setUpdateStatus(st)
	if _, err := recoverInterruptedUpdate(s); err != nil {
		st.Phase = "blocked"
		st.Message = "미완료 업데이트 복구 실패 · 안전을 위해 서버 시작 차단"
		st.Error = err.Error()
		st.BlockStart = true
		appendV4Event("error", "update", s.ID, st.Message, st.Error)
		return setUpdateStatus(st)
	}
	// A deferred/manual policy preserves the existing plugin set on startup.
	// Interrupted transaction recovery above still runs before this decision.
	switch normalizeServerUpdatePolicy(s.UpdatePolicy) {
	case serverUpdateHold:
		st.Phase = "held"
		st.Message = "사용자가 업데이트를 보류했습니다 · 기존 파일로 서버 시작"
		return setUpdateStatus(st)
	case serverUpdateManual:
		st.Phase = "manual"
		st.Message = "수동 업데이트 정책 · 기존 파일로 서버 시작"
		return setUpdateStatus(st)
	}
	manifest, manifestHash, release, err := fetchVerifiedManifestPinned(c, s.UpdatePin)
	if err != nil {
		st.Phase = "error"
		st.Message = "업데이트 확인 실패 · 기존 파일로 서버 시작"
		st.Error = err.Error()
		appendV4Event("warn", "update", s.ID, st.Message, st.Error)
		return setUpdateStatus(st)
	}
	st.Release = release
	plan, err := buildUpdatePlan(s, manifest)
	if err != nil {
		st.Phase = "error"
		st.Message = "업데이트 계획 실패 · 기존 파일로 서버 시작"
		st.Error = err.Error()
		appendV4Event("warn", "update", s.ID, st.Message, st.Error)
		return setUpdateStatus(st)
	}
	for _, item := range plan {
		st.Available = append(st.Available, item.Component.PluginName+" "+item.Installed.Version+" -> "+item.Component.Version)
	}
	if len(plan) == 0 {
		st.Phase = "current"
		st.Message = "업데이트 없음"
		return setUpdateStatus(st)
	}

	st.Phase = "downloading"
	st.Message = fmt.Sprintf("%d개 업데이트 검증/적용 중", len(plan))
	setUpdateStatus(st)

	cachePaths := make(map[string]string, len(plan))
	for _, item := range plan {
		cachePath, err := downloadVerifiedArtifact(c, release, item.Component)
		if err != nil {
			st.Phase = "error"
			st.Message = "업데이트 다운로드/검증 실패 · 기존 파일로 서버 시작"
			st.Error = item.Component.PluginName + ": " + err.Error()
			appendV4Event("warn", "update", s.ID, st.Message, st.Error)
			return setUpdateStatus(st)
		}
		cachePaths[item.Key] = cachePath
	}

	tx, err := applyUpdateTransaction(s, plan, cachePaths, c.Channel, release, manifestHash)
	if err != nil {
		st.Phase = "error"
		st.Message = "업데이트 트랜잭션 실패 · 이전 파일 복구 후 서버 시작"
		st.Error = err.Error()
		st.BlockStart = hasPendingUpdate(s)
		if st.BlockStart {
			st.Phase = "blocked"
			st.Message = "업데이트 트랜잭션 복구 미완료 · 안전을 위해 서버 시작 차단"
		}
		appendV4Event("warn", "update", s.ID, st.Message, st.Error)
		return setUpdateStatus(st)
	}
	st.Transaction = tx.ID
	for _, item := range tx.Items {
		st.Applied = append(st.Applied, item.PluginName+" "+item.ToVersion)
	}
	st.Phase = "pending_health"
	st.Message = fmt.Sprintf("%d개 업데이트 적용 · 서버 시작 후 health 검증 대기", len(st.Applied))
	appendV4Event("info", "update", s.ID, st.Message, "transaction="+tx.ID+" "+strings.Join(st.Applied, ", "))
	return setUpdateStatus(st)
}

func fetchVerifiedManifest(c UpdateConfig) (DeploymentManifest, string, string, error) {
	return fetchVerifiedManifestPinnedMode(c, "", false)
}

func fetchVerifiedManifestFresh(c UpdateConfig) (DeploymentManifest, string, string, error) {
	return fetchVerifiedManifestPinnedMode(c, "", true)
}

func fetchVerifiedManifestPinned(c UpdateConfig, pin string) (DeploymentManifest, string, string, error) {
	return fetchVerifiedManifestPinnedMode(c, pin, false)
}

func fetchVerifiedManifestPinnedMode(c UpdateConfig, pin string, forceNetwork bool) (DeploymentManifest, string, string, error) {
	var zero DeploymentManifest
	pub, err := loadDeploymentPublicKey(c.PublicKeyPath)
	if err != nil {
		return zero, "", "", err
	}
	parts := strings.Split(c.Repository, "/")
	if len(parts) != 2 {
		return zero, "", "", errors.New("invalid update repository")
	}
	timeout := time.Duration(c.TimeoutSeconds) * time.Second
	client := &http.Client{Timeout: timeout}
	apiURL := "https://api.github.com/repos/" + url.PathEscape(parts[0]) + "/" + url.PathEscape(parts[1]) + "/releases?per_page=30"
	var body []byte
	if forceNetwork {
		body, _, err = githubPublicJSONFresh(client, apiURL, 4<<20)
	} else {
		body, _, err = githubPublicJSON(client, apiURL, 4<<20)
	}
	if err != nil {
		return zero, "", "", fmt.Errorf("GitHub release 조회 실패: %w", err)
	}
	var releases []githubRelease
	if err := json.Unmarshal(body, &releases); err != nil {
		return zero, "", "", fmt.Errorf("GitHub release 응답 해석 실패: %w", err)
	}
	if strings.TrimSpace(pin) == "" {
		sortGitHubReleasesNewestFirst(releases)
	}

	manifestName := "deployment-" + c.Channel + ".json"
	sigName := manifestName + ".sig"
	pin = strings.TrimSpace(pin)
	for _, rel := range releases {
		if rel.Draft {
			continue
		}
		if pin != "" && rel.TagName != pin {
			continue
		}
		var manifestURL, sigURL string
		for _, a := range rel.Assets {
			switch a.Name {
			case manifestName:
				manifestURL = a.BrowserDownloadURL
			case sigName:
				sigURL = a.BrowserDownloadURL
			}
		}
		if manifestURL == "" || sigURL == "" {
			continue
		}
		manifestBytes, err := fetchSmallHTTPS(client, manifestURL, 2<<20)
		if err != nil {
			return zero, "", "", fmt.Errorf("manifest 다운로드 실패: %w", err)
		}
		sig, err := fetchSmallHTTPS(client, sigURL, 4096)
		if err != nil {
			return zero, "", "", fmt.Errorf("manifest signature 다운로드 실패: %w", err)
		}
		if !ed25519.Verify(pub, manifestBytes, sig) {
			return zero, "", "", errors.New("deployment manifest Ed25519 signature 검증 실패")
		}
		var m DeploymentManifest
		if err := json.Unmarshal(manifestBytes, &m); err != nil {
			return zero, "", "", fmt.Errorf("manifest JSON 오류: %w", err)
		}
		if m.Schema != 1 || m.Channel != c.Channel || m.Release != rel.TagName || m.Repository != c.Repository {
			return zero, "", "", errors.New("manifest metadata가 요청한 channel/release/repository와 일치하지 않습니다")
		}
		sum := sha256.Sum256(manifestBytes)
		return m, hex.EncodeToString(sum[:]), rel.TagName, nil
	}
	if pin != "" {
		return zero, "", "", fmt.Errorf("고정 release %s에서 %s 채널의 서명된 deployment manifest를 찾지 못했습니다", pin, c.Channel)
	}
	return zero, "", "", fmt.Errorf("%s 채널의 서명된 deployment manifest를 최근 GitHub Release에서 찾지 못했습니다", c.Channel)
}

func fetchSmallHTTPS(client *http.Client, rawURL string, max int64) ([]byte, error) {
	u, err := url.Parse(rawURL)
	if err != nil || u.Scheme != "https" || u.Host == "" {
		return nil, errors.New("HTTPS URL required")
	}
	req, _ := http.NewRequest(http.MethodGet, rawURL, nil)
	req.Header.Set("User-Agent", "GeumyiServerCenter/"+appVersion)
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, max+1))
	if err != nil {
		return nil, err
	}
	if int64(len(b)) > max {
		return nil, errors.New("response too large")
	}
	return b, nil
}

func loadDeploymentPublicKey(path string) (ed25519.PublicKey, error) {
	if strings.TrimSpace(path) == "" {
		return nil, errors.New("deployment public key path is empty")
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("deployment public key 읽기 실패: %w", err)
	}
	block, _ := pem.Decode(b)
	if block == nil {
		return nil, errors.New("deployment public key PEM 형식 오류")
	}
	key, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("deployment public key 해석 실패: %w", err)
	}
	pub, ok := key.(ed25519.PublicKey)
	if !ok || len(pub) != ed25519.PublicKeySize {
		return nil, errors.New("deployment public key가 Ed25519가 아닙니다")
	}
	return pub, nil
}


func buildUpdatePlan(s ServerConfig, m DeploymentManifest) ([]updatePlanItem, error) {
	dir := resolveServerDir(s)
	if dir == "" {
		return nil, errors.New("server directory unavailable")
	}
	installed := pluginInventory(dir)
	byName := map[string][]PluginInventory{}
	for _, p := range installed {
		if !p.Enabled || p.Name == "" {
			continue
		}
		k := strings.ToLower(p.Name)
		byName[k] = append(byName[k], p)
	}

	keys := make([]string, 0, len(m.Components))
	for k := range m.Components {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	plan := []updatePlanItem{}
	for _, key := range keys {
		comp := m.Components[key]
		if strings.ToLower(comp.Kind) != "plugin" || !targetIncludesServer(comp.Targets, s) {
			continue
		}
		if !strings.HasPrefix(strings.ToLower(comp.PluginName), "geumyi") {
			return nil, fmt.Errorf("refusing non-Geumyi managed plugin: %s", comp.PluginName)
		}
		current := byName[strings.ToLower(comp.PluginName)]
		if len(current) == 0 {
			// Day 8 updates existing self-managed plugins only. Automatic first
			// install/policy assignment is intentionally deferred to fleet policy.
			continue
		}
		if len(current) != 1 {
			return nil, fmt.Errorf("%s installed JAR count is %d; refusing ambiguous replacement", comp.PluginName, len(current))
		}
		if current[0].Version == comp.Version {
			continue
		}
		if filepath.Base(comp.File) != comp.File || !strings.HasSuffix(strings.ToLower(comp.File), ".jar") {
			return nil, fmt.Errorf("%s has unsafe artifact file name", comp.PluginName)
		}
		if len(comp.SHA256) != 64 {
			return nil, fmt.Errorf("%s has invalid sha256", comp.PluginName)
		}
		if _, err := hex.DecodeString(comp.SHA256); err != nil {
			return nil, fmt.Errorf("%s has invalid sha256", comp.PluginName)
		}
		if comp.Size <= 0 || comp.Size > 256<<20 {
			return nil, fmt.Errorf("%s has invalid artifact size", comp.PluginName)
		}
		u, err := url.Parse(comp.URL)
		if err != nil || u.Scheme != "https" || u.Host == "" {
			return nil, fmt.Errorf("%s has non-HTTPS artifact URL", comp.PluginName)
		}
		plan = append(plan, updatePlanItem{Key: key, Component: comp, Installed: current[0]})
	}
	if err := validateUpdatePlan(s, m, plan); err != nil {
		return nil, err
	}
	return plan, nil
}

func downloadVerifiedArtifact(c UpdateConfig, release string, comp DeploymentComponent) (string, error) {
	cacheDir := filepath.Join(v4Root(), "Updates", "cache", safePathPart(release))
	if err := os.MkdirAll(cacheDir, 0755); err != nil {
		return "", err
	}
	dst := filepath.Join(cacheDir, comp.File)
	if ok, _ := verifyArtifactFile(dst, comp); ok {
		return dst, nil
	}
	_ = os.Remove(dst)

	client := &http.Client{Timeout: time.Duration(c.TimeoutSeconds) * time.Second}
	req, _ := http.NewRequest(http.MethodGet, comp.URL, nil)
	req.Header.Set("User-Agent", "GeumyiServerCenter/"+appVersion)
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	tmp := dst + ".part"
	_ = os.Remove(tmp)
	f, err := os.OpenFile(tmp, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0644)
	if err != nil {
		return "", err
	}
	h := sha256.New()
	n, copyErr := io.Copy(io.MultiWriter(f, h), io.LimitReader(resp.Body, (256<<20)+1))
	closeErr := f.Close()
	if copyErr != nil {
		_ = os.Remove(tmp)
		return "", copyErr
	}
	if closeErr != nil {
		_ = os.Remove(tmp)
		return "", closeErr
	}
	if n > 256<<20 {
		_ = os.Remove(tmp)
		return "", errors.New("artifact too large")
	}
	if n != comp.Size {
		_ = os.Remove(tmp)
		return "", fmt.Errorf("artifact size mismatch: got %d want %d", n, comp.Size)
	}
	if !strings.EqualFold(hex.EncodeToString(h.Sum(nil)), comp.SHA256) {
		_ = os.Remove(tmp)
		return "", errors.New("artifact SHA-256 mismatch")
	}
	if err := os.Rename(tmp, dst); err != nil {
		_ = os.Remove(tmp)
		return "", err
	}
	return dst, nil
}

func verifyArtifactFile(path string, comp DeploymentComponent) (bool, error) {
	st, err := os.Stat(path)
	if err != nil || st.IsDir() {
		return false, err
	}
	if st.Size() != comp.Size {
		return false, nil
	}
	f, err := os.Open(path)
	if err != nil {
		return false, err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return false, err
	}
	return strings.EqualFold(hex.EncodeToString(h.Sum(nil)), comp.SHA256), nil
}

func replaceManagedPluginPreStart(s ServerConfig, item updatePlanItem, cachePath string) error {
	dir := resolveServerDir(s)
	if dir == "" {
		return errors.New("server directory unavailable")
	}
	pluginDir := filepath.Join(dir, "plugins")
	oldPath := filepath.Join(pluginDir, item.Installed.File)
	newPath := filepath.Join(pluginDir, item.Component.File)
	if filepath.Clean(oldPath) == filepath.Clean(newPath) {
		newPath = oldPath
	}
	stagingDir := filepath.Join(dir, ".geumyi-update", "staging")
	previousDir := filepath.Join(dir, ".geumyi-update", "previous")
	if err := os.MkdirAll(stagingDir, 0755); err != nil {
		return err
	}
	if err := os.MkdirAll(previousDir, 0755); err != nil {
		return err
	}
	stage := filepath.Join(stagingDir, item.Component.File+".new")
	_ = os.Remove(stage)
	if err := copyFileV4(cachePath, stage); err != nil {
		return err
	}
	ok, err := verifyArtifactFile(stage, item.Component)
	if err != nil || !ok {
		_ = os.Remove(stage)
		if err != nil {
			return err
		}
		return errors.New("staged artifact verification failed")
	}

	backup := filepath.Join(previousDir, safePathPart(item.Component.PluginName)+".jar.previous")
	_ = os.Remove(backup)
	if err := copyFileV4(oldPath, backup); err != nil {
		_ = os.Remove(stage)
		return fmt.Errorf("current plugin backup failed: %w", err)
	}

	// Do not leave two enabled JARs for the same plugin. The previous copy lives
	// outside plugins/, so Paper cannot load it.
	if filepath.Clean(oldPath) != filepath.Clean(newPath) {
		if _, err := os.Stat(newPath); err == nil {
			_ = os.Remove(stage)
			return fmt.Errorf("target JAR already exists: %s", filepath.Base(newPath))
		}
	}
	if err := os.Remove(oldPath); err != nil {
		_ = os.Remove(stage)
		return fmt.Errorf("old plugin remove failed: %w", err)
	}
	if err := os.Rename(stage, newPath); err != nil {
		_ = copyFileV4(backup, oldPath)
		_ = os.Remove(stage)
		return fmt.Errorf("new plugin activate failed: %w", err)
	}
	ok, err = verifyArtifactFile(newPath, item.Component)
	if err != nil || !ok {
		_ = os.Remove(newPath)
		_ = copyFileV4(backup, oldPath)
		if err != nil {
			return fmt.Errorf("installed artifact verify failed and previous restored: %w", err)
		}
		return errors.New("installed artifact hash mismatch; previous restored")
	}
	return nil
}

func safePathPart(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return "_"
	}
	var b strings.Builder
	for _, r := range s {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '.', r == '-', r == '_':
			b.WriteRune(r)
		default:
			b.WriteByte('_')
		}
	}
	return b.String()
}

func writeUpdateState(s ServerConfig, st UpdateStatus, manifestHash string) {
	root := filepath.Join(v4Root(), "Updates", "state")
	_ = os.MkdirAll(root, 0755)
	payload := map[string]any{
		"server_id":       s.ID,
		"channel":         st.Channel,
		"release":         st.Release,
		"manifest_sha256": manifestHash,
		"applied":         st.Applied,
		"updated":         time.Now().Format(time.RFC3339),
	}
	b, _ := json.MarshalIndent(payload, "", "  ")
	tmp := filepath.Join(root, safePathPart(s.ID)+".json.tmp")
	dst := filepath.Join(root, safePathPart(s.ID)+".json")
	if os.WriteFile(tmp, b, 0644) == nil {
		_ = os.Remove(dst)
		_ = os.Rename(tmp, dst)
	}
}
