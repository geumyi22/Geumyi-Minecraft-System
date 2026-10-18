package velocitylifecycle

import (
    "encoding/json"
    "testing"
)

func testFleetReview(t *testing.T, taskPolicy,taskCOM,principal []byte) FleetEvidenceReview{
    t.Helper()
    report,err:=ReviewFleetEvidence(taskPolicy,taskCOM,principal)
    if err!=nil{t.Fatal(err)}
    return report
}

func TestThreeHostReportsCorrelateOnlyAsHistoricalNoGo(t *testing.T){
    report:=testFleetReview(t,observedTaskPolicyFixture(999),
        taskInstanceFixture("ONE_VISIBLE"),asPrincipalJSON(principalFixture()))
    if report.Status!="READ_ONLY_HISTORICAL_CORRELATION_NO_GO"||
        report.EvidenceSourceAuthenticated||report.LiveControlAuthorized||
        !report.SchedulerAutomaticRestartReported||
        !report.CrossPrincipalSeparationReported||
        report.GSCProcessPrincipalVerified||len(report.Findings)!=3||
        len(report.RemainingGates)<6{
        t.Fatalf("evidence improperly promoted to runtime rights: %+v",report)
    }
    for i,id:=range []string{"wild","playground","other"} {
        f:=report.Findings[i]
        if f.Target!=id||!f.TaskRunningReported||!f.COMEngineParentHint||
            !f.TaskJavaAccountMatchHint||f.JavaVsInteractiveCollector!="DIFFERENT"||
            !f.AutomaticRestartRisk||f.LiveStopStartRestartAuthorized{
            t.Fatalf("invalid historical fleet finding for %s: %+v",id,f)
        }
    }
}

func TestEvenZeroSchedulerRestartsAndSameAccountsAreNoGo(t *testing.T){
    m:=principalFixture()
    for i:=0;i<3;i++{
        principalRow(m,i)["task_principal_vs_collector"]="MATCH"
        principalRow(m,i)["udp_java_owner_vs_collector"]="MATCH"
    }
    report:=testFleetReview(t,observedTaskPolicyFixture(0),
        taskInstanceFixture("ONE_VISIBLE"),asPrincipalJSON(m))
    if report.LiveControlAuthorized||report.SchedulerAutomaticRestartReported||
        report.CrossPrincipalSeparationReported||report.GSCProcessPrincipalVerified{
        t.Fatal("no configured retries and same CLI account incorrectly unlocked lifecycle")
    }
    for _,f:=range report.Findings{
        if f.LiveStopStartRestartAuthorized||f.AutomaticRestartRisk{
            t.Fatalf("wrong false-safe policy classification: %+v",f)
        }
    }
}

func TestFleetRejectsInconsistentAndUntrustedInputs(t *testing.T){
    goodPolicy:=observedTaskPolicyFixture(999)
    goodCOM:=taskInstanceFixture("ONE_VISIBLE")
    goodPrincipal:=asPrincipalJSON(principalFixture())
    var brokenCOM map[string]any
    if err:=json.Unmarshal(goodCOM,&brokenCOM);err!=nil{t.Fatal(err)}
    entry:=brokenCOM["instances"].([]any)[0].(map[string]any)
    entry["task_running"]=false
    entry["result"]="TASK_STATE_NOT_CONFIRMED_NO_GO"
    stoppedCOM,err:=json.Marshal(brokenCOM)
    if err!=nil{t.Fatal(err)}
    tests:=[]struct{
        name string
        task,com,principal []byte
    }{
        {"missing_policy",nil,goodCOM,goodPrincipal},
        {"missing_COM",goodPolicy,nil,goodPrincipal},
        {"missing_principal",goodPolicy,goodCOM,nil},
        {"fake_policy",[]byte("{}"),goodCOM,goodPrincipal},
        {"fake_COM",goodPolicy,[]byte("{}"),goodPrincipal},
        {"fake_principal",goodPolicy,goodCOM,[]byte("{}")},
        {"contradictory_running",goodPolicy,stoppedCOM,goodPrincipal},
    }
    for _,tc:=range tests{
        t.Run(tc.name,func(t *testing.T){
            out,err:=ReviewFleetEvidence(tc.task,tc.com,tc.principal)
            if err==nil||out.LiveControlAuthorized{
                t.Fatalf("unsafe evidence accepted: %+v",out)
            }
        })
    }
}
