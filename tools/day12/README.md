# Day 12 tools

This directory contains the final production-hardening toolset.

## Current phase — 12.0A

- `Day12_Phase0_Golden_Baseline_READ_ONLY.ps1`: captures the Day-11 final runtime baseline from the real server PC without mutation.
- `Day12_Phase0_Golden_Baseline_READ_ONLY.cmd`: Windows launcher.

The Phase 0A report is required **before** creating/protecting the Golden Recovery Checkpoint in 12.0B.

## Later final verification — 12.10

- `Day12_Final_Verification_READ_ONLY.ps1`: reads local GSC/network/service/backup/disk state and writes a redacted JSON report.
- `Day12_Final_Verification_READ_ONLY.cmd`: Windows launcher.

READ-ONLY tools do not stop/restart servers, edit firewall rules, change server files, delete/move backups, or claim real-client E2E. Their reports are evidence for Day 12; they are not Day-12 completion by themselves.
