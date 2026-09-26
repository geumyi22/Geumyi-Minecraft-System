//go:build windows

package main

import (
	"fmt"
	"os"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

const gscServiceName = "Geumyi Server Center Host"

const (
	serviceStopped            = 1
	serviceStartPending       = 2
	serviceStopPending        = 3
	serviceRunning            = 4
	serviceAcceptStop         = 0x1
	serviceAcceptShutdown     = 0x4
	serviceControlStop        = 1
	serviceControlInterrogate = 4
	serviceControlShutdown    = 5
	serviceWin32OwnProcess    = 0x10
)

type serviceStatus struct {
	ServiceType             uint32
	CurrentState            uint32
	ControlsAccepted        uint32
	Win32ExitCode           uint32
	ServiceSpecificExitCode uint32
	CheckPoint              uint32
	WaitHint                uint32
}

type serviceTableEntry struct {
	Name *uint16
	Proc uintptr
}

var (
	advapi32GSC                      = syscall.NewLazyDLL("advapi32.dll")
	procStartServiceCtrlDispatcher   = advapi32GSC.NewProc("StartServiceCtrlDispatcherW")
	procRegisterServiceCtrlHandlerEx = advapi32GSC.NewProc("RegisterServiceCtrlHandlerExW")
	procSetServiceStatus             = advapi32GSC.NewProc("SetServiceStatus")
	serviceStatusHandle              uintptr
	serviceRunner                    func() error
	serviceLastStatus                serviceStatus
)

func serviceModeRequested() bool {
	for _, a := range os.Args[1:] {
		if strings.EqualFold(a, "--service") {
			return true
		}
	}
	return false
}

func runWindowsService(run func() error) error {
	serviceRunner = run
	name, _ := syscall.UTF16PtrFromString(gscServiceName)
	entries := []serviceTableEntry{{Name: name, Proc: syscall.NewCallback(serviceMainCallback)}, {}}
	r, _, e := procStartServiceCtrlDispatcher.Call(uintptr(unsafe.Pointer(&entries[0])))
	if r == 0 {
		return fmt.Errorf("StartServiceCtrlDispatcherW: %v", e)
	}
	return nil
}

func setSvcStatus(state uint32, accepted uint32, win32Code uint32, wait uint32) {
	if serviceStatusHandle == 0 {
		return
	}
	st := serviceStatus{ServiceType: serviceWin32OwnProcess, CurrentState: state, ControlsAccepted: accepted, Win32ExitCode: win32Code, WaitHint: wait}
	serviceLastStatus = st
	procSetServiceStatus.Call(serviceStatusHandle, uintptr(unsafe.Pointer(&st)))
}

func serviceMainCallback(argc uintptr, argv uintptr) uintptr {
	name, _ := syscall.UTF16PtrFromString(gscServiceName)
	serviceStatusHandle, _, _ = procRegisterServiceCtrlHandlerEx.Call(uintptr(unsafe.Pointer(name)), syscall.NewCallback(serviceControlHandler), 0)
	if serviceStatusHandle == 0 {
		return 0
	}
	setSvcStatus(serviceStartPending, 0, 0, 15000)
	setSvcStatus(serviceRunning, serviceAcceptStop|serviceAcceptShutdown, 0, 0)
	err := serviceRunner()
	code := uint32(0)
	if err != nil {
		code = 1
	}
	setSvcStatus(serviceStopped, 0, code, 0)
	return 0
}

func serviceControlHandler(control uintptr, eventType uintptr, eventData uintptr, context uintptr) uintptr {
	switch uint32(control) {
	case serviceControlStop, serviceControlShutdown:
		setSvcStatus(serviceStopPending, 0, 0, 15000)
		quitOnce.Do(func() { close(hostQuit) })
		go func() {
			time.Sleep(14 * time.Second)
			setSvcStatus(serviceStopped, 0, 0, 0)
		}()
	case serviceControlInterrogate:
		st := serviceLastStatus
		procSetServiceStatus.Call(serviceStatusHandle, uintptr(unsafe.Pointer(&st)))
	}
	return 0
}
