package main

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/md5"
	"crypto/sha1"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// Only metadata from the publisher may select an artifact URL and checksum.
type instanceServerArtifact struct {
	URL    string `json:"url"`
	SHA1   string `json:"sha1"`
	SHA256 string `json:"sha256"`
	MD5    string `json:"md5"`
	Size   int64  `json:"size"`
}

type instanceMojangManifest struct {
	Versions []struct {
		ID   string `json:"id"`
		Type string `json:"type"`
		URL  string `json:"url"`
		SHA1 string `json:"sha1"`
	} `json:"versions"`
}

func instanceMojangGame(ctx context.Context, version string) ([]byte, error) {
	var manifest instanceMojangManifest
	if err := instanceFetchJSON(ctx, "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json", &manifest); err != nil {
		return nil, err
	}
	for _, v := range manifest.Versions {
		if v.ID != version {
			continue
		}
		b, err := instanceFetch(ctx, v.URL, instanceMetadataLimit)
		if err != nil {
			return nil, err
		}
		s := sha1.Sum(b)
		if len(v.SHA1) != 40 || !strings.EqualFold(hex.EncodeToString(s[:]), v.SHA1) {
			return nil, errors.New("Minecraft 버전 메타데이터 해시 불일치")
		}
		return b, nil
	}
	return nil, errors.New("Minecraft 공식 버전 정보를 찾지 못했습니다")
}

type instanceFillBuild struct {
	ID        int    `json:"id"`
	Channel   string `json:"channel"`
	Downloads map[string]struct {
		URL       string `json:"url"`
		Size      int64  `json:"size"`
		Checksums struct {
			SHA256 string `json:"sha256"`
		} `json:"checksums"`
	} `json:"downloads"`
}

func instanceFillBuilds(ctx context.Context, kind, version string) ([]instanceFillBuild, error) {
	var builds []instanceFillBuild
	err := instanceFetchJSON(ctx, "https://fill.papermc.io/v3/projects/"+kind+"/versions/"+version+"/builds", &builds)
	return builds, err
}

func instanceDirectVersions(ctx context.Context, kind, version string) (instanceVersionList, error) {
	out := instanceVersionList{Minecraft: []string{}, Loaders: []string{}}
	switch kind {
	case "vanilla":
		var manifest instanceMojangManifest
		if err := instanceFetchJSON(ctx, "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json", &manifest); err != nil {
			return out, err
		}
		for _, v := range manifest.Versions {
			if v.Type == "release" && instanceVersionPattern.MatchString(v.ID) {
				out.Minecraft = append(out.Minecraft, v.ID)
			}
		}
	case "paper", "velocity":
		var project struct {
			Versions map[string][]string `json:"versions"`
		}
		if err := instanceFetchJSON(ctx, "https://fill.papermc.io/v3/projects/"+kind, &project); err != nil {
			return out, err
		}
		for _, versions := range project.Versions {
			for _, v := range versions {
				if instanceVersionPattern.MatchString(v) && !strings.Contains(v, "-") {
					out.Minecraft = append(out.Minecraft, v)
				}
			}
		}
	case "purpur":
		var project struct {
			Versions []string `json:"versions"`
		}
		if err := instanceFetchJSON(ctx, "https://api.purpurmc.org/v2/purpur", &project); err != nil {
			return out, err
		}
		for _, v := range project.Versions {
			if instanceVersionPattern.MatchString(v) {
				out.Minecraft = append(out.Minecraft, v)
			}
		}
	default:
		return out, errors.New("지원하지 않는 직접 다운로드 종류입니다")
	}
	sort.Slice(out.Minecraft, func(i, j int) bool {
		a, b := out.Minecraft[i], out.Minecraft[j]
		previewA, previewB := strings.Contains(a, "-"), strings.Contains(b, "-")
		if previewA != previewB {
			return !previewA
		}
		return instanceVersionLess(a, b)
	})
	if version == "" {
		return out, nil
	}
	if !instanceContains(out.Minecraft, version) {
		return out, errors.New("공식 목록에 없는 버전입니다")
	}
	if kind == "paper" || kind == "velocity" {
		builds, err := instanceFillBuilds(ctx, kind, version)
		if err != nil {
			return out, err
		}
		for _, b := range builds {
			if b.Channel == "STABLE" && b.Downloads["server:default"].URL != "" {
				out.Loaders = append(out.Loaders, strconv.Itoa(b.ID))
			}
		}
		if len(out.Loaders) == 0 {
			return out, errors.New("이 버전에는 공식 안정 빌드가 없습니다. 다른 버전을 선택하세요")
		}
	} else if kind == "purpur" {
		var data struct {
			Builds struct {
				All []string `json:"all"`
			} `json:"builds"`
		}
		if err := instanceFetchJSON(ctx, "https://api.purpurmc.org/v2/purpur/"+version, &data); err != nil {
			return out, err
		}
		for _, b := range data.Builds.All {
			if _, err := strconv.Atoi(b); err == nil {
				out.Loaders = append(out.Loaders, b)
			}
		}
	}
	sort.Slice(out.Loaders, func(i, j int) bool { return instanceVersionLess(out.Loaders[i], out.Loaders[j]) })
	if kind == "velocity" {
		// Current upstream deployment baseline; independent of backend MC versions.
		out.JavaMajor = 25
	} else {
		n, err := instanceRequiredJava(ctx, version)
		if err != nil {
			return out, err
		}
		out.JavaMajor = n
		if kind == "paper" || kind == "purpur" {
			out.JavaMajor = instancePaperJava(version, n)
		}
	}
	return out, nil
}

