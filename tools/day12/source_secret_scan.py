#!/usr/bin/env python3
import json,re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=Path(sys.argv[sys.argv.index("--output")+1]) if "--output" in sys.argv else ROOT/"day12-secret-scan.json"
EXT={".go",".py",".ps1",".cmd",".yml",".yaml",".json",".md",".txt",".properties",".toml",".gradle",".kts",".dart",".swift",".sh"}
SKIP={".git","build","dist",".dart_tool",".gradle","Pods","DerivedData"}
patterns=[
 ("private_key",re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")),
 ("github_token",re.compile(r"\bgh[pousr]_[A-Za-z0-9_]{30,}\b")),
 ("github_pat",re.compile(r"\bgithub_pat_[A-Za-z0-9_]{40,}\b")),
 ("aws_access_key",re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
 ("discord_bot_token",re.compile(r"\b(?:mfa\.)?[A-Za-z0-9_-]{24,}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{25,}\b")),
]
allow=("CHANGE_THIS","REDACTED","PLACEHOLDER","EXAMPLE","example.com","dummy","synthetic")
findings=[]
for p in ROOT.rglob("*"):
    if not p.is_file() or p.suffix.lower() not in EXT or any(x in SKIP for x in p.parts):continue
    try:
        if p.stat().st_size>2_000_000:continue
        text=p.read_text(encoding="utf-8",errors="ignore")
    except Exception:continue
    for n,line in enumerate(text.splitlines(),1):
        if any(a in line for a in allow):continue
        if "$" + "{{ secrets." in line:continue
        for kind,rx in patterns:
            if rx.search(line):
                findings.append({"kind":kind,"path":p.relative_to(ROOT).as_posix(),"line":n})
report={"schema":1,"scanner":"day12-source-secret-scan","findings":findings,"count":len(findings)}
OUT.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
print(json.dumps(report))
sys.exit(2 if findings else 0)
