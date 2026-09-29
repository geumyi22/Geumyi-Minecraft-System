Geumyi Server Center v4.2.4
Day 9 Transaction / Rollback Update

4.2.4 핵심 변경
- 자체 플러그인 업데이트를 파일별 교체가 아닌 서버 단위 transaction으로 처리합니다.
- 전체 대상 artifact를 먼저 다운로드/검증한 뒤 backup + staging을 완료해야 실제 교체를 시작합니다.
- transaction journal/pending state를 기록하고, GSC 또는 PC가 중단된 경우 다음 시작 전에 미완료 transaction을 자동 복구합니다.
- 새 버전 부팅 후 Java port + GST Diagnostics + GDS API health gate를 통과해야 업데이트를 최종 확정합니다.
- health 실패 시 서버를 정상 종료하고 이전 JAR 전체를 복원한 뒤 이전 버전으로 자동 재시작합니다.
- health 실패 release는 서버별 rejected-release로 보류하여 같은 잘못된 release의 재적용 루프를 막습니다.
- deployment manifest의 release_group / requires 정보를 검증하여 호환되지 않는 조합을 거부합니다.
- failure-injection 테스트로 부분 교체 중 실패 시 전체 원복을 검증합니다.

GSCM mobile-backend release built on the v4.1.5 reliability baseline.

Coordinated baseline
- GeumyiServerCenter 4.2.4
- GeumyiServerTools 1.1.1 HOTFIX
- GeumyiDiscordStatus 1.1.1
- GeumyiStatusAgent 0.5.4

GSCM / mobile foundation
- Port 8787 transport listens on all interfaces, but non-loopback requests are admitted only when mobile access is enabled and the source address is LAN/private/Tailscale/CGNAT.
- Windows firewall rule is restricted to LocalSubnet and Tailscale 100.64.0.0/10.
- Public Internet source addresses are rejected by the Host before API authentication is evaluated.
- RCON, GDS and Agent ports remain local and are never exposed to GSCM.
- Mobile access can be enabled/disabled without changing Minecraft server configuration.

Pairing v2
- 8-digit, one-time pairing codes.
- Default expiry: 5 minutes (configurable 60..3600 seconds).
- Pairing code remains visible in GSC until expiry/claim instead of disappearing on dashboard refresh.
- GSC exposes preferred LAN/Tailscale URLs and a gscm:// pairing URI.
- Pair claims are rate-limited per remote address.
- Each device receives its own revocable token; devices can be revoked/restored/deleted.

Control API v1 additions
- GET/POST /api/v1/mobile
- GET/POST /api/v1/pairing
- POST /api/v1/pairing/claim
- GET/POST /api/v1/devices
- GET/POST /api/v1/backups
- POST /api/v1/backups/verify
- POST /api/v1/backups/restore
- GET/POST /api/v1/automations
- GET /api/v1/metrics
- GET /api/v1/servers/{id}/console
- POST /api/v1/servers/{id}/player-action
- POST/DELETE /api/v1/servers/{id}/schedule
- GET /api/v1/servers/{id}/inventory
- force-stop / force-stop-launcher / cancel-schedule server actions

Player administration
- kick
- whitelist_add / whitelist_remove
- op / deop
- ban / pardon
- player-name validation and Audit logging

Server extensions
- ServerTools and DiscordStatus reported on all configured servers.
- Technology/Chemistry are exposed only for the wild server, matching the real deployment layout.

Retained from v4.1.5
- RCON is a management warning rather than a false server-health degradation.
- Native Windows RCON listener and Java process-memory fallbacks.
- max-players reconciliation against server.properties.
- background cached Windows telemetry and bounded latest.log tailing.
- deterministic Whole Shutdown and targeted GSC-owned Edge cleanup.
- GST Diagnostics v2, GDS bridge v4, Job Queue, WebSocket and Audit Log.

Security
- Do not port-forward 8787 to the public Internet.
- Use LAN or Tailscale.
- Remote calls require a Host API token or per-device token.
- Pairing claim is the only unauthenticated mobile endpoint and is limited to LAN/Tailscale, one-time codes and rate limiting.

v4.2.3 mobile pairing stabilization
- GSC desktop Remote/GDS page no longer rebuilds the whole GSCM section every 5 seconds.
- Pairing countdown now updates locally once per second without panel flicker.
- Built-in QR pairing: GSC renders a local/offline QR containing the gscm://pair claim URI.
- QR generation is dependency-free and does not send the pairing code to an external service.
- Mobile address advertisement excludes APIPA/link-local 169.254/16 and prioritizes Tailscale, then normal LAN IPv4.
- Existing v4.2.0 Control API and device tokens remain compatible.

v4.2.3 server-management fixes
- Force Stop now kills the GSC-tracked start.bat process tree first, then resolves Java by listener PID, tracked PID and cached Java telemetry.
- Force Stop no longer depends on a healthy/open Minecraft Java port plus a fresh stats cache, so STARTING/hung states can still be terminated.
- Every GSC server profile is synchronized into the integrated Agent catalog automatically. Newly added servers receive name, Java port, GDS API port and GSC-ID mapping.
- GeumyiStatusAgent 0.5.4 builds the Discord status board and slash-command server list from that managed catalog instead of assuming only wild/playground.
- Lifecycle countdown Discord messages are delivered directly with the Agent Discord bot configuration. RCON/GDS announce remains only a fallback.
- When a profile or managed GDS configuration changes, GSC restarts the Agent only when its managed configuration changed, then reloads changed GDS configurations where possible.
