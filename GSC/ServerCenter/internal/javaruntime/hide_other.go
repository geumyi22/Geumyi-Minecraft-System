//go:build !windows

package javaruntime

import "os/exec"

func hide(c *exec.Cmd) {}
