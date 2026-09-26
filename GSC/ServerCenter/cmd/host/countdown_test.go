package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestLifecycleNotifySecondDefault(t *testing.T) {
	want := map[int]bool{60: true, 30: true, 10: true, 5: true, 4: true, 3: true, 2: true, 1: true}
	for sec := 1; sec <= 60; sec++ {
		got := lifecycleNotifySecond(sec, 60)
		if got != want[sec] {
			t.Fatalf("sec=%d got=%v want=%v", sec, got, want[sec])
		}
	}
}

func TestLifecycleNotifySecondCustom(t *testing.T) {
	for _, sec := range []int{300, 120, 60, 30, 10, 5, 4, 3, 2, 1} {
		if !lifecycleNotifySecond(sec, 300) {
			t.Fatalf("expected notification at %ds", sec)
		}
	}
	if lifecycleNotifySecond(299, 300) {
		t.Fatal("unexpected notification at 299s")
	}
	if !lifecycleNotifySecond(45, 45) {
		t.Fatal("custom countdown must announce its start second")
	}
}

func TestLifecycleScheduleStatus(t *testing.T) {
	id := "status-test"
	now := time.Now()
	op := &scheduledLifecycle{
		action:           "restart",
		cancel:           make(chan struct{}),
		done:             make(chan struct{}),
		target:           now.Add(90 * time.Second),
		countdownSeconds: 60,
		createdAt:        now,
		phase:            "waiting",
	}
	lifecycleMu.Lock()
	old := lifecycleOps[id]
	lifecycleOps[id] = op
	lifecycleMu.Unlock()
	defer func() {
		lifecycleMu.Lock()
		if old == nil {
			delete(lifecycleOps, id)
		} else {
			lifecycleOps[id] = old
		}
		lifecycleMu.Unlock()
	}()

	st := lifecycleScheduleStatus(id)
	if !st.Active || st.Action != "restart" || st.CountdownSeconds != 60 || st.Phase != "waiting" {
		t.Fatalf("unexpected status: %+v", st)
	}
	if st.RemainingSeconds < 88 || st.RemainingSeconds > 91 {
		t.Fatalf("unexpected remaining seconds: %d", st.RemainingSeconds)
	}
}

func TestLifecycleScheduleFileLivesBesideConfig(t *testing.T) {
	old := configPath
	configPath = filepath.Join(t.TempDir(), "server.json")
	defer func() { configPath = old }()
	if got, want := lifecycleScheduleFile(), filepath.Join(filepath.Dir(configPath), "lifecycle-schedules.json"); got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestLifecycleDiscordDoesNotRequireRCON(t *testing.T) {
	d := t.TempDir()
	props := "discord.bot_token=test-token\ndiscord.events_channel_id=123456789012345678\n"
	if err := os.WriteFile(filepath.Join(d, "agent.properties"), []byte(props), 0600); err != nil {
		t.Fatal(err)
	}

	configMu.Lock()
	oldCfg := cfg
	cfg = Config{Agent: AgentConfig{WorkingDir: d}}
	configMu.Unlock()
	defer func() {
		configMu.Lock()
		cfg = oldCfg
		configMu.Unlock()
	}()

	var gotAuth, gotPath, gotTitle, gotDescription string
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		gotPath = r.URL.Path
		var payload struct {
			Embeds []struct {
				Title       string `json:"title"`
				Description string `json:"description"`
			} `json:"embeds"`
		}
		_ = json.NewDecoder(r.Body).Decode(&payload)
		if len(payload.Embeds) > 0 {
			gotTitle = payload.Embeds[0].Title
			gotDescription = payload.Embeds[0].Description
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer ts.Close()

	oldBase := automationDiscordAPIBase
	automationDiscordAPIBase = ts.URL
	defer func() { automationDiscordAPIBase = oldBase }()

	err := sendLifecycleDiscordNow(ServerConfig{ID: "other", Name: "금이 기타 서버"}, "restart", 30, "[서버 재시작] 30초 후 서버가 재시작됩니다.")
	if err != nil {
		t.Fatal(err)
	}
	if gotAuth != "Bot test-token" {
		t.Fatalf("bad auth: %q", gotAuth)
	}
	if gotPath != "/channels/123456789012345678/messages" {
		t.Fatalf("bad path: %q", gotPath)
	}
	if !strings.Contains(gotTitle, "금이 기타 서버") || !strings.Contains(gotTitle, "30초") {
		t.Fatalf("unexpected title: %q", gotTitle)
	}
	if !strings.Contains(gotDescription, "30초") {
		t.Fatalf("unexpected description: %q", gotDescription)
	}
}
