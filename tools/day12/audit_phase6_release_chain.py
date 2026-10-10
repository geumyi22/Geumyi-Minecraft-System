#!/usr/bin/env python3
import copy, hashlib, json, pathlib, subprocess, sys, tempfile
root=pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0,str(root/"tools/day12"))
from validate_final_release_gates import check_gates
from validate_final_closure_evidence import review_closure_evidence, PRIVATE_PORTS
def need(ok,msg):
    if not ok: raise AssertionError(msg)
read=lambda p:(root/p).read_text(encoding="utf-8-sig")
g=json.loads(read("FINAL-RELEASE-GATES.json"))
ok,reasons=check_gates(g)
need(not ok and "phase_12_10_backend_ports_private" in g["live_gates"],"12.10 release gate")
need(g["release"]=={"stable_release_allowed":False,"maintenance_mode_allowed":False},"stable unexpectedly enabled")
fixture=copy.deepcopy(g);fixture["status"]="VERIFIED_ALL_MANDATORY_GATES"
for section in ("repository_gates","live_gates"):
    for key in fixture[section]:fixture[section][key]="PASS"
fixture["release"]={"stable_release_allowed":True,"maintenance_mode_allowed":True}
need(check_gates(fixture)[0],"synthetic complete fixture")
for key in ("phase_12_7_offline_known_good_startup","phase_12_10_backend_ports_private","phase_12_11_final_live_e2e","phase_12_12_soak"):
    bad=copy.deepcopy(fixture);bad["live_gates"][key]="PENDING_LIVE"
    need(not check_gates(bad)[0],"missing fail-closed: "+key)
bad=copy.deepcopy(fixture);del bad["live_gates"]["phase_12_10_backend_ports_private"]
need(not check_gates(bad)[0] and len(PRIVATE_PORTS)==8,"native backend source coverage")
need(not review_closure_evidence(json.loads(read("FINAL-HEALTH-REPORT.json")),json.loads(read("FINAL-SECURITY-REPORT.json")))[0],"host security closure must block")
release=read(".github/workflows/day12-final-release.yml")
closure=read(".github/workflows/day12-final-gate.yml")
for src in (release,closure):
    need("validate_final_release_gates.py FINAL-RELEASE-GATES.json" in src,"missing final gate")
    need("validate_final_closure_evidence.py ." in src,"missing health/security veto")
for term in ("needs: [gate, safety, security, system, android, ios]","require_release_signing: true","DEPLOYMENT_ED25519_PRIVATE_KEY_B64","openssl pkeyutl -verify","sha256sum -c",'gh release create "$TAG"',"gh release view"):
    need(term in release,"missing release contract: "+term)
need('existing_tag="$(git ls-remote --tags --refs origin "refs/tags/${TAG}")"' in release,"missing exact remote Git-tag collision check")
need('if [[ -n "$existing_tag" ]]; then echo \'Git tag already exists\'; exit 1; fi' in release,"missing tag reuse fail-closed path")
need(release.index('git ls-remote --tags --refs origin') < release.index('gh release create "$TAG"'),"tag collision check ordered after publication")
terms=("Verify checksum sidecars","Generate Stable deployment manifest","Sign and verify deployment manifest","Add final evidence to release assets","Publish final immutable Stable release")
positions=[release.find(x) for x in terms]
need(all(x>=0 for x in positions) and positions==sorted(positions),"release order")
with tempfile.TemporaryDirectory() as tmp:
    d=pathlib.Path(tmp);a=d/"assets";a.mkdir();body=b"CI only"
    (a/"fixture.jar").write_bytes(body)
    catalog=d/"catalog.json";catalog.write_text(json.dumps({"repository":"geumyi22/Geumyi-Minecraft-System","components":{"fixture":{"artifact_glob":"fixture.jar","version":"test","kind":"plugin","targets":["disposable"]}}}))
    m=d/"manifest.json"
    cmd=[sys.executable,str(root/"tools/release/generate_manifest.py"),"--catalog",str(catalog),"--assets",str(a),"--channel","stable","--tag","fixture-not-release","--base-url","https://example.invalid","--output",str(m)]
    need(subprocess.run(cmd,capture_output=True,timeout=15).returncode==0,"manifest fixture")
    need(json.loads(m.read_text())["components"]["fixture"]["sha256"]==hashlib.sha256(body).hexdigest(),"real byte hashing")
    (a/"fixture.jar").unlink();m.unlink()
    need(subprocess.run(cmd,capture_output=True,timeout=15).returncode!=0 and not m.exists(),"missing asset fail closed")
print(json.dumps({"result":"PASS_REPOSITORY_RELEASE_CHAIN_AUDIT","synthetic_gate_negative_cases":4,"actual_release_signed":False,"stable_allowed":False,"blocking_reasons":len(reasons)}))
