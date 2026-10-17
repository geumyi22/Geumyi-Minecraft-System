// Package velocitylifecycle models a prospective safe Velocity lifecycle.
// It deliberately contains no OS, network, filesystem, task, or process control.
// In particular, a completed simulation is NEVER authorization to operate live.
package velocitylifecycle

import (
	"errors"
	"regexp"
	"strings"
	"time"
)

type Action string

const (
	Start   Action = "start"
	Stop    Action = "stop"
	Restart Action = "restart"
)

type Phase string

const (
	Preflight      Phase = "preflight"
	AwaitShutdown  Phase = "await_graceful_shutdown"
	AwaitStart     Phase = "await_verified_start"
	Complete       Phase = "simulation_complete"
	Blocked        Phase = "blocked"
)

var ticketPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{16,128}$`)

// Plan tracks ONLY synthetic evidence progression, not live control rights.
type Plan struct {
	Target          string
	Action          Action
	Ticket          string
	ExpiresAt       time.Time
	Phase           Phase
	Sequence        uint64
	OldGeneration   string
	BlockReason     string
	// Always false. No caller may treat this model as an execution permit.
	LiveAuthorized  bool
}

// Evidence is input from a disposable simulator. A future real adapter MUST
// authenticate and attest every field; bools are not proofs in production.
type Evidence struct {
	Target         string
	Ticket         string
	Sequence       uint64
	OperatorApproved bool
	MaintenanceWindowOpen bool
	TaskFingerprintVerified bool
	TaskProcessLineageVerified bool
	SchedulerAutoRestartControlled bool
	SiblingProxyGenerationsUnchanged bool
	NoDuplicateProxyProcesses bool
	AuditAvailable bool

	PlayersExactlyZeroVerified bool
	GracefulBridgeAuthenticated bool
	CurrentGeneration string

	// Presence is never inferred from empty Windows Get-NetTCPConnection output.
	TargetProcessFamilyAbsentVerified bool
	PublicTCPAndUDPFreeIndependentlyVerified bool
	GracefulShutdownAcknowledged bool
	StoppedGeneration string

	SchedulerStartReceiptVerified bool
	FreshProcessPairVerified bool
	NewGeneration string
	JavaTCPResponding bool
	BedrockRaknetPong bool
}

func validTarget(s string) bool {
	return s == "wild" || s == "playground" || s == "other"
}

func validAction(a Action) bool {
	return a == Start || a == Stop || a == Restart
}

// NewPlan produces an in-memory simulation, never an OS command or capability.
func NewPlan(target string, action Action, ticket string, deadline time.Time) (Plan, error) {
	if !validTarget(target) || !validAction(action) {
		return Plan{}, errors.New("unknown Velocity proxy or lifecycle operation")
	}
	if !ticketPattern.MatchString(ticket) || deadline.IsZero() {
		return Plan{}, errors.New("invalid simulation ticket or deadline")
	}
	return Plan{Target: target, Action: action, Ticket: ticket, ExpiresAt: deadline,
		Phase: Preflight, LiveAuthorized: false}, nil
}

func block(p Plan, reason string) Plan {
	p.Phase = Blocked
	p.BlockReason = reason
	p.LiveAuthorized = false
	return p
}

// Advance accepts one ordered synthetic observation. Missing/conflicting proof
// causes terminal BLOCK, never a best-effort fallback. It has no side effects.
func Advance(p Plan, e Evidence, now time.Time) Plan {
	p.LiveAuthorized = false
	if p.Phase == Complete || p.Phase == Blocked {
		return p
	}
	if !validTarget(p.Target) || !validAction(p.Action) ||
		!ticketPattern.MatchString(p.Ticket) || p.ExpiresAt.IsZero() ||
		(p.Phase != Preflight && p.Phase != AwaitShutdown && p.Phase != AwaitStart) {
		return block(p, "invalid_simulation_plan")
	}
	if !now.Before(p.ExpiresAt) {
		return block(p, "deadline_expired")
	}
	if e.Target != p.Target || e.Ticket != p.Ticket {
		return block(p, "wrong_proxy_or_ticket")
	}
	if e.Sequence != p.Sequence+1 {
		return block(p, "out_of_order_or_replayed_evidence")
	}
	p.Sequence = e.Sequence
	if !e.OperatorApproved || !e.MaintenanceWindowOpen {
		return block(p, "operator_approval_or_window_missing")
	}
	if !e.TaskFingerprintVerified || !e.TaskProcessLineageVerified ||
		!e.SchedulerAutoRestartControlled || !e.NoDuplicateProxyProcesses ||
		!e.SiblingProxyGenerationsUnchanged || !e.AuditAvailable {
		return block(p, "task_identity_or_sibling_safety_unverified")
	}
	switch p.Phase {
	case Preflight:
		switch p.Action {
		case Start:
			if !e.TargetProcessFamilyAbsentVerified ||
				!e.PublicTCPAndUDPFreeIndependentlyVerified {
				return block(p, "authoritative_absence_or_port_free_proof_missing")
			}
			p.Phase = AwaitStart
		case Stop, Restart:
			if !e.PlayersExactlyZeroVerified || !e.GracefulBridgeAuthenticated ||
				strings.TrimSpace(e.CurrentGeneration) == "" {
				return block(p, "graceful_shutdown_or_zero_player_preflight_missing")
			}
			p.OldGeneration = e.CurrentGeneration
			p.Phase = AwaitShutdown
		}
	case AwaitShutdown:
		if !e.PlayersExactlyZeroVerified || !e.GracefulBridgeAuthenticated ||
			!e.GracefulShutdownAcknowledged ||
			!e.TargetProcessFamilyAbsentVerified ||
			!e.PublicTCPAndUDPFreeIndependentlyVerified ||
			e.StoppedGeneration != p.OldGeneration {
			return block(p, "graceful_shutdown_or_stopped_generation_unverified")
		}
		if p.Action == Stop {
			p.Phase = Complete
		} else {
			p.Phase = AwaitStart
		}
	case AwaitStart:
		if !e.SchedulerStartReceiptVerified || !e.FreshProcessPairVerified ||
			!e.JavaTCPResponding || !e.BedrockRaknetPong ||
			strings.TrimSpace(e.NewGeneration) == "" ||
			(p.Action == Restart && e.NewGeneration == p.OldGeneration) {
			return block(p, "fresh_process_or_application_health_unverified")
		}
		p.Phase = Complete
	default:
		return block(p, "invalid_phase_transition")
	}
	p.LiveAuthorized = false
	return p
}
