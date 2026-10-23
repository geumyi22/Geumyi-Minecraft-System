package velocitybridge

import (
    "bytes"
    "encoding/binary"
    "encoding/hex"
    "encoding/json"
    "errors"
    "io"
)

// Fixed-size-bounded framing for a future OS-authenticated local pipe.
// These functions have NO I/O destination by themselves. They do not create
// sockets or pipes, authenticate a peer, query players or execute commands.
const maxBridgeFrameBytes = 2048
var errBridgeFrame=errors.New("velocity bridge frame rejected")

// rejectDuplicateKeys rejects an overwritten JSON field at ANY nesting level.
// json.Unmarshal by itself silently accepts duplicate object keys.
func rejectDuplicateKeys(data []byte) error {
    decoder:=json.NewDecoder(bytes.NewReader(data))
    var scan func() error
    scan=func() error {
        token,err:=decoder.Token()
        if err!=nil{return errBridgeFrame}
        switch token {
        case json.Delim('{'):
            seen:=make(map[string]struct{})
            for decoder.More() {
                tk,err:=decoder.Token()
                if err!=nil{return errBridgeFrame}
                key,ok:=tk.(string)
                if !ok{return errBridgeFrame}
                if _,exists:=seen[key];exists{return errBridgeFrame}
                seen[key]=struct{}{}
                if err:=scan();err!=nil{return errBridgeFrame}
            }
            _,err=decoder.Token()
            if err!=nil{return errBridgeFrame}
        case json.Delim('['):
            for decoder.More() {
                if err:=scan();err!=nil{return errBridgeFrame}
            }
            _,err=decoder.Token()
            if err!=nil{return errBridgeFrame}
        }
        return nil
    }
    if err:=scan();err!=nil{return errBridgeFrame}
    if _,err:=decoder.Token();err!=io.EOF{return errBridgeFrame}
    return nil
}

func encodeFrame(w io.Writer,value any) error {
    if w==nil{return errBridgeFrame}
    data,err:=json.Marshal(value)
    if err!=nil||len(data)==0||len(data)>maxBridgeFrameBytes{return errBridgeFrame}
    var prefix [4]byte
    binary.BigEndian.PutUint32(prefix[:],uint32(len(data)))
    n,err:=w.Write(prefix[:])
    if err!=nil||n!=len(prefix){return errBridgeFrame}
    n,err=w.Write(data)
    if err!=nil||n!=len(data){return errBridgeFrame}
    return nil
}

func decodeFrame(r io.Reader,out any) error {
    if r==nil{return errBridgeFrame}
    var prefix [4]byte
    if _,err:=io.ReadFull(r,prefix[:]);err!=nil{return errBridgeFrame}
    count:=binary.BigEndian.Uint32(prefix[:])
    if count==0||count>maxBridgeFrameBytes{return errBridgeFrame}
    data:=make([]byte,int(count))
    if _,err:=io.ReadFull(r,data);err!=nil{return errBridgeFrame}
    if err:=rejectDuplicateKeys(data);err!=nil{return errBridgeFrame}
    decoder:=json.NewDecoder(bytes.NewReader(data))
    decoder.DisallowUnknownFields()
    if err:=decoder.Decode(out);err!=nil{return errBridgeFrame}
    if _,err:=decoder.Token();err!=io.EOF{return errBridgeFrame}
    return nil
}

func shapeEnvelope(e Envelope) bool {
    if e.Version!=envelopeVersion||!allowedTarget(e.Target)||
        !allowedOperation(e.Operation)||!generationShape.MatchString(e.Generation)||
        !nonceShape.MatchString(e.Nonce)||
        e.IssuedUnix<=0||e.ExpiresUnix<=e.IssuedUnix||
        e.ExpiresUnix-e.IssuedUnix>maxLifetimeSeconds {return false}
    mac,err:=hex.DecodeString(e.MAC)
    return err==nil&&len(mac)==32
}

// MarshalSignedEnvelopeFrame does not independently sign or grant access.
// The receiver MUST apply VerifyIssuedOnce with a locally issued challenge.
func MarshalSignedEnvelopeFrame(w io.Writer,e Envelope) error {
    if !shapeEnvelope(e){return errBridgeFrame}
    return encodeFrame(w,e)
}
func UnmarshalSignedEnvelopeFrame(r io.Reader) (Envelope,error) {
    var e Envelope
    if err:=decodeFrame(r,&e);err!=nil||!shapeEnvelope(e){
        return Envelope{},errBridgeFrame
    }
    return e,nil
}

func MarshalChallengeFrame(w io.Writer,c Challenge) error {
    if !validChallengeShape(c){return errBridgeFrame}
    return encodeFrame(w,c)
}
func UnmarshalChallengeFrame(r io.Reader) (Challenge,error) {
    var c Challenge
    if err:=decodeFrame(r,&c);err!=nil||!validChallengeShape(c){
        return Challenge{},errBridgeFrame
    }
    return c,nil
}
