#!/usr/bin/env bash
# One-time copy/publish of byte-identical operator-accepted Day11 artifacts.
# Does not weaken FINAL-RELEASE-GATES.json or create deployment-stable.json.
set -euo pipefail
test "$GITHUB_REPOSITORY" = 'geumyi22/Geumyi-Minecraft-System'
SRC='system-2026.10.07-day11-gsc438-beta'
SHA='a17975030ed3f9b71d8632a7897c1c206d9bfcdf'
TAG='system-2026.10.11-gsc438-gscm117-ops-stable'
gh api "repos/$GITHUB_REPOSITORY/releases/tags/$SRC" > "$RUNNER_TEMP/origin.json"
python3 - "$RUNNER_TEMP/origin.json" "$SRC" "$SHA" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]))
assert j['id']==405786755 and j['tag_name']==sys.argv[2] and j['target_commitish']==sys.argv[3]
assert not j['draft'] and j['prerelease'] and len(j['assets'])==26
PY
test "$(gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$SRC" --jq .object.sha)" = "$SHA"
if gh release view "$TAG" >/dev/null 2>&1; then echo 'ERROR: destination release exists'; exit 1; fi
if gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$TAG" >/dev/null 2>&1; then echo 'ERROR: destination tag exists'; exit 1; fi
mkdir -p dist
gh release download "$SRC" --dir dist
python3 - "$RUNNER_TEMP/origin.json" <<'PY'
import json,hashlib,pathlib,sys
j=json.load(open(sys.argv[1]))
d=pathlib.Path('dist')
assets={x['name']:x for x in j['assets']}
assert set(assets)=={x.name for x in d.iterdir() if x.is_file()}, 'missing/unknown original asset'
pins={
'GeumyiServerCenter-v4.3.8-Setup.exe':'288aeb4f0cf75691a997411911bf2fddac1b61644e915845bb6161468080a039',
'GSCM-v1.1.5+117-Android.apk':'372073ff8da40cb32ef9e9c1ed351779b812d0d121d75d05694ba46ecf2f9afe',
'GSCM-v1.1.5+117-unsigned.ipa':'569506440987fa17f31d6a18400c7a8530b7336819c1da31ca8a7aa4a8f4a290'}
checked=[]
for name,asset in sorted(assets.items()):
    p=d/name
    digest=hashlib.sha256(p.read_bytes()).hexdigest()
    assert asset.get('digest')=='sha256:'+digest, 'source SHA256 mismatch '+name
    assert asset['size']==p.stat().st_size, 'source size mismatch '+name
    if name in pins: assert digest==pins[name], 'pinned binary mismatch '+name
    checked.append({'filename':name,'sha256':digest,'bytes':asset['size']})
attestation={'schema':1,'scope':'OPERATOR_ACCEPTED_SMALL_SERVER_OPERATIONS_STABLE',
    'gsc_version':'4.3.8','gscm_version':'1.1.5+117',
    'source_tag':'system-2026.10.07-day11-gsc438-beta',
    'source_sha':'a17975030ed3f9b71d8632a7897c1c206d9bfcdf',
    'original_signed_beta_manifest_preserved':True,
    'signed_stable_auto_update_manifest_created':False,
    'day12_formal_stable_gate':'BLOCKED',
    'no_runtime_changes':True,
    'ios_is_unsigned':True,'original_asset_count':len(checked),'assets':checked}
