package velocitylifecycle

import "testing"

func TestFourHistoricalReportsAgreeWithoutAuthorizingControl(t *testing.T){
    report,err:=ReviewFleetWithHostEvidence(
        observedTaskPolicyFixture(999),
        taskInstanceFixture("ONE_VISIBLE"),
        asPrincipalJSON(principalFixture()),
        hostBytes(hostPrincipalFixture()))
    if err!=nil{t.Fatal(err)}
    if report.Status!="HISTORICAL_PRINCIPAL_TOPOLOGY_NO_GO"||
        !report.HostAndProxySIDMatchHints||
        !report.HostAndInteractiveCollectorDifferHint||
        report.GSCProcessIdentityVerified||
        report.DPAPISharedKeyUsable||report.PeerAuthenticated||
        report.PlayerAdmissionFrozen||report.SchedulerRecoveryValidated||
        report.LiveControlAuthorized||len(report.RemainingGates)!=6||
        len(report.Findings)!=3 {
        t.Fatalf("historical matching SIDs falsely unlocked shutdown: %+v",report)
    }
    for i,id:=range []string{"wild","playground","other"}{
        row:=report.Findings[i]
        if row.Target!=id||row.LiveStopStartRestartAuthorized||
            !row.TaskRunningReported||!row.TaskJavaAccountMatchHint||
            !row.AutomaticRestartRisk||!row.COMEngineParentHint {
            t.Fatalf("unexpected observed %s state: %+v",id,row)
        }
    }
}

func TestHostTopologyAllowsLegitimateDifferentAccountWithoutTrustPromotion(t *testing.T){
    m:=hostPrincipalFixture()
    m["collector_vs_host"]="MATCH"
    for i:=0;i<3;i++{
        e:=hostRow(m,i)
        e["host_vs_task_principal"]="DIFFERENT"
    }
    r,err:=ReviewFleetWithHostEvidence(
        observedTaskPolicyFixture(999),taskInstanceFixture("ONE_VISIBLE"),
        asPrincipalJSON(principalFixture()),hostBytes(m))
    if err!=nil{t.Fatal(err)}
    if r.HostAndProxySIDMatchHints||r.HostAndInteractiveCollectorDifferHint||
       r.DPAPISharedKeyUsable||r.LiveControlAuthorized {
        t.Fatal("alternate principal topology incorrectly authorized control")
    }
}

func TestFleetHostRejectsImpossibleSIDTransitivityAndMissingEvidence(t *testing.T){
    for _,test:=range []struct{name string;edit func(map[string]any)}{
        {"impossible-host-collector",func(m map[string]any){m["collector_vs_host"]="MATCH"}},
        {"task-running-contradicts-COM",func(m map[string]any){
            hostRow(m,0)["task_running"]=false
            m["result"]="GSC_HOST_PRINCIPAL_SCOPE_UNVERIFIED_NO_GO"
        }},
    }{
        t.Run(test.name,func(t *testing.T){
            m:=hostPrincipalFixture()
            test.edit(m)
            _,err:=ReviewFleetWithHostEvidence(
                observedTaskPolicyFixture(999),taskInstanceFixture("ONE_VISIBLE"),
                asPrincipalJSON(principalFixture()),hostBytes(m))
            if err==nil{t.Fatal("impossible host-vs-task-vs-collector relation accepted")}
        })
    }
    for _,test:=range []struct{name string;policy,com,principal,host []byte}{
        {"no_policy",nil,taskInstanceFixture("ONE_VISIBLE"),asPrincipalJSON(principalFixture()),hostBytes(hostPrincipalFixture())},
        {"no_COM",observedTaskPolicyFixture(999),nil,asPrincipalJSON(principalFixture()),hostBytes(hostPrincipalFixture())},
        {"no_principal",observedTaskPolicyFixture(999),taskInstanceFixture("ONE_VISIBLE"),nil,hostBytes(hostPrincipalFixture())},
        {"no_host",observedTaskPolicyFixture(999),taskInstanceFixture("ONE_VISIBLE"),asPrincipalJSON(principalFixture()),nil},
    }{
        t.Run(test.name,func(t *testing.T){
            report,err:=ReviewFleetWithHostEvidence(test.policy,test.com,test.principal,test.host)
            if err==nil||report.LiveControlAuthorized{t.Fatal("missing evidence accepted")}
        })
    }
}
