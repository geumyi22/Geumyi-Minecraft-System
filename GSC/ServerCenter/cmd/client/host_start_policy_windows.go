//go:build windows

package main

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
	"unicode/utf16"
	"unsafe"
)

const hostServiceKey = `SYSTEM\CurrentControlSet\Services\Geumyi Server Center Host`

func modeRegistryValue(root syscall.Handle, path, name string) (uint32, []byte, error) {
	var k syscall.Handle
	if err := syscall.RegOpenKeyEx(root, wptr(path), 0, syscall.KEY_QUERY_VALUE, &k); err != nil {
		return 0, nil, err
	}
	defer syscall.RegCloseKey(k)
	var size, kind uint32
	if err := syscall.RegQueryValueEx(k, wptr(name), nil, &kind, nil, &size); err != nil {
		return 0, nil, err
	}
	if size == 0 || size > 64<<10 {
		return 0, nil, errors.New("unexpected registry value size")
	}
	buf := make([]byte, size)
	if err := syscall.RegQueryValueEx(k, wptr(name), nil, &kind, &buf[0], &size); err != nil {
		return 0, nil, err
	}
	return kind, buf[:size], nil
}

func hostStartType() string {
	kind, buf, err := modeRegistryValue(syscall.HKEY_LOCAL_MACHINE, hostServiceKey, "Start")
	if errors.Is(err, syscall.ERROR_FILE_NOT_FOUND) {
		return "missing"
	}
	if err != nil || kind != syscall.REG_DWORD || len(buf) != 4 {
		return "unknown"
	}
	imageKind, image, err := modeRegistryValue(syscall.HKEY_LOCAL_MACHINE, hostServiceKey, "ImagePath")
	if err != nil || (imageKind != syscall.REG_SZ && imageKind != syscall.REG_EXPAND_SZ) {
		return "unknown"
	}
	host, config := installedHostPaths()
	if !strings.EqualFold(strings.TrimSpace(strings.TrimRight(utf16LE(image), "\x00")), `"`+host+`" --service --config "`+config+`"`) || host == "" {
		return "unknown"
	}
	switch binary.LittleEndian.Uint32(buf) {
	case 2:
		kind, buf, err = modeRegistryValue(syscall.HKEY_LOCAL_MACHINE, hostServiceKey, "DelayedAutoStart")
		if errors.Is(err, syscall.ERROR_FILE_NOT_FOUND) {
			return "automatic"
		}
		if err != nil || kind != syscall.REG_DWORD || len(buf) != 4 {
			return "unknown"
		}
		if binary.LittleEndian.Uint32(buf) != 0 {
			return "delayed-automatic"
		}
		return "automatic"
	case 3:
		return "manual"
	case 4:
		return "disabled"
	}
	return "unknown"
}

// Setup persists its actual install location in HKLM, including custom roots.
func installedHostPaths() (string, string) {
	dir := filepath.Join(os.Getenv("ProgramFiles"), "Geumyi Server Center")
	kind, raw, err := modeRegistryValue(syscall.HKEY_LOCAL_MACHINE, `SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\GeumyiServerCenter`, "InstallLocation")
	if err == nil && kind == syscall.REG_SZ {
		dir = strings.TrimRight(utf16LE(raw), "\x00")
	}
	host := filepath.Join(dir, "GeumyiServerHost.exe")
	cfg := filepath.Join(os.Getenv("ProgramData"), "GeumyiServerCenter", "server.json")
	if !filepath.IsAbs(host) || !filepath.IsAbs(cfg) {
		return "", ""
	}
	for _, path := range []string{host, cfg} {
		st, err := os.Stat(path)
		if err != nil || !st.Mode().IsRegular() {
			return "", ""
		}
	}
	return host, cfg
}

func utf16LE(buf []byte) string {
	if len(buf)%2 != 0 {
		return ""
	}
	units := make([]uint16, len(buf)/2)
	for i := range units {
		units[i] = binary.LittleEndian.Uint16(buf[2*i:])
	}
	return string(utf16.Decode(units))
}

