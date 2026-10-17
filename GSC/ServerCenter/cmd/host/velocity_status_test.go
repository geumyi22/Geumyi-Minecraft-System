package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"runtime"
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
