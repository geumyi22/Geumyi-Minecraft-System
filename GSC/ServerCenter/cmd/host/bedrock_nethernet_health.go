package main

import (
	"encoding/json"
	"io"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// NetherNet replaced RakNet for current Bedrock clients. Discovery is a
// readiness check only: it does NOT prove an authenticated WebRTC/gameplay join.
func matchesNetherNetJoin(body []byte) bool {
	if len(body) > 64<<10 {
		return false
	}
	var info struct {
		DataVersion    int    `json:"dataVersion"`
		Protocol       int    `json:"protocol"`
		Version        string `json:"version"`
		TransportLayer int    `json:"transportLayer"`
	}
	if json.Unmarshal(body, &info) != nil {
		return false
	}
	return info.DataVersion > 0 && info.Protocol > 0 && strings.TrimSpace(info.Version) != "" && len(info.Version) <= 64 && info.TransportLayer == 2
}
func probeBedrockNetherNet(port int) bool {
	if port < 1 || port > 65535 {
		return false
	}
	client := &http.Client{Timeout: 1500 * time.Millisecond, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	resp, err := client.Get("http://" + net.JoinHostPort("127.0.0.1", strconv.Itoa(port)) + "/v1/join")
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return false
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, (64<<10)+1))
	return err == nil && matchesNetherNetJoin(body)
}
func probeBedrockTransportReady(port int) bool {
	return probeBedrockNetherNet(port) || probeBedrockRaknet(port)
}
