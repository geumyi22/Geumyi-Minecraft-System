// Package velocitybridge defines an isolated, replay-resistant envelope
// contract for a future LOCAL-ONLY Velocity control bridge. It provides NO
// network listener, plugin, task scheduler integration, or shutdown capability.
package velocitybridge

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"regexp"
	"sync"
	"time"
)

const envelopeVersion = 1
const maxLifetimeSeconds = 20
const maxReplayEntries = 1024

var nonceShape = regexp.MustCompile(`^[A-Za-z0-9_-]{32,64}$`)
var generationShape = regexp.MustCompile(`^[A-Za-z0-9_.:-]{8,128}$`)

var errRejected = errors.New("velocity bridge envelope rejected")

type Envelope struct {
	Version int `json:"version"`
	Target string `json:"target"`
	Operation string `json:"operation"`
	Generation string `json:"generation"`
	Nonce string `json:"nonce"`
	IssuedUnix int64 `json:"issued_unix"`
	ExpiresUnix int64 `json:"expires_unix"`
	MAC string `json:"mac"`
}

func allowedTarget(s string) bool {
	return s == "wild" || s == "playground" || s == "other"
}
func allowedOperation(s string) bool {
	switch s {
	case "status", "prepare_shutdown", "confirm_shutdown":
		return true
	default:
		return false
	}
}

// canonical writes length-prefixed fields to avoid separator ambiguities.
// The format is versioned and must be identical in a future Java adapter.
func canonical(e Envelope) []byte {
	buf := make([]byte, 0, 256)
	appendUint := func(v uint64) {
		var word [8]byte
		binary.BigEndian.PutUint64(word[:], v)
		buf = append(buf, word[:]...)
	}
	appendText := func(s string) {
		appendUint(uint64(len(s)))
		buf = append(buf, s...)
	}
	appendUint(uint64(e.Version))
	appendText(e.Target)
	appendText(e.Operation)
	appendText(e.Generation)
	appendText(e.Nonce)
	appendUint(uint64(e.IssuedUnix))
	appendUint(uint64(e.ExpiresUnix))
	return buf
}

func macFor(key []byte, e Envelope) string {
	mac := hmac.New(sha256.New, key)
	_, _ = mac.Write(canonical(e))
	return hex.EncodeToString(mac.Sum(nil))
}

// NewSignedRequest does not obtain or persist a secret. The calling runtime
// must supply a per-proxy, OS-protected 256-bit-or-larger key.
func NewSignedRequest(key []byte, target, operation, generation string, now time.Time) (Envelope, error) {
	if len(key) < 32 || !allowedTarget(target) || !allowedOperation(operation) ||
		!generationShape.MatchString(generation) {
		return Envelope{}, errRejected
	}
	random := make([]byte, 24)
	if _, err := rand.Read(random); err != nil {
		return Envelope{}, errRejected
	}
	nonce := base64.RawURLEncoding.EncodeToString(random)
	e := Envelope{Version: envelopeVersion, Target: target, Operation: operation,
		Generation: generation, Nonce: nonce, IssuedUnix: now.Unix(),
		ExpiresUnix: now.Unix() + maxLifetimeSeconds}
	e.MAC = macFor(key, e)
	return e, nil
}

// Verifier is a bounded one-shot replay ledger. It authenticates message
// provenance; it does NOT authorize a start, stop, or restart operation.
type Verifier struct {
	mu sync.Mutex
	key []byte
	seen map[string]int64
}

func NewVerifier(key []byte) (*Verifier, error) {
	if len(key) < 32 {
		return nil, errRejected
	}
	return &Verifier{key: append([]byte(nil), key...), seen: map[string]int64{}}, nil
}

// VerifyOnce rejects cross-proxy/cross-operation/cross-process-generation
// substitution, tampering, replay, expiry, clock skew and ledger overflow.
func (v *Verifier) VerifyOnce(e Envelope, target, operation, generation string, now time.Time) error {
	if v == nil || !allowedTarget(target) || !allowedOperation(operation) ||
		!generationShape.MatchString(generation) ||
		e.Version != envelopeVersion || e.Target != target ||
		e.Operation != operation || e.Generation != generation ||
		!nonceShape.MatchString(e.Nonce) ||
		e.IssuedUnix > now.Unix()+5 ||
		e.IssuedUnix < now.Unix()-30 ||
		e.ExpiresUnix <= now.Unix() ||
		e.ExpiresUnix > e.IssuedUnix+maxLifetimeSeconds ||
		e.ExpiresUnix <= e.IssuedUnix {
		return errRejected
	}
	received, err := hex.DecodeString(e.MAC)
	if err != nil || len(received) != sha256.Size {
		return errRejected
	}
	expected, _ := hex.DecodeString(macFor(v.key, e))
	if !hmac.Equal(received, expected) {
		return errRejected
	}
	v.mu.Lock()
	defer v.mu.Unlock()
	for nonce, expires := range v.seen {
		if expires <= now.Unix() {
			delete(v.seen, nonce)
		}
	}
	if _, used := v.seen[e.Nonce]; used || len(v.seen) >= maxReplayEntries {
		return errRejected
	}
	v.seen[e.Nonce] = e.ExpiresUnix
	return nil
}
