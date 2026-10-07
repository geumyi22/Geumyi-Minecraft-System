#!/usr/bin/env python3
import json,sys
from pathlib import Path
p=Path(sys.argv[1] if len(sys.argv)>1 else "FINAL-RELEASE-GATES.json")
j=json.loads(p.read_text(encoding="utf-8"))
bad=[]
for section in ("repository_gates","live_gates"):
    for k,v in j.get(section,{}).items():
        if v!="PASS": bad.append(f"{section}.{k}={v}")
allowed=(not bad and j.get("release",{}).get("stable_release_allowed") is True and j.get("release",{}).get("maintenance_mode_allowed") is True)
print(json.dumps({"allowed":allowed,"blocking":bad},indent=2))
sys.exit(0 if allowed else 2)
