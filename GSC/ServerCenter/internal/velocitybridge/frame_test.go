package velocitybridge

import (
    "bytes"
    "encoding/binary"
    "net"
    "strings"
    "sync"
    "testing"
)

type partialFrameWriter struct{}
func (partialFrameWriter) Write(p []byte)(int,error){return len(p)-1,nil}

func encodeTestFrame(t *testing.T,payload []byte) []byte {
    t.Helper()
    b:=make([]byte,4+len(payload))
    binary.BigEndian.PutUint32(b[:4],uint32(len(payload)))
    copy(b[4:],payload)
    return b
}

func TestStrictFramingRoundTripAndOneShotChallenge(t *testing.T){
    verifier,_:=NewChallengeVerifier(fixtureKey())
    issued,err:=verifier.Issue("wild","prepare_shutdown","parent-100_child-101",challengeTime)
    if err!=nil{t.Fatal(err)}
    var request bytes.Buffer
    if err:=MarshalChallengeFrame(&request,issued);err!=nil{t.Fatal(err)}
    decoded,err:=UnmarshalChallengeFrame(&request)
    if err!=nil||decoded!=issued{t.Fatalf("challenge frame roundtrip failed: %v",err)}
    signed,err:=SignChallenge(fixtureKey(),decoded)
    if err!=nil{t.Fatal(err)}
    var reply bytes.Buffer
    if err:=MarshalSignedEnvelopeFrame(&reply,signed);err!=nil{t.Fatal(err)}
    envelope,err:=UnmarshalSignedEnvelopeFrame(&reply)
    if err!=nil||envelope!=signed{t.Fatalf("envelope roundtrip failed: %v",err)}
    if err:=verifier.VerifyIssuedOnce(envelope,envelope.Target,envelope.Operation,envelope.Generation,challengeTime);err!=nil{
        t.Fatalf("signed issued envelope rejected: %v",err)
    }
    if err:=verifier.VerifyIssuedOnce(envelope,envelope.Target,envelope.Operation,envelope.Generation,challengeTime);err==nil{
        t.Fatal("framing bypassed one-shot replay ledger")
    }
}

func TestChallengeResponseOverDisposableInMemoryDuplexPipe(t *testing.T){
    // net.Pipe is strictly IN MEMORY; never listens on an OS network port.
    a,b:=net.Pipe()
    defer a.Close()
    defer b.Close()
    verifier,_:=NewChallengeVerifier(fixtureKey())
    issued,err:=verifier.Issue("other","status","parent-100_child-101",challengeTime)
    if err!=nil{t.Fatal(err)}
    var wg sync.WaitGroup
    var clientErr error
    wg.Add(1)
    go func(){
        defer wg.Done()
        challenge,err:=UnmarshalChallengeFrame(b)
        if err!=nil{clientErr=err;return}
        answer,err:=SignChallenge(fixtureKey(),challenge)
        if err!=nil{clientErr=err;return}
        clientErr=MarshalSignedEnvelopeFrame(b,answer)
    }()
    if err:=MarshalChallengeFrame(a,issued);err!=nil{t.Fatal(err)}
    answer,err:=UnmarshalSignedEnvelopeFrame(a)
    if err!=nil{t.Fatal(err)}
    if err:=verifier.VerifyIssuedOnce(answer,"other","status","parent-100_child-101",challengeTime);err!=nil{
        t.Fatalf("in-memory IPC challenge proof rejected: %v",err)
    }
    wg.Wait()
    if clientErr!=nil{t.Fatal(clientErr)}
    next,_:=NewChallengeVerifier(fixtureKey())
    if err:=next.VerifyIssuedOnce(answer,"other","status","parent-100_child-101",challengeTime);err==nil{
        t.Fatal("receiver restart accepted previous signed pipe frame")
    }
}

func TestStrictFramingRejectsMalformedUntrustedInput(t *testing.T){
    verifier,_:=NewChallengeVerifier(fixtureKey())
    issued,_:=verifier.Issue("wild","status","parent-100_child-101",challengeTime)
    signed,_:=SignChallenge(fixtureKey(),issued)
    var good bytes.Buffer
    if err:=MarshalSignedEnvelopeFrame(&good,signed);err!=nil{t.Fatal(err)}
    original:=good.Bytes()
    raw:=string(original[4:])
    cases:=[]struct{name string;data []byte}{
        {"empty",nil},
        {"short-prefix",[]byte{0,0,0}},
        {"zero-size",[]byte{0,0,0,0}},
        {"huge-size",[]byte{0,0,0x80,0}},
        {"truncated",original[:len(original)-3]},
        {"broken-json",encodeTestFrame(t,[]byte("{"))},
        {"scalar-json",encodeTestFrame(t,[]byte("123"))},
        {"duplicate-nonce",encodeTestFrame(t,[]byte(strings.Replace(raw, "\""+"nonce\""+":", "\""+"nonce\""+":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\",\"nonce\":",1)))},
        {"duplicate-object",encodeTestFrame(t,[]byte(strings.TrimSuffix(raw,"}")+",\"mac\":\""+signed.MAC+"\"}"))},
        {"unknown-field",encodeTestFrame(t,[]byte(strings.TrimSuffix(raw,"}")+",\"action\":\"kill\"}"))},
        {"extra-json",encodeTestFrame(t,[]byte(raw+"{}"))},
    }
    for _,tc:=range cases{
        t.Run(tc.name,func(t *testing.T){
            if _,err:=UnmarshalSignedEnvelopeFrame(bytes.NewReader(tc.data));err==nil{
                t.Fatal("invalid untrusted signed frame accepted")
            }
        })
    }
    if err:=MarshalSignedEnvelopeFrame(partialFrameWriter{},signed);err==nil {
        t.Fatal("short writer accepted as full frame")
    }
    signed.MAC="bad"
    if err:=MarshalSignedEnvelopeFrame(&bytes.Buffer{},signed);err==nil{
        t.Fatal("malformed MAC serialized as valid frame")
    }
}

func TestChallengeFrameRejectsForgedAndWrongShape(t *testing.T){
    v,_:=NewChallengeVerifier(fixtureKey())
    c,_:=v.Issue("wild","status","parent-100_child-101",challengeTime)
    var good bytes.Buffer
    if err:=MarshalChallengeFrame(&good,c);err!=nil{t.Fatal(err)}
    raw:=string(good.Bytes()[4:])
    cases:=[][]byte{
        encodeTestFrame(t,[]byte(strings.TrimSuffix(raw,"}")+",\"extra\":0}")),
        encodeTestFrame(t,[]byte(strings.Replace(raw,"\"nonce\":","\"nonce\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\",\"nonce\":",1))),
        encodeTestFrame(t,[]byte(strings.Replace(raw,"\"target\":\"wild\"","\"target\":\"lobby\"",1))),
        encodeTestFrame(t,[]byte(strings.Replace(raw,"\"expires_unix\":","\"expires_unix\":0,\"expires_unix\":",1))),
    }
    for i,data:=range cases{
        if _,err:=UnmarshalChallengeFrame(bytes.NewReader(data));err==nil{
            t.Fatalf("forged challenge frame %d accepted",i)
        }
    }
    if err:=MarshalChallengeFrame(partialFrameWriter{},c);err==nil{
        t.Fatal("partial challenge frame writer accepted")
    }
}
