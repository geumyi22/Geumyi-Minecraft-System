//go:build ignore

// Disposable CI fixture ONLY. This command takes NO operator file paths,
// reads NO production state, NEVER uploads to clouds and NEVER holds real keys.
// It proves bounded AES-GCM part sealing, manifest MAC, tamper rejection and
// isolated round-trip restore with synthetic data inside an OS temp folder.
package main

import (
	"archive/tar"
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

const chunkSize = 64 * 1024 // Small synthetic parts; NOT a production sizing claim.
const schemaVersion = 1

type partMeta struct {
	Name       string `json:"name"`
	Index      int    `json:"index"`
	Nonce      string `json:"nonce"`
	Length     int    `json:"length"`
	CipherHash string `json:"cipher_sha256"`
	PlainHash  string `json:"plain_sha256"`
}

type manifest struct {
	Version       int        `json:"version"`
	ArchiveID     string     `json:"archive_id"`
	OriginalSize  int        `json:"original_size"`
	OriginalHash  string     `json:"original_sha256"`
	Parts         []partMeta `json:"parts"`
}

func digest(b []byte) string {
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

func derive(master []byte, label string) []byte {
	mac := hmac.New(sha256.New, master)
	_, _ = mac.Write([]byte("geumyi-day12-disposable/" + label + "/v1"))
	return mac.Sum(nil)
}

func signManifest(data, macKey []byte) []byte {
	mac := hmac.New(sha256.New, macKey)
	_, _ = mac.Write([]byte("manifest/v1\x00"))
	_, _ = mac.Write(data)
	return mac.Sum(nil)
}

func randomBytes(n int) ([]byte, error) {
	out := make([]byte, n)
	_, err := io.ReadFull(rand.Reader, out)
	return out, err
}

func writeNew(path string, data []byte) error {
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	n, writeErr := f.Write(data)
	if writeErr == nil && n != len(data) {
		writeErr = io.ErrShortWrite
	}
	closeErr := f.Close()
	if writeErr != nil {
		return writeErr
	}
	return closeErr
}

func seal(dir string, input, master []byte) ([]byte, []byte, error) {
	if len(master) != 32 || len(input) == 0 {
		return nil, nil, errors.New("bad synthetic key or empty test input")
	}
	key := derive(master, "encryption")
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, nil, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, nil, err
	}
	idBytes, err := randomBytes(16)
	if err != nil {
		return nil, nil, err
	}
	m := manifest{Version: schemaVersion, ArchiveID: hex.EncodeToString(idBytes),
		OriginalSize: len(input), OriginalHash: digest(input)}
	for i, offset := 0, 0; offset < len(input); i, offset = i+1, offset+chunkSize {
		end := offset + chunkSize
		if end > len(input) {
			end = len(input)
		}
		plaintext := input[offset:end]
		nonce, err := randomBytes(aead.NonceSize())
		if err != nil {
			return nil, nil, err
		}
		aad := []byte(fmt.Sprintf("geumyi/chunk/v1|%s|%d", m.ArchiveID, i))
		ciphertext := aead.Seal(nil, nonce, plaintext, aad)
		name := fmt.Sprintf("part-%06d.gcm", i)
		if err := writeNew(filepath.Join(dir, name), ciphertext); err != nil {
			return nil, nil, err
		}
		m.Parts = append(m.Parts, partMeta{Name: name, Index: i, Nonce: hex.EncodeToString(nonce),
			Length: len(plaintext), CipherHash: digest(ciphertext), PlainHash: digest(plaintext)})
	}
	data, err := json.Marshal(m)
	if err != nil {
		return nil, nil, err
	}
	return data, signManifest(data, derive(master, "manifest-auth")), nil
}

var namePattern = regexp.MustCompile(`^part-[0-9]{6}\.gcm$`)

func restore(dir string, data, tag, master []byte) ([]byte, error) {
	if len(master) != 32 || !hmac.Equal(signManifest(data, derive(master, "manifest-auth")), tag) {
		return nil, errors.New("manifest authentication failed")
	}
	var m manifest
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, err
	}
	if m.Version != schemaVersion || len(m.ArchiveID) != 32 ||
		m.OriginalSize <= 0 || len(m.Parts) == 0 || len(m.Parts) > 10000 {
		return nil, errors.New("invalid archive metadata")
	}
	if _, err := hex.DecodeString(m.ArchiveID); err != nil {
		return nil, errors.New("invalid archive id")
	}
	entries, err := os.ReadDir(dir)
	if err != nil || len(entries) != len(m.Parts) {
		return nil, errors.New("missing or unexpected archive parts")
	}
	key := derive(master, "encryption")
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	var output []byte
	for i, part := range m.Parts {
		expectedName := fmt.Sprintf("part-%06d.gcm", i)
		if part.Index != i || part.Name != expectedName || !namePattern.MatchString(part.Name) ||
			part.Length < 1 || part.Length > chunkSize {
			return nil, errors.New("unsafe or nonsequential part metadata")
		}
		nonce, err := hex.DecodeString(part.Nonce)
		if err != nil || len(nonce) != aead.NonceSize() {
			return nil, errors.New("invalid part nonce")
		}
		path := filepath.Join(dir, part.Name)
		info, err := os.Lstat(path)
		if err != nil || !info.Mode().IsRegular() || info.Size() != int64(part.Length+aead.Overhead()) {
			return nil, errors.New("missing, reparse or unexpected-size archive part")
		}
		ciphertext, err := os.ReadFile(path)
		if err != nil || digest(ciphertext) != part.CipherHash {
			return nil, errors.New("part checksum failed")
		}
		aad := []byte(fmt.Sprintf("geumyi/chunk/v1|%s|%d", m.ArchiveID, i))
		plain, err := aead.Open(nil, nonce, ciphertext, aad)
		if err != nil || len(plain) != part.Length || digest(plain) != part.PlainHash {
			return nil, errors.New("part authentication failed")
		}
		output = append(output, plain...)
	}
	if len(output) != m.OriginalSize || digest(output) != m.OriginalHash {
		return nil, errors.New("restored data mismatch")
	}
	return output, nil
}

