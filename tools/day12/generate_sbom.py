#!/usr/bin/env python3
import json,re,sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=Path(sys.argv[sys.argv.index("--output")+1]) if "--output" in sys.argv else ROOT/"FINAL-SBOM.cdx.json"
components=[]
seen=set()
def add(name,version,ctype="library",purl=None,scope=None,props=None):
    key=(name,version,purl or "")
    if key in seen:return
    seen.add(key)
    c={"type":ctype,"name":name,"version":version or "unknown","bom-ref":purl or f"pkg:generic/{name}@{version or 'unknown'}"}
    if purl:c["purl"]=purl
    if scope:c["scope"]=scope
    if props:c["properties"]=[{"name":k,"value":str(v)} for k,v in sorted(props.items())]
    components.append(c)

deploy=json.loads((ROOT/"deploy/components.json").read_text(encoding="utf-8"))
for cid,x in sorted(deploy["components"].items()):
    add(cid,str(x.get("version","unknown")),"application" if x.get("kind") in ("gsc","mobile","agent") else "library",
        props={"geumyi:kind":x.get("kind",""),"geumyi:targets":",".join(x.get("targets",[]))})

pub=ROOT/"GSCM/pubspec.yaml"
if pub.exists():
    section=None
    for line in pub.read_text(encoding="utf-8").splitlines():
        if line=="dependencies:":section="runtime";continue
        if line=="dev_dependencies:":section="dev";continue
        if line and not line.startswith(" ") and line.endswith(":") and line not in ("dependencies:","dev_dependencies:"):section=None
        m=re.match(r"^  ([A-Za-z0-9_+-]+):\s*([^#]+)?$",line)
        if section and m:
            name=m.group(1);val=(m.group(2) or "").strip()
            if val and not val.endswith(":") and val!="flutter":
                add(name,val,"library",f"pkg:pub/{name}@{val}",scope="optional" if section=="dev" else "required",props={"geumyi:source":"GSCM/pubspec.yaml"})
for gradle in ROOT.glob("Plugins/**/build.gradle.kts"):
    text=gradle.read_text(encoding="utf-8",errors="ignore")
    for conf,coord in re.findall(r'(?m)^\s*(implementation|api|compileOnly|runtimeOnly|testImplementation)\("([^"]+)"\)',text):
        parts=coord.split(":")
        if len(parts)>=3:
            group,artifact,version=parts[0],parts[1],":".join(parts[2:])
            add(artifact,version,"library",f"pkg:maven/{group}/{artifact}@{version}",scope="optional" if conf in ("compileOnly","testImplementation") else "required",props={"geumyi:declared_in":gradle.relative_to(ROOT).as_posix()})

bom={
 "bomFormat":"CycloneDX","specVersion":"1.5","version":1,
 "metadata":{"component":{"type":"application","name":"Geumyi Minecraft System","version":"Day12-pre-final"},
             "properties":[{"name":"geumyi:scope","value":"declared dependencies and managed components; transitive resolution not claimed"},
                           {"name":"geumyi:status","value":"PRELIMINARY_UNTIL_FINAL_RELEASE"}]},
 "components":sorted(components,key=lambda x:(x["name"],x["version"],x["bom-ref"]))
}
OUT.write_text(json.dumps(bom,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(f"SBOM components: {len(components)} -> {OUT}")
