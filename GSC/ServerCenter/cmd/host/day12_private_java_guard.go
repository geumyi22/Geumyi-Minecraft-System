package main

import (
	"fmt"
	"net"
	"strings"
)

// day12ExpectedPrivateJavaPort intentionally limits this additional guard to
// the four fixed Day 12 internal Paper profiles. Legacy/unrelated GSC server
// profiles retain their existing preflight semantics.
func day12ExpectedPrivateJavaPort(id string) (int, bool) {
	switch strings.ToLower(strings.TrimSpace(id)) {
	case "wild":
		return 25570, true
	case "playground":
		return 25571, true
	case "other":
		return 25572, true
	case "lobby":
		return 25573, true
	default:
		return 0, false
	}
}

// day12ManagedJavaBindGuard verifies only the effective on-disk Paper
// server-ip before GSC launches a known Day12 private backend. It is a
// preventive configuration check, NOT live OS socket/binding/owner attestation.
// In particular, RCON binding and IPv6 exposure remain separate gates.
func day12ManagedJavaBindGuard(s ServerConfig, serverDir string) (status, message string, applicable bool) {
	expected, known := day12ExpectedPrivateJavaPort(s.ID)
	if !known || s.JavaPort != expected {
		return "", "", false
	}
	raw, err := readServerProperty(serverDir, "server-ip")
	if err != nil {
		return "fail", "내부 Java server-ip를 읽지 못했습니다. 시작을 차단합니다.", true
	}
	value := strings.TrimSpace(raw)
	address := net.ParseIP(strings.Trim(value, "[]"))
	if value == "" || address == nil || !address.IsLoopback() {
		return "fail", "내부 Java server-ip가 루프백 주소가 아닙니다. 설정을 확인한 뒤 다시 시작하세요.", true
	}
	return "ok", fmt.Sprintf("Java 루프백 설정 확인 (%s) · 실제 TCP 수신/소유권은 별도 검증", value), true
}
