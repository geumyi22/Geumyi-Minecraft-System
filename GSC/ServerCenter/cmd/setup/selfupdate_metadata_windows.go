//go:build windows

package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"syscall"
	"unicode/utf8"
	"unsafe"
)

const selfUpdateUninstallKey = `Software\Microsoft\Windows\CurrentVersion\Uninstall\GeumyiServerCenter`

// Keep the original type and bytes so rollback does not reinterpret registry
// data or change any other uninstall value. A missing key remains missing.
type selfUpdateVersionValue struct {
	KeyExists bool   `json:"key_exists"`
	Exists    bool   `json:"exists"`
	Type      uint32 `json:"type"`
	Data      []byte `json:"data,omitempty"`
}

type selfUpdateMetadataStore struct {
	readVersion  func() (selfUpdateVersionValue, error)
	writeVersion func(selfUpdateVersionValue) error
	writeRole    func(string, []byte) error
}

func installedSelfUpdateMetadataStore() selfUpdateMetadataStore {
	return selfUpdateMetadataStore{readVersion: readSelfUpdateVersionValue, writeVersion: writeSelfUpdateVersionValue, writeRole: replaceSelfUpdateRole}
}

type selfUpdateMetadata struct {
	rolePath     string
	roleOriginal []byte
	roleUpdated  []byte
	roleExists   bool
	oldVersion   selfUpdateVersionValue
	newVersion   selfUpdateVersionValue
	store        selfUpdateMetadataStore
	dirty        bool
}

// Prepare this snapshot before stopping the Host. Only existing role metadata
// is patched: legacy absent files/registration are not invented by an update.
func prepareSelfUpdateMetadata(dataDir, backupDir, targetVersion string, store selfUpdateMetadataStore) (*selfUpdateMetadata, error) {
	m := &selfUpdateMetadata{rolePath: filepath.Join(dataDir, roleStateFile), store: store}
	if targetVersion == "" {
		return nil, errors.New("empty self-update metadata version")
	}
	b, err := os.ReadFile(m.rolePath)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	if err == nil {
		var fields map[string]json.RawMessage
		if err := json.Unmarshal(b, &fields); err != nil || fields == nil || !utf8.Valid(b) {
			return nil, errors.New("existing role metadata is not a JSON object")
		}
		m.roleExists, m.roleOriginal = true, b
		fields["version"], _ = json.Marshal(targetVersion)
		m.roleUpdated, err = json.MarshalIndent(fields, "", "  ")
		if err != nil {
			return nil, err
		}
		m.roleUpdated = append(m.roleUpdated, '\n')
		if err := os.WriteFile(filepath.Join(backupDir, roleStateFile), b, 0600); err != nil {
			return nil, err
		}
	}
	m.oldVersion, err = store.readVersion()
	if err != nil {
		return nil, fmt.Errorf("read uninstall version: %w", err)
	}
	m.newVersion = m.oldVersion
	if m.oldVersion.KeyExists {
		encoded, err := syscall.UTF16FromString(targetVersion)
		if err != nil {
			return nil, err
		}
		data := make([]byte, len(encoded)*2)
		for i, ch := range encoded {
			data[2*i], data[2*i+1] = byte(ch), byte(ch>>8)
		}
		m.newVersion = selfUpdateVersionValue{KeyExists: true, Exists: true, Type: syscall.REG_SZ, Data: data}
	}
	snapshot, err := json.MarshalIndent(m.oldVersion, "", "  ")
	if err != nil {
		return nil, err
	}
	if err := os.WriteFile(filepath.Join(backupDir, "uninstall-display-version.json"), append(snapshot, '\n'), 0600); err != nil {
		return nil, err
	}
	return m, nil
}

func sameSelfUpdateVersion(a, b selfUpdateVersionValue) bool {
	return a.KeyExists == b.KeyExists && a.Exists == b.Exists && a.Type == b.Type && bytes.Equal(a.Data, b.Data)
}

func (m *selfUpdateMetadata) commit() error {
	if m == nil {
		return nil
	}
	// Refuse concurrent metadata edits instead of overwriting changes made
	// while the new Host was starting.
	b, err := os.ReadFile(m.rolePath)
	if (m.roleExists && (err != nil || !bytes.Equal(b, m.roleOriginal))) || (!m.roleExists && !errors.Is(err, os.ErrNotExist)) {
		return errors.New("role metadata changed during self-update")
	}
	current, err := m.store.readVersion()
	if err != nil || !sameSelfUpdateVersion(current, m.oldVersion) {
		return errors.New("uninstall version changed during self-update")
	}
	m.dirty = true
	if m.roleExists {
		if err := m.store.writeRole(m.rolePath, m.roleUpdated); err != nil {
			return fmt.Errorf("update role version: %w", err)
		}
	}
	if m.newVersion.KeyExists {
		if err := m.store.writeVersion(m.newVersion); err != nil {
			return fmt.Errorf("update uninstall version: %w", err)
		}
	}
	if m.roleExists {
		if b, err := os.ReadFile(m.rolePath); err != nil || !bytes.Equal(b, m.roleUpdated) {
			return errors.New("updated role version readback failed")
		}
	}
	current, err = m.store.readVersion()
	if err != nil || !sameSelfUpdateVersion(current, m.newVersion) {
		return errors.New("updated uninstall version readback failed")
	}
	return nil
}

