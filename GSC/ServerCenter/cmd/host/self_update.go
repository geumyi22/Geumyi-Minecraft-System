package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type GSCSelfUpdateStatus struct {
	Installed         string `json:"installed"`
	Latest            string `json:"latest,omitempty"`
	Available         bool   `json:"available"`
	DowngradeBlocked  bool   `json:"downgrade_blocked"`
	TargetRelation    string `json:"target_relation,omitempty"`
	Channel           string `json:"channel"`
	Release           string `json:"release,omitempty"`
	File              string `json:"file,omitempty"`
	SHA256            string `json:"sha256,omitempty"`
	Size              int64  `json:"size,omitempty"`
	SignatureVerified bool   `json:"signature_verified"`
	Staged            bool   `json:"staged"`
	StagedPath        string `json:"staged_path,omitempty"`
	LiveApplied       bool           `json:"live_applied"`
	LastApply         map[string]any `json:"last_apply,omitempty"`
	Message           string         `json:"message"`
	Error             string `json:"error,omitempty"`
	Updated           string `json:"updated"`
}

func selfUpdateComponent(m DeploymentManifest) (DeploymentComponent, error) {
	comp, ok := m.Components["gsc"]
	if !ok {
		return DeploymentComponent{}, errors.New("signed deployment manifest has no gsc component")
	}
	if !strings.EqualFold(strings.TrimSpace(comp.Kind), "gsc") {
		return DeploymentComponent{}, errors.New("gsc component kind mismatch")
	}
	hostTarget := false
	for _, t := range comp.Targets {
		t = strings.ToLower(strings.TrimSpace(t))
		if t == "host" || t == "*" {
			hostTarget = true
			break
		}
	}
	if !hostTarget {
		return DeploymentComponent{}, errors.New("gsc component is not targeted to host")
	}
	if strings.TrimSpace(comp.Version) == "" || filepath.Base(comp.File) != comp.File || strings.TrimSpace(comp.File) == "" {
		return DeploymentComponent{}, errors.New("gsc component metadata is incomplete")
	}
	if len(comp.SHA256) != 64 || comp.Size <= 0 {
		return DeploymentComponent{}, errors.New("gsc component verification metadata is invalid")
	}
	return comp, nil
}

func selfUpdateStagePath(release string, comp DeploymentComponent) string {
	return filepath.Join(v4Root(), "Staging", "GSC", safePathPart(release), comp.File)
}

func gscSelfUpdateLastPath() string {
	return filepath.Join(v4Root(), "Updates", "gsc-self-update-last.json")
}

func gscSelfUpdateLockPath() string {
	return filepath.Join(v4Root(), "Updates", "gsc-self-update.lock")
}

func readGSCSelfUpdateLast() map[string]any {
	b, err := os.ReadFile(gscSelfUpdateLastPath())
	if err != nil {
		return nil
	}
	var out map[string]any
	if json.Unmarshal(b, &out) != nil {
		return nil
	}
	return out
}

func reserveGSCSelfUpdateLaunch(target string) error {
	p := gscSelfUpdateLockPath()
	if st, err := os.Stat(p); err == nil {
		if time.Since(st.ModTime()) < 15*time.Minute {
			return errors.New("GSC self-update helper is already active")
		}
		_ = os.Remove(p)
	}
	if err := os.MkdirAll(filepath.Dir(p), 0755); err != nil {
		return err
	}
	f, err := os.OpenFile(p, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	_, werr := f.WriteString(target + "\n")
	cerr := f.Close()
	if werr != nil {
		_ = os.Remove(p)
		return werr
	}
	if cerr != nil {
		_ = os.Remove(p)
		return cerr
	}
	return nil
}

func parseGSCVersion(v string) ([]int, error) {
	v = strings.TrimSpace(strings.TrimPrefix(strings.TrimPrefix(v, "v"), "V"))
	if v == "" {
		return nil, errors.New("empty version")
	}
	if i := strings.IndexAny(v, "-+"); i >= 0 {
		v = v[:i]
	}
	parts := strings.Split(v, ".")
	if len(parts) < 2 || len(parts) > 4 {
		return nil, fmt.Errorf("unsupported version format: %s", v)
	}
	out := make([]int, len(parts))
	for i, p := range parts {
		if p == "" {
			return nil, fmt.Errorf("unsupported version format: %s", v)
		}
		n, err := strconv.Atoi(p)
		if err != nil || n < 0 {
			return nil, fmt.Errorf("unsupported version format: %s", v)
		}
		out[i] = n
	}
	return out, nil
}

// gscVersionPrerelease preserves prerelease ordering while keeping the
// existing deployed numeric core parser. A release version is strictly newer
// than its prerelease. Build metadata after '+' never affects precedence.
func gscVersionPrerelease(v string) (string, error) {
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
		return "", errors.New("empty GSC prerelease identifier")
	}
	for _, part := range strings.Split(pre, ".") {
		if part == "" {
			return "", errors.New("empty GSC prerelease segment")
		}
		for _, ch := range part {
			if !(ch >= '0' && ch <= '9' || ch >= 'a' && ch <= 'z' ||
				ch >= 'A' && ch <= 'Z' || ch == '-') {
				return "", errors.New("invalid GSC prerelease segment")
			}
		}
	}
	return pre, nil
}

