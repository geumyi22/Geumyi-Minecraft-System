//go:build windows

package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
	"unsafe"
)

func metadataTestFixture(t *testing.T) (string, string, []byte) {
	t.Helper()
	dir := t.TempDir()
	backup := filepath.Join(dir, "backup")
	if err := os.Mkdir(backup, 0700); err != nil {
		t.Fatal(err)
	}
	original := []byte("{\n  \"version\":\"4.5.1\",\"role\":3,\"role_name\":\"둘 다\",\"unknown\":{\"large\":9007199254740993,\"text\":\"한글 보존\"},\"dedicated_profile_active\":false\n}\n")
	if err := os.WriteFile(filepath.Join(dir, roleStateFile), original, 0600); err != nil {
		t.Fatal(err)
	}
	return dir, backup, original
}

func TestSelfUpdateMetadataPreservesRoleFieldsAndRollsBackExactBytes(t *testing.T) {
	dir, backup, original := metadataTestFixture(t)
	old := selfUpdateVersionValue{KeyExists: true, Exists: true, Type: syscall.REG_BINARY, Data: []byte{1, 2, 3}}
	value := old
	store := selfUpdateMetadataStore{
		readVersion:  func() (selfUpdateVersionValue, error) { return value, nil },
		writeVersion: func(v selfUpdateVersionValue) error { value = v; return nil },
		writeRole:    replaceSelfUpdateRole,
	}
	m, err := prepareSelfUpdateMetadata(dir, backup, "5.0.0", store)
	if err != nil {
		t.Fatal(err)
	}
	if b, err := os.ReadFile(filepath.Join(backup, roleStateFile)); err != nil || !bytes.Equal(b, original) {
		t.Fatal("role backup differs from original")
	}
	if err := m.commit(); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(filepath.Join(dir, roleStateFile))
	var before, after map[string]json.RawMessage
	_ = json.Unmarshal(original, &before)
	if err := json.Unmarshal(b, &after); err != nil {
		t.Fatal(err)
	}
	if string(after["version"]) != `"5.0.0"` {
		t.Fatalf("wrong version: %s", b)
	}
	delete(before, "version")
	delete(after, "version")
	for k, v := range before {
		var a, b bytes.Buffer
		_ = json.Compact(&a, v)
		_ = json.Compact(&b, after[k])
		if !bytes.Equal(a.Bytes(), b.Bytes()) {
			t.Fatalf("changed preserved field %s", k)
		}
	}
	if len(before) != len(after) || !strings.Contains(string(b), "둘 다") || !strings.Contains(string(b), "한글 보존") {
		t.Fatal("role fields or Korean changed")
	}
	if value.Type != syscall.REG_SZ || !value.Exists {
		t.Fatalf("wrong uninstall metadata: %+v", value)
	}
	if err := m.restore(); err != nil {
		t.Fatal(err)
	}
	b, _ = os.ReadFile(filepath.Join(dir, roleStateFile))
	if !bytes.Equal(b, original) || !sameSelfUpdateVersion(value, old) {
		t.Fatal("rollback did not restore exact original metadata")
	}
}

func TestSelfUpdateMetadataRegistryFailureRestoresPartialRoleWrite(t *testing.T) {
	dir, backup, original := metadataTestFixture(t)
	old := selfUpdateVersionValue{KeyExists: true}
	value := old
	writes := 0
	store := selfUpdateMetadataStore{
		readVersion: func() (selfUpdateVersionValue, error) { return value, nil },
		writeVersion: func(v selfUpdateVersionValue) error {
			writes++
			if writes == 1 {
				return errors.New("injected registry denial")
			}
			value = v
			return nil
		},
		writeRole: replaceSelfUpdateRole,
	}
	m, err := prepareSelfUpdateMetadata(dir, backup, "5.0.0", store)
	if err != nil {
		t.Fatal(err)
	}
	if err = m.commit(); err == nil {
		t.Fatal("partial metadata write reported success")
	}
	if b, _ := os.ReadFile(filepath.Join(dir, roleStateFile)); bytes.Equal(b, original) {
		t.Fatal("fixture never reached partial role update")
	}
	if err = m.restore(); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(filepath.Join(dir, roleStateFile)); !bytes.Equal(b, original) {
		t.Fatal("role not restored after registry failure")
	}
	if !sameSelfUpdateVersion(value, old) {
		t.Fatal("previously absent DisplayVersion was created by rollback")
	}
}

