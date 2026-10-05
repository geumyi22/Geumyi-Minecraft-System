//go:build windows

package main

import (
	"fmt"
	"path/filepath"
	"syscall"
	"unsafe"
)

const (
	invalidSessionID        = 0xffffffff
	createUnicodeEnvironment = 0x00000400
	logonWithProfile         = 0x00000001
)

type startupInfoW struct {
	Cb            uint32
	LpReserved    *uint16
	LpDesktop     *uint16
	LpTitle       *uint16
	DwX           uint32
	DwY           uint32
	DwXSize       uint32
	DwYSize       uint32
	DwXCountChars uint32
	DwYCountChars uint32
	DwFillAttribute uint32
	DwFlags       uint32
	WShowWindow   uint16
	CbReserved2   uint16
	LpReserved2   *byte
	HStdInput     syscall.Handle
	HStdOutput    syscall.Handle
	HStdError     syscall.Handle
}

type processInformationW struct {
	HProcess    syscall.Handle
	HThread     syscall.Handle
	ProcessID   uint32
	ThreadID    uint32
}

type interactiveLaunchResult struct {
	SessionID uint32
	PID       uint32
	Method    string
}

var (
	kernel32Interactive = syscall.NewLazyDLL("kernel32.dll")
	wtsapi32Interactive = syscall.NewLazyDLL("wtsapi32.dll")
	userenvInteractive  = syscall.NewLazyDLL("userenv.dll")
	advapi32Interactive = syscall.NewLazyDLL("advapi32.dll")

	pGetActiveConsoleSessionID = kernel32Interactive.NewProc("WTSGetActiveConsoleSessionId")
	pCloseHandleInteractive    = kernel32Interactive.NewProc("CloseHandle")
	pWTSQueryUserToken         = wtsapi32Interactive.NewProc("WTSQueryUserToken")
	pCreateEnvironmentBlock    = userenvInteractive.NewProc("CreateEnvironmentBlock")
	pDestroyEnvironmentBlock   = userenvInteractive.NewProc("DestroyEnvironmentBlock")
	pCreateProcessAsUserW      = advapi32Interactive.NewProc("CreateProcessAsUserW")
	pCreateProcessWithTokenW   = advapi32Interactive.NewProc("CreateProcessWithTokenW")
)

func winCallErr(name string, r1 uintptr, e error) error {
	if r1 != 0 {
		return nil
	}
	if e != nil && e != syscall.Errno(0) {
		return fmt.Errorf("%s failed: %w", name, e)
	}
	return fmt.Errorf("%s failed", name)
}

func activeInteractiveSessionID() (uint32, error) {
	r1, _, _ := pGetActiveConsoleSessionID.Call()
	sessionID := uint32(r1)
	if sessionID == invalidSessionID {
		return 0, fmt.Errorf("no active interactive Windows session")
	}
	return sessionID, nil
}

// launchClientInInteractiveSession starts the desktop client in the currently
// active console user's session instead of inheriting the Windows service's
// Session 0. The self-update helper runs as LocalSystem, so directly using
// exec.Command would create an invisible client in Session 0.
func launchClientInInteractiveSession(exePath string) (interactiveLaunchResult, error) {
	var out interactiveLaunchResult
	sessionID, err := activeInteractiveSessionID()
	if err != nil {
		return out, err
	}
	out.SessionID = sessionID

	var token syscall.Handle
	r1, _, e1 := pWTSQueryUserToken.Call(
		uintptr(sessionID),
		uintptr(unsafe.Pointer(&token)),
	)
	if err := winCallErr("WTSQueryUserToken", r1, e1); err != nil {
		return out, err
	}
	defer pCloseHandleInteractive.Call(uintptr(token))

	var environment uintptr
	r1, _, e1 = pCreateEnvironmentBlock.Call(
		uintptr(unsafe.Pointer(&environment)),
		uintptr(token),
		0,
	)
	if err := winCallErr("CreateEnvironmentBlock", r1, e1); err != nil {
		return out, err
	}
	defer pDestroyEnvironmentBlock.Call(environment)

	app, err := syscall.UTF16PtrFromString(exePath)
	if err != nil {
		return out, fmt.Errorf("client executable path is invalid: %w", err)
	}
	desktop, _ := syscall.UTF16PtrFromString("winsta0\\default")
	currentDir, err := syscall.UTF16PtrFromString(filepath.Dir(exePath))
	if err != nil {
		return out, fmt.Errorf("client working directory is invalid: %w", err)
	}

	si := startupInfoW{
		Cb:        uint32(unsafe.Sizeof(startupInfoW{})),
		LpDesktop: desktop,
	}
	var pi processInformationW

	r1, _, e1 = pCreateProcessAsUserW.Call(
		uintptr(token),
		uintptr(unsafe.Pointer(app)),
		0,
		0,
		0,
		0,
		createUnicodeEnvironment,
		environment,
		uintptr(unsafe.Pointer(currentDir)),
		uintptr(unsafe.Pointer(&si)),
		uintptr(unsafe.Pointer(&pi)),
	)
	if r1 != 0 {
		out.PID = pi.ProcessID
		out.Method = "CreateProcessAsUserW"
		pCloseHandleInteractive.Call(uintptr(pi.HThread))
		pCloseHandleInteractive.Call(uintptr(pi.HProcess))
		return out, nil
	}

	firstErr := e1
	pi = processInformationW{}
	r1, _, e1 = pCreateProcessWithTokenW.Call(
		uintptr(token),
		logonWithProfile,
		uintptr(unsafe.Pointer(app)),
		0,
		createUnicodeEnvironment,
		environment,
		uintptr(unsafe.Pointer(currentDir)),
		uintptr(unsafe.Pointer(&si)),
		uintptr(unsafe.Pointer(&pi)),
	)
	if r1 == 0 {
		if firstErr == nil || firstErr == syscall.Errno(0) {
			firstErr = fmt.Errorf("CreateProcessAsUserW failed")
		}
		if e1 != nil && e1 != syscall.Errno(0) {
			return out, fmt.Errorf("interactive client launch failed: CreateProcessAsUserW: %v; CreateProcessWithTokenW: %w", firstErr, e1)
		}
		return out, fmt.Errorf("interactive client launch failed: CreateProcessAsUserW: %v; CreateProcessWithTokenW failed", firstErr)
	}

	out.PID = pi.ProcessID
	out.Method = "CreateProcessWithTokenW"
	pCloseHandleInteractive.Call(uintptr(pi.HThread))
	pCloseHandleInteractive.Call(uintptr(pi.HProcess))
	return out, nil
}