func gscNumericIdentifier(s string) bool {
	if s == "" {
		return false
	}
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

func gscComparePrerelease(a, b string) int {
	if a == b {
		return 0
	}
	if a == "" {
		return 1 // release > prerelease
	}
	if b == "" {
		return -1
	}
	aa, bb := strings.Split(a, "."), strings.Split(b, ".")
	for i := 0; i < len(aa) && i < len(bb); i++ {
		if aa[i] == bb[i] {
			continue
		}
		an, bn := gscNumericIdentifier(aa[i]), gscNumericIdentifier(bb[i])
		if an && !bn {
			return -1
		}
		if !an && bn {
			return 1
		}
		if an {
			ai := strings.TrimLeft(aa[i], "0")
			bi := strings.TrimLeft(bb[i], "0")
			if len(ai) < len(bi) {
				return -1
			}
			if len(ai) > len(bi) {
				return 1
			}
			if ai < bi {
				return -1
			}
			return 1
		}
		if aa[i] < bb[i] {
			return -1
		}
		return 1
	}
	if len(aa) < len(bb) {
		return -1
	}
	return 1
}

func compareGSCVersions(a, b string) (int, error) {
	av, err := parseGSCVersion(a)
	if err != nil {
		return 0, err
	}
	bv, err := parseGSCVersion(b)
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
	ap, err := gscVersionPrerelease(a)
	if err != nil {
		return 0, err
	}
	bp, err := gscVersionPrerelease(b)
	if err != nil {
		return 0, err
	}
	return gscComparePrerelease(ap, bp), nil
}

func requireNewerGSCVersion(target string) error {
	cmp, err := compareGSCVersions(appVersion, target)
	if err != nil {
		return fmt.Errorf("cannot safely compare GSC versions: %w", err)
	}
	if cmp >= 0 {
		if cmp == 0 {
			return fmt.Errorf("GSC is already on verified target version %s", target)
		}
		return fmt.Errorf("downgrade blocked: installed GSC %s is newer than verified release %s", appVersion, target)
	}
	return nil
}

func checkGSCSelfUpdate(forceNetwork bool) GSCSelfUpdateStatus {
	c := normalizeUpdateConfig(configSnapshot().Update)
	st := GSCSelfUpdateStatus{
		Installed: appVersion,
		Channel: c.Channel,
		LiveApplied: false,
		LastApply: readGSCSelfUpdateLast(),
		Updated: time.Now().Format(time.RFC3339),
		Message: "서명된 GSC release 확인 중",
	}
	var m DeploymentManifest
	var release string
	var err error
	if forceNetwork {
		m, _, release, err = fetchVerifiedManifestFresh(c)
	} else {
		m, _, release, err = fetchVerifiedManifest(c)
	}
	if err != nil {
		st.Message = "GSC 업데이트 확인 실패"
		st.Error = err.Error()
		return st
	}
	comp, err := selfUpdateComponent(m)
	if err != nil {
		st.Message = "GSC 업데이트 manifest 오류"
		st.Error = err.Error()
		return st
	}
	st.Release = release
	st.Latest = comp.Version
	st.File = comp.File
	st.SHA256 = comp.SHA256
	st.Size = comp.Size
	st.SignatureVerified = true
	if cmp, cmpErr := compareGSCVersions(appVersion, comp.Version); cmpErr != nil {
		st.TargetRelation = "unknown"
		st.Message = "GSC 버전 비교 실패"
		st.Error = cmpErr.Error()
		return st
	} else if cmp < 0 {
		st.TargetRelation = "newer"
		st.Available = true
	} else if cmp == 0 {
		st.TargetRelation = "same"
	} else {
		st.TargetRelation = "older"
		st.DowngradeBlocked = true
	}
	stage := selfUpdateStagePath(release, comp)
	if st.Available {
		if ok, _ := verifyArtifactFile(stage, comp); ok {
			st.Staged = true
			st.StagedPath = stage
		}
	}
	if st.Available {
		st.Message = "검증된 GSC 업데이트 사용 가능"
	} else if st.DowngradeBlocked {
		st.Message = "현재 GSC가 검증 release보다 최신입니다 · 다운그레이드 차단"
	} else {
		st.Message = "GSC가 현재 검증 release와 일치합니다"
	}
	return st
}

func startGSCSelfUpdateStartupCheck() {
	go func() {
		// Keep Host startup fail-open. Release discovery happens only after the
		// local API/runtime is initialized and never blocks Minecraft startup.
		time.Sleep(5 * time.Second)
		st := checkGSCSelfUpdate(false)
		if st.Error != "" {
			appendV4Event("warn", "update", "", "GSC 시작 시 업데이트 확인 실패", st.Error)
			return
		}
		if st.Available {
			appendV4Event("info", "update", "", "검증된 GSC 업데이트 사용 가능",
				"installed="+st.Installed+" target="+st.Latest+" release="+st.Release)
		}
	}()
}

func apiV4GSCSelfUpdateStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", http.StatusMethodNotAllowed)
		return
	}
	force := r.URL.Query().Get("fresh") == "1"
	writeJSON(w, checkGSCSelfUpdate(force))
}

