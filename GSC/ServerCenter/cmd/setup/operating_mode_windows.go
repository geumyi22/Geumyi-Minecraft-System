//go:build windows

package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"unicode/utf16"
	"unsafe"
)

const operatingModeName = "GMS_OperatingMode_v3.0.1.exe"
const recoveryInUse = "운영 모드 관리자의 중단된 작업을 복구하거나 기존 모드로 복원한 후 다시 실행하세요."

// Read only the identities needed to tell if Setup would invalidate v3's backup.
// A completed restore leaves a valid empty journal, which does not block updates.
func checkOperatingModeJournal(path string, fullSetup, replacesLegacyTasks bool) error {
	f, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return errors.New("운영 모드 복구 기록의 접근 권한을 확인하세요.")
	}
	defer f.Close()
	stat, err := f.Stat()
	if err != nil || !stat.Mode().IsRegular() || stat.Size() > 64<<20 {
		return errors.New("운영 모드 복구 기록을 확인할 수 없습니다.")
	}
	var j struct {
		Schema  int
		Sid     string
		Pending *string
		Owned   []struct{ Kind, Id string }
	}
	b, err := io.ReadAll(io.LimitReader(f, (64<<20)+1))
	if err != nil || len(b) > 64<<20 || json.Unmarshal(b, &j) != nil || j.Schema != 3 || j.Pending == nil || j.Owned == nil {
		return errors.New("운영 모드 복구 기록을 확인할 수 없습니다. 관리자에서 백업 상태를 확인하세요.")
	}
	if *j.Pending != "" {
		return errors.New(recoveryInUse)
	}
	for _, e := range j.Owned {
		if e.Kind == "Service" && strings.EqualFold(e.Id, hostServiceName) {
			return errors.New(recoveryInUse)
		}
		if e.Kind == "Task" {
			names := []string{hostTaskName, "Geumyi Server Host"}
			if fullSetup && replacesLegacyTasks {
				names = legacyTaskNames()
			}
			for _, name := range names {
				if strings.EqualFold(e.Id, `\`+name) {
					return errors.New(recoveryInUse)
				}
			}
		}
		if fullSetup && e.Kind == "Run" {
			// v3 Id stores hive/view/key/name/physical key in UTF-16 Base64.
			parts := strings.Split(e.Id, "|")
			if len(parts) != 5 {
				return errors.New(recoveryInUse)
			}
			fields := make([]string, 4)
			for i := range fields {
				raw, err := base64.StdEncoding.DecodeString(parts[i])
				if err != nil || len(raw)%2 != 0 {
					return errors.New(recoveryInUse)
				}
				units := make([]uint16, len(raw)/2)
				for n := range units {
					units[n] = binary.LittleEndian.Uint16(raw[n*2:])
				}
				fields[i] = string(utf16.Decode(units))
			}
			if fields[0] == "HKCU" && fields[2] == "Run" && strings.EqualFold(fields[3], "Geumyi Server Center") {
				token, err := syscall.OpenCurrentProcessToken()
				if err != nil {
					return errors.New(recoveryInUse)
				}
				user, err := token.GetTokenUser()
				token.Close()
				if err != nil {
					return errors.New(recoveryInUse)
				}
				sid, err := user.User.Sid.String()
				if err != nil || j.Sid == "" || strings.EqualFold(j.Sid, sid) {
					return errors.New(recoveryInUse)
				}
			}
		}
	}
	return nil
}

func operatingModeJournalPath() string {
	return filepath.Join(envOr("ProgramFiles", `C:\Program Files`), "GMS Operating Mode Recovery v3", "current.json")
}

// v3 holds this same mutex across each change. Keep it for the install/update
// so that a new transition cannot start after the journal preflight.
func guardOperatingMode(fullSetup, replacesLegacyTasks bool) (func(), error) {
	kernel := syscall.NewLazyDLL("kernel32.dll")
	name, _ := syscall.UTF16PtrFromString(`Global\GMS-OperatingMode-v1`)
	runtime.LockOSThread()
	h, _, _ := kernel.NewProc("CreateMutexW").Call(0, 0, uintptr(unsafe.Pointer(name)))
	if h == 0 {
		runtime.UnlockOSThread()
		return nil, errors.New("GMS 운영 모드의 작업 잠금을 확인할 수 없습니다.")
	}
	handle := syscall.Handle(h)
	state, err := syscall.WaitForSingleObject(handle, 0)
	if err != nil || (state != syscall.WAIT_OBJECT_0 && state != syscall.WAIT_ABANDONED) {
		syscall.CloseHandle(handle)
		runtime.UnlockOSThread()
		return nil, errors.New("기존 운영 모드 창이나 진행 중인 전환이 있습니다. 작업을 마치고 다시 시도하세요.")
	}
	release := func() { kernel.NewProc("ReleaseMutex").Call(h); syscall.CloseHandle(handle); runtime.UnlockOSThread() }
	if err := checkOperatingModeJournal(operatingModeJournalPath(), fullSetup, replacesLegacyTasks); err != nil {
		release()
		return nil, err
	}
	return release, nil
}

func modePayloadFor(target string) (candidate, original []byte, err error) {
	candidate, err = payload.ReadFile("payload/" + operatingModeName)
	if err != nil || len(candidate) < 100000 {
		return nil, nil, errors.New("운영 모드 설치 파일을 확인할 수 없습니다.")
	}
	info, err := os.Lstat(target)
	if errors.Is(err, os.ErrNotExist) {
		return candidate, nil, nil
	}
	if err != nil || !info.Mode().IsRegular() || info.Size() > 8<<20 {
		return nil, nil, errors.New("운영 모드 설치 대상 경로가 예상과 다릅니다.")
	}
	original, err = os.ReadFile(target)
	if err != nil {
		return nil, nil, err
	}
	return candidate, original, nil
}

func writeModeAtomically(target string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
		return err
	}
	file, err := os.CreateTemp(filepath.Dir(target), ".gsc-mode-*.tmp")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	_, err = file.Write(data)
	if err == nil {
		err = file.Sync()
	}
	closeErr := file.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(file.Name(), target)
}

// Preserve a differently built standalone image before installing the bundled version.
// A sharing violation (e.g. an open older manager) leaves its EXE in place.
func installOperatingMode(installDir, dataDir string) error {
	target := filepath.Join(installDir, operatingModeName)
	candidate, original, err := modePayloadFor(target)
	if err != nil || bytes.Equal(candidate, original) {
		return err
	}
	if original != nil {
		sum := sha256.Sum256(original)
		backup := filepath.Join(dataDir, "Backups", "OperatingMode", fmt.Sprintf("%x.exe.bak", sum))
		prev, readErr := os.ReadFile(backup)
		switch {
		case errors.Is(readErr, os.ErrNotExist):
			if err = writeModeAtomically(backup, original); err != nil {
				return err
			}
		case readErr != nil || !bytes.Equal(prev, original):
			return errors.New("기존 운영 모드 EXE의 백업을 확인하지 못했습니다.")
		}
	}
	return writeModeAtomically(target, candidate)
}