func TestSelfUpdateMetadataFailsClosedForConcurrentChanges(t *testing.T) {
	dir, backup, _ := metadataTestFixture(t)
	writes := 0
	store := selfUpdateMetadataStore{
		readVersion:  func() (selfUpdateVersionValue, error) { return selfUpdateVersionValue{}, nil },
		writeVersion: func(selfUpdateVersionValue) error { writes++; return nil },
		writeRole:    func(string, []byte) error { writes++; return nil },
	}
	m, err := prepareSelfUpdateMetadata(dir, backup, "5.0.0", store)
	if err != nil {
		t.Fatal(err)
	}
	changed := []byte(`{"version":"4.5.1","operator_edit":true}`)
	if err = os.WriteFile(filepath.Join(dir, roleStateFile), changed, 0600); err != nil {
		t.Fatal(err)
	}
	if err = m.commit(); err == nil {
		t.Fatal("concurrent role edit was accepted")
	}
	if err = m.restore(); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(filepath.Join(dir, roleStateFile))
	if writes != 0 || !bytes.Equal(b, changed) {
		t.Fatal("concurrent operator edit overwritten")
	}
}

func TestSelfUpdateMetadataDoesNotInventAbsentRecords(t *testing.T) {
	dir := t.TempDir()
	writes := 0
	store := selfUpdateMetadataStore{
		readVersion:  func() (selfUpdateVersionValue, error) { return selfUpdateVersionValue{}, nil },
		writeVersion: func(selfUpdateVersionValue) error { writes++; return nil },
		writeRole:    func(string, []byte) error { writes++; return nil },
	}
	m, err := prepareSelfUpdateMetadata(dir, dir, "5.0.0", store)
	if err != nil {
		t.Fatal(err)
	}
	if err = m.commit(); err != nil {
		t.Fatal(err)
	}
	if err = m.restore(); err != nil {
		t.Fatal(err)
	}
	if writes != 0 {
		t.Fatal("absent legacy metadata was invented")
	}
	if _, err = os.Stat(filepath.Join(dir, roleStateFile)); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("absent role was created")
	}
}

func TestSelfUpdateMetadataRestoreFailureIsReportedAndAllRecordsAttempted(t *testing.T) {
	dir, backup, _ := metadataTestFixture(t)
	value := selfUpdateVersionValue{KeyExists: true}
	failRestore := false
	registryRestored := false
	store := selfUpdateMetadataStore{
		readVersion: func() (selfUpdateVersionValue, error) { return value, nil },
		writeVersion: func(v selfUpdateVersionValue) error {
			value = v
			if failRestore {
				registryRestored = true
			}
			return nil
		},
		writeRole: func(p string, b []byte) error {
			if failRestore {
				return errors.New("injected role restore failure")
			}
			return replaceSelfUpdateRole(p, b)
		},
	}
	m, err := prepareSelfUpdateMetadata(dir, backup, "5.0.0", store)
	if err != nil {
		t.Fatal(err)
	}
	if err = m.commit(); err != nil {
		t.Fatal(err)
	}
	failRestore = true
	if err = m.restore(); err == nil || !registryRestored {
		t.Fatal("restore failure hidden or later registry restore skipped")
	}
}

