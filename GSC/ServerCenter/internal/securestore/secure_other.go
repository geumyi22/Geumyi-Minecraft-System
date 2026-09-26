//go:build !windows

package securestore

func ProtectString(s string, machine bool) (string, error) { return s, nil }
func UnprotectString(s string) (string, error)             { return s, nil }
