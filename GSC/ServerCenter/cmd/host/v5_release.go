package main

import "net/http"

// Read-only and authenticated. Product v5 intentionally keeps the v4
// management API for existing GSCM clients. The legacy Velocity owner fields
// describe the three original Scheduler proxies and retain their v5 contract.
// Separately registered, new GSC-owned Velocity instances are supported without
// adopting those original tasks; each instance reports its management_mode.
func apiV5ReleaseInfo(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, map[string]any{
		"ok": true, "product": "Geumyi Server Center", "version": appVersion,
		"channel": "stable", "api_compatible_major": 4, "product_major": 5,
		"gscm_version_unchanged":                  true,
		"velocity_lifecycle_owner":                "windows_task_scheduler",
		"gsc_owns_velocity_processes":             false,
		"velocity_lifecycle_scope":                "legacy_three_scheduled_proxies",
		"legacy_velocity_lifecycle_owner":         "windows_task_scheduler",
		"new_velocity_gsc_management_supported":   true,
		"automatic_stable_promotion":              false,
		"stable_release_requires_manual_operator": true,
	})
}
