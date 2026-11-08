#!/usr/bin/env python3
"""Prepare/verify a GSC-only personal Stable payload; never access private keys."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

REPOSITORY = "geumyi22/Geumyi-Minecraft-System"
TAG = "gsc-v5.0.0"
VERSION = "5.0.0"
PUBLIC_KEY_SHA256 = "f21e62e87bb9d68ba05a964e0efd2e160ac249ebfbbf5f4a5125bae8f11718e3"
BINARIES = ("GeumyiServerCenter-v5.0.0-Setup.exe", "GeumyiServerHost.exe", "GeumyiServerCenter.exe")
LEDGER = "gsc-5.0.0-personal-acceptance.json"
NOTES = "RELEASE-NOTES-5.0.0.md"
MANIFEST = "deployment-stable.json"
EXPECTED_FILES = set(BINARIES) | {"SHA256SUMS.txt", LEDGER, NOTES, MANIFEST,
    MANIFEST + ".sig", "deployment-public.pem", "GSC-PERSONAL-PROVENANCE.json", "SOURCE-COMMIT.txt"}


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def validate_ledger(value):
    require(value.get("schema") == 1 and value.get("scope") == "personal_operator_accepted", "wrong personal acceptance scope")
    require(value.get("full_live_qa_pass_claimed") is False, "full live QA must not be claimed")
    evidence = value.get("evidence")
    require(isinstance(evidence, list) and bool(evidence), "acceptance evidence missing")
    for row in evidence:
        require(isinstance(row, dict) and row.get("status") in {
            "verified", "operator_confirmed", "operator_accepted", "not_run", "unresolved", "pending"
        }, "unknown evidence status")


def check_inputs(tag, commit):
    require(tag == TAG, "unexpected immutable release tag")
    require(re.fullmatch(r"[0-9a-f]{40}", commit) is not None, "exact source commit required")


def resolve_draft_id(pages, tag, commit):
    """Resolve an unpublished draft from authenticated paginated release lists.

    GitHub's releases/tags endpoint need not resolve a draft before its Git
    tag exists. Never treat that 404 as evidence that the draft is absent.
    """
    check_inputs(tag, commit)
    require(isinstance(pages, list) and all(isinstance(page, list) for page in pages), "invalid paginated release list")
    releases = [item for page in pages for item in page]
    require(all(isinstance(item, dict) for item in releases), "invalid release list item")
    matches = [item for item in releases if item.get("tag_name") == tag]
    require(len(matches) == 1, "expected exactly one release for immutable tag")
    draft = matches[0]
    require(draft.get("draft") is True and draft.get("prerelease") is False and draft.get("target_commitish") == commit,
        "not the reviewed exact-commit Stable draft")
    release_id = draft.get("id")
    require(type(release_id) is int and release_id > 0, "invalid draft release ID")
    return release_id


def verify_checksums(assets, expected):
    entries = {}
    for line in (assets / "SHA256SUMS.txt").read_text(encoding="ascii").splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9._+-]+)", line)
        require(match is not None, "malformed checksum entry")
        checksum, name = match.groups()
        require(name not in entries, "duplicate checksum entry")
        entries[name] = checksum
    require(set(entries) == set(expected), "checksum inventory differs from expected files")
    for name, checksum in entries.items():
        require(digest(assets / name) == checksum, "artifact checksum mismatch: " + name)


def prepare(assets, root, tag, commit, run_id):
    check_inputs(tag, commit)
    require(run_id > 0, "exact CI run required")
    require({p.name for p in assets.iterdir()} == set(BINARIES) | {"SHA256SUMS.txt"}, "unexpected Windows CI artifact inventory")
    verify_checksums(assets, BINARIES)
    for name in BINARIES:
        require((assets / name).stat().st_size > 100000, "Windows binary too small")
        with (assets / name).open("rb") as stream:
            require(stream.read(2) == b"MZ", "Windows PE header missing")
    validate_ledger(load(root / "deploy" / LEDGER))
    require(load(root / "FINAL-RELEASE-GATES.json")["release"]["stable_release_allowed"] is False, "formal Day12 lock changed")
    shutil.copyfile(root / "deploy" / LEDGER, assets / LEDGER)
    shutil.copyfile(root / "docs/releases/GSC-5.0.0.md", assets / NOTES)
    (assets / "SOURCE-COMMIT.txt").write_text(commit + "\n", encoding="ascii")
    installer = assets / BINARIES[0]
    manifest = {
        "schema": 1, "channel": "stable", "release": tag, "repository": REPOSITORY,
        "source_commit": commit, "ci_run_id": run_id, "scope": "personal_operator_accepted",
        "windows_binaries": {name: {"sha256": digest(assets / name), "size": (assets / name).stat().st_size}
            for name in BINARIES},
        "components": {"gsc": {"version": VERSION, "kind": "gsc", "targets": ["host"],
            "requires_restart": True, "file": installer.name,
            "url": f"https://github.com/{REPOSITORY}/releases/download/{tag}/{installer.name}",
            "sha256": digest(installer), "size": installer.stat().st_size}},
    }
    write_json(assets / MANIFEST, manifest)
    write_json(assets / "GSC-PERSONAL-PROVENANCE.json", {
        "schema": 1, "scope": "personal_operator_accepted", "source_commit": commit,
        "ci_run_id": run_id, "ci_run_url": f"https://github.com/{REPOSITORY}/actions/runs/{run_id}",
        "exact_ci_workflow": "system-ci.yml called by personal Stable stage",
        "acceptance_sha256": digest(assets / LEDGER), "formal_day12_closure": False,
        "windows_authenticode_signed": False, "deployment_signature": "Ed25519",
    })


def seal(assets):
    require({p.name for p in assets.iterdir()} == EXPECTED_FILES, "release inventory incomplete")
    (assets / "SHA256SUMS.txt").write_text("".join(
        digest(assets / name) + "  " + name + "\n" for name in sorted(EXPECTED_FILES - {"SHA256SUMS.txt"})
    ), encoding="ascii", newline="\n")


def verify(assets, root, tag, commit, release_metadata=None):
    check_inputs(tag, commit)
    require({p.name for p in assets.iterdir()} == EXPECTED_FILES, "unexpected release inventory")
    verify_checksums(assets, EXPECTED_FILES - {"SHA256SUMS.txt"})
    require(digest(assets / "deployment-public.pem") == PUBLIC_KEY_SHA256, "trusted deployment public key mismatch")
    subprocess.run(["openssl", "pkeyutl", "-verify", "-rawin", "-pubin", "-inkey", str(assets / "deployment-public.pem"),
        "-in", str(assets / MANIFEST), "-sigfile", str(assets / (MANIFEST + ".sig"))], check=True)
    manifest = load(assets / MANIFEST)
    require(manifest.get("schema") == 1 and manifest.get("channel") == "stable" and manifest.get("release") == tag and
        manifest.get("repository") == REPOSITORY and manifest.get("source_commit") == commit and
        manifest.get("scope") == "personal_operator_accepted", "signed release identity mismatch")
    require(set(manifest.get("components", {})) == {"gsc"}, "release must contain GSC only")
    signed_binaries = manifest.get("windows_binaries", {})
    require(set(signed_binaries) == set(BINARIES), "signed Windows binary inventory mismatch")
    for name, metadata in signed_binaries.items():
        require(metadata.get("sha256") == digest(assets / name) and metadata.get("size") == (assets / name).stat().st_size,
            "signed Windows binary mismatch: " + name)
    component = manifest["components"]["gsc"]
    require(component.get("version") == VERSION and component.get("kind") == "gsc" and component.get("targets") == ["host"], "GSC metadata mismatch")
    require(component.get("file") == BINARIES[0] and component.get("url") == f"https://github.com/{REPOSITORY}/releases/download/{tag}/{BINARIES[0]}", "GSC artifact URL mismatch")
    require(component.get("sha256") == digest(assets / BINARIES[0]) and component.get("size") == (assets / BINARIES[0]).stat().st_size, "signed GSC artifact mismatch")
    require((assets / "SOURCE-COMMIT.txt").read_text(encoding="ascii").strip() == commit, "source revision mismatch")
    provenance = load(assets / "GSC-PERSONAL-PROVENANCE.json")
    require(provenance.get("source_commit") == commit and provenance.get("ci_run_id") == manifest.get("ci_run_id") and
        type(provenance.get("ci_run_id")) is int and provenance["ci_run_id"] > 0, "CI provenance mismatch")
    require(provenance.get("formal_day12_closure") is False and provenance.get("windows_authenticode_signed") is False, "incorrect verification claim")
    require(provenance.get("acceptance_sha256") == digest(assets / LEDGER), "acceptance provenance mismatch")
    validate_ledger(load(assets / LEDGER))
    require((assets / LEDGER).read_text(encoding="utf-8") == (root / "deploy" / LEDGER).read_text(encoding="utf-8"), "acceptance ledger differs from source")
    require((assets / NOTES).read_text(encoding="utf-8") == (root / "docs/releases/GSC-5.0.0.md").read_text(encoding="utf-8"), "release notes differ from source")
    if release_metadata:
        release = load(release_metadata)
        require(release.get("draft") is True and release.get("prerelease") is False and release.get("tag_name") == tag and release.get("target_commitish") == commit, "not the reviewed exact-commit Stable draft")
        require(release.get("body", "").replace("\r\n", "\n").strip() == (assets / NOTES).read_text(encoding="utf-8").strip(), "GitHub release notes differ from reviewed source")
        remote = {a["name"]: a for a in release.get("assets", [])}
        require(set(remote) == EXPECTED_FILES, "GitHub asset inventory mismatch")
        for name, asset in remote.items():
            require(asset.get("size") == (assets / name).stat().st_size and asset.get("digest") == "sha256:" + digest(assets / name), "GitHub uploaded asset mismatch: " + name)
    return provenance["ci_run_id"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("prepare", "seal", "verify", "resolve-draft"))
    parser.add_argument("--assets", type=Path)
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--tag", default=TAG)
    parser.add_argument("--commit")
    parser.add_argument("--run-id", type=int)
    parser.add_argument("--release-metadata", type=Path)
    args = parser.parse_args()
    if args.mode == "resolve-draft":
        require(args.release_metadata is not None, "paginated release metadata required")
        print(resolve_draft_id(load(args.release_metadata), args.tag, args.commit))
        return
    require(args.assets is not None, "release assets directory required")
    if args.mode == "prepare":
        prepare(args.assets, args.root, args.tag, args.commit, args.run_id)
    elif args.mode == "seal":
        seal(args.assets)
    else:
        run_id = verify(args.assets, args.root, args.tag, args.commit, args.release_metadata)
        print(f"Verified personal Stable payload; exact CI run {run_id}")


if __name__ == "__main__":
    main()
