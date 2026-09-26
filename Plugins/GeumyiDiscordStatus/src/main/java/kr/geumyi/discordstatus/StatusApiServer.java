package kr.geumyi.discordstatus;

import com.sun.net.httpserver.Headers;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import org.bukkit.Bukkit;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.*;

final class StatusApiServer {
    private final GeumyiDiscordStatus plugin;
    private HttpServer server;
    private ExecutorService executor;
    private volatile String configuredToken = "";
    private volatile boolean allowUnauthenticatedLoopback = true;
    private volatile boolean allowUnauthenticatedActions = false;
    private volatile boolean actionsEnabled = true;
    private volatile int actionTimeoutMs = 3000;
    private final ConcurrentHashMap<String, CachedAction> actionCache = new ConcurrentHashMap<>();

    StatusApiServer(GeumyiDiscordStatus plugin) { this.plugin = plugin; }

    synchronized void start() {
        stop();
        if (!plugin.getConfig().getBoolean("api.enabled", true)) return;
        String bind = plugin.getConfig().getString("api.bind", "127.0.0.1");
        if (bind == null || bind.isBlank()) bind = "127.0.0.1";
        int port = plugin.getConfig().getInt("api.port", 8766);
        String token = plugin.getConfig().getString("api.token", "");
        configuredToken = token == null ? "" : token.trim();
        allowUnauthenticatedLoopback = plugin.getConfig().getBoolean("api.allow-unauthenticated-loopback", true);
        allowUnauthenticatedActions = plugin.getConfig().getBoolean("api.allow-unauthenticated-actions", false);
        actionsEnabled = plugin.getConfig().getBoolean("api.actions-enabled", true);
        actionTimeoutMs = Math.max(500, plugin.getConfig().getInt("api.action-timeout-ms", 3000));
        token = configuredToken;
        try {
            InetAddress address = InetAddress.getByName(bind.trim());
            if (!address.isLoopbackAddress() && token.isBlank()) {
                plugin.getLogger().warning("GDS API가 loopback이 아닌 주소에 바인드되었지만 api.token이 비어 있어 API 시작을 거부합니다.");
                return;
            }
            server = HttpServer.create(new InetSocketAddress(address, port), 0);
            server.createContext("/health", this::health);
            server.createContext("/api/status", ex -> guardedGet(ex, plugin::legacyStatusJson));
            server.createContext("/api/v4/status", ex -> guardedGet(ex, plugin::v4StatusJson));
            server.createContext("/api/v4/capabilities", ex -> guardedGet(ex, plugin::capabilitiesJson));
            server.createContext("/api/v4/players", ex -> guardedGet(ex, plugin::playersJson));
            server.createContext("/api/v4/worlds", ex -> guardedGet(ex, plugin::worldsJson));
            server.createContext("/api/v4/plugins", ex -> guardedGet(ex, plugin::pluginsJson));
            server.createContext("/api/v4/datapacks", ex -> guardedGet(ex, plugin::datapacksJson));
            server.createContext("/api/v4/events", this::events);
            server.createContext("/api/v4/diagnostics", ex -> guardedGet(ex, plugin::diagnosticsJson));
            server.createContext("/api/v4/gst", ex -> guardedGet(ex, plugin::gstJson));
            server.createContext("/api/v4/action", this::action);
            executor = Executors.newFixedThreadPool(Math.max(2, plugin.getConfig().getInt("api.worker-threads", 4)), r -> {
                Thread t = new Thread(r, "GDS-HTTP");
                t.setDaemon(true);
                return t;
            });
            server.setExecutor(executor);
            server.start();
            plugin.getLogger().info("GDS API listening on " + bind + ":" + port + " (legacy + protocol v4)");
        } catch (Throwable t) {
            plugin.getLogger().warning("GDS API 시작 실패: " + t.getMessage());
            stop();
        }
    }

    synchronized void restart() { start(); }

    synchronized void stop() {
        if (server != null) {
            server.stop(0);
            server = null;
        }
        if (executor != null) {
            executor.shutdown();
            executor = null;
        }
    }

    private void health(HttpExchange ex) throws IOException {
        if (!"GET".equalsIgnoreCase(ex.getRequestMethod())) { methodNotAllowed(ex, "GET"); return; }
        respond(ex, 200, "text/plain; charset=UTF-8", "OK\n");
    }

    private void guardedGet(HttpExchange ex, BodySupplier supplier) throws IOException {
        if (!"GET".equalsIgnoreCase(ex.getRequestMethod())) { methodNotAllowed(ex, "GET"); return; }
        if (!authorizedRead(ex)) { unauthorized(ex); return; }
        try { respond(ex, 200, "application/json; charset=UTF-8", supplier.get()); }
        catch (Throwable t) { respond(ex, 500, "application/json; charset=UTF-8", errorJson("internal_error", t.getMessage())); }
    }

