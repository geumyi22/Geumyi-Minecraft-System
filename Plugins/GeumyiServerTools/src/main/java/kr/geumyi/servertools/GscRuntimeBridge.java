package kr.geumyi.servertools;

import java.io.BufferedWriter;
import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.time.Instant;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

import org.bukkit.Bukkit;
import org.bukkit.World;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import org.bukkit.plugin.Plugin;
import org.bukkit.scheduler.BukkitTask;

/**
 * File-based local runtime contract for GSC v4. All disk I/O is off the server thread.
 * This is intentionally one-way telemetry; remote actions stay behind authenticated GDS/GSC APIs.
 */
final class GscRuntimeBridge {
    private static final String PREFIX = "§8[§bGST§8] §r";
    private final GeumyiServerToolsV110 plugin;
    private final MaintenanceController maintenance;
    private final String sessionId = UUID.randomUUID().toString();
    private final long startedAt = System.currentTimeMillis();
    private final AtomicBoolean writeQueued = new AtomicBoolean();
    private final AtomicLong lastWriteOk = new AtomicLong();
    private final AtomicLong lastWriteFailed = new AtomicLong();
    private volatile boolean enabled;
    private volatile boolean stopReady;
    private volatile boolean stopSaveOk;
    private volatile String stopReason = "";
    private volatile String lastEventType = "startup";
    private volatile String lastEventMessage = "";
    private volatile boolean previousUncleanShutdown;
    private volatile DiagnosticsService.DiagnosticsSnapshot diagnostics;
    private volatile String lastStatusJson = "{}";
    private ExecutorService io;
    private BukkitTask captureTask;
    private Path runtimeDir;

    GscRuntimeBridge(GeumyiServerToolsV110 plugin, MaintenanceController maintenance) {
        this.plugin = plugin;
        this.maintenance = maintenance;
    }

    void start() {
        io = Executors.newSingleThreadExecutor(r -> {
            Thread t = new Thread(r, "GST-GSCv4-IO");
            t.setDaemon(true);
            return t;
        });
        reloadSettings();
        if (enabled) {
            submitIo(() -> {
                try {
                    Files.createDirectories(runtimeDir);
                    previousUncleanShutdown = Files.exists(runtimeDir.resolve("READY"));
                    Files.deleteIfExists(runtimeDir.resolve("STOPPED"));
                    Files.deleteIfExists(runtimeDir.resolve("stop-ready.json"));
                    writeCapabilities();
                    writeMarker("READY", "session=" + sessionId + "\nversion=1.1.1\n");
                    if (previousUncleanShutdown) {
                        lastEventType = "unclean_shutdown_detected";
                        lastEventMessage = "Previous GST session did not remove READY marker";
                    }
                } catch (Exception e) {
                    failed(e);
                }
            });
            restartCaptureTask();
            flushSoon();
        }
    }

    void stop() {
        if (captureTask != null) captureTask.cancel();
        captureTask = null;
        if (enabled) {
            RuntimeSnapshot s = capture();
            submitIo(() -> {
                try {
                    writeStatus(s, "STOPPING");
                    Files.deleteIfExists(runtimeDir.resolve("READY"));
                    writeMarker("STOPPED", "time=" + Instant.now() + "\nsession=" + sessionId + "\n");
                } catch (Exception e) {
                    failed(e);
                }
            });
        }
        if (io != null) {
            io.shutdown();
            try { io.awaitTermination(2, TimeUnit.SECONDS); }
            catch (InterruptedException e) { Thread.currentThread().interrupt(); }
        }
    }

    void reloadSettings() {
        enabled = plugin.getConfig().getBoolean("gsc-v4.enabled", true);
        String configured = plugin.getConfig().getString("gsc-v4.runtime-directory", "runtime");
        if (configured == null || configured.isBlank()) configured = "runtime";
        configured = configured.replace('\\', '/');
        if (configured.contains("..") || configured.startsWith("/") || configured.contains(":")) configured = "runtime";
        runtimeDir = new File(plugin.getDataFolder(), configured).toPath();
        restartCaptureTask();
    }

    private void restartCaptureTask() {
        if (captureTask != null) captureTask.cancel();
        captureTask = null;
        if (!enabled) return;
        int seconds = Math.max(2, plugin.getConfig().getInt("gsc-v4.interval-seconds", 5));
        captureTask = Bukkit.getScheduler().runTaskTimer(plugin, this::flushSoon, 1L, seconds * 20L);
    }

