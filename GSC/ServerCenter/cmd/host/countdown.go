package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	defaultLifecycleCountdownSeconds = 60
	maxLifecycleCountdownSeconds     = 24 * 60 * 60
	maxLifecycleScheduleHorizon      = 366 * 24 * time.Hour
	missedScheduleGrace              = 10 * time.Minute
)

type LifecycleScheduleStatus struct {
	Active                    bool   `json:"active"`
	Action                    string `json:"action,omitempty"`
	ActionLabel               string `json:"action_label,omitempty"`
	ExecuteAt                 string `json:"execute_at,omitempty"`
	CountdownSeconds          int    `json:"countdown_seconds,omitempty"`
	CountdownStartsAt         string `json:"countdown_starts_at,omitempty"`
	Phase                     string `json:"phase,omitempty"`
	RemainingSeconds          int64  `json:"remaining_seconds,omitempty"`
	CountdownRemainingSeconds int64  `json:"countdown_remaining_seconds,omitempty"`
	CreatedAt                 string `json:"created_at,omitempty"`
}

type scheduledLifecycle struct {
	action           string
	cancel           chan struct{}
	done             chan struct{}
	target           time.Time
	countdownSeconds int
	createdAt        time.Time
	phase            string
	prevDesired      bool
	desiredCaptured  bool
}

type persistedLifecycleSchedule struct {
	ID               string `json:"id"`
	Action           string `json:"action"`
	ExecuteAt        string `json:"execute_at"`
	CountdownSeconds int    `json:"countdown_seconds"`
	CreatedAt        string `json:"created_at"`
}

var lifecycleMu sync.Mutex
var lifecycleOps = map[string]*scheduledLifecycle{}

func lifecycleActionLabel(action string) string {
	switch strings.ToLower(action) {
	case "restart":
		return "재시작"
	case "stop":
		return "종료"
	default:
		return action
	}
}

func lifecycleNotifySecond(sec, total int) bool {
	if sec <= 0 {
		return false
	}
	if sec == total {
		return true
	}
	switch sec {
	case 3600, 1800, 900, 600, 300, 120, 60, 30, 10, 5, 4, 3, 2, 1:
		return sec <= total
	default:
		return false
	}
}

func lifecycleScheduleFile() string {
	if strings.TrimSpace(configPath) == "" {
		return ""
	}
	return filepath.Join(filepath.Dir(configPath), "lifecycle-schedules.json")
}

func saveLifecycleSchedulesLocked() error {
	path := lifecycleScheduleFile()
	if path == "" {
		return nil
	}
	rows := make([]persistedLifecycleSchedule, 0, len(lifecycleOps))
	for id, op := range lifecycleOps {
		rows = append(rows, persistedLifecycleSchedule{
			ID:               id,
			Action:           op.action,
			ExecuteAt:        op.target.Format(time.RFC3339Nano),
			CountdownSeconds: op.countdownSeconds,
			CreatedAt:        op.createdAt.Format(time.RFC3339Nano),
		})
	}
	b, err := json.MarshalIndent(rows, "", "  ")
	if err != nil {
		return err
	}
	if err = os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err = os.WriteFile(tmp, b, 0600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func restoreLifecycleSchedules() {
	path := lifecycleScheduleFile()
	if path == "" {
		return
	}
	b, err := os.ReadFile(path)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			fmt.Fprintf(os.Stderr, "schedule restore error: %v\n", err)
		}
		return
	}
	var rows []persistedLifecycleSchedule
	if err := json.Unmarshal(b, &rows); err != nil {
		fmt.Fprintf(os.Stderr, "schedule restore parse error: %v\n", err)
		return
	}
	now := time.Now()
	type restored struct {
		s  ServerConfig
		op *scheduledLifecycle
	}
	var start []restored

	lifecycleMu.Lock()
	for _, row := range rows {
		action := strings.ToLower(strings.TrimSpace(row.Action))
		if action != "stop" && action != "restart" {
			continue
		}
		s, ok := serverByID(row.ID)
		if !ok {
			continue
		}
		target, e := time.Parse(time.RFC3339Nano, row.ExecuteAt)
		if e != nil {
			continue
		}
		if target.Before(now.Add(-missedScheduleGrace)) {
			setLaunchPhase(s.ID, "stopped", s.Name+" 지난 예약 만료 · 실행하지 않음", "")
			continue
		}
		countdown := row.CountdownSeconds
		if countdown < 0 {
			countdown = 0
		}
		if countdown > maxLifecycleCountdownSeconds {
			countdown = maxLifecycleCountdownSeconds
		}
		created := now
		if row.CreatedAt != "" {
			if t, e := time.Parse(time.RFC3339Nano, row.CreatedAt); e == nil {
				created = t
			}
		}
		// If the Host was briefly unavailable and the exact execution time has just
		// passed, honor the reservation immediately instead of replaying a full countdown.
		if !target.After(now) {
			target = now.Add(1 * time.Second)
			countdown = 0
		}
		op := &scheduledLifecycle{
			action:           action,
			cancel:           make(chan struct{}),
			done:             make(chan struct{}),
			target:           target,
			countdownSeconds: countdown,
			createdAt:        created,
			phase:            "waiting",
		}
		if lifecycleOps[s.ID] != nil {
			continue
		}
		lifecycleOps[s.ID] = op
		start = append(start, restored{s: s, op: op})
	}
	_ = saveLifecycleSchedulesLocked()
	lifecycleMu.Unlock()

	for _, r := range start {
		go runLifecycleSchedule(r.s, r.op)
	}
}

