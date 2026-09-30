package main

import "testing"

func TestDay10FullUpdateSelfTest(t *testing.T) {
	day9UpdateFaultHook = nil
	defer func() { day9UpdateFaultHook = nil }()
	if err := runDay10SelfTest(); err != nil {
		t.Fatal(err)
	}
}
