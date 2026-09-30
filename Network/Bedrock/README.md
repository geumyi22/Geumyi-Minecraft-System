# Day 10 Bedrock foundation

This phase stages the Bedrock entrypoint without changing live firewall/router
rules or backend files.

## Chosen topology

```text
Bedrock UDP 19132
       |
 Geyser-Velocity
       |
 Floodgate-Velocity
       |
    Velocity
       |
     Lobby
    /     \
 Wild  Playground
```

Geyser and Floodgate live on Velocity only. Backend Floodgate is intentionally
not installed because the current Geumyi plugins do not use the Floodgate API.

## Protocol compatibility

Current Geyser documentation says Geyser emulates a Java 26.2 client. The
backends are Paper 26.3, so the backends need to accept an older 26.2 client.

The approved compatibility pair for this Day 10 baseline is:

- ViaVersion 5.12.0
- ViaBackwards 5.12.0

ViaBackwards 5.12.0 explicitly added 26.3 server support and requires
ViaVersion. Both JARs are staged for each Paper backend: Lobby, Wild and
Playground.

## Geyser/Floodgate selection

`tools/day10/prepare_bedrock_foundation.ps1` resolves the latest promoted/default
build from GeyserMC's official Downloads API at staging time and verifies the
SHA-256 published by that API.

It stages:

- `proxy-plugins/Geyser-Velocity.jar`
- `proxy-plugins/floodgate-velocity.jar`
- `backend-plugins/ViaVersion-5.12.0.jar`
- `backend-plugins/ViaBackwards-5.12.0.jar`
- `geyser-required-overrides.yml`
- `bedrock-plan.json`

The two Via JARs use pinned immutable GitHub Release URLs and pinned SHA-256
digests.

## Required Geyser settings after first proxy startup

Geyser's generated config remains authoritative. The deployment step patches
only the required values:

```yaml
bedrock:
  address: 0.0.0.0
  port: 19132
  clone-remote-port: false

remote:
  address: auto
  auth-type: floodgate
```

With Floodgate installed on the same Velocity instance, Geyser's current config
also supports automatic Floodgate discovery when `remote.address` is `auto`.

## Security

- Floodgate's key material is runtime-only and must never be committed.
- Backend Paper ports remain localhost-only.
- Public Bedrock exposure is UDP 19132 on Geyser/Velocity only.
- This staging phase does not open Windows Firewall or router ports.
- Java and Bedrock both enter Lobby first.
