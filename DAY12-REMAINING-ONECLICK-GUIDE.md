# Day 12 — Remaining nine phases, one-click read-only review

## What this new CMD actually checks

Run **only on Minecraft server PC**, not the SubPC. Previous **Golden backup (12.0), real whole-system health (12.3), synthetic disaster-recovery drill (12.8), LAN IPv4/IPv6, Tailscale IPv4/IPv6 and real GSC unauthenticated HTTP 401 verification** are previously completed within their stated scopes. Running these scans again would waste time and **cannot** supply the missing Windows socket-owner proof.

Download the GitHub Actions **`day12-remaining-oneclick-readonly-kit`** focused artifact after all Windows CI checks pass, extract the ZIP in full and double-click the root file **`Geumyi_Day12_Remaining_OneClick_READ_ONLY.cmd`**.

No special approval is needed for this read-only inventory and no UAC elevation is requested. The command refuses to run without the installed server-PC **Geumyi Server Center Host** service (protecting SubPC). It neither starts/stops a service nor deploys, deletes, cleans or overwrites server assets.

- **12.1** Collect up-to-date resource pack/datapack *inventory/preflight only* using the existing scoped read-only collector. If the managed manifest has no enabled entries, report `NOT_CONFIGURED`; never pretend successful live deployment.
- **12.2** Collect GSC component/fleet inventory only and inspect installed `GeumyiStatusAgent-0.5.4.jar` plus **in-memory** Windows Java process command lines for an actual launch of the canonical Agent JAR. Only Boolean flags/counts are exported, **never process commands, PIDs, install paths or API credentials**. Installed file alone is not proof that the right Agent is running. Even a matching command is not an authenticated JAR or runtime functional E2E.
- **12.4** Reopen only `deploy/day12-lifecycle-policy.json` and verify protected backup/Golden/transaction exemptions, Trash-only policy and permanent-delete-auto=false. Historic 0 candidates and 4/4 Golden remain preserved. **No new full backup inventory, retention dry-run POST or Apply**.
- **12.5** Preserve earlier real 5/5 NTFS ACL review and prior scoped firewall candidate review; effective ACL/firewall verification remains `REVIEW_REQUIRED`. **Do not rescan 268 firewall rules** or change them.
- **12.7** Read at most local known-good manifest metadata. Prior 84 cache artifacts remain previously verified, but **offline known-good startup E2E is NOT performed**; no unplugging networking, restarting or cache Build.
- **12.10** Preserve real tested-path evidence: LAN IPv4/IPv6 and Tailnet IPv4/IPv6 each 0/8 private, and 8/8 unauthorized GSC HTTP GET returned 401; strict OS native owner/bind remains FAIL. **Do not repeat GetExtendedTcpTable/GetTcpTable2, netstat, WFP or remote port scans**.
- **12.11** Flag human Java/Bedrock/GSCM and safe restart/backup/update E2E as pending. No fake device actions.
- **12.12** Flag real 8–12 h soak as pending; do not accidentally start a soak session during a quick review.
- **12.13** Read checked-in final release manifest; never set gates PASS, sign, tag or publish Stable.

## Output and interpretation

The command saves one **safe-to-share** consolidated `Day12-Remaining-Summary.json` under `Desktop\Geumyi-Day12-Remaining-YYYYMMDD-HHMMSS\`. **Upload only this summary JSON to ChatGPT.** Subfolders for Phase 12.1/12.2 contain more detailed local data such as filenames, checksums and installed-content properties; they are **operator-private and must not be uploaded wholesale** without review.

All remaining nine phases appear exactly once. Status values such as `NOT_CONFIGURED`, `RUNTIME_PROVENANCE_REVIEW_REQUIRED`, `EFFECTIVE_ACL_FIREWALL_REVIEW_REQUIRED`, `KERNEL_OWNER_BIND_UNVERIFIED`, `REAL_DEVICE_E2E_REQUIRED` and `RELEASE_GATES_BLOCKED` mean **not complete**. A child report being `CAPTURED` means inventory gathered, NOT deployed or real-client E2E PASSED.

The result `REVIEW_REQUIRED`, and process exit code 0, **only mean the review tool successfully generated its summary**. They are not security PASS or Day 12 completion. On a missing required report, the respective phase remains `PREFLIGHT_CAPTURE_INCOMPLETE` or `RUNTIME_PROVENANCE_REVIEW_REQUIRED`, never auto-approves release. Existing `FINAL-RELEASE-GATES.json` is not changed.

## Scope / limits

This is a single compact **read-only remaining-work audit**, not an impossible automated proof of genuine Minecraft client operation, native Windows socket ownership, a safe shutdown and recovery, Bedrock UDP sessions, effective WFP rules or an eight-hour passage of time. Actual 12.1 content deployment, 12.5 security changes, offline outage tests, service reboot, update and restore **require distinct preflight/operator approval** and preservation of 4/4 Golden backups. New E2E and soak evidence will follow only after these gates are ready.

Do not use old all-phases Collect All CMD for this task; it repeats already verified passes and can overwhelm debugging evidence. **The new focused CMD is intentionally different.**

## Windows CI

The new workflow `.github/workflows/day12-remaining-oneclick-readonly-kit.yml` uses a disposable Windows runner to:
1. Parse all packaged PowerShell scripts and verify ZIP layout.
2. Invoke this runner with `-Synthetic`: validate exactly nine mandatory phases with no network/CIM/firewall/service access and verify fail-closed statuses.
3. Invoke without `-Synthetic` on the disposable runner (where the GSC Host service is absent) and assert it **refuses** to pretend the runner is the user's server PC.
4. Verify the package includes the required two read-only child collectors, deploy references, report gates and this guide.

GitHub CI success is only a **tool packaging/synthetic contract PASS**, never live server PASS.
