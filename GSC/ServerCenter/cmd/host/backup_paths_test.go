package main

import "testing"

func TestDeclaredBackupScope(t *testing.T) {
	for _, m := range []BackupManifest{
		{Scope: "full", Roots: []string{"."}},
		{Scope: "config", Roots: []string{"server.properties", "plugins/GeumyiDiscordStatus"}},
		{Scope: "world", Roots: []string{"custom_world", "extra/world"}},
	} {
		if err := m.validateRoots(); err != nil {
			t.Fatal(m, err)
		}
	}
	m := BackupManifest{Scope: "config", Roots: []string{"config"}}
	if _, err := m.entryName("config/settings.yml"); err != nil {
		t.Fatal(err)
	}
	if _, err := m.entryName("logs/latest.log"); err == nil {
		t.Fatal("accepted file outside configuration snapshot")
	}
	for _, m := range []BackupManifest{
		{Scope: "config"}, {Scope: "world", Roots: []string{"."}},
		{Scope: "config", Roots: []string{"logs"}}, {Scope: "full", Roots: []string{"world"}},
	} {
		if err := m.validateRoots(); err == nil {
			t.Fatalf("accepted inconsistent manifest: %+v", m)
		}
	}
}
