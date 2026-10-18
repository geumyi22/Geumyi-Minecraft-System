package velocitylifecycle

import "errors"

// FleetWithHostReview adds a FOURTH independent historical, sanitized report
// to the three-report context. MATCH is a topology HINT, not a live credential,
// not an executable attestation and never a start/stop/restart permission.
type FleetWithHostReview struct {
    Status string `json:"status"`
    HostAndProxySIDMatchHints bool `json:"host_and_proxy_sid_match_hints"`
    HostAndInteractiveCollectorDifferHint bool `json:"host_and_interactive_collector_differ_hint"`
    GSCProcessIdentityVerified bool `json:"gsc_process_identity_verified"`
    DPAPISharedKeyUsable bool `json:"dpapi_shared_key_usable"`
    PeerAuthenticated bool `json:"peer_authenticated"`
    PlayerAdmissionFrozen bool `json:"player_admission_frozen"`
    SchedulerRecoveryValidated bool `json:"scheduler_recovery_validated"`
    LiveControlAuthorized bool `json:"live_control_authorized"`
    Findings []FleetTargetFinding `json:"findings"`
    RemainingGates []string `json:"remaining_gates"`
}

// ReviewFleetWithHostEvidence corroborates historical task, COM, Java account
// and GSC-host account observations. It rejects contradictory equalities, but
// cannot attest the same process generation across different sampling times.
func ReviewFleetWithHostEvidence(taskPolicy,taskCOM,principalScope,hostScope []byte) (FleetWithHostReview,error) {
    base,err:=ReviewFleetEvidence(taskPolicy,taskCOM,principalScope)
    if err!=nil{return FleetWithHostReview{},err}
    p,err:=ReviewPrincipalScopeReport(principalScope)
    if err!=nil{return FleetWithHostReview{},err}
    host,err:=ReviewHostPrincipalReport(hostScope)
    if err!=nil{return FleetWithHostReview{},err}
    if len(base.Findings)!=3||len(host.Findings)!=3||len(p.Findings)!=3 {
        return FleetWithHostReview{},errors.New("incomplete GSC host topology")
    }
    allMatch:=host.AllHostTaskSIDMatchHints
    for i,id:=range []string{"wild","playground","other"}{
        h,s,f:=host.Findings[i],p.Findings[i],base.Findings[i]
        if h.Target!=id||s.Target!=id||f.Target!=id||h.TaskRunning!=f.TaskRunningReported {
            return FleetWithHostReview{},errors.New("contradictory GSC host task identity")
        }
        // Host-task / Host-collector / Task-collector are 3 equality tests
        // and must satisfy transitivity; this test works for DIFFERENT and
        // UNKNOWN, without inventing a third Windows account.
        if !consistentRelationships(h.HostVsTaskPrincipal,host.HostVsCollector,s.TaskVsCollector) {
            return FleetWithHostReview{},errors.New("contradictory host and collector account relationships")
        }
        allMatch=allMatch&&s.TaskAndJavaSameAccount&&s.JavaParentAndChildSameAccount
    }
    out:=FleetWithHostReview{
        Status:"HISTORICAL_PRINCIPAL_TOPOLOGY_NO_GO",
        HostAndProxySIDMatchHints:allMatch,
        HostAndInteractiveCollectorDifferHint:host.HostVsCollector=="DIFFERENT",
        GSCProcessIdentityVerified:false,
        DPAPISharedKeyUsable:false,PeerAuthenticated:false,
        PlayerAdmissionFrozen:false,SchedulerRecoveryValidated:false,
        LiveControlAuthorized:false,
        Findings:base.Findings,
        RemainingGates:[]string{
            "GSC_AND_JVM_EXECUTABLE_GENERATION_NOT_AUTHENTICATED",
            "SAME_PRINCIPAL_PIPE_DACL_AND_PEER_TOKEN_NOT_WIRED",
            "PER_PROXY_JAVA_KEY_CUSTODY_NOT_PROVISIONED",
            "JAVA_ADMISSION_FREEZE_AND_ZERO_PLAYERS_NOT_WIRED",
            "SCHEDULER_999_RESTART_RESTORE_NOT_VALIDATED_ON_VM",
            "ACTUAL_JAVA_BEDROCK_LOGIN_AND_OPERATOR_APPROVAL_MISSING",
        },
    }
    // Even a completely coherent observed SID topology does NOT grant
    // access to the current-user DPAPI blob to Java without actual verified
    // provisioning. No live capability is ever populated in this type.
    return out,nil
}
