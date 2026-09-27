Geumyi Server Center v4.2.3
Stability & Optimization Update

4.2.3 핵심 변경
- 서버 상태 텔레메트리에서 4초 주기의 PowerShell/CIM 외부 프로세스 실행을 제거했습니다.
- TCP/UDP 리스너, Java 메모리/CPU/스레드/핸들, Windows CPU/RAM/디스크/업타임을 네이티브 Windows API로 조회합니다.
- Host가 실행하는 비대화형 보조 프로세스는 CREATE_NO_WINDOW/HideWindow 경로를 사용하도록 정리했습니다.
- GeumyiStatusAgent 0.5.4의 Discord 상태 메시지 단일 PATCH/복구 로직을 포함합니다. 일시적 429/5xx 실패에서 중복 상태 메시지를 만들지 않습니다.
- 메인컴 / 서버컴 / 둘 다 설치 모드는 모두 동일한 4.2.3 바이너리 세트를 사용합니다.
- 기존 메인컴을 4.2.3으로 업데이트할 때 저장된 Host URL과 DPAPI 보호 API 토큰을 유지할 수 있습니다.
- 기존 서버 설정, 서버 목록, 토큰, Minecraft 월드/plugins/start.bat은 보존합니다.


GSCM mobile-backend release built on the v4.1.5 reliability baseline.

Coordinated baseline
- GeumyiServerCenter 4.2.3
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