    void flushSoon() {
        if (!enabled || io == null || io.isShutdown()) return;
        RuntimeSnapshot snapshot = capture();
        if (!writeQueued.compareAndSet(false, true)) return;
        submitIo(() -> {
            try {
                Files.createDirectories(runtimeDir);
                writeStatus(snapshot, snapshot.health());
                DiagnosticsService.DiagnosticsSnapshot d = diagnostics;
                if (d != null) atomicWrite(runtimeDir.resolve("health-v2.json"), d.toJson() + "\n");
                lastWriteOk.set(System.currentTimeMillis());
            } catch (Exception e) {
                failed(e);
            } finally {
                writeQueued.set(false);
            }
        });
    }

    void recordEvent(String type, String title, String message) {
        lastEventType = safe(type, 80);
        lastEventMessage = safe(message, 500);
        if (!enabled || io == null || io.isShutdown()) return;
        long now = System.currentTimeMillis();
        String line = "{\"time\":" + now + ",\"session_id\":\"" + json(sessionId) + "\",\"type\":\"" + json(type)
                + "\",\"title\":\"" + json(title) + "\",\"message\":\"" + json(message) + "\"}\n";
        submitIo(() -> {
            try {
                Files.createDirectories(runtimeDir);
                rotateEventsIfNeeded();
                try (BufferedWriter w = Files.newBufferedWriter(runtimeDir.resolve("events.jsonl"), StandardCharsets.UTF_8,
                        StandardOpenOption.CREATE, StandardOpenOption.WRITE, StandardOpenOption.APPEND)) {
                    w.write(line);
                }
            } catch (Exception e) {
                failed(e);
            }
        });
    }

    void markStopReady(boolean saveOk, String reason) {
        stopReady = true;
        stopSaveOk = saveOk;
        stopReason = safe(reason, 500);
        if (!enabled) return;
        String json = "{\"ready\":true,\"save_ok\":" + saveOk + ",\"time\":" + System.currentTimeMillis()
                + ",\"session_id\":\"" + json(sessionId) + "\",\"reason\":\"" + json(stopReason) + "\"}\n";
        submitIo(() -> {
            try { atomicWrite(runtimeDir.resolve("stop-ready.json"), json); }
            catch (Exception e) { failed(e); }
        });
    }

    void clearStopReady() {
        stopReady = false;
        stopSaveOk = false;
        stopReason = "";
        if (!enabled || io == null) return;
        submitIo(() -> {
            try { Files.deleteIfExists(runtimeDir.resolve("stop-ready.json")); }
            catch (Exception e) { failed(e); }
        });
    }

    void updateDiagnostics(DiagnosticsService.DiagnosticsSnapshot snapshot) {
        diagnostics = snapshot;
    }

    void recordLagIncident(String eventType, DiagnosticsService.LagIncident incident) {
        if (incident == null || !enabled || io == null || io.isShutdown()) return;
        String line = incident.toJson(eventType, sessionId) + "\n";
        submitIo(() -> {
            try {
                Files.createDirectories(runtimeDir);
                rotateIfNeeded(runtimeDir.resolve("lag-events.jsonl"), runtimeDir.resolve("lag-events.previous.jsonl"),
                        Math.max(1, plugin.getConfig().getInt("lag-recorder.event-log-max-mb", 5)));
                try (BufferedWriter w = Files.newBufferedWriter(runtimeDir.resolve("lag-events.jsonl"), StandardCharsets.UTF_8,
                        StandardOpenOption.CREATE, StandardOpenOption.WRITE, StandardOpenOption.APPEND)) {
                    w.write(line);
                }
            } catch (Exception e) { failed(e); }
        });
    }

    String lastStatusJson() { return lastStatusJson; }

    boolean isEnabled() { return enabled; }
    boolean isHealthy() { return !enabled || lastWriteFailed.get() <= lastWriteOk.get(); }
    long lastWriteOk() { return lastWriteOk.get(); }
    Path runtimeDir() { return runtimeDir; }
    String sessionId() { return sessionId; }
    boolean previousUncleanShutdown() { return previousUncleanShutdown; }

