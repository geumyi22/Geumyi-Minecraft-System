package velocitybridge

import (
    "errors"
    "io"
    "time"
)

// DeadlineDuplex is a transport-agnostic stream that MUST support real
// deadlines. This package deliberately has no named-pipe listener, sockets,
// OS process control, Windows task handling, player events, or plugin calls.
// The concrete runtime transport must separately authenticate its OS peer.
type DeadlineDuplex interface {
    io.Reader
    io.Writer
    SetDeadline(time.Time) error
}

const statusResponseDeadline = 1500 * time.Millisecond

// StatusExchangeResult never authorizes lifecycle actions or claims to have
// authenticated a remote JVM executable, the installed Velocity plugin, the
// player count, or the Windows Scheduled Task ownership.
type StatusExchangeResult struct {
    Target string `json:"target"`
    CredentialProofValid bool `json:"credential_proof_valid"`
    PeerProcessAuthenticated bool `json:"peer_process_authenticated"`
    JavaPluginAuthenticated bool `json:"java_plugin_authenticated"`
    OperationalStatusVerified bool `json:"operational_status_verified"`
    LiveControlAuthorized bool `json:"live_control_authorized"`
    Result string `json:"result"`
}

var errStatusOnly = errors.New("Velocity status-only challenge exchange rejected")

// CheckOfflineStatusCredential sends a fresh operation="status" challenge and
// validates exactly one matching signed response over a deadline-capable duplex
// stream. It neither retrieves actual player counts nor trusts a process PID.
// The caller MUST authenticate and pin the OS process, select a per-proxy
// secret only after that identity check, and maintain the transport lifetime;
// this helper supplies NONE of those capabilities. In particular, an offline
// success is not authority to shut down even an apparently empty proxy.
func CheckOfflineStatusCredential(stream DeadlineDuplex, ledger *ChallengeVerifier,
    target,generation string) (StatusExchangeResult,error) {
    if stream==nil || ledger==nil || !allowedTarget(target) ||
        !generationShape.MatchString(generation) {
        return StatusExchangeResult{},errStatusOnly
    }
    now:=time.Now().UTC()
    if err:=stream.SetDeadline(now.Add(statusResponseDeadline));err!=nil {
        return StatusExchangeResult{},errStatusOnly
    }
    c,err:=ledger.Issue(target,"status",generation,now)
    if err!=nil{return StatusExchangeResult{},errStatusOnly}
    if err:=MarshalChallengeFrame(stream,c);err!=nil{return StatusExchangeResult{},errStatusOnly}
    response,err:=UnmarshalSignedEnvelopeFrame(stream)
    if err!=nil{return StatusExchangeResult{},errStatusOnly}
    if err:=ledger.VerifyIssuedOnce(response,target,"status",generation,time.Now().UTC());err!=nil {
        return StatusExchangeResult{},errStatusOnly
    }
    return StatusExchangeResult{
        Target:target,
        CredentialProofValid:true,
        PeerProcessAuthenticated:false,
        JavaPluginAuthenticated:false,
        OperationalStatusVerified:false,
        LiveControlAuthorized:false,
        Result:"OFFLINE_STATUS_CREDENTIAL_ONLY_NO_GO",
    },nil
}
