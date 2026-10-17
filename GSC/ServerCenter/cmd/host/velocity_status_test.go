package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"runtime"
	"regexp"
	"strings"
	"testing"
)

func sampleVelocityInventory() velocityInventory {
	return velocityInventory{
		Schema: 1,
		ReadOnly: true,
		Proxies: []velocityProxyStatus{
			{ID: "wild", JavaPort: 25565, BedrockPort: 19132, Status: "ports_ready_owner_unverified"},
			{ID: "playground", JavaPort: 25566, BedrockPort: 19133, Status: "offline_or_starting"},
			{ID: "other", JavaPort: 25567, BedrockPort: 19134, Status: "task_config_drift"},
		},
	}
}

func TestVelocityInventoryRejectsMissingOrInventedTargets(t *testing.T) {
	valid := sampleVelocityInventory()
	cases := []struct {
		name string
		mutate func(*velocityInventory)
	}{
		{"not-read-only", func(p *velocityInventory) { p.ReadOnly = false }},
		{"missing-proxy", func(p *velocityInventory) { p.Proxies = p.Proxies[:2] }},
		{"duplicate-id", func(p *velocityInventory) { p.Proxies[1].ID = "wild" }},
		{"wrong-port", func(p *velocityInventory) { p.Proxies[0].BedrockPort = 19133 }},
		{"unexpected-state", func(p *velocityInventory) { p.Proxies[2].Status = "ONLINE" }},
		{"false-identity-proof", func(p *velocityInventory) { p.TaskProcessIdentityVerified = true }},
		{"false-game-e2e-proof", func(p *velocityInventory) { p.LiveJavaRaknetE2EVerified = true }},
		{"impossible-udp-pair", func(p *velocityInventory) { p.UDPThreeUniqueChildOwners = true }},
		{"unknown-schema", func(p *velocityInventory) { p.Schema = 2 }},
	}
	body, _ := json.Marshal(valid)
	if _, err := decodeVelocityInventory(body); err != nil {
		t.Fatalf("expected valid inventory: %v", err)
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			p := sampleVelocityInventory()
			c.mutate(&p)
			raw, _ := json.Marshal(p)
			if _, err := decodeVelocityInventory(raw); err == nil {
				t.Fatal("invalid Velocity inventory was accepted")
			}
		})
	}
	if _, err := decodeVelocityInventory([]byte("{bad")); err == nil {
		t.Fatal("bad JSON accepted")
	}
}


func TestVelocityInventoryOctober17TcpGapCanBeRepresentedWithoutClaimingE2E(t *testing.T) {
	// Redacted real-host 2026-10-17 sample: three tasks Running and matching;
	// three UDP owners are unique Velocity children; TCP provider returned no
	// rows. This is not proof that TCP is down.
	info := sampleVelocityInventory()
	info.ProcessPairCensusConsistent = true
	info.UDPThreeUniqueChildOwners = true
	for i := range info.Proxies {
		item := &info.Proxies[i]
		item.TaskPresent = true
		item.TaskMatchesBaseline = true
		item.TaskState = "Running"
		item.JavaListening = false
		item.BedrockListening = true
		item.PortOwnerConsistent = false
		item.UDPOwnerMatchesVelocityChild = true
		item.Status = "tcp_inventory_missing_udp_child_verified"
	}
	body, err := json.Marshal(info)
	if err != nil {
		t.Fatal(err)
	}
	got, err := decodeVelocityInventory(body)
	if err != nil {
		t.Fatalf("historical TCP-telemetry-gap inventory rejected: %v", err)
	}
	if got.TaskProcessIdentityVerified || got.LiveJavaRaknetE2EVerified {
		t.Fatal("telemetry gap fabricated process identity or real client E2E")
	}
	for _, mutation := range []struct {
		name string
		mutate func(*velocityInventory)
	}{
		{"no-child-proof", func(v *velocityInventory) { v.Proxies[0].UDPOwnerMatchesVelocityChild = false }},
		{"no-census", func(v *velocityInventory) { v.UDPThreeUniqueChildOwners = false }},
		{"unexpected-TCP", func(v *velocityInventory) { v.Proxies[0].JavaListening = true }},
		{"no-UDP", func(v *velocityInventory) { v.Proxies[0].BedrockListening = false }},
		{"task-drift", func(v *velocityInventory) { v.Proxies[0].TaskMatchesBaseline = false }},
		{"task-stopped", func(v *velocityInventory) { v.Proxies[0].TaskState = "Ready" }},
	} {
		t.Run(mutation.name, func(t *testing.T) {
			modified := got
			modified.Proxies = append([]velocityProxyStatus(nil), got.Proxies...)
			mutation.mutate(&modified)
			raw, _ := json.Marshal(modified)
			if _, err := decodeVelocityInventory(raw); err == nil {
				t.Fatal("inconsistent TCP-gap evidence was accepted")
			}
		})
	}
}

func TestVelocityStatusEndpointIsGETOnlyAndDoesNotOfferProcessActions(t *testing.T) {
	for _, method := range []string{http.MethodPost, http.MethodPut, http.MethodDelete} {
		req := httptest.NewRequest(method, "/api/v4/velocity/status", strings.NewReader(`{"action":"restart"}`))
		rec := httptest.NewRecorder()
		apiV4VelocityStatus(rec, req)
		if rec.Code != http.StatusMethodNotAllowed {
			t.Fatalf("%s: got %d, want 405", method, rec.Code)
		}
	}
	if runtime.GOOS != "windows" {
		req := httptest.NewRequest(http.MethodGet, "/api/v4/velocity/status", nil)
		rec := httptest.NewRecorder()
		apiV4VelocityStatus(rec, req)
		if rec.Code != http.StatusNotImplemented {
			t.Fatalf("non-Windows read = %d, want 501", rec.Code)
		}
	}
}

func TestVelocityInventoryPowerShellSourceIsStrictlyReadOnly(t *testing.T) {
	// This guards against accidentally turning a diagnostics endpoint into
	// a task/process control endpoint during later feature development.
	forbidden := regexp.MustCompile(`(?i)\b(?:Stop-Process|Start-Process|Stop-ScheduledTask|Start-ScheduledTask|Set-ScheduledTask|Register-ScheduledTask|Unregister-ScheduledTask|Remove-ScheduledTask|Set-NetFirewallRule|New-NetFirewallRule|Remove-NetFirewallRule|Set-Content|Out-File|Remove-Item|Invoke-Expression)\b`)
	if hit := forbidden.FindString(velocityStatusPS); hit != "" {
		t.Fatalf("Velocity status script contains a mutating operation: %q", hit)
	}
	for _, marker := range []string{
		"Get-CimInstance Win32_Process",
		"socket_inventory_missing",
		"task_process_identity_verified=$false",
		"live_java_raknet_e2e_verified=$false",
	} {
		if !strings.Contains(velocityStatusPS, marker) {
			t.Fatalf("Velocity status guard marker is missing: %q", marker)
		}
	}
}
