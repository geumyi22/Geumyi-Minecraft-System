package main

import (
	"bufio"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// reconcileLocalCompanionConfigs keeps the integrated Agent and the per-server
// GeumyiDiscordStatus bridge on one local trust/configuration set. Upgrades used
// to preserve both files independently, so a migrated Agent secret or a default
// playground config could leave Minecraft reachable while Agent heartbeat stayed
// permanently missing.
func reconcileLocalCompanionConfigs() ([]string, bool) {
	c := configSnapshot()
	if !isLoopbackAgent(c.Agent) || strings.TrimSpace(c.Agent.WorkingDir) == "" {
		return nil, false
	}
	props := filepath.Join(c.Agent.WorkingDir, "agent.properties")
	catalogChanged, catalogErr := syncAgentServerCatalog(props, c.Servers)
	if catalogErr != nil {
		appendV4Event("warn", "bridge", "", "Agent 서버 목록 자동 조정 실패", catalogErr.Error())
	}
	secret, secretChanged, err := ensureAgentBridgeSecret(props)
	if err != nil || secret == "" {
		if err != nil {
			appendV4Event("warn", "bridge", "", "Agent/GDS 자동 조정 실패", err.Error())
		}
		return nil, catalogChanged
	}
	agentChanged := catalogChanged || secretChanged
	if secretChanged {
		appendV4Event("info", "bridge", "", "Agent 로컬 브리지 비밀키 자동 정리", "Agent/GDS 공유키를 안전한 로컬 키로 갱신했습니다")
	}
	if catalogChanged {
		appendV4Event("info", "bridge", "", "Agent 서버 목록 자동 동기화", "GSC에 등록된 서버를 Discord 상태판/명령 목록에 반영했습니다")
	}

	changed := []string{}
	for _, s := range c.Servers {
		dir := resolveServerDir(s)
		if dir == "" || !hasGDSPlugin(dir) {
			continue
		}
		path := filepath.Join(dir, "plugins", "GeumyiDiscordStatus", "config.yml")
		endpoint := agentIngestURL(c.Agent)
		wanted := []yamlScalar{
			{section: "server", key: "id", value: yamlQuote(agentServerID(s))},
			{section: "server", key: "name", value: yamlQuote(s.Name)},
			{section: "bridge", key: "enabled", value: "true"},
			{section: "bridge", key: "url", value: yamlQuote(endpoint)},
			{section: "bridge", key: "secret", value: yamlQuote(secret)},
			{section: "agent", key: "enabled", value: "true"},
			{section: "agent", key: "url", value: yamlQuote(endpoint)},
			{section: "agent", key: "secret", value: yamlQuote(secret)},
			{section: "api", key: "enabled", value: "true"},
			{section: "api", key: "bind", value: yamlQuote("127.0.0.1")},
			{section: "api", key: "port", value: strconv.Itoa(s.GDSAPIPort)},
		}
		wasChanged, e := patchGDSConfig(path, wanted)
		if e != nil {
			appendV4Event("warn", "bridge", s.ID, "GDS 설정 자동 조정 실패", e.Error())
			continue
		}
		if wasChanged {
			changed = append(changed, s.ID)
			appendV4Event("info", "bridge", s.ID, "GDS 로컬 브리지 설정 동기화", "서버 ID/API 포트/Agent endpoint/공유키를 GSC 프로필과 일치시켰습니다")
		}
	}
	return changed, agentChanged
}

func applyCompanionReconcile(changedBridges []string, agentChanged bool) {
	go func() {
		if agentChanged && getAgentDesired() && !shuttingDown.Load() {
			setAgentDesired(false)
			if err := stopAgent(); err != nil {
				appendV4Event("warn", "bridge", "", "Agent 설정 재적용 실패", err.Error())
				setAgentDesired(true)
			} else {
				setAgentDesired(true)
				if _, err := startAgent(); err != nil {
					appendV4Event("warn", "bridge", "", "Agent 재시작 실패", err.Error())
				} else {
					appendV4Event("info", "bridge", "", "Agent 서버 목록 즉시 반영", "Discord 상태판과 서버 명령 목록을 새 프로필 기준으로 다시 불러왔습니다")
				}
			}
		}
		reloadReconciledGDS(changedBridges)
	}()
}

func isLoopbackAgent(a AgentConfig) bool {
	for _, raw := range []string{a.StateURL, a.HealthURL} {
		u, err := url.Parse(strings.TrimSpace(raw))
		if err != nil || u.Hostname() == "" {
			continue
		}
		h := u.Hostname()
		if strings.EqualFold(h, "localhost") {
			return true
		}
		if ip := net.ParseIP(h); ip != nil && ip.IsLoopback() {
			return true
		}
	}
	return false
}

func agentIngestURL(a AgentConfig) string {
	raw := strings.TrimSpace(a.StateURL)
	if raw == "" {
		raw = strings.TrimSpace(a.HealthURL)
	}
	if u, err := url.Parse(raw); err == nil && u.Scheme != "" && u.Host != "" {
		u.Path = "/ingest"
		u.RawQuery = ""
		u.Fragment = ""
		return u.String()
	}
	return "http://127.0.0.1:8877/ingest"
}

func agentServerID(s ServerConfig) string {
	if strings.EqualFold(s.ID, "wild") {
		return "survival"
	}
	return s.ID
}

func hasGDSPlugin(dir string) bool {
	if st, err := os.Stat(filepath.Join(dir, "plugins", "GeumyiDiscordStatus")); err == nil && st.IsDir() {
		return true
	}
	m, _ := filepath.Glob(filepath.Join(dir, "plugins", "GeumyiDiscordStatus*.jar"))
	return len(m) > 0
}

func syncAgentServerCatalog(path string, servers []ServerConfig) (bool, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return false, fmt.Errorf("agent.properties 읽기 실패: %w", err)
	}
	text := strings.ReplaceAll(string(b), "\r\n", "\n")
	original := text
	ids := make([]string, 0, len(servers))
	seen := map[string]bool{}
	for _, s := range servers {
		id := strings.TrimSpace(agentServerID(s))
		if id == "" || seen[id] {
			continue
		}
		seen[id] = true
		ids = append(ids, id)
		name := strings.TrimSpace(s.Name)
		if name == "" {
			name = strings.TrimSpace(s.ID)
		}
		text = setPropertyValue(text, "server."+id+".name", name)
		text = setPropertyValue(text, "server."+id+".host", "127.0.0.1")
		text = setPropertyValue(text, "server."+id+".java_port", strconv.Itoa(s.JavaPort))
		text = setPropertyValue(text, "server."+id+".gds_api_port", strconv.Itoa(s.GDSAPIPort))
		text = setPropertyValue(text, "gsc.server_id."+id, s.ID)
	}
	text = setPropertyValue(text, "servers", strings.Join(ids, ","))
	if text == original {
		return false, nil
	}
	if err := atomicWriteText(path, text); err != nil {
		return false, err
	}
	return true, nil
}

