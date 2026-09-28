#!/usr/bin/env python3
import argparse, datetime as dt, hashlib, json, pathlib, sys

def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", required=True)
    ap.add_argument("--assets", required=True)
    ap.add_argument("--channel", required=True, choices=["stable", "beta", "canary"])
    ap.add_argument("--tag", required=True)
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    catalog = json.loads(pathlib.Path(args.catalog).read_text(encoding="utf-8"))
    assets = pathlib.Path(args.assets)
    out = {
        "schema": 1,
        "channel": args.channel,
        "release": args.tag,
        "generated_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "repository": catalog["repository"],
        "components": {},
    }

    missing = []
    for key, meta in catalog["components"].items():
        matches = list(assets.rglob(meta["artifact_glob"]))
        if len(matches) != 1:
            missing.append(f"{key}: expected exactly one {meta['artifact_glob']!r}, found {len(matches)}")
            continue
        p = matches[0]
        item = {k: v for k, v in meta.items() if k != "artifact_glob"}
        item.update({
            "file": p.name,
            "url": args.base_url.rstrip("/") + "/" + p.name,
            "sha256": sha256(p),
            "size": p.stat().st_size,
        })
        out["components"][key] = item

    if missing:
        print("Manifest generation failed:", file=sys.stderr)
        for x in missing:
            print(" - " + x, file=sys.stderr)
        return 2

    pathlib.Path(args.output).write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {args.output} with {len(out['components'])} components")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
