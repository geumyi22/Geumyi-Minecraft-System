//go:build !windows

package atomicfile

import "os"

func replaceFile(tmp, dst string) error { return os.Rename(tmp, dst) }
