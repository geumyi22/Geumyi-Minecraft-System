//go:build windows

package atomicfile

import (
	"errors"
	"os"
	"syscall"
	"time"
)

const (
	errorAccessDenied     syscall.Errno = 5
	errorSharingViolation syscall.Errno = 32
	errorLockViolation    syscall.Errno = 33
)

// replaceFile uses os.Rename (MoveFileEx with MOVEFILE_REPLACE_EXISTING).
// A reader such as an antivirus scanner or a PowerShell Get-Content that holds
// the destination open without FILE_SHARE_DELETE makes the replace fail
// transiently; retry briefly instead of deleting the destination first.
func replaceFile(tmp, dst string) error {
	var err error
	delay := 25 * time.Millisecond
	for attempt := 0; attempt < 8; attempt++ {
		if err = os.Rename(tmp, dst); err == nil {
			return nil
		}
		if !transient(err) {
			return err
		}
		time.Sleep(delay)
		if delay < 400*time.Millisecond {
			delay *= 2
		}
	}
	return err
}

func transient(err error) bool {
	var errno syscall.Errno
	if !errors.As(err, &errno) {
		return false
	}
	return errno == errorAccessDenied || errno == errorSharingViolation || errno == errorLockViolation
}
