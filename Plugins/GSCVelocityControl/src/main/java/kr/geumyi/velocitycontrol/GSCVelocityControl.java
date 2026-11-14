package kr.geumyi.velocitycontrol;

import com.google.inject.Inject;
import com.velocitypowered.api.event.Subscribe;
import com.velocitypowered.api.event.connection.PreLoginEvent;
import com.velocitypowered.api.event.proxy.ProxyInitializeEvent;
import com.velocitypowered.api.event.proxy.ProxyShutdownEvent;
import com.velocitypowered.api.plugin.annotation.DataDirectory;
import com.velocitypowered.api.proxy.ProxyServer;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import net.kyori.adventure.text.Component;
import org.slf4j.Logger;

import java.io.IOException;
import java.io.InputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.Properties;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/** Local-only, token-authenticated status and graceful shutdown. No command console. */
public final class GSCVelocityControl {
    private final ProxyServer proxy;
    private final Logger logger;
    private final Path dataDirectory;
    private final long pid = ProcessHandle.current().pid();
    private final long startTime = ProcessHandle.current().info().startInstant().orElseThrow().toEpochMilli();
    private final AtomicBoolean draining = new AtomicBoolean();
    private HttpServer http;
    private ThreadPoolExecutor executor;
    private byte[] authorization;
    private String directory;

    @Inject
    public GSCVelocityControl(ProxyServer proxy, Logger logger, @DataDirectory Path dataDirectory) {
        this.proxy = proxy;
        this.logger = logger;
        this.dataDirectory = dataDirectory;
    }

    @Subscribe
    public void initialize(ProxyInitializeEvent event) {
        try {
            Properties config = new Properties();
            // The Host creates this file only during the explicit prepare action.
            try (InputStream input = Files.newInputStream(dataDirectory.resolve("control.properties"))) {
                config.load(input);
            }
            String token = config.getProperty("token", "");
            int port = Integer.parseInt(config.getProperty("port", "0"));
            if (!token.matches("[0-9a-f]{64}") || port < 1024 || port > 65535) {
                throw new IllegalArgumentException("invalid local control configuration");
            }
            directory = Path.of("").toRealPath().toString();
            authorization = ("Bearer " + token).getBytes(StandardCharsets.US_ASCII);
            http = HttpServer.create(new InetSocketAddress(InetAddress.getByName("127.0.0.1"), port), 8);
            executor = new ThreadPoolExecutor(1, 2, 15, TimeUnit.SECONDS,
                    new ArrayBlockingQueue<>(16), r -> {
                Thread thread = new Thread(r, "gsc-local-control");
                thread.setDaemon(true);
                return thread;
            });
            http.setExecutor(executor);
            http.createContext("/", this::handle);
            http.start();
            logger.info("GSC local control enabled on loopback port {}", port);
        } catch (Exception e) {
            // Never log config values or exception data that could contain the token.
            if (http != null) http.stop(0);
            if (executor != null) executor.shutdownNow();
            http = null;
            logger.warn("GSC local control disabled: missing/invalid configuration or unavailable loopback port.");
        }
    }

    private void handle(HttpExchange exchange) throws IOException {
        try (exchange) {
            String auth = exchange.getRequestHeaders().getFirst("Authorization");
            if (!exchange.getRemoteAddress().getAddress().isLoopbackAddress()
                    || exchange.getRequestHeaders().containsKey("Origin")
                    || auth == null || auth.length() != authorization.length
                    || !MessageDigest.isEqual(authorization, auth.getBytes(StandardCharsets.US_ASCII))) {
                reply(exchange, 403, "{\"error\":\"forbidden\"}");
                return;
            }
            if (exchange.getRequestURI().getRawQuery() != null) {
                reply(exchange, 400, "{\"error\":\"query_not_supported\"}");
                return;
            }
            String path = exchange.getRequestURI().getPath();
            if ("/status".equals(path) && "GET".equals(exchange.getRequestMethod())) {
                reply(exchange, 200, "{\"pid\":" + pid + ",\"start_time\":" + startTime
                        + ",\"directory\":" + quote(directory) + ",\"players\":" + proxy.getPlayerCount()
                        + ",\"java_port\":" + proxy.getBoundAddress().getPort()
                        + ",\"stopping\":" + draining.get() + "}");
            } else if ("/shutdown".equals(path) && "POST".equals(exchange.getRequestMethod())) {
                if (!Long.toString(pid).equals(exchange.getRequestHeaders().getFirst("X-GSC-Expected-PID"))
                        || !Long.toString(startTime).equals(exchange.getRequestHeaders().getFirst("X-GSC-Expected-Start"))) {
                    reply(exchange, 409, "{\"error\":\"process_changed\"}");
                    return;
                }
                if (proxy.getPlayerCount() != 0) {
                    reply(exchange, 409, "{\"error\":\"players_connected\"}");
                    return;
                }
                if (!draining.compareAndSet(false, true)) {
                    reply(exchange, 409, "{\"error\":\"already_stopping\"}");
                    return;
                }
                // Finish the HTTP response before Velocity tears down the plugin.
                reply(exchange, 202, "{\"accepted\":true}");
                proxy.getScheduler().buildTask(this, () -> {
                    if (proxy.getPlayerCount() == 0) proxy.shutdown();
                    else draining.set(false); // A login already in progress won the race. Leave it running.
                }).delay(250, TimeUnit.MILLISECONDS).schedule();
            } else {
                reply(exchange, 404, "{\"error\":\"not_found\"}");
            }
        } catch (RuntimeException e) {
            logger.warn("GSC local control request failed.");
        }
    }

    @Subscribe
    public void preLogin(PreLoginEvent event) {
        if (draining.get()) {
            event.setResult(PreLoginEvent.PreLoginComponentResult.denied(Component.text("Proxy maintenance in progress.")));
        }
    }

    @Subscribe
    public void shutdown(ProxyShutdownEvent event) {
        if (http != null) http.stop(0);
        if (executor != null) executor.shutdownNow();
    }

    private static void reply(HttpExchange exchange, int status, String body) throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
        exchange.getResponseHeaders().set("Cache-Control", "no-store");
        exchange.sendResponseHeaders(status, bytes.length);
        exchange.getResponseBody().write(bytes);
    }

    static String quote(String value) {
        StringBuilder out = new StringBuilder("\"");
        for (char c : value.toCharArray()) {
            switch (c) {
                case '\\': out.append("\\\\"); break;
                case '"': out.append("\\\""); break;
                case '\n': out.append("\\n"); break;
                case '\r': out.append("\\r"); break;
                case '\t': out.append("\\t"); break;
                default:
                    if (c < 32) out.append(String.format("\\u%04x", (int)c));
                    else out.append(c);
            }
        }
        return out.append('"').toString();
    }
}
