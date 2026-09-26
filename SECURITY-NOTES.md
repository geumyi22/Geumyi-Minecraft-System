# Source import security review

Scope: the final tracked source tree, including decoded GSCM files, source templates, Java/Bukkit defaults, build scripts, tests and resource-pack text/assets. Existing release binaries and complete Git history were not audited or modified.

Checks: Gitleaks directory scan with redacted output, targeted Discord/RCON/API/device/pairing/GitHub/Apple/keystore/private-key patterns, configuration inspection, disallowed-extension checks and archive/source comparison.

No real credential was detected in the reviewed upload set. Gitleaks reported two Discord-ID matches in GSC unit tests; both are the literal synthetic fixture 123456789012345678, not recovered operational IDs. Test pairing code 12345678 and old-secret/KEEP_ME are likewise synthetic fixtures. The QR fixture's private-looking 100.x address was replaced by 100.64.0.1.

Agent templates and GDS defaults contain blanks or explicit CHANGE_THIS / PUT_YOUR placeholders. Installer-managed filenames are retained only for those placeholder templates because source code reads the exact paths. Never commit configured copies.

Excluded: EXE/JAR/APK/IPA/ZIP/MCPACK distributions, base JARs, keystores, signing certificates/private keys, configured agent files, runtime pairing/device state, logs and private local settings. PNG/ICO/OGG files are required source assets.

Pattern scanning cannot prove absence of every possible secret. If a real credential is discovered in old history or Releases, rotate it before treating deletion as remediation.
