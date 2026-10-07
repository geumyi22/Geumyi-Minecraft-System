# Geumyi Recovery Kit

Day 12 recovery source package. **No plaintext secrets are included.**

Use only after identifying the failed component and preserving incident logs.

1. Verify known-good files with `Verify-KnownGood.ps1`.
2. Stop only the affected GSC service/process through normal operator procedures.
3. Restore the selected verified file with `Restore-Verified-File.ps1`.
4. Start the affected component normally.
5. Run the Day 12 read-only health/final verification tools.
6. If Minecraft world/config recovery is required, use the GSC Protection & Recovery UI/API and its restore preflight/checkpoint/rollback path instead of copying world files manually.

The recovery scripts refuse a SHA mismatch and do not contain credentials.
