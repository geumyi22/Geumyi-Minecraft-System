//go:build windows

package main

import (
	"crypto/sha256"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestOperatingModeOpensOnlyAfterExplicitLocalIntent(t *testing.T) {
	url := "http://127.0.0.1:" + fmt.Sprint(personalClientPort()) + "/client/operating-mode/open"
	for _, tc := range []struct {
		name, method, intent, body, origin, peer string
		code                                     int
	}{
		{"explicit", "POST", "open-operating-mode", "{}", "", "127.0.0.1:23", 200},
		{"manual", "POST", "open-operating-mode", `{ "view": "manual" }`, "", "127.0.0.1:23", 200},
		{"restore", "POST", "open-operating-mode", `{"view":"restore"}`, "", "127.0.0.1:23", 200},
		{"unknown action", "POST", "open-operating-mode", `{"view":"apply"}`, "", "127.0.0.1:23", 400},
		{"duplicate view", "POST", "open-operating-mode", `{"view":"manual","view":"restore"}`, "", "127.0.0.1:23", 400},
		{"navigation", "GET", "", "", "", "127.0.0.1:23", 405},
		{"no intent", "POST", "", "{}", "", "127.0.0.1:23", 403},
		{"foreign", "POST", "open-operating-mode", "{}", "https://other.invalid", "127.0.0.1:23", 403},
		{"remote peer", "POST", "open-operating-mode", "{}", "", "192.0.2.1:23", 403},
		{"extra option", "POST", "open-operating-mode", `{"target":"ignored"}`, "", "127.0.0.1:23", 400},
		{"empty body", "POST", "open-operating-mode", "", "", "127.0.0.1:23", 400},
		{"json null", "POST", "open-operating-mode", "null", "", "127.0.0.1:23", 400},
	} {
		t.Run(tc.name, func(t *testing.T) {
			calls := 0
			handler := guardClientBrowserRequests(operatingModeOpenHandler(func(view operatingModeView) error {
				calls++
				wanted := modeHome
				if tc.name == "manual" {
					wanted = modeManualReview
				} else if tc.name == "restore" {
					wanted = modeRestoreReview
				}
				if view != wanted {
					t.Fatalf("incorrect native preview destination %v", view)
				}
				return nil
			}))
			req := httptest.NewRequest(tc.method, url, strings.NewReader(tc.body))
			req.RemoteAddr = tc.peer
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("X-GSC-Intent", tc.intent)
			req.Header.Set("Origin", tc.origin)
			out := httptest.NewRecorder()
			handler.ServeHTTP(out, req)
			if out.Code != tc.code || (calls == 1) != (tc.code == http.StatusOK) {
				t.Fatalf("status=%d launches=%d", out.Code, calls)
			}
		})
	}
}

func TestOperatingModeOnlyLaunchesMatchingSibling(t *testing.T) {
	dir := t.TempDir()
	client := filepath.Join(dir, "GeumyiServerCenter.exe")
	data := []byte("inert fixture, never executed")
	expected := fmt.Sprintf("%x", sha256.Sum256(data))
	if _, err := verifiedOperatingMode(client, expected); err == nil {
		t.Fatal("missing sibling accepted")
	}
	path := filepath.Join(dir, operatingModeFile)
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
	f, err := verifiedOperatingMode(client, expected)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(path, []byte("replacement"), 0600); err == nil {
		t.Fatal("verified image not locked while launching")
	}
	f.Close()
	if err = os.WriteFile(path, []byte("replacement"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err = verifiedOperatingMode(client, expected); err == nil {
		t.Fatal("modified sibling accepted")
	}
}

func TestDashboardOpeningHonorsManualHostPolicy(t *testing.T) {
	for _, mode := range []string{"manual", "disabled", "unknown", "automatic", "delayed-automatic", "missing"} {
		calls := 0
		actual := automaticHostTarget(mode, func() bool { calls++; return true })
		want := ""
		if mode == "automatic" || mode == "delayed-automatic" {
			want = "service"
		} else if mode == "missing" {
			want = "task"
		}
		if actual != want || (calls > 0) != (mode == "missing") {
			t.Fatalf("%s returned %q and queried legacy %d times", mode, actual, calls)
		}
	}
	if automaticHostTarget("missing", func() bool { return false }) != "" {
		t.Fatal("missing task cannot start")
	}
	for _, tc := range []struct {
		xml  string
		want bool
	}{
		{`<Task><Triggers><BootTrigger/><LogonTrigger><Enabled>false</Enabled></LogonTrigger></Triggers></Task>`, true},
		{`<Task><Triggers><BootTrigger><Enabled>false</Enabled></BootTrigger></Triggers></Task>`, false},
		{`<Task><Triggers><BootTrigger/></Triggers><Settings><Enabled>false</Enabled></Settings></Task>`, false},
		{`<Task><Triggers/></Task>`, false},
		{`<Task>`, false},
	} {
		const action = `<Actions><Exec><Command>fixture.exe</Command><Arguments>--config "fixture.json"</Arguments></Exec></Actions>`
		raw := strings.Replace(tc.xml, "</Task>", action+"</Task>", 1)
		if usableHostTask([]byte(raw), "fixture.exe", "fixture.json", true) != tc.want {
			t.Fatal(tc.xml)
		}
		if usableHostTask([]byte(raw), "foreign.exe", "fixture.json", false) {
			t.Fatal("same name with a foreign executable accepted")
		}
		if usableHostTask([]byte(strings.Replace(raw, "</Actions>", "<ComHandler/></Actions>", 1)), "fixture.exe", "fixture.json", false) {
			t.Fatal("mixed task accepted")
		}
	}
}