// Paper's supported runtime baseline is higher than vanilla on some releases.
func instancePaperJava(version string, vanilla int) int {
	if !strings.HasPrefix(version, "1.") {
		return vanilla
	}
	parts := strings.Split(version, ".")
	minor, _ := strconv.Atoi(parts[1])
	baseline := 8
	switch {
	case minor >= 20:
		baseline = 21
	case minor >= 17:
		baseline = 17
	case version == "1.16.5":
		baseline = 16
	case minor >= 12:
		baseline = 11
	}
	if baseline > vanilla {
		return baseline
	}
	return vanilla
}

func instanceDirectArtifact(ctx context.Context, kind, version, build string) (instanceServerArtifact, error) {
	switch kind {
	case "vanilla":
		b, err := instanceMojangGame(ctx, version)
		if err != nil {
			return instanceServerArtifact{}, err
		}
		var game struct {
			Downloads struct {
				Server instanceServerArtifact `json:"server"`
			} `json:"downloads"`
		}
		if err = json.Unmarshal(b, &game); err != nil {
			return instanceServerArtifact{}, err
		}
		if game.Downloads.Server.URL == "" {
			return instanceServerArtifact{}, errors.New("이 Vanilla 버전에 서버 다운로드가 없습니다")
		}
		return game.Downloads.Server, nil
	case "paper", "velocity":
		builds, err := instanceFillBuilds(ctx, kind, version)
		if err != nil {
			return instanceServerArtifact{}, err
		}
		for _, b := range builds {
			if strconv.Itoa(b.ID) == build && b.Channel == "STABLE" {
				a := b.Downloads["server:default"]
				return instanceServerArtifact{URL: a.URL, SHA256: a.Checksums.SHA256, Size: a.Size}, nil
			}
		}
		return instanceServerArtifact{}, errors.New("선택한 공식 안정 빌드를 찾지 못했습니다")
	case "purpur":
		var data struct {
			Result string `json:"result"`
			MD5    string `json:"md5"`
			SHA256 string `json:"sha256"`
		}
		u := "https://api.purpurmc.org/v2/purpur/" + version + "/" + build
		if err := instanceFetchJSON(ctx, u, &data); err != nil {
			return instanceServerArtifact{}, err
		}
		if data.Result != "SUCCESS" {
			return instanceServerArtifact{}, errors.New("성공한 Purpur 빌드가 아닙니다")
		}
		return instanceServerArtifact{URL: u + "/download", MD5: data.MD5, SHA256: data.SHA256}, nil
	}
	return instanceServerArtifact{}, errors.New("공식 서버 다운로드를 찾지 못했습니다")
}

func downloadInstanceServer(ctx context.Context, a instanceServerArtifact, destination string, progress ...func(int64, int64)) error {
	algorithm, want := "sha256", a.SHA256
	if want == "" {
		algorithm, want = "sha1", a.SHA1
	}
	if want == "" {
		algorithm, want = "md5", a.MD5
	}
	length := map[string]int{"sha256": 64, "sha1": 40, "md5": 32}[algorithm]
	if len(want) != length {
		return errors.New("공식 서버 다운로드 검증값이 없습니다")
	}
	if _, err := hex.DecodeString(want); err != nil {
		return errors.New("공식 다운로드 해시 형식이 잘못되었습니다")
	}
	var b []byte
	var err error
	if strings.HasPrefix(a.URL, "https://api.purpurmc.org/v2/purpur/") {
		b, err = instanceFetchPurpurServer(ctx, a.URL, progress...)
	} else {
		b, err = instanceFetch(ctx, a.URL, 256<<20)
	}
	if err != nil {
		return err
	}
	if a.Size > 0 && int64(len(b)) != a.Size {
		return errors.New("공식 서버 다운로드 크기가 일치하지 않습니다")
	}
	got := ""
	switch algorithm {
	case "sha256":
		s := sha256.Sum256(b)
		got = hex.EncodeToString(s[:])
	case "sha1":
		s := sha1.Sum(b)
		got = hex.EncodeToString(s[:])
	case "md5":
		s := md5.Sum(b)
		got = hex.EncodeToString(s[:])
	}
	if !strings.EqualFold(got, want) {
		return errors.New("공식 서버 다운로드 해시가 일치하지 않습니다")
	}
	z, err := zip.NewReader(bytes.NewReader(b), int64(len(b)))
	if err != nil {
		return errors.New("공식 다운로드가 올바른 JAR가 아닙니다")
	}
	manifest := false
	for _, f := range z.File {
		if f.Name == "META-INF/MANIFEST.MF" {
			manifest = true
			break
		}
	}
	if !manifest {
		return errors.New("서버 JAR manifest가 없습니다")
	}
	return writeInstanceNewFile(destination, b)
}

