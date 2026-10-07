package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

type V4Automation struct {
	ID          string `json:"id"`
	ServerID    string `json:"server_id"`
	Name        string `json:"name"`
	Action      string `json:"action"`         // backup|restart|backup_restart|stop|start
	Time        string `json:"time"`           // HH:MM
	Days        []int  `json:"days,omitempty"` // 0 Sunday ... 6 Saturday; empty=every day
	BackupScope string `json:"backup_scope,omitempty"`
	Enabled     bool   `json:"enabled"`
	LastRunDate string `json:"last_run_date,omitempty"`
	LastResult  string `json:"last_result,omitempty"`
}

var autoMu sync.Mutex
var hhmmRE = regexp.MustCompile(`^(?:[01]\d|2[0-3]):[0-5]\d$`)

func automationsPath() string { return filepath.Join(v4Root(), "automations.json") }
func loadAutomations() []V4Automation {
	autoMu.Lock()
	defer autoMu.Unlock()
	var a []V4Automation
	b, e := os.ReadFile(automationsPath())
	if e == nil {
		_ = json.Unmarshal(b, &a)
	}
	return a
}
func saveAutomations(a []V4Automation) error {
	b, e := json.MarshalIndent(a, "", "  ")
	if e != nil {
		return e
	}
	_ = os.MkdirAll(filepath.Dir(automationsPath()), 0755)
	tmp := automationsPath() + ".tmp"
	if e = os.WriteFile(tmp, b, 0600); e != nil {
		return e
	}
	_ = os.Remove(automationsPath())
	return os.Rename(tmp, automationsPath())
}
func dayAllowed(days []int, w time.Weekday) bool {
	if len(days) == 0 {
		return true
	}
	for _, d := range days {
		if d == int(w) {
			return true
		}
	}
	return false
}
func validAutomation(a V4Automation) error {
	if a.ID == "" {
		a.ID = "auto"
	}
	if _, ok := serverByID(a.ServerID); !ok {
		return fmt.Errorf("unknown server")
	}
	if !hhmmRE.MatchString(a.Time) {
		return fmt.Errorf("time must be HH:MM")
	}
	switch a.Action {
	case "backup", "restart", "backup_restart", "stop", "start":
	default:
		return fmt.Errorf("unsupported action")
	}
	if a.BackupScope == "" {
		a.BackupScope = "world"
	}
	if a.BackupScope != "world" && a.BackupScope != "config" && a.BackupScope != "full" {
		return fmt.Errorf("bad backup scope")
	}
	return nil
}

var automationDiscordAPIBase = "https://discord.com/api/v10"
var discordChannelRE = regexp.MustCompile(`^\d{5,32}$`)

func automationActionLabel(action string) string {
	switch action {
	case "backup":
		return "백업"
	case "restart":
		return "재시작"
	case "backup_restart":
		return "백업 후 재시작"
	case "stop":
		return "정상 종료"
	case "start":
		return "서버 시작"
	default:
		return action
	}
}

func readAutomationProperties(path string) map[string]string {
	out := map[string]string{}
	b, err := os.ReadFile(path)
	if err != nil {
		return out
	}
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(strings.TrimSuffix(line, "\r"))
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, "!") {
			continue
		}
		i := strings.IndexByte(line, '=')
		if i < 1 {
			continue
		}
		out[strings.TrimSpace(line[:i])] = strings.TrimSpace(line[i+1:])
	}
	return out
}

func automationDiscordConfig() (token, channel string, ok bool) {
	c := configSnapshot()
	work := strings.TrimSpace(c.Agent.WorkingDir)
	if work == "" {
		return "", "", false
	}
	p := readAutomationProperties(filepath.Join(work, "agent.properties"))
	token = strings.TrimSpace(p["discord.bot_token"])
	channel = strings.TrimSpace(p["discord.events_channel_id"])
	if channel == "" {
		channel = strings.TrimSpace(p["discord.status_channel_id"])
	}
	if token == "" || token == "PUT_YOUR_BOT_TOKEN_HERE" || token == "CHANGE_ME" || !discordChannelRE.MatchString(channel) {
		return "", "", false
	}
	return token, channel, true
}

