package main

import "testing"

// A fresh configuration must not opt a real Minecraft server into Canary.
// This test does not read or modify the installed host configuration.
func TestReleaseChannelFreshHostDefaultIsStableAndDisabled(t *testing.T) {
	got := defaultUpdateConfig(t.TempDir())
	if got.Channel != "stable" || got.Enabled {
		t.Fatalf("fresh Host updater = channel %q enabled %v; want stable/disabled", got.Channel, got.Enabled)
	}
}

func TestReleaseChannelHostNormalizationKeepsExplicitOptIn(t *testing.T) {
	for _, tc := range []struct{ input, want string }{
		{"", "stable"},
		{"invalid", "stable"},
		{"stable", "stable"},
		{"beta", "beta"},
		{"canary", "canary"},
		{" CANARY ", "canary"},
	} {
		t.Run(tc.input, func(t *testing.T) {
			got := normalizeUpdateConfig(UpdateConfig{Channel: tc.input, Enabled: true})
			if got.Channel != tc.want || !got.Enabled {
				t.Fatalf("normalize channel %q = %q enabled=%v, want %q and enabled=true", tc.input, got.Channel, got.Enabled, tc.want)
			}
		})
	}
}
