# Lobby backend

Day 10 introduces one new Minecraft world/server: **Lobby**.

## Purpose

- Every successful public login enters Lobby first.
- Lobby always places the player at the central spawn.
- Lobby provides the Wild / Playground selector.
- Wild and Playground worlds remain unchanged.
- Lobby is a backend behind Velocity and must not be exposed directly.

## Candidate local ports

- Java: `127.0.0.1:25569`
- RCON: `127.0.0.1:25579`
- GDS API: reserved for later integration; not required by the first Lobby build.

## Required files at runtime

- Paper 26.3 as `paper.jar`
- `GeumyiLobby-0.1.0.jar` in `plugins/`
- generated Velocity forwarding secret applied to Paper modern forwarding config

## Important security transition

The template already uses `online-mode=false` because authentication belongs to
Velocity in the final network. Do not expose this backend publicly. During the
actual cutover, Paper modern forwarding must be enabled with the same secret as
Velocity and the server stays bound to `127.0.0.1`.

## Lobby map

The first GeumyiLobby build generates a compact floating/plaza-style hub at the
configured spawn:

- central quartz/stone plaza
- safety barrier edge
- Wild nature gate
- Playground colored quartz gate
- four decorative trees
- compass server selector
- walking into either gate also requests a server transfer

The map generator only runs on the dedicated Lobby server. It does not touch
Wild or Playground.
