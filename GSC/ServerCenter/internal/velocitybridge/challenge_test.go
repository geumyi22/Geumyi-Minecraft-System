package velocitybridge

import (
    "strings"
    "sync"
    "sync/atomic"
    "testing"
    "time"
)

var challengeTime=time.Date(2026,10,18,12,0,0,0,time.UTC)

func issueSigned(t *testing.T, v *ChallengeVerifier, target,op,gen string,when time.Time) Envelope {
    t.Helper()
    c,err:=v.Issue(target,op,gen,when)
    if err!=nil {t.Fatal(err)}
    e,err:=SignChallenge(fixtureKey(),c)
    if err!=nil {t.Fatal(err)}
    return e
}

func TestIssuedChallengeAcceptsOnceAndRejectsAcrossVerifierRestart(t *testing.T){
    for _,id:=range []string{"wild","playground","other"} {
        t.Run(id,func(t *testing.T){
            generation:="parent-100_child-101"
            first,_:=NewChallengeVerifier(fixtureKey())
            e:=issueSigned(t,first,id,"prepare_shutdown",generation,challengeTime)
            restarted,_:=NewChallengeVerifier(fixtureKey())
            if err:=restarted.VerifyIssuedOnce(e,id,e.Operation,generation,challengeTime);err==nil{
                t.Fatal("replayed valid HMAC accepted after verifier process restart")
            }
            if err:=first.VerifyIssuedOnce(e,id,e.Operation,generation,challengeTime);err!=nil{
                t.Fatalf("issued challenge rejected: %v",err)
            }
            if err:=first.VerifyIssuedOnce(e,id,e.Operation,generation,challengeTime);err==nil{
                t.Fatal("issued challenge accepted twice")
            }
        })
    }
}

func TestChallengeRejectsExpiredAndCrossScopedMessages(t *testing.T){
    baseTarget:="wild";op:="confirm_shutdown";gen:="parent-100_child-101"
    cases:=[]struct{
        name string
        mutate func(*Envelope)
        target,operation,generation string
        now time.Time
    }{
        {"other-target",func(*Envelope){},"playground",op,gen,challengeTime},
        {"other-operation",func(*Envelope){},baseTarget,"prepare_shutdown",gen,challengeTime},
        {"other-generation",func(*Envelope){},baseTarget,op,"parent-200_child-201",challengeTime},
        {"tampered-target",func(e *Envelope){e.Target="other"},baseTarget,op,gen,challengeTime},
        {"tampered-generation",func(e *Envelope){e.Generation="parent-200_child-201"},baseTarget,op,gen,challengeTime},
        {"tampered-nonce",func(e *Envelope){e.Nonce=strings.Repeat("A",32)},baseTarget,op,gen,challengeTime},
        {"tampered-expiry",func(e *Envelope){e.ExpiresUnix++},baseTarget,op,gen,challengeTime},
        {"tampered-mac",func(e *Envelope){e.MAC=strings.Repeat("f",64)},baseTarget,op,gen,challengeTime},
        {"expires-exactly",func(*Envelope){},baseTarget,op,gen,challengeTime.Add(20*time.Second)},
        {"expired-later",func(*Envelope){},baseTarget,op,gen,challengeTime.Add(45*time.Second)},
        {"issued-too-early",func(*Envelope){},baseTarget,op,gen,challengeTime.Add(-6*time.Second)},
    }
    for _,tc:=range cases {
        t.Run(tc.name,func(t *testing.T){
            v,_:=NewChallengeVerifier(fixtureKey())
            e:=issueSigned(t,v,baseTarget,op,gen,challengeTime)
            tc.mutate(&e)
            if err:=v.VerifyIssuedOnce(e,tc.target,tc.operation,tc.generation,tc.now);err==nil{
                t.Fatal("unissued/stale/wrong-scoped response accepted")
            }
        })
    }
}

func TestChallengeBadMACConsumesPendingIssue(t *testing.T){
    v,_:=NewChallengeVerifier(fixtureKey())
    original:=issueSigned(t,v,"other","prepare_shutdown","generation-abcd-1",challengeTime)
    forged:=original
    forged.MAC=strings.Repeat("0",64)
    if err:=v.VerifyIssuedOnce(forged,original.Target,original.Operation,original.Generation,challengeTime);err==nil{
        t.Fatal("forged MAC accepted")
    }
    if err:=v.VerifyIssuedOnce(original,original.Target,original.Operation,original.Generation,challengeTime);err==nil{
        t.Fatal("correct MAC accepted on already-burned issue")
    }
}

func TestChallengeConcurrentReplayOneSuccess(t *testing.T){
    v,_:=NewChallengeVerifier(fixtureKey())
    e:=issueSigned(t,v,"wild","status","parent-100_child-101",challengeTime)
    var accepted atomic.Int64
    var wg sync.WaitGroup
    for i:=0;i<64;i++{
        wg.Add(1)
        go func(){
            defer wg.Done()
            if v.VerifyIssuedOnce(e,e.Target,e.Operation,e.Generation,challengeTime)==nil {
                accepted.Add(1)
            }
        }()
    }
    wg.Wait()
    if got:=accepted.Load();got!=1{t.Fatalf("expected one accepted, got %d",got)}
}

func TestChallengeRejectsInvalidInputAndCapacityOverflow(t *testing.T){
    if _,err:=NewChallengeVerifier([]byte("weak"));err==nil{t.Fatal("weak secret accepted")}
    var missing *ChallengeVerifier
    if _,err:=missing.Issue("wild","status","parent-100_child-101",challengeTime);err==nil{
        t.Fatal("nil verifier issued challenge")
    }
    if err:=missing.VerifyIssuedOnce(Envelope{},"wild","status","parent-100_child-101",challengeTime);err==nil{
        t.Fatal("nil verifier accepted")
    }
    v,_:=NewChallengeVerifier(fixtureKey())
    for _,tc:=range []struct{target,op,gen string}{
        {"lobby","status","parent-100_child-101"},
        {"wild","kill","parent-100_child-101"},
        {"wild","status","x"},
    }{
        if _,err:=v.Issue(tc.target,tc.op,tc.gen,challengeTime);err==nil {
            t.Fatalf("invalid target/action/generation %v accepted",tc)
        }
    }
    if _,err:=SignChallenge([]byte("bad"),Challenge{});err==nil{t.Fatal("invalid signing accepted")}
    for i:=0;i<maxReplayEntries;i++ {
        if _,err:=v.Issue("wild","status","parent-100_child-101",challengeTime);err!=nil {
            t.Fatalf("challenge %d unexpectedly rejected: %v",i,err)
        }
    }
    if _,err:=v.Issue("wild","status","parent-100_child-101",challengeTime);err==nil {
        t.Fatal("challenge ledger silently evicted an unexpired nonce")
    }
    if _,err:=v.Issue("wild","status","parent-100_child-101",challengeTime.Add(21*time.Second));err!=nil {
        t.Fatalf("expired challenge ledger not collected: %v",err)
    }
}
