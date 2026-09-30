package main

import (
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
)

func TestDay10PlayerLocationStoreKeepsServersSeparate(t *testing.T) {
	root := t.TempDir()

	configMu.Lock()
	oldCfg := cfg
	oldPath := configPath
	cfg = Config{
		Servers: []ServerConfig{
			{ID: "wild", Role: serverRoleWild},
			{ID: "playground", Role: serverRolePlayground},
			{ID: "lobby", Role: serverRoleLobby},
		},
	}
	configPath = filepath.Join(root, "server.json")
	configMu.Unlock()
	defer func() {
		configMu.Lock()
		cfg = oldCfg
		configPath = oldPath
		configMu.Unlock()
	}()

	uuid := "123e4567-e89b-12d3-a456-426614174000"
	if err := savePlayerLocation(playerLocationRecord{
		UUID: uuid, ServerID: "wild", World: "world_nether",
		X: 100.25, Y: 64.0, Z: -200.75, Yaw: 90, Pitch: 10,
	}); err != nil {
		t.Fatal(err)
	}
	if err := savePlayerLocation(playerLocationRecord{
		UUID: uuid, ServerID: "playground", World: "world",
		X: 1.5, Y: 70.0, Z: 2.5,
	}); err != nil {
		t.Fatal(err)
	}

	wild, ok, err := loadPlayerLocation(uuid, "wild")
	if err != nil || !ok {
		t.Fatalf("wild location unavailable: ok=%v err=%v", ok, err)
	}
	if wild.World != "world_nether" || wild.X != 100.25 || wild.Z != -200.75 {
		t.Fatalf("wild location changed: %+v", wild)
	}

	play, ok, err := loadPlayerLocation(uuid, "playground")
	if err != nil || !ok {
		t.Fatalf("playground location unavailable: ok=%v err=%v", ok, err)
	}
	if play.World != "world" || play.X != 1.5 || play.Z != 2.5 {
		t.Fatalf("playground location changed: %+v", play)
	}

	if err := savePlayerLocation(playerLocationRecord{
		UUID: uuid, ServerID: "lobby", World: "world", X: 0.5, Y: 81, Z: 0.5,
	}); err == nil {
		t.Fatal("Lobby location must not be persisted")
	}
}

func TestDay10PlayerLocationAPIGetPost(t *testing.T) {
	root := t.TempDir()

	configMu.Lock()
	oldCfg := cfg
	oldPath := configPath
	cfg = Config{Servers: []ServerConfig{{ID: "wild", Role: serverRoleWild}}}
	configPath = filepath.Join(root, "server.json")
	configMu.Unlock()
	defer func() {
		configMu.Lock()
		cfg = oldCfg
		configPath = oldPath
		configMu.Unlock()
	}()

	body := `{"uuid":"123e4567-e89b-12d3-a456-426614174000","server_id":"wild","world":"world_the_end","x":5.5,"y":80,"z":-6.5,"yaw":45,"pitch":-10}`
	pw := httptest.NewRecorder()
	pr := httptest.NewRequest("POST", "/api/v4/player-location", strings.NewReader(body))
	apiV4PlayerLocation(pw, pr)
	if pw.Code != 200 {
		t.Fatalf("POST failed: %d %s", pw.Code, pw.Body.String())
	}

	gw := httptest.NewRecorder()
	gr := httptest.NewRequest("GET", "/api/v4/player-location?uuid=123e4567-e89b-12d3-a456-426614174000&server_id=wild", nil)
	apiV4PlayerLocation(gw, gr)
	if gw.Code != 200 {
		t.Fatalf("GET failed: %d %s", gw.Code, gw.Body.String())
	}
	for _, want := range []string{`"server_id":"wild"`, `"world":"world_the_end"`, `"x":5.5`} {
		if !strings.Contains(gw.Body.String(), want) {
			t.Fatalf("GET body missing %s: %s", want, gw.Body.String())
		}
	}
}