func ensureAgentBridgeSecret(path string) (string, bool, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", false, fmt.Errorf("agent.properties 읽기 실패: %w", err)
	}
	text := strings.ReplaceAll(string(b), "\r\n", "\n")
	secret := propertyValue(text, "secret")
	changed := false
	if weakBridgeSecret(secret) {
		buf := make([]byte, 32)
		if _, err := rand.Read(buf); err != nil {
			return "", false, err
		}
		secret = base64.RawURLEncoding.EncodeToString(buf)
		text = setPropertyValue(text, "secret", secret)
		changed = true
	}
	stateSecret := propertyValue(text, "state_api_secret")
	if weakBridgeSecret(stateSecret) {
		text = setPropertyValue(text, "state_api_secret", secret)
		changed = true
	}
	if !strings.EqualFold(propertyValue(text, "allow_loopback_ingest_without_matching_secret"), "false") {
		text = setPropertyValue(text, "allow_loopback_ingest_without_matching_secret", "false")
		changed = true
	}
	if changed {
		if err := atomicWriteText(path, text); err != nil {
			return "", false, err
		}
	}
	return secret, changed, nil
}

func weakBridgeSecret(v string) bool {
	v = strings.TrimSpace(v)
	return len(v) < 24 || strings.HasPrefix(strings.ToUpper(v), "CHANGE_THIS") || strings.Contains(strings.ToUpper(v), "PUT_YOUR")
}

func propertyValue(text, key string) string {
	sc := bufio.NewScanner(strings.NewReader(text))
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") || !strings.Contains(line, "=") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if strings.TrimSpace(parts[0]) == key {
			return strings.TrimSpace(parts[1])
		}
	}
	return ""
}

func setPropertyValue(text, key, value string) string {
	lines := strings.Split(text, "\n")
	prefix := key + "="
	for i, line := range lines {
		trim := strings.TrimSpace(line)
		if strings.HasPrefix(trim, "#") {
			continue
		}
		if strings.HasPrefix(trim, prefix) {
			indent := line[:len(line)-len(strings.TrimLeft(line, " \t"))]
			lines[i] = indent + prefix + value
			return strings.Join(lines, "\n")
		}
	}
	if len(lines) > 0 && strings.TrimSpace(lines[len(lines)-1]) != "" {
		lines = append(lines, "")
	}
	lines = append(lines, prefix+value)
	return strings.Join(lines, "\n")
}

type yamlScalar struct{ section, key, value string }

func yamlQuote(v string) string { return strconv.Quote(v) }

func patchGDSConfig(path string, wanted []yamlScalar) (bool, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return false, err
	}
	var text string
	if b, err := os.ReadFile(path); err == nil {
		text = strings.ReplaceAll(string(b), "\r\n", "\n")
	} else if os.IsNotExist(err) {
		text = defaultGDSConfig()
	} else {
		return false, err
	}
	original := text
	for _, w := range wanted {
		text = setYAMLScalar(text, w.section, w.key, w.value)
	}
	if text == original {
		return false, nil
	}
	return true, atomicWriteText(path, text)
}

