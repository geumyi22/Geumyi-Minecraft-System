#!/usr/bin/env python3
"""CI-ONLY localhost IPC contract with NO Velocity/process control.

Exercises Go/Java Phase C canonical HMAC message fields on ephemeral
127.0.0.1 TCP transport with read-only status response. No production keys,
no privileged commands, no task access, no plugin integration, no persistent
network listener, no filesystem output, no stop/start/restart handler.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import socket
import socketserver
import struct
import threading
import time

MAX_FRAME = 4096
SAFE_REPLY = {"read_only": True, "safe_to_execute": False, "status": "unverified_fixture_only"}
KEY = os.urandom(32)
TARGET = "wild"
GEN = "parent-100-child-101"


def canon(env: dict) -> bytes:
    def u(n: int) -> bytes:
        return struct.pack(">Q", n)
    def t(s: str) -> bytes:
        v = s.encode("utf-8")
        return u(len(v)) + v
    return (u(env["version"]) + t(env["target"]) + t(env["operation"])
            + t(env["generation"]) + t(env["nonce"])
            + u(env["issued_unix"]) + u(env["expires_unix"]))


def signed(target: str, operation: str, now: int) -> dict:
    from base64 import urlsafe_b64encode
    env = dict(version=1, target=target, operation=operation,
               generation=GEN, nonce=urlsafe_b64encode(os.urandom(24)).decode().rstrip("="),
               issued_unix=now, expires_unix=now + 20)
    env["mac"] = hmac.new(KEY, canon(env), hashlib.sha256).hexdigest()
    return env


def verify(env: dict, now: int, seen: set[str]) -> bool:
    try:
        if set(env) != {
            "version", "target", "operation", "generation", "nonce",
            "issued_unix", "expires_unix", "mac"
        }:
            return False
        if env["version"] != 1 or env["target"] != TARGET or env["operation"] != "status":
            return False
        if env["generation"] != GEN or not isinstance(env["nonce"], str) or len(env["nonce"]) != 32:
            return False
        if type(env["issued_unix"]) is not int or type(env["expires_unix"]) is not int:
            return False
        if env["issued_unix"] > now + 5 or env["issued_unix"] < now - 30:
            return False
        if env["expires_unix"] <= now or env["expires_unix"] > env["issued_unix"] + 20:
            return False
        mac = bytes.fromhex(env["mac"])
        if len(mac) != 32 or not hmac.compare_digest(
            mac, hmac.new(KEY, canon(env), hashlib.sha256).digest()
        ):
            return False
        nonce = env["nonce"]
        if nonce in seen or len(seen) >= 128:
            return False
        seen.add(nonce)
        return True
    except (ValueError, TypeError, KeyError, UnicodeEncodeError, struct.error):
        return False


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        # Strict one-frame limit, no unauthenticated command data returned.
        frame = self.rfile.readline(MAX_FRAME + 1)
        if not frame.endswith(b"\n") or len(frame) > MAX_FRAME:
            self.wfile.write(b'{"read_only":true,"safe_to_execute":false,"error":"invalid_frame"}\n')
            return
        try:
            body = json.loads(frame)
            if type(body) is not dict:
                raise ValueError("request must be object")
        except (ValueError, UnicodeError):
            body = {}
        with self.server.guard:
            valid = verify(body, int(time.time()), self.server.seen)
        response = SAFE_REPLY if valid else {
            "read_only": True, "safe_to_execute": False, "error": "rejected"
        }
        self.wfile.write(json.dumps(response, separators=(",", ":")).encode() + b"\n")


class FixtureServer(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = False
    def __init__(self):
        super().__init__(("127.0.0.1", 0), Handler, bind_and_activate=True)
        self.guard = threading.Lock()
        self.seen = set()


def exchange(server: FixtureServer, envelope: dict) -> dict:
    data = json.dumps(envelope, separators=(",", ":")).encode() + b"\n"
    assert len(data) <= MAX_FRAME
    with socket.create_connection(("127.0.0.1", server.server_address[1]), timeout=3) as s:
        s.sendall(data)
        s.settimeout(3)
        return json.loads(s.makefile("rb").readline(MAX_FRAME))


def main():
    # Cross-language binding: the same fixed wire vector is covered by
    # Java PR #58 and Go PR #57. Never use this known key in production.
    vector = dict(
        version=1, target="wild", operation="status",
        generation="parent-100-child-101",
        nonce="A" * 32, issued_unix=1792267200, expires_unix=1792267220
    )
    assert len(canon(vector)) == 118
    assert hmac.new(bytes(range(32)), canon(vector), hashlib.sha256).hexdigest() == (
        "1488217fd43660a2e0810dc60caf3f93d89d4ba4bb9b4920967f42d31fff70c5"
    ), "Go/Java/Python wire canonicalization drift"

    with FixtureServer() as server:
        assert server.server_address[0] == "127.0.0.1" and server.server_address[1] != 0
        worker = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True)
        worker.start()
        try:
            now = int(time.time())
            sample = signed(TARGET, "status", now)
            assert exchange(server, sample) == SAFE_REPLY, "signed status denied"
            assert exchange(server, sample).get("error") == "rejected", "replay accepted"
            assert exchange(server, signed("other", "status", now)).get("error") == "rejected", "cross proxy accepted"
            for command in ("prepare_shutdown", "confirm_shutdown", "stop", "restart", "start", "kill"):
                msg = signed(TARGET, command, now)
                assert exchange(server, msg).get("error") == "rejected", command + " accepted"
            expired = signed(TARGET, "status", now - 31)
            assert exchange(server, expired).get("error") == "rejected", "expired accepted"
            forged = signed(TARGET, "status", now)
            forged["mac"] = "00" * 32
            assert exchange(server, forged).get("error") == "rejected", "forged MAC accepted"
            altered = signed(TARGET, "status", now)
            altered["generation"] = "parent-900-child-901"
            assert exchange(server, altered).get("error") == "rejected", "generation tamper accepted"
            print("CI LOCALHOST READ-ONLY IPC CONTRACT PASS: signed status only; replay/forgery/cross-proxy/stale and all lifecycle verbs denied.")
        finally:
            server.shutdown()
            worker.join(timeout=5)


if __name__ == "__main__":
    main()
