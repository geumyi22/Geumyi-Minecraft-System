package velocitybridge

import (
    "errors"
    "net"
    "sync"
    "testing"
    "time"
)

func TestStatusOnlyChallengeNeverPromotesOfflineProofToControl(t *testing.T) {
    for _,target:=range []string{"wild","playground","other"} {
        t.Run(target,func(t *testing.T){
            server,client:=net.Pipe()
            defer server.Close()
            defer client.Close()
            ledger,err:=NewChallengeVerifier(fixtureKey())
            if err!=nil{t.Fatal(err)}
            done:=make(chan error,1)
            go func(){
                c,err:=UnmarshalChallengeFrame(client)
                if err!=nil{done<-err;return}
                e,err:=SignChallenge(fixtureKey(),c)
                if err!=nil{done<-err;return}
                done<-MarshalSignedEnvelopeFrame(client,e)
            }()
            out,err:=CheckOfflineStatusCredential(server,ledger,target,"parent-100_child-101")
            if err!=nil{t.Fatal(err)}
            if e:=<-done;e!=nil{t.Fatal(e)}
            if out.Target!=target||!out.CredentialProofValid||
                out.PeerProcessAuthenticated||out.JavaPluginAuthenticated||
                out.OperationalStatusVerified||out.LiveControlAuthorized||
                out.Result!="OFFLINE_STATUS_CREDENTIAL_ONLY_NO_GO"{
                t.Fatalf("status-only MAC was promoted to live authorization: %+v",out)
            }
        })
    }
}

func TestStatusOnlyRejectsWrongProxyGenerationAndOperation(t *testing.T){
    cases:=[]struct{
        name string
        mutation func(*Challenge)
    }{
        {"wrong-target",func(c *Challenge){c.Target="other"}},
        {"wrong-operation",func(c *Challenge){c.Operation="prepare_shutdown"}},
        {"wrong-generation",func(c *Challenge){c.Generation="parent-other-child-111"}},
        {"wrong-time",func(c *Challenge){c.IssuedUnix++}},
        {"wrong-nonce",func(c *Challenge){c.Nonce="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}},
    }
    for _,tc:=range cases{
        t.Run(tc.name,func(t *testing.T){
            server,client:=net.Pipe()
            defer server.Close();defer client.Close()
            ledger,_:=NewChallengeVerifier(fixtureKey())
            done:=make(chan error,1)
            go func(){
                c,err:=UnmarshalChallengeFrame(client)
                if err!=nil{done<-err;return}
                tc.mutation(&c)
                e,err:=SignChallenge(fixtureKey(),c)
                if err!=nil{done<-err;return}
                done<-MarshalSignedEnvelopeFrame(client,e)
            }()
            out,err:=CheckOfflineStatusCredential(server,ledger,"wild","parent-100_child-101")
            if err==nil||out.CredentialProofValid||out.LiveControlAuthorized{
                t.Fatalf("mutated credential proof accepted: %+v",out)
            }
            if e:=<-done;e!=nil{t.Fatalf("test client write unexpectedly failed: %v",e)}
        })
    }
}

func TestStatusOnlyRejectsBadMACAndConnectionClose(t *testing.T){
    cases:=[]struct{
        name string
        respond func(net.Conn,Challenge)error
    }{
        {"bad-HMAC",func(c net.Conn,challenge Challenge)error{
            env,err:=SignChallenge(fixtureKey(),challenge)
            if err!=nil{return err}
            env.MAC="0000000000000000000000000000000000000000000000000000000000000000"
            return MarshalSignedEnvelopeFrame(c,env)
        }},
        {"truncated",func(c net.Conn,challenge Challenge)error{
            _,err:=c.Write([]byte{0,0,0,100,1})
            return err
        }},
    }
    for _,tc:=range cases{
        t.Run(tc.name,func(t *testing.T){
            server,client:=net.Pipe()
            defer server.Close();defer client.Close()
            ledger,_:=NewChallengeVerifier(fixtureKey())
            done:=make(chan error,1)
            go func(){
                challenge,err:=UnmarshalChallengeFrame(client)
                if err!=nil{done<-err;return}
                done<-tc.respond(client,challenge)
                _=client.Close()
            }()
            out,err:=CheckOfflineStatusCredential(server,ledger,"other","generation-abcd-1")
            if err==nil||out.LiveControlAuthorized||out.CredentialProofValid{
                t.Fatalf("untrusted response accepted: %+v",out)
            }
            <-done
        })
    }
}

type noDeadlineDuplex struct{err error}
func (n noDeadlineDuplex) Read(p []byte)(int,error){return 0,errors.New("no read")}
func (n noDeadlineDuplex) Write(p []byte)(int,error){return len(p),nil}
func (n noDeadlineDuplex) SetDeadline(time.Time)error{return n.err}

func TestStatusOnlyFailClosedWithoutDeadlineOrValidTarget(t *testing.T){
    ledger,_:=NewChallengeVerifier(fixtureKey())
    if _,err:=CheckOfflineStatusCredential(nil,ledger,"wild","generation-abcd-1");err==nil{t.Fatal("nil transport accepted")}
    if _,err:=CheckOfflineStatusCredential(noDeadlineDuplex{err:errors.New("unsupported")},ledger,"wild","generation-abcd-1");err==nil{
        t.Fatal("unsupported deadline accepted")
    }
    if _,err:=CheckOfflineStatusCredential(noDeadlineDuplex{},ledger,"lobby","generation-abcd-1");err==nil{
        t.Fatal("unknown proxy target accepted")
    }
    if _,err:=CheckOfflineStatusCredential(noDeadlineDuplex{},ledger,"wild","x");err==nil{
        t.Fatal("invalid process generation accepted")
    }
    if _,err:=CheckOfflineStatusCredential(noDeadlineDuplex{},nil,"wild","generation-abcd-1");err==nil{
        t.Fatal("nil verifier accepted")
    }
}

func TestStatusOnlyUnansweredPeerTimesOut(t *testing.T){
    server,client:=net.Pipe()
    defer server.Close();defer client.Close()
    ledger,_:=NewChallengeVerifier(fixtureKey())
    var wg sync.WaitGroup
    wg.Add(1)
    go func(){
        defer wg.Done()
        // Consume the challenge without responding.
        _,_ = UnmarshalChallengeFrame(client)
        <-time.After(statusResponseDeadline+200*time.Millisecond)
    }()
    start:=time.Now()
    out,err:=CheckOfflineStatusCredential(server,ledger,"wild","generation-abcd-1")
    if err==nil||out.CredentialProofValid||out.LiveControlAuthorized{
        t.Fatal("unanswered peer treated as authorized")
    }
    elapsed:=time.Since(start)
    if elapsed<statusResponseDeadline/2||elapsed>statusResponseDeadline+3*time.Second{
        t.Fatalf("timeout outside bounded window: %v",elapsed)
    }
    wg.Wait()
}