func beginLifecycleCountdown(s ServerConfig, action string) (string, error) {
	action = strings.ToLower(strings.TrimSpace(action))
	if action != "stop" && action != "restart" {
		return "", errors.New("unsupported lifecycle action")
	}
	if shuttingDown.Load() {
		return "전체 종료 중", errors.New("shutdown in progress")
	}

	// Keep the v3.0.5 quick-action behavior: an offline stop needs no countdown,
	// and an offline restart is effectively a start request.
	if !tcpOpen("127.0.0.1", s.JavaPort, 350*time.Millisecond) {
		if action == "stop" {
			return s.Name + " 이미 OFFLINE", nil
		}
		go func() { _, _ = restartServer(s) }()
		return s.Name + " OFFLINE · 즉시 시작 요청됨", nil
	}

	executeAt := time.Now().Add(defaultLifecycleCountdownSeconds * time.Second)
	return createLifecycleSchedule(s, action, executeAt, defaultLifecycleCountdownSeconds)
}

func createLifecycleSchedule(s ServerConfig, action string, executeAt time.Time, countdownSeconds int) (string, error) {
	action = strings.ToLower(strings.TrimSpace(action))
	if action != "stop" && action != "restart" {
		return "", errors.New("unsupported lifecycle action")
	}
	if shuttingDown.Load() {
		return "전체 종료 중", errors.New("shutdown in progress")
	}
	if countdownSeconds < 0 || countdownSeconds > maxLifecycleCountdownSeconds {
		return "", fmt.Errorf("countdown_seconds must be 0..%d", maxLifecycleCountdownSeconds)
	}
	now := time.Now()
	if !executeAt.After(now.Add(500 * time.Millisecond)) {
		return "예약 시각은 현재보다 최소 1초 뒤여야 합니다", errors.New("schedule time must be in the future")
	}
	if executeAt.Sub(now) > maxLifecycleScheduleHorizon {
		return "예약은 최대 366일 뒤까지 가능합니다", errors.New("schedule horizon exceeded")
	}

	lifecycleMu.Lock()
	if old := lifecycleOps[s.ID]; old != nil {
		label := lifecycleActionLabel(old.action)
		lifecycleMu.Unlock()
		return fmt.Sprintf("%s %s 예약이 이미 진행 중입니다", s.Name, label), errors.New("schedule already active")
	}
	op := &scheduledLifecycle{
		action:           action,
		cancel:           make(chan struct{}),
		done:             make(chan struct{}),
		target:           executeAt,
		countdownSeconds: countdownSeconds,
		createdAt:        now,
		phase:            "waiting",
	}
	lifecycleOps[s.ID] = op
	if err := saveLifecycleSchedulesLocked(); err != nil {
		delete(lifecycleOps, s.ID)
		lifecycleMu.Unlock()
		return "예약 저장 실패", err
	}
	lifecycleMu.Unlock()

	go runLifecycleSchedule(s, op)
	label := lifecycleActionLabel(action)
	return fmt.Sprintf("%s %s 예약 · %s · 카운트다운 %d초", s.Name, label, executeAt.Local().Format("2006-01-02 15:04:05"), countdownSeconds), nil
}

func cancelLifecycleCountdown(id string) bool {
	lifecycleMu.Lock()
	op := lifecycleOps[id]
	if op == nil {
		lifecycleMu.Unlock()
		return false
	}
	delete(lifecycleOps, id)
	_ = saveLifecycleSchedulesLocked()
	close(op.cancel)
	lifecycleMu.Unlock()
	return true
}

func finishLifecycleCountdown(id string, op *scheduledLifecycle) {
	lifecycleMu.Lock()
	if lifecycleOps[id] == op {
		delete(lifecycleOps, id)
		_ = saveLifecycleSchedulesLocked()
	}
	lifecycleMu.Unlock()
	close(op.done)
}

