package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestEnsureAgentBridgeSecretReplacesPlaceholder(t *testing.T) {
	d := t.TempDir()
	p := filepath.Join(d, "agent.properties")
	body := "secret=CHANGE_THIS_SAME_SECRET\nstate_api_secret=CHANGE_THIS_SAME_SECRET\nallow_loopback_ingest_without_matching_secret=true\ndiscord.bot_token=KEEP_ME\n"
	if err := os.WriteFile(p, []byte(body), 0600); err != nil {
		t.Fatal(err)
	}
	secret, changed, err := ensureAgentBridgeSecret(p)
	if err != nil {
		t.Fatal(err)
	}
	if !changed || weakBridgeSecret(secret) {
		t.Fatalf("expected strong generated secret, changed=%v secret=%q", changed, secret)
	}
	b, _ := os.ReadFile(p)
	s := string(b)
	if !strings.Contains(s, "secret="+secret) || !strings.Contains(s, "state_api_secret="+secret) {
		t.Fatalf("generated secret not persisted consistently: %s", s)
	}
	if !strings.Contains(s, "allow_loopback_ingest_without_matching_secret=false") {
		t.Fatalf("loopback bypass was not disabled: %s", s)
	}
	if !strings.Contains(s, "discord.bot_token=KEEP_ME") {
		t.Fatalf("unrelated property was modified: %s", s)
	}
}

func TestPatchGDSConfigPreservesOtherSettings(t *testing.T) {
	d := t.TempDir()
	p := filepath.Join(d, "plugins", "GeumyiDiscordStatus", "config.yml")
	if err := os.MkdirAll(filepath.Dir(p), 0755); err != nil {
		t.Fatal(err)
	}
	old := `server:
  id: "survival"
  name: "old"
agent:
  enabled: true
  url: "http://127.0.0.1:8877/ingest"
  secret: "old-secret"
api:
  enabled: true
  bind: "127.0.0.1"
  port: 8766
events:
  join: true
`
	if err := os.WriteFile(p, []byte(old), 0644); err != nil {
		t.Fatal(err)
	}
	changed, err := patchGDSConfig(p, []yamlScalar{
		{section: "server", key: "id", value: yamlQuote("playground")},
		{section: "server", key: "name", value: yamlQuote("금이 놀이터")},
		{section: "agent", key: "secret", value: yamlQuote("new-secret-abcdefghijklmnopqrstuvwxyz")},
		{section: "api", key: "port", value: "8765"},
	})
	if err != nil || !changed {
		t.Fatalf("patch failed changed=%v err=%v", changed, err)
	}
	b, _ := os.ReadFile(p)
	s := string(b)
	for _, want := range []string{`id: "playground"`, `name: "금이 놀이터"`, `port: 8765`, `events:`, `join: true`} {
		if !strings.Contains(s, want) {
			t.Fatalf("missing %q in:\n%s", want, s)
		}
	}
}

func TestAgentServerIDMapping(t *testing.T) {
	if got := agentServerID(ServerConfig{ID: "wild"}); got != "survival" {
		t.Fatalf("wild mapping = %q", got)
	}
	if got := agentServerID(ServerConfig{ID: "playground"}); got != "playground" {
		t.Fatalf("playground mapping = %q", got)
	}
}

func TestSyncAgentServerCatalogIncludesCustomServer(t *testing.T) {
	d := t.TempDir()
	p := filepath.Join(d, "agent.properties")
	body := "servers=playground,survival\nserver.playground.name=금이 놀이터\nserver.survival.name=금이 야생\ndiscord.bot_token=KEEP_ME\n"
	if err := os.WriteFile(p, []byte(body), 0600); err != nil {
		t.Fatal(err)
	}
	changed, err := syncAgentServerCatalog(p, []ServerConfig{
		{ID: "wild", Name: "금이 야생", JavaPort: 25565, GDSAPIPort: 8766},
		{ID: "playground", Name: "금이 놀이터", JavaPort: 25566, GDSAPIPort: 8765},
		{ID: "other", Name: "금이 기타 서버", JavaPort: 25567, GDSAPIPort: 8767},
	})
	if err != nil || !changed {
		t.Fatalf("sync failed changed=%v err=%v", changed, err)
	}
	b, _ := os.ReadFile(p)
	s := string(b)
	for _, want := range []string{
		"servers=survival,playground,other",
		"server.other.name=금이 기타 서버",
		"server.other.host=127.0.0.1",
		"server.other.java_port=25567",
		"server.other.gds_api_port=8767",
		"gsc.server_id.other=other",
		"gsc.server_id.survival=wild",
		"discord.bot_token=KEEP_ME",
	} {
		if !strings.Contains(s, want) {
			t.Fatalf("missing %q in:\n%s", want, s)
		}
	}
}