func clientRunState(exe string) string {
	kind, buf, err := modeRegistryValue(syscall.HKEY_CURRENT_USER, `Software\Microsoft\Windows\CurrentVersion\Run`, "Geumyi Server Center")
	if errors.Is(err, syscall.ERROR_FILE_NOT_FOUND) {
		return "absent"
	}
	if err != nil || kind != syscall.REG_SZ {
		return "unknown"
	}
	command := strings.TrimSpace(strings.TrimRight(utf16LE(buf), "\x00"))
	if strings.EqualFold(command, `"`+exe+`" --background`) {
		return "registered"
	}
	return "unknown"
}

func usableHostTask(raw []byte, host, config string, automatic bool) bool {
	if len(raw) == 0 || len(raw) > 1<<20 {
		return false
	}
	if bytes.HasPrefix(raw, []byte{0xff, 0xfe}) {
		raw = []byte(utf16LE(raw[2:]))
	} else if bytes.HasPrefix(raw, []byte{'<', 0}) {
		raw = []byte(utf16LE(raw))
	}
	raw = bytes.TrimPrefix(raw, []byte{0xef, 0xbb, 0xbf})
	var task struct {
		XMLName xml.Name `xml:"Task"`
		Enabled *bool    `xml:"Settings>Enabled"`
		Actions struct {
			Items []struct {
				XMLName   xml.Name
				Command   string `xml:"Command"`
				Arguments string `xml:"Arguments"`
			} `xml:",any"`
		} `xml:"Actions"`
		Triggers struct {
			Items []struct {
				Enabled *bool `xml:"Enabled"`
			} `xml:",any"`
		} `xml:"Triggers"`
	}
	dec := xml.NewDecoder(bytes.NewReader(raw))
	// schtasks may keep an encoding="UTF-16" declaration in converted output.
	dec.CharsetReader = func(label string, r io.Reader) (io.Reader, error) {
		if !strings.EqualFold(label, "UTF-16") && !strings.EqualFold(label, "UTF-8") {
			return nil, errors.New("unexpected encoding")
		}
		return r, nil
	}
	if dec.Decode(&task) != nil || (task.Enabled != nil && !*task.Enabled) {
		return false
	}
	if host == "" || config == "" || len(task.Actions.Items) != 1 {
		return false
	}
	action := task.Actions.Items[0]
	if action.XMLName.Local != "Exec" || !strings.EqualFold(strings.TrimSpace(action.Command), host) ||
		!strings.EqualFold(strings.TrimSpace(action.Arguments), `--config "`+config+`"`) {
		return false
	}
	if !automatic {
		return true
	}
	for _, trigger := range task.Triggers.Items {
		if trigger.Enabled == nil || *trigger.Enabled {
			return true
		}
	}
	return false
}

func automaticHostTarget(start string, legacy func() bool) string {
	switch start {
	case "automatic", "delayed-automatic":
		return "service"
	case "missing":
		if legacy() {
			return "task"
		}
	}
	return ""
}

func activeHostTarget() string {
	return automaticHostTarget(hostStartType(), func() bool {
		return installedHostTask(true)
	})
}

func systemTool(name string) (string, error) {
	var buf [260]uint16
	api := syscall.NewLazyDLL("kernel32.dll").NewProc("GetSystemDirectoryW")
	n, _, err := api.Call(uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
	if n == 0 || n >= uintptr(len(buf)) {
		return "", fmt.Errorf("Windows system directory unavailable: %v", err)
	}
	return filepath.Join(syscall.UTF16ToString(buf[:n]), name), nil
}

func installedHostTask(automatic bool) bool {
	host, config := installedHostPaths()
	if host == "" {
		return false
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	tool, err := systemTool("schtasks.exe")
	if err != nil {
		return false
	}
	cmd := exec.CommandContext(ctx, tool, "/Query", "/TN", "Geumyi Server Center Host", "/XML")
	hiddenClientCommand(cmd)
	out, err := cmd.Output()
	return err == nil && usableHostTask(out, host, config, automatic)
}

func startHostTarget(target string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	var cmd *exec.Cmd
	switch target {
	case "service":
		tool, err := systemTool("sc.exe")
		if err != nil {
			return err
		}
		cmd = exec.CommandContext(ctx, tool, "start", "Geumyi Server Center Host")
	case "task":
		tool, err := systemTool("schtasks.exe")
		if err != nil {
			return err
		}
		cmd = exec.CommandContext(ctx, tool, "/Run", "/TN", "Geumyi Server Center Host")
	default:
		return errors.New("automatic Host startup is disabled")
	}
	hiddenClientCommand(cmd)
	return cmd.Run()
}
