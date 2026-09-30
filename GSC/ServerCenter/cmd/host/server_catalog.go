package main

import (
	"net/http"
	"strings"
)

const (
	serverRoleLobby      = "lobby"
	serverRoleWild       = "wild"
	serverRolePlayground = "playground"
	serverRoleOther      = "other"

	serverUpdateManaged = "managed"
	serverUpdateManual  = "manual"
	serverUpdateHold    = "hold"
)

func validServerRole(role string) bool {
	switch strings.ToLower(strings.TrimSpace(role)) {
	case serverRoleLobby, serverRoleWild, serverRolePlayground, serverRoleOther:
		return true
	default:
		return false
	}
}

func inferServerRole(id string) string {
	switch strings.ToLower(strings.TrimSpace(id)) {
	case "lobby":
		return serverRoleLobby
	case "wild":
		return serverRoleWild
	case "playground":
		return serverRolePlayground
	default:
		return serverRoleOther
	}
}

func normalizeServerUpdatePolicy(policy string) string {
	switch strings.ToLower(strings.TrimSpace(policy)) {
	case serverUpdateManual:
		return serverUpdateManual
	case serverUpdateHold:
		return serverUpdateHold
	default:
		return serverUpdateManaged
	}
}

func normalizeServerConfig(s ServerConfig) ServerConfig {
	s.ID = strings.ToLower(strings.TrimSpace(s.ID))
	s.Name = strings.TrimSpace(s.Name)
	role := strings.ToLower(strings.TrimSpace(s.Role))
	if !validServerRole(role) {
		role = inferServerRole(s.ID)
	}
	s.Role = role
	s.UpdatePolicy = normalizeServerUpdatePolicy(s.UpdatePolicy)
	return s
}

func normalizeServerCatalog(servers []ServerConfig) []ServerConfig {
	out := make([]ServerConfig, len(servers))
	for i, s := range servers {
		out[i] = normalizeServerConfig(s)
	}
	return out
}

func targetIncludesServer(targets []string, s ServerConfig) bool {
	s = normalizeServerConfig(s)
	for _, raw := range targets {
		t := strings.ToLower(strings.TrimSpace(raw))
		switch {
		case t == "*":
			return true
		case t == s.ID:
			return true
		case strings.HasPrefix(t, "role:") && strings.TrimSpace(strings.TrimPrefix(t, "role:")) == s.Role:
			return true
		}
	}
	return false
}

// targetIncludes remains for older tests/callers. New deployment code should
// use targetIncludesServer so role selectors such as role:lobby are available.
func targetIncludes(targets []string, id string) bool {
	return targetIncludesServer(targets, ServerConfig{ID: id})
}

type serverCatalogEntry struct {
	ID             string `json:"id"`
	Name           string `json:"name"`
	Role           string `json:"role"`
	UpdatePolicy   string `json:"update_policy"`
	JavaPort       int    `json:"java_port"`
	RCONPort       int    `json:"rcon_port"`
	BedrockPort    int    `json:"bedrock_port"`
	GDSAPIPort     int    `json:"gds_api_port"`
	AutoStart      bool   `json:"auto_start"`
	RestartOnCrash bool   `json:"restart_on_crash"`
}

func apiV4ServerCatalog(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", http.StatusMethodNotAllowed)
		return
	}
	c := configSnapshot()
	entries := make([]serverCatalogEntry, 0, len(c.Servers))
	for _, raw := range c.Servers {
		s := normalizeServerConfig(raw)
		entries = append(entries, serverCatalogEntry{
			ID: s.ID,
			Name: s.Name,
			Role: s.Role,
			UpdatePolicy: s.UpdatePolicy,
			JavaPort: s.JavaPort,
			RCONPort: s.RCONPort,
			BedrockPort: s.BedrockPort,
			GDSAPIPort: s.GDSAPIPort,
			AutoStart: s.AutoStart,
			RestartOnCrash: s.RestartOnCrash,
		})
	}
	writeJSON(w, map[string]any{
		"schema": 1,
		"roles": []string{serverRoleLobby, serverRoleWild, serverRolePlayground, serverRoleOther},
		"servers": entries,
	})
}
