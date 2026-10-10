# Day 12.9 — GSC / GSCM Console UX Operator Sign-off (2026-10-11 KST)

**Disposition: CLOSED FOR OPERATOR-ACCEPTED UX WORKFLOW, WITH EXPLICIT iOS PATCHED-BINARY EVIDENCE EXCEPTION.** This is not a claim that iOS was independently tested after an updated binary installation.

## Actual changes and prior evidence

- GSC desktop `GSC/ServerCenter/cmd/client/dashboard.html` displays the active console and refreshes on a **four-second timer** while open. The polling is not WebSocket push; stale/overlapping requests and scroll behavior are guarded.
- GSCM `GSCM/lib/screens/server_detail_screen.dart` defaults the **four-second console auto-refresh ON**, with a toggle and overlap prevention. This is a source change for both Android and iOS, not proof both client apps have the changed build installed.
- Focused source/JS contract [GitHub Actions `38057732807`](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/38057732807) **PASS**. Source changes `57f45031188eab5467b8dc22c3c8a858fe8bcb81` and focused fixture `aefc25dcbe683edf116e2ec62090a8d032220599`.
- Operator reported GSC Host test update **"업데이트 정상"**, then after an explicit four-second console test **"정상"**; classify **PC CONSOLE USER-REPORTED REAL UI PASS**.
- Operator reported **"안드로이드 콘솔 정상"** after the targeted patched Android test; classify **ANDROID GSCM CONSOLE USER-REPORTED REAL UI PASS**.
- Prior operator **"둘다 정상"** covers an earlier Android+iOS GSCM **status/reconnect basic smoke**. Later the operator stated **"ios도 된다 해 어짜피 똑같아"**, explicitly directing iOS be regarded as normal for operational acceptance. Preserve as **OPERATOR_ASSERTED_IOS_PATCHED_CONSOLE_NORMAL_WITHOUT_UPDATED_IPA_DEVICE_E2E**; do not invent an installed IPA hash or fresh iOS auto-refresh observation.

## Final review action

The operator explicitly requested Phase **12.9** be processed second in `12.4 → 12.9 → 12.2 → 12.6`. Given both source/CI contract and real PC + Android UI acceptance, **close the UX task in user-accepted scope**, without requesting duplicate functional tests or modifying live servers.

The remaining iOS patched-binary verification is a **documented evidence exception**, not a newly executed test. This sign-off **does not close 12.11 full canonical E2E, 12.6 mobile signed-release production distribution, 12.10 private backend bind or 12.13 Stable**. Existing versions and files are unchanged; no new build/IPA/APK is published by this record.
