//go:build ignore

// P0 CONFIG CONTRACT - DISPOSABLE FIXTURE ONLY.
// This helper is run TOGETHER with disposable_crypto_roundtrip.go.
// It reads only hardcoded fake config bytes, not any operator paths or keys.
// It deliberately does not generate a real backup or upload to cloud.
package main

import (
  "archive/tar"
  "bytes"
  "crypto/rand"
  "errors"
  "fmt"
  "io"
  "os"
  "path"
  "path/filepath"
  "sort"
  "strings"
)

var expectedP0Files = []string{
  "gsc/server.json",
  "paper/wild/server.properties",
  "paper/playground/server.properties",
  "paper/other/server.properties",
  "paper/lobby/server.properties",
  "proxy/wild/velocity.toml",
  "proxy/playground/velocity.toml",
  "proxy/other/velocity.toml",
  "proxy/wild/forwarding.secret",
  "proxy/playground/forwarding.secret",
  "proxy/other/forwarding.secret",
  "proxy/wild/plugins/floodgate/key.pem",
  "proxy/playground/plugins/floodgate/key.pem",
  "proxy/other/plugins/floodgate/key.pem",
}
func allowedP0Name(name string) bool {
  if name=="" || path.Clean(name)!=name || strings.ContainsAny(name, "\\:\x00\r\n") ||
     strings.HasPrefix(name,"/") || strings.Contains(name,"..") {return false}
  parts:=strings.Split(name,"/")
  for _,component:=range parts {
    if component=="" || component=="." || component==".." || strings.HasSuffix(component,".") {return false}
  }
  if name=="gsc/server.json" {return true}
  if len(parts)<3{return false}
  tail:=strings.Join(parts[2:],"/")
  switch parts[0] {
  case "paper":
    switch parts[1] {case "wild","playground","other","lobby": default:return false}
    switch tail {
    case "server.properties","bukkit.yml","spigot.yml","permissions.yml",
      "ops.json","whitelist.json","banned-players.json","banned-ips.json",
      "start.bat","start.cmd","eula.txt",
      "config/paper-global.yml","config/paper-world-defaults.yml",
      "plugins/GeumyiTechnology/config.yml","plugins/GeumyiChemistry/config.yml":
      return true
    }
  case "proxy":
    switch parts[1] {case "wild","playground","other":default:return false}
    switch tail {
    case "velocity.toml","forwarding.secret",
      "plugins/Geyser-Velocity/config.yml","plugins/floodgate/config.yml",
      "plugins/floodgate/key.pem":
      return true
    }
  }
  return false
}
func validateP0Input(files map[string][]byte) error {
  if len(files)<len(expectedP0Files) || len(files)>128 {return errors.New("P0 input count incomplete/outside bounds")}
  lower:=map[string]bool{}
  size:=0
  for name,b:=range files {
    if !allowedP0Name(name){return errors.New("P0 path not allowlisted")}
    k:=strings.ToLower(name);if lower[k]{return errors.New("casefold collision")};lower[k]=true
    if len(b)<1 || len(b)>8*1024*1024{return errors.New("P0 file size unsafe")}
    size+=len(b);if size>32*1024*1024{return errors.New("P0 aggregate size unsafe")}
  }
  for _,name:=range expectedP0Files {if len(files[name])==0{return errors.New("missing mandatory P0 input")}}
  for _,relative:=range []string{"forwarding.secret","plugins/floodgate/key.pem"} {
    baseline:=files["proxy/wild/"+relative]
    for _,role:=range []string{"playground","other"} {
      if !bytes.Equal(baseline,files["proxy/"+role+"/"+relative]){
        return errors.New("cross-proxy key mismatch")
      }
    }
  }
  return nil
}
func fixtureP0Inputs() map[string][]byte {
  out:=map[string][]byte{
    "gsc/server.json":[]byte("{\"api_token\":\"FAKE_NEVER_REAL_2D8F\",\"servers\":[]}"),
    "paper/wild/server.properties":[]byte("rcon.password=FAKE_WILD_2D8F"),
    "paper/playground/server.properties":[]byte("rcon.password=FAKE_PLAYGROUND_2D8F"),
    "paper/other/server.properties":[]byte("rcon.password=FAKE_OTHER_2D8F"),
    "paper/lobby/server.properties":[]byte("rcon.password=FAKE_LOBBY_2D8F"),
  }
  for _,role:=range []string{"wild","playground","other"} {
    out["proxy/"+role+"/velocity.toml"]=[]byte("config-version = \"2.9\"\n")
    out["proxy/"+role+"/forwarding.secret"]=[]byte("SYNTHETIC_FORWARDING_KEY_NOT_LIVE")
    out["proxy/"+role+"/plugins/floodgate/key.pem"]=[]byte("SYNTHETIC_FLOODGATE_PRIVATE_KEY_NOT_LIVE")
    out["proxy/"+role+"/plugins/Geyser-Velocity/config.yml"]=[]byte("bedrock:\n  port: 19132\n")
  }
  return out
}
func p0Fatal(err error){if err!=nil{panic(err)}}
func p0Reject(label string,err error){if err==nil{panic("P0_NEGATIVE_CASE_ACCEPTED_"+label)}}
func runP0DisposableContract() {
  files:=fixtureP0Inputs()
  p0Fatal(validateP0Input(files))
  del:=make(map[string][]byte,len(files))
  for k,v:=range files{del[k]=v};delete(del,"proxy/other/plugins/floodgate/key.pem")
  p0Reject("MISSING_KEY",validateP0Input(del))
  changed:=make(map[string][]byte,len(files))
  for k,v:=range files{changed[k]=v};changed["proxy/other/forwarding.secret"]=[]byte("SYNTHETIC_DIFFERENT")
  p0Reject("MISMATCHED_KEY",validateP0Input(changed))
  changed["proxy/other/forwarding.secret"]=files["proxy/other/forwarding.secret"]
  changed["paper/wild/world/region/r.0.0.mca"]=[]byte("world-not-P0")
  p0Reject("WORLD_DISALLOWED",validateP0Input(changed))
  delete(changed,"paper/wild/world/region/r.0.0.mca")
  changed["proxy/wild/../../gsc/server.json"]=[]byte("path-escape")
  p0Reject("TRAVERSAL_DISALLOWED",validateP0Input(changed))
  changed["proxy/wild/../../gsc/server.json"]=nil
  delete(changed,"proxy/wild/../../gsc/server.json")
  tarBytes,err:=fixtureTar(files);p0Fatal(err)
  key:=make([]byte,32);_,err=io.ReadFull(rand.Reader,key);p0Fatal(err)
  folder,err:=os.MkdirTemp("","day12-p0-fixture-");p0Fatal(err);defer os.RemoveAll(folder)
  parts:=filepath.Join(folder,"encrypted");p0Fatal(os.Mkdir(parts,0700))
  metadata,mac,err:=seal(parts,tarBytes,key);p0Fatal(err)
  for _,name:=range []string{"gsc/server.json","proxy/wild/forwarding.secret"} {
    if bytes.Contains(metadata,files[name]){panic("P0_MANIFEST_EXPOSED_FIXTURE_SECRET")}
  }
  entries,err:=os.ReadDir(parts);p0Fatal(err)
  for _,entry:=range entries {
    blob,err:=os.ReadFile(filepath.Join(parts,entry.Name()));p0Fatal(err)
    for _,name:=range []string{"gsc/server.json","proxy/wild/forwarding.secret"} {
      if bytes.Contains(blob,files[name]){panic("P0_CIPHERTEXT_EXPOSED_FIXTURE_SECRET")}
    }
  }
  restored,err:=restore(parts,metadata,mac,key);p0Fatal(err)
  if !bytes.Equal(restored,tarBytes){panic("P0_TAR_BYTE_MISMATCH")}
  clean:=filepath.Join(folder,"isolated-restore")
  p0Fatal(os.Mkdir(clean,0700))
  p0Fatal(fixtureRestoreTree(restored,clean))
  names:=make([]string,0,len(files));for k:=range files{names=append(names,k)};sort.Strings(names)
  for _,n:=range names {
    b,err:=os.ReadFile(filepath.Join(clean,filepath.FromSlash(n)));p0Fatal(err)
    if !bytes.Equal(b,files[n]){panic("P0_RESTORED_CONFIG_DIFFERENCE")}
  }
  // Simulate a valid AEAD manifest paired with an unsafe file path.
  evil:=map[string][]byte{"../outside": []byte("evil")}
  evilTar,err:=fixtureTar(evil);p0Fatal(err)
  p0Reject("UNSAFE_EXTRACTION",fixtureRestoreTree(evilTar,filepath.Join(folder,"evil-restore")))
  // Reject unexpected TAR node types before any extraction.
  var buf bytes.Buffer
  tw:=tar.NewWriter(&buf)
  p0Fatal(tw.WriteHeader(&tar.Header{Name:"proxy/wild/forwarding.secret",Typeflag:tar.TypeSymlink,Linkname:"../outside"}))
  p0Fatal(tw.Close())
  p0Reject("SYMLINK_EXTRACTION",fixtureRestoreTree(buf.Bytes(),filepath.Join(folder,"links")))
  if _,err:=os.Stat(filepath.Join(folder,"outside"));err==nil{panic("P0_EXTRACTED_OUTSIDE_DISPOSABLE")}
  fmt.Printf("DAY12_P0_CRYPTO_CONTRACT_DISPOSABLE_PASS input_roles=8 validated_files=%d AES_256_GCM=true HMAC=true no_real_source_access=true no_cloud_upload=true no_operator_secrets=true no_production_backup=true\n",len(files))
}
func init(){runP0DisposableContract()}
