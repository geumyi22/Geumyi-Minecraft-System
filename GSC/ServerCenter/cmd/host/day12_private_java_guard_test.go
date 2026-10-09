package main

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func day12TestProps(ip string, javaPort, rconPort int) string {
	return "server-ip=" + ip + "\nserver-port=" + strconv.Itoa(javaPort) +
		"\nenable-rcon=true\nrcon.port=" + strconv.Itoa(rconPort) + "\n"
}

func TestDay12ManagedJavaBindGuard(t *testing.T) {
	valid := day12TestProps("127.0.0.1", 25570, 25575)
	tests := []struct {
		name       string
		id         string
		port       int
		rconProfilePort int
		properties string
		wantStatus string
		wantApply  bool
	}{
		{name: "wild loopback IPv4", id: "wild", port: 25570, properties: valid, wantStatus: "ok", wantApply: true},
		{name: "playground loopback", id: "playground", port: 25571, properties: day12TestProps("127.0.0.1", 25571, 25576), wantStatus: "ok", wantApply: true},
		{name: "other configured loopback", id: "other", port: 25572, properties: day12TestProps("127.0.0.1", 25572, 25577), wantStatus: "ok", wantApply: true},
		{name: "other alternate loopback rejected", id: "other", port: 25572, properties: day12TestProps("127.0.0.2", 25572, 25577), wantStatus: "fail", wantApply: true},
		{name: "lobby loopback IPv4", id: "lobby", port: 25573, properties: day12TestProps("127.0.0.1", 25573, 25579), wantStatus: "ok", wantApply: true},
		{name: "lobby loopback IPv6 incompatible with GSC", id: "lobby", port: 25573, properties: day12TestProps("::1", 25573, 25579), wantStatus: "fail", wantApply: true},
		{name: "wild wildcard", id: "wild", port: 25570, properties: day12TestProps("0.0.0.0", 25570, 25575), wantStatus: "fail", wantApply: true},
		{name: "wild empty default", id: "wild", port: 25570, properties: day12TestProps("", 25570, 25575), wantStatus: "fail", wantApply: true},
		{name: "wild missing ip", id: "wild", port: 25570, properties: "server-port=25570\nenable-rcon=true\nrcon.port=25575\n", wantStatus: "fail", wantApply: true},
		{name: "wild public IPv4", id: "wild", port: 25570, properties: day12TestProps("192.0.2.15", 25570, 25575), wantStatus: "fail", wantApply: true},
		{name: "wild IPv6 wildcard", id: "wild", port: 25570, properties: day12TestProps("::", 25570, 25575), wantStatus: "fail", wantApply: true},
		{name: "wild malformed", id: "wild", port: 25570, properties: day12TestProps("not_an_ip", 25570, 25575), wantStatus: "fail", wantApply: true},
		{name: "bad profile port bypass blocked", id: "wild", port: 25565, properties: valid, wantStatus: "fail", wantApply: true},
		{name: "profile RCON port drift blocked", id: "wild", port: 25570, rconProfilePort: 25576, properties: valid, wantStatus: "fail", wantApply: true},
		{name: "mismatched on disk java port", id: "wild", port: 25570, properties: day12TestProps("127.0.0.1", 25565, 25575), wantStatus: "fail", wantApply: true},
		{name: "mismatched on disk rcon port", id: "wild", port: 25570, properties: day12TestProps("127.0.0.1", 25570, 25576), wantStatus: "fail", wantApply: true},
		{name: "disabled rcon", id: "wild", port: 25570, properties: strings.Replace(valid, "enable-rcon=true", "enable-rcon=false", 1), wantStatus: "fail", wantApply: true},
		{name: "missing rcon port", id: "wild", port: 25570, properties: strings.Replace(valid, "rcon.port=25575\n", "", 1), wantStatus: "fail", wantApply: true},
		{name: "wild later duplicate overrides checked IP", id: "wild", port: 25570, properties: valid + "server-ip=0.0.0.0\n", wantStatus: "fail", wantApply: true},
		{name: "wild duplicate even if same", id: "wild", port: 25570, properties: valid + "server-ip=127.0.0.1\n", wantStatus: "fail", wantApply: true},
		{name: "rcon later duplicate overrides port", id: "wild", port: 25570, properties: valid + "rcon.port=25565\n", wantStatus: "fail", wantApply: true},
		{name: "unicode escaped shadow key", id: "wild", port: 25570, properties: valid + "server\\u002dip=0.0.0.0\n", wantStatus: "fail", wantApply: true},
		{name: "colon separator shadow", id: "wild", port: 25570, properties: valid + "server-ip:0.0.0.0\n", wantStatus: "fail", wantApply: true},
		{name: "whitespace separator shadow", id: "wild", port: 25570, properties: valid + "server-ip 0.0.0.0\n", wantStatus: "fail", wantApply: true},
		{name: "logical-line continuation shadow", id: "wild", port: 25570, properties: valid + "serv\\\ner-ip=0.0.0.0\n", wantStatus: "fail", wantApply: true},
		{name: "unescaped critical value rejected", id: "wild", port: 25570, properties: strings.Replace(valid, "server-ip=127.0.0.1", "server-ip=\\u0031" + "27.0.0.1", 1), wantStatus: "fail", wantApply: true},
		{name: "case distinct key not critical", id: "wild", port: 25570, properties: valid + "Server-IP=0.0.0.0\n", wantStatus: "ok", wantApply: true},
		{name: "non-target profile unaffected", id: "experimental", port: 25570, properties: "server-ip=0.0.0.0\n", wantStatus: "", wantApply: false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			if err := os.WriteFile(filepath.Join(dir, "server.properties"), []byte(tc.properties), 0600); err != nil {
				t.Fatal(err)
			}
			rconPort := tc.rconProfilePort
			if rconPort == 0 {
				_, expected, _ := day12ExpectedPrivatePorts(tc.id)
				rconPort = expected
			}
			got, msg, applies := day12ManagedJavaBindGuard(ServerConfig{ID: tc.id, JavaPort: tc.port, RCONPort: rconPort}, dir)
			if got != tc.wantStatus || applies != tc.wantApply {
				t.Fatalf("status=%q applies=%v; want status=%q applies=%v", got, applies, tc.wantStatus, tc.wantApply)
			}
			if tc.wantApply && strings.TrimSpace(msg) == "" {
				t.Fatal("missing fail-closed explanation")
			}
		})
	}
}

func TestDay12ManagedJavaBindGuardMissingProperties(t *testing.T) {
	got, _, applies := day12ManagedJavaBindGuard(ServerConfig{ID: "playground", JavaPort: 25571, RCONPort: 25576}, t.TempDir())
	if got != "fail" || !applies {
		t.Fatalf("missing properties must fail closed: status %q applies %v", got, applies)
	}
}