func validateInstanceBackend(address string) (string, error) {
	if address == "" {
		address = "127.0.0.1:25565"
	}
	host, port, err := net.SplitHostPort(address)
	if err != nil || host == "" {
		return "", errors.New("백엔드 주소는 호스트:포트 형식이어야 합니다")
	}
	n, err := strconv.Atoi(port)
	if err != nil || n < 1 || n > 65535 {
		return "", errors.New("백엔드 포트는 1–65535여야 합니다")
	}
	if strings.ContainsAny(host, "\"\\") || strings.IndexFunc(host, func(r rune) bool { return r <= 32 || r == 127 }) >= 0 {
		return "", errors.New("잘못된 백엔드 호스트입니다")
	}
	return net.JoinHostPort(host, strconv.Itoa(n)), nil
}

func instanceNewServerProperties(p *ManagedInstance) string {
	if p.ProxyBackend {
		// This opt-in is only applied inside the creator's new directory. Loopback
		// binding prevents clients bypassing the local authenticating proxy.
		return fmt.Sprintf("# New GSC server: local proxy backend explicitly selected.\nserver-port=%d\nserver-ip=127.0.0.1\nonline-mode=false\nenable-rcon=false\n", p.JavaPort)
	}
	return fmt.Sprintf("# Created for a new GSC server.\nserver-port=%d\nonline-mode=true\nenable-rcon=false\n", p.JavaPort)
}

func writeInstanceVelocityConfig(p *ManagedInstance, backend string) error {
	address, err := validateInstanceBackend(backend)
	if err != nil {
		return err
	}
	if err = validateInstanceProxyDestination(p.JavaPort, address); err != nil {
		return err
	}
	version := "2.9"
	if strings.HasPrefix(p.MinecraftVersion, "3.") {
		version = "2.7"
	}
	config := fmt.Sprintf("# Created for this new GSC proxy only.\nconfig-version = %q\nbind = %q\nmotd = \"GSC Velocity\"\nshow-max-players = 100\nonline-mode = true\nplayer-info-forwarding-mode = \"none\"\n[servers]\nbackend = %q\ntry = [\"backend\"]\n[forced-hosts]\n", version, net.JoinHostPort("0.0.0.0", strconv.Itoa(p.JavaPort)), address)
	return writeInstanceNewFile(filepath.Join(p.Dir, "velocity.toml"), []byte(config))
}

func validateInstanceProxyDestination(proxyPort int, address string) error {
	host, port, err := net.SplitHostPort(address)
	if err != nil {
		return err
	}
	ip := net.ParseIP(host)
	if port == strconv.Itoa(proxyPort) && (strings.EqualFold(host, "localhost") || (ip != nil && (ip.IsLoopback() || ip.IsUnspecified()))) {
		return errors.New("프록시의 연결 대상이 자기 자신입니다. 일반 서버의 주소와 포트를 선택하세요")
	}
	return nil
}

func applyInstanceCreationDefaults(p *ManagedInstance) error {
	p.ID = strings.ToLower(strings.TrimSpace(p.ID))
	if !instanceIDPattern.MatchString(p.ID) {
		return errors.New("서버 ID가 올바르지 않습니다")
	}
	if strings.TrimSpace(p.Dir) == "" {
		base, err := filepath.Abs(filepath.Dir(configPath))
		if err != nil {
			return err
		}
		p.Dir = filepath.Join(base, "servers", p.ID)
	}
	if p.JavaPort != 0 {
		return nil
	}
	profiles, err := listManagedInstances()
	if err != nil {
		return err
	}
	used := map[int]bool{8790: true}
	c := configSnapshot()
	used[c.Port] = true
	for _, s := range c.Servers {
		for _, port := range []int{s.JavaPort, s.RCONPort, s.GDSAPIPort, s.BedrockPort} {
			used[port] = true
		}
	}
	for _, s := range profiles {
		used[s.JavaPort] = true
		used[s.BridgePort] = true
	}
	instanceInstallMu.Lock()
	for _, j := range instanceInstallJobs {
		if j.Phase != "complete" && j.Phase != "failed" {
			used[j.profile.JavaPort] = true
		}
	}
	instanceInstallMu.Unlock()
	ports := []int{}
	if p.Kind == "velocity" {
		ports = append(ports, 25577, 25578, 25579)
	}
	for port := 25580; port <= 25680; port++ {
		ports = append(ports, port)
	}
	for _, port := range ports {
		if used[port] {
			continue
		}
		listener, err := net.Listen("tcp", net.JoinHostPort("", strconv.Itoa(port)))
		if err != nil {
			continue
		}
		_ = listener.Close()
		p.JavaPort = port
		return nil
	}
	return errors.New("자동 선택할 빈 서버 포트가 없습니다. 고급 설정에서 포트를 지정하세요")
}
