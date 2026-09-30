package main

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
)

type playerLocationRecord struct {
	UUID     string  `json:"uuid"`
	ServerID string  `json:"server_id"`
	World    string  `json:"world"`
	X        float64 `json:"x"`
	Y        float64 `json:"y"`
	Z        float64 `json:"z"`
	Yaw      float64 `json:"yaw"`
	Pitch    float64 `json:"pitch"`
	SavedAt  string  `json:"saved_at"`
}

type playerLocationStore struct {
	Schema  int                                      `json:"schema"`
	Players map[string]map[string]playerLocationRecord `json:"players"`
}

var (
	playerLocationMu sync.Mutex
	playerUUIDRE = regexp.MustCompile(`(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)
)

func playerLocationPath() (string, error) {
	if strings.TrimSpace(configPath) == "" {
		return "", errors.New("GSC config path unavailable")
	}
	return filepath.Join(filepath.Dir(configPath), "player-locations.json"), nil
}

func readPlayerLocationStore(path string) (playerLocationStore, error) {
	store := playerLocationStore{Schema: 1, Players: map[string]map[string]playerLocationRecord{}}
	b, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return store, nil
		}
		return store, err
	}
	if err := json.Unmarshal(b, &store); err != nil {
		return store, err
	}
	if store.Schema != 1 {
		return store, errors.New("unsupported player location schema")
	}
	if store.Players == nil {
		store.Players = map[string]map[string]playerLocationRecord{}
	}
	return store, nil
}

func normalizePlayerLocationRecord(rec playerLocationRecord) (playerLocationRecord, error) {
	rec.UUID = strings.ToLower(strings.TrimSpace(rec.UUID))
	rec.ServerID = strings.ToLower(strings.TrimSpace(rec.ServerID))
	rec.World = strings.TrimSpace(rec.World)
	if !playerUUIDRE.MatchString(rec.UUID) {
		return rec, errors.New("invalid uuid")
	}
	if rec.ServerID == "" || rec.World == "" {
		return rec, errors.New("server_id and world are required")
	}
	server, ok := serverByID(rec.ServerID)
	if !ok {
		return rec, errors.New("unknown server")
	}
	server = normalizeServerConfig(server)
	if server.Role == serverRoleLobby {
		return rec, errors.New("Lobby location is intentionally not persisted")
	}
	rec.SavedAt = time.Now().Format(time.RFC3339Nano)
	return rec, nil
}

func savePlayerLocation(rec playerLocationRecord) error {
	var err error
	rec, err = normalizePlayerLocationRecord(rec)
	if err != nil {
		return err
	}
	path, err := playerLocationPath()
	if err != nil {
		return err
	}

	playerLocationMu.Lock()
	defer playerLocationMu.Unlock()

	store, err := readPlayerLocationStore(path)
	if err != nil {
		return err
	}
	if store.Players[rec.UUID] == nil {
		store.Players[rec.UUID] = map[string]playerLocationRecord{}
	}
	store.Players[rec.UUID][rec.ServerID] = rec
	return day9WriteJSONAtomic(path, store)
}

func loadPlayerLocation(uuid, serverID string) (playerLocationRecord, bool, error) {
	uuid = strings.ToLower(strings.TrimSpace(uuid))
	serverID = strings.ToLower(strings.TrimSpace(serverID))
	if !playerUUIDRE.MatchString(uuid) || serverID == "" {
		return playerLocationRecord{}, false, errors.New("invalid uuid/server_id")
	}
	path, err := playerLocationPath()
	if err != nil {
		return playerLocationRecord{}, false, err
	}

	playerLocationMu.Lock()
	defer playerLocationMu.Unlock()

	store, err := readPlayerLocationStore(path)
	if err != nil {
		return playerLocationRecord{}, false, err
	}
	servers := store.Players[uuid]
	if servers == nil {
		return playerLocationRecord{}, false, nil
	}
	rec, ok := servers[serverID]
	return rec, ok, nil
}

func apiV4PlayerLocation(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		rec, ok, err := loadPlayerLocation(r.URL.Query().Get("uuid"), r.URL.Query().Get("server_id"))
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if !ok {
			http.Error(w, "location not found", http.StatusNotFound)
			return
		}
		writeJSON(w, rec)
	case http.MethodPost:
		var rec playerLocationRecord
		if json.NewDecoder(io.LimitReader(r.Body, 64<<10)).Decode(&rec) != nil {
			http.Error(w, "bad json", http.StatusBadRequest)
			return
		}
		if err := savePlayerLocation(rec); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, map[string]any{"ok": true})
	default:
		http.Error(w, "GET or POST required", http.StatusMethodNotAllowed)
	}
}
