package main

import (
	"bytes"
	"context"
	_ "embed"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"os/exec"
	"runtime"
	"time"
	"unicode/utf16"
)

//go:embed velocity_status.ps1
var velocityStatusPS string

// velocityInventory contains only task and socket summary flags. No credentials,
// process command lines, filesystem paths or raw identifiers are returned.
type velocityInventory struct {
	Schema                     int                   `json:"schema"`
	ReadOnly                   bool                  `json:"read_only"`
	ProcessPairCensusConsistent bool               `json:"process_pair_census_consistent"`
	UDPThreeUniqueChildOwners bool                 `json:"udp_three_unique_child_owners"`
	TaskProcessIdentityVerified bool               `json:"task_process_identity_verified"`
	LiveJavaRaknetE2EVerified bool                 `json:"live_java_raknet_e2e_verified"`
	Proxies                    []velocityProxyStatus `json:"proxies"`
}

type velocityProxyStatus struct {
	ID                  string `json:"id"`
	TaskPresent         bool   `json:"task_present"`
	TaskMatchesBaseline bool   `json:"task_matches_baseline"`
	TaskState           string `json:"task_state"`
	JavaPort            int    `json:"java_port"`
	BedrockPort         int    `json:"bedrock_port"`
	JavaListening       bool   `json:"java_listening"`
	BedrockListening    bool   `json:"bedrock_listening"`
	PortOwnerConsistent bool   `json:"port_owner_consistent"`
	UDPOwnerMatchesVelocityChild bool `json:"udp_owner_matches_velocity_child"`
	Status              string `json:"status"`
}

func decodeVelocityInventory(raw []byte) (velocityInventory, error) {
	var inventory velocityInventory
	if len(raw) > (1 << 20) || json.Unmarshal(bytes.TrimSpace(raw), &inventory) != nil {
		return inventory, errors.New("invalid Velocity inventory JSON")
	}
	if inventory.Schema != 1 || !inventory.ReadOnly || len(inventory.Proxies) != 3 ||
		inventory.TaskProcessIdentityVerified || inventory.LiveJavaRaknetE2EVerified ||
		(inventory.UDPThreeUniqueChildOwners && !inventory.ProcessPairCensusConsistent) {
		// The read-only phase must never assert full task-to-process identity or real E2E.
		return inventory, errors.New("unexpected Velocity inventory schema")
	}
	expected := []struct {
		id string
		tcp, udp int
	}{
		{"wild", 25565, 19132},
		{"playground", 25566, 19133},
		{"other", 25567, 19134},
	}
	for i, item := range inventory.Proxies {
		if item.ID != expected[i].id ||
			item.JavaPort != expected[i].tcp || item.BedrockPort != expected[i].udp {
			return inventory, errors.New("unexpected Velocity inventory target")
		}
		if item.UDPOwnerMatchesVelocityChild && !inventory.UDPThreeUniqueChildOwners {
			return inventory, errors.New("Velocity child owner claimed without fleet census")
		}
		if item.Status == "tcp_inventory_missing_udp_child_verified" &&
			(!inventory.UDPThreeUniqueChildOwners || !item.UDPOwnerMatchesVelocityChild ||
			 !item.BedrockListening || item.JavaListening ||
			 !item.TaskPresent || !item.TaskMatchesBaseline || item.TaskState != "Running") {
			return inventory, errors.New("inconsistent TCP telemetry gap evidence")
		}
		switch item.Status {
		case "task_missing_or_duplicate", "task_config_drift", "offline_or_starting",
			"ports_ready_owner_unverified", "ports_partial_or_conflicting", "unverified",
			"task_not_running_unverified", "socket_inventory_missing",
			"tcp_inventory_missing_udp_visible", "tcp_inventory_missing_udp_child_verified",
			"udp_inventory_missing_tcp_visible":
		default:
			return inventory, errors.New("unexpected Velocity inventory state")
		}
	}
	return inventory, nil
}

func velocityInventoryCommand(ctx context.Context) *exec.Cmd {
	// The script is compiled into GSC. No user-provided values enter PowerShell,
	// and no script is written to or executed from a writable temp folder.
	runes := utf16.Encode([]rune(velocityStatusPS))
	wide := make([]byte, len(runes)*2)
	for i, v := range runes {
		wide[i*2], wide[i*2+1] = byte(v), byte(v>>8)
	}
	encoded := base64.StdEncoding.EncodeToString(wide)
	return exec.CommandContext(ctx, "powershell.exe", "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded)
}

// apiV4VelocityStatus supports GET only. It deliberately does not expose
// Stop-ScheduledTask, task creation, forced process termination, or restart.
func apiV4VelocityStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET required: Velocity operations are not enabled", http.StatusMethodNotAllowed)
		return
	}
	if runtime.GOOS != "windows" {
		http.Error(w, "Velocity task inventory is Windows-only", http.StatusNotImplemented)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
	defer cancel()
	// The context kills the PowerShell inspection subprocess on timeout;
	// it does not affect Velocity or its scheduler tasks.
	cmd := velocityInventoryCommand(ctx)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		// Do not expose PowerShell diagnostic text: it may contain system paths.
		http.Error(w, "Velocity read-only inventory unavailable", http.StatusServiceUnavailable)
		return
	}
	info, err := decodeVelocityInventory(out)
	if err != nil {
		http.Error(w, "Velocity inventory could not be verified", http.StatusBadGateway)
		return
	}
	writeJSON(w, info)
}