func lifecycleScheduleStatus(id string) LifecycleScheduleStatus {
	lifecycleMu.Lock()
	op := lifecycleOps[id]
	if op == nil {
		lifecycleMu.Unlock()
		return LifecycleScheduleStatus{}
	}
	target := op.target
	countdown := op.countdownSeconds
	created := op.createdAt
	phase := op.phase
	action := op.action
	lifecycleMu.Unlock()

	now := time.Now()
	remain := int64(math.Ceil(target.Sub(now).Seconds()))
	if remain < 0 {
		remain = 0
	}
	countdownStart := target.Add(-time.Duration(countdown) * time.Second)
	countdownRemain := int64(0)
	if !now.Before(countdownStart) && target.After(now) {
		countdownRemain = remain
	}
	return LifecycleScheduleStatus{
		Active:                    true,
		Action:                    action,
		ActionLabel:               lifecycleActionLabel(action),
		ExecuteAt:                 target.Format(time.RFC3339Nano),
		CountdownSeconds:          countdown,
		CountdownStartsAt:         countdownStart.Format(time.RFC3339Nano),
		Phase:                     phase,
		RemainingSeconds:          remain,
		CountdownRemainingSeconds: countdownRemain,
		CreatedAt:                 created.Format(time.RFC3339Nano),
	}
}

func setLifecyclePhase(id string, op *scheduledLifecycle, phase string) {
	lifecycleMu.Lock()
	if lifecycleOps[id] == op {
		op.phase = phase
	}
	lifecycleMu.Unlock()
}

func captureAndSuppressDesired(id string, op *scheduledLifecycle) {
	lifecycleMu.Lock()
	if lifecycleOps[id] == op && !op.desiredCaptured {
		op.prevDesired = getDesired(id)
		op.desiredCaptured = true
	}
	lifecycleMu.Unlock()
	setDesired(id, false)
}

func handleLifecycleCancel(s ServerConfig, op *scheduledLifecycle, label string) {
	lifecycleMu.Lock()
	captured := op.desiredCaptured
	prev := op.prevDesired
	lifecycleMu.Unlock()
	if captured {
		setDesired(s.ID, prev)
	}
	phase := "stopped"
	if tcpOpen("127.0.0.1", s.JavaPort, 250*time.Millisecond) {
		phase = "online"
	}
	setLaunchPhase(s.ID, phase, s.Name+" "+label+" 예약 취소 · 서버 상태 유지", "")
	lifecycleNotice(s, "cancel", 0)
}

func runLifecycleSchedule(s ServerConfig, op *scheduledLifecycle) {
	defer finishLifecycleCountdown(s.ID, op)
	label := lifecycleActionLabel(op.action)
	countdownStart := op.target.Add(-time.Duration(op.countdownSeconds) * time.Second)

	if time.Now().Before(countdownStart) {
		setLifecyclePhase(s.ID, op, "waiting")
		setLaunchPhase(s.ID, "scheduled", fmt.Sprintf("%s 예약 · %s · %d초 전 카운트다운", label, op.target.Local().Format("2006-01-02 15:04:05"), op.countdownSeconds), "")
		t := time.NewTimer(time.Until(countdownStart))
		select {
		case <-op.cancel:
			if !t.Stop() {
				select {
				case <-t.C:
				default:
				}
			}
			handleLifecycleCancel(s, op, label)
			return
		case <-t.C:
		}
	}

	setLifecyclePhase(s.ID, op, "countdown")
	captureAndSuppressDesired(s.ID, op)
	lastNotified := -1

	for {
		select {
		case <-op.cancel:
			handleLifecycleCancel(s, op, label)
			return
		default:
		}

		remainingDuration := time.Until(op.target)
		if remainingDuration <= 0 {
			break
		}
		sec := int(math.Ceil(remainingDuration.Seconds()))
		setLaunchPhase(s.ID, "countdown", fmt.Sprintf("%s까지 %d초 · 예약 %s", label, sec, op.target.Local().Format("15:04:05")), "")
		if lifecycleNotifySecond(sec, op.countdownSeconds) && sec != lastNotified {
			lifecycleNotice(s, op.action, sec)
			lastNotified = sec
		}

		next := op.target.Add(-time.Duration(sec-1) * time.Second)
		wait := time.Until(next)
		if wait <= 0 || wait > time.Second {
			wait = time.Second
		}
		t := time.NewTimer(wait)
		select {
		case <-op.cancel:
			if !t.Stop() {
				select {
				case <-t.C:
				default:
				}
			}
			handleLifecycleCancel(s, op, label)
			return
		case <-t.C:
		}
	}

	setLifecyclePhase(s.ID, op, "executing")
	setLaunchPhase(s.ID, "executing", s.Name+" 예약 시각 도달 · "+label+" 실행 중", "")
	lifecycleNotice(s, op.action, 0)

	if op.action == "restart" {
		setDesired(s.ID, false)
		_, _ = restartServer(s)
		return
	}
	setDesired(s.ID, false)
	_, _ = stopServer(s)
}

