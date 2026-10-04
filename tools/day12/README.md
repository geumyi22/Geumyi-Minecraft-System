# Day 12 tools

This directory starts the final production-hardening toolset.

- `Day12_Final_Verification_READ_ONLY.ps1`: reads local GSC/network/service/backup/disk state and writes a redacted JSON report.
- `Day12_Final_Verification_READ_ONLY.cmd`: Windows launcher.

The verifier **does not** stop/restart servers, edit firewall rules, change server files, delete backups, or claim real-client E2E. Its report is evidence for Day 12, not Day 12 completion by itself.
