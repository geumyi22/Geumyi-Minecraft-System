package main

import "net/http"

// Read-only and authenticated. Product v5 intentionally keeps the v4
// management API for existing GSCM clients. Velocity process ownership stays
// with the original Windows Task Scheduler, not the abandoned GSC experiment.
func apiV5ReleaseInfo(w http.ResponseWriter, r *http.Request) {
 if r.Method != http.MethodGet {
  http.Error(w,"GET required",http.StatusMethodNotAllowed)
  return
 }
 w.Header().Set("Cache-Control","no-store")
 writeJSON(w,map[string]any{
  "ok":true,"product":"Geumyi Server Center","version":appVersion,
  "channel":"beta","api_compatible_major":4,"product_major":5,
  "gscm_version_unchanged":true,
  "velocity_lifecycle_owner":"windows_task_scheduler",
  "gsc_owns_velocity_processes":false,
  "automatic_stable_promotion":false,
  "stable_release_requires_manual_operator":true,
 })
}
