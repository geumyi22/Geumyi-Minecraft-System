package main

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sync"
	"sync/atomic"
	"time"
)

var errInstanceRangeUnsupported = errors.New("공식 다운로드 서버가 분할 다운로드를 지원하지 않습니다")

var instancePurpurHTTP1Transport = func() *http.Transport {
	t := http.DefaultTransport.(*http.Transport).Clone()
	// The observed Purpur CDN stalled large HTTP/2 bodies; HTTP/1 ranges were
	// verified against the complete official checksum. TLS verification stays on.
	t.ForceAttemptHTTP2 = false
	t.TLSNextProto = map[string]func(string, *tls.Conn) http.RoundTripper{}
	if t.TLSClientConfig == nil {
		t.TLSClientConfig = &tls.Config{}
	} else {
		t.TLSClientConfig = t.TLSClientConfig.Clone()
	}
	t.TLSClientConfig.NextProtos = []string{"http/1.1"}
	return t
}()

// Purpur's CDN supports byte ranges. Bounded requests avoid a stalled large
// response blocking the whole download; the publisher's full-file checksum is
// still verified by downloadInstanceServer before any file is written.
func instanceFetchPurpurServer(ctx context.Context, address string, progress ...func(int64, int64)) ([]byte, error) {
	_, size, err := instanceFetchServerRange(ctx, address, 0, 0, 0)
	if errors.Is(err, errInstanceRangeUnsupported) {
		return instanceFetch(ctx, address, 256<<20)
	}
	if err != nil {
		return nil, err
	}
	if size <= 0 || size > 256<<20 {
		return nil, errors.New("Purpur 다운로드 크기가 제한을 초과합니다")
	}
	data := make([]byte, int(size))
	type part struct{ start, end int64 }
	const block int64 = 1 << 20
	jobs := make(chan part, int((size+block-1)/block))
	for start := int64(0); start < size; start += block {
		end := start + block - 1
		if end >= size {
			end = size - 1
		}
		jobs <- part{start, end}
	}
	close(jobs)
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	failures := make(chan error, 1)
	var workers sync.WaitGroup
	var received atomic.Int64
	for i := 0; i < 4; i++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			for p := range jobs {
				if ctx.Err() != nil {
					return
				}
				var b []byte
				var err error
				for attempt := 0; attempt < 2; attempt++ {
					b, _, err = instanceFetchServerRange(ctx, address, p.start, p.end, size)
					if err == nil || ctx.Err() != nil {
						break
					}
				}
				if err != nil {
					select {
					case failures <- err:
					default:
					}
					cancel()
					return
				}
				copy(data[int(p.start):int(p.end+1)], b)
				done := received.Add(int64(len(b)))
				if len(progress) > 0 && progress[0] != nil {
					progress[0](done, size)
				}
			}
		}()
	}
	workers.Wait()
	select {
	case err := <-failures:
		return nil, err
	default:
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	return data, nil
}

func instanceFetchServerRange(ctx context.Context, address string, start, end, total int64) ([]byte, int64, error) {
	u, err := url.Parse(address)
	if err != nil {
		return nil, 0, err
	}
	if err = validateInstanceDownloadURL(u); err != nil {
		return nil, 0, err
	}
	ctx, cancel := context.WithTimeout(ctx, 90*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("User-Agent", "GeumyiServerCenter/"+appVersion+" (https://github.com/geumyi22/Geumyi-Minecraft-System)")
	req.Header.Set("Range", fmt.Sprintf("bytes=%d-%d", start, end))
	req.Header.Set("Accept-Encoding", "identity")
	client := instanceInstallHTTP
	if client.Transport == nil {
		copy := *client
		copy.Transport = instancePurpurHTTP1Transport
		client = &copy
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, 0, fmt.Errorf("다운로드 구간 %d–%d 요청 실패: %w", start, end, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusOK {
		return nil, 0, errInstanceRangeUnsupported
	}
	if resp.StatusCode != http.StatusPartialContent {
		return nil, 0, fmt.Errorf("공식 분할 다운로드 응답 %d", resp.StatusCode)
	}
	var gotStart, gotEnd, size int64
	if n, err := fmt.Sscanf(resp.Header.Get("Content-Range"), "bytes %d-%d/%d", &gotStart, &gotEnd, &size); err != nil || n != 3 || gotStart != start || gotEnd != end || size <= end || (total > 0 && total != size) {
		return nil, 0, errors.New("공식 분할 다운로드 범위가 일치하지 않습니다")
	}
	expected := end - start + 1
	if expected <= 0 || expected > 1<<20 {
		return nil, 0, errors.New("잘못된 다운로드 분할 크기입니다")
	}
	if resp.ContentLength >= 0 && resp.ContentLength != expected {
		return nil, 0, errors.New("공식 분할 다운로드 응답 길이가 일치하지 않습니다")
	}
	b := make([]byte, int(expected))
	n, err := io.ReadFull(resp.Body, b)
	if err != nil {
		return nil, 0, fmt.Errorf("다운로드 구간 %d–%d 수신 중단 (%d/%d bytes): %w", start, end, n, expected, err)
	}
	if int64(len(b)) != expected {
		return nil, 0, errors.New("공식 분할 다운로드 크기가 일치하지 않습니다")
	}
	return b, size, nil
}
