//go:build windows

package securestore

import (
	"encoding/base64"
	"errors"
	"strings"
	"syscall"
	"unsafe"
)

type dataBlob struct {
	cbData uint32
	pbData *byte
}

var (
	crypt32             = syscall.NewLazyDLL("crypt32.dll")
	kernel32SS          = syscall.NewLazyDLL("kernel32.dll")
	pCryptProtectData   = crypt32.NewProc("CryptProtectData")
	pCryptUnprotectData = crypt32.NewProc("CryptUnprotectData")
	pLocalFreeSS        = kernel32SS.NewProc("LocalFree")
)

const (
	cryptProtectUIForbidden  = 0x1
	cryptProtectLocalMachine = 0x4
)

func blobFromBytes(b []byte) dataBlob {
	if len(b) == 0 {
		return dataBlob{}
	}
	return dataBlob{cbData: uint32(len(b)), pbData: &b[0]}
}

func bytesFromBlob(b dataBlob) []byte {
	if b.cbData == 0 || b.pbData == nil {
		return nil
	}
	src := unsafe.Slice(b.pbData, int(b.cbData))
	out := make([]byte, len(src))
	copy(out, src)
	return out
}

func ProtectString(s string, machine bool) (string, error) {
	if s == "" {
		return "", nil
	}
	in := []byte(s)
	inBlob := blobFromBytes(in)
	var out dataBlob
	flags := uintptr(cryptProtectUIForbidden)
	prefix := "dpapi-u:"
	if machine {
		flags |= cryptProtectLocalMachine
		prefix = "dpapi-m:"
	}
	r, _, e := pCryptProtectData.Call(uintptr(unsafe.Pointer(&inBlob)), 0, 0, 0, 0, flags, uintptr(unsafe.Pointer(&out)))
	if r == 0 {
		if e != nil && e != syscall.Errno(0) {
			return "", e
		}
		return "", errors.New("CryptProtectData failed")
	}
	defer pLocalFreeSS.Call(uintptr(unsafe.Pointer(out.pbData)))
	return prefix + base64.RawStdEncoding.EncodeToString(bytesFromBlob(out)), nil
}

func UnprotectString(s string) (string, error) {
	if s == "" {
		return "", nil
	}
	machine := false
	var enc string
	switch {
	case strings.HasPrefix(s, "dpapi-m:"):
		machine = true
		enc = strings.TrimPrefix(s, "dpapi-m:")
	case strings.HasPrefix(s, "dpapi-u:"):
		enc = strings.TrimPrefix(s, "dpapi-u:")
	default:
		return s, nil // legacy plaintext; caller may migrate on next save
	}
	raw, err := base64.RawStdEncoding.DecodeString(enc)
	if err != nil {
		return "", err
	}
	inBlob := blobFromBytes(raw)
	var out dataBlob
	flags := uintptr(cryptProtectUIForbidden)
	_ = machine // scope is encoded by DPAPI; no flag needed for decrypt
	r, _, e := pCryptUnprotectData.Call(uintptr(unsafe.Pointer(&inBlob)), 0, 0, 0, 0, flags, uintptr(unsafe.Pointer(&out)))
	if r == 0 {
		if e != nil && e != syscall.Errno(0) {
			return "", e
		}
		return "", errors.New("CryptUnprotectData failed")
	}
	defer pLocalFreeSS.Call(uintptr(unsafe.Pointer(out.pbData)))
	return string(bytesFromBlob(out)), nil
}