func TestSelfUpdateMetadataMalformedRoleIsRejectedBeforeWrites(t *testing.T) {
	for _, bad := range []string{`null`, `[]`, `{"role":`, "{\"name\":\"\xff\"}"} {
		t.Run(bad, func(t *testing.T) {
			dir := t.TempDir()
			p := filepath.Join(dir, roleStateFile)
			if err := os.WriteFile(p, []byte(bad), 0600); err != nil {
				t.Fatal(err)
			}
			store := selfUpdateMetadataStore{readVersion: func() (selfUpdateVersionValue, error) {
				t.Fatal("invalid role reached registry")
				return selfUpdateVersionValue{}, nil
			}}
			if _, err := prepareSelfUpdateMetadata(dir, dir, "5.0.0", store); err == nil {
				t.Fatal("invalid role accepted")
			}
			b, _ := os.ReadFile(p)
			if string(b) != bad {
				t.Fatal("invalid role changed")
			}
		})
	}
}

func TestSelfUpdateVersionRegistryPreservesUnrelatedValues(t *testing.T) {
	// Exercise the native registry functions only under a disposable HKCU key.
	// Never open the installed HKLM product registration in this test.
	path := fmt.Sprintf(`Software\GSCMetadataTest-%d`, time.Now().UnixNano())
	ptr, _ := syscall.UTF16PtrFromString(path)
	var key syscall.Handle
	api := syscall.NewLazyDLL("advapi32.dll")
	r, _, _ := api.NewProc("RegCreateKeyExW").Call(syscall.HKEY_CURRENT_USER, uintptr(unsafe.Pointer(ptr)), 0, 0, 0, syscall.KEY_ALL_ACCESS|syscall.KEY_WOW64_64KEY, 0, uintptr(unsafe.Pointer(&key)), 0)
	if r != 0 {
		t.Fatalf("create disposable registry key: %v", syscall.Errno(r))
	}
	t.Cleanup(func() {
		syscall.RegCloseKey(key)
		api.NewProc("RegDeleteKeyW").Call(syscall.HKEY_CURRENT_USER, uintptr(unsafe.Pointer(ptr)))
	})
	name, _ := syscall.UTF16PtrFromString("UnrelatedValue")
	marker := []byte{7, 8, 9}
	r, _, _ = api.NewProc("RegSetValueExW").Call(uintptr(key), uintptr(unsafe.Pointer(name)), 0, syscall.REG_BINARY, uintptr(unsafe.Pointer(&marker[0])), uintptr(len(marker)))
	if r != 0 {
		t.Fatal(syscall.Errno(r))
	}
	old, err := readSelfUpdateVersionAt(syscall.HKEY_CURRENT_USER, path)
	if err != nil {
		t.Fatal(err)
	}
	if !old.KeyExists || old.Exists {
		t.Fatal("wrong absent DisplayVersion snapshot")
	}
	want := selfUpdateVersionValue{KeyExists: true, Exists: true, Type: syscall.REG_BINARY, Data: []byte{4, 5, 6}}
	if err = writeSelfUpdateVersionAt(syscall.HKEY_CURRENT_USER, path, want); err != nil {
		t.Fatal(err)
	}
	got, err := readSelfUpdateVersionAt(syscall.HKEY_CURRENT_USER, path)
	if err != nil || !sameSelfUpdateVersion(got, want) {
		t.Fatalf("registry roundtrip differs: %+v %v", got, err)
	}
	if err = writeSelfUpdateVersionAt(syscall.HKEY_CURRENT_USER, path, old); err != nil {
		t.Fatal(err)
	}
	got, err = readSelfUpdateVersionAt(syscall.HKEY_CURRENT_USER, path)
	if err != nil || !sameSelfUpdateVersion(got, old) {
		t.Fatal("absent DisplayVersion not restored")
	}
	buf := make([]byte, 10)
	size := uint32(len(buf))
	var typ uint32
	if err = syscall.RegQueryValueEx(key, name, nil, &typ, &buf[0], &size); err != nil || typ != syscall.REG_BINARY || !bytes.Equal(buf[:size], marker) {
		t.Fatal("unrelated registration value changed")
	}
}
