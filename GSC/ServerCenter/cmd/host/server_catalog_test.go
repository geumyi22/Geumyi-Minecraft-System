package main

import (
	"encoding/json"
	"net/http/httptest"
	"testing"
)

func TestDay10LegacyServerRolesNormalizeWithoutConfigBreakage(t *testing.T) {
	servers := normalizeServerCatalog([]ServerConfig{
		{ID: "wild", Name: "금이 야생"},
		{ID: "playground", Name: "금이 놀이터"},
		{ID: "lobby", Name: "금이 로비"},
		{ID: "event-1", Name: "이벤트"},
	})
	if got := servers[0].Role; got != serverRoleWild {
		t.Fatalf("wild legacy role=%q", got)
	}
	if got := servers[1].Role; got != serverRolePlayground {
		t.Fatalf("playground legacy role=%q", got)
	}
	if got := servers[2].Role; got != serverRoleLobby {
		t.Fatalf("lobby inferred role=%q", got)
	}
	if got := servers[3].Role; got != serverRoleOther {
		t.Fatalf("other inferred role=%q", got)
	}
	for _, s := range servers {
		if s.UpdatePolicy != serverUpdateManaged {
			t.Fatalf("%s update policy=%q want managed", s.ID, s.UpdatePolicy)
		}
	}
}

func TestDay10RoleAwareDeploymentTargeting(t *testing.T) {
	lobby := ServerConfig{ID: "hub-1", Role: serverRoleLobby}
	wild := ServerConfig{ID: "wild", Role: serverRoleWild}
	playground := ServerConfig{ID: "playground", Role: serverRolePlayground}

	if !targetIncludesServer([]string{"role:lobby"}, lobby) {
		t.Fatal("role:lobby must target a lobby-role server even when ID is not lobby")
	}
	if targetIncludesServer([]string{"role:lobby"}, wild) {
		t.Fatal("role:lobby must not target wild")
	}
	if !targetIncludesServer([]string{"wild"}, wild) {
		t.Fatal("legacy ID target wild must keep working")
	}
	if targetIncludesServer([]string{"wild"}, playground) {
		t.Fatal("Wild-only target leaked into Playground")
	}
	if !targetIncludesServer([]string{"*"}, playground) {
		t.Fatal("wildcard target must keep working")
	}
}

func TestDay10ServerCatalogAPIExposesRoles(t *testing.T) {
	configMu.Lock()
	oldCfg := cfg
	cfg = Config{
		Servers: []ServerConfig{
			{ID: "wild", Name: "금이 야생"},
			{ID: "playground", Name: "금이 놀이터"},
			{ID: "hub-main", Name: "금이 로비", Role: serverRoleLobby, UpdatePolicy: serverUpdateManual},
		},
	}
	configMu.Unlock()
	defer func() {
		configMu.Lock()
		cfg = oldCfg
		configMu.Unlock()
	}()

	w := httptest.NewRecorder()
	r := httptest.NewRequest("GET", "/api/v4/server-catalog", nil)
	apiV4ServerCatalog(w, r)
	if w.Code != 200 {
		t.Fatalf("catalog API failed: %d %s", w.Code, w.Body.String())
	}

	var body struct {
		Schema int `json:"schema"`
		Roles []string `json:"roles"`
		Servers []struct {
			ID string `json:"id"`
			Role string `json:"role"`
			UpdatePolicy string `json:"update_policy"`
		} `json:"servers"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Schema != 1 || len(body.Servers) != 3 {
		t.Fatalf("unexpected catalog response: %+v", body)
	}
	got := map[string]struct{ role, policy string }{}
	for _, s := range body.Servers {
		got[s.ID] = struct{ role, policy string }{s.Role, s.UpdatePolicy}
	}
	if got["wild"].role != serverRoleWild || got["wild"].policy != serverUpdateManaged {
		t.Fatalf("legacy Wild catalog normalization failed: %+v", got["wild"])
	}
	if got["playground"].role != serverRolePlayground {
		t.Fatalf("legacy Playground role failed: %+v", got["playground"])
	}
	if got["hub-main"].role != serverRoleLobby || got["hub-main"].policy != serverUpdateManual {
		t.Fatalf("explicit Lobby role/policy lost: %+v", got["hub-main"])
	}
}
