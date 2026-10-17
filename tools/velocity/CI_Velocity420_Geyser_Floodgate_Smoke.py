#!/usr/bin/env python3
"""NO-PRODUCTION GitHub CI: SHA-pinned Velocity+Geyser+Floodgate coexistence.

Downloads only officially published SHA-pinned artifacts, then runs them
together with the disabled Geumyi bridge inside a Docker container on a unique --internal bridge with NO
external network route, NO published ports, NO privileges, NO host-server
volumes and temporary storage. The bridge is deleted after every run.
No synthetic startup log is accepted as full player E2E or production safety.
"""
from __future__ import annotations

import hashlib
import os
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

    "floodgate-velocity.jar": (
        "https://download.geysermc.org/v2/projects/floodgate/versions/2.2.5/builds/141/downloads/velocity",
        "649835022de37ff09255fc626d4bfe7bc2a3b926d07b0dfaf1f51e12bf37001d",
        None,
        30 * 1024 * 1024,
    ),
}
# The production-match profile reproduces the exact *published JAR builds*
# identified from the operator's sanitized SHA-256 report. The newer profile
# is a separately labelled reference, NOT the deployed server's version.
GEYSER_PROFILES = {
    "operator": (
        "2.11.3", "1251",
        "dd963f2123704b89c47d3775b908b189b8174b1650008c51d37b1026d6dd928e",
        48_674_589,
    ),
    "reference": (
        "2.12.0", "1263",
        "f04cb787529b731ed5a1ab4797ee49bb5192c9ccec5217bfed2f368723036043",
        None,
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


def test_only_transport_hint(root: pathlib.Path) -> str:
    # Private disposable configuration generated during THIS CI run only.
    # Return a fixed enum, never YAML content, credentials or file paths.
    config = root / "plugins" / "Geyser-Velocity" / "config.yml"
    if not config.is_file() or config.stat().st_size > 262144:
        return "config_missing_or_oversized"
    content = config.read_text(encoding="utf8", errors="replace")
    matches = re.findall(
        r"(?im)^\s{2,6}transport:\s*(nethernet|raknet|both)\s*(?:#.*)?$",
        content,
    )
    return matches[0].lower() if len(matches) == 1 else "transport_not_attested"


def test_only_socket_present(docker: str, container: str, udp_port: int) -> bool:
    # Linux /proc inspection INSIDE the isolated Docker container. No PID,
    # raw socket address, config, path or content is emitted to CI logs.
    result = subprocess.run(
        [docker, "exec", container, "cat", "/proc/net/udp", "/proc/net/udp6"],
        capture_output=True, text=True, timeout=7,
    )
    if result.returncode != 0:
        return False
    token = f":{udp_port:04X}"
    return any(
        token in line.split()[1].upper()
        for line in result.stdout.splitlines()
        if len(line.split()) >= 2 and line.split()[0].endswith(":")
    )


def test_only_generated_bedrock_config(root: pathlib.Path) -> dict[str, object]:
    # Only parse the CI-created plugin config; never use a real server config.
    # Emit permitted fixed numeric/boolean fields, not text or file contents.
    file = root / "plugins" / "Geyser-Velocity" / "config.yml"
    answer = {"found": False, "port": None, "raknet_port": None,
              "clone_remote_port": None}
    if not file.is_file() or file.stat().st_size > 262144:
        return answer
    answer["found"] = True
    content = file.read_text(encoding="utf8", errors="replace")
    # Only YAML scalars in the CI-generated "bedrock:" section.
    block = re.search(r"(?ms)^bedrock:\s*\n((?:^[ \t]+[^\n]*\n|^\s*\n)*)", content)
    if not block:
        return answer
    for key, label in (
        ("port", "port"),
        ("raknet-port", "raknet_port"),
        ("clone-remote-port", "clone_remote_port"),
    ):
        pattern = r"(?m)^\s{2,8}" + re.escape(key) + r":\s*([^\r\n#]+)"
        found = re.search(pattern, block.group(1))
        if not found:
            continue
        raw = found.group(1).strip()
        if label == "clone_remote_port":
            if raw in ("true", "false"):
                answer[label] = raw == "true"
        elif raw.isdecimal():
            number = int(raw)
            if 0 <= number <= 65535:
                answer[label] = number
    return answer


def test_only_udp_ports(docker: str, container: str) -> list[int]:
    # Only numeric UDP port identifiers in the disposable namespace,
    # never local/remote addresses, PIDs, credentials or raw proc text.
    result = subprocess.run(
        [docker, "exec", container, "cat", "/proc/net/udp", "/proc/net/udp6"],
        capture_output=True, text=True, timeout=7,
    )
    if result.returncode != 0:
        return []
    ports = set()
    for line in result.stdout.splitlines():
        cells = line.split()
        if len(cells) < 2 or not cells[0].endswith(":"):
            continue
        last = cells[1].rsplit(":", 1)
        if len(last) != 2:
            continue
        try:
            port = int(last[1], 16)
        except ValueError:
            continue
        if 0 < port < 65536:
            ports.add(port)
    return sorted(ports)[:16]


def prepare_disposable_offline_raknet_config(docker: str, root: pathlib.Path) -> None:
    """Generate Geyser defaults, then alter ONLY CI's disposable config.

    Geyser.initialize() requests Mojang's Xbox auth public key BEFORE the
    RakNet listener starts when validate-bedrock-login=true. This completely
    network-isolated test only checks the unauthenticated status-ping protocol,
    NEVER player login or auth, and does not publish any container ports.
    Do not call this helper with real-server data or any operator file.
    """
    conf = root / "plugins" / "Geyser-Velocity" / "config.yml"
    name = "gsc452-config-" + os.urandom(8).hex()
    invocation = [
        docker, "run", "-d", "--rm", "--name", name,
        "--network", "none",
        "--user", f"{os.getuid()}:{os.getgid()}",
        "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges",
        "--pids-limit", "128",
        "--memory", "2g",
        "--cpus", "2",
        "--mount", f"type=bind,src={root},dst=/work",
        "--workdir", "/work",
        "eclipse-temurin:26-jre",
        "java", "-DgeyserTransport=raknet", "-Xms128M", "-Xmx640M",
        "-jar", "velocity-4.2.0-30.jar",
    ]
    try:
        started = subprocess.run(
            invocation, capture_output=True, text=True, timeout=25,
        )
        if started.returncode != 0:
            raise RuntimeError("CI-only default-config generation container failed")
        deadline = time.monotonic() + 25
        while time.monotonic() < deadline:
            if conf.is_file() and 0 < conf.stat().st_size <= 262144:
                generated = conf.read_text(encoding="utf8", errors="replace")
                if "validate-bedrock-login:" in generated:
                    break
            time.sleep(0.4)
        else:
            raise RuntimeError("CI-only default Geyser config did not appear")
    finally:
        subprocess.run(
            [docker, "rm", "-f", name],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=15, check=False,
        )
    # Strictly require exactly ONE default-true authentication setting.
    # The only permitted replacement is in this brand-new temporary folder
    # with no public ports/external network. No general config merge or
    # world/player/production configuration changes are supported.
    pattern = re.compile(r"(?m)^([ \t]+validate-bedrock-login:[ \t]*)true([ \t]*(?:#.*)?)$")
    generated = conf.read_text(encoding="utf8")
    if len(pattern.findall(generated)) != 1:
        raise RuntimeError("CI-only Geyser auth gate not uniquely identified; no override applied")
    modified = pattern.sub(r"\g<1>false\g<2>", generated, count=1)
    conf.write_text(modified, encoding="utf8")
    print("CI_OFFLINE_RAKNET_ONLY_AUTH_DISABLED=TRUE (no players, no external network, test-generated config only)")


def run(plugin: pathlib.Path, profile: str) -> None:
    if profile not in GEYSER_PROFILES:
        raise ValueError("unknown pinned Geyser compatibility profile")
    if plugin.suffix != ".jar" or not plugin.is_file() or plugin.stat().st_size < 100:
        raise RuntimeError("missing CI-built disabled bridge JAR")
    docker = shutil.which("docker")
    if not docker:
        raise RuntimeError("Docker unavailable; do not run on production host as fallback")
    with tempfile.TemporaryDirectory(prefix="gsc452-geyser-floodgate-isolated-") as directory:
        root = pathlib.Path(directory)
        version, build, geyser_sha, geyser_length = GEYSER_PROFILES[profile]
        artifacts = {
            **ARTIFACTS,
            "Geyser-Velocity.jar": (
                "https://download.geysermc.org/v2/projects/geyser/versions/"
                + version + "/builds/" + build + "/downloads/velocity",
                geyser_sha, geyser_length, 90 * 1024 * 1024,
            ),
        }
        for name, (url, sha, length, maximum) in artifacts.items():
            dest = root / name if name.startswith("velocity-") else root / "plugins" / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            download_pinned(dest, url, sha, length, maximum)
        shutil.copyfile(plugin, root / "plugins" / "geumyi-velocity-bridge-disabled.jar")
        # Compile a CI-only fixed-loopback protocol probe to Java 26 bytecode.
        # It runs inside the SAME network-disabled test namespace as Velocity.
        # Isolated preflight generates a default config without ever exposing
        # the test JVM to external network/host ports. Authentication is
        # strictly disabled for local, unauthenticated PONG protocol only.
        prepare_disposable_offline_raknet_config(docker, root)
        probe_dir = root / "probes"
        probe_dir.mkdir()
        subprocess.run(
            ["javac", "-d", str(probe_dir),
             "tools/velocity/CI_Velocity_Loopback_Probe.java"],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20,
        )
        # Docker isolated bridge: no host plugin path, no production mounts,
        # no outgoing network and no privileged OS capabilities.
        # Name is randomized and scoped to this runner; only this container
        # can be removed in finally, including if Docker client times out.
        container_name = "gsc452-coexistence-" + os.urandom(8).hex()
        network_name = "gsc452-internal-" + os.urandom(8).hex()
        # A Docker 'none' namespace may not have usable 127.0.0.1. For
        # application-layer loopback packet tests, use a UNIQUE Docker bridge
        # with --internal (no external routing) and NO published host ports.
        created = subprocess.run(
            [docker, "network", "create", "--driver", "bridge",
             "--internal", "--label", "geumyi.gsc452=ci-test", network_name],
            capture_output=True, text=True, timeout=15,
        )
        if created.returncode != 0:
            raise RuntimeError("cannot create disposable internal-only CI network")
        invocation = [
            docker, "run", "-d", "--rm", "--name", container_name,
            "--network", network_name,
            # Docker bind mount preserves host runner UID/GID. The temporary
            # directory is 0700: matching the invoking runner avoids both
            # world-readable credentials and Java "unable to access jarfile".
            "--user", f"{os.getuid()}:{os.getgid()}",
            "--cap-drop", "ALL",
            "--security-opt", "no-new-privileges",
            "--pids-limit", "128",
            "--memory", "2g",
            "--cpus", "2",
            "--mount", f"type=bind,src={root},dst=/work",
            "--workdir", "/work",
            "eclipse-temurin:26-jre",
            # Official Geyser test-only JVM override: enable RakNet rather
            # than its default NetherNet transport. The user's GSC screenshot
            # separately observed RakNet PONGs, but no user config is imported.
            "java", "-DgeyserTransport=raknet", "-Xms128M", "-Xmx640M",
            "-jar", "velocity-4.2.0-30.jar",
        ]
        combined = ""
        ready = {"bridge": False, "geyser": False, "floodgate": False}
        protocol = {"java_status": False, "raknet_pong": False}
        docker_exit = "not_started"
        try:
            spawned = subprocess.run(
                invocation, capture_output=True, text=True, timeout=25,
            )
            docker_exit = str(spawned.returncode)
            if spawned.returncode != 0:
                raise RuntimeError("disposable Docker runtime failed to start")
            # Docker run -d returns immediately; only the CI-owned child JVM
            # is visible, in a private --network none namespace.
            deadline = time.monotonic() + 40
            while time.monotonic() < deadline:
                capture = subprocess.run(
                    [docker, "logs", "--tail", "600", container_name],
                    capture_output=True, text=True, timeout=10,
                )
                combined = (capture.stdout + capture.stderr)[-300000:]
                ready = {
                    "bridge": BRIDGE_MARKER in combined,
                    "geyser": regex_loaded(combined, "geyser"),
                    "floodgate": regex_loaded(combined, "floodgate"),
                }
                if all(ready.values()):
                    # "Loaded plugin" refers to Velocity's metadata discovery,
                    # NOT Geyser's completed bootstrap. In a network-isolated
                    # JVM, dependency checks and asynchronous initialization
                    # may take substantially longer than 1.5 seconds.
                    # Require the UDP socket before proceeding to RakNet PONG.
                    if test_only_socket_present(docker, container_name, 19132):
                        time.sleep(0.5)
                        break
                inspect = subprocess.run(
                    [docker, "inspect", "--format", "{{.State.Running}}", container_name],
                    capture_output=True, text=True, timeout=6,
                )
                if inspect.returncode != 0 or inspect.stdout.strip() != "true":
                    break
                time.sleep(0.75)
            if not all(ready.values()):
                classes = sorted(set(re.findall(
                    r"\b[A-Z][A-Za-z0-9]*(?:Exception|Error)\b", combined
                )))[:10]
                print("ISOLATED COEXISTENCE UNVERIFIED:", ready,
                      "docker_exit:", docker_exit,
                      "log_bytes:", len(combined),
                      "error_classes:", classes, file=sys.stderr)
                raise RuntimeError("disposable plugins did not all initialize")

            running = subprocess.run(
                [docker, "inspect", "--format", "{{.State.Running}}", container_name],
                capture_output=True, text=True, timeout=6,
            )
            if running.returncode != 0 or running.stdout.strip() != "true":
                diagnostics = {
                    "server_stopped_after_plugin_init": True,
                    "configuration_error": bool(re.search(
                        r"(?i)(invalid config|configuration error|failed to load config|configuration could not)", combined)),
                    "binding_error": bool(re.search(
                        r"(?i)(failed to bind|could not bind|address already in use)", combined)),
                    "missing_secret_file": bool(re.search(
                        r"(?i)(forwarding.secret|secret file)", combined)),
                    "startup_exception_present": bool(re.search(r"(?i)(exception|error)", combined)),
                }
                print("DISPOSABLE PROXY EXITED BEFORE NETWORK PROBE:", diagnostics, file=sys.stderr)
                raise RuntimeError("proxy initialization marker does not prove active JVM")

            # Execute probe from the SAME isolated Java container. No port is
            # published and no real user/backend address is accepted.
            attempt = subprocess.run(
                [docker, "exec", "--user", f"{os.getuid()}:{os.getgid()}",
                 "--workdir", "/work", container_name,
                 "java", "-cp", "/work/probes", "CI_Velocity_Loopback_Probe"],
                capture_output=True, text=True, timeout=20,
            )
            protocol = {
                "java_status": "DISPOSABLE_JAVA_STATUS_RESPONSE=PASS" in attempt.stdout,
                "raknet_pong": "DISPOSABLE_BEDROCK_RAKNET_PONG=PASS" in attempt.stdout,
            }
            if attempt.returncode != 0 or not all(protocol.values()):
                # Distinguish an alive-but-unbound proxy from a container that
                # exited during the probe. Never print raw JVM/plugin logs.
                after = subprocess.run(
                    [docker, "inspect", "--format", "{{.State.Running}}", container_name],
                    capture_output=True, text=True, timeout=6,
                )
                still_running = after.returncode == 0 and after.stdout.strip() == "true"
                # Only whitelisted exception-class identifiers, not raw logs,
                # untrusted exception text or generated plugin configuration.
                classes = re.findall(
                    r"DISPOSABLE_(?:JAVA|RAKNET)_ERROR_CLASS=[A-Za-z]{3,48}",
                    attempt.stdout,
                )
                print("DISPOSABLE ENDPOINTS UNVERIFIED:", protocol,
                      "probe_exit:", attempt.returncode,
                      "jvm_still_running:", still_running,
                      "ci_generated_geyser_transport", test_only_transport_hint(root),
                      "udp_19132_bound_in_container", test_only_socket_present(
                          docker, container_name, 19132
                      ) if still_running else False,
                      "udp_19133_bound_in_container", test_only_socket_present(
                          docker, container_name, 19133
                      ) if still_running else False,
                      "udp_25565_bound_in_container", test_only_socket_present(
                          docker, container_name, 25565
                      ) if still_running else False,
                      "geyser_startup_error_seen", bool(re.search(
                          r"(?i)(geyser[^\r\n]{0,100}(failed|error|cannot|unable)|"
                          r"(failed|error|cannot|unable)[^\r\n]{0,100}geyser)", combined
                      )),
                      "network_or_fetch_error_seen", bool(re.search(
                          r"(?i)(network is unreachable|unknownhostexception|"
                          r"failed to download|unable to download|could not fetch)", combined
                      )),
                      "binding_error_seen", bool(re.search(
                          r"(?i)(failed to bind|address already in use|"
                          r"could not bind|unable to bind)", combined
                      )),
                      "ci_only_udp_bound_port_numbers",
                      test_only_udp_ports(docker, container_name) if still_running else [],
                      "geyser_transport_property_processed",
                      "Transport set from system property: raknet" in combined,
                      "geyser_ci_config", test_only_generated_bedrock_config(root),
                      "classes:", classes[:2], file=sys.stderr)
                raise RuntimeError("loopback Java status/RakNet response test failed")
        finally:
            # Only this script's uniquely named disposable CI container.
            subprocess.run(
                [docker, "rm", "-f", container_name],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                timeout=15, check=False,
            )
            subprocess.run(
                [docker, "network", "rm", network_name],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                timeout=15, check=False,
            )
        print(
            "ISOLATED COEXISTENCE STARTUP PASS: profile=" + profile
            + ", SHA256-pinned Velocity 4.2.0/30 + Geyser " + version + "/" + build
            + " + Floodgate 2.2.5/141 + disabled Geumyi bridge."
        )
        print("ISOLATED LOOPBACK ENDPOINT PROBES PASS: Java status 25565 and RakNet unconnected PONG 19132, no login.")
        print("Internal-only disposable CI network, no published host ports or production resources. No player login/resourcepack/stop-restart test.")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[2] not in GEYSER_PROFILES:
        raise SystemExit(
            "CI-only: python3 CI_Velocity420_Geyser_Floodgate_Smoke.py "
            "<disabled-plugin.jar> <operator|reference>"
        )
    run(pathlib.Path(sys.argv[1]), sys.argv[2])