(d/'OPS-STABLE-PROVENANCE.json').write_text(json.dumps(attestation,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
with (d/'SHA256SUMS-OPS-STABLE.txt').open('w',encoding='utf-8') as out:
    for f in sorted(d.iterdir()):
        if f.is_file() and f.name!='SHA256SUMS-OPS-STABLE.txt':
            out.write(hashlib.sha256(f.read_bytes()).hexdigest()+'  '+f.name+'\n')
print('VERIFIED: %d original assets, pinned GSC/GSCM hashes unchanged'%len(checked))
PY
(cd dist && sha256sum --check SHA256SUMS-OPS-STABLE.txt)
openssl pkeyutl -verify -rawin -pubin -inkey dist/deployment-public.pem -sigfile dist/deployment-beta.json.sig -in dist/deployment-beta.json
cat > "$RUNNER_TEMP/release-notes.md" <<'EOF'
# 금이 마인크래프트 시스템 — Stable (소규모 서버 운영 기준)

**GSC 4.3.8 / GSCM 1.1.5+117 / StatusAgent 0.5.4 / Paper 26.3**

실제 운영 중인 Day 11 베타 배포 파일 **26개를 변경 없이 재사용**한 최종 운영 Stable 스냅샷입니다. 모든 업로드 원본의 GitHub SHA-256·길이·프로그램 파일 고정 해시와 배포 베타 명세의 Ed25519 서명을 다시 검증했습니다.

- GSC 4.3.8 Setup·Windows Host·Client, GSCM Android 1.1.5+117 APK
- iOS IPA는 **미서명** 상태이므로 별도 코드 서명이 필요합니다.
- 기존 Paper 플러그인 JAR, 원본 서명된 *beta* 배포 명세, 공개키·서명, 전체 파일 SHA 목록 및 출처 정보 포함
- 설치 중인 GSC/GSCM과 서버 파일, 월드, Golden 백업은 변경하지 않았습니다.

**중요:** 이 릴리즈는 운영자가 수락한 **GitHub Stable 기준 스냅샷**입니다. 원본 서명은 *beta* 채널 명세에만 유효합니다. 새로 서명된 deployment-stable.json이 없으므로 GSC 자동 Stable 업데이트 피드에 사용되지 않습니다.

Day 12 공식 보안 게이트(내부 포트 네이티브 바인딩, Windows 방화벽·ACL 실효 보호, 실제 오프라인 부팅 등)는 아직 충족되지 않았습니다. FINAL-RELEASE-GATES.json의 정식 Stable 차단은 유지합니다. 기타 서버의 일부 테스트는 운영자 지시에 따라 면제했습니다.

원본 릴리즈: https://github.com/geumyi22/Geumyi-Minecraft-System/releases/tag/system-2026.10.07-day11-gsc438-beta

운영 마감: https://github.com/geumyi22/Geumyi-Minecraft-System/blob/main/PROJECT-CLOSEOUT-2026-10-11.md
EOF
gh api -X POST "repos/$GITHUB_REPOSITORY/git/refs" -f ref="refs/tags/$TAG" -f sha="$SHA" --jq '{ref,sha:.object.sha}'
gh release create "$TAG" --verify-tag --draft --title 'Geumyi Minecraft System — Stable 운영 기준 (GSC 4.3.8 / GSCM 1.1.5+117)' --notes-file "$RUNNER_TEMP/release-notes.md"
gh release upload "$TAG" dist/*
gh api "repos/$GITHUB_REPOSITORY/releases/tags/$TAG" > "$RUNNER_TEMP/draft.json"
python3 - "$RUNNER_TEMP/draft.json" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]))
assert j['draft'] is True and len(j['assets'])==28, 'incomplete draft asset set'
assert j['target_commitish']=='a17975030ed3f9b71d8632a7897c1c206d9bfcdf'
names={x['name'] for x in j['assets']}
assert 'deployment-stable.json' not in names
assert {'deployment-beta.json','OPS-STABLE-PROVENANCE.json','SHA256SUMS-OPS-STABLE.txt'}<=names
PY
release_id="$(gh api "repos/$GITHUB_REPOSITORY/releases/tags/$TAG" --jq .id)"
gh api -X PATCH "repos/$GITHUB_REPOSITORY/releases/$release_id" -F draft=false -F prerelease=false -f make_latest=false --jq '{tag_name,draft,prerelease,html_url}'
