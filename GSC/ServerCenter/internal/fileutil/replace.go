package fileutil

import (
	"io"
	"os"
	"path/filepath"
)

// Replace stages the complete file beside its destination so a failed copy
// or rename leaves the previous destination and other writers' files intact.
func Replace(path string, contents io.Reader, mode os.FileMode) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	staged, err := os.CreateTemp(dir, ".gsc-stage-*.tmp")
	if err != nil {
		return err
	}
	defer os.Remove(staged.Name())
	if _, err = io.Copy(staged, contents); err == nil {
		err = staged.Chmod(mode)
	}
	if err == nil {
		err = staged.Sync()
	}
	closeErr := staged.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(staged.Name(), path)
}
