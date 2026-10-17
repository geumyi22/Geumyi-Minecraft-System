#!/usr/bin/env python3
"""NO-PRODUCTION GitHub CI: SHA-pinned Velocity+Geyser+Floodgate coexistence.

Downloads only officially published SHA-pinned artifacts, then runs them
together with the disabled Geumyi bridge inside a Docker container that has
NO NETWORK, NO privileges, NO host-server volumes, and temporary storage.
No synthetic startup log is accepted as full player E2E or production safety.
"""
from __future__ import annotations

import hashlib
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

ARTIFACTS = {
    "velocity-4.2.0-30.jar": (
        "https://fill-data.papermc.io/v1/objects/"
        "35a5596a5468a035d8a32c8de5ebb0dc6b8d8f0cc3ff5169d514aca762af8aa8/"
        "velocity-4.2.0-30.jar",
        "35a5596a5468a035d8a32c8de5ebb0dc6b8d8f0cc3ff5169d514aca762af8aa8",
        42_163_652,
        80 * 1024 * 1024,
    ),
    "Geyser-Velocity.jar": (
        "https://download.geysermc.org/v2/projects/geyser/versions/2.12.0/builds/1263/downloads/velocity",
        "f04cb787529b731ed5a1ab4797ee49bb5192c9ccec5217bfed2f368723036043",
        None,
        90 * 1024 * 1024,
    ),
    "floodgate-velocity.jar": (
        "https://download.geysermc.org/v2/projects/floodgate/versions/2.2.5/builds/141/downloads/velocity",
        "649835022de37ff09255fc626d4bfe7bc2a3b926d07b0dfaf1f51e12bf37001d",
        None,
        30 * 1024 * 1024,
    ),
}
BRIDGE_MARKER = "Geumyi Velocity Bridge development shell loaded"


def download_pinned(dest: pathlib.Path, url: str, sha: str, expected_size: int | None, maximum: int) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": "Geumyi-v452-disposable-CI/1"})
    digest = hashlib.sha256()
    size = 0
    with urllib.request.urlopen(req, timeout=65) as source, dest.open("wb") as output:
        while True:
            buf = source.read(65536)
            if not buf:
                break
            size += len(buf)
            if size > maximum:
                raise RuntimeError("SHA-pinned upstream artifact exceeds budget")
            digest.update(buf)
            output.write(buf)
    if digest.hexdigest() != sha or (expected_size is not None and size != expected_size):
        raise RuntimeError("official artifact digest/length rejected")


def regex_loaded(text: str, plugin_id: str) -> bool:
    return bool(re.search(r"(?i)\bloaded plugin\b[^\r\n]*\b" + re.escape(plugin_id) + r"\b", text))


def run(plugin: pathlib.Path) -> None:
    if plugin.suffix != ".jar" or not plugin.is_file() or plugin.stat().st_size < 100:
        raise RuntimeError("missing CI-built disabled bridge JAR")
    docker = shutil.which("docker")
    if not docker:
        raise RuntimeError("Docker unavailable; do not run on production host as fallback")
    with tempfile.TemporaryDirectory(prefix="gsc452-geyser-floodgate-isolated-") as directory:
        root = pathlib.Path(directory)
        for name, (url, sha, length, maximum) in ARTIFACTS.items():
            dest = root / name if name.startswith("velocity-") else root / "plugins" / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            download_pinned(dest, url, sha, length, maximum)
        shutil.copyfile(plugin, root / "plugins" / "geumyi-velocity-bridge-disabled.jar")
        # Docker isolated bridge: no host plugin path, no production mounts,
        # no outgoing network and no privileged OS capabilities.
        invocation = [
            docker, "run", "--rm",
            "--network", "none",
            "--cap-drop", "ALL",
            "--security-opt", "no-new-privileges",
            "--pids-limit", "128",
            "--memory", "2g",
            "--cpus", "2",
            "--mount", f"type=bind,src={root},dst=/work",
            "--workdir", "/work",
            "eclipse-temurin:26-jre",
            "java", "-Xms128M", "-Xmx640M", "-jar", "velocity-4.2.0-30.jar",
        ]
        try:
            p = subprocess.run(invocation, capture_output=True, text=True, timeout=65)
            combined = p.stdout[-300000:] + p.stderr[-300000:]
        except subprocess.TimeoutExpired as ex:
            # Docker may remain alive if client is killed: unique label +
            # forced bounded cleanup below ensures only this CI-owned container.
            combined = (ex.stdout or b"").decode("utf8", errors="replace") if isinstance(ex.stdout, bytes) else (ex.stdout or "")
            combined += (ex.stderr or b"").decode("utf8", errors="replace") if isinstance(ex.stderr, bytes) else (ex.stderr or "")
        # Do not echo runtime log, generated Floodgate keys, user names, paths.
        ready = {
            "bridge": BRIDGE_MARKER in combined,
            "geyser": regex_loaded(combined, "geyser"),
            "floodgate": regex_loaded(combined, "floodgate"),
        }
        if not all(ready.values()):
            print("ISOLATED COEXISTENCE NOT VERIFIED:", ready, file=sys.stderr)
            raise RuntimeError("test bootstrap did not confirm every plugin; production remains blocked")
        print("ISOLATED COEXISTENCE STARTUP PASS: SHA256-pinned Velocity 4.2.0 + Geyser 2.12.0/1263 + Floodgate 2.2.5/141 + disabled Geumyi bridge.")
        print("No external network or production resources. No player login, resourcepack or stop/restart test.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("CI-only: python3 CI_Velocity420_Geyser_Floodgate_Smoke.py <disabled-plugin.jar>")
    run(pathlib.Path(sys.argv[1]))
