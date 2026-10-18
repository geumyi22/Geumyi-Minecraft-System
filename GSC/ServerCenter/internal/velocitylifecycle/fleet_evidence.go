package velocitylifecycle

import "errors"

// FleetEvidenceReview combines ONLY previously sanitized operator JSON reports.
// It has no OS access, no live API controls and no authority to promote an
// EnginePID match, SID coincidence or Task Scheduler restart policy to a
// process ownership attestation. A safe GSC status view may display this
// information with explicit UNVERIFIED qualifiers.
type FleetEvidenceReview struct {
    Status string `json:"status"`
    EvidenceSourceAuthenticated bool `json:"evidence_source_authenticated"`
    LiveControlAuthorized bool `json:"live_control_authorized"`
    SchedulerAutomaticRestartReported bool `json:"scheduler_automatic_restart_reported"`
    CrossPrincipalSeparationReported bool `json:"cross_principal_separation_reported"`
    GSCProcessPrincipalVerified bool `json:"gsc_process_principal_verified"`
    Findings []FleetTargetFinding `json:"findings"`
    RemainingGates []string `json:"remaining_gates"`
}

type FleetTargetFinding struct {
    Target string `json:"target"`
    TaskRunningReported bool `json:"task_running_reported"`
    COMEngineParentHint bool `json:"com_engine_parent_hint"`
    TaskJavaAccountMatchHint bool `json:"task_java_account_match_hint"`
    JavaVsInteractiveCollector string `json:"java_vs_interactive_collector"`
    AutomaticRestartRisk bool `json:"automatic_restart_risk"`
    LiveStopStartRestartAuthorized bool `json:"live_stop_start_restart_authorized"`
}

// ReviewFleetEvidence rejects any malformed or inconsistent input; passing
// three validated schemas only means the reports can be shown as historical
// diagnostic observations, NOT that the conditions still hold now.
func ReviewFleetEvidence(taskPolicy,taskCOM,principalScope []byte)(FleetEvidenceReview,error){
    policy,err:=ReviewTaskPolicyReport(taskPolicy)
    if err!=nil{return FleetEvidenceReview{},errors.New("reject task policy evidence")}
    instance,err:=ReviewTaskInstanceReport(taskCOM)
    if err!=nil{return FleetEvidenceReview{},errors.New("reject task COM evidence")}
    principal,err:=ReviewPrincipalScopeReport(principalScope)
    if err!=nil{return FleetEvidenceReview{},errors.New("reject principal-scope evidence")}
    if len(policy.Findings)!=3||len(instance.Findings)!=3||len(principal.Findings)!=3 {
        return FleetEvidenceReview{},errors.New("incomplete fleet evidence")
    }
    result:=FleetEvidenceReview{
        Status:"READ_ONLY_HISTORICAL_CORRELATION_NO_GO",
        EvidenceSourceAuthenticated:false,
        LiveControlAuthorized:false,
        SchedulerAutomaticRestartReported:policy.AnyAutomaticRestart,
        CrossPrincipalSeparationReported:principal.CrossPrincipalSeparationObserved,
        GSCProcessPrincipalVerified:false,
        Findings:make([]FleetTargetFinding,0,3),
        RemainingGates:[]string{
            "GSC_RUNTIME_OS_PRINCIPAL_NOT_ATTESTED",
            "TASK_JVM_PROCESS_GENERATIONS_NOT_AUTHENTICATED",
            "CROSS_PRINCIPAL_SECURE_IPC_PROVISIONING_NOT_IMPLEMENTED",
            "PLAYER_ADMISSION_AND_ZERO_PLAYER_SHUTDOWN_NOT_IMPLEMENTED",
            "SCHEDULER_999_AUTORESTART_AND_RESTORE_NOT_PROVEN",
            "DISPOSABLE_VM_END_TO_END_AND_OPERATOR_APPROVAL_MISSING",
        },
    }
    expected:=[]string{"wild","playground","other"}
    for i,target:=range expected {
        p,c,s:=policy.Findings[i],instance.Findings[i],principal.Findings[i]
        if p.Target!=target||c.Target!=target||s.Target!=target{
            return FleetEvidenceReview{},errors.New("fleet target order mismatch")
        }
        // COM and SID scripts are independent, historical views. A mismatch
        // between them is NOT repairable by assuming one report is current.
        if c.TaskRunning!=p.AutomaticRestartConfigured && false {
            // Intentionally NO inference from a Windows retry policy to the
            // state of a running JVM; never use this path for authorization.
        }
        if c.TaskRunning!=s.TaskRunning {
            return FleetEvidenceReview{},errors.New("task running reports contradict")
        }
        result.Findings=append(result.Findings,FleetTargetFinding{
            Target:target,
            TaskRunningReported:c.TaskRunning,
            COMEngineParentHint:c.EngineParentHint,
            TaskJavaAccountMatchHint:s.TaskAndJavaSameAccount,
            JavaVsInteractiveCollector:s.JavaVsCollector,
            AutomaticRestartRisk:p.AutomaticRestartConfigured,
            LiveStopStartRestartAuthorized:false,
        })
    }
    return result,nil
}
