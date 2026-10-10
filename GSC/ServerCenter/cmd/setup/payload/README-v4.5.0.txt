Geumyi Server Center 4.5.0 — Stable Maintenance Build (2026-10-11)

This is a fresh 4.5.0 rebuild of the Geumyi Server Center Host, Client and Setup source, coordinated with GSCM 1.5.0+150.
Existing functionality is carried forward; no new gameplay features are claimed by this version.
The last independently operator-verified installed baseline before this release was GSC 4.3.8 / GSCM 1.1.5+117.

Core functions:
- Host and Client independent self-update flows
- Managed Java / Bedrock worlds and Velocity Lobby routing
- Trusted signed update manifests with SHA-256 verification and controlled rollback
- Protection & Recovery 2.0 backups and protected Golden checkpoints
- Updated Windows native listener PID attribution hardening
- Exclusive random temporary files when saving trusted mobile device records

Safety: do not put API credentials, RCON passwords, device tokens or signing keys in this repository.
The release build cannot by itself establish that a live Minecraft server has been safely updated.
