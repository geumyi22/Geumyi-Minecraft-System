//go:build windows

package main

import (
	"strings"
	"testing"
)

func TestVelocityControlPreviewUIOnlyRequestsReadOnlyPreflight(t *testing.T) {
	for _, marker := range []string{
		"async function checkVelocityControl(id,action)",
		"/api/v4/velocity/preflight?id=",
		"result.safe_to_execute!==false",
		"result.decision!=='blocked'",
		"result.target!==id || result.action!==action",
		"시작 사전점검",
		"중지 사전점검",
		"재시작 사전점검",
	} {
		if !strings.Contains(dashboardHTML, marker) {
			t.Errorf("read-only Velocity dashboard marker missing: %q", marker)
		}
	}
	// This client surface must not advertise a mutating Velocity endpoint.
	for _, dangerous := range []string{
		"/api/v4/velocity/start",
		"/api/v4/velocity/stop",
		"/api/v4/velocity/restart",
		"velocity/control',{method:'POST'",
	} {
		if strings.Contains(dashboardHTML, dangerous) {
			t.Errorf("unexpected live Velocity control in dashboard: %q", dangerous)
		}
	}
}
