//go:build windows

package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

const operatingModeFile = "GMS_OperatingMode_v3.0.1.exe"

// The release build binds the Client to the sibling included by that same Setup.
var operatingModeSHA256 string

type operatingModeStatus struct {
	Available       bool   `json:"available"`
	Version         string `json:"version"`
	Message         string `json:"message,omitempty"`
	HostStartType   string `json:"host_start_type"`
	ClientAutoStart string `json:"client_autostart"`
}

func verifiedOperatingMode(client, expected string) (*os.File, error) {
	if len(expected) != sha256.Size*2 {
		return nil, errors.New("이 Client 빌드에 운영 모드 관리자 검증 정보가 없습니다. 5.2.0 Setup으로 설치하세요.")
	}
	path := filepath.Join(filepath.Dir(client), operatingModeFile)
	name, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		return nil, err
	}
	// Hold a read-only handle without write/delete sharing until CreateProcess returns.
	handle, err := syscall.CreateFile(name, syscall.GENERIC_READ, syscall.FILE_SHARE_READ, nil, syscall.OPEN_EXISTING, syscall.FILE_FLAG_OPEN_REPARSE_POINT, 0)
	if err != nil {
		return nil, errors.New("운영 모드 EXE를 읽을 수 없습니다. 같은 릴리스의 EXE를 Client 옆에 두거나 Setup으로 설치하세요.")
	}
	f := os.NewFile(uintptr(handle), path)
	var info syscall.ByHandleFileInformation
	if syscall.GetFileInformationByHandle(handle, &info) != nil || info.FileAttributes&(syscall.FILE_ATTRIBUTE_REPARSE_POINT|syscall.FILE_ATTRIBUTE_DIRECTORY) != 0 || info.FileSizeHigh != 0 || info.FileSizeLow > 8<<20 {
		f.Close()
		return nil, errors.New("운영 모드 EXE의 파일 형식을 확인할 수 없습니다.")
	}
	hash := sha256.New()
	if _, err = io.Copy(hash, f); err != nil || !strings.EqualFold(hex.EncodeToString(hash.Sum(nil)), expected) {
		f.Close()
		return nil, errors.New("운영 모드 EXE와 이 Client의 배포본이 일치하지 않습니다. 같은 릴리스의 파일을 사용하세요.")
	}
	return f, nil
}

func operatingModeStatusAPI(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		w.WriteHeader(http.StatusMethodNotAllowed)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "GET 요청이 필요합니다."})
		return
	}
	client, err := os.Executable()
	result := operatingModeStatus{Version: "3.0.1", HostStartType: hostStartType(), ClientAutoStart: "unknown"}
	if err == nil {
		result.ClientAutoStart = clientRunState(client)
		var image *os.File
		image, err = verifiedOperatingMode(client, operatingModeSHA256)
		if err == nil {
			result.Available = true
			image.Close()
		}
	}
	if err != nil {
		result.Message = err.Error()
	}
	_ = json.NewEncoder(w).Encode(result)
}

type operatingModeView int

const (
	modeHome operatingModeView = iota
	modeManualReview
	modeRestoreReview
)

func parseOperatingView(body []byte) (operatingModeView, bool) {
	var compact bytes.Buffer
	if json.Compact(&compact, body) != nil {
		return modeHome, false
	}
	switch compact.String() {
	case "{}":
		return modeHome, true
	case `{"view":"manual"}`:
		return modeManualReview, true
	case `{"view":"restore"}`:
		return modeRestoreReview, true
	}
	return modeHome, false
}

func operatingModeOpenHandler(open func(operatingModeView) error) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		fail := func(status int, message string) {
			w.WriteHeader(status)
			_ = json.NewEncoder(w).Encode(map[string]any{"ok": false, "error": message})
		}
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			fail(http.StatusMethodNotAllowed, "POST 요청이 필요합니다.")
			return
		}
		if r.Header.Get("X-GSC-Intent") != "open-operating-mode" {
			fail(http.StatusForbidden, "관리 화면에서 실행을 선택하세요.")
			return
		}
		media, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
		if err != nil || media != "application/json" {
			fail(http.StatusUnsupportedMediaType, "JSON 요청이 필요합니다.")
			return
		}
		body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 256))
		view, ok := parseOperatingView(body)
		if err != nil || !ok {
			fail(http.StatusBadRequest, "지원하는 운영 모드 화면을 선택하세요.")
			return
		}
		if err := open(view); err != nil {
			fail(http.StatusConflict, err.Error())
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]bool{"ok": true})
	}
}

func tokenElevated(t syscall.Token) (bool, error) {
	var elevated, returned uint32
	err := syscall.GetTokenInformation(t, syscall.TokenElevation, (*byte)(unsafe.Pointer(&elevated)), 4, &returned)
	return elevated != 0, err
}

// Even when Setup or an operator opened the Client elevated, the manager's
// first window must use the user's normal token. Only its own GUI requests UAC.
func openOperatingMode(view operatingModeView) error {
	client, err := os.Executable()
	if err != nil {
		return err
	}
	exe, err := verifiedOperatingMode(client, operatingModeSHA256)
	if err != nil {
		return err
	}
	defer exe.Close()
	var cmd *exec.Cmd
	switch view {
	case modeHome:
		cmd = exec.Command(exe.Name())
	case modeManualReview:
		cmd = exec.Command(exe.Name(), "--review-manual")
	case modeRestoreReview:
		cmd = exec.Command(exe.Name(), "--review-restore")
	default:
		return errors.New("지원하지 않는 운영 모드 화면입니다.")
	}
	cmd.Dir = filepath.Dir(client)
	token, err := syscall.OpenCurrentProcessToken()
	if err != nil {
		return errors.New("현재 Windows 계정의 권한을 확인하지 못했습니다.")
	}
	defer token.Close()
	elevated, err := tokenElevated(token)
	if err != nil {
		return errors.New("현재 Windows 권한을 확인하지 못했습니다.")
	}
	if elevated {
		var limited syscall.Token
		var returned uint32
		err = syscall.GetTokenInformation(token, syscall.TokenLinkedToken, (*byte)(unsafe.Pointer(&limited)), uint32(unsafe.Sizeof(limited)), &returned)
		if err != nil || limited == 0 {
			return errors.New("GSC를 일반 권한으로 다시 열거나 운영 모드 EXE를 직접 실행하세요.")
		}
		defer limited.Close()
		if high, err := tokenElevated(limited); high || err != nil {
			return errors.New("같은 계정의 일반 권한을 확인하지 못했습니다.")
		}
		cmd.SysProcAttr = &syscall.SysProcAttr{Token: limited}
	}
	if err = cmd.Start(); err != nil {
		return fmt.Errorf("일반 권한으로 운영 모드 관리자를 열지 못했습니다. EXE를 직접 열어 주세요. %w", err)
	}
	return cmd.Process.Release()
}
