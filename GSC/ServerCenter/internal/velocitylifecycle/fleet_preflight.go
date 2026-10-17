package velocitylifecycle

import (
	"crypto/subtle"
	"strings"
	"time"
)

// These are artifact identities observed from the operator's sanitized,
 // read-only fingerprints, NOT proof of the binaries currently in JVM memory.
const velocity420Build30SHA = "35a5596a5468a035d8a32c8de5ebb0dc6b8d8f0cc3ff5169d514aca762af8aa8"

// ProxySnapshot is synthetic, in-memory input ONLY. The package neither
// reads Windows processes nor asserts that these supplied facts are trusted.
// Never serialize a snapshot: fields can contain OS-process metadata.
type ProxySnapshot struct {
	Target string
	ObservedAt time.Time
	TaskDefinitionMatches bool
	TaskToParentIndependentlyAttested bool
	ParentPID int
	ChildPID int
	ChildParentPID int
	UDPOwnerPID int
	TCPOwnerPID int
	TCPInventoryPresent bool
	JavaStatusResponded bool
	BedrockRaknetPong bool
	VelocitySHA256 string
}

// ProxyFinding deliberately omits raw PIDs and paths. In particular,
// Responding=true is never process identity proof, and SourceVerified=false
// remains true until a real, separately authenticated host adapter exists.
type ProxyFinding struct {
	Target string `json:"target"`
	Classification string `json:"classification"`
	ArtifactMatchesReference bool `json:"artifact_matches_reference"`
	OwnerCorrelationInSnapshot bool `json:"owner_correlation_in_snapshot"`
	PublicTCPResponded bool `json:"public_tcp_responded"`
	BedrockPongResponded bool `json:"bedrock_pong_responded"`
	TCPInventoryMissing bool `json:"tcp_inventory_missing"`
	SourceVerified bool `json:"source_verified"`
	SafeToExecute bool `json:"safe_to_execute"`
	Reasons []string `json:"reasons"`
}

type FleetFinding struct {
	Schema int `json:"schema"`
	ReadOnly bool `json:"read_only"`
	AllThreePresent bool `json:"all_three_present"`
	CrossProxyOwnersDistinct bool `json:"cross_proxy_owners_distinct"`
	SourceVerified bool `json:"source_verified"`
	SafeToExecute bool `json:"safe_to_execute"`
	Proxies []ProxyFinding `json:"proxies"`
}

func proxyPorts(target string) (int, int) {
	switch target {
	case "wild": return 25565, 19132
	case "playground": return 25566, 19133
	case "other": return 25567, 19134
	default: return 0, 0
	}
}

// InspectProxyFleet is a pure classification of three synthetic snapshots.
// It intentionally has no control side effects and NEVER grants stop/start.
// It cannot prove live ownership because the caller can forge this input.
func InspectProxyFleet(snapshots []ProxySnapshot, now time.Time) FleetFinding {
	out := FleetFinding{Schema: 1, ReadOnly: true, Proxies: []ProxyFinding{}}
	expected := []string{"wild", "playground", "other"}
	snapshotByTarget := make(map[string]ProxySnapshot, len(snapshots))
	noDuplicates := len(snapshots) == len(expected)
	for _, snap := range snapshots {
		if !validTarget(snap.Target) {
			noDuplicates = false
			continue
		}
		if _, exists := snapshotByTarget[snap.Target]; exists { noDuplicates = false }
		snapshotByTarget[snap.Target] = snap
	}
	out.AllThreePresent = noDuplicates && len(snapshotByTarget) == len(expected)

	// Count both parent and child JVMs. No JVM identity may be shared between
	// independently scheduled proxies, including parent-as-other-child.
	processIDs := make(map[int]string, 6)
	unique := out.AllThreePresent
	for _, target := range expected {
		s, ok := snapshotByTarget[target]
		if !ok { unique = false; continue }
		for _, pid := range []int{s.ParentPID, s.ChildPID} {
			if pid <= 0 { unique = false; continue }
			if owner, exists := processIDs[pid]; exists && owner != target {
				unique = false
			}
			processIDs[pid] = target
		}
		if s.ParentPID == s.ChildPID { unique = false }
	}
	out.CrossProxyOwnersDistinct = unique

	for _, target := range expected {
		s, present := snapshotByTarget[target]
		f := ProxyFinding{Target: target, Classification: "unverified", Reasons: []string{}}
		if !present || !out.AllThreePresent {
			f.Reasons = append(f.Reasons, "incomplete_or_duplicate_proxy_snapshot")
		}
		if !present { out.Proxies = append(out.Proxies, f); continue }
		javaPort, udpPort := proxyPorts(target)
		if javaPort == 0 || udpPort == 0 { f.Reasons=append(f.Reasons,"target_not_allowed") }
		// Real source timestamps must be fresh; future timestamps also fail.
		if now.IsZero() || s.ObservedAt.IsZero() || s.ObservedAt.After(now) ||
			now.Sub(s.ObservedAt) > 30*time.Second {
			f.Reasons = append(f.Reasons, "snapshot_stale_or_future")
		}
		if !s.TaskDefinitionMatches || !s.TaskToParentIndependentlyAttested {
			f.Reasons = append(f.Reasons, "task_to_parent_identity_unverified")
		}
		f.ArtifactMatchesReference = len(s.VelocitySHA256) == len(velocity420Build30SHA) &&
			subtle.ConstantTimeCompare(
				[]byte(strings.ToLower(s.VelocitySHA256)), []byte(velocity420Build30SHA)) == 1
		if !f.ArtifactMatchesReference { f.Reasons=append(f.Reasons,"jar_artifact_not_matching_reference") }
		f.OwnerCorrelationInSnapshot = unique && s.ParentPID > 0 &&
			s.ChildPID > 0 && s.ParentPID != s.ChildPID &&
			s.ChildParentPID == s.ParentPID && s.UDPOwnerPID == s.ChildPID
		if !f.OwnerCorrelationInSnapshot { f.Reasons=append(f.Reasons,"udp_owner_or_process_lineage_conflict") }
		f.PublicTCPResponded = s.JavaStatusResponded
		f.BedrockPongResponded = s.BedrockRaknetPong
		f.TCPInventoryMissing = !s.TCPInventoryPresent
		if s.TCPInventoryPresent && (s.TCPOwnerPID <= 0 || s.TCPOwnerPID != s.ChildPID) {
			f.Reasons = append(f.Reasons, "tcp_owner_conflict")
		}
		if !s.JavaStatusResponded { f.Reasons=append(f.Reasons,"java_application_status_unverified") }
		if !s.BedrockRaknetPong { f.Reasons=append(f.Reasons,"bedrock_raknet_unverified") }
		if len(f.Reasons) == 0 {
			f.Classification = "snapshot_correlated_runtime_identity_still_unverified"
			if f.TCPInventoryMissing {
				// Missing Windows TCP inventory is not a TCP outage when
				// independent Java application status is responding.
				f.Classification = "tcp_inventory_gap_java_application_responding"
			}
		} else {
			f.Classification = "blocked_inconsistent_or_incomplete_evidence"
		}
		// Intentionally irreversible: a simulation is never an operator
		// credential, an authenticated plugin peer or a live permission.
		f.SourceVerified = false
		f.SafeToExecute = false
		out.Proxies = append(out.Proxies, f)
	}
	out.SourceVerified = false
	out.SafeToExecute = false
	return out
}
