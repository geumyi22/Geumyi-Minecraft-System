package velocitylifecycle

import (
	"strings"
	"testing"
	"time"
)

var maintenanceTime = time.Date(2026,10,18,6,0,0,0,time.UTC)
const maintenanceDigest = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

func syntheticLease(t *testing.T, target string) MaintenanceLease {
	t.Helper()
	p,err:=NewMaintenanceLease(target, "ci-only-maintenance-ticket-123", maintenanceDigest, 999, "IgnoreNew", maintenanceTime.Add(time.Minute))
	if err != nil {t.Fatal(err)}
	return p
}

func syntheticMaintenanceEvidence(target string, n uint64, active int) MaintenanceObservation {
	return MaintenanceObservation{
		Target:target, Ticket:"ci-only-maintenance-ticket-123", Sequence:n,
		TaskIdentityVerified:true, OperatorApproved:true, MaintenanceWindowOpen:true,
		SiblingTasksUnchanged:true, TargetOnlyMutationProof:true,
		OriginalDigest:maintenanceDigest, OriginalRestarts:999, OriginalPolicy:"IgnoreNew",
		ActiveRestarts:active, ActivePolicy:"IgnoreNew",
		RestorationAck: active==999,
		RestoredDigest:maintenanceDigest,
		NoOrphanTaskProcesses:true,
	}
}

func noLiveCapability(t *testing.T, m MaintenanceLease) {
	t.Helper()
	if m.LiveAuthorized {t.Fatal("synthetic maintenance authorized a real operation")}
}

func TestAllThree999RestartTaskLeasesMustRestore(t *testing.T) {
	for _,id:=range []string{"wild","playground","other"} {
		t.Run(id,func(t *testing.T){
			m:=syntheticLease(t,id)
			m=MaintenanceNext(m,syntheticMaintenanceEvidence(id,1,0),maintenanceTime)
			noLiveCapability(t,m)
			if m.Phase!=MaintenanceRestoreRequired {t.Fatalf("expected restore obligation %+v",m)}
			m=MaintenanceNext(m,syntheticMaintenanceEvidence(id,2,999),maintenanceTime.Add(time.Second))
			if m.Phase!=MaintenanceRestoring {t.Fatalf("expected verification %+v",m)}
			m=MaintenanceNext(m,syntheticMaintenanceEvidence(id,3,999),maintenanceTime.Add(2*time.Second))
			noLiveCapability(t,m)
			if m.Phase!=MaintenanceRestored {t.Fatalf("expected restored model %+v",m)}
			again:=MaintenanceNext(m,syntheticMaintenanceEvidence(id,4,0),maintenanceTime.Add(3*time.Second))
			if again.Phase!=MaintenanceRestored || again.LiveAuthorized {t.Fatal("terminal proof not idempotent")}
		})
	}
}

