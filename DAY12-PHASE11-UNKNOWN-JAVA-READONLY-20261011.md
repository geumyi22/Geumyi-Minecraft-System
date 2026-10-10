# Day12 #2 single unidentified JVM read-only follow-up (2026-10-11 KST)

Prior real `Day12-2-12-17-SHARE-SUMMARY-20261011-002947.json` reported GSC Host 1 Running, Velocity 6 = three verified parent/child pairs, UDP 19132/19133/19134 each owned by correct child, 3 Paper-name-matched JVMs and **one other Java**. The old validator assumed **four running Paper JVMs without independently checking whether a backend is offline**, causing `REVIEW_REQUIRED`. It neither proves an orphan nor justifies a restart.

This scoped follow-up reads only Windows Java/javaw process command lines in memory and GETs `http://127.0.0.1:8790/api/v1/snapshot` with no supplied credentials, exporting only process-role counts, whitelisted role labels and GSC online/offline counts. No command lines, JAR paths, PIDs, IPs, tokens, player names or secrets are exported. It never touches server files, process state, firewall or backup.

- If the one extra JVM is the expected `GeumyiStatusAgent-0.5.4.jar`, exactly three Paper processes are observed and GSC reports **three online and one offline**, the **narrow process role census** may return `PASS_SCOPED_ROLE_RECONCILIATION`. This reuses earlier Velocity parent/child/UDP evidence. It does **not** prove Day12.10 native owner/bind or exact Paper PID↔server identity.
- If four servers report online but only three Paper launchers are seen, any unrecognized/alternate JAR exists, or GSC API denies unauthenticated loopback GET, remain `REVIEW_REQUIRED` without guessing or changing production services.
- The StatusAgent role is only a possibility; **nothing establishes it until the actual follow-up report**.
- #12 and #17 CI state-machine/temporary plugin rollback remain previously tested in disposable GitHub CI (run `38063619014`) only; this script does not repeat them or pretend to have triggered an actual unexpected process crash or signed update.
- Safely run on **server PC**, once, and upload only `Desktop\Geumyi-Day12-Three-Tests\Day12-Unknown-Java-Role-READ-ONLY-*.json`.

No Stable release or security/soak gate changes.

## Actual follow-up result — 2026-10-11 00:42 KST

**PASS_SCOPED_ROLE_RECONCILIATION** from submitted real operator file `Day12-Unknown-Java-Role-READ-ONLY-20261011-004221.json`, generated `2026-10-10T15:42:21.3125520Z`. Process roles: Velocity 6, Paper 3, StatusAgent 1, unknown 0. GSC four distinct server IDs, 3 online/1 offline. **This resolves the earlier scoped #2 anomaly**. Previous source described StatusAgent as a hypothesis only; it is now confirmed **by process launch argument classification**, not binary cryptographic attestation.

No changes were made to running services, worlds, network or backups. No new #12 real unexpected process loss or #17 real signed canary update/rollback was performed. Security's native TCP bind and Stable remain OPEN.
