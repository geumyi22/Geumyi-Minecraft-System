Geumyi Server Center 5.0.0 — personal operator-accepted Stable

Host, Client and Setup share version 5.0.0. GSCM remains separately
versioned; the compatible v4 management API is retained.

The release notes and personal acceptance ledger distinguish automated
checks, operator confirmation, accepted limitations and unexecuted tests.
This personal release does not claim full Day12 production closure.

Original Windows Scheduled Tasks remain the Velocity lifecycle owner.
The abandoned direct Velocity management experiment is excluded.
Existing Canary migration guards, backups and rollback checks are retained.

The Stable update feed uses a detached Ed25519 signature and artifact
SHA256/size verification. This is not Windows Authenticode code signing.
Preserve the existing trusted deployment public key and existing settings.
Never upload server/client configuration, worlds, tokens or private keys.
