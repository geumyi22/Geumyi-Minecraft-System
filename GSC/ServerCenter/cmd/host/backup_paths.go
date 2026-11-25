package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
)

var backupConfigRoots = []string{"server.properties", "bukkit.yml", "spigot.yml", "permissions.yml", "ops.json", "whitelist.json", "config", "plugins/GeumyiDiscordStatus", "plugins/GeumyiServerTools"}

func (m BackupManifest) validateRoots() error {
	if m.Scope == "full" && slices.Equal(m.Roots, []string{"."}) {
		return nil
	}
	if (m.Scope != "config" && m.Scope != "world") || len(m.Roots) == 0 {
		return errors.New("invalid backup scope or missing roots")
	}
	for _, root := range m.Roots {
		name := filepath.ToSlash(root)
		if _, err := filepath.Localize(name); err != nil || name == "." {
			return errors.New("invalid backup root")
		}
		if m.Scope == "config" && !slices.Contains(backupConfigRoots, name) {
			return errors.New("unexpected configuration backup root")
		}
	}
	return nil
}

// Archive members must belong to the declared snapshot even on rollback.
func (m BackupManifest) entryName(entry string) (string, error) {
	name := strings.TrimSuffix(entry, "/")
	local, err := filepath.Localize(name)
	if err != nil || name == "." {
		return "", errors.New("invalid backup entry")
	}
	for _, root := range m.Roots {
		root = filepath.ToSlash(root)
		if root == "." || name == root || strings.HasPrefix(name, root+"/") {
			return local, nil
		}
	}
	return "", errors.New("backup entry outside its declared roots")
}

// The configured server directory is trusted. A nested link may refer to
// unrelated data and cannot be used as a backup or restoration destination.
func confinedBackupPath(base, name string) (string, error) {
	local, err := filepath.Localize(filepath.ToSlash(name))
	if err != nil || local == "." {
		return "", errors.New("expected a path inside the server directory")
	}
	target := filepath.Join(base, local)
	for p := target; p != filepath.Clean(base); p = filepath.Dir(p) {
		st, err := os.Lstat(p)
		if err != nil && !os.IsNotExist(err) {
			return "", err
		}
		if err == nil && st.Mode()&os.ModeSymlink != 0 {
			return "", fmt.Errorf("backup path contains a link: %s", name)
		}
	}
	return target, nil
}
