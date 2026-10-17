package main

import (
	"net/http"
	"net/http/httptest"
	"runtime"
	"strings"
	"testing"
)

func TestVelocityControlPreflightBlocksEveryActionEvenWhenHealthy(t *testing.T) {
	info := sampleVelocityInventory()
	info.ProcessPairCensusConsistent = true
	info.UDPThreeUniqueChildOwners = true
	for i := range info.Proxies {
		x := &info.Proxies[i]
		x.TaskPresent, x.TaskMatchesBaseline = true, true
		x.TaskState = "Running"
		x.UDPOwnerMatchesVelocityChild = true
		x.JavaListening, x.BedrockListening = true, true
		x.PortOwnerConsistent = true
	}
	for _, target := range []string{"wild", "playground", "other"} {
		for _, action := range []string{"start", "stop", "restart"} {
			t.Run(target+"-"+action, func(t *testing.T) {
				for _, layerHealthy := range []bool{false, true} {
					p, err := buildVelocityControlPreflight(info, target, action, layerHealthy, layerHealthy)
					if err != nil {
						t.Fatal(err)
					}
					if p.SafeToExecute || !p.ReadOnly || p.Decision != "blocked" ||
						p.LiveClientE2EVerified || p.OperatorApprovalCaptured || len(p.Reasons) < 3 {
						t.Fatalf("Velocity control unlocked without a safe bridge: %+v", p)
					}
					if p.Observed.TaskProcessIdentityVerified {
						t.Fatal("socket owners were misrepresented as task-to-process identity proof")
					}
					joined := strings.Join(p.Reasons, ",")
					if !strings.Contains(joined, "operator_approval_not_collected") ||
						!strings.Contains(joined, "task_process_identity_unverified") {
						t.Fatalf("critical control blockers lost: %s", joined)
					}
					if action == "restart" && !strings.Contains(joined, "graceful_shutdown_control_unavailable") {
						t.Fatal("restart has no proven graceful shutdown")
					}
					if action == "start" && !strings.Contains(joined, "target_runtime_absence_unproven") {
						t.Fatal("start lacks an authoritative absence proof")
					}
				}
			})
		}
	}
}

func TestVelocityControlPreflightRejectsAmbiguousOrUnknownTargets(t *testing.T) {
	info := sampleVelocityInventory()
	for _, x := range [][2]string{
		{"all", "restart"}, {"wild; stop", "restart"},
		{"wild", "kill"}, {"", "start"}, {"wild", "force-stop"},
	} {
		if _, err := buildVelocityControlPreflight(info, x[0], x[1], true, true); err == nil {
			t.Fatalf("accepted target/action %q/%q", x[0], x[1])
		}
	}
	for _, method := range []string{http.MethodPost, http.MethodPut, http.MethodPatch, http.MethodDelete} {
		req := httptest.NewRequest(method, "/api/v4/velocity/preflight?id=wild&action=restart", strings.NewReader(`{"confirm":true}`))
		rec := httptest.NewRecorder()
		apiV4VelocityControlPreflight(rec, req)
		if rec.Code != http.StatusMethodNotAllowed {
			t.Fatalf("mutation %s returned %d (want 405)", method, rec.Code)
		}
	}
	req := httptest.NewRequest(http.MethodGet, "/api/v4/velocity/preflight?id=wild&action=force-stop", nil)
	rec := httptest.NewRecorder()
	apiV4VelocityControlPreflight(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("unknown action returned %d (want 400)", rec.Code)
	}
	if runtime.GOOS != "windows" {
		req := httptest.NewRequest(http.MethodGet, "/api/v4/velocity/preflight?id=wild&action=restart", nil)
		rec := httptest.NewRecorder()
		apiV4VelocityControlPreflight(rec, req)
		if rec.Code != http.StatusNotImplemented {
			t.Fatalf("non-Windows preflight returned %d (want 501)", rec.Code)
		}
	}
}

func TestVelocityControlPreflightStillBlocksWithActualTcpMissingSample(t *testing.T) {
	info := sampleVelocityInventory()
	info.ProcessPairCensusConsistent, info.UDPThreeUniqueChildOwners = true, true
	info.Proxies[0] = velocityProxyStatus{
		ID: "wild", TaskPresent: true, TaskMatchesBaseline: true, TaskState: "Running",
		JavaPort: 25565, BedrockPort: 19132, JavaListening: false, BedrockListening: true,
		UDPOwnerMatchesVelocityChild: true, Status: "tcp_inventory_missing_udp_child_verified",
	}
	for _, action := range []string{"start", "stop", "restart"} {
		result, err := buildVelocityControlPreflight(info, "wild", action, true, true)
		if err != nil {
			t.Fatal(err)
		}
		if result.SafeToExecute || result.Observed.TCPListenerTelemetryPresent ||
			!result.Observed.JavaTCPProbeResponding || !result.Observed.BedrockRaknetPong {
			t.Fatalf("TCP telemetry should not override observed Java/RakNet replies or unblock %q: %+v", action, result)
		}
	}
}
