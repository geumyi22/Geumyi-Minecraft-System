# Day 8 release/deployment foundation

This directory is the source-of-truth for artifacts promoted by the Day 8 release workflow.

## Security boundary

- CI build artifacts are not production releases by themselves.
- Release publication requires a persistent Android signing key and a deployment-manifest signing key.
- Private signing material belongs only in GitHub Actions secrets.
- Minecraft pre-start update must fail open: if the network, manifest, signature, checksum, or install step fails, the already installed server files remain usable and the server start continues.

## Required GitHub Actions secrets

Android:
- `ANDROID_RELEASE_KEYSTORE_B64`
- `ANDROID_RELEASE_STORE_PASSWORD`
- `ANDROID_RELEASE_KEY_ALIAS`
- `ANDROID_RELEASE_KEY_PASSWORD`

Deployment manifest:
- `DEPLOYMENT_ED25519_PRIVATE_KEY_B64` — base64 of an unencrypted PKCS#8 PEM Ed25519 private key.

The matching Ed25519 public key is configured on the GSC host. Never fetch the verification key from the same release that is being verified.

## Channels

`stable`, `beta`, and `canary` are encoded in the signed manifest. Per-server pin/hold policy is a later operations-UX layer; Day 8 establishes the signed release source and next-start updater foundation.