// The structured restore rehearsal uses only synthetic TAR payloads. This
// deliberately separate, disposable extractor rejects symlinks, hard links,
// traversal, absolute paths, Windows drive syntax, duplicates and large items.
// It is NOT yet approved for production archive extraction or real credentials.
func fixtureTar(files map[string][]byte) ([]byte, error) {
	var out bytes.Buffer
	tw := tar.NewWriter(&out)
	names := make([]string, 0, len(files))
	for name := range files {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		data := files[name]
		if err := tw.WriteHeader(&tar.Header{
			Name: name, Mode: 0600, Size: int64(len(data)), Typeflag: tar.TypeReg,
		}); err != nil {
			return nil, err
		}
		if _, err := tw.Write(data); err != nil {
			return nil, err
		}
	}
	if err := tw.Close(); err != nil {
		return nil, err
	}
	return out.Bytes(), nil
}

func fixtureRestoreTree(data []byte, target string) error {
	r := tar.NewReader(bytes.NewReader(data))
	seen := map[string]bool{}
	files := 0
	var total int64
	for {
		hdr, err := r.Next()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		files++
		total += hdr.Size
		if files > 20 || hdr.Size < 0 || hdr.Size > 2*1024*1024 || total > 8*1024*1024 {
			return errors.New("oversized disposable tree")
		}
		if hdr.Typeflag != tar.TypeReg || strings.ContainsAny(hdr.Name, ":\\") ||
			path.IsAbs(hdr.Name) || hdr.Name == "" || path.Clean(hdr.Name) != hdr.Name ||
			hdr.Name == ".." || strings.HasPrefix(hdr.Name, "../") {
			return errors.New("unsafe disposable archive name/type")
		}
		safeName := strings.ToLower(hdr.Name)
		if seen[safeName] {
			return errors.New("duplicate or case-colliding entry")
		}
		seen[safeName] = true
		dst := filepath.Join(target, filepath.FromSlash(hdr.Name))
		relative, err := filepath.Rel(target, dst)
		if err != nil || relative == "." || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
			return errors.New("restoration root escape")
		}
		if err := os.MkdirAll(filepath.Dir(dst), 0700); err != nil {
			return err
		}
		f, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
		if err != nil {
			return err
		}
		n, copyErr := io.CopyN(f, r, hdr.Size)
		closeErr := f.Close()
		if copyErr != nil || closeErr != nil || n != hdr.Size {
			return errors.New("partial or unavailable fixture write")
		}
	}
}

func unsafeTarFixture(name string, kind byte) []byte {
	var out bytes.Buffer
	tw := tar.NewWriter(&out)
	h := &tar.Header{Name: name, Mode: 0600, Size: 1, Typeflag: kind}
	if kind == tar.TypeSymlink {
		h.Size = 0
		h.Linkname = "../target"
	}
	must(tw.WriteHeader(h))
	if h.Size == 1 {
		_, err := tw.Write([]byte("x"))
		must(err)
	}
	must(tw.Close())
	return out.Bytes()
}

func testStructuredDisposableRestore(root string, master []byte) {
	files := map[string][]byte{
		"servers/wild/world/region/r.0.0.mca":       []byte("SYNTHETIC_REGION_NOT_MINECRAFT_WORLD"),
		"servers/playground/plugins/example.yml":    []byte("synthetic: true\n"),
		"servers/lobby/server.properties":             []byte("online-mode=false\n# fixture only\n"),
		"management/gsc-version.txt":                  []byte("4.5.1-FIXTURE-NOT_INSTALLED"),
	}
	payload, err := fixtureTar(files)
	must(err)
	chunkDir := filepath.Join(root, "structured-encrypted")
	must(os.Mkdir(chunkDir, 0700))
	meta, tag, err := seal(chunkDir, payload, master)
	must(err)
	decoded, err := restore(chunkDir, meta, tag, master)
	must(err)
	if !bytes.Equal(decoded, payload) {
		panic("STRUCTURED_ENCRYPTED_RESTORE_PAYLOAD_MISMATCH")
	}
	restoreDir := filepath.Join(root, "structured-restore")
	must(os.Mkdir(restoreDir, 0700))
	must(fixtureRestoreTree(decoded, restoreDir))
	for name, want := range files {
		got, err := os.ReadFile(filepath.Join(restoreDir, filepath.FromSlash(name)))
		must(err)
		if !bytes.Equal(got, want) {
			panic("STRUCTURED_TREE_CONTENT_MISMATCH")
		}
	}
	badDir := filepath.Join(root, "bad-tar")
	must(os.Mkdir(badDir, 0700))
	expectRejected("STRUCTURED_PATH_TRAVERSAL",
		fixtureRestoreTree(unsafeTarFixture("../escape", tar.TypeReg), badDir))
	expectRejected("STRUCTURED_ABSOLUTE_PATH",
		fixtureRestoreTree(unsafeTarFixture("/root-escape", tar.TypeReg), badDir))
	expectRejected("STRUCTURED_SYMLINK",
		fixtureRestoreTree(unsafeTarFixture("root/link", tar.TypeSymlink), badDir))
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}

