package main

import "testing"

func TestWebSocketAcceptRFC6455(t *testing.T) {
	got := wsAccept("dGhlIHNhbXBsZSBub25jZQ==")
	want := "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
	if got != want {
		t.Fatalf("ws accept = %q, want %q", got, want)
	}
}

func TestHeaderHasToken(t *testing.T) {
	if !headerHasToken("keep-alive, Upgrade", "upgrade") {
		t.Fatal("Upgrade token not detected")
	}
	if headerHasToken("keep-alive", "upgrade") {
		t.Fatal("unexpected token match")
	}
}
