package main

import (
	"bufio"
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

const wsGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

type wsClient struct {
	conn      net.Conn
	mu        sync.Mutex
	principal authPrincipal
}

type wsEnvelope struct {
	Type string `json:"type"`
	Time string `json:"time"`
	Data any    `json:"data,omitempty"`
}

var wsHub struct {
	sync.RWMutex
	clients map[*wsClient]struct{}
}

func initWebSocketHub() {
	wsHub.Lock()
	if wsHub.clients == nil {
		wsHub.clients = map[*wsClient]struct{}{}
	}
	wsHub.Unlock()
	go wsHeartbeatLoop()
}

func wsClientCount() int {
	wsHub.RLock()
	defer wsHub.RUnlock()
	return len(wsHub.clients)
}

func wsPublish(kind string, data any) {
	env := wsEnvelope{Type: kind, Time: time.Now().Format(time.RFC3339Nano), Data: data}
	b, err := json.Marshal(env)
	if err != nil {
		return
	}
	wsHub.RLock()
	clients := make([]*wsClient, 0, len(wsHub.clients))
	for c := range wsHub.clients {
		clients = append(clients, c)
	}
	wsHub.RUnlock()
	for _, c := range clients {
		if err := c.writeFrame(0x1, b); err != nil {
			removeWSClient(c)
		}
	}
}

func removeWSClient(c *wsClient) {
	wsHub.Lock()
	if _, ok := wsHub.clients[c]; ok {
		delete(wsHub.clients, c)
		_ = c.conn.Close()
	}
	wsHub.Unlock()
}

func wsHeartbeatLoop() {
	t := time.NewTicker(25 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-hostQuit:
			return
		case <-t.C:
			wsHub.RLock()
			clients := make([]*wsClient, 0, len(wsHub.clients))
			for c := range wsHub.clients {
				clients = append(clients, c)
			}
			wsHub.RUnlock()
			for _, c := range clients {
				if err := c.writeFrame(0x9, []byte("gsc")); err != nil {
					removeWSClient(c)
				}
			}
		}
	}
}

func validWSOrigin(r *http.Request) bool {
	o := strings.TrimSpace(r.Header.Get("Origin"))
	if o == "" {
		return true
	}
	u, err := url.Parse(o)
	if err != nil {
		return false
	}
	host := strings.ToLower(u.Host)
	reqHost := strings.ToLower(r.Host)
	if host == reqHost {
		return true
	}
	h := strings.Split(host, ":")[0]
	return h == "127.0.0.1" || h == "localhost" || h == "[::1]"
}

func apiV1WebSocket(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required", 405)
		return
	}
	if !validWSOrigin(r) {
		http.Error(w, "origin not allowed", http.StatusForbidden)
		return
	}
	if !strings.EqualFold(strings.TrimSpace(r.Header.Get("Upgrade")), "websocket") || !headerHasToken(r.Header.Get("Connection"), "upgrade") {
		http.Error(w, "websocket upgrade required", http.StatusUpgradeRequired)
		return
	}
	key := strings.TrimSpace(r.Header.Get("Sec-WebSocket-Key"))
	if key == "" {
		http.Error(w, "missing websocket key", 400)
		return
	}
	if v := strings.TrimSpace(r.Header.Get("Sec-WebSocket-Version")); v != "13" {
		w.Header().Set("Sec-WebSocket-Version", "13")
		http.Error(w, "websocket version 13 required", 426)
		return
	}
	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "websocket unsupported", 500)
		return
	}
	conn, rw, err := hj.Hijack()
	if err != nil {
		return
	}
	accept := wsAccept(key)
	_, _ = fmt.Fprintf(rw, "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n", accept)
	_ = rw.Flush()
	c := &wsClient{conn: conn, principal: principalFromRequest(r)}
	wsHub.Lock()
	wsHub.clients[c] = struct{}{}
	wsHub.Unlock()
	appendAudit(r, "websocket.connect", "control-api-v1", "accepted", principalLabel(c.principal))
	hello := map[string]any{"gsc_version": appVersion, "api_version": controlAPIVersion, "client_count": wsClientCount(), "principal": c.principal}
	_ = c.writeJSON("hello", hello)
	cfg := configSnapshot()
	views := make([]ControlServerView, 0, len(cfg.Servers))
	for _, s := range cfg.Servers {
		views = append(views, controlServerView(s))
	}
	_ = c.writeJSON("snapshot", map[string]any{"servers": views, "active_jobs": activeControlJobCount()})
	go c.readLoop(r)
}

