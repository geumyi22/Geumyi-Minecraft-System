//go:build windows

package main

import "testing"

func TestFirstPowerGUID(t *testing.T) {
	got := firstPowerGUID("Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)")
	if got != "381b4222-f694-41f0-9685-ff5bb260df2e" {
		t.Fatalf("unexpected guid: %q", got)
	}
}

func TestRoleHelpers(t *testing.T) {
	if !hasServerRole(1) || !hasServerRole(3) || hasServerRole(2) {
		t.Fatal("server role helper")
	}
	if !hasClientRole(2) || !hasClientRole(3) || hasClientRole(1) {
		t.Fatal("client role helper")
	}
}