func TestUnsafeLeaseInputAndRestorationNegativeCases(t *testing.T) {
	for _,tc:=range []struct{
		name string
		phase MaintenancePhase
		edit func(*MaintenanceObservation)
	}{
		{"missing_operator",MaintenancePreflight,func(e *MaintenanceObservation){e.OperatorApproved=false}},
		{"unverified_task",MaintenancePreflight,func(e *MaintenanceObservation){e.TaskIdentityVerified=false}},
		{"other_proxy_changed",MaintenancePreflight,func(e *MaintenanceObservation){e.SiblingTasksUnchanged=false}},
		{"wrong_ticket",MaintenancePreflight,func(e *MaintenanceObservation){e.Ticket="other-ticket-123456789"}},
		{"wrong_target",MaintenancePreflight,func(e *MaintenanceObservation){e.Target="other"}},
		{"replayed_sequence",MaintenancePreflight,func(e *MaintenanceObservation){e.Sequence=0}},
		{"not_suppressed",MaintenancePreflight,func(e *MaintenanceObservation){e.ActiveRestarts=999}},
		{"changed_policy",MaintenancePreflight,func(e *MaintenanceObservation){e.ActivePolicy="Parallel"}},
		{"mismatched_original",MaintenancePreflight,func(e *MaintenanceObservation){e.OriginalDigest=strings.Repeat("b",64)}},
		{"restoration_ack_only",MaintenanceRestoreRequired,func(e *MaintenanceObservation){e.ActiveRestarts=0}},
		{"restoration_wrong_digest",MaintenanceRestoreRequired,func(e *MaintenanceObservation){e.RestoredDigest=strings.Repeat("c",64)}},
		{"restoration_wrong_policy",MaintenanceRestoreRequired,func(e *MaintenanceObservation){e.ActivePolicy="StopExisting"}},
		{"restoration_orphan",MaintenanceRestoreRequired,func(e *MaintenanceObservation){e.NoOrphanTaskProcesses=false}},
		{"second_restoration_mismatch",MaintenanceRestoring,func(e *MaintenanceObservation){e.RestoredDigest="wrong"}},
	}{
		t.Run(tc.name,func(t *testing.T){
			m:=syntheticLease(t,"wild")
			var e MaintenanceObservation
			switch tc.phase {
			case MaintenancePreflight:e=syntheticMaintenanceEvidence("wild",1,0)
			case MaintenanceRestoreRequired:
				m=MaintenanceNext(m,syntheticMaintenanceEvidence("wild",1,0),maintenanceTime)
				e=syntheticMaintenanceEvidence("wild",2,999)
			case MaintenanceRestoring:
				m=MaintenanceNext(m,syntheticMaintenanceEvidence("wild",1,0),maintenanceTime)
				m=MaintenanceNext(m,syntheticMaintenanceEvidence("wild",2,999),maintenanceTime.Add(time.Second))
				e=syntheticMaintenanceEvidence("wild",3,999)
			}
			tc.edit(&e)
			m=MaintenanceNext(m,e,maintenanceTime.Add(2*time.Second))
			noLiveCapability(t,m)
			if m.Phase!=MaintenanceBlocked || m.BlockReason=="" {
				t.Fatalf("unsafe scenario not blocked: %+v",m)
			}
		})
	}
}

func TestExpiredAndCrashedSimulationCanOnlyRecoverWithOriginalTask(t *testing.T) {
	m:=syntheticLease(t,"playground")
	m=MaintenanceNext(m,syntheticMaintenanceEvidence("playground",1,0),maintenanceTime)
	if m.Phase!=MaintenanceRestoreRequired {t.Fatal(m)}
	m=MaintenanceNext(m,syntheticMaintenanceEvidence("playground",2,999),maintenanceTime.Add(61*time.Second))
	if m.Phase!=MaintenanceBlocked {t.Fatal("expired maintenance lease proceeded")}
	noLiveCapability(t,m)
	incomplete:=syntheticMaintenanceEvidence("playground",2,0)
	m=RecoverMaintenance(m,incomplete)
	if m.Phase!=MaintenanceBlocked || m.LiveAuthorized {t.Fatal("incomplete recovery accepted")}
	complete:=syntheticMaintenanceEvidence("playground",2,999)
	m=RecoverMaintenance(m,complete)
	if m.Phase!=MaintenanceRestored || m.LiveAuthorized {t.Fatalf("original 999 policy recovery rejected: %+v",m)}
}

func TestMaintenancePlanNeverAllowsZeroCountAsOriginalBaseline(t *testing.T) {
	for _,c:=range []struct{target string;ticket string;count int;policy string;digest string;deadline time.Time}{
		{"unknown","valid-ci-ticket-12345",999,"IgnoreNew",maintenanceDigest,maintenanceTime.Add(time.Minute)},
		{"wild","short",999,"IgnoreNew",maintenanceDigest,maintenanceTime.Add(time.Minute)},
		{"wild","valid-ci-ticket-12345",0,"IgnoreNew",maintenanceDigest,maintenanceTime.Add(time.Minute)},
		{"wild","valid-ci-ticket-12345",1000,"IgnoreNew",maintenanceDigest,maintenanceTime.Add(time.Minute)},
		{"wild","valid-ci-ticket-12345",999,"Parallel",maintenanceDigest,maintenanceTime.Add(time.Minute)},
		{"wild","valid-ci-ticket-12345",999,"IgnoreNew","bad",maintenanceTime.Add(time.Minute)},
		{"wild","valid-ci-ticket-12345",999,"IgnoreNew",maintenanceDigest,time.Time{}},
	} {
		if _,err:=NewMaintenanceLease(c.target,c.ticket,c.digest,c.count,c.policy,c.deadline);err==nil {
			t.Fatalf("invalid in-memory lease accepted: %+v",c)
		}
	}
}
