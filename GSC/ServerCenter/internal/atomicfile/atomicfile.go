// Package atomicfile replaces files without ever opening a predictable
// temporary path and without deleting the previous destination first.
//
// Why: GSC runs as LocalSystem and writes below %ProgramData%\GeumyiServerCenter.
// On the production host those directories inherit a BUILTIN\Users
// "create files/folders" ACE from %ProgramData%. A fixed "<file>.tmp" path can
// therefore be pre-created by an unprivileged local user. Windows keeps the
// existing file's security descriptor (and owner) when a privileged process
// truncates and rewrites it, so the privileged data would land in a file the
// unprivileged user owns, and Rename would then publish that object as the
// real destination.
//
// Guarantees of WriteFile / WriteFrom:
//   - the temporary file is created with O_EXCL under an unpredictable name in
//     the destination directory (same volume, so the final rename is atomic);
//   - content is flushed with Sync before the rename;
//   - the destination is never removed before the replacement succeeds;
//   - on any error the temporary file is removed and the destination is left
//     exactly as it was;
//   - no ACL is set explicitly: the new file inherits the directory's DACL,
//     which is the same behaviour as the previous os.WriteFile code paths.
//
// Legacy fixed temporary names (for example "server.json.tmp") are left
// untouched on purpose: they may be attacker-owned and must not be opened.
package atomicfile

import (
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// TempPattern returns the os.CreateTemp pattern used for path. Exposed so tests
// and diagnostics can locate leftovers without guessing.
func TempPattern(path string) string {
	base := strings.Map(func(r rune) rune {
		if r == '*' || r == '/' || r == '\\' {
			return '_'
		}
		return r
	}, filepath.Base(path))
	return "." + base + ".gsc-*.tmp"
}

// WriteFile atomically replaces path with data.
func WriteFile(path string, data []byte, perm os.FileMode) error {
	return WriteFrom(path, perm, func(w io.Writer) error {
		_, err := w.Write(data)
		return err
	})
}

// WriteFrom atomically replaces path with whatever fill writes. If fill returns
// an error (for example a hash mismatch detected while streaming) nothing is
// published and the destination is preserved.
func WriteFrom(path string, perm os.FileMode, fill func(io.Writer) error) (err error) {
	if fill == nil {
		return errors.New("atomicfile: nil fill function")
	}
	dir := filepath.Dir(path)
	f, err := os.CreateTemp(dir, TempPattern(path))
	if err != nil {
		return err
	}
	tmp := f.Name()
	published := false
	defer func() {
		if !published {
			_ = f.Close()
			_ = os.Remove(tmp)
		}
	}()
	if err = f.Chmod(perm); err != nil {
		return err
	}
	if err = fill(f); err != nil {
		return err
	}
	if err = f.Sync(); err != nil {
		return err
	}
	if err = f.Close(); err != nil {
		return err
	}
	if err = replaceFile(tmp, path); err != nil {
		return err
	}
	published = true
	return nil
}
