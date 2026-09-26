package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestTailFileReturnsLastLinesFromLargeLog(t *testing.T) {
	p := filepath.Join(t.TempDir(), "latest.log")
	f, err := os.Create(p)
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 120000; i++ {
		fmt.Fprintf(f, "%06d %s\n", i, strings.Repeat("x", 80))
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
	b, err := tailFile(p, 500)
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimSpace(string(b)), "\n")
	if len(lines) != 500 {
		t.Fatalf("got %d lines", len(lines))
	}
	if !strings.HasPrefix(lines[0], "119500 ") || !strings.HasPrefix(lines[499], "119999 ") {
		t.Fatalf("unexpected tail range: first=%q last=%q", lines[0], lines[499])
	}
}
