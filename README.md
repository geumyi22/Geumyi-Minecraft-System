# Geumyi Minecraft System

성민님의 Minecraft 서버/관리 시스템 최신 통합 저장소입니다.

## Current baseline — 2026-09-26

| Component | Version |
|---|---|
| Minecraft / Paper baseline | 26.3 |
| GeumyiServerCenter (GSC) | 4.2.3 |
| GeumyiStatusAgent | 0.5.4 |
| GSCM | 1.1.2+112 |
| GeumyiServerTools (GST) | 1.1.1 HOTFIX |
| GeumyiDiscordStatus (GDS) | 1.1.1 |
| GeumyiTechnology | 0.1.3 |
| GeumyiChemistry | 0.4.1 |

## Repository policy

- `main` keeps only the current/latest source, configuration templates, scripts and documentation.
- Old versions are tracked by Git history/tags rather than duplicated `old/`, `backup/`, `v1/` folders.
- Large distributable binaries (EXE/APK/IPA/server bundles) belong in GitHub Releases, not normal Git history.
- Secrets and machine-specific credentials are never committed.

## Main areas

- `GSC/` — GeumyiServerCenter / StatusAgent
- `GSCM/` — mobile client and build documentation
- `Plugins/` — GST / GDS / Technology / Chemistry
- `Servers/Wild/` — 야생 서버 current configuration/package notes
- `Servers/Playground/` — 놀이터 서버 current configuration/package notes
- `ResourcePacks/` — current 26.3 resource-pack notes
- `.github/workflows/` — GSCM Android/iOS CI retained from the existing repository

## Important

Runtime files containing Discord bot tokens, RCON passwords, GSC API/device/pairing tokens, GitHub tokens, Apple signing credentials, keystores or other secrets are intentionally excluded.

See `VERSION-MATRIX.md` and `SECURITY-NOTES.md`.