func expectRejected(label string, err error) {
	if err == nil {
		panic("DISPOSABLE_NEGATIVE_FIXTURE_FALSE_PASS_" + label)
	}
}

func main() {
	if len(os.Args) != 1 {
		panic("DISPOSABLE_FIXTURE_REFUSES_ARGUMENTS_OR_OPERATOR_PATHS")
	}
	root, err := os.MkdirTemp("", "geumyi-day12-disposable-crypto-")
	must(err)
	defer func() { _ = os.RemoveAll(root) }() // Owned OS-created disposable dir only.
	parts := filepath.Join(root, "encrypted")
	must(os.Mkdir(parts, 0700))

	// Fixture contains no user files, world data, account names or real credentials.
	sentinel := []byte("FICTIONAL_TEST_DATA_NOT_A_REAL_WORLD_OR_PASSWORD|")
	input := bytes.Repeat(sentinel, 7300)
	master, err := randomBytes(32)
	must(err)
	data, tag, err := seal(parts, input, master)
	must(err)
	var m manifest
	must(json.Unmarshal(data, &m))
	if len(m.Parts) < 3 {
		panic("INSUFFICIENT_TEST_PARTS")
	}
	restored, err := restore(parts, data, tag, master)
	must(err)
	if !bytes.Equal(restored, input) {
		panic("DISPOSABLE_ROUNDTRIP_MISMATCH")
	}
	firstPath := filepath.Join(parts, m.Parts[0].Name)
	original, err := os.ReadFile(firstPath)
	must(err)
	if bytes.Contains(original, sentinel) {
		panic("SYNTHETIC_PLAINTEXT_IN_ENCRYPTED_PART")
	}
	// A single corrupt byte must be refused.
	corrupt := bytes.Clone(original)
	corrupt[3] ^= 0x40
	must(os.WriteFile(firstPath, corrupt, 0600))
	_, err = restore(parts, data, tag, master)
	expectRejected("CIPHERTEXT_TAMPER", err)
	must(os.WriteFile(firstPath, original, 0600))

	// Missing/truncated part must never be accepted as a valid backup.
	must(os.Truncate(firstPath, 10))
	_, err = restore(parts, data, tag, master)
	expectRejected("TRUNCATION", err)
	must(os.WriteFile(firstPath, original, 0600))
	lastPath := filepath.Join(parts, m.Parts[len(m.Parts)-1].Name)
	last, err := os.ReadFile(lastPath)
	must(err)
	must(os.Remove(lastPath))
	_, err = restore(parts, data, tag, master)
	expectRejected("MISSING_PART", err)
	must(writeNew(lastPath, last))

	wrong := bytes.Clone(master)
	wrong[0] ^= 1
	_, err = restore(parts, data, tag, wrong)
	expectRejected("WRONG_KEY", err)
	_, err = restore(parts, append(bytes.Clone(data), '\n'), tag, master)
	expectRejected("MANIFEST_TAMPER", err)

	// Even a deliberately authenticated but malicious manifest path is rejected.
	m.Parts[0].Name = "../outside"
	traversal, err := json.Marshal(m)
	must(err)
	_, err = restore(parts, traversal, signManifest(traversal, derive(master, "manifest-auth")), master)
	expectRejected("TRAVERSAL", err)

	// The encrypted dataset must refuse unrelated/extra cloud parts.
	extra := filepath.Join(parts, "unexpected.gcm")
	must(writeNew(extra, []byte("fake")))
	_, err = restore(parts, data, tag, master)
	expectRejected("EXTRA_PART", err)
	must(os.Remove(extra))
	again, err := restore(parts, data, tag, master)
	must(err)
	if !bytes.Equal(again, input) {
		panic("RECOVERY_AFTER_NEGATIVE_TESTS_FAILED")
	}
	testStructuredDisposableRestore(root, master)
	fmt.Printf("DAY12_CRYPTO_DISPOSABLE_ROUNDTRIP_PASS parts=%d negative_cases=10 structured_tree_restore=true no_cloud_upload=true no_production_source_read=true no_real_backup_created=true\n", len(m.Parts))
}
