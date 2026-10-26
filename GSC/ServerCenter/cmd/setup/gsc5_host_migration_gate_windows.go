//go:build windows

package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// This gate protects an operator's existing Host BEFORE doInstall reaches
// prepareForUpgradeAll (which stops GSC processes) or rewrites config.
//
// 5.0.0-beta.1 was built from 4.5.1 Stable, not the separately installed
// 4.5.2 Canary experiment. The gate is NOT permission to install in production:
// operator backup, rollback, port ownership and live QA remain mandatory.
const gsc5MigrationHealthURL = "http://127.0.0.1:8787/api/health"

type gsc5ExistingHostHealth struct {
	OK         bool   `json:"ok"`
	Version    string `json:"version"`
	Service    bool   `json:"service"`
	Generation int    `json:"generation"`
}

func isGSC452CanaryVersion(v string) bool {
	v = strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(v), "v"))
	return v == "4.5.2" || strings.HasPrefix(v, "4.5.2-") || strings.HasPrefix(v, "4.5.2+")
}

func gsc5MigrationDecision(role int, storedVersion string, health gsc5ExistingHostHealth, healthKnown bool) error {
	if !hasServerRole(role) {
		return nil // Never query a production Host for a disposable Client-only install.
	}
	if isGSC452CanaryVersion(storedVersion) || isGSC452CanaryVersion(health.Version) {
		return errors.New("existing GSC 4.5.2 Canary Host migration is not verified; upgrade stopped before service changes")
	}
	if !healthKnown || !health.OK || !health.Service || health.Generation != 4 {
		return errors.New("existing Host identity/health unverified; upgrade stopped before service changes")
	}
	// Only the published stable-base -> beta path and same-beta reinstall
	// are covered by this source-level gate; older or unexpected Host
	// versions need separately evaluated operator-approved migration.
	if health.Version != "4.5.1" && health.Version != version {
		return fmt.Errorf("existing Host version %q has no approved GSC 5 beta migration path", health.Version)
	}
	return nil
}

func gsc5ReadStoredRoleVersion(dataDir string) (string, error) {
	b, err := os.ReadFile(filepath.Join(dataDir, roleStateFile))
	if errors.Is(err, os.ErrNotExist) {
		return "", nil // Legacy Host installs may not have role.json.
	}
	if err != nil {
		return "", err
	}
	var state struct {
		Version string `json:"version"`
	}
	if err := json.Unmarshal(b, &state); err != nil {
		return "", fmt.Errorf("existing role state unreadable: %w", err)
	}
	return state.Version, nil
}

func gsc5ReadExistingHostHealth(client *http.Client, url string) (gsc5ExistingHostHealth, error) {
	resp, err := client.Get(url)
	if err != nil {
		return gsc5ExistingHostHealth{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return gsc5ExistingHostHealth{}, fmt.Errorf("health status %d", resp.StatusCode)
	}
	var h gsc5ExistingHostHealth
	if err := json.NewDecoder(io.LimitReader(resp.Body, 32768)).Decode(&h); err != nil {
		return gsc5ExistingHostHealth{}, err
	}
	return h, nil
}

func gsc5GuardExistingHostBeforeInstall(role int, dataDir string) error {
	if !hasServerRole(role) {
		return nil
	}
	stored, err := gsc5ReadStoredRoleVersion(dataDir)
	if err != nil {
		return errors.New("cannot verify preserved GSC Host role state; upgrade blocked")
	}
	if isGSC452CanaryVersion(stored) {
		return gsc5MigrationDecision(role, stored, gsc5ExistingHostHealth{}, false)
	}
	client := &http.Client{Timeout: 1800 * time.Millisecond}
	health, err := gsc5ReadExistingHostHealth(client, gsc5MigrationHealthURL)
	return gsc5MigrationDecision(role, stored, health, err == nil)
}