func apiV4GSCSelfUpdateStage(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", http.StatusMethodNotAllowed)
		return
	}
	c := normalizeUpdateConfig(configSnapshot().Update)
	m, _, release, err := fetchVerifiedManifestFresh(c)
	if err != nil {
		http.Error(w, "signed GSC manifest verification failed: "+err.Error(), http.StatusBadGateway)
		return
	}
	comp, err := selfUpdateComponent(m)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	if err = requireNewerGSCVersion(comp.Version); err != nil {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	cachePath, err := downloadVerifiedArtifact(c, release, comp)
	if err != nil {
		http.Error(w, "GSC artifact download/verification failed: "+err.Error(), http.StatusBadGateway)
		return
	}
	dst := selfUpdateStagePath(release, comp)
	if err = os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if err = copyFileV4(cachePath, dst); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if ok, verifyErr := verifyArtifactFile(dst, comp); verifyErr != nil || !ok {
		_ = os.Remove(dst)
		if verifyErr != nil {
			http.Error(w, "staged GSC verification failed: "+verifyErr.Error(), http.StatusInternalServerError)
		} else {
			http.Error(w, "staged GSC verification failed", http.StatusInternalServerError)
		}
		return
	}
	appendV4Event("info", "update", "", "GSC self-update artifact staging 완료",
		"release="+release+" version="+comp.Version+" live_modified=false")
	appendAudit(r, "update.gsc.stage", release, "completed", "version="+comp.Version)
	writeJSON(w, map[string]any{
		"ok": true,
		"installed": appVersion,
		"target": comp.Version,
		"release": release,
		"sha256": comp.SHA256,
		"staged_path": dst,
		"live_applied": false,
		"next_step": "helper replacement + GSC-only backup + service restart + health gate + rollback",
	})
}


func apiV4GSCSelfUpdateApply(w http.ResponseWriter, r *http.Request) {
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
	if q.Confirm != "APPLY_GSC_SELF_UPDATE" {
		http.Error(w, "confirm must be APPLY_GSC_SELF_UPDATE", http.StatusBadRequest)
		return
	}
	c := normalizeUpdateConfig(configSnapshot().Update)
	m, _, release, err := fetchVerifiedManifestFresh(c)
	if err != nil {
		http.Error(w, "signed GSC manifest verification failed: "+err.Error(), http.StatusBadGateway)
		return
	}
	comp, err := selfUpdateComponent(m)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	if err = requireNewerGSCVersion(comp.Version); err != nil {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	stage := selfUpdateStagePath(release, comp)
	if ok, verifyErr := verifyArtifactFile(stage, comp); verifyErr != nil || !ok {
		http.Error(w, "verified staged GSC installer is required before apply", http.StatusConflict)
		return
	}
	if err = reserveGSCSelfUpdateLaunch(comp.Version); err != nil {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	cmd := exec.Command(stage, "--self-update")
	cmd.Dir = filepath.Dir(stage)
	if err = cmd.Start(); err != nil {
		_ = os.Remove(gscSelfUpdateLockPath())
		http.Error(w, "self-update helper launch failed: "+err.Error(), http.StatusInternalServerError)
		return
	}
	appendV4Event("warn", "update", "", "GSC self-update helper 시작",
		"target="+comp.Version+" release="+release+" minecraft_velocity_touched=false")
	appendAudit(r, "update.gsc.apply", release, "accepted", "target="+comp.Version)
	writeJSON(w, map[string]any{
		"ok": true,
		"accepted": true,
		"installed": appVersion,
		"target": comp.Version,
		"release": release,
		"host_will_restart": true,
		"minecraft_velocity_touched": false,
		"result_path": gscSelfUpdateLastPath(),
	})
}