func (m *selfUpdateMetadata) restore() error {
	if m == nil || !m.dirty {
		return nil
	}
	var failures []error
	if m.roleExists {
		if err := m.store.writeRole(m.rolePath, m.roleOriginal); err != nil {
			failures = append(failures, errors.New("original role metadata could not be restored"))
		}
	}
	if m.oldVersion.KeyExists {
		if err := m.store.writeVersion(m.oldVersion); err != nil {
			failures = append(failures, errors.New("original uninstall version could not be restored"))
		}
	}
	if m.roleExists {
		if b, err := os.ReadFile(m.rolePath); err != nil || !bytes.Equal(b, m.roleOriginal) {
			failures = append(failures, errors.New("original role metadata restore readback failed"))
		}
	}
	if current, err := m.store.readVersion(); err != nil || !sameSelfUpdateVersion(current, m.oldVersion) {
		failures = append(failures, errors.New("original uninstall version restore readback failed"))
	}
	if len(failures) == 0 {
		m.dirty = false
	}
	return errors.Join(failures...)
}

// ReplaceFile preserves the existing destination's ACL rather than deleting
// role.json and recreating it with inherited permissions.
func replaceSelfUpdateRole(path string, b []byte) error {
	f, err := os.CreateTemp(filepath.Dir(path), ".gsc-role-*.tmp")
	if err != nil {
		return err
	}
	tmp := f.Name()
	defer os.Remove(tmp)
	if _, err := f.Write(b); err != nil {
		_ = f.Close()
		return err
	}
	if err := f.Sync(); err != nil {
		_ = f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	dst, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		return err
	}
	src, err := syscall.UTF16PtrFromString(tmp)
	if err != nil {
		return err
	}
	ok, _, callErr := syscall.NewLazyDLL("kernel32.dll").NewProc("ReplaceFileW").Call(uintptr(unsafe.Pointer(dst)), uintptr(unsafe.Pointer(src)), 0, 0, 0, 0)
	if ok == 0 {
		return fmt.Errorf("replace role metadata: %w", callErr)
	}
	return nil
}

func readSelfUpdateVersionValue() (selfUpdateVersionValue, error) {
	return readSelfUpdateVersionAt(syscall.HKEY_LOCAL_MACHINE, selfUpdateUninstallKey)
}

func readSelfUpdateVersionAt(root syscall.Handle, keyPath string) (selfUpdateVersionValue, error) {
	var value selfUpdateVersionValue
	path, err := syscall.UTF16PtrFromString(keyPath)
	if err != nil {
		return value, err
	}
	var key syscall.Handle
	err = syscall.RegOpenKeyEx(root, path, 0, syscall.KEY_QUERY_VALUE|syscall.KEY_WOW64_64KEY, &key)
	if errors.Is(err, syscall.ERROR_FILE_NOT_FOUND) {
		return value, nil
	}
	if err != nil {
		return value, err
	}
	defer syscall.RegCloseKey(key)
	value.KeyExists = true
	name, _ := syscall.UTF16PtrFromString("DisplayVersion")
	var size uint32
	err = syscall.RegQueryValueEx(key, name, nil, &value.Type, nil, &size)
	if errors.Is(err, syscall.ERROR_FILE_NOT_FOUND) {
		return value, nil
	}
	if err != nil {
		return value, err
	}
	if size > 64*1024 {
		return value, errors.New("uninstall version is unexpectedly large")
	}
	value.Exists = true
	if size > 0 {
		value.Data = make([]byte, size)
		if err := syscall.RegQueryValueEx(key, name, nil, &value.Type, &value.Data[0], &size); err != nil {
			return value, err
		}
		value.Data = value.Data[:size]
	}
	return value, nil
}

func writeSelfUpdateVersionValue(value selfUpdateVersionValue) error {
	return writeSelfUpdateVersionAt(syscall.HKEY_LOCAL_MACHINE, selfUpdateUninstallKey, value)
}

func writeSelfUpdateVersionAt(root syscall.Handle, keyPath string, value selfUpdateVersionValue) error {
	if !value.KeyExists {
		return nil
	}
	path, err := syscall.UTF16PtrFromString(keyPath)
	if err != nil {
		return err
	}
	var key syscall.Handle
	if err := syscall.RegOpenKeyEx(root, path, 0, syscall.KEY_SET_VALUE|syscall.KEY_WOW64_64KEY, &key); err != nil {
		return err
	}
	defer syscall.RegCloseKey(key)
	name, _ := syscall.UTF16PtrFromString("DisplayVersion")
	api := syscall.NewLazyDLL("advapi32.dll")
	var result uintptr
	if value.Exists {
		var data *byte
		if len(value.Data) > 0 {
			data = &value.Data[0]
		}
		result, _, _ = api.NewProc("RegSetValueExW").Call(uintptr(key), uintptr(unsafe.Pointer(name)), 0, uintptr(value.Type), uintptr(unsafe.Pointer(data)), uintptr(len(value.Data)))
	} else {
		result, _, _ = api.NewProc("RegDeleteValueW").Call(uintptr(key), uintptr(unsafe.Pointer(name)))
		if syscall.Errno(result) == syscall.ERROR_FILE_NOT_FOUND {
			return nil
		}
	}
	if result != 0 {
		return syscall.Errno(result)
	}
	return nil
}
