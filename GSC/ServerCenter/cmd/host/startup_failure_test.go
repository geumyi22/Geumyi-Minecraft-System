package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestClassifyDatapackStartupFailure(t *testing.T) {
	f := classifyStartupFailure("[WARN]: Failed to load datapacks, can't proceed with server load. You can either fix your datapacks or reset to vanilla with --safeMode")
	if f == nil || f.Code != "datapack-load" {
		t.Fatalf("datapack failure not detected: %#v", f)
	}
}

func TestClassifyJavaStartupFailure(t *testing.T) {
	f := classifyStartupFailure("Error: LinkageError occurred while loading main class io.papermc.paperclip.Paperclip\njava.lang.UnsupportedClassVersionError: newer class file version")
	if f == nil || f.Code != "java-version" {
		t.Fatalf("java version failure not detected: %#v", f)
	}
}

func TestStartupCursorIgnoresOldLogAndDetectsNewAppend(t *testing.T) {
	dir := t.TempDir()
	oldConfigPath := configPath
	oldCfg := configSnapshot()
	defer func() { configPath = oldConfigPath; configMu.Lock(); cfg = oldCfg; configMu.Unlock() }()
	configPath = filepath.Join(dir, "server.json")
	sdir := filepath.Join(dir, "server")
	if err := os.MkdirAll(filepath.Join(sdir, "logs"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(sdir, "server.properties"), []byte("server-port=25565\n"), 0644); err != nil {
		t.Fatal(err)
	}
	configMu.Lock()
	cfg.Servers = []ServerConfig{{ID: "test", Path: sdir, JavaPort: 25565}}
	configMu.Unlock()
	latest := filepath.Join(sdir, "logs", "latest.log")
	if err := os.WriteFile(latest, []byte("old: Failed to load datapacks, can't proceed with server load\n"), 0644); err != nil {
		t.Fatal(err)
	}
	c := newStartupLogCursor(ServerConfig{ID: "test", Path: sdir, JavaPort: 25565})
	if f := c.detect(); f != nil {
		t.Fatalf("old failure must be ignored: %#v", f)
	}
	f, err := os.OpenFile(latest, os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		t.Fatal(err)
	}
	_, _ = f.WriteString("[WARN] Failed to load registries due to errors\n")
	_ = f.Close()
	got := c.detect()
	if got == nil || got.Code != "registry-load" {
		t.Fatalf("new failure not detected: %#v", got)
	}
}

func TestStartupCursorDetectsSplitFatalLine(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "launcher.log")
	if err := os.WriteFile(path, nil, 0644); err != nil {
		t.Fatal(err)
	}
	c := &startupLogCursor{offsets: map[string]int64{path: 0}, tails: map[string]string{}}
	f, _ := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0644)
	_, _ = f.WriteString("Failed to load datapacks, can't pro")
	_ = f.Close()
	if got := c.detect(); got != nil {
		t.Fatalf("partial marker should not fire: %#v", got)
	}
	f, _ = os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0644)
	_, _ = f.WriteString("ceed with server load\n")
	_ = f.Close()
	got := c.detect()
	if got == nil || got.Code != "datapack-load" {
		t.Fatalf("split marker not detected: %#v", got)
	}
}