    private void events(HttpExchange ex) throws IOException {
        if (!"GET".equalsIgnoreCase(ex.getRequestMethod())) { methodNotAllowed(ex, "GET"); return; }
        if (!authorizedRead(ex)) { unauthorized(ex); return; }
        long since = 0L;
        String query = ex.getRequestURI().getRawQuery();
        if (query != null) {
            Map<String, String> q = Text.parseForm(query);
            try { since = Long.parseLong(q.getOrDefault("since", "0")); } catch (NumberFormatException ignored) {}
        }
        respond(ex, 200, "application/json; charset=UTF-8", plugin.eventsJson(since));
    }

    private void action(HttpExchange ex) throws IOException {
        if (!"POST".equalsIgnoreCase(ex.getRequestMethod())) { methodNotAllowed(ex, "POST"); return; }
        if (!actionsEnabled) {
            respond(ex, 403, "application/json; charset=UTF-8", errorJson("actions_disabled", "Remote actions are disabled"));
            return;
        }
        if (!authorizedAction(ex)) { unauthorized(ex); return; }

        byte[] bytes;
        try (InputStream in = ex.getRequestBody()) {
            bytes = in.readNBytes(65_537);
        }
        if (bytes.length > 65_536) {
            respond(ex, 413, "application/json; charset=UTF-8", errorJson("payload_too_large", "Request body is limited to 64 KiB"));
            return;
        }
        String body = new String(bytes, StandardCharsets.UTF_8);
        String contentType = ex.getRequestHeaders().getFirst("Content-Type");
        Map<String, String> params;
        try {
            params = contentType != null && contentType.toLowerCase().contains("application/json") ? Text.parseFlatJson(body) : Text.parseForm(body);
        } catch (IllegalArgumentException e) {
            respond(ex, 400, "application/json; charset=UTF-8", errorJson("invalid_body", e.getMessage()));
            return;
        }

        String requestId = ex.getRequestHeaders().getFirst("X-GSC-Request-Id");
        if (requestId == null || requestId.isBlank()) requestId = params.getOrDefault("request_id", "");
        if (requestId.isBlank()) requestId = UUID.randomUUID().toString();
        requestId = sanitizeRequestId(requestId);
        if (requestId.isBlank()) requestId = UUID.randomUUID().toString();
        final String rid = requestId;
        final String remote = String.valueOf(ex.getRemoteAddress());
        final String actionName = params.getOrDefault("action", "");
        final String actor = auditHeader(ex, "X-GSC-Actor", "unknown");
        final String actorId = auditHeader(ex, "X-GSC-Actor-Id", "");
        final String source = auditHeader(ex, "X-GSC-Source", "gds-api");

        pruneCache();
        CachedAction cached = actionCache.get(rid);
        if (cached != null && System.currentTimeMillis() - cached.timestamp < 300_000L) {
            respond(ex, cached.status, "application/json; charset=UTF-8", cached.body);
            return;
        }

        CompletableFuture<ActionResult> future = new CompletableFuture<>();
        Map<String, String> immutable = Map.copyOf(params);
        // Cache and audit the eventual result even if the HTTP caller times out. This prevents
        // an idempotent retry from executing the Minecraft action twice during a lag spike.
        future.whenComplete((result, error) -> {
            ActionResult finalResult = result;
            if (finalResult == null) {
                String detail = error == null || error.getMessage() == null ? "작업 실행 실패" : error.getMessage();
                finalResult = ActionResult.fail("action_failed", detail);
            }
            int finalStatus = finalResult.ok() ? 200 : 400;
            String finalResponse = actionResponse(rid, finalResult);
            actionCache.put(rid, new CachedAction(System.currentTimeMillis(), finalStatus, finalResponse));
            plugin.auditAction(remote, rid, actionName, actor, actorId, source, finalResult);
        });

        try {
            Bukkit.getScheduler().runTask(plugin, () -> {
                try { future.complete(plugin.performAction(immutable)); }
                catch (Throwable t) { future.complete(ActionResult.fail("action_failed", t.getMessage())); }
            });
        } catch (Throwable t) {
            ActionResult failed = ActionResult.fail("server_unavailable", t.getMessage());
            future.complete(failed);
            respond(ex, 503, "application/json; charset=UTF-8", actionResponse(rid, failed));
            return;
        }

        ActionResult result;
        try {
            result = future.get(actionTimeoutMs, TimeUnit.MILLISECONDS);
        } catch (TimeoutException e) {
            String response = "{\"ok\":false,\"request_id\":\"" + Text.json(rid) +
                    "\",\"code\":\"action_timeout\",\"message\":\"Minecraft main thread did not answer in time; the request id remains protected against duplicate execution\"}";
            // The eventual completion callback will replace this temporary timeout entry with
            // the real result. Until then a retry receives the timeout instead of running twice.
            actionCache.put(rid, new CachedAction(System.currentTimeMillis(), 504, response));
            respond(ex, 504, "application/json; charset=UTF-8", response);
            return;
        } catch (Throwable t) {
            ActionResult failed = ActionResult.fail("action_failed", t.getMessage());
            respond(ex, 500, "application/json; charset=UTF-8", actionResponse(rid, failed));
            return;
        }

        int status = result.ok() ? 200 : 400;
        respond(ex, status, "application/json; charset=UTF-8", actionResponse(rid, result));
    }

