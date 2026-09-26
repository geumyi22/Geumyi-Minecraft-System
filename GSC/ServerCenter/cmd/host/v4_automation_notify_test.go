package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAutomationDiscordNotificationUsesAgentEventsChannel(t *testing.T) {
	work := t.TempDir()
	props := "discord.bot_token=test-token\ndiscord.events_channel_id=123456789012345678\n"
	if err := os.WriteFile(filepath.Join(work, "agent.properties"), []byte(props), 0600); err != nil {
		t.Fatal(err)
	}

	configMu.Lock()
	oldCfg := cfg
	cfg.Agent.WorkingDir = work
	configMu.Unlock()
	defer func() { configMu.Lock(); cfg = oldCfg; configMu.Unlock() }()

	var auth, path, payload string
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth = r.Header.Get("Authorization")
		path = r.URL.Path
		b, _ := io.ReadAll(r.Body)
		payload = string(b)
		w.WriteHeader(http.StatusNoContent)
	}))
	defer ts.Close()

	oldBase := automationDiscordAPIBase
	automationDiscordAPIBase = ts.URL
	defer func() { automationDiscordAPIBase = oldBase }()

	err := sendAutomationDiscordNow(ServerConfig{ID: "wild", Name: "금이 야생"}, V4Automation{Name: "새벽 백업", Action: "backup"}, "백업 완료")
	if err != nil {
		t.Fatal(err)
	}
	if auth != "Bot test-token" {
		t.Fatalf("bad auth header: %q", auth)
	}
	if path != "/channels/123456789012345678/messages" {
		t.Fatalf("bad Discord path: %q", path)
	}
	if !strings.Contains(payload, "GSC 자동화") || !strings.Contains(payload, "새벽 백업") || !strings.Contains(payload, "백업 완료") {
		t.Fatalf("notification payload missing expected text: %s", payload)
	}
}