func sendAutomationDiscordNow(s ServerConfig, a V4Automation, result string) error {
	token, channel, ok := automationDiscordConfig()
	if !ok {
		return errors.New("discord agent configuration unavailable")
	}
	levelColor := 0x398FF4
	low := strings.ToLower(result)
	if strings.Contains(low, "실패") || strings.Contains(low, "error") || strings.Contains(low, "fail") {
		levelColor = 0xF06478
	}
	desc := fmt.Sprintf("**%s** · %s\n%s", a.Name, automationActionLabel(a.Action), result)
	body, _ := json.Marshal(map[string]any{
		"allowed_mentions": map[string]any{"parse": []string{}},
		"embeds": []map[string]any{{
			"title":       "⚙️ GSC 자동화 · " + s.Name,
			"description": desc,
			"color":       levelColor,
		}},
	})
	ctxClient := &http.Client{Timeout: 5 * time.Second}
	req, err := http.NewRequest(http.MethodPost, strings.TrimRight(automationDiscordAPIBase, "/")+"/channels/"+channel+"/messages", bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bot "+token)
	req.Header.Set("Content-Type", "application/json; charset=utf-8")
	req.Header.Set("User-Agent", "GeumyiServerCenter/4.2.3")
	resp, err := ctxClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 64<<10))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("discord HTTP %d", resp.StatusCode)
	}
	return nil
}

func automationGDSFallback(s ServerConfig, a V4Automation, result string) error {
	pass, err := readServerProperty(resolveServerDir(s), "rcon.password")
	if err != nil || strings.TrimSpace(pass) == "" || s.RCONPort <= 0 {
		return errors.New("RCON unavailable")
	}
	msg := fmt.Sprintf("[GSC 자동화] %s · %s · %s", a.Name, automationActionLabel(a.Action), result)
	msg = strings.NewReplacer("\r", " ", "\n", " ").Replace(msg)
	if len(msg) > 900 {
		msg = msg[:900]
	}
	_, err = rconCommand("127.0.0.1", s.RCONPort, pass, "gds announce "+msg)
	return err
}

func notifyAutomationDiscord(s ServerConfig, a V4Automation, result string) {
	go func() {
		if err := sendAutomationDiscordNow(s, a, result); err == nil {
			return
		}
		if err := automationGDSFallback(s, a, result); err != nil {
			appendV4Event("warn", "automation", s.ID, "Discord 자동화 알림 전달 실패", "Agent Discord 설정 및 GDS/RCON 연결을 확인하세요")
		}
	}()
}

func runAutomation(a V4Automation) string {
	s, ok := serverByID(a.ServerID)
	if !ok {
		return "서버 프로필 없음"
	}
	switch a.Action {
	case "backup":
		rel, e := beginV4Operation(s.ID, "scheduled-backup")
		if e != nil {
			return e.Error()
		}
		defer rel()
		_, e = createBackupWithReason(s, a.BackupScope, false, "automation:"+a.ID)
		if e != nil {
			return e.Error()
		}
		pruneScheduledBackups(s.ID, 14)
		return "백업 완료"
	case "restart":
		msg, e := beginLifecycleCountdown(s, "restart")
		if e != nil {
			return e.Error()
		}
		return msg
	case "backup_restart":
		rel, e := beginV4Operation(s.ID, "scheduled-backup")
		if e != nil {
			return e.Error()
		}
		_, e = createBackupWithReason(s, a.BackupScope, false, "automation:"+a.ID)
		rel()
		if e != nil {
			return e.Error()
		}
		pruneScheduledBackups(s.ID, 14)
		msg, e := beginLifecycleCountdown(s, "restart")
		if e != nil {
			return e.Error()
		}
		return "백업 완료 · " + msg
	case "stop":
		msg, e := beginLifecycleCountdown(s, "stop")
		if e != nil {
			return e.Error()
		}
		return msg
	case "start":
		_, e := startServer(s)
		if e != nil {
			return e.Error()
		}
		return "시작 요청 완료"
	}
	return "unknown"
}
func pruneScheduledBackups(id string, keep int) {
	s, ok := serverByID(id)
	if !ok {
		return
	}
	plan := buildBackupRetentionDryRun(s, keep)
	if plan.BlockedReason != "" {
		appendV4Event("warn", "backup", s.ID, "자동 백업 retention 보류", plan.BlockedReason)
		return
	}
	moved := 0
	for _, candidate := range plan.Candidates {
		if _, err := trashBackupFile(s, candidate.File); err != nil {
			appendV4Event("warn", "backup", s.ID, "자동 백업 retention 중단", err.Error())
			return
		}
		moved++
	}
	if moved > 0 {
		appendV4Event("info", "backup", s.ID, "자동 백업 retention 휴지통 이동",
			fmt.Sprintf("moved=%d keep_latest=%d", moved, plan.KeepLatest))
	}
}

