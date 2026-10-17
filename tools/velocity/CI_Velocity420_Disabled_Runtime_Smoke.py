#!/usr/bin/env python3
"""CI-ONLY disposable Velocity 4.2.0 plugin-load smoke.

Never run this script on the user's server PC. It executes an official,
SHA-256-pinned Velocity proxy only inside a throwaway GitHub runner directory,
terminates its own ephemeral child, then destroys the temporary directory.
No GSC APIs, credentials, live Scheduled Tasks, ports, worlds or backups used.
"""
from __future__ import annotations

import hashlib
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

EXPECTED_SHA = "35a5596a5468a035d8a32c8de5ebb0dc6b8d8f0cc3ff5169d514aca762af8aa8"
EXPECTED_SIZE = 42_163_652
OFFICIAL_URL = (
    "https://fill-data.papermc.io/v1/objects/"
    + EXPECTED_SHA
    + "/velocity-4.2.0-30.jar"
)
EXPECTED_LOG = "Geumyi Velocity Bridge development shell loaded"


def check_binary(binary: bytes) -> None:
    if len(binary) != EXPECTED_SIZE or hashlib.sha256(binary).hexdigest() != EXPECTED_SHA:
        raise RuntimeError("Upstream Velocity 4.2.0 build #30 SHA/size mismatch")


def run(plugin_jar: pathlib.Path) -> None:
    if not plugin_jar.is_file() or plugin_jar.suffix != ".jar":
        raise RuntimeError("Expected exactly one CI-built plugin JAR")
    req = urllib.request.Request(OFFICIAL_URL, headers={"User-Agent": "Geumyi-GSC452-Offline-CI/1.0"})
    with urllib.request.urlopen(req, timeout=45) as response:
        content = response.read(EXPECTED_SIZE + 1)
    check_binary(content)

    with tempfile.TemporaryDirectory(prefix="gsc452-disposable-velocity-") as tmp:
        root = pathlib.Path(tmp)
        proxy_jar = root / "velocity-4.2.0-30.jar"
        proxy_jar.write_bytes(content)
        (root / "plugins").mkdir()
        shutil.copyfile(plugin_jar, root / "plugins" / "geumyi-velocity-bridge-disabled.jar")
        log = root / "smoke.log"
        proc = None
        try:
            with log.open("wb") as sink:
                proc = subprocess.Popen(
                    ["java", "-jar", str(proxy_jar)],
                    cwd=root,
                    stdin=subprocess.DEVNULL,
                    stdout=sink,
                    stderr=subprocess.STDOUT,
                )
                deadline = time.monotonic() + 30
                loaded = False
                while time.monotonic() < deadline:
                    if log.exists() and EXPECTED_LOG in log.read_text(encoding="utf-8", errors="replace"):
                        loaded = True
                        break
                    if proc.poll() is not None:
                        break
                    time.sleep(0.5)
                if not loaded:
                    raise RuntimeError("Disabled bridge did not report initialization in disposable Velocity 4.2.0 runtime")
        finally:
            if proc is not None and proc.poll() is None:
                proc.terminate()  # Only the CI-created disposable subprocess.
                try:
                    proc.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    proc.kill()  # Only the CI-created disposable subprocess.
                    proc.wait(timeout=8)
        print(
            "CI-only Velocity 4.2.0 #30 plugin-load smoke PASS: "
            "disabled shell initialized; no shutdown, control listener, "
            "production install, or live player E2E exercised."
        )


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: CI_Velocity420_Disabled_Runtime_Smoke.py <CI-built-plugin.jar>")
    run(pathlib.Path(sys.argv[1]))