    private static String actionResponse(String requestId, ActionResult result) {
        return "{\"ok\":" + result.ok() + ",\"request_id\":\"" + Text.json(requestId) + "\",\"code\":\"" +
                Text.json(result.code()) + "\",\"message\":\"" + Text.json(result.message()) + "\"}";
    }

    private static String auditHeader(HttpExchange ex, String name, String fallback) {
        String value = ex.getRequestHeaders().getFirst(name);
        if (value == null || value.isBlank()) return fallback;
        StringBuilder b = new StringBuilder(Math.min(128, value.length()));
        for (int i = 0; i < value.length() && b.length() < 128; i++) {
            char c = value.charAt(i);
            if (c >= 0x20 && c != 0x7f && c != '\t' && c != '\r' && c != '\n') b.append(c);
        }
        String out = b.toString().trim();
        return out.isBlank() ? fallback : out;
    }

    private static String sanitizeRequestId(String value) {
        if (value == null) return "";
        StringBuilder b = new StringBuilder(Math.min(128, value.length()));
        for (int i = 0; i < value.length() && b.length() < 128; i++) {
            char c = value.charAt(i);
            if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
                    c == '-' || c == '_' || c == '.' || c == ':') b.append(c);
        }
        return b.toString();
    }

    private boolean authorizedRead(HttpExchange ex) {
        String token = configuredToken;
        if (token.isBlank()) {
            return allowUnauthenticatedLoopback && isLoopback(ex);
        }
        return matchesToken(ex, token);
    }

    private boolean authorizedAction(HttpExchange ex) {
        String token = configuredToken;
        if (token.isBlank()) {
            return allowUnauthenticatedActions && isLoopback(ex);
        }
        return matchesToken(ex, token);
    }

    private boolean matchesToken(HttpExchange ex, String token) {
        String auth = ex.getRequestHeaders().getFirst("Authorization");
        String header = ex.getRequestHeaders().getFirst("X-GDS-Token");
        String candidate = auth != null && auth.regionMatches(true, 0, "Bearer ", 0, 7) ? auth.substring(7).trim() : header;
        return BridgeReporter.constantTimeEquals(token, candidate == null ? "" : candidate.trim());
    }

    private boolean isLoopback(HttpExchange ex) {
        try { return ex.getRemoteAddress().getAddress().isLoopbackAddress(); }
        catch (Throwable t) { return false; }
    }

    private void pruneCache() {
        if (actionCache.size() < 256) return;
        long cutoff = System.currentTimeMillis() - 300_000L;
        actionCache.entrySet().removeIf(e -> e.getValue().timestamp < cutoff);
        if (actionCache.size() > 512) actionCache.clear();
    }

    private void unauthorized(HttpExchange ex) throws IOException {
        ex.getResponseHeaders().set("WWW-Authenticate", "Bearer realm=\"GDS\"");
        respond(ex, 401, "application/json; charset=UTF-8", errorJson("unauthorized", "Authentication required"));
    }

    private void methodNotAllowed(HttpExchange ex, String allow) throws IOException {
        ex.getResponseHeaders().set("Allow", allow);
        respond(ex, 405, "application/json; charset=UTF-8", errorJson("method_not_allowed", "Use " + allow));
    }

    private void respond(HttpExchange ex, int status, String contentType, String body) throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        Headers h = ex.getResponseHeaders();
        h.set("Content-Type", contentType);
        h.set("Cache-Control", "no-store");
        h.set("X-Content-Type-Options", "nosniff");
        h.set("X-Geumyi-Protocol", Integer.toString(GeumyiDiscordStatus.PROTOCOL_VERSION));
        ex.sendResponseHeaders(status, bytes.length);
        try (OutputStream out = ex.getResponseBody()) { out.write(bytes); }
    }

    private static String errorJson(String code, String message) {
        return "{\"error\":\"" + Text.json(code) + "\",\"message\":\"" + Text.json(message == null ? "" : message) + "\"}";
    }

    @FunctionalInterface private interface BodySupplier { String get(); }
    private record CachedAction(long timestamp, int status, String body) {}
}
