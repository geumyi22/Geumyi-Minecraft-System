package main

import (
	"crypto/sha256"
	"encoding/hex"
	"strings"
	"testing"
)

func TestQRV6LPairingPayload(t *testing.T) {
	text := "gscm://pair?host=http%3A%2F%2F100.84.252.113%3A8787&code=12345678"
	m, err := qrV6LModules(text)
	if err != nil {
		t.Fatal(err)
	}
	if len(m) != 41 || len(m[0]) != 41 {
		t.Fatalf("unexpected matrix size: %dx%d", len(m), len(m[0]))
	}
	raw := make([]byte, 0, 41*41)
	for _, row := range m {
		for _, dark := range row {
			if dark {
				raw = append(raw, 1)
			} else {
				raw = append(raw, 0)
			}
		}
	}
	sum := sha256.Sum256(raw)
	if got := hex.EncodeToString(sum[:]); got != "2da682c61fdca119382e189a2de721b8e671e81805f66385a592d759f2944e8e" {
		t.Fatalf("QR matrix mismatch: %s", got)
	}
	svg, err := qrV6LSVG(text)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(svg, `<svg`) || !strings.Contains(svg, `<path`) {
		t.Fatalf("invalid svg")
	}
}

func TestQRV6LRejectsOversize(t *testing.T) {
	if _, err := qrV6LModules(strings.Repeat("x", 135)); err == nil {
		t.Fatal("expected oversize error")
	}
}
