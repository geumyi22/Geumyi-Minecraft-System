package main

// Offline client-only GSC Canary package verification. This is a read-only
// Windows utility built solely from Go standard library. It never executes
// installer code, changes files, makes network calls or reads account tokens.
import (
	"crypto/ed25519"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

const (
	trustedKeySHA = "f21e62e87bb9d68ba05a964e0efd2e160ac249ebfbbf5f4a5125bae8f11718e3"
	expectedSetupSHA = "2a623e25193d6b92dc4ec69b9ce76f098b246541c2861087f7c4911ae297602f"
	expectedRollbackSHA = "05402a24c499b9457a4d587817d1ef1393acb74992b63712970a6c94b7f65c61"
	expectedNewClientSHA = "c3057d6dfc2e88232a857932e960866c12fd6c8b65c40d2252ed71d6000fe111"
	expectedSource = "8a02ef221ada5936e5ef6d5c0826fa8d1880d123"
	expectedRepo = "geumyi22/Geumyi-Minecraft-System"
	setupName = "GeumyiServerCenter-v4.3.9-rc.2-Setup.exe"
	rollbackName = "GeumyiServerCenter-v4.3.8-Recovery.exe"
	manifestName = "deployment-client-canary.json"
	signatureName = "deployment-client-canary.json.sig"
	publicName = "deployment-public.pem"
)

type clientCanaryManifest struct {
	Schema int `json:"schema"`
	Purpose string `json:"purpose"`
	Channel string `json:"channel"`
	Version string `json:"version"`
	SourceCommit string `json:"source_commit"`
	Repository string `json:"repository"`
	TargetRole string `json:"target_role"`
	BaselineClientSHA256 string `json:"baseline_client_sha256"`
	CandidateSetupSHA256 string `json:"candidate_setup_sha256"`
	CandidateClientSHA256 string `json:"candidate_client_sha256"`
	ProductionHostInstallAllowed bool `json:"production_host_install_allowed"`
	PublicReleasePublished bool `json:"public_release_published"`
	ExplicitOperatorActionRequired bool `json:"explicit_operator_action_required"`
}

func digest(b []byte) string {
	h:=sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}
func fileDigest(path string)(string,error){
	f,e:=os.Open(path)
	if e!=nil{return "",e}
	defer f.Close()
	h:=sha256.New()
	if _,e=io.Copy(h,f);e!=nil{return "",e}
	return hex.EncodeToString(h.Sum(nil)),nil
}
func verifyDir(dir string) error {
	if dir=="" {return errors.New("DIRECTORY_REQUIRED")}
	keyBytes,e:=os.ReadFile(filepath.Join(dir,publicName))
	if e!=nil {return errors.New("PUBLIC_KEY_UNAVAILABLE")}
	if digest(keyBytes)!=trustedKeySHA{return errors.New("TRUSTED_KEY_DIGEST_MISMATCH")}
	block,_:=pem.Decode(keyBytes)
	if block==nil{return errors.New("KEY_PEM_INVALID")}
	keyAny,e:=x509.ParsePKIXPublicKey(block.Bytes)
	if e!=nil{return errors.New("KEY_PARSE_INVALID")}
	key,ok:=keyAny.(ed25519.PublicKey)
	if !ok{return errors.New("KEY_ALGORITHM_NOT_ED25519")}
	manifest,e:=os.ReadFile(filepath.Join(dir,manifestName))
	if e!=nil{return errors.New("MANIFEST_UNAVAILABLE")}
	sig,e:=os.ReadFile(filepath.Join(dir,signatureName))
	if e!=nil || len(sig)!=ed25519.SignatureSize{return errors.New("SIGNATURE_UNAVAILABLE")}
	if !ed25519.Verify(key,manifest,sig){return errors.New("SIGNATURE_INVALID")}
	var m clientCanaryManifest
	d:=json.NewDecoder(strings.NewReader(string(manifest)))
	d.DisallowUnknownFields()
	if e=d.Decode(&m);e!=nil{return errors.New("MANIFEST_SCHEMA_INVALID")}
	if m.Schema!=1 || m.Purpose!="gsc-client-only-canary-offline-test" ||
		m.Channel!="canary-offline" || m.Version!="4.3.9-rc.2" ||
		m.SourceCommit!=expectedSource || m.Repository!=expectedRepo ||
		m.TargetRole!="client_only" || m.BaselineClientSHA256!=expectedRollbackSHA ||
		m.CandidateSetupSHA256!=expectedSetupSHA || m.CandidateClientSHA256!=expectedNewClientSHA ||
		m.ProductionHostInstallAllowed || m.PublicReleasePublished ||
		!m.ExplicitOperatorActionRequired {
		return errors.New("SIGNED_SCOPE_OR_VERSION_INVALID")
	}
	for _,entry:=range [][2]string{
		{setupName,expectedSetupSHA},
		{rollbackName,expectedRollbackSHA},
	} {
		got,e:=fileDigest(filepath.Join(dir,entry[0]))
		if e!=nil{return errors.New("PACKAGE_FILE_MISSING")}
		if got!=entry[1]{return errors.New("PACKAGE_FILE_SHA256_INVALID")}
	}
	return nil
}
func main(){
	if len(os.Args)!=2 {
		fmt.Fprintln(os.Stderr,"GSC_CLIENT_OFFLINE_VERIFIER_DIR_REQUIRED")
		os.Exit(2)
	}
	if e:=verifyDir(os.Args[1]);e!=nil{
		fmt.Fprintln(os.Stderr,"GSC_CLIENT_CANARY_REJECTED:",e.Error())
		os.Exit(2)
	}
	fmt.Println("GSC_CLIENT_OFFLINE_SIGNATURE_AND_FILE_HASH_PASS")
}
