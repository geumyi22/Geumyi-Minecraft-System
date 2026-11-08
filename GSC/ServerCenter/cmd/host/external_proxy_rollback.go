package main

import (
	"errors"
	"fmt"
	"os"
	"strings"
)

type externalProxyBackup struct {
	Live, Backup string
	Exists       bool
}

// Restore both JAR and configuration bytes. A failed copy/hash must never be
// reported as a safe rollback, nor followed by starting an inconsistent proxy.
func restoreExternalProxyBackups(records []externalProxyBackup) error {
	failures := []string{}
	for _, r := range records {
		if !r.Exists {
			if e := os.Remove(r.Live); e != nil && !os.IsNotExist(e) {
				failures = append(failures, fmt.Sprintf("remove newly created file: %v", e))
			}
			continue
		}
		expected, e := fileSHA256(r.Backup)
		if e != nil {
			failures = append(failures, fmt.Sprintf("backup unavailable: %v", e))
			continue
		}
		if e = externalAtomicCopy(r.Backup, r.Live); e != nil {
			failures = append(failures, fmt.Sprintf("restore copy failed: %v", e))
			continue
		}
		got, e := fileSHA256(r.Live)
		if e != nil || !strings.EqualFold(expected, got) {
			failures = append(failures, "restored file hash mismatch")
		}
	}
	if len(failures) > 0 {
		return errors.New(strings.Join(failures, "; "))
	}
	return nil
}
