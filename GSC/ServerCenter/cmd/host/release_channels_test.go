package main

import "testing"

func TestGSCReleaseChannelsDistinctAndStableRecommended(t *testing.T) {
	catalog := gscReleaseChannelCatalog()
	if len(catalog) != 3 {
		t.Fatalf("channel count=%d want 3", len(catalog))
	}
	expected := []struct {
		id       string
		manifest string
		optIn    bool
	}{
		{"stable", "deployment-stable.json", false},
		{"beta", "deployment-beta.json", true},
		{"canary", "deployment-canary.json", true},
	}
	for i, want := range expected {
		got := catalog[i]
		if got.ID != want.id || got.SignedManifest != want.manifest || got.RequiresOptIn != want.optIn {
			t.Fatalf("channel %d mismatch: %+v", i, got)
		}
		if got.Recommended != (i == 0) || got.Label == "" || got.Purpose == "" || got.PromotionGate == "" || got.Audience == "" {
			t.Fatalf("channel %s missing operator-safe description", got.ID)
		}
	}
}

func TestGSCUpdateChannelDefaultStableButExplicitPrereleasePreserved(t *testing.T) {
	base := defaultUpdateConfig(t.TempDir())
	if base.Channel != "stable" || base.Enabled {
		t.Fatalf("default update must be disabled stable, got %+v", base)
	}
	for _, input := range []struct{ channel, want string }{
		{"", "stable"}, {"unknown", "stable"}, {" STABLE ", "stable"},
		{"beta", "beta"}, {"CANARY", "canary"},
	} {
		base.Channel = input.channel
		if got := normalizeUpdateConfig(base).Channel; got != input.want {
			t.Fatalf("normalize channel %q => %q, want %q", input.channel, got, input.want)
		}
	}
}

func TestPublicGSCChannelMetadataDoesNotConferInstallApproval(t *testing.T) {
	body := publicUpdateConfig(Config{Update: UpdateConfig{Enabled: false, Channel: "beta"}})
	if body["channel"] != "beta" || body["recommended_channel"] != "stable" || body["channel_selection_only"] != true {
		t.Fatalf("unexpected channel metadata: %v", body)
	}
	channels, ok := body["channels"].([]GSCReleaseChannel)
	if !ok || len(channels) != 3 {
		t.Fatal("read-only release catalog is missing")
	}
	if body["enabled"] != false {
		t.Fatal("reading channel catalog must never enable updates")
	}
}