func v4AutomationLoop() {
	t := time.NewTicker(20 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-hostQuit:
			return
		case now := <-t.C:
			a := loadAutomations()
			changed := false
			today := now.Format("2006-01-02")
			clock := now.Format("15:04")
			for i := range a {
				if !a[i].Enabled || a[i].Time != clock || a[i].LastRunDate == today || !dayAllowed(a[i].Days, now.Weekday()) {
					continue
				}
				a[i].LastRunDate = today
				a[i].LastResult = "실행 중"
				_ = saveAutomations(a)
				res := runAutomation(a[i])
				a[i].LastResult = res
				changed = true
				lvl := "info"
				if strings.Contains(strings.ToLower(res), "실패") || strings.Contains(strings.ToLower(res), "error") {
					lvl = "error"
				}
				appendV4Event(lvl, "automation", a[i].ServerID, "자동화: "+a[i].Name, res)
				if s, ok := serverByID(a[i].ServerID); ok {
					notifyAutomationDiscord(s, a[i], res)
				}
			}
			if changed {
				_ = saveAutomations(a)
			}
		}
	}
}

type automationReq struct {
	Action     string       `json:"action"`
	Automation V4Automation `json:"automation"`
	ID         string       `json:"id"`
}

func apiV4Automations(w http.ResponseWriter, r *http.Request) {
	if r.Method == "GET" {
		writeJSON(w, map[string]any{"automations": loadAutomations()})
		return
	}
	if r.Method != "POST" {
		http.Error(w, "POST required", 405)
		return
	}
	var q automationReq
	if json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&q) != nil {
		http.Error(w, "bad json", 400)
		return
	}
	a := loadAutomations()
	switch strings.ToLower(q.Action) {
	case "upsert":
		if q.Automation.ID == "" {
			q.Automation.ID = fmt.Sprintf("auto-%d", time.Now().UnixNano())
		}
		if q.Automation.Name == "" {
			q.Automation.Name = q.Automation.Action + " " + q.Automation.Time
		}
		if q.Automation.BackupScope == "" {
			q.Automation.BackupScope = "world"
		}
		if e := validAutomation(q.Automation); e != nil {
			http.Error(w, e.Error(), 400)
			return
		}
		idx := -1
		for i := range a {
			if a[i].ID == q.Automation.ID {
				idx = i
				break
			}
		}
		if idx >= 0 {
			lastDate, lastResult := a[idx].LastRunDate, a[idx].LastResult
			a[idx] = q.Automation
			a[idx].LastRunDate = lastDate
			a[idx].LastResult = lastResult
		} else {
			a = append(a, q.Automation)
		}
	case "delete":
		id := q.ID
		if id == "" {
			id = q.Automation.ID
		}
		out := a[:0]
		for _, x := range a {
			if x.ID != id {
				out = append(out, x)
			}
		}
		a = out
	case "run":
		id := q.ID
		if id == "" {
			id = q.Automation.ID
		}
		for i := range a {
			if a[i].ID == id {
				res := runAutomation(a[i])
				a[i].LastResult = res
				lvl := "info"
				low := strings.ToLower(res)
				if strings.Contains(low, "실패") || strings.Contains(low, "error") || strings.Contains(low, "fail") {
					lvl = "error"
				}
				appendV4Event(lvl, "automation", a[i].ServerID, "자동화 수동 실행: "+a[i].Name, res)
				if s, ok := serverByID(a[i].ServerID); ok {
					notifyAutomationDiscord(s, a[i], res)
				}
				writeJSON(w, map[string]any{"ok": true, "result": res})
				_ = saveAutomations(a)
				return
			}
		}
		http.Error(w, "automation not found", 404)
		return
	default:
		http.Error(w, "unknown action", 400)
		return
	}
	if e := saveAutomations(a); e != nil {
		http.Error(w, e.Error(), 500)
		return
	}
	writeJSON(w, map[string]any{"ok": true, "automations": a})
}
