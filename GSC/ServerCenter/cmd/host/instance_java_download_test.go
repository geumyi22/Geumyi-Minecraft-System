package main

import (
	"archive/zip"
	"net/url"
	"os"
	"path/filepath"
	"testing"
)

func TestInstanceJavaArchiveRejectsEscapeAndLinks(t *testing.T) {
	for _, name := range []string{"../outside.txt", "/absolute.txt", "C:/drive.txt", "jdk\\..\\outside.txt"} {
		t.Run(name, func(t *testing.T) {
			root := t.TempDir()
			archive := filepath.Join(root, "test.zip")
			f, _ := os.Create(archive)
			z := zip.NewWriter(f)
			e, _ := z.Create(name)
			_, _ = e.Write([]byte("data"))
			_ = z.Close()
			_ = f.Close()
			if err := extractInstanceJavaZIP(archive, filepath.Join(root, "out")); err == nil {
				t.Fatal("unsafe archive accepted")
			}
		})
	}
	root := t.TempDir()
	archive := filepath.Join(root, "safe.zip")
	f, _ := os.Create(archive)
	z := zip.NewWriter(f)
	e, _ := z.Create("jdk/bin/java.exe")
	_, _ = e.Write([]byte("fixture"))
	_ = z.Close()
	_ = f.Close()
	if err := extractInstanceJavaZIP(archive, filepath.Join(root, "out")); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(root, "out", "jdk", "bin", "java.exe")); err != nil {
		t.Fatal(err)
	}
}

func TestInstanceJavaRejectsUnofficialDownloads(t *testing.T) {
	for _, raw := range []string{"http://api.adoptium.net/a", "https://github.com/unknown/repo/a", "https://github.com.evil.example/adoptium/a", "https://api.adoptium.net:444/a", "https://user@api.adoptium.net/a"} {
		u, _ := url.Parse(raw)
		if err := validateInstanceJavaURL(u); err == nil {
			t.Fatalf("accepted %s", raw)
		}
	}
	for _, raw := range []string{"https://api.adoptium.net/v3/assets/latest/21/hotspot", "https://github.com/adoptium/temurin21-binaries/releases/download/a.zip", "https://release-assets.githubusercontent.com/github-production-release-asset/a"} {
		u, _ := url.Parse(raw)
		if err := validateInstanceJavaURL(u); err != nil {
			t.Fatal(err)
		}
	}
}
