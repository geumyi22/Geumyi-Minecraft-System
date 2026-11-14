package main

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"strings"
	"testing"
)

func TestInstancePurpurTransportUsesVerifiedHTTP1(t *testing.T) {
	tc := instancePurpurHTTP1Transport.TLSClientConfig
	if tc == nil || tc.InsecureSkipVerify || len(tc.NextProtos) != 1 || tc.NextProtos[0] != "http/1.1" || instancePurpurHTTP1Transport.ForceAttemptHTTP2 {
		t.Fatal("Purpur transport must keep certificate verification and negotiate only HTTP/1.1")
	}
}

func TestInstancePurpurRangesReassembleExactBytes(t *testing.T) {
	data := bytes.Repeat([]byte("official-server-test"), 100000)
	old := instanceInstallHTTP
	t.Cleanup(func() { instanceInstallHTTP = old })
	instanceInstallHTTP = &http.Client{Transport: instanceInstallerTransport(func(r *http.Request) (*http.Response, error) {
		var start, end int64
		if _, err := fmt.Sscanf(r.Header.Get("Range"), "bytes=%d-%d", &start, &end); err != nil {
			return nil, err
		}
		if start < 0 || end >= int64(len(data)) {
			return nil, fmt.Errorf("range outside artifact")
		}
		header := make(http.Header)
		header.Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, end, len(data)))
		return &http.Response{StatusCode: 206, Header: header, Body: io.NopCloser(bytes.NewReader(data[start : end+1])), ContentLength: end - start + 1, Request: r}, nil
	})}
	got, err := instanceFetchPurpurServer(context.Background(), "https://api.purpurmc.org/v2/purpur/26.3/2658/download")
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, data) {
		t.Fatal("partitioned download changed artifact bytes")
	}
}

func TestInstancePurpurRejectsWrongContentRange(t *testing.T) {
	old := instanceInstallHTTP
	t.Cleanup(func() { instanceInstallHTTP = old })
	instanceInstallHTTP = &http.Client{Transport: instanceInstallerTransport(func(r *http.Request) (*http.Response, error) {
		header := make(http.Header)
		header.Set("Content-Range", "bytes 1-1/100")
		return &http.Response{StatusCode: 206, Header: header, Body: io.NopCloser(strings.NewReader("x")), ContentLength: 1, Request: r}, nil
	})}
	if _, err := instanceFetchPurpurServer(context.Background(), "https://api.purpurmc.org/v2/purpur/26.3/2658/download"); err == nil {
		t.Fatal("accepted wrong range")
	}
}