    void sendStatus(CommandSender sender) {
        sender.sendMessage(PREFIX + "§bGSC v4 Runtime Bridge");
        sender.sendMessage("§7상태: " + (enabled ? (isHealthy() ? "§aREADY" : "§eDEGRADED") : "§8DISABLED"));
        sender.sendMessage("§7세션: §f" + sessionId);
        sender.sendMessage("§7Runtime: §f" + runtimeDir.toAbsolutePath());
        sender.sendMessage("§7마지막 기록: §f" + (lastWriteOk.get() == 0 ? "아직 없음" : Instant.ofEpochMilli(lastWriteOk.get())));
        sender.sendMessage("§7Stop ready: §f" + stopReady + (stopReady ? " / save=" + stopSaveOk : ""));
    }

    void sendCompactStatus(CommandSender sender) {
        if (!enabled) sender.sendMessage(PREFIX + "§7GSC v4 bridge: §8OFF");
        else if (isHealthy()) sender.sendMessage(PREFIX + "§7GSC v4 bridge: §aREADY §8| §7점검: " + (maintenance.isActive() ? "§eON" : "§aOFF"));
        else sender.sendMessage(PREFIX + "§7GSC v4 bridge: §eDEGRADED §8| §7/gst health 확인");
    }

    private RuntimeSnapshot capture() {
        int online = 0;
        int afk = 0;
        for (Player p : Bukkit.getOnlinePlayers()) {
            online++;
            try { if (plugin.isAfk(p)) afk++; } catch (Throwable ignored) {}
        }
        int worlds = 0;
        long loadedChunks = 0;
        long entities = 0;
        for (World w : Bukkit.getWorlds()) {
            worlds++;
            try { loadedChunks += w.getLoadedChunks().length; } catch (Throwable ignored) {}
            try { entities += w.getEntities().size(); } catch (Throwable ignored) {}
        }
        Runtime rt = Runtime.getRuntime();
        long used = rt.totalMemory() - rt.freeMemory();
        long max = rt.maxMemory();
        long freeDisk = plugin.getDataFolder().getUsableSpace();
        String gdsVersion = pluginVersion("GeumyiDiscordStatus");
        DiagnosticsService.DiagnosticsSnapshot d = diagnostics;
        boolean diagBad = d != null && ("CRITICAL".equals(d.grade()) || "DEGRADED".equals(d.grade()));
        String health = maintenance.isActive() ? "MAINTENANCE" : ((!isHealthy() || diagBad) ? "DEGRADED" : "HEALTHY");
        return new RuntimeSnapshot(System.currentTimeMillis(), online, afk, worlds, loadedChunks, entities,
                used, max, freeDisk, gdsVersion, health);
    }

    private void writeStatus(RuntimeSnapshot s, String state) throws Exception {
        DiagnosticsService.DiagnosticsSnapshot d = diagnostics;
        String performance = d == null ? "null" : d.toJson();
        String body = "{"
                + "\"schema\":2,"
                + "\"plugin\":\"GeumyiServerTools\",\"version\":\"1.1.1\","
                + "\"session_id\":\"" + json(sessionId) + "\","
                + "\"time\":" + s.time() + ",\"uptime_ms\":" + Math.max(0, s.time() - startedAt) + ","
                + "\"state\":\"" + json(state) + "\","
                + "\"minecraft_version\":\"" + json(Bukkit.getBukkitVersion()) + "\","
                + "\"server_version\":\"" + json(Bukkit.getVersion()) + "\","
                + "\"java_version\":\"" + json(System.getProperty("java.version", "")) + "\","
                + "\"players\":{\"online\":" + s.online() + ",\"afk\":" + s.afk() + "},"
                + "\"worlds\":{\"count\":" + s.worlds() + ",\"loaded_chunks\":" + s.loadedChunks() + ",\"entities\":" + s.entities() + "},"
                + "\"memory\":{\"used_bytes\":" + s.memoryUsed() + ",\"max_bytes\":" + s.memoryMax() + "},"
                + "\"disk_free_bytes\":" + s.diskFree() + ","
                + "\"maintenance\":{\"active\":" + maintenance.isActive() + ",\"reason\":\"" + json(maintenance.reason()) + "\"},"
                + "\"previous_unclean_shutdown\":" + previousUncleanShutdown + ","
                + "\"stop_ready\":{\"ready\":" + stopReady + ",\"save_ok\":" + stopSaveOk + ",\"reason\":\"" + json(stopReason) + "\"},"
                + "\"integrations\":{\"discord_status_version\":\"" + json(s.gdsVersion()) + "\"},"
                + "\"diagnostics_v2\":" + performance + ","
                + "\"latest_event\":{\"type\":\"" + json(lastEventType) + "\",\"message\":\"" + json(lastEventMessage) + "\"}"
                + "}\n";
        lastStatusJson = body.trim();
        atomicWrite(runtimeDir.resolve("status.json"), body);
    }

