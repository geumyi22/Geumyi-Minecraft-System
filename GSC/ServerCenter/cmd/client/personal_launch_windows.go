//go:build windows

package main

import (
	"os"
	"strconv"
)

func personalClientValue(key string) string {
	for i, arg := range os.Args[1:] {
		if arg == key && i+2 < len(os.Args) {
			return os.Args[i+2]
		}
	}
	return ""
}
func personalClientFlag(key string) bool {
	for _, arg := range os.Args[1:] {
		if arg == key {
			return true
		}
	}
	return false
}
func personalClientPort() int {
	if n, err := strconv.Atoi(personalClientValue("--port")); err == nil && n > 1024 && n <= 65535 {
		return n
	}
	return localPort
}
