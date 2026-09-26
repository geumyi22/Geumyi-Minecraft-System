package kr.geumyi.discordstatus;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Duration;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

final class BridgeReporter implements AutoCloseable {
    private final GeumyiDiscordStatus plugin;
    private final ScheduledExecutorService executor;
    private volatile HttpClient client;
    private volatile boolean configuredEnabled;
    private volatile String configuredEndpoint = "";
    private volatile String configuredSecret = "";
    private volatile int requestTimeoutMs = 1800;
    private volatile int maxInFlightConfigured = 8;
    private volatile int maxAttemptsConfigured = 3;
    private volatile long retryBaseDelayMs = 500L;
    private final AtomicInteger inFlight = new AtomicInteger();
    private final AtomicLong sent = new AtomicLong();
    private final AtomicLong failed = new AtomicLong();
    private volatile long lastSuccessMillis;
    private volatile long lastFailureMillis;
    private volatile String lastError = "";
    private volatile boolean closed;

    BridgeReporter(GeumyiDiscordStatus plugin) {
        this.plugin = plugin;
        ThreadFactory tf = r -> {
            Thread t = new Thread(r, "GDS-Bridge");
            t.setDaemon(true);
            return t;
        };
        this.executor = Executors.newSingleThreadScheduledExecutor(tf);
        rebuild();
    }

    void rebuild() {
        if (closed) return;
        String bridgeUrl = plugin.getConfig().getString("bridge.url", "");
        boolean legacyAgentMode = bridgeUrl == null || bridgeUrl.isBlank();
        int connect = legacyAgentMode
                ? Math.max(250, plugin.getConfig().getInt("agent.connect-timeout-ms", 1200))
                : Math.max(250, plugin.getConfig().getInt("bridge.connect-timeout-ms", 1200));
        this.requestTimeoutMs = legacyAgentMode
                ? Math.max(500, plugin.getConfig().getInt("agent.request-timeout-ms", 1800))
                : Math.max(500, plugin.getConfig().getInt("bridge.request-timeout-ms", 1800));
        this.maxInFlightConfigured = Math.max(1, plugin.getConfig().getInt("bridge.max-in-flight", 8));
        this.maxAttemptsConfigured = Math.max(1, plugin.getConfig().getInt("bridge.retry.max-attempts", 3));
        this.retryBaseDelayMs = Math.max(100L, plugin.getConfig().getLong("bridge.retry.base-delay-ms", 500L));
        this.configuredEnabled = legacyAgentMode
                ? plugin.getConfig().getBoolean("agent.enabled", true)
                : plugin.getConfig().getBoolean("bridge.enabled", true);
        String url = legacyAgentMode ? plugin.getConfig().getString("agent.url", "") : bridgeUrl;
        this.configuredEndpoint = url == null ? "" : url.trim();
        String sec = plugin.getConfig().getString("bridge.secret", "");
        if (sec == null || sec.isBlank()) sec = plugin.getConfig().getString("agent.secret", "");
        this.configuredSecret = sec == null ? "" : sec;
        this.client = HttpClient.newBuilder()
                .executor(executor)
                .connectTimeout(Duration.ofMillis(connect))
                .version(HttpClient.Version.HTTP_1_1)
                .build();
    }

    boolean enabled() { return configuredEnabled && !configuredEndpoint.isBlank(); }
    String endpoint() { return configuredEndpoint; }
    String secret() { return configuredSecret; }

    void sendAsync(Map<String, String> payload) {
        if (closed || !enabled()) return;
        if (inFlight.incrementAndGet() > maxInFlightConfigured) {
            inFlight.decrementAndGet();
            failed.incrementAndGet();
            lastFailureMillis = System.currentTimeMillis();
            lastError = "bridge queue full";
            return;
        }
        Map<String, String> copy = Map.copyOf(payload);
        try {
            executor.execute(() -> sendAttempt(copy, 1));
        } catch (RejectedExecutionException e) {
            finishFailure("bridge executor closed");
            inFlight.decrementAndGet();
        }
    }

