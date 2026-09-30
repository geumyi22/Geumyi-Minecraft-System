package main

import (
	"net/http"
	"strings"
)

func loopbackOnly(fn http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !isLoopbackRemote(r.RemoteAddr) {
			http.Error(w, "loopback only", http.StatusForbidden)
			return
		}
		fn(w, r)
	}
}

func apiV4NetworkServerState(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", http.StatusMethodNotAllowed)
		return
	}
	id := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("id")))
	s, ok := serverByID(id)
	if !ok {
		http.Error(w, "unknown server", http.StatusBadRequest)
		return
	}

	st := getServerStatus(s)
	update := updateStatusFor(s.ID)
	phase := strings.ToLower(strings.TrimSpace(update.Phase))

	blockedUpdate := false
	switch phase {
	case "checking", "downloading", "pending_health", "health_check", "rolling_back", "rollback_failed", "blocked":
		blockedUpdate = true
	}

	allowed := st.Online &&
		currentOperation(s.ID) == "" &&
		activeControlJob(s.ID) == nil &&
		!st.Schedule.Active &&
		!blockedUpdate

	reason := ""
	if !st.Online {
		reason = "offline"
	} else if currentOperation(s.ID) != "" {
		reason = "maintenance"
	} else if activeControlJob(s.ID) != nil || st.Schedule.Active {
		reason = "lifecycle"
	} else if blockedUpdate {
		reason = "update_" + phase
	}

	writeJSON(w, map[string]any{
		"id":             s.ID,
		"role":           normalizeServerConfig(s).Role,
		"online":         st.Online,
		"state":          st.State,
		"move_allowed":   allowed,
		"blocked_reason": reason,
		"update_phase":   update.Phase,
	})
}