func wsAccept(key string) string {
	h := sha1.Sum([]byte(key + wsGUID))
	return base64.StdEncoding.EncodeToString(h[:])
}

func headerHasToken(v, token string) bool {
	for _, x := range strings.Split(v, ",") {
		if strings.EqualFold(strings.TrimSpace(x), token) {
			return true
		}
	}
	return false
}

func (c *wsClient) writeJSON(kind string, data any) error {
	b, err := json.Marshal(wsEnvelope{Type: kind, Time: time.Now().Format(time.RFC3339Nano), Data: data})
	if err != nil {
		return err
	}
	return c.writeFrame(0x1, b)
}

func (c *wsClient) writeFrame(op byte, payload []byte) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if len(payload) > 16<<20 {
		return errors.New("websocket payload too large")
	}
	h := []byte{0x80 | (op & 0x0f)}
	n := len(payload)
	switch {
	case n < 126:
		h = append(h, byte(n))
	case n <= 0xffff:
		h = append(h, 126, byte(n>>8), byte(n))
	default:
		h = append(h, 127, 0, 0, 0, 0, byte(uint64(n)>>24), byte(uint64(n)>>16), byte(uint64(n)>>8), byte(n))
	}
	_ = c.conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
	if _, err := c.conn.Write(h); err != nil {
		return err
	}
	if n > 0 {
		_, err := c.conn.Write(payload)
		return err
	}
	return nil
}

func (c *wsClient) readLoop(r *http.Request) {
	defer func() {
		removeWSClient(c)
		appendAudit(r, "websocket.disconnect", "control-api-v1", "completed", principalLabel(c.principal))
	}()
	br := bufio.NewReader(c.conn)
	for {
		op, payload, err := readWSFrame(br, c.conn)
		if err != nil {
			return
		}
		switch op {
		case 0x8:
			_ = c.writeFrame(0x8, nil)
			return
		case 0x9:
			if len(payload) > 125 {
				return
			}
			_ = c.writeFrame(0xA, payload)
		case 0xA:
			// pong
		case 0x1:
			// v1 websocket is server-push only. Ignore text input except ping-like JSON.
			if len(payload) > 0 && strings.Contains(string(payload), `"type":"ping"`) {
				_ = c.writeJSON("pong", map[string]any{"ok": true})
			}
		default:
			// Ignore unsupported data frames; control actions go through authenticated HTTP endpoints.
		}
	}
}

func readWSFrame(br *bufio.Reader, conn net.Conn) (byte, []byte, error) {
	_ = conn.SetReadDeadline(time.Now().Add(70 * time.Second))
	b0, err := br.ReadByte()
	if err != nil {
		return 0, nil, err
	}
	b1, err := br.ReadByte()
	if err != nil {
		return 0, nil, err
	}
	if b0&0x80 == 0 {
		return 0, nil, errors.New("fragmented frames not supported")
	}
	op := b0 & 0x0f
	masked := b1&0x80 != 0
	if !masked {
		return 0, nil, errors.New("client frame must be masked")
	}
	n := uint64(b1 & 0x7f)
	if n == 126 {
		var x uint16
		if err = binary.Read(br, binary.BigEndian, &x); err != nil {
			return 0, nil, err
		}
		n = uint64(x)
	} else if n == 127 {
		if err = binary.Read(br, binary.BigEndian, &n); err != nil {
			return 0, nil, err
		}
	}
	if n > 1<<20 {
		return 0, nil, errors.New("client websocket frame too large")
	}
	mask := make([]byte, 4)
	if _, err = io.ReadFull(br, mask); err != nil {
		return 0, nil, err
	}
	p := make([]byte, int(n))
	if _, err = io.ReadFull(br, p); err != nil {
		return 0, nil, err
	}
	for i := range p {
		p[i] ^= mask[i%4]
	}
	return op, p, nil
}
