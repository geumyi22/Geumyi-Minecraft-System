package main

import (
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// GSTDiagnostics is the normalized GeumyiServerTools diagnostics view exposed to
// Control API v1 / WebSocket consumers such as GSCM.
type GSTDiagnostics struct {
	Available     bool           `json:"available"`
	Installed     bool           `json:"installed"`
	Stale         bool           `json:"stale"`
	Schema        int            `json:"schema,omitempty"`
	Plugin        string         `json:"plugin,omitempty"`
	Version       string         `json:"version,omitempty"`
	Time          int64          `json:"time,omitempty"`
	Grade         string         `json:"grade,omitempty"`
	LagActive     bool           `json:"lag_active"`
	IncidentCount int64          `json:"incident_count"`
	Performance   map[string]any `json:"performance,omitempty"`
	Counts        map[string]any `json:"counts,omitempty"`
	LastIncident  map[string]any `json:"last_incident,omitempty"`
	AgeSeconds    float64        `json:"age_seconds,omitempty"`
	Error         string         `json:"error,omitempty"`
}

type gstHealthFile struct {
	Schema        int            `json:"schema"`
	Plugin        string         `json:"plugin"`
	Version       string         `json:"version"`
	Time          int64          `json:"time"`
	Grade         string         `json:"grade"`
	LagActive     bool           `json:"lag_active"`
	IncidentCount int64          `json:"incident_count"`
	Performance   map[string]any `json:"performance"`
	Counts        map[string]any `json:"counts"`
	LastIncident  map[string]any `json:"last_incident"`
}

func gstInstalled(dir string) bool {
	if dir == "" {
		return false
	}
	if st, err := os.Stat(filepath.Join(dir, "plugins", "GeumyiServerTools")); err == nil && st.IsDir() {
		return true
	}
	matches, _ := filepath.Glob(filepath.Join(dir, "plugins", "GeumyiServerTools*.jar"))
	return len(matches) > 0
}

func readGSTDiagnostics(s ServerConfig) GSTDiagnostics {
	dir := resolveServerDir(s)
	out := GSTDiagnostics{Installed: gstInstalled(dir)}
	if dir == "" {
		out.Error = "server directory unavailable"
		return out
	}
	p := filepath.Join(dir, "plugins", "GeumyiServerTools", "runtime", "health-v2.json")
	f, err := os.Open(p)
	if err != nil {
		if !os.IsNotExist(err) {
			out.Error = err.Error()
		}
		return out
	}
	defer f.Close()
	var raw gstHealthFile
	dec := json.NewDecoder(io.LimitReader(f, 1<<20))
	if err := dec.Decode(&raw); err != nil {
		out.Error = "invalid diagnostics JSON: " + err.Error()
		return out
	}
	out.Available = true
	out.Schema = raw.Schema
	out.Plugin = raw.Plugin
	out.Version = raw.Version
	out.Time = raw.Time
	out.Grade = strings.ToUpper(strings.TrimSpace(raw.Grade))
	out.LagActive = raw.LagActive
	out.IncidentCount = raw.IncidentCount
	out.Performance = raw.Performance
	out.Counts = raw.Counts
	out.LastIncident = raw.LastIncident
	if raw.Time > 0 {
		age := time.Since(time.UnixMilli(raw.Time)).Seconds()
		if age < 0 {
			age = 0
		}
		out.AgeSeconds = age
		out.Stale = age > 30
	}
	return out
}

func gstDegraded(g GSTDiagnostics) bool {
	if !g.Available {
		return false
	}
	return g.Stale || g.Grade == "DEGRADED" || g.Grade == "CRITICAL"
}
