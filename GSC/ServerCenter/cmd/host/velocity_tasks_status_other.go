//go:build !windows

package main

import "context"

// No Windows Task Scheduler exists on the current platform.
func observeVelocityTasks(context.Context) map[string]string {
    return map[string]string{}
}
