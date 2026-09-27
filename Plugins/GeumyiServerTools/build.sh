#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BASE="${BASE_JAR:-$ROOT/base/GeumyiServerTools-0.1.5-Paper26.3.jar}"
BUILD="$ROOT/build-repro"
if [[ ! -f "$BASE" ]]; then echo "Missing base/reference JAR: $BASE" >&2; exit 2; fi
OUT="$ROOT/GeumyiServerTools-1.1.1-SpigotPaper26.3-GSCv4.1-HOTFIX.jar"
rm -rf "$BUILD"
mkdir -p "$BUILD/stubs" "$BUILD/classes" "$BUILD/jarroot"
find "$ROOT/stubs" -name '*.java' -print0 | xargs -0 javac -encoding UTF-8 -d "$BUILD/stubs"
find "$ROOT/src/main/java" -name '*.java' -print0 | xargs -0 javac -encoding UTF-8 -cp "$BUILD/stubs:$BASE" -d "$BUILD/classes"
(cd "$BUILD/jarroot" && jar xf "$BASE")
cat > "$BUILD/jarroot/META-INF/geumyi-26.3-upgrade.properties" <<'EOF'
target=Spigot/Paper 26.3
version=0.1.5
compatibility=Spigot/Paper API 26.3
patches=Spigot compatibility hotfix: replaced Paper-only Bukkit.getMinecraftVersion() calls with Bukkit.getBukkitVersion()
EOF
python3 - "$BUILD/jarroot" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
for p in root.rglob('*.class'):
    b=p.read_bytes()
    b2=b.replace(b'0.1.5', b'1.1.1')
    if b2!=b: p.write_bytes(b2)
PY
rm -f "$BUILD/jarroot/plugin.yml" "$BUILD/jarroot/config.yml"
cp -a "$ROOT/src/main/resources/." "$BUILD/jarroot/"
find "$BUILD/classes/kr/geumyi/servertools" -type f -name '*.class' ! -name 'CoreTests.class' -exec cp -f {} "$BUILD/jarroot/kr/geumyi/servertools/" \;
rm -f "$OUT"
(cd "$BUILD/jarroot" && jar --create --file "$OUT" .)
echo "$OUT"
