package velocitybridge

import (
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

var fixtureNow = time.Date(2026, 10, 17, 12, 0, 0, 0, time.UTC)

func fixtureKey() []byte {
	return []byte(strings.Repeat("x", 32)) // synthetic; never use in production
}

func signedFixture(t *testing.T) Envelope {
	t.Helper()
	e, err := NewSignedRequest(fixtureKey(), "wild", "prepare_shutdown", "parent-100_child-101", fixtureNow)
	if err != nil {
		t.Fatal(err)
	}
	return e
}

func TestBridgeValidOneShotRequestAndReplayRejection(t *testing.T) {
	e := signedFixture(t)
	v, err := NewVerifier(fixtureKey())
	if err != nil { t.Fatal(err) }
	if err := v.VerifyOnce(e, "wild", "prepare_shutdown", "parent-100_child-101", fixtureNow); err != nil {
		t.Fatalf("valid signed envelope rejected: %v", err)
	}
	if err := v.VerifyOnce(e, "wild", "prepare_shutdown", "parent-100_child-101", fixtureNow); err == nil {
		t.Fatal("replayed HMAC request was accepted")
	}
}

func TestBridgeRejectsTargetActionGenerationAndMACSubstitution(t *testing.T) {
	e := signedFixture(t)
	cases := []struct {
		name string
		edit func(*Envelope)
		wantTarget string
		wantAction string
		wantGeneration string
		now time.Time
	}{
		{"wrong-target",func(*Envelope){},"playground","prepare_shutdown","parent-100_child-101",fixtureNow},
		{"wrong-action",func(*Envelope){},"wild","confirm_shutdown","parent-100_child-101",fixtureNow},
		{"wrong-generation",func(*Envelope){},"wild","prepare_shutdown","parent-200_child-201",fixtureNow},
		{"tampered-target",func(e *Envelope){e.Target="other"},"other","prepare_shutdown","parent-100_child-101",fixtureNow},
		{"tampered-operation",func(e *Envelope){e.Operation="confirm_shutdown"},"wild","confirm_shutdown","parent-100_child-101",fixtureNow},
		{"tampered-generation",func(e *Envelope){e.Generation="parent-200_child-201"},"wild","prepare_shutdown","parent-200_child-201",fixtureNow},
		{"tampered-timestamp",func(e *Envelope){e.ExpiresUnix++},"wild","prepare_shutdown","parent-100_child-101",fixtureNow},
		{"tampered-nonce",func(e *Envelope){e.Nonce=strings.Repeat("a",32)},"wild","prepare_shutdown","parent-100_child-101",fixtureNow},
		{"tampered-mac",func(e *Envelope){e.MAC=strings.Repeat("0",64)},"wild","prepare_shutdown","parent-100_child-101",fixtureNow},
		{"invalid-hex",func(e *Envelope){e.MAC="not-hex"},"wild","prepare_shutdown","parent-100_child-101",fixtureNow},
		{"old-request",func(*Envelope){},"wild","prepare_shutdown","parent-100_child-101",fixtureNow.Add(21*time.Second)},
		{"issued-in-future",func(e *Envelope){e.IssuedUnix+=10},"wild","prepare_shutdown","parent-100_child-101",fixtureNow},
		{"invalid-version",func(e *Envelope){e.Version=2},"wild","prepare_shutdown","parent-100_child-101",fixtureNow},
	}
	for _, c := range cases {
		t.Run(c.name,func(t *testing.T){
			m := e
			c.edit(&m)
			v,_ := NewVerifier(fixtureKey())
			if err := v.VerifyOnce(m,c.wantTarget,c.wantAction,c.wantGeneration,c.now); err == nil {
				t.Fatal("modified or wrong-scope control envelope accepted")
			}
		})
	}
}

func TestBridgeRejectsWeakKeysInvalidTargetsAndUnknownCommands(t *testing.T) {
	if _, err := NewVerifier([]byte("weak")); err == nil { t.Fatal("accepted weak key") }
	for _, c := range [][3]string{
		{"all","status","parent-100_child-101"},
		{"wild","kill","parent-100_child-101"},
		{"wild","confirm_shutdown",""},
		{"wild; rm -rf","status","parent-100_child-101"},
	} {
		if _, err := NewSignedRequest(fixtureKey(),c[0],c[1],c[2],fixtureNow); err == nil {
			t.Fatalf("invalid request scope accepted: %q",c)
		}
	}
	if _,err := NewSignedRequest([]byte("weak"),"wild","status","parent-100_child-101",fixtureNow); err == nil {
		t.Fatal("signed request with weak key")
	}
	var nilVerifier *Verifier
	if err := nilVerifier.VerifyOnce(signedFixture(t),"wild","prepare_shutdown","parent-100_child-101",fixtureNow); err == nil {
		t.Fatal("nil verifier accepted request")
	}
}

func TestBridgeConcurrentReplayPermitsExactlyOne(t *testing.T) {
	v,_ := NewVerifier(fixtureKey())
	e := signedFixture(t)
	var accepted atomic.Int64
	var wg sync.WaitGroup
	for i:=0;i<24;i++ {
		wg.Add(1)
		go func(){
			defer wg.Done()
			if v.VerifyOnce(e,"wild","prepare_shutdown","parent-100_child-101",fixtureNow)==nil {
				accepted.Add(1)
			}
		}()
	}
	wg.Wait()
	if accepted.Load()!=1 {t.Fatalf("replayed nonce was accepted %d times",accepted.Load())}
}

func TestBridgeBoundedReplayLedgerBlocksOverflow(t *testing.T) {
	v,_ := NewVerifier(fixtureKey())
	for i:=0;i<maxReplayEntries;i++ {
		e,err := NewSignedRequest(fixtureKey(),"wild","status","parent-100_child-101",fixtureNow)
		if err!=nil {t.Fatal(err)}
		if err := v.VerifyOnce(e,"wild","status","parent-100_child-101",fixtureNow); err!=nil {
			t.Fatalf("nonce %d unexpectedly rejected: %v",i,err)
		}
	}
	extra,_ := NewSignedRequest(fixtureKey(),"wild","status","parent-100_child-101",fixtureNow)
	if err := v.VerifyOnce(extra,"wild","status","parent-100_child-101",fixtureNow); err==nil {
		t.Fatal("replay ledger overflow failed open")
	}
	later,_ := NewSignedRequest(fixtureKey(),"wild","status","parent-100_child-101",fixtureNow.Add(22*time.Second))
	if err := v.VerifyOnce(later,"wild","status","parent-100_child-101",fixtureNow.Add(22*time.Second)); err!=nil {
		t.Fatal("expired nonce entries were not collected")
	}
}


// Test vector shared with the GSC v4.5.2 Canary Java disabled plugin prototype
// (PR #58). It is generated from the agreed big-endian, length-prefixed
// canonical encoding, not from a live production key.
func TestGoJavaHMACGoldenVector(t *testing.T) {
	key := make([]byte, 32)
	for i := range key {
		key[i] = byte(i)
	}
	e := Envelope{
		Version: 1,
		Target: "wild",
		Operation: "status",
		Generation: "parent-100-child-101",
		Nonce: strings.Repeat("A", 32),
		IssuedUnix: 1792267200,
		ExpiresUnix: 1792267220,
	}
	want := "1488217fd43660a2e0810dc60caf3f93d89d4ba4bb9b4920967f42d31fff70c5"
	if len(canonical(e)) != 118 {
		t.Fatalf("canonical size mismatch: %d", len(canonical(e)))
	}
	if got := macFor(key, e); got != want {
		t.Fatalf("cross-language HMAC vector mismatch: %s", got)
	}
	e.MAC = want
	v, err := NewVerifier(key)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Unix(1792267200, 0)
	if err := v.VerifyOnce(e, "wild", "status", e.Generation, now); err != nil {
		t.Fatalf("expected Java-compatible signature accepted: %v", err)
	}
}
