package main

import "testing"

// Setup and Host must agree; the existing saved Beta/Canary choice is preserved.
func TestReleaseChannelFreshSetupDefaultIsStableAndDisabled(t *testing.T) {
	got := defaultUpdateConfig(t.TempDir())
	if got.Channel != "stable" || got.Enabled {
		t.Fatalf("fresh Setup updater = channel %q enabled %v; want stable/disabled", got.Channel, got.Enabled)
	}
}

func TestReleaseChannelSetupNormalizationKeepsExplicitOptIn(t *testing.T) {
	for _, tc := range []struct{ input, want string }{
		{"", "stable"},
		{"invalid", "stable"},
		{"stable", "stable"},
		{"beta", "beta"},
		{"canary", "canary"},
		{" CANARY ", "canary"},
	} {
		t.Run(tc.input, func(t *testing.T) {
			got := normalizeUpdateConfig(UpdateConfig{Channel: tc.input, Enabled: true}, t.TempDir())
			if got.Channel != tc.want || !got.Enabled {
				t.Fatalf("normalize channel %q = %q enabled=%v, want %q and enabled=true", tc.input, got.Channel, got.Enabled, tc.want)
			}
		})
	}
}
