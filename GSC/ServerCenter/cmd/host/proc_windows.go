//go:build windows

package main

import (
	"encoding/binary"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

func hideProcess(c *exec.Cmd) {
	if c.SysProcAttr == nil {
		c.SysProcAttr = &syscall.SysProcAttr{}
	}
	c.SysProcAttr.HideWindow = true
	c.SysProcAttr.CreationFlags |= 0x08000000
}
func shellCommand(line string) *exec.Cmd {
	shell := os.Getenv("ComSpec")
	if shell == "" {
		shell = filepath.Join(os.Getenv("SystemRoot"), "System32", "cmd.exe")
	}
	c := exec.Command(shell)
	hideProcess(c)
	// cmd.exe does not implement CommandLineToArgvW. Do not let os/exec insert backslash-escaped quotes.
	c.SysProcAttr.CmdLine = `"` + shell + `" /D /V:OFF /S /C "` + line + `"`
	return c
}

func killProcessTree(pid int) error {
	c := exec.Command("taskkill.exe", "/PID", fmt.Sprintf("%d", pid), "/T", "/F")
	hideProcess(c)
	if out, err := c.CombinedOutput(); err != nil {
		return fmt.Errorf("start.bat 프로세스 트리 종료 실패: %w %s", err, string(out))
	}
	return nil
}

type processWatch struct {
	handle syscall.Handle
	pid    int
}

func watchPID(pid int) (*processWatch, error) {
	h, e := syscall.OpenProcess(0x00100000|0x1000, false, uint32(pid))
	if e != nil {
		return nil, e
	}
	return &processWatch{handle: h, pid: pid}, nil
}
func (p *processWatch) alive() bool {
	if p == nil {
		return false
	}
	code, e := syscall.WaitForSingleObject(p.handle, 0)
	return e != nil || code == 258
}
func (p *processWatch) close() {
	if p != nil {
		syscall.CloseHandle(p.handle)
	}
}
func (p *processWatch) pidValue() int {
	if p == nil {
		return 0
	}
	return p.pid
}

var tcpTable = syscall.NewLazyDLL("iphlpapi.dll").NewProc("GetExtendedTcpTable")

func listenerPID(port int) (int, bool) {
	if port <= 0 {
		return 0, false
	}
	for _, family := range []uint32{2, 23} {
		var size uint32
		tcpTable.Call(0, uintptr(unsafe.Pointer(&size)), 0, uintptr(family), 3, 0)
		if size < 4 {
			continue
		}
		buf := make([]byte, size)
		rc, _, _ := tcpTable.Call(uintptr(unsafe.Pointer(&buf[0])), uintptr(unsafe.Pointer(&size)), 0, uintptr(family), 3, 0)
		if rc != 0 {
			continue
		}
		stride, po, so, pi := 24, 8, 0, 20
		if family == 23 {
			// MIB_TCP6ROW_OWNER_PID: localPort=20, state=48, owningPid=52.
			stride, po, so, pi = 56, 20, 48, 52
		}
		count := int(binary.LittleEndian.Uint32(buf[:4]))
		for i := 0; i < count; i++ {
			off := 4 + i*stride
			if off+stride > len(buf) {
				break
			}
			row := buf[off : off+stride]
			state := binary.LittleEndian.Uint32(row[so : so+4])
			if state == 2 && int(binary.BigEndian.Uint16(row[po:po+2])) == port {
				return int(binary.LittleEndian.Uint32(row[pi : pi+4])), true
			}
		}
	}
	return 0, false
}

func nativeTCPListener(port int) bool {
	_, ok := listenerPID(port)
	return ok
}

type processMemoryCountersEx struct {
	Cb                         uint32
	PageFaultCount             uint32
	PeakWorkingSetSize         uintptr
	WorkingSetSize             uintptr
	QuotaPeakPagedPoolUsage    uintptr
	QuotaPagedPoolUsage        uintptr
	QuotaPeakNonPagedPoolUsage uintptr
	QuotaNonPagedPoolUsage     uintptr
	PagefileUsage              uintptr
	PeakPagefileUsage          uintptr
	PrivateUsage               uintptr
}

var (
	psapiDLL             = syscall.NewLazyDLL("psapi.dll")
	getProcessMemoryInfo = psapiDLL.NewProc("GetProcessMemoryInfo")
	kernel32DLL          = syscall.NewLazyDLL("kernel32.dll")
	getProcessHandleCnt  = kernel32DLL.NewProc("GetProcessHandleCount")
)

func nativeJavaStats(port int) (JavaStats, bool) {
	pid, ok := listenerPID(port)
	if !ok || pid <= 0 {
		return JavaStats{}, false
	}
	out := JavaStats{PID: pid}
	h, err := syscall.OpenProcess(0x0400|0x0010, false, uint32(pid)) // QUERY_INFORMATION | VM_READ
	if err != nil {
		return out, true
	}
	defer syscall.CloseHandle(h)
	var pm processMemoryCountersEx
	pm.Cb = uint32(unsafe.Sizeof(pm))
	if r, _, _ := getProcessMemoryInfo.Call(uintptr(h), uintptr(unsafe.Pointer(&pm)), uintptr(pm.Cb)); r != 0 {
		out.WorkingSetMB = float64(pm.WorkingSetSize) / (1024 * 1024)
		out.PrivateMB = float64(pm.PrivateUsage) / (1024 * 1024)
	}
	var handles uint32
	if r, _, _ := getProcessHandleCnt.Call(uintptr(h), uintptr(unsafe.Pointer(&handles))); r != 0 {
		out.Handles = int(handles)
	}
	fillNativeProcessTimes(h, &out)
	out.Threads = processThreadCount(pid)
	return out, true
}

// uniqueListenerOwner rejects invalid or conflicting PIDs from the OS-provided
// listener-only TCP owner table. Repeated rows from the same PID are permitted.
func uniqueListenerOwner(previous, candidate int) (int, error) {
	if candidate <= 0 {
		return 0, fmt.Errorf("TCP listener owner PID not available")
	}
	if previous != 0 && previous != candidate {
		return 0, fmt.Errorf("conflicting TCP listener owner PIDs")
	}
	return candidate, nil
}

// portPID is used for lifecycle tracking and explicit force-stop targeting.
// TCP_TABLE_OWNER_PID_LISTENER (class 3) is a listener-only API by contract.
// Do not require dwState == 2 here: the operator's Windows Insider build
// returned native state 0 even for self-owned, verified loopback listeners.
// Reject unknown and conflicting owners instead of returning the first PID.
func portPID(port int) (int, error) {
	if port <= 0 || port > 65535 {
		return 0, fmt.Errorf("invalid TCP port")
	}
	owner := 0
	for _, family := range []uint32{2, 23} {
		var size uint32
		tcpTable.Call(0, uintptr(unsafe.Pointer(&size)), 0, uintptr(family), 3, 0)
		if size < 4 {
			continue
		}
		buf := make([]byte, size)
		rc, _, _ := tcpTable.Call(uintptr(unsafe.Pointer(&buf[0])), uintptr(unsafe.Pointer(&size)), 0, uintptr(family), 3, 0)
		if rc != 0 {
			continue
		}
		stride, po, pi := 24, 8, 20
		if family == 23 {
			stride, po, pi = 56, 20, 52
		}
		count := int(binary.LittleEndian.Uint32(buf[:4]))
		for i := 0; i < count; i++ {
			off := 4 + i*stride
			if off+stride > len(buf) {
				break
			}
			row := buf[off : off+stride]
			if int(binary.BigEndian.Uint16(row[po:po+2])) != port {
				continue
			}
			pid := int(binary.LittleEndian.Uint32(row[pi : pi+4]))
			var err error
			owner, err = uniqueListenerOwner(owner, pid)
			if err != nil {
				return 0, fmt.Errorf("port %d: %w", port, err)
			}
		}
	}
	if owner > 0 {
		return owner, nil
	}
	return 0, fmt.Errorf("포트 %d의 프로세스를 확인하지 못했습니다", port)
}

var udpTable = syscall.NewLazyDLL("iphlpapi.dll").NewProc("GetExtendedUdpTable")

func nativeUDPListener(port int) bool {
	if port <= 0 {
		return false
	}
	for _, family := range []uint32{2, 23} {
		var size uint32
		udpTable.Call(0, uintptr(unsafe.Pointer(&size)), 0, uintptr(family), 1, 0) // UDP_TABLE_OWNER_PID
		if size < 4 {
			continue
		}
		buf := make([]byte, size)
		rc, _, _ := udpTable.Call(uintptr(unsafe.Pointer(&buf[0])), uintptr(unsafe.Pointer(&size)), 0, uintptr(family), 1, 0)
		if rc != 0 {
			continue
		}
		stride, portOff := 12, 4
		if family == 23 {
			// MIB_UDP6ROW_OWNER_PID: addr[16], scope(4), localPort(4), pid(4).
			stride, portOff = 28, 20
		}
		count := int(binary.LittleEndian.Uint32(buf[:4]))
		for i := 0; i < count; i++ {
			off := 4 + i*stride
			if off+stride > len(buf) {
				break
			}
			row := buf[off : off+stride]
			if int(binary.BigEndian.Uint16(row[portOff:portOff+2])) == port {
				return true
			}
		}
	}
	return false
}

type winFiletime struct {
	LowDateTime  uint32
	HighDateTime uint32
}

type memoryStatusEx struct {
	Length               uint32
	MemoryLoad           uint32
	TotalPhys            uint64
	AvailPhys            uint64
	TotalPageFile        uint64
	AvailPageFile        uint64
	TotalVirtual         uint64
	AvailVirtual         uint64
	AvailExtendedVirtual uint64
}

type threadEntry32 struct {
	Size           uint32
	Usage          uint32
	ThreadID       uint32
	OwnerProcessID uint32
	BasePri        int32
	DeltaPri       int32
	Flags          uint32
}

var (
	globalMemoryStatusEx = kernel32DLL.NewProc("GlobalMemoryStatusEx")
	getDiskFreeSpaceExW  = kernel32DLL.NewProc("GetDiskFreeSpaceExW")
	getTickCount64       = kernel32DLL.NewProc("GetTickCount64")
	getSystemTimes       = kernel32DLL.NewProc("GetSystemTimes")
	getProcessTimes      = kernel32DLL.NewProc("GetProcessTimes")
	createToolhelp32Snap = kernel32DLL.NewProc("CreateToolhelp32Snapshot")
	thread32First        = kernel32DLL.NewProc("Thread32First")
	thread32Next         = kernel32DLL.NewProc("Thread32Next")
	cpuSampleMu          sync.Mutex
	cpuLastIdle          uint64
	cpuLastKernel        uint64
	cpuLastUser          uint64
	cpuHaveSample        bool
)

func filetimeTicks(ft winFiletime) uint64 {
	return uint64(ft.HighDateTime)<<32 | uint64(ft.LowDateTime)
}

func nativeCPUPercent() float64 {
	var idle, kernel, user winFiletime
	ok, _, _ := getSystemTimes.Call(
		uintptr(unsafe.Pointer(&idle)),
		uintptr(unsafe.Pointer(&kernel)),
		uintptr(unsafe.Pointer(&user)),
	)
	if ok == 0 {
		return 0
	}
	i, k, u := filetimeTicks(idle), filetimeTicks(kernel), filetimeTicks(user)
	cpuSampleMu.Lock()
	defer cpuSampleMu.Unlock()
	if !cpuHaveSample {
		cpuLastIdle, cpuLastKernel, cpuLastUser = i, k, u
		cpuHaveSample = true
		return 0
	}
	di, dk, du := i-cpuLastIdle, k-cpuLastKernel, u-cpuLastUser
	cpuLastIdle, cpuLastKernel, cpuLastUser = i, k, u
	total := dk + du
	if total == 0 || di > total {
		return 0
	}
	v := 100 * float64(total-di) / float64(total)
	if v < 0 {
		return 0
	}
	if v > 100 {
		return 100
	}
	return v
}

func nativeHostStats() (HostStats, bool) {
	h := HostStats{}
	okAny := false

	var mem memoryStatusEx
	mem.Length = uint32(unsafe.Sizeof(mem))
	if r, _, _ := globalMemoryStatusEx.Call(uintptr(unsafe.Pointer(&mem))); r != 0 && mem.TotalPhys > 0 {
		h.RAMTotalGB = float64(mem.TotalPhys) / 1073741824
		h.RAMUsedGB = float64(mem.TotalPhys-mem.AvailPhys) / 1073741824
		okAny = true
	}

	root := os.Getenv("SystemDrive")
	if root == "" {
		root = `C:`
	}
	root += `\`
	if ptr, err := syscall.UTF16PtrFromString(root); err == nil {
		var avail, total, free uint64
		if r, _, _ := getDiskFreeSpaceExW.Call(
			uintptr(unsafe.Pointer(ptr)),
			uintptr(unsafe.Pointer(&avail)),
			uintptr(unsafe.Pointer(&total)),
			uintptr(unsafe.Pointer(&free)),
		); r != 0 && total > 0 {
			h.DiskFreeGB = float64(avail) / 1073741824
			h.DiskTotalGB = float64(total) / 1073741824
			okAny = true
		}
	}

	ms, _, _ := getTickCount64.Call()
	if ms > 0 {
		h.Uptime = formatDuration(time.Duration(uint64(ms)) * time.Millisecond)
		okAny = true
	}
	h.CPUPercent = nativeCPUPercent()
	return h, okAny
}

func processThreadCount(pid int) int {
	const th32csSnapThread = 0x00000004
	h, _, _ := createToolhelp32Snap.Call(th32csSnapThread, 0)
	if h == 0 || h == ^uintptr(0) {
		return 0
	}
	defer syscall.CloseHandle(syscall.Handle(h))
	var e threadEntry32
	e.Size = uint32(unsafe.Sizeof(e))
	r, _, _ := thread32First.Call(h, uintptr(unsafe.Pointer(&e)))
	count := 0
	for r != 0 {
		if int(e.OwnerProcessID) == pid {
			count++
		}
		r, _, _ = thread32Next.Call(h, uintptr(unsafe.Pointer(&e)))
	}
	return count
}

func fillNativeProcessTimes(h syscall.Handle, out *JavaStats) {
	var create, exit, kernel, user winFiletime
	if r, _, _ := getProcessTimes.Call(
		uintptr(h),
		uintptr(unsafe.Pointer(&create)),
		uintptr(unsafe.Pointer(&exit)),
		uintptr(unsafe.Pointer(&kernel)),
		uintptr(unsafe.Pointer(&user)),
	); r == 0 {
		return
	}
	out.CPUSeconds = float64(filetimeTicks(kernel)+filetimeTicks(user)) / 1e7
	const windowsToUnix100ns = uint64(116444736000000000)
	ct := filetimeTicks(create)
	if ct > windowsToUnix100ns {
		u := ct - windowsToUnix100ns
		sec := int64(u / 1e7)
		nsec := int64(u%1e7) * 100
		out.StartTime = time.Unix(sec, nsec).UTC().Format(time.RFC3339)
	}
}
