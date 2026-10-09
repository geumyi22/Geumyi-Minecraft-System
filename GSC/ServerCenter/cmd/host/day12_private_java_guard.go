package main

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// This security guard intentionally applies by the four reserved Day12 profile
// identities, including if a profile's JavaPort was accidentally changed.
// Other/legacy CUSTOM profile names are unaffected.
func day12ExpectedPrivatePorts(id string) (javaPort, rconPort int, known bool) {
	switch strings.ToLower(strings.TrimSpace(id)) {
	case "wild":
		return 25570, 25575, true
	case "playground":
		return 25571, 25576, true
	case "other":
		return 25572, 25577, true
	case "lobby":
		return 25573, 25579, true
	default:
		return 0, 0, false
	}
}

// Decode a Java .properties key, including escaped characters and ASCII
// Unicode escapes. Reject malformed escapes rather than miss a shadow alias.
func day12DecodePropertyKey(raw string) (string, error) {
	var result strings.Builder
	for i := 0; i < len(raw); i++ {
		if raw[i] != '\\' {
			result.WriteByte(raw[i])
			continue
		}
		i++
		if i >= len(raw) {
			return "", errors.New("dangling key escape")
		}
		if raw[i] == 'u' {
			if i+4 >= len(raw) {
				return "", errors.New("short Unicode key escape")
			}
			n, err := strconv.ParseUint(raw[i+1:i+5], 16, 16)
			if err != nil {
				return "", errors.New("invalid Unicode key escape")
			}
			result.WriteRune(rune(n))
			i += 4
		} else {
			switch raw[i] {
			case 't':
				result.WriteByte('\t')
			case 'r':
				result.WriteByte('\r')
			case 'n':
				result.WriteByte('\n')
			case 'f':
				result.WriteByte('\f')
			default:
				result.WriteByte(raw[i])
			}
		}
	}
	return result.String(), nil
}

func day12KeySpace(c byte) bool {
	return c == ' ' || c == '\t' || c == '\f'
}

func day12SplitProperty(line string) (string, string, error) {
	line = strings.TrimLeft(line, " \t\f")
	end := 0
	escaped := false
	for end < len(line) {
		c := line[end]
		if !escaped && (c == '=' || c == ':' || day12KeySpace(c)) {
			break
		}
		if !escaped && c == '\\' {
			escaped = true
		} else {
			escaped = false
		}
		end++
	}
	key, err := day12DecodePropertyKey(line[:end])
	if err != nil {
		return "", "", err
	}
	for end < len(line) && day12KeySpace(line[end]) {
		end++
	}
	if end < len(line) && (line[end] == '=' || line[end] == ':') {
		end++
	}
	for end < len(line) && day12KeySpace(line[end]) {
		end++
	}
	return key, line[end:], nil
}

func day12SecurityKey(key string) bool {
	switch key {
	case "server-ip", "server-port", "enable-rcon", "rcon.port":
		return true
	}
	return false
}

func day12HasTrailingContinuation(line string) bool {
	count := 0
	for i := len(line) - 1; i >= 0 && line[i] == '\\'; i-- {
		count++
	}
	return count%2 == 1
}

// Parse critical .properties keys with Java key separators, escaped aliases
// and continuation semantics. The legacy readServerProperty helper returns
// the first key and does not implement Java duplicate-key behavior: using it
// as a security barrier could let a later shadow override the checked value.
//
// Reject duplicate security keys and security-key continuations/escaped
// VALUES to avoid accepting ambiguous runtime interpretation.
func day12ReadSecureProperties(dir string) (map[string]string, error) {
	file, err := os.Open(filepath.Join(dir, "server.properties"))
	if err != nil {
		return nil, errors.New("properties unreadable")
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 4096), 2*1024*1024)
	values := make(map[string]string)
	var logical strings.Builder
	continued := false
	hadContinuation := false
	appendLogical := func() error {
		line := strings.TrimLeft(strings.TrimPrefix(logical.String(), "\ufeff"), " \t\f")
		logical.Reset()
		if len(line) == 0 || line[0] == '#' || line[0] == '!' {
			return nil
		}
		key, value, err := day12SplitProperty(line)
		if err != nil {
			return errors.New("invalid properties key encoding")
		}
		if !day12SecurityKey(key) {
			return nil
		}
		if _, exists := values[key]; exists {
			return errors.New("duplicate security property")
		}
		if hadContinuation || strings.Contains(value, "\\") {
			return errors.New("ambiguous security property encoding")
		}
		values[key] = strings.TrimSpace(value)
		return nil
	}
	for scanner.Scan() {
		line := strings.TrimSuffix(scanner.Text(), "\r")
		if continued {
			line = strings.TrimLeft(line, " \t\f")
		}
		cont := day12HasTrailingContinuation(line)
		if cont {
			line = line[:len(line)-1]
			hadContinuation = true
		}
		logical.WriteString(line)
		continued = cont
		if !continued {
			if err := appendLogical(); err != nil {
				return nil, err
			}
			hadContinuation = false
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, errors.New("properties scan error")
	}
	if continued {
		return nil, errors.New("unterminated properties continuation")
	}
	return values, nil
}

// Preventive PRE-LAUNCH on-disk Java+RCON port configuration guard only,
// NOT a runtime socket owner/bind attestation. RCON bind scope is not proven.
func day12ManagedJavaBindGuard(s ServerConfig, serverDir string) (status, message string, applicable bool) {
	javaPort, rconPort, known := day12ExpectedPrivatePorts(s.ID)
	if !known {
		return "", "", false
	}
	fail := func(reason string) (string, string, bool) {
		return "fail", reason + " · 서버는 시작하지 않습니다.", true
	}
	if s.JavaPort != javaPort || s.RCONPort != rconPort {
		return fail("Day12 내부 Java/RCON 프로필 포트가 예약된 값과 다릅니다")
	}
	props, err := day12ReadSecureProperties(serverDir)
	if err != nil {
		return fail("내부 서버 설정값이 누락되었거나 중복/인코딩이 모호합니다")
	}
	// GSC's Java/RCON control and health clients dial 127.0.0.1.
	// An alternative loopback (127.0.0.2 or ::1) passes net.IP.IsLoopback()
	// but would break those management paths. Require the exact deployed bind.
	if props["server-ip"] != "127.0.0.1" {
		return fail("내부 Java server-ip는 정확히 127.0.0.1이어야 합니다")
	}
	if p, err := strconv.Atoi(props["server-port"]); err != nil || p != javaPort {
		return fail("내부 Java server-port가 예약된 값과 다릅니다")
	}
	if props["enable-rcon"] != "true" {
		return fail("내부 RCON 활성화 설정이 예상값과 다릅니다")
	}
	if p, err := strconv.Atoi(props["rcon.port"]); err != nil || p != rconPort {
		return fail("내부 RCON 포트가 예약된 값과 다릅니다")
	}
	return "ok", fmt.Sprintf("내부 Java IP 루프백 및 Java/RCON 포트 일치 (Java %d / RCON %d) · 실제 OS 수신/소유권은 별도 검증", javaPort, rconPort), true
}
