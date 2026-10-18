package velocitybridge

import (
    "crypto/rand"
    "encoding/base64"
    "errors"
    "sync"
    "time"
)

// Challenge is a short-lived server-generated nonce scoped to one target,
// operation and process generation. It is NOT a live operation permission.
// New verifier processes start with an EMPTY set of issued challenges so that
// envelopes captured before a verifier restart always fail closed.
type Challenge struct {
    Target string `json:"target"`
    Operation string `json:"operation"`
    Generation string `json:"generation"`
    Nonce string `json:"nonce"`
    IssuedUnix int64 `json:"issued_unix"`
    ExpiresUnix int64 `json:"expires_unix"`
}

var errChallengeRejected = errors.New("velocity one-shot challenge rejected")

type ChallengeVerifier struct {
    mu sync.Mutex
    inner *Verifier
    issued map[string]Challenge
}

// NewChallengeVerifier makes a new process-local challenge ledger and copies
// the key. The key must be scoped to ONE Velocity proxy and protected by OS
// mechanisms in any future real implementation. No pipe, listener, plugin
// control or OS process operation is present in this package.
func NewChallengeVerifier(key []byte) (*ChallengeVerifier, error) {
    inner, err := NewVerifier(key)
    if err != nil { return nil, errChallengeRejected }
    return &ChallengeVerifier{inner:inner,issued:make(map[string]Challenge)},nil
}

func validChallengeShape(c Challenge) bool {
    return allowedTarget(c.Target) && allowedOperation(c.Operation) &&
        generationShape.MatchString(c.Generation) && nonceShape.MatchString(c.Nonce) &&
        c.IssuedUnix>0 && c.ExpiresUnix>c.IssuedUnix &&
        c.ExpiresUnix-c.IssuedUnix<=maxLifetimeSeconds
}

func (v *ChallengeVerifier) Issue(target, operation, generation string, now time.Time) (Challenge, error) {
    if v==nil || v.inner==nil || v.issued==nil || now.IsZero() ||
        !allowedTarget(target) || !allowedOperation(operation) ||
        !generationShape.MatchString(generation) {
        return Challenge{},errChallengeRejected
    }
    nonceBytes:=make([]byte,24)
    if _,err:=rand.Read(nonceBytes);err!=nil {return Challenge{},errChallengeRejected}
    c:=Challenge{
        Target:target,Operation:operation,Generation:generation,
        Nonce:base64.RawURLEncoding.EncodeToString(nonceBytes),
        IssuedUnix:now.Unix(),ExpiresUnix:now.Unix()+maxLifetimeSeconds,
    }
    if !validChallengeShape(c) {return Challenge{},errChallengeRejected}
    v.mu.Lock()
    defer v.mu.Unlock()
    for n,old:=range v.issued {
        if old.ExpiresUnix<=now.Unix(){delete(v.issued,n)}
    }
    if len(v.issued)>=maxReplayEntries {
        return Challenge{},errChallengeRejected
    }
    if _,exists:=v.issued[c.Nonce];exists {return Challenge{},errChallengeRejected}
    v.issued[c.Nonce]=c
    return c,nil
}

// SignChallenge signs exactly the verifier-issued challenge. A caller must
// never select or substitute an arbitrary nonce for live authorization. In
// any future implementation this runs only after an OS-authenticated pipe
// connection, and cannot by itself cause a Velocity operation.
func SignChallenge(key []byte,c Challenge) (Envelope,error) {
    if len(key)<32 || !validChallengeShape(c) {return Envelope{},errChallengeRejected}
    e:=Envelope{
        Version:envelopeVersion,
        Target:c.Target,Operation:c.Operation,Generation:c.Generation,
        Nonce:c.Nonce,IssuedUnix:c.IssuedUnix,ExpiresUnix:c.ExpiresUnix,
    }
    e.MAC=macFor(key,e)
    return e,nil
}

// VerifyIssuedOnce requires both a valid HMAC/replay record AND an issue
// record created by THIS verifier instance. A new verifier has no pending
// challenge for an old captured envelope even when the same key is reused.
// Bad signatures consume the matching issue record to reduce guessing.
// This only attests knowledge of a key, NOT OS peer identity, players=0,
// scheduler task ownership or authorization for a live shutdown.
func (v *ChallengeVerifier) VerifyIssuedOnce(e Envelope,target,operation,generation string,now time.Time) error {
    if v==nil || v.inner==nil || v.issued==nil || now.IsZero() {return errChallengeRejected}
    v.mu.Lock()
    defer v.mu.Unlock()
    c,ok:=v.issued[e.Nonce]
    if !ok{return errChallengeRejected}
    if !validChallengeShape(c) ||
        c.Target!=target || c.Operation!=operation || c.Generation!=generation ||
        c.Target!=e.Target || c.Operation!=e.Operation || c.Generation!=e.Generation ||
        c.IssuedUnix!=e.IssuedUnix || c.ExpiresUnix!=e.ExpiresUnix ||
        now.Unix()<c.IssuedUnix-5 || now.Unix()>=c.ExpiresUnix {
        return errChallengeRejected
    }
    // One chance per issued challenge: even a bad MAC cannot be replayed.
    delete(v.issued,e.Nonce)
    if err:=v.inner.VerifyOnce(e,target,operation,generation,now);err!=nil {
        return errChallengeRejected
    }
    return nil
}
