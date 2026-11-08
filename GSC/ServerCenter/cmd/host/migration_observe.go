package main

import (
	"net/http"
	"os"
)

// Observation is an explicit service-start option, never a persisted setting or
// an API toggle. Removing it requires an operator-controlled Host restart.
func migrationObserveRequested() bool {
	for _, arg := range os.Args[1:] {
		if arg == "--migration-observe" {
			return true
		}
	}
	return false
}

// Keep diagnostics available without replaying old jobs, schedules or automatic
// configuration reconciliation. In particular initV41Runtime loads and rewrites
// interrupted jobs, so it must not run in observation mode either.
func initializeHostRuntime(observe bool) {
	initRuntimeState()
	if observe {
		startStatusTelemetry()
		return
	}
	initV4Runtime()
	initV41Runtime()
	syncMobileFirewall(configSnapshot().MobileEnabled)
	restoreLifecycleSchedules()
	changedBridges, _ := reconcileLocalCompanionConfigs()
	startStatusTelemetry()
	go startupSupervisor()
	go reloadReconciledGDS(changedBridges)
	go v4MetricsLoop()
	go v4AutomationLoop()
}

// This outer gate also covers unauthenticated/loopback and future API routes.
// WebSocket is explicitly denied: an upgraded connection must not provide a
// second command transport while the HTTP mutation routes are disabled.
func migrationObservationGuard(observe bool, next http.Handler) http.Handler {
	if !observe {
		return next
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if (r.Method != http.MethodGet && r.Method != http.MethodHead) || r.URL.Path == "/api/v1/ws" {
			writeJSONStatus(w, http.StatusLocked, map[string]any{
				"ok":                false,
				"error":             "migration_observe_read_only",
				"message":           "마이그레이션 확인 모드입니다. 상태 조회만 가능하며, 변경 작업은 운영자가 확인 모드를 해제한 뒤 사용할 수 있습니다.",
				"migration_observe": true,
			})
			return
		}
		next.ServeHTTP(w, r)
	})
}

func hostHealthPayload(observe bool) map[string]any {
	health := map[string]any{
		"ok": true, "version": appVersion, "service": serviceModeRequested(),
		"generation": 4,
	}
	if observe {
		health["migration_observe"] = true
	}
	return health
}
