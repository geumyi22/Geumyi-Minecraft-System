package main

import (
	"bytes"
	"encoding/binary"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"
)

func loopbackOnly(fn http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !isLoopbackRemote(r.RemoteAddr) {
			http.Error(w, "loopback only", http.StatusForbidden)
			return
		}
		fn(w, r)
	}
}

func apiV4NetworkServerState(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", http.StatusMethodNotAllowed)
		return
	}
	id := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("id")))
	s, ok := serverByID(id)
	if !ok {
		http.Error(w, "unknown server", http.StatusBadRequest)
		return
	}

	st := getServerStatus(s)
	update := updateStatusFor(s.ID)
	phase := strings.ToLower(strings.TrimSpace(update.Phase))

	blockedUpdate := false
	switch phase {
	case "checking", "downloading", "pending_health", "health_check", "rolling_back", "rollback_failed", "blocked":
		blockedUpdate = true
	}

	allowed := st.Online &&
		currentOperation(s.ID) == "" &&
		activeControlJob(s.ID) == nil &&
		!st.Schedule.Active &&
		!blockedUpdate

	reason := ""
	if !st.Online {
		reason = "offline"
	} else if currentOperation(s.ID) != "" {
		reason = "maintenance"
	} else if activeControlJob(s.ID) != nil || st.Schedule.Active {
		reason = "lifecycle"
	} else if blockedUpdate {
		reason = "update_" + phase
	}

	writeJSON(w, map[string]any{
		"id":             s.ID,
		"role":           normalizeServerConfig(s).Role,
		"online":         st.Online,
		"state":          st.State,
		"move_allowed":   allowed,
		"blocked_reason": reason,
		"update_phase":   update.Phase,
	})
}

const raknetPongID byte = 0x1c

var raknetMagic = []byte{0, 255, 255, 0, 254, 254, 254, 254, 253, 253, 253, 253, 18, 52, 86, 120}

type networkEndpointStatus struct {
	ID string `json:"id"`
	JavaTCP int `json:"java_tcp"`
	BedrockUDP int `json:"bedrock_udp"`
	JavaResponding bool `json:"java_responding"`
	BedrockRaknetPong bool `json:"bedrock_raknet_pong"`
}

func day10NetworkEndpoints() []networkEndpointStatus {
	return []networkEndpointStatus{
		{ID: "wild", JavaTCP: 25565, BedrockUDP: 19132},
		{ID: "playground", JavaTCP: 25566, BedrockUDP: 19133},
		{ID: "other", JavaTCP: 25567, BedrockUDP: 19134},
	}
}

func matchesRaknetPong(packet []byte) bool {
	return len(packet) >= 33 && packet[0] == raknetPongID &&
		bytes.Equal(packet[17:33], raknetMagic)
}

func probeJavaTCP(port int) bool {
	conn, err := net.DialTimeout("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(port)), 250*time.Millisecond)
	if err != nil { return false }
	_ = conn.Close()
	return true
}

func probeBedrockRaknet(port int) bool {
	conn, err := net.DialTimeout("udp", net.JoinHostPort("127.0.0.1", strconv.Itoa(port)), 500*time.Millisecond)
	if err != nil { return false }
	defer conn.Close()
	// RakNet UNCONNECTED_PING: packet ID, time, 16-byte magic, client GUID.
	ping := make([]byte, 33)
	ping[0] = 0x01
	binary.BigEndian.PutUint64(ping[1:9], uint64(time.Now().UnixMilli()))
	copy(ping[9:25], raknetMagic)
	_ = conn.SetDeadline(time.Now().Add(550*time.Millisecond))
	if _, err := conn.Write(ping); err != nil { return false }
	pong := make([]byte, 1492)
	n, err := conn.Read(pong)
	return err == nil && matchesRaknetPong(pong[:n])
}

// Local port responsiveness is not proof that a Velocity/Geyser process owns
// the socket, that its forwarding secret is correct, or that Lobby E2E passes.
func apiV4NetworkEntryStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", http.StatusMethodNotAllowed)
		return
	}
	status := day10NetworkEndpoints()
	for i := range status {
		status[i].JavaResponding = probeJavaTCP(status[i].JavaTCP)
		status[i].BedrockRaknetPong = probeBedrockRaknet(status[i].BedrockUDP)
	}
	writeJSON(w, map[string]any{
		"schema": 1,
		"endpoints": status,
		"note": "Port and RakNet responsiveness only. These results do not verify Velocity ownership or Lobby login.",
		"live_e2e_verified": false,
	})
}
