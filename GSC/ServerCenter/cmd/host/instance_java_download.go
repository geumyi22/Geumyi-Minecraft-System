package main

import (
	"archive/zip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"geumyi/servercenter/internal/javaruntime"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
)

var instanceJavaDownloadMu sync.Mutex

func resolveInstanceInstallJava(ctx context.Context, id string, p *ManagedInstance, required int) (javaruntime.Runtime, error) {
	if p.JavaPath != "" {
		if !filepath.IsAbs(p.JavaPath) {
			return javaruntime.Runtime{}, errors.New("Java 실행 파일의 전체 경로를 선택하세요")
		}
		if _, err := os.Stat(p.JavaPath); err != nil {
			return javaruntime.Runtime{}, err
		}
		j, err := javaruntime.Resolve(p.JavaPath)
		if err != nil {
			return j, err
		}
		major := instanceJavaMajor(j.Version)
		if major < required || (required < 17 && major != required) {
			return j, fmt.Errorf("이 서버는 Java %d%s가 필요합니다", required, instanceJavaRequirementSuffix(required))
		}
		return j, nil
	}
	instanceJavaDownloadMu.Lock()
	defer instanceJavaDownloadMu.Unlock()
	root := filepath.Join(filepath.Dir(configPath), "java-runtimes")
	final := filepath.Join(root, fmt.Sprintf("java-%d", required))
	// Prefer an exact major already installed; newer Java can break older loaders.
	candidates := []string{}
	if j, err := javaruntime.Resolve(""); err == nil {
		candidates = append(candidates, j.Executable)
	}
	for _, vendor := range []string{"Java", "Eclipse Adoptium", "Microsoft", "BellSoft", "Zulu", "Amazon Corretto"} {
		matches, _ := filepath.Glob(filepath.Join(os.Getenv("ProgramFiles"), vendor, "*", "bin", "java.exe"))
		candidates = append(candidates, matches...)
	}
	managed, _ := filepath.Glob(filepath.Join(final, "*", "bin", "java.exe"))
	candidates = append(managed, candidates...)
	for _, candidate := range candidates {
		j, err := javaruntime.Resolve(candidate)
		if err == nil && instanceJavaMajor(j.Version) == required {
			if p.Kind == "spigot" {
				if _, err := os.Stat(filepath.Join(j.Home, "bin", "javac.exe")); err != nil {
					continue
				}
			}
			_, _ = instanceInstallLog{id}.Write([]byte(fmt.Sprintf("Java %d 자동 선택: %s\n", required, j.Executable)))
			return j, nil
		}
	}
	if runtime.GOOS != "windows" || runtime.GOARCH != "amd64" {
		return javaruntime.Runtime{}, errors.New("Java 자동 설치는 Windows x64에서 지원합니다. Java 경로를 직접 지정하세요")
	}
	if required < 8 || required > 40 {
		return javaruntime.Runtime{}, errors.New("공식 Java 버전을 확인하지 못했습니다")
	}
	instanceInstallUpdate(id, "downloading", fmt.Sprintf("호환 Java %d 자동 다운로드 중 · 시스템 Java 설정은 유지합니다", required))
	var assets []struct {
		Binary struct {
			Package struct {
				Link, Checksum string
				Size           int64
			}
		}
	}
	metadata := fmt.Sprintf("https://api.adoptium.net/v3/assets/latest/%d/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse", required)
	b, err := instanceJavaFetchMetadata(ctx, metadata)
	if err != nil {
		return javaruntime.Runtime{}, err
	}
	if err := json.Unmarshal(b, &assets); err != nil {
		return javaruntime.Runtime{}, err
	}
	if len(assets) == 0 {
		return javaruntime.Runtime{}, fmt.Errorf("Java %d 공식 Windows 패키지가 없습니다. 경로를 직접 지정하세요", required)
	}
	pkg := assets[0].Binary.Package
	if len(pkg.Checksum) != 64 || pkg.Size < 1 || pkg.Size > 512<<20 {
		return javaruntime.Runtime{}, errors.New("Java 다운로드 검증 정보가 올바르지 않습니다")
	}
	if _, err := os.Stat(final); err == nil {
		return javaruntime.Runtime{}, fmt.Errorf("기존 Java 폴더를 덮어쓰지 않았습니다: %s", final)
	}
	if err := os.MkdirAll(root, 0700); err != nil {
		return javaruntime.Runtime{}, err
	}
	staging, err := os.MkdirTemp(root, "download-")
	if err != nil {
		return javaruntime.Runtime{}, err
	}
	defer os.RemoveAll(staging) // Only this freshly-created private temporary directory.
	archive := filepath.Join(staging, "java.zip")
	if err = instanceJavaDownload(ctx, pkg.Link, pkg.Checksum, pkg.Size, archive); err != nil {
		return javaruntime.Runtime{}, err
	}
	extracted := filepath.Join(staging, "runtime")
	if err = extractInstanceJavaZIP(archive, extracted); err != nil {
		return javaruntime.Runtime{}, err
	}
	matches, _ := filepath.Glob(filepath.Join(extracted, "*", "bin", "java.exe"))
	if len(matches) != 1 {
		return javaruntime.Runtime{}, errors.New("Java 패키지의 실행 파일을 확인하지 못했습니다")
	}
	probe, err := javaruntime.Resolve(matches[0])
	if err != nil || instanceJavaMajor(probe.Version) != required {
		return javaruntime.Runtime{}, fmt.Errorf("다운로드한 Java %d 실행 검증 실패: %v", required, err)
	}
	rel, _ := filepath.Rel(extracted, matches[0])
	if err = os.Rename(extracted, final); err != nil {
		return javaruntime.Runtime{}, err
	}
	j, err := javaruntime.Resolve(filepath.Join(final, rel))
	if err != nil {
		return j, err
	}
	_, _ = instanceInstallLog{id}.Write([]byte(fmt.Sprintf("Java %d 자동 설치 완료: %s\n", required, j.Executable)))
	return j, nil
}

