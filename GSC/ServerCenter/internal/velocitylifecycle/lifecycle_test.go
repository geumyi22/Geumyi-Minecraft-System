package velocitylifecycle

import (
	"reflect"
	"strings"
	"testing"
	"time"
)

var testNow = time.Date(2026, 10, 17, 10, 0, 0, 0, time.UTC)
const testTicket = "fixed-fixture-ticket-2026"

func newFixturePlan(t *testing.T, target string, action Action) Plan {
	t.Helper()
	plan, err := NewPlan(target, action, testTicket, testNow.Add(time.Minute))
	if err != nil {
		t.Fatal(err)
	}
	return plan
}

func goodEvidence(target string, seq uint64) Evidence {
	return Evidence{
		Target: target, Ticket: testTicket, Sequence: seq,
		OperatorApproved: true, MaintenanceWindowOpen: true,
		TaskFingerprintVerified: true, TaskProcessLineageVerified: true,
		SchedulerAutoRestartControlled: true, SiblingProxyGenerationsUnchanged: true,
		NoDuplicateProxyProcesses: true, AuditAvailable: true,
		PlayersExactlyZeroVerified: true, GracefulBridgeAuthenticated: true,
		CurrentGeneration: "parent-100-child-101",
		TargetProcessFamilyAbsentVerified: true, PublicTCPAndUDPFreeIndependentlyVerified: true,
		GracefulShutdownAcknowledged: true, StoppedGeneration: "parent-100-child-101",
		SchedulerStartReceiptVerified: true, FreshProcessPairVerified: true,
		NewGeneration: "parent-200-child-201", JavaTCPResponding: true, BedrockRaknetPong: true,
	}
}

func requirePhase(t *testing.T, p Plan, desired Phase) {
	t.Helper()
	if p.Phase != desired {
		t.Fatalf("phase=%s, want %s (reason=%s)", p.Phase, desired, p.BlockReason)
	}
	if p.LiveAuthorized {
		t.Fatal("pure simulation incorrectly authorized live Velocity control")
	}
}

func TestAllNineTargetActionSimulationsWithoutLiveCapability(t *testing.T) {
	for _, target := range []string{"wild", "playground", "other"} {
		for _, action := range []Action{Start, Stop, Restart} {
			t.Run(target+"/"+string(action), func(t *testing.T) {
				p := newFixturePlan(t, target, action)
				requirePhase(t, p, Preflight)
				p = Advance(p, goodEvidence(target, 1), testNow)
				if action == Start {
					requirePhase(t, p, AwaitStart)
				} else {
					requirePhase(t, p, AwaitShutdown)
				}
				next := goodEvidence(target, 2)
				p = Advance(p, next, testNow.Add(time.Second))
				if action == Stop {
					requirePhase(t, p, Complete)
				} else if action == Start {
					requirePhase(t, p, Complete)
				} else {
					requirePhase(t, p, AwaitStart)
					p = Advance(p, goodEvidence(target, 3), testNow.Add(2*time.Second))
					requirePhase(t, p, Complete)
				}
				same := Advance(p, goodEvidence(target, 100), testNow.Add(3*time.Second))
				if !reflect.DeepEqual(p, same) {
					t.Fatal("terminal state changed after unexpected event")
				}
			})
		}
	}
}

func TestGlobalGatesFailClosedAcrossEveryAction(t *testing.T) {
	for _, mutation := range []struct {
		name string
		fn func(*Evidence)
	}{
		{"approval_missing", func(e *Evidence) { e.OperatorApproved = false }},
		{"maintenance_window_closed", func(e *Evidence) { e.MaintenanceWindowOpen = false }},
		{"task_fingerprint_mismatch", func(e *Evidence) { e.TaskFingerprintVerified = false }},
		{"task_pid_attribution_unknown", func(e *Evidence) { e.TaskProcessLineageVerified = false }},
		{"scheduler_restart_unsafe", func(e *Evidence) { e.SchedulerAutoRestartControlled = false }},
		{"sibling_changed", func(e *Evidence) { e.SiblingProxyGenerationsUnchanged = false }},
		{"duplicate_proxy_java", func(e *Evidence) { e.NoDuplicateProxyProcesses = false }},
		{"audit_unavailable", func(e *Evidence) { e.AuditAvailable = false }},
	} {
		t.Run(mutation.name, func(t *testing.T) {
			for _, action := range []Action{Start, Stop, Restart} {
				e := goodEvidence("wild", 1)
				mutation.fn(&e)
				p := Advance(newFixturePlan(t, "wild", action), e, testNow)
				requirePhase(t, p, Blocked)
				if p.BlockReason == "" {
					t.Fatal("block reason absent")
				}
			}
		})
	}
}

func TestStartWillNotTrustMissingOSPortRows(t *testing.T) {
	for _, mut := range []struct {
		name string
		fn func(*Evidence)
	}{
		{"process_tree_still_exists", func(e *Evidence) { e.TargetProcessFamilyAbsentVerified = false }},
		{"no_authoritative_tcp_udp_free_proof", func(e *Evidence) { e.PublicTCPAndUDPFreeIndependentlyVerified = false }},
	} {
		t.Run(mut.name, func(t *testing.T) {
			e := goodEvidence("wild", 1)
			mut.fn(&e)
			p := Advance(newFixturePlan(t, "wild", Start), e, testNow)
			requirePhase(t, p, Blocked)
			if !strings.Contains(p.BlockReason, "port_free_proof_missing") {
				t.Fatal("unsafe start did not block on authoritative port/process proof")
			}
		})
	}
}

