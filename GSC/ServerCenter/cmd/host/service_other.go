//go:build !windows

package main

func serviceModeRequested() bool               { return false }
func runWindowsService(run func() error) error { return run() }
