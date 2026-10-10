# Day12.10 — disposable Windows firewall staging evidence and deployment boundary

**Status:** CI disposable-runner experiment / not a production change. **Canonical `backend_ports_private`: FAIL.**

## Motivation

The 04:25 and 04:38 server-PC ActiveStore and Java-program correlation reports narrowed the redacted set to **36 widely scoped All-program Allow candidates**; none can be safely disabled based on missing raw rule identities and dependencies. No running-Java-image-specific Allow was observed, but an Any-program Allow can still apply to a Java service. Prior remote LAN negative checks and historical app bind messages do not prove current exclusive loopback binding.

Microsoft documents scoped inbound firewall rules with `-LocalAddress`, `-RemoteAddress`, `-LocalPort`, `-Protocol`, `-Direction` and `-Action` for Windows Firewall. A scoped Block candidate that targets **only the runner's nonloopback local IPv4** and an **ephemeral TCP port** is one avenue to evaluate loopback impact without touching any real server. See: [New-NetFirewallRule reference](https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule?view=windowsserver2025-ps).

## What the isolated Windows Actions experiment actually does

Workflow `.github/workflows/day12-disposable-firewall-stage.yml` uses a newly provisioned **GitHub-hosted Windows runner**, *not the user's Windows Minecraft server*.

1. Source `tools/day12/Day12_Phase10_Disposable_Firewall_Loopback_CI.ps1` refuses to create any firewall rule without a special CI environment flag, repository identity, GitHub run identifier, and explicit `-DisposableRunner` argument. Its `-Synthetic` path creates **no rule** and is checked by the standard Day12 Safety CI.
2. The runner creates a real loopback TCP listener on an **OS-selected ephemeral port (49152–65535)**. No Paper, Velocity, Geyser, GSC, mobile backend or RCON ports are used.
3. The tool chooses one temporary **nonloopback local IPv4** as the firewall rule `LocalAddress`. It verifies a local TCP handshake before rule creation.
4. It creates **one** uniquely named, inbound TCP Block rule scoped to the CI ephemeral port, selected nonloopback local IPv4, profile Any and remote address Any. **It does not modify or remove any pre-existing rule.**
5. It re-reads the rule, local/port filters, and checks **127.0.0.1** handshake while the rule exists. A passing test shows only *this local loopback sample* was not interrupted on that CI runner; it does not prove real remote traffic would be blocked.
6. It removes **only the rule created in this invocation** within `finally` and requires its removal to return a successful result. The hosted CI machine is discarded after completion.

The script exports only a non-sensitive JSON with result, whether rule creation/readback/removal succeeded, local loopback handshake flags and an explicit `canonical_backend_ports_private=UNCHANGED_FAIL`. No rule name, IP, host identity, executable path, world data, token or password is exported.

## Explicit limits

- A local TCP loopback test on a CI runner is **not** a full external firewall policy/E2E proof. It doesn't establish packet drops from a separate LAN host, real IPv6/IPv4-mapped, DHCP address changes, VPN/Tailscale, Geyser UDP, authorized GSC remote access or actual Java/RCON listener ownership.
- The CI rule applies to **one local IPv4 and one temporary port**. A future production candidate must address **all relevant active LAN/overlay/IPv6 local endpoints**, dynamic address changes and Windows profile variations, or remain unapproved. Never assume a blanket Block on eight ports leaves proxy-to-backend/RCON loopback intact.
- Broad Any-program Allow candidates (36) remain in production unchanged. A scoped firewall Block may have different enforcement semantics depending on Windows WFP precedence, IPsec authenticated overrides, programs and interfaces. **Don't claim strict backend bind PASS from firewall changes alone.**
- Since CI uses `New-NetFirewallRule` and `Remove-NetFirewallRule` **on a disposable Microsoft/GitHub runner only**, never put this script into any operator CMD launch path or ask the user to execute it on their server. Its environment guard is intentional.

## Follow-up before any live modification

1. CI staging must show creation + correct metadata + **loopback before/after** + successful owned-rule deletion, or be marked **INCONCLUSIVE/FAIL**.
2. Build a *separate* disposable VM or secondary test host with two network vantage points to prove inbound remote packet drop and preserved loopback for both IPv4/IPv6 with representative Paper/RCON/proxy behavior. Do not use a production reboot for this rehearsal.
3. Privately identify each of the 36 broad rule IDs, programs, feature owners, scopes and dependencies; **do not disable based on ordinal, name hint or a single redacted rule class**.
4. Before any real-host firewall edit, present exact rules, effective expected scopes, remote access impact, a protected configuration export, Golden 4/4 prerequisite, active-player/change-window preflight and a reversible rollback. Require explicit operator approval.
5. Re-run canonical `Geumyi_Final_Verification.cmd` only after new trustworthy runtime bind evidence or an approved release-standard change. Until then Day12.10 FAIL, Day12.11 final E2E pending, Day12.12 live soak pending, Day12.13 Stable blocked.

## Sources

- [04:38 real Java firewall identity analysis](DAY12-PHASE10-JAVA-RULE-LIVE-RESULT-20261010.md)
- [Compensating-control options](DAY12-PHASE10-COMPENSATING-CONTROLS-REVIEW.md)
- [Day12.10 security decision](DAY12-PHASE10-SECURITY-DECISION-PACKET.md)
