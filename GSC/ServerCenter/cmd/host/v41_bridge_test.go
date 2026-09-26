package main

import (
	"encoding/json"
	"net"
	"net/http"
	"testing"
)

func TestControlViewIncludesGDSBridgeSnapshot(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	port := ln.Addr().(*net.TCPAddr).Port
	srv := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v4/status" {
			http.NotFound(w, r)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"protocol_version": 4,
			"plugin_version":   "1.1.0",
			"mode":             "ONLINE",
			"gst_diagnostics":  map[string]any{"available": true, "grade": "HEALTHY"},
		})
	})}
	go srv.Serve(ln)
	defer srv.Close()

	s := ServerConfig{ID: "test", Name: "Test", GDSAPIPort: port}
	st := ServerStatus{Online: true, GDSAPIOnline: true, State: "ONLINE"}
	v := controlServerViewFromStatus(s, st)
	if v.Bridge == nil {
		t.Fatal("bridge missing")
	}
	if got := v.Bridge["plugin_version"]; got != "1.1.0" {
		t.Fatalf("plugin version = %v", got)
	}
}
