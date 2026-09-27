#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
rm -rf "$ROOT/build" && mkdir -p "$ROOT/build/classes"
javac --release 21 -encoding UTF-8 -d "$ROOT/build/classes" $(find "$ROOT/src" -name '*.java' | sort)
cat > "$ROOT/build/MANIFEST.MF" <<'M'
Manifest-Version: 1.0
Main-Class: kr.geumyi.statusagent.GeumyiStatusAgent
Implementation-Title: GeumyiStatusAgent
Implementation-Version: 0.5.4
M
jar --create --file "$ROOT/GeumyiStatusAgent-0.5.4.jar" --manifest "$ROOT/build/MANIFEST.MF" --date=2026-09-24T00:00:00Z -C "$ROOT/build/classes" .
sha256sum "$ROOT/GeumyiStatusAgent-0.5.4.jar"
