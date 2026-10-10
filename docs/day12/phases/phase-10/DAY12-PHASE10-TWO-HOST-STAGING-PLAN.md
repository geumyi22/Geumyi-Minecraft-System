# Day 12.10 — two-host disposable staging plan (prepared; not executed)

**Current status: PLAN + offline fail-closed matrix only. No production firewall changes, no second-host runtime test.**  
**Canonical `backend_ports_private` remains FAIL. Stable/Maintenance remains blocked.**

## Why the prior runner test is insufficient

The actual GitHub-hosted Windows runner [disposable firewall stage #37982653272](https://github.com/geumyi22/Geumyi-Minecraft-System/actions/runs/37982653272) created a temporary inbound Block rule on its own **ephemeral port**, read back the metadata, verified local `127.0.0.1` connectivity and removed the rule. Its captured artifact confirms `remote_host_tested=false`, `ipv6_tested=false`; a local client on the same machine **is not an independent remote network vantage**.

GitHub-hosted Windows runners generally sit behind controlled hosted networking and this repo has **no authorized second routable test VM** in the current environment. Starting two independent GitHub Jobs does not by itself create inbound TCP reachability from one runner to the other. Do not infer remote filtering from an isolated local TCP connect; do not expose an ad-hoc tunnel or modify a public interface to manufacture a test.

## Required test environment BEFORE any host action

- **Two explicitly disposable Windows hosts** on an isolated network: *stage-server* (test service + test rule), *stage-client* (different host, same isolated segment). Neither may be the live Geumyi Minecraft server PC or rely on players' game servers as test listeners.
- Stage-server has independently verified IPv4 **and IPv6** nonloopback test addresses and loopback; stage-client can reach each stage listener *before* any deny rule. If IPv6 cannot be routed, mark that test **UNVERIFIED**, not passed.
- Use a unique **OS-assigned ephemeral TCP test port**, with a simple disposable listener bound to the staged nonloopback addresses; do not use production ports 25565–25579 or GSC 8787, and do not require RCON credentials.
- A separate reachable TCP **positive control** plus a safely implemented UDP game-protocol control (not treating a sent UDP datagram as proof of server receipt) must remain healthy before, during and after the rule. No player sessions or production application included.
- Both hosts must have a tested out-of-band recovery path. Record a private firewall-policy backup before changing any stage rule, record exactly which new rules were created and verify owned-rule deletion at the end. Staging rule changes require control of this *disposable* environment; no authorization exists for live server changes.
- Use distinct inbound IPv4 and IPv6 stage rules or sufficiently reviewed dual-family scopes. An IPv4 `LocalAddress` rule does **not** demonstrate IPv6 restrictions. Validate Windows firewall profile changes, adapters and address-family paths explicitly.

## Test sequence and stop conditions

1. **Before:** stage-client connects to the deliberately nonloopback IPv4 and IPv6 *test* listeners. Stage-server can also connect to its own `127.0.0.1` and `::1` listeners. Public TCP/UDP controls are working. Confirm test processes remain alive throughout.
2. **Apply on disposable stage-server only:** create uniquely named, scope-limited inbound Block candidate(s) for **the test ephemeral port** and current *nonloopback* local v4 and v6 stage addresses. Do not edit existing production rules or copy/paste a blanket 'block all Java' command. Export exact stage-rule definitions.
3. **After:** stage-client must **fail to connect** to both nonloopback IP families. Stage-server local v4/v6 loopback listeners must still connect, and the independent TCP and UDP positive controls must remain working. If a public control or loopback fails, ABORT and remove only the new stage rules immediately.
4. **Rollback:** remove only the uniquely owned staging rules. Stage-client connectivity to the intentionally public v4/v6 test listeners must recover. Both loopback and control paths must still work. Verify no owned stage rule remains, no unintended service changes occurred and original stage policy matches the recorded backup.
5. **Interpreting the result:** a coherent before → blocked after → restored rollback remote test is stronger causal evidence than a single negative port probe. It is **still a disposable staging test, not evidence that the live eight backends are securely bound or firewalled**. Rule precedence, IPsec exceptions, VPN/overlay paths, changing LAN addresses and live application/process owner associations remain separate.

## JSON matrix, independently reviewed offline

Repo-only evidence evaluator: `tools/day12/Day12_Phase10_TwoHost_Stage_Evidence_REVIEW_ONLY.ps1`. It **does not connect to sockets, run Windows firewall commands, enable auditing or touch Minecraft**. Its only function is to check whether self-reported staged **before / after / rollback** rows contain the required distinct-host, IPv4+IPv6, local-loopback, TCP/UDP positive control, alive-process and owned-rule cleanup fields. A consistent report is labelled **`EVIDENCE_MATRIX_CONSISTENT_REVIEW_ONLY`**, not PASS. The negative/unknown paths are **`CHECK_REQUIRED`**.

Example **schema only** (not real captured evidence):

```json
{
  "schema": 1,
  "environment": "DISPOSABLE_TWO_HOST",
  "explicitly_not_production": true,
  "independent_client_host": true,
  "production_modified": false,
  "rule_backup_created": true,
  "created_only_owned_test_rules": true,
  "owned_rules_removed": true,
  "before": {
    "server_process_alive": true,
    "tcp_public_control_ok": true,
    "udp_public_control_ok": true,
    "ipv4_local_loopback_ok": true,
    "ipv6_local_loopback_ok": true,
    "ipv4_remote_stage_port_connects": true,
    "ipv6_remote_stage_port_connects": true
  },
  "after": {
    "server_process_alive": true,
    "tcp_public_control_ok": true,
    "udp_public_control_ok": true,
    "ipv4_local_loopback_ok": true,
    "ipv6_local_loopback_ok": true,
    "ipv4_remote_stage_port_connects": false,
    "ipv6_remote_stage_port_connects": false
  },
  "rollback": {
    "server_process_alive": true,
    "tcp_public_control_ok": true,
    "udp_public_control_ok": true,
    "ipv4_local_loopback_ok": true,
    "ipv6_local_loopback_ok": true,
    "ipv4_remote_stage_port_connects": true,
    "ipv6_remote_stage_port_connects": true
  }
}
```

**Important:** The example JSON is *illustrative*, not user-supplied data; feeding it to the evaluator would only show schema consistency and MUST NOT be called a network/firewall test. The evaluator does not authenticate remote captures or inspect firewall policy. Windows CI's synthetic test checks fail-closed behavior on missing separate-host attestation, bad IPv6 denial, failed rollback and failed public controls.

## Gate decision

- **Source + synthetic CI:** may proceed autonomously.
- **True two-host runtime test:** cannot be performed from the existing one Windows CI runner; schedule only after a proper disposable infrastructure is actually available.
- **36 broad server-PC Allow rules:** preserve intact, because no stable rule identity and dependency audit justifies deletion.
- **Real server firewall modification:** **NO**, until exact effective policy + target endpoints, one-window deployment/rollback, independent v4/v6/overlay test, Golden 4/4, GSC/RCON/Java/Bedrock controls and explicit operator approval.
- **Strict 12.10 `backend_ports_private`: FAIL** and no Stable/Day12.13 promotion until direct current IPv4+IPv6 listener owner/bind evidence is proved or a separately formalized and approved alternative security policy replaces the original standard transparently.

Related: [previous single-runner result](DAY12-PHASE10-DISPOSABLE-FIREWALL-RESULT-20261010.md), [04:38 application rule review](DAY12-PHASE10-JAVA-RULE-LIVE-RESULT-20261010.md), [security decision record](DAY12-PHASE10-SECURITY-DECISION-PACKET.md).
