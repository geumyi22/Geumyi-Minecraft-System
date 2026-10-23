package velocitylifecycle

import (
	"errors"
	"time"
)

// MaintenancePhase is a pure state transition model of a FUTURE, operator-
// approved maintenance-scoped Scheduler restart-policy transaction.
// No Windows task or Java process is ever read or changed by this package.
type MaintenancePhase string

const (
	MaintenancePreflight       MaintenancePhase = "preflight_only"
	MaintenanceRestoreRequired MaintenancePhase = "restoration_required"
	MaintenanceRestoring       MaintenancePhase = "restoring"
	MaintenanceRestored        MaintenancePhase = "restored_no_live_capability"
	MaintenanceBlocked         MaintenancePhase = "blocked_restore_required"
)

type MaintenanceLease struct {
	Target           string
	Phase            MaintenancePhase
	Ticket           string
	ExpiresAt        time.Time
	OriginalRestarts int
	OriginalPolicy   string
	OriginalDigest   string
	Sequence         uint64
	BlockReason      string
	// Never set true. Even a completed isolated simulation conveys no
	// authority to execute a real scheduled task, shutdown, or restart.
	LiveAuthorized   bool
}

type MaintenanceObservation struct {
	Target         string
	Ticket         string
	Sequence       uint64
	// These fields are untrusted synthetic simulation inputs. A real adapter
	// would need OS-backed task identity and operator authentication.
	TaskIdentityVerified    bool
	OperatorApproved        bool
	MaintenanceWindowOpen   bool
	SiblingTasksUnchanged   bool
	TargetOnlyMutationProof bool
	OriginalDigest          string
	OriginalRestarts        int
	OriginalPolicy          string
	ActiveRestarts          int
	ActivePolicy            string
	RestorationAck          bool
	RestoredDigest          string
	NoOrphanTaskProcesses   bool
}

// MaintenanceNext is a deterministic, **non-executing** model. A report of
// "maintenance lease acquired" never means it is safe to stop a server.
// Restoration must be demonstrated by identical original task fingerprint
// and restart policy, not an acknowledgment alone.
func NewMaintenanceLease(target, ticket, digest string, originalRestarts int, originalPolicy string, expires time.Time) (MaintenanceLease, error) {
	if !validTarget(target) || !ticketPattern.MatchString(ticket) ||
		len(digest) != 64 || originalRestarts < 1 || originalRestarts > 999 ||
		originalPolicy != "IgnoreNew" || expires.IsZero() {
		return MaintenanceLease{}, errors.New("invalid fail-closed synthetic maintenance plan")
	}
	return MaintenanceLease{
		Target: target, Ticket: ticket, OriginalDigest: digest,
		OriginalRestarts: originalRestarts, OriginalPolicy: originalPolicy,
		ExpiresAt: expires, Phase: MaintenancePreflight,
	}, nil
}

func maintenanceBlock(m MaintenanceLease, reason string) MaintenanceLease {
	m.Phase = MaintenanceBlocked
	m.BlockReason = reason
	m.LiveAuthorized = false
	return m
}

func MaintenanceNext(m MaintenanceLease, e MaintenanceObservation, at time.Time) MaintenanceLease {
	m.LiveAuthorized = false
	if m.Phase == MaintenanceBlocked || m.Phase == MaintenanceRestored {
		return m
	}
	if !validTarget(m.Target) || m.OriginalRestarts <= 0 ||
		m.OriginalPolicy != "IgnoreNew" || len(m.OriginalDigest) != 64 ||
		!ticketPattern.MatchString(m.Ticket) || m.ExpiresAt.IsZero() ||
		!at.Before(m.ExpiresAt) {
		return maintenanceBlock(m, "lease_expired_or_invalid_restoration_required")
	}
	if e.Target != m.Target || e.Ticket != m.Ticket || e.Sequence != m.Sequence+1 {
		return maintenanceBlock(m, "wrong_target_ticket_or_replayed_evidence")
	}
	m.Sequence = e.Sequence
	if !e.TaskIdentityVerified || !e.OperatorApproved || !e.MaintenanceWindowOpen ||
		!e.SiblingTasksUnchanged || !e.TargetOnlyMutationProof ||
		e.OriginalDigest != m.OriginalDigest ||
		e.OriginalRestarts != m.OriginalRestarts ||
		e.OriginalPolicy != m.OriginalPolicy {
		return maintenanceBlock(m, "task_approval_sibling_or_original_state_unverified")
	}
	switch m.Phase {
	case MaintenancePreflight:
		// This is only an abstract simulated temporary override. No
		// Windows TaskScheduler call or production policy change exists.
		if e.ActiveRestarts != 0 || e.ActivePolicy != m.OriginalPolicy {
			return maintenanceBlock(m, "temporary_override_not_attested")
		}
		m.Phase = MaintenanceRestoreRequired
	case MaintenanceRestoreRequired:
		// ACK alone or restored count alone is never sufficient.
		if !e.RestorationAck || e.RestoredDigest != m.OriginalDigest ||
			e.ActiveRestarts != m.OriginalRestarts ||
			e.ActivePolicy != m.OriginalPolicy ||
			!e.NoOrphanTaskProcesses {
			return maintenanceBlock(m, "original_task_policy_not_fully_restored")
		}
		m.Phase = MaintenanceRestoring
	case MaintenanceRestoring:
		if !e.RestorationAck || e.RestoredDigest != m.OriginalDigest ||
			e.ActiveRestarts != m.OriginalRestarts ||
			e.ActivePolicy != m.OriginalPolicy ||
			!e.NoOrphanTaskProcesses {
			return maintenanceBlock(m, "restored_task_regressed")
		}
		m.Phase = MaintenanceRestored
	default:
		return maintenanceBlock(m, "unexpected_maintenance_phase")
	}
	return m
}


// RecoverMaintenance models an out-of-band *verification* that the original
// policy was restored after a simulated process crash or expired lease.
// It never changes a task and never opens a live control permission. It must
// remain usable even after lease expiration or a blocked transition.
func RecoverMaintenance(m MaintenanceLease, e MaintenanceObservation) MaintenanceLease {
	m.LiveAuthorized = false
	if !validTarget(m.Target) || !ticketPattern.MatchString(m.Ticket) ||
		e.Target != m.Target || e.Ticket != m.Ticket ||
		!e.TaskIdentityVerified || !e.SiblingTasksUnchanged ||
		!e.RestorationAck || !e.NoOrphanTaskProcesses ||
		e.OriginalDigest != m.OriginalDigest ||
		e.RestoredDigest != m.OriginalDigest ||
		e.OriginalPolicy != m.OriginalPolicy ||
		e.ActivePolicy != m.OriginalPolicy ||
		e.OriginalRestarts != m.OriginalRestarts ||
		e.ActiveRestarts != m.OriginalRestarts {
		return maintenanceBlock(m, "recovery_original_state_not_proven")
	}
	m.Phase = MaintenanceRestored
	m.BlockReason = ""
	return m
}
