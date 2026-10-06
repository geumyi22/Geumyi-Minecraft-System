package main

import "testing"

func TestDay11CanaryRolloutOrderMatchesFleetPlan(t *testing.T) {
	c := Config{Servers: []ServerConfig{
		{ID: "lobby", Role: serverRoleLobby},
		{ID: "other", Role: serverRoleOther},
		{ID: "wild", Role: serverRoleWild},
		{ID: "playground", Role: serverRolePlayground},
	}}
	got := defaultCanaryRolloutOrder(c)
	want := []string{"playground", "wild", "other", "lobby"}
	if len(got) != len(want) {
		t.Fatalf("order=%v want=%v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("order[%d]=%q want=%q; full=%v", i, got[i], want[i], got)
		}
	}
}

func TestDay11CanaryTargetPolicyIsPolicyOnlyAndRestorable(t *testing.T) {
	c := Config{Servers: []ServerConfig{{
		ID: "playground",
		Role: serverRolePlayground,
		UpdatePolicy: serverUpdateManual,
		UpdateChannel: serverUpdateChannelBeta,
		UpdatePin: "old-beta-release",
		AutoStart: true,
		RestartOnCrash: true,
	}}}

	prev, err := applyCanaryTargetPolicy(&c, "playground", "canary-release-1")
	if err != nil {
		t.Fatal(err)
	}
	s := normalizeServerConfig(c.Servers[0])
	if s.UpdatePolicy != serverUpdateManaged || s.UpdateChannel != serverUpdateChannelCanary || s.UpdatePin != "canary-release-1" {
		t.Fatalf("unexpected promoted policy: %+v", s)
	}
	if !s.AutoStart || !s.RestartOnCrash {
		t.Fatalf("promotion modified lifecycle settings: %+v", s)
	}
	if prev.Policy != serverUpdateManual || prev.Channel != serverUpdateChannelBeta || prev.Pin != "old-beta-release" {
		t.Fatalf("unexpected previous snapshot: %+v", prev)
	}

	if err := restoreCanaryTargetPolicy(&c, "playground", prev); err != nil {
		t.Fatal(err)
	}
	s = normalizeServerConfig(c.Servers[0])
	if s.UpdatePolicy != serverUpdateManual || s.UpdateChannel != serverUpdateChannelBeta || s.UpdatePin != "old-beta-release" {
		t.Fatalf("policy restore failed: %+v", s)
	}
}

func TestDay11CanaryPromotionRequiresReleaseHealth(t *testing.T) {
	tests := []struct {
		name string
		st UpdateStatus
		release string
		ok bool
	}{
		{"applied same release", UpdateStatus{Phase: "applied", Release: "r1"}, "r1", true},
		{"current same release", UpdateStatus{Phase: "current", Release: "r1"}, "r1", true},
		{"available not applied", UpdateStatus{Phase: "available", Release: "r1"}, "r1", false},
		{"pending health", UpdateStatus{Phase: "pending_health", Release: "r1"}, "r1", false},
		{"rolled back", UpdateStatus{Phase: "rolled_back", Release: "r1"}, "r1", false},
		{"different release", UpdateStatus{Phase: "applied", Release: "r0"}, "r1", false},
	}
	for _, tc := range tests {
		ok, _ := canaryUpdateStateReady(tc.st, tc.release)
		if ok != tc.ok {
			t.Fatalf("%s: ok=%v want=%v", tc.name, ok, tc.ok)
		}
	}
}

func TestDay11CanaryUnknownServerDoesNotMutateConfig(t *testing.T) {
	c := Config{Servers: []ServerConfig{{ID: "wild", UpdatePolicy: serverUpdateHold}}}
	before := c.Servers[0]
	if _, err := applyCanaryTargetPolicy(&c, "missing", "r1"); err == nil {
		t.Fatal("unknown server promotion should fail")
	}
	if c.Servers[0] != before {
		t.Fatalf("failed promotion mutated config: before=%+v after=%+v", before, c.Servers[0])
	}
}
