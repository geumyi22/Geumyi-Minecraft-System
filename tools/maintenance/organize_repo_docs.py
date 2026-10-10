#!/usr/bin/env python3
"""One-time Markdown document relocation; no program/runtime/CI payload edits."""
import argparse
from collections import defaultdict
from pathlib import Path
import posixpath
import re
import subprocess
from urllib.parse import unquote

ROOT=Path(__file__).resolve().parents[2]
MOVE={
 "DAY4-E2E-REPORT.md":"docs/history/day-04/DAY4-E2E-REPORT.md",
 "DAY5-STABILITY-REPORT.md":"docs/history/day-05/DAY5-STABILITY-REPORT.md",
 "DAY6-DEVICE-TEST.md":"docs/history/day-06/DAY6-DEVICE-TEST.md",
 "DAY7-CI-REPORT.md":"docs/history/day-07/DAY7-CI-REPORT.md",
 "DAY8-RELEASE-REPORT.md":"docs/history/day-08/DAY8-RELEASE-REPORT.md",
 "DAY8-RUNBOOK.md":"docs/history/day-08/DAY8-RUNBOOK.md",
 "DAY10-PLAN.md":"docs/history/day-10/DAY10-PLAN.md",
 "DAY10-E2E-REPORT.md":"docs/history/day-10/DAY10-E2E-REPORT.md",
 "DAY11-PLAN.md":"docs/history/day-11/DAY11-PLAN.md",
 "DAY11-PHASE0-REPORT.md":"docs/history/day-11/DAY11-PHASE0-REPORT.md",
 "DAY11-PHASE7-REPORT.md":"docs/history/day-11/DAY11-PHASE7-REPORT.md",
 "DAY11-FINAL-REPORT.md":"docs/history/day-11/DAY11-FINAL-REPORT.md",
 "DEPLOYMENT-ARCHITECTURE.md":"docs/reference/DEPLOYMENT-ARCHITECTURE.md",
 "RECOVERY-REPORT.md":"docs/reference/RECOVERY-REPORT.md",
 "SECURITY-NOTES.md":"docs/reference/SECURITY-NOTES.md",
 "VERSION-MATRIX.md":"docs/reference/VERSION-MATRIX.md",
 "MAINTENANCE-MODE.md":"docs/operations/MAINTENANCE-MODE.md",
}
# Live-gate JSON, final E2E Markdown and operator-kit input Markdown stay at root.
LINK=re.compile(r"(?P<start>!?\[[^\]\n]*\]\()(?P<url>[^)\n]+)(?P<end>\))")

def tracked():
 return sorted(v.decode("utf-8") for v in subprocess.check_output(["git","ls-files","-z"],cwd=ROOT).split(b"\0") if v)

def source_references(files,candidates):
 found=defaultdict(list)
 for p in files:
  if not (p.startswith((".github/","tools/","GSC/","GSCM/","Plugins/")) and p.endswith((".yml",".yaml",".py",".ps1",".cmd",".sh",".go",".js",".gradle",".toml"))):
   continue
  f=ROOT/p
  try:
   if f.stat().st_size>1048576:continue
   t=f.read_text(encoding="utf-8-sig")
  except (UnicodeError,OSError):continue
  for name in candidates:
   if name in t:found[name].append(p)
 return found

def index_pages(active,blocked):
 hist=["# Day 4–11 개발 및 검증 기록","","기존 보고서 원문은 변경하지 않고 일차별 폴더로 보관합니다.",""]
 for folder in sorted({posixpath.dirname(v) for v in active.values() if v.startswith("docs/history/")}):
  hist.append("## Day "+str(int(folder.split("-")[-1]))+"\n")
  for name,path in sorted(active.items()):
   if posixpath.dirname(path)==folder:
    hist.append("- ["+name+"]("+posixpath.relpath(path,"docs/history")+")")
  hist.append("")
 reference=["# 공통 기술·복구 자료",""]
 for name,path in sorted(active.items()):
  if path.startswith("docs/reference/"):reference.append("- ["+name+"]("+posixpath.basename(path)+")")
 operations=["# 운영·유지보수 자료","","- [프로젝트 마감](../../PROJECT-CLOSEOUT-2026-10-11.md)"]
 for name,path in sorted(active.items()):
  if path.startswith("docs/operations/"):operations.append("- ["+name+"]("+posixpath.basename(path)+")")
 overview=["# 금이 마인크래프트 시스템 문서 안내",
  "",
  "최상위 폴더의 복잡한 개발 기록을 일차별 및 주제별로 재배치했습니다.",
  "",
  "## 찾아보기",
  "",
  "- [현재 프로젝트 안내](../README.md)",
  "- [프로젝트 종료 보고서](../PROJECT-CLOSEOUT-2026-10-11.md)",
  "- [Day 1~12 전체 일차 상태](../DAY-TIMELINE.md)",
  "- [Day 4~11 이력](history/INDEX.md)",
  "- [Day 12 상세 65개 보고서](day12/INDEX.md)",
  "- [공통 아키텍처·버전·복구·보안](reference/INDEX.md)",
  "- [운영 및 유지보수](operations/INDEX.md)",
  "- [과거 CI 워크플로 보관함](archive/workflows/README.md)",
  "",
  "## 최상위 문서 보존 원칙",
  "",
  "FINAL 게이트 JSON, 최종 E2E/버전 문서, Day 12 CI·Operator Kit가 루트에서 읽는 계획서·실행 안내, 소스 매니페스트는 위치를 변경하지 않았습니다.",
  "이동은 Git 히스토리를 재작성하지 않으며 서버 파일·백업·실행 파일을 건드리지 않습니다.",
  ""]
 if blocked:
  overview+=["## 코드에서 경로를 참조하여 이동하지 않은 문서",""]
  for name,refs in sorted(blocked.items()):overview.append("- "+name+" — "+", ".join(refs[:3]))
 return {
  "docs/README.md":"\n".join(overview)+"\n",
  "docs/history/INDEX.md":"\n".join(hist)+"\n",
  "docs/reference/INDEX.md":"\n".join(reference)+"\n",
  "docs/operations/INDEX.md":"\n".join(operations)+"\n",
 }

