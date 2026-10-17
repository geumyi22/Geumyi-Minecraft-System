package main

import (
	"context"
	"errors"
	"net/http"
	"runtime"
	"strings"
	"time"
)

// VelocityControlPreflight is a read-only decision aid, not a capability token.
// safe_to_execute is deliberately always false until a separately reviewed
// graceful control path and live Windows tests exist.
type velocityControlPreflight struct {
	Schema int `json:"schema"`
	ReadOnly bool `json:"read_only"`
	Target string `json:"target"`
	Action string `json:"action"`
	SafeToExecute bool `json:"safe_to_execute"`
	Decision string `json:"decision"`
	Reasons []string `json:"reasons"`
	Observed velocityPreflightObservation `json:"observed"`
	LiveClientE2EVerified bool `json:"live_client_e2e_verified"`
	OperatorApprovalCaptured bool `json:"operator_approval_captured"`
}

type velocityPreflightObservation struct {
	TaskPresent bool `json:"task_present"`
	TaskMatchesBaseline bool `json:"task_matches_baseline"`
	TaskRunning bool `json:"task_running"`
	SixJavaProcessCensusConsistent bool `json:"six_java_process_census_consistent"`
	UDPThreeUniqueChildOwners bool `json:"udp_three_unique_child_owners"`
	TargetUDPChildOwnerObserved bool `json:"target_udp_child_owner_observed"`
	TaskProcessIdentityVerified bool `json:"task_process_identity_verified"`
	JavaTCPProbeResponding bool `json:"java_tcp_probe_responding"`
	BedrockRaknetPong bool `json:"bedrock_raknet_pong"`
	TCPListenerTelemetryPresent bool `json:"tcp_listener_telemetry_present"`
	UDPListenerTelemetryPresent bool `json:"udp_listener_telemetry_present"`
}

func velocityPreflightTarget(id string) bool {
	switch id {
	case "wild", "playground", "other":
		return true
	default:
		return false
	}
}

func velocityPreflightAction(action string) bool {
	switch action {
	case "start", "stop", "restart":
		return true
	default:
		return false
	}
}

func buildVelocityControlPreflight(info velocityInventory, target, action string, javaResponding, raknetPong bool) (velocityControlPreflight, error) {
	if !velocityPreflightTarget(target) || !velocityPreflightAction(action) {
		return velocityControlPreflight{}, errors.New("invalid Velocity preflight selection")
	}
	var status *velocityProxyStatus
	for i := range info.Proxies {
		if info.Proxies[i].ID == target {
			status = &info.Proxies[i]
			break
		}
	}
	if status == nil {
		return velocityControlPreflight{}, errors.New("unknown Velocity proxy in inventory")
	}
	observed := velocityPreflightObservation{
		TaskPresent: status.TaskPresent,
		TaskMatchesBaseline: status.TaskMatchesBaseline,
		TaskRunning: status.TaskState == "Running",
		SixJavaProcessCensusConsistent: info.ProcessPairCensusConsistent,
		UDPThreeUniqueChildOwners: info.UDPThreeUniqueChildOwners,
		TargetUDPChildOwnerObserved: status.UDPOwnerMatchesVelocityChild,
		TaskProcessIdentityVerified: false,
		JavaTCPProbeResponding: javaResponding,
		BedrockRaknetPong: raknetPong,
		TCPListenerTelemetryPresent: status.JavaListening,
		UDPListenerTelemetryPresent: status.BedrockListening,
	}
	reasons := []string{
		"operator_approval_not_collected",
		"task_process_identity_unverified",
		"live_client_e2e_not_verified",
	}
	if !status.TaskPresent || !status.TaskMatchesBaseline || status.TaskState != "Running" {
		reasons = append(reasons, "task_preflight_not_verified")
	}
	if !info.ProcessPairCensusConsistent || !info.UDPThreeUniqueChildOwners || !status.UDPOwnerMatchesVelocityChild {
		reasons = append(reasons, "process_topology_not_verified")
	}
	switch action {
	case "start":
		// A blank Windows TCP provider is not proof that an existing proxy has
		// stopped or that its listener port is available.
		reasons = append(reasons, "target_runtime_absence_unproven", "port_availability_unproven")
		if javaResponding || raknetPong {
			reasons = append(reasons, "target_port_responding")
		}
	case "stop":
		reasons = append(reasons, "graceful_shutdown_control_unavailable", "player_count_unknown", "task_auto_restart_not_mitigated")
	case "restart":
		reasons = append(reasons, "graceful_shutdown_control_unavailable", "player_count_unknown",
			"task_auto_restart_not_mitigated", "port_availability_unproven",
			"shutdown_and_start_health_sequence_unverified")
	}
	return velocityControlPreflight{
		Schema: 1, ReadOnly: true, Target: target, Action: action,
		SafeToExecute: false, Decision: "blocked", Reasons: reasons, Observed: observed,
		LiveClientE2EVerified: false, OperatorApprovalCaptured: false,
	}, nil
}

// apiV4VelocityControlPreflight is explicitly limited to GET and never runs a
// lifecycle action. This route must not be used as a future POST action route.
func apiV4VelocityControlPreflight(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET only: Velocity lifecycle controls unavailable", http.StatusMethodNotAllowed)
		return
	}
	target := strings.TrimSpace(r.URL.Query().Get("id"))
	action := strings.TrimSpace(r.URL.Query().Get("action"))
	if !velocityPreflightTarget(target) || !velocityPreflightAction(action) {
		http.Error(w, "invalid Velocity target or action", http.StatusBadRequest)
		return
	}
	if runtime.GOOS != "windows" {
		http.Error(w, "Windows-only Velocity preflight", http.StatusNotImplemented)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
	defer cancel()
	cmd := velocityInventoryCommand(ctx)
	raw, err := cmd.Output()
	if err != nil {
		// Keep system error text and paths private.
		http.Error(w, "Velocity read-only process inventory unavailable", http.StatusServiceUnavailable)
		return
	}
	info, err := decodeVelocityInventory(raw)
	if err != nil {
		http.Error(w, "Velocity preflight inventory invalid", http.StatusBadGateway)
		return
	}
	var tcpPort, udpPort int
	for _, p := range info.Proxies {
		if p.ID == target {
			tcpPort, udpPort = p.JavaPort, p.BedrockPort
			break
		}
	}
	// Network probes use fixed local TCP/RakNet ports, never arbitrary client
	// addresses. Their results do not establish task-to-process ownership.
	javaResponding := probeJavaTCP(tcpPort)
	raknetPong := probeBedrockRaknet(udpPort)
	preview, err := buildVelocityControlPreflight(info, target, action, javaResponding, raknetPong)
	if err != nil {
		http.Error(w, "Velocity preflight rejected", http.StatusBadGateway)
		return
	}
	writeJSON(w, preview)
}