func validateInstanceJavaURL(u *url.URL) error {
	if u == nil || u.Scheme != "https" || u.User != nil || (u.Port() != "" && u.Port() != "443") {
		return errors.New("Java 공식 HTTPS 주소가 아닙니다")
	}
	switch strings.ToLower(u.Hostname()) {
	case "api.adoptium.net", "release-assets.githubusercontent.com", "objects.githubusercontent.com":
		return nil
	case "github.com":
		p := strings.ToLower(u.Path)
		if strings.HasPrefix(p, "/adoptium/") || strings.HasPrefix(p, "/adoptopenjdk/") {
			return nil
		}
	}
	return errors.New("Java 공식 다운로드 호스트가 아닙니다")
}

var instanceJavaHTTP = &http.Client{Timeout: 8 * time.Minute, CheckRedirect: func(req *http.Request, via []*http.Request) error {
	if len(via) >= 6 {
		return errors.New("Java 다운로드 리디렉션 한도 초과")
	}
	return validateInstanceJavaURL(req.URL)
}}

func instanceJavaRequest(ctx context.Context, raw string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, raw, nil)
	if err != nil {
		return nil, err
	}
	if err := validateInstanceJavaURL(req.URL); err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "GeumyiServerCenter/"+appVersion+" (https://github.com/geumyi22/Geumyi-Minecraft-System)")
	res, err := instanceJavaHTTP.Do(req)
	if err != nil {
		return nil, err
	}
	if res.StatusCode != http.StatusOK {
		res.Body.Close()
		return nil, fmt.Errorf("공식 Java 다운로드 응답 %d", res.StatusCode)
	}
	return res, nil
}
func instanceJavaFetchMetadata(ctx context.Context, raw string) ([]byte, error) {
	res, err := instanceJavaRequest(ctx, raw)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	b, err := io.ReadAll(io.LimitReader(res.Body, (8<<20)+1))
	if len(b) > 8<<20 {
		return nil, errors.New("Java 메타데이터 크기 초과")
	}
	return b, err
}
func instanceJavaDownload(ctx context.Context, raw, checksum string, size int64, dest string) error {
	res, err := instanceJavaRequest(ctx, raw)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	f, err := os.OpenFile(dest, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	h := sha256.New()
	n, copyErr := io.Copy(io.MultiWriter(f, h), io.LimitReader(res.Body, size+1))
	closeErr := f.Close()
	if copyErr != nil {
		return copyErr
	}
	if closeErr != nil {
		return closeErr
	}
	if n != size || !strings.EqualFold(hex.EncodeToString(h.Sum(nil)), checksum) {
		return errors.New("Java 다운로드 크기 또는 SHA-256 검증 실패")
	}
	return nil
}
func extractInstanceJavaZIP(archive, dest string) error {
	z, err := zip.OpenReader(archive)
	if err != nil {
		return err
	}
	defer z.Close()
	var total uint64
	for _, entry := range z.File {
		name := filepath.FromSlash(entry.Name)
		if strings.ContainsAny(entry.Name, "\\:\x00") || filepath.IsAbs(name) || !filepath.IsLocal(name) || entry.Mode()&os.ModeSymlink != 0 {
			return errors.New("Java 압축 파일의 경로가 올바르지 않습니다")
		}
		total += entry.UncompressedSize64
		if total > 2<<30 {
			return errors.New("Java 압축 해제 크기 제한 초과")
		}
		output := filepath.Join(dest, name)
		if entry.FileInfo().IsDir() {
			if err := os.MkdirAll(output, 0700); err != nil {
				return err
			}
			continue
		}
		if err := os.MkdirAll(filepath.Dir(output), 0700); err != nil {
			return err
		}
		src, err := entry.Open()
		if err != nil {
			return err
		}
		out, err := os.OpenFile(output, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
		if err != nil {
			src.Close()
			return err
		}
		_, copyErr := io.Copy(out, io.LimitReader(src, int64(entry.UncompressedSize64)+1))
		src.Close()
		closeErr := out.Close()
		if copyErr != nil {
			return copyErr
		}
		if closeErr != nil {
			return closeErr
		}
	}
	return nil
}
