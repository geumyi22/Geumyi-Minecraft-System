package main

import "testing"

// Setup and Host must agree; an old explicit beta/canary selection is kept,
// while a new installation is neither auto-updating nor prerelease by default.
func TestInstallerReleaseChannelDefaultAndCompatibility(t *testing.T) {
	dir := t.TempDir()
	base := defaultUpdateConfig(dir)
	if base.Channel != "stable" || base.Enabled {
		t.Fatalf("new setup should default to disabled stable channel: %+v", base)
	}
	for _, item := range []struct{ input, want string }{
		{"", "stable"}, {"invalid", "stable"}, {" STABLE ", "stable"},
		{"beta", "beta"}, {"CANARY", "canary"},
	} {
		base.Channel = item.input
		if got := normalizeUpdateConfig(base, dir).Channel; got != item.want {
			t.Fatalf("normalize %q = %q, want %q", item.input, got, item.want)
		}
	}
}