func TestStopRequiresPlayerQuietAndAuthenticatedBridge(t *testing.T) {
	for _, m := range []struct{
		name string
		fn func(*Evidence)
	}{
		{"players_present", func(e *Evidence) { e.PlayersExactlyZeroVerified = false }},
		{"bridge_absent", func(e *Evidence) { e.GracefulBridgeAuthenticated = false }},
		{"generation_missing", func(e *Evidence) { e.CurrentGeneration = "" }},
	} {
		t.Run(m.name, func(t *testing.T) {
			for _, a := range []Action{Stop, Restart} {
				e := goodEvidence("playground", 1)
				m.fn(&e)
				p := Advance(newFixturePlan(t, "playground", a), e, testNow)
				requirePhase(t, p, Blocked)
			}
		})
	}
}

func TestGracefulShutdownMustEndExactGeneration(t *testing.T) {
	for _, m := range []struct {
		name string
		fn func(*Evidence)
	}{
		{"players_appeared", func(e *Evidence) { e.PlayersExactlyZeroVerified = false }},
		{"bridge_unavailable", func(e *Evidence) { e.GracefulBridgeAuthenticated = false }},
		{"no_ack", func(e *Evidence) { e.GracefulShutdownAcknowledged = false }},
		{"child_still_alive", func(e *Evidence) { e.TargetProcessFamilyAbsentVerified = false }},
		{"ports_not_independently_free", func(e *Evidence) { e.PublicTCPAndUDPFreeIndependentlyVerified = false }},
		{"different_stopped_process_generation", func(e *Evidence) { e.StoppedGeneration = "unrelated-java" }},
	} {
		t.Run(m.name, func(t *testing.T) {
			for _, a := range []Action{Stop, Restart} {
				p := Advance(newFixturePlan(t, "wild", a), goodEvidence("wild", 1), testNow)
				requirePhase(t, p, AwaitShutdown)
				e := goodEvidence("wild", 2)
				m.fn(&e)
				p = Advance(p, e, testNow.Add(time.Second))
				requirePhase(t, p, Blocked)
			}
		})
	}
}

func TestRestartNeedsNewJVMGenerationAndApplicationHealth(t *testing.T) {
	for _, m := range []struct {
		name string
		fn func(*Evidence)
	}{
		{"start_not_attested", func(e *Evidence) { e.SchedulerStartReceiptVerified = false }},
		{"new_process_missing", func(e *Evidence) { e.FreshProcessPairVerified = false }},
		{"same_legacy_generation", func(e *Evidence) { e.NewGeneration = e.CurrentGeneration }},
		{"empty_generation", func(e *Evidence) { e.NewGeneration = "" }},
		{"java_probe_missing", func(e *Evidence) { e.JavaTCPResponding = false }},
		{"raknet_not_responding", func(e *Evidence) { e.BedrockRaknetPong = false }},
		{"another_proxy_changed", func(e *Evidence) { e.SiblingProxyGenerationsUnchanged = false }},
	} {
		t.Run(m.name, func(t *testing.T) {
			p := Advance(newFixturePlan(t, "wild", Restart), goodEvidence("wild", 1), testNow)
			p = Advance(p, goodEvidence("wild", 2), testNow.Add(time.Second))
			requirePhase(t, p, AwaitStart)
			e := goodEvidence("wild", 3)
			m.fn(&e)
			p = Advance(p, e, testNow.Add(2*time.Second))
			requirePhase(t, p, Blocked)
		})
	}
}

func TestOperationTamperingReplayTimeoutAndBadTicketsFailClosed(t *testing.T) {
	for _, c := range []struct{
		target string
		action Action
		ticket string
	}{
		{"all", Start, testTicket},
		{"wild", Action("force-stop"), testTicket},
		{"wild", Start, ""},
		{"wild", Stop, "newline\nINJECT"},
	} {
		if _, err := NewPlan(c.target,c.action,c.ticket,testNow.Add(time.Minute)); err == nil {
			t.Fatalf("invalid new plan accepted: %+v", c)
		}
	}
	tests := []struct{
		name string
		edit func(*Evidence)
		now time.Time
	}{
		{"wrong_target",func(e *Evidence){e.Target="other"},testNow},
		{"wrong_ticket",func(e *Evidence){e.Ticket="different-abcdef12345"},testNow},
		{"replay_sequence",func(e *Evidence){e.Sequence=0},testNow},
		{"skip_sequence",func(e *Evidence){e.Sequence=3},testNow},
		{"deadline_expired",func(e *Evidence){},testNow.Add(time.Minute)},
	}
	for _, tc := range tests {
		t.Run(tc.name,func(t *testing.T){
			p:=newFixturePlan(t,"wild",Restart)
			e:=goodEvidence("wild",1)
			tc.edit(&e)
			p=Advance(p,e,tc.now)
			requirePhase(t,p,Blocked)
		})
	}
}
