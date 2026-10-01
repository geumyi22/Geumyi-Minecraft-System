package main

import (
    "net/http"
    "net/http/httptest"
    "testing"
)

func TestDay10PublicEntryPortPairs(t *testing.T) {
    eps := day10NetworkEndpoints()
    ids := []string{"wild", "playground", "other"}
    java := []int{25565,25566,25567}
    bedrock := []int{19132,19133,19134}
    if len(eps) != 3 { t.Fatalf("endpoint count=%d",len(eps)) }
    for i, e := range eps {
        if e.ID != ids[i] || e.JavaTCP != java[i] || e.BedrockUDP != bedrock[i] {
            t.Fatalf("bad endpoint at %d: %+v",i,e)
        }
    }
}

func TestDay10RaknetPongValidation(t *testing.T) {
    valid := make([]byte,33)
    valid[0] = raknetPongID
    copy(valid[17:],raknetMagic)
    if !matchesRaknetPong(valid) { t.Fatal("valid RakNet unconnected pong was rejected") }
    for _, invalid := range [][]byte{nil, {raknetPongID}, make([]byte,33)} {
        if matchesRaknetPong(invalid) { t.Fatal("invalid RakNet response was accepted") }
    }
    valid[17] = 12
    if matchesRaknetPong(valid) { t.Fatal("RakNet magic mismatch was accepted") }
}

func TestDay10EntryStatusRejectsMutation(t *testing.T) {
    w := httptest.NewRecorder()
    apiV4NetworkEntryStatus(w,httptest.NewRequest(http.MethodPost,"/api/v4/network/entry-status",nil))
    if w.Code != http.StatusMethodNotAllowed {
        t.Fatalf("POST returned %d",w.Code)
    }
}