func sendLifecycleDiscordNow(s ServerConfig, action string, sec int, message string) error {
	token, channel, ok := automationDiscordConfig()
	if !ok {
		return errors.New("discord agent configuration unavailable")
	}
	color := 0x398FF4
	title := "⏱️ GSC 서버 작업 · " + s.Name
	switch strings.ToLower(action) {
	case "stop":
		color = 0xF06478
		title = "⏱️ 서버 종료 · " + s.Name
	case "restart":
		color = 0xE8BC55
		title = "⏱️ 서버 재시작 · " + s.Name
	case "cancel":
		color = 0x7895AF
		title = "↩️ 서버 작업 취소 · " + s.Name
	}
	if sec > 0 {
		title += fmt.Sprintf(" · %d초", sec)
	}
	body, _ := json.Marshal(map[string]any{
		"allowed_mentions": map[string]any{"parse": []string{}},
		"embeds": []map[string]any{{
			"title":       title,
			"description": message,
			"color":       color,
		}},
	})
	client := &http.Client{Timeout: 5 * time.Second}
	req, err := http.NewRequest(http.MethodPost, strings.TrimRight(automationDiscordAPIBase, "/")+"/channels/"+channel+"/messages", bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bot "+token)
	req.Header.Set("Content-Type", "application/json; charset=utf-8")
	req.Header.Set("User-Agent", "GeumyiServerCenter/4.2.3")
	resp, err := client.Do(req)
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

func lifecycleGDSFallback(s ServerConfig, message string) error {
	if s.RCONPort <= 0 {
		return errors.New("RCON unavailable")
	}
	pass, err := readServerProperty(resolveServerDir(s), "rcon.password")
	if err != nil || strings.TrimSpace(pass) == "" {
		return errors.New("RCON unavailable")
	}
	msg := strings.NewReplacer("\r", " ", "\n", " ").Replace(message)
	if len(msg) > 900 {
		msg = msg[:900]
	}
	_, err = rconCommand("127.0.0.1", s.RCONPort, pass, "gds announce "+msg)
	return err
}

func notifyLifecycleDiscord(s ServerConfig, action string, sec int, message string) {
	go func() {
		if err := sendLifecycleDiscordNow(s, action, sec, message); err == nil {
			return
		}
		if err := lifecycleGDSFallback(s, message); err != nil {
			appendV4Event("warn", "server", s.ID, "Discord 카운트다운 알림 전달 실패", "Agent Discord 설정과 GDS/RCON 연결을 확인하세요")
		}
	}()
}

func lifecycleNotice(s ServerConfig, action string, sec int) {
	label := lifecycleActionLabel(action)
	var chat, discord string
	pitch := "1.2"
	switch {
	case action == "cancel":
		chat = "서버 종료/재시작 예약이 취소되었습니다."
		discord = "[서버 안내] 종료/재시작 예약이 취소되었습니다."
		pitch = "0.8"
	case sec > 0:
		chat = fmt.Sprintf("서버가 %d초 후 %s됩니다.", sec, label)
		discord = fmt.Sprintf("[서버 %s] %d초 후 서버가 %s됩니다.", label, sec, label)
		if sec <= 5 {
			pitch = "1.8"
		} else if sec <= 10 {
			pitch = "1.5"
		}
	default:
		chat = fmt.Sprintf("지금 서버를 %s합니다.", label)
		discord = fmt.Sprintf("[서버 %s] 지금 서버를 %s합니다.", label, label)
		pitch = "2.0"
	}

	// Discord delivery is independent from RCON. Newly added server profiles can
	// therefore receive lifecycle countdowns as soon as the Agent Discord config
	// is available, even when RCON is disabled or still starting.
	notifyLifecycleDiscord(s, action, sec, discord)

	pass, err := readServerProperty(resolveServerDir(s), "rcon.password")
	if err != nil || strings.TrimSpace(pass) == "" || s.RCONPort <= 0 {
		return
	}
	tellraw := fmt.Sprintf(`tellraw @a {"text":"[서버] ","color":"gold","bold":true,"extra":[{"text":%q,"color":"yellow","bold":false}]}`, chat)
	_, _ = rconCommand("127.0.0.1", s.RCONPort, pass, tellraw)
	_, _ = rconCommand("127.0.0.1", s.RCONPort, pass, "execute as @a at @s run playsound minecraft:block.note_block.pling master @s ~ ~ ~ 0.9 "+pitch)
}