    private void writeCapabilities() throws Exception {
        String body = "{\"schema\":2,\"plugin\":\"GeumyiServerTools\",\"version\":\"1.1.1\","
                + "\"capabilities\":[\"afk_room\",\"performance_monitor\",\"performance_v2\",\"lag_spike_recorder\",\"diagnostics_v2\",\"chunk_diagnostics\",\"death_history\","
                + "\"sleep_manager\",\"idle_freeze\",\"maintenance\",\"prepare_stop\",\"health_selftest\","
                + "\"runtime_status\",\"incident_events\",\"unclean_shutdown_detection\"],"
                + "\"commands\":[\"status\",\"perf\",\"players\",\"scan\",\"deaths\",\"afk\",\"alerts\","
                + "\"backup\",\"countdown\",\"afkroom\",\"maintenance\",\"preparestop\",\"resume\",\"health\",\"bridge\",\"diagnose\",\"lag\"]}" + "\n";
        atomicWrite(runtimeDir.resolve("capabilities.json"), body);
    }

    private void rotateEventsIfNeeded() throws IOException {
        rotateIfNeeded(runtimeDir.resolve("events.jsonl"), runtimeDir.resolve("events.previous.jsonl"),
                Math.max(1, plugin.getConfig().getInt("gsc-v4.event-log-max-mb", 5)));
    }

    private static void rotateIfNeeded(Path f, Path old, long mb) throws IOException {
        if (!Files.isRegularFile(f)) return;
        if (Files.size(f) < mb * 1024L * 1024L) return;
        Files.deleteIfExists(old);
        Files.move(f, old, StandardCopyOption.REPLACE_EXISTING);
    }

    private void writeMarker(String name, String body) throws Exception {
        if (!plugin.getConfig().getBoolean("gsc-v4.write-ready-marker", true)) return;
        atomicWrite(runtimeDir.resolve(name), body);
    }

    private static void atomicWrite(Path target, String body) throws Exception {
        Files.createDirectories(target.getParent());
        Path tmp = target.resolveSibling(target.getFileName().toString() + ".tmp");
        Files.writeString(tmp, body, StandardCharsets.UTF_8, StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING, StandardOpenOption.WRITE);
        try {
            Files.move(tmp, target, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
        } catch (Exception e) {
            Files.move(tmp, target, StandardCopyOption.REPLACE_EXISTING);
        }
    }

    private String pluginVersion(String name) {
        try {
            Plugin p = Bukkit.getPluginManager().getPlugin(name);
            if (p == null || !p.isEnabled()) return "";
            return p.getDescription().getVersion();
        } catch (Throwable ignored) {
            return "";
        }
    }

    private void submitIo(Runnable r) {
        ExecutorService e = io;
        if (e == null || e.isShutdown()) return;
        try { e.execute(r); } catch (Throwable ignored) {}
    }

    private void failed(Throwable t) {
        lastWriteFailed.set(System.currentTimeMillis());
        plugin.getLogger().warning("GSC v4 runtime write failed: " + t.getMessage());
    }

    static String json(String s) {
        if (s == null) return "";
        StringBuilder b = new StringBuilder(s.length() + 16);
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '\\' -> b.append("\\\\");
                case '"' -> b.append("\\\"");
                case '\n' -> b.append("\\n");
                case '\r' -> b.append("\\r");
                case '\t' -> b.append("\\t");
                default -> {
                    if (c < 0x20) b.append(String.format("\\u%04x", (int)c));
                    else b.append(c);
                }
            }
        }
        return b.toString();
    }

    static int javaMajor(String v) {
        if (v == null || v.isBlank()) return 0;
        try {
            String[] p = v.split("\\.");
            if (p[0].equals("1") && p.length > 1) return Integer.parseInt(p[1]);
            String first = p[0].replaceAll("[^0-9].*$", "");
            return Integer.parseInt(first);
        } catch (Exception e) {
            return 0;
        }
    }

    private static String safe(String s, int max) {
        if (s == null) return "";
        String v = s.replace('\r', ' ').replace('\n', ' ').trim();
        return v.length() <= max ? v : v.substring(0, max);
    }

    private record RuntimeSnapshot(long time, int online, int afk, int worlds, long loadedChunks, long entities,
                                   long memoryUsed, long memoryMax, long diskFree, String gdsVersion, String health) {}
}
