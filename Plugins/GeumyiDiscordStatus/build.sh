#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
rm -rf "$ROOT/build"
mkdir -p "$ROOT/build/stubclasses" "$ROOT/build/classes"
find "$ROOT/stubs" -name '*.java' -print0 | xargs -0 javac --release 21 -encoding UTF-8 -d "$ROOT/build/stubclasses"
find "$ROOT/src/main/java" -name '*.java' -print0 | xargs -0 javac --release 21 -encoding UTF-8 -cp "$ROOT/build/stubclasses" -d "$ROOT/build/classes"
cp -a "$ROOT/src/main/resources/." "$ROOT/build/classes/"
OUT="$ROOT/GeumyiDiscordStatus-1.1.1-SpigotPaper26.3.jar"
rm -f "$OUT"
(cd "$ROOT/build/classes" && jar --create --file "$OUT" .)
if unzip -Z1 "$OUT" | grep -q '^org/bukkit/'; then
  echo 'ERROR: compile stubs leaked into JAR' >&2
  exit 1
fi
unzip -t "$OUT" >/dev/null
printf 'Built %s\n' "$OUT"
