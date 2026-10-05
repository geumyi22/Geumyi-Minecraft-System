package main

import (
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type GSCSelfUpdateStatus struct {
	Installed         string `json:"installed"`
	Latest            string `json:"latest,omitempty"`
	Available         bool   `json:"available"`
	Channel           string `json:"channel"`
	Release           string `json:"release,omitempty"`
	File              string `json:"file,omitempty"`
	SHA256            string `json:"sha256,omitempty"`
	Size              int64  `json:"size,omitempty"`
	SignatureVerified bool   `json:"signature_verified"`
	Staged            bool   `json:"staged"`
	StagedPath        string `json:"staged_path,omitempty"`
	LiveApplied       bool   `json:"live_applied"`
	Message           string `json:"message"`
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

func checkGSCSelfUpdate() GSCSelfUpdateStatus {
	c := normalizeUpdateConfig(configSnapshot().Update)
	st := GSCSelfUpdateStatus{
		Installed: appVersion,
		Channel: c.Channel,
		LiveApplied: false,
		Updated: time.Now().Format(time.RFC3339),
		Message: "서명된 GSC release 확인 중",
	}
	m, _, release, err := fetchVerifiedManifest(c)
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
	st.Available = comp.Version != appVersion
	stage := selfUpdateStagePath(release, comp)
	if ok, _ := verifyArtifactFile(stage, comp); ok {
		st.Staged = true
		st.StagedPath = stage
	}
	if st.Available {
		st.Message = "검증된 GSC 업데이트 사용 가능"
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
		st := checkGSCSelfUpdate()
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
	writeJSON(w, checkGSCSelfUpdate())
}

func apiV4GSCSelfUpdateStage(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", http.StatusMethodNotAllowed)
		return
	}
	c := normalizeUpdateConfig(configSnapshot().Update)
	m, _, release, err := fetchVerifiedManifest(c)
	if err != nil {
		http.Error(w, "signed GSC manifest verification failed: "+err.Error(), http.StatusBadGateway)
		return
	}
	comp, err := selfUpdateComponent(m)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
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