def updated_links(text,old,new,active,after,byname,stats):
 olddir=posixpath.dirname(old);newdir=posixpath.dirname(new) or "."
 def fix(m):
  v=m.group("url").strip()
  if not v or v.startswith(("#","/","http:","https:","mailto:","<")) or " " in v:return m.group()
  stem,hashmark,anchor=v.partition("#")
  stem,question,query=stem.partition("?")
  stem=unquote(stem)
  original=posixpath.normpath(posixpath.join(olddir,stem))
  destination=active.get(original,original)
  if destination not in after:
   found=byname.get(posixpath.basename(stem),[])
   if len(found)!=1:return m.group()
   destination=found[0]
  rel=posixpath.relpath(destination,newdir)
  if question:rel+="?"+query
  if hashmark:rel+="#"+anchor
  if rel!=v:stats.append((new,v,rel))
  return m.group("start")+rel+m.group("end")
 return LINK.sub(fix,text)

def run(apply):
 files=tracked();before=set(files)
 active={old:new for old,new in MOVE.items() if old in before}
 blocked=source_references(files,list(active))
 for old in blocked:active.pop(old,None)
 if any(new in before for new in active.values()):raise RuntimeError("destination already exists")
 generated=index_pages(active,blocked)
 after=(before-set(active))|set(active.values())|set(generated)
 byname=defaultdict(list)
 for name in sorted(after):
  if name.lower().endswith((".md",".txt")):byname[posixpath.basename(name)].append(name)
 changes=[];updates={}
 for old in files:
  if not old.endswith(".md"):continue
  new=active.get(old,old)
  src=(ROOT/old).read_text(encoding="utf-8-sig")
  out=updated_links(src,old,new,active,after,byname,changes)
  if old!=new or src!=out:updates[new]=out
 updates.update(generated)
 # Fail closed on any unresolved links pointing specifically at relocated names.
 oldnames=set(active)
 invalid=[]
 for dst,data in updates.items():
  for match in LINK.finditer(data):
   v=match.group("url").strip()
   if not v or v.startswith(("#","/","http:","https:","mailto:")) or " " in v:continue
   stem=unquote(v.split("#")[0].split("?")[0])
   resolved=posixpath.normpath(posixpath.join(posixpath.dirname(dst),stem))
   if resolved not in after and posixpath.basename(stem) in oldnames:
    invalid.append(dst+" -> "+v)
 if invalid:raise RuntimeError("Unresolved moved-doc links: "+repr(invalid[:20]))
 print("DOCUMENT_ORGANIZER: candidate root moves",len(active),"blocked",len(blocked),"link fixes",len(changes),"markdown updates",len(updates))
 for old,new in sorted(active.items()):print("MOVE",old,"->",new)
 for old,refs in sorted(blocked.items()):print("RETAIN",old,"because",",".join(refs[:4]))
 if not apply:return
 for old in active:(ROOT/old).unlink()
 for dst,content in updates.items():
  path=ROOT/dst;path.parent.mkdir(parents=True,exist_ok=True)
  path.write_text(content,encoding="utf-8")
 print("DOCUMENT_ORGANIZER: applied")

if __name__=="__main__":
 p=argparse.ArgumentParser();p.add_argument("--apply",action="store_true")
 args=p.parse_args();run(args.apply)
