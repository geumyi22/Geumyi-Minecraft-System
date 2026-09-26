package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type V4MetricPoint struct {
	Time          string  `json:"time"`
	ServerID      string  `json:"server_id"`
	Online        bool    `json:"online"`
	Players       int     `json:"players"`
	JavaRAMMB     float64 `json:"java_ram_mb"`
	TPS           float64 `json:"tps,omitempty"`
	MSPT          float64 `json:"mspt,omitempty"`
	MemoryPercent float64 `json:"memory_percent,omitempty"`
	LoadedChunks  int     `json:"loaded_chunks,omitempty"`
	Entities      int     `json:"entities,omitempty"`
}

func numAny(v any) float64 {
	switch x := v.(type) {
	case float64:
		return x
	case int:
		return float64(x)
	case json.Number:
		f, _ := x.Float64()
		return f
	case string:
		f, _ := strconv.ParseFloat(x, 64)
		return f
	}
	return 0
}
func intAny(v any) int { return int(numAny(v)) }

func metricPath(id string) string { return filepath.Join(v4Root(), "metrics", id+".jsonl") }
func appendMetric(p V4MetricPoint) {
	b, _ := json.Marshal(p)
	path := metricPath(p.ServerID)
	_ = os.MkdirAll(filepath.Dir(path), 0755)
	if st, e := os.Stat(path); e == nil && st.Size() > 12<<20 {
		_ = trimMetricFile(path, 12000)
	}
	if f, e := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644); e == nil {
		_, _ = f.Write(append(b, '\n'))
		_ = f.Close()
	}
}
func trimMetricFile(path string, keep int) error {
	b, e := os.ReadFile(path)
	if e != nil {
		return e
	}
	lines := strings.Split(strings.TrimSpace(string(b)), "\n")
	if len(lines) > keep {
		lines = lines[len(lines)-keep:]
	}
	return os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0644)
}

func v4MetricsLoop() {
	ticker := time.NewTicker(15 * time.Second)
	defer ticker.Stop()
	time.Sleep(3 * time.Second)
	for {
		select {
		case <-hostQuit:
			return
		case <-ticker.C:
			c := configSnapshot()
			for _, s := range c.Servers {
				st := getServerStatus(s)
				p := V4MetricPoint{Time: time.Now().Format(time.RFC3339), ServerID: s.ID, Online: st.Online, Players: st.MC.Online, JavaRAMMB: st.Java.WorkingSetMB}
				if b := bridgeV4Status(s); b != nil {
					if m, ok := b["metrics"].(map[string]any); ok {
						p.TPS = numAny(m["tps_1m"])
						p.MSPT = numAny(m["mspt"])
						p.MemoryPercent = numAny(m["memory_percent"])
						p.LoadedChunks = intAny(m["loaded_chunks"])
						p.Entities = intAny(m["entities"])
					}
				}
				appendMetric(p)
			}
		}
	}
}

func readMetrics(id string, limit int) []V4MetricPoint {
	if limit <= 0 || limit > 10000 {
		limit = 720
	}
	f, e := os.Open(metricPath(id))
	if e != nil {
		return nil
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	buf := make([]byte, 64*1024)
	sc.Buffer(buf, 1024*1024)
	arr := make([]V4MetricPoint, 0, limit)
	for sc.Scan() {
		var p V4MetricPoint
		if json.Unmarshal(sc.Bytes(), &p) == nil {
			arr = append(arr, p)
			if len(arr) > limit {
				copy(arr, arr[len(arr)-limit:])
				arr = arr[:limit]
			}
		}
	}
	return arr
}
func apiV4Metrics(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Query().Get("id")
	if _, ok := serverByID(id); !ok {
		http.Error(w, "unknown server", 400)
		return
	}
	n, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	writeJSON(w, map[string]any{"server_id": id, "points": readMetrics(id, n), "sampling_seconds": 15, "note": fmt.Sprintf("최대 %d개 포인트 반환", func() int {
		if n <= 0 || n > 10000 {
			return 720
		}
		return n
	}())})
}