func setYAMLScalar(text, section, key, value string) string {
	lines := strings.Split(text, "\n")
	sec := -1
	end := len(lines)
	for i, line := range lines {
		if strings.TrimSpace(line) == section+":" && len(line)-len(strings.TrimLeft(line, " \t")) == 0 {
			sec = i
			for j := i + 1; j < len(lines); j++ {
				trim := strings.TrimSpace(lines[j])
				if trim == "" || strings.HasPrefix(trim, "#") {
					continue
				}
				if len(lines[j])-len(strings.TrimLeft(lines[j], " \t")) == 0 {
					end = j
					break
				}
			}
			break
		}
	}
	entry := "  " + key + ": " + value
	if sec < 0 {
		if len(lines) > 0 && strings.TrimSpace(lines[len(lines)-1]) != "" {
			lines = append(lines, "")
		}
		lines = append(lines, section+":", entry)
		return strings.Join(lines, "\n")
	}
	for i := sec + 1; i < end; i++ {
		trim := strings.TrimSpace(lines[i])
		if strings.HasPrefix(trim, key+":") && len(lines[i])-len(strings.TrimLeft(lines[i], " \t")) > 0 {
			lines[i] = entry
			return strings.Join(lines, "\n")
		}
	}
	lines = append(lines[:end], append([]string{entry}, lines[end:]...)...)
	return strings.Join(lines, "\n")
}

func atomicWriteText(path, text string) error {
	tmp := path + ".gsc.tmp"
	if err := os.WriteFile(tmp, []byte(text), 0600); err != nil {
		return err
	}
	if err := os.Rename(tmp, path); err != nil {
		_ = os.Remove(path)
		if err2 := os.Rename(tmp, path); err2 != nil {
			_ = os.Remove(tmp)
			return err
		}
	}
	return nil
}

func defaultGDSConfig() string {
	return `# Managed by Geumyi Server Center. Other GDS settings remain editable.
server:
  id: "survival"
  name: "Geumyi Server"
bridge:
  enabled: true
  url: ""
  secret: ""
  heartbeat-seconds: 10
  connect-timeout-ms: 1200
  request-timeout-ms: 1800
  max-in-flight: 8
  retry:
    max-attempts: 3
    base-delay-ms: 500
agent:
  enabled: true
  url: "http://127.0.0.1:8877/ingest"
  secret: ""
  heartbeat-seconds: 10
  connect-timeout-ms: 1200
  request-timeout-ms: 1800
api:
  enabled: true
  bind: "127.0.0.1"
  port: 8766
  token: ""
  allow-unauthenticated-loopback: true
  actions-enabled: true
  allow-unauthenticated-actions: false
  action-timeout-ms: 3000
  worker-threads: 4
performance:
  enabled: true
  interval-seconds: 5
  low-tps: 18.0
  high-mspt: 50.0
  high-memory-percent: 90.0
  consecutive-samples: 3
  recovery-samples: 3
  alert-cooldown-seconds: 120
integration:
  gst:
    enabled: true
    health-max-age-seconds: 30
    relay-lag-events: true
    relay-alert-log: true
    relay-existing-on-startup: false
    prefer-gst-performance-alerts: true
  discordsrv:
    suppress-join-quit-when-present: true
events:
  startup: true
  shutdown: true
  first-join: true
  join: false
  quit: false
  death: false
logging:
  events-file: true
  metrics-file: true
  actions-file: true
  metrics-interval-seconds: 60
  debug: false
`
}

// If an already-running server had an old in-memory GDS config, reload it only
// after the new Agent had time to start. Stopped servers simply consume the
// reconciled config on their next start.
func reloadReconciledGDS(ids []string) {
	if len(ids) == 0 {
		return
	}
	time.Sleep(4 * time.Second)
	for _, id := range ids {
		s, ok := serverByID(id)
		if !ok || !tcpOpen("127.0.0.1", s.JavaPort, 300*time.Millisecond) {
			continue
		}
		pass, err := readServerProperty(resolveServerDir(s), "rcon.password")
		if err != nil || pass == "" {
			appendV4Event("warn", "bridge", s.ID, "GDS 설정 반영 대기", "서버 재시작 시 자동 반영됩니다 (RCON 사용 불가)")
			continue
		}
		if _, err := rconCommand("127.0.0.1", s.RCONPort, pass, "gds reload"); err != nil {
			appendV4Event("warn", "bridge", s.ID, "GDS 설정 reload 실패", err.Error())
		} else {
			appendV4Event("info", "bridge", s.ID, "GDS 설정 즉시 반영", "Agent heartbeat 설정을 다시 읽었습니다")
		}
	}
}
