package kr.geumyi.discordstatus;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;

final class DirectWebhook implements AutoCloseable {
    private final GeumyiDiscordStatus plugin;
    private final ExecutorService executor;
    private final HttpClient client;
    private volatile boolean closed;

    DirectWebhook(GeumyiDiscordStatus plugin) {
        this.plugin = plugin;
        this.executor = Executors.newSingleThreadExecutor(r -> {
            Thread t = new Thread(r, "GDS-Webhook");
            t.setDaemon(true);
            return t;
        });
        this.client = HttpClient.newBuilder()
                .executor(executor)
                .connectTimeout(Duration.ofMillis(1200))
                .build();
    }

    void sendEvent(String title, String message, int color) {
        if (closed) return;
        if (!plugin.getConfig().getBoolean("discord.direct-events.enabled", false)) return;
        String url = plugin.getConfig().getString("discord.direct-events.webhook-url", "");
        if (url == null || url.isBlank()) return;
        String username = plugin.getConfig().getString("discord.direct-events.username", "SDC Server Status");
        String json = "{\"username\":\"" + Text.json(username) + "\",\"allowed_mentions\":{\"parse\":[]},\"embeds\":[{\"title\":\"" +
                Text.json(title) + "\",\"description\":\"" + Text.json(message) + "\",\"color\":" + color + "}]}";
        try {
            executor.execute(() -> {
                try {
                    HttpRequest req = HttpRequest.newBuilder(URI.create(url.trim()))
                            .timeout(Duration.ofMillis(2500))
                            .header("Content-Type", "application/json; charset=UTF-8")
                            .POST(HttpRequest.BodyPublishers.ofString(json, StandardCharsets.UTF_8))
                            .build();
                    client.sendAsync(req, HttpResponse.BodyHandlers.discarding())
                            .exceptionally(error -> { plugin.debug("webhook failed: " + error.getMessage()); return null; });
                } catch (Throwable t) {
                    plugin.debug("webhook build failed: " + t.getMessage());
                }
            });
        } catch (RejectedExecutionException ignored) {
            plugin.debug("webhook executor closed");
        }
    }

    @Override public void close() {
        if (closed) return;
        closed = true;
        executor.shutdown();
    }
}
