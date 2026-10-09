#!/usr/bin/env python3
"""Build GSC-only Canary manifest (draft distribution). Never publish by itself."""
from __future__ import annotations
import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
import re
import sys

VERSION = "4.3.9-rc.2"
SOURCE_SHA = "8a02ef221ada5936e5ef6d5c0826fa8d1880d123"
SETUP_NAME = "GeumyiServerCenter-v4.3.9-rc.2-Setup.exe"
SETUP_SHA256 = "2a623e25193d6b92dc4ec69b9ce76f098b246541c2861087f7c4911ae297602f"
REPO = "geumyi22/Geumyi-Minecraft-System"
TAG = "system-2026.10.10-day12-gsc439-rc2-canary"


def build(setup: Path, tag: str, base_url: str) -> dict:
    if tag != TAG:
        raise ValueError("unexpected canary draft tag")
    if base_url != f"https://github.com/{REPO}/releases/download/{tag}":
        raise ValueError("unexpected release host or path")
    if setup.name != SETUP_NAME or not setup.is_file():
        raise ValueError("wrong or missing pinned GSC candidate installer")
    h = hashlib.sha256()
    size = 0
    with setup.open("rb") as f:
        for b in iter(lambda: f.read(1024 * 1024), b""):
            h.update(b)
            size += len(b)
    if h.hexdigest() != SETUP_SHA256 or size < 100000:
        raise ValueError("GSC candidate installer SHA256/size mismatch")
    return {
        "schema": 1,
        "channel": "canary",
        "release": tag,
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "repository": REPO,
        "components": {
            "gsc": {
                "version": VERSION,
                "kind": "gsc",
                "targets": ["host"],
                "requires_restart": True,
                "file": SETUP_NAME,
                "url": f"{base_url}/{SETUP_NAME}",
                "sha256": SETUP_SHA256,
                "size": size,
            }
        },
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--setup", required=True)
    ap.add_argument("--tag", required=True)
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()
    try:
        payload = build(Path(args.setup), args.tag, args.base_url)
        dest = Path(args.output)
        if dest.name != "deployment-canary.json":
            raise ValueError("output manifest filename must be deployment-canary.json")
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("GSC-only Canary draft manifest prepared, component count: 1; not signed or published by this script")
        return 0
    except (ValueError, OSError) as exc:
        print("GSC Canary manifest refused:", str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
