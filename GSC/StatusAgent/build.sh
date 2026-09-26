#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
rm -rf "$ROOT/build" && mkdir -p "$ROOT/build/old" "$ROOT/build/classes" "$ROOT/build/jarroot"
(cd "$ROOT/build/old" && jar xf "$ROOT/base/GeumyiStatusAgent-0.4.5.jar")
rm -f "$ROOT/build/old/kr/geumyi/statusagent/GeumyiStatusAgent.class" "$ROOT/build/old/kr/geumyi/statusagent/DiscordBot.class" "$ROOT/build/old/kr/geumyi/statusagent/DiscordBot\$Listener.class"
javac --release 21 -encoding UTF-8 -cp "$ROOT/build/old" -d "$ROOT/build/classes" $(find "$ROOT/src" -name '*.java')
cp -a "$ROOT/build/old/kr" "$ROOT/build/jarroot/"
cp -a "$ROOT/build/classes/kr" "$ROOT/build/jarroot/"
cat > "$ROOT/build/MANIFEST.MF" <<'M'
Manifest-Version: 1.0
Main-Class: kr.geumyi.statusagent.GeumyiStatusAgent
Implementation-Title: GeumyiStatusAgent
Implementation-Version: 0.5.4
M
jar --create --file "$ROOT/GeumyiStatusAgent-0.5.4.jar" --manifest "$ROOT/build/MANIFEST.MF" --date=2026-09-24T00:00:00Z -C "$ROOT/build/jarroot" .
sha256sum "$ROOT/GeumyiStatusAgent-0.5.4.jar"