    private void sendAttempt(Map<String, String> payload, int attempt) {
        HttpRequest request;
        try {
            request = request(payload);
        } catch (Throwable t) {
            finishFailure(t.getMessage());
            inFlight.decrementAndGet();
            return;
        }
        client.sendAsync(request, HttpResponse.BodyHandlers.discarding())
                .whenComplete((response, error) -> {
                    if (error == null && response != null && response.statusCode() >= 200 && response.statusCode() < 300) {
                        sent.incrementAndGet();
                        lastSuccessMillis = System.currentTimeMillis();
                        lastError = "";
                        inFlight.decrementAndGet();
                        return;
                    }
                    int code = response == null ? -1 : response.statusCode();
                    boolean retryable = error != null || code == 408 || code == 429 || code >= 500;
                    if (!closed && retryable && attempt < maxAttemptsConfigured) {
                        long delay = Math.min(10_000L, retryBaseDelayMs << Math.min(Math.max(0, attempt - 1), 5));
                        try {
                            executor.schedule(() -> sendAttempt(payload, attempt + 1), delay, TimeUnit.MILLISECONDS);
                            return;
                        } catch (RejectedExecutionException ignored) {}
                    }
                    String detail = error != null ? error.getMessage() : "HTTP " + code;
                    finishFailure(detail);
                    inFlight.decrementAndGet();
                });
    }

    private HttpRequest request(Map<String, String> payload) throws Exception {
        String body = Text.form(payload);
        int timeout = requestTimeoutMs;
        String secret = configuredSecret;
        long ts = System.currentTimeMillis();
        String nonce = UUID.randomUUID().toString();
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create(configuredEndpoint))
                .timeout(Duration.ofMillis(timeout))
                .header("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
                .header("User-Agent", "GeumyiDiscordStatus/" + GeumyiDiscordStatus.VERSION)
                .header("X-Geumyi-Protocol", Integer.toString(GeumyiDiscordStatus.PROTOCOL_VERSION))
                .header("X-GDS-Secret", secret)
                .header("X-GDS-Timestamp", Long.toString(ts))
                .header("X-GDS-Nonce", nonce);
        if (!secret.isBlank()) b.header("X-GDS-Signature", hmac(secret, ts + "\n" + nonce + "\n" + body));
        return b.POST(HttpRequest.BodyPublishers.ofString(body, StandardCharsets.UTF_8)).build();
    }

    private static String hmac(String secret, String data) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        byte[] out = mac.doFinal(data.getBytes(StandardCharsets.UTF_8));
        StringBuilder b = new StringBuilder(out.length * 2);
        for (byte x : out) b.append(String.format("%02x", x & 0xff));
        return b.toString();
    }

    private void finishFailure(String detail) {
        failed.incrementAndGet();
        lastFailureMillis = System.currentTimeMillis();
        lastError = detail == null ? "unknown" : detail;
        plugin.debug("bridge send failed: " + lastError);
    }

    boolean flush(long timeoutMs) {
        long deadline = System.currentTimeMillis() + Math.max(0L, timeoutMs);
        while (inFlight.get() > 0 && System.currentTimeMillis() < deadline) {
            try { Thread.sleep(20L); }
            catch (InterruptedException e) { Thread.currentThread().interrupt(); break; }
        }
        return inFlight.get() == 0;
    }

    long sentCount() { return sent.get(); }
    long failedCount() { return failed.get(); }
    int inFlight() { return inFlight.get(); }
    long lastSuccessMillis() { return lastSuccessMillis; }
    long lastFailureMillis() { return lastFailureMillis; }
    String lastError() { return lastError; }


    static boolean constantTimeEquals(String a, String b) {
        if (a == null || b == null) return false;
        return MessageDigest.isEqual(a.getBytes(StandardCharsets.UTF_8), b.getBytes(StandardCharsets.UTF_8));
    }

    @Override public void close() {
        if (closed) return;
        closed = true;
        try { executor.schedule(executor::shutdown, 2, TimeUnit.SECONDS); }
        catch (RejectedExecutionException ignored) { executor.shutdown(); }
    }
}
