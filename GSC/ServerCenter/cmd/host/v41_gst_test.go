package main

import (
	"os"
	"path/filepath"
	"strconv"
	"testing"
	"time"
)

func TestReadGSTDiagnostics(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "server.properties"), []byte("server-port=25565\n"), 0644); err != nil {
		t.Fatal(err)
	}
	runtimeDir := filepath.Join(dir, "plugins", "GeumyiServerTools", "runtime")
	if err := os.MkdirAll(runtimeDir, 0755); err != nil {
		t.Fatal(err)
	}
	body := `{"schema":2,"plugin":"GeumyiServerTools","version":"1.1.0","time":` +
		fmtInt(time.Now().UnixMilli()) + `,"grade":"DEGRADED","lag_active":true,"incident_count":2,"performance":{"mspt":60.0},"counts":{"players":3}}`
	if err := os.WriteFile(filepath.Join(runtimeDir, "health-v2.json"), []byte(body), 0644); err != nil {
		t.Fatal(err)
	}
	g := readGSTDiagnostics(ServerConfig{ID: "wild", Path: dir, JavaPort: 25565})
	if !g.Available || !g.Installed {
		t.Fatalf("expected available+installed: %+v", g)
	}
	if g.Version != "1.1.0" || g.Grade != "DEGRADED" || !g.LagActive || g.IncidentCount != 2 {
		t.Fatalf("bad diagnostics: %+v", g)
	}
	if !gstDegraded(g) {
		t.Fatal("degraded health should degrade server view")
	}
}

func TestReadGSTDiagnosticsStale(t *testing.T) {
	dir := t.TempDir()
	_ = os.WriteFile(filepath.Join(dir, "server.properties"), []byte("server-port=25565\n"), 0644)
	runtimeDir := filepath.Join(dir, "plugins", "GeumyiServerTools", "runtime")
	_ = os.MkdirAll(runtimeDir, 0755)
	body := `{"schema":2,"plugin":"GeumyiServerTools","version":"1.1.0","time":` +
		fmtInt(time.Now().Add(-time.Minute).UnixMilli()) + `,"grade":"HEALTHY","lag_active":false,"incident_count":0}`
	_ = os.WriteFile(filepath.Join(runtimeDir, "health-v2.json"), []byte(body), 0644)
	g := readGSTDiagnostics(ServerConfig{ID: "wild", Path: dir, JavaPort: 25565})
	if !g.Stale || !gstDegraded(g) {
		t.Fatalf("expected stale degraded: %+v", g)
	}
}

func fmtInt(v int64) string {
	// Keep test dependency-free.
	return strconv.FormatInt(v, 10)
}
