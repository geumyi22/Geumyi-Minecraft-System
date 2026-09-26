package kr.geumyi.discordstatus;

import org.bukkit.Bukkit;
import org.bukkit.World;
import org.bukkit.command.Command;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.entity.PlayerDeathEvent;
import org.bukkit.event.player.PlayerJoinEvent;
import org.bukkit.event.player.PlayerQuitEvent;
import org.bukkit.plugin.Plugin;
import org.bukkit.plugin.PluginDescriptionFile;
import org.bukkit.plugin.java.JavaPlugin;
import org.bukkit.scheduler.BukkitTask;

import java.io.IOException;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.text.SimpleDateFormat;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.ThreadLocalRandom;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class GeumyiDiscordStatus extends JavaPlugin implements Listener {
    public static final String VERSION = "1.1.1";
    public static final int PROTOCOL_VERSION = 4;
    public static final String PREFIX = "§8[§bGDS§8] §r";
    private static final Pattern DURATION = Pattern.compile("^(\\d+)(s|m|h|d)?$", Pattern.CASE_INSENSITIVE);
    private static final long MAX_RESTART_SECONDS = 7L * 24 * 60 * 60;

    private final long startMillis = System.currentTimeMillis();
    private final String bootId = UUID.randomUUID().toString();
    private final EventBuffer eventBuffer = new EventBuffer(512);

    private String instanceId;
    private BridgeReporter reporter;
    private DirectWebhook webhook;
    private StatusApiServer apiServer;
    private GstRelay gstRelay;
    private AsyncFileLog fileLog;
    private BukkitTask sampleTask;
    private BukkitTask countdownTask;
    private volatile ServerSnapshot snapshot;
    private volatile boolean debugEnabled;
    private volatile boolean actionsLogEnabled = true;
    private volatile String serverIdCache = "survival";
    private volatile String serverNameCache = "금이 서버";
    private volatile int bridgeHeartbeatSecondsCache = 10;
    private volatile List<String> allowedActionsCache = List.of("broadcast", "save", "maintenance", "restart_schedule", "restart_cancel", "whitelist", "whitelist_add", "whitelist_remove", "kick");
    private volatile List<String> selfTestCache = List.of("WARN self-test not run yet");
    private volatile List<PluginSnapshot> pluginInventoryCache = List.of();
    private volatile List<DatapackSnapshot> datapackInventoryCache = List.of();
    private volatile long inventoryUpdatedMillis;

    private boolean degraded;
    private boolean maintenance;
    private String maintenanceReason = "";
    private boolean restarting;
    private String restartReason = "";
    private long restartDueMillis;
    private int badSamples;
    private int goodSamples;
    private long lastPerfAlert;
    private long lastHeartbeat;
    private long lastMetricsLog;

    // Spigot fallback sampler state. Paper's native metrics are used reflectively when available.
    private long perfLastWallNanos;
    private long perfLastCpuNanos = -1L;
    private double fallbackTps1 = 20.0;
    private double fallbackTps5 = 20.0;
    private double fallbackTps15 = 20.0;

    @Override public void onEnable() {
        saveDefaultConfig();
        getConfig().options().copyDefaults(true);
        saveConfig();
        loadRuntimeConfigCache();
        instanceId = loadOrCreateInstanceId();
        fileLog = new AsyncFileLog(this);
        reporter = new BridgeReporter(this);
        webhook = new DirectWebhook(this);
        apiServer = new StatusApiServer(this);
        gstRelay = new GstRelay(this);
        Bukkit.getPluginManager().registerEvents(this, this);
        sample();
        apiServer.start();
        startTasks();
        selfTestCache = runSelfTest();
        Bukkit.getScheduler().runTaskLater(this, () -> {
            if (getConfig().getBoolean("events.startup", true)) {
                emitEvent("startup", "서버 시작", serverName() + " 서버가 온라인 상태입니다.", true);
            }
            sendHeartbeat(true);
        }, 20L);
        getLogger().info("GeumyiDiscordStatus " + VERSION + " / GSC bridge protocol v" + PROTOCOL_VERSION +
                " enabled for " + serverName() + " (" + serverId() + ")");
    }

    @Override public void onDisable() {
        try {
            if (countdownTask != null) countdownTask.cancel();
            if (sampleTask != null) sampleTask.cancel();
            sample();
            if (getConfig().getBoolean("events.shutdown", true)) {
                emitEvent("shutdown", "서버 종료", "정상 종료", true);
                // shutdown must be the final bridge event. A heartbeat after it makes
                // the legacy StatusAgent clear plannedShutdown and report a false crash.
                if (reporter != null && !reporter.flush(1800L)) {
                    getLogger().warning("정상 종료 상태 전송 확인 시간이 초과되었습니다.");
                }
            }
        } catch (Throwable t) {
            getLogger().warning("shutdown telemetry build failed: " + t.getMessage());
        }
        try { if (apiServer != null) apiServer.stop(); } catch (Throwable ignored) {}
        try { if (gstRelay != null) gstRelay.close(); } catch (Throwable ignored) {}
        try { if (webhook != null) webhook.close(); } catch (Throwable ignored) {}
        try { if (reporter != null) reporter.close(); } catch (Throwable ignored) {}
        try { if (fileLog != null) fileLog.close(); } catch (Throwable ignored) {}
    }

    private void startTasks() {
        if (sampleTask != null) sampleTask.cancel();
        int interval = Math.max(2, getConfig().getInt("performance.interval-seconds", 5));
        sampleTask = Bukkit.getScheduler().runTaskTimer(this, () -> {
            sample();
            checkPerformance();
            maybeHeartbeat();
            maybeMetricsLog();
            if (gstRelay != null) gstRelay.pollAsync();
        }, 20L, interval * 20L);
    }

    private void sample() {
        try {
            Perf perf = measurePerformance();
            double tps1 = perf.tps1();
            double tps5 = perf.tps5();
            double tps15 = perf.tps15();
            double mspt = perf.mspt();

            Runtime rt = Runtime.getRuntime();
            long max = Math.max(1L, rt.maxMemory());
            long used = Math.max(0L, rt.totalMemory() - rt.freeMemory());
            double mem = Math.min(100.0, (used * 100.0) / max);

            int javaPlayers = 0, bedrockPlayers = 0;
            List<PlayerSnapshot> players = new ArrayList<>();
            for (Player p : Bukkit.getOnlinePlayers()) {
                boolean bedrock = Compat.isBedrock(p);
                if (bedrock) bedrockPlayers++; else javaPlayers++;
                String world = p.getWorld() == null ? "" : p.getWorld().getName();
                String gm = p.getGameMode() == null ? "" : p.getGameMode().name();
                int ping;
                try { ping = p.getPing(); } catch (Throwable ignored) { ping = -1; }
                players.add(new PlayerSnapshot(p.getName(), p.getUniqueId().toString(), bedrock ? "bedrock" : "java", world, ping, gm));
            }

            int chunks = 0, entities = 0;
            List<WorldSnapshot> worlds = new ArrayList<>();
            for (World w : Bukkit.getWorlds()) {
                int wc = safeChunkCount(w);
                int we = safeEntityCount(w);
                chunks += wc;
                entities += we;
                worlds.add(new WorldSnapshot(w.getName(), wc, we));
            }

            long now = System.currentTimeMillis();
            refreshInventoryIfNeeded(now);
            List<PluginSnapshot> plugins = pluginInventoryCache;
            List<DatapackSnapshot> datapacks = datapackInventoryCache;

            Metrics m = new Metrics(now, tps1, tps5, tps15, mspt, mem, used, max,
                    players.size(), Bukkit.getServer().getMaxPlayers(), javaPlayers, bedrockPlayers,
                    chunks, entities, Math.max(0L, (now - startMillis) / 1000L));
            boolean gst = safePluginEnabled("GeumyiServerTools");
            boolean dsrv = safePluginEnabled("DiscordSRV");
            snapshot = new ServerSnapshot(serverId(), serverName(), instanceId, bootId, VERSION, PROTOCOL_VERSION,
                    mode(), maintenanceReason, restartReason, restartDueMillis, m,
                    safeMinecraftVersion(), safePaperVersion(), safePort(), gst, dsrv,
                    List.copyOf(players), List.copyOf(worlds), List.copyOf(plugins), List.copyOf(datapacks));
        } catch (Throwable t) {
            debug("metrics sample failed: " + t.getMessage());
        }
    }

    private void refreshInventoryIfNeeded(long now) {
        long refreshMs = Math.max(10L, getConfig().getLong("inventory.refresh-seconds", 30L)) * 1000L;
        if (inventoryUpdatedMillis > 0L && now - inventoryUpdatedMillis < refreshMs) return;
        pluginInventoryCache = List.copyOf(snapshotPlugins());
        datapackInventoryCache = List.copyOf(snapshotDatapacks());
        inventoryUpdatedMillis = now;
    }

    private List<PluginSnapshot> snapshotPlugins() {
        List<PluginSnapshot> out = new ArrayList<>();
        try {
            for (Plugin plugin : Bukkit.getPluginManager().getPlugins()) {
                if (plugin == null) continue;
                String version = "";
                String main = "";
                String api = "";
                try {
                    PluginDescriptionFile d = plugin.getDescription();
                    if (d != null) {
                        version = Objects.toString(d.getVersion(), "");
                        main = Objects.toString(d.getMain(), "");
                        api = Objects.toString(d.getAPIVersion(), "");
                    }
                } catch (Throwable ignored) {}
                out.add(new PluginSnapshot(plugin.getName(), version, plugin.isEnabled(), main, api));
            }
            out.sort(Comparator.comparing(PluginSnapshot::name, String.CASE_INSENSITIVE_ORDER));
        } catch (Throwable t) {
            debug("plugin snapshot failed: " + t.getMessage());
        }
        return out;
    }

    /**
     * Paper-specific datapack information is collected reflectively so the plugin stays tolerant of
     * small API package changes while still exposing the data GSC v4 needs for its Datapack Manager.
     */
    private List<DatapackSnapshot> snapshotDatapacks() {
        List<DatapackSnapshot> out = new ArrayList<>();
        try {
            Class<?> serverApi = Class.forName("org.bukkit.Server");
            Object manager = serverApi.getMethod("getDatapackManager").invoke(Bukkit.getServer());
            if (manager == null) return out;
            Class<?> managerApi = Class.forName("io.papermc.paper.datapack.DatapackManager");
            Class<?> discoveredApi = Class.forName("io.papermc.paper.datapack.DiscoveredDatapack");
            Class<?> datapackApi = Class.forName("io.papermc.paper.datapack.Datapack");
            Object value = managerApi.getMethod("getPacks").invoke(manager);
            if (!(value instanceof Collection<?> packs)) return out;
            for (Object pack : packs) {
                if (pack == null) continue;
                String name = Objects.toString(discoveredApi.getMethod("getName").invoke(pack), "");
                boolean enabled = Boolean.TRUE.equals(datapackApi.getMethod("isEnabled").invoke(pack));
                boolean required = Boolean.TRUE.equals(discoveredApi.getMethod("isRequired").invoke(pack));
                String compatibility = Objects.toString(discoveredApi.getMethod("getCompatibility").invoke(pack), "");
                String source = Objects.toString(discoveredApi.getMethod("getSource").invoke(pack), "");
                out.add(new DatapackSnapshot(name, enabled, required, compatibility, source));
            }
            out.sort(Comparator.comparing(DatapackSnapshot::name, String.CASE_INSENSITIVE_ORDER));
        } catch (ClassNotFoundException | NoSuchMethodException ignored) {
            // Not available on this server build; endpoint will simply return an empty list.
        } catch (Throwable t) {
            debug("datapack snapshot failed: " + t.getMessage());
        }
        return out;
    }

    /**
     * Uses Paper performance methods reflectively when present. On Spigot, TPS is
     * derived from scheduler cadence and MSPT is estimated from main-thread CPU
     * time plus wall-clock tick overrun. No Paper-only method is hard-linked.
     */
    private Perf measurePerformance() {
        long now = System.nanoTime();
        long cpuNow = currentThreadCpuTime();
        int intervalSeconds = Math.max(2, getConfig().getInt("performance.interval-seconds", 5));
        double fallbackMspt = 0.0;

        if (perfLastWallNanos != 0L) {
            long elapsedNanos = Math.max(1L, now - perfLastWallNanos);
            double elapsedSeconds = elapsedNanos / 1_000_000_000.0;
            double expectedSeconds = intervalSeconds;
            boolean normalInterval = elapsedSeconds >= expectedSeconds * 0.65;
            double expectedTicks = normalInterval ? intervalSeconds * 20.0 : Math.max(1.0, elapsedSeconds * 20.0);
            double instantTps = normalInterval ? clamp(expectedTicks / elapsedSeconds, 0.0, 20.0) : 20.0;

            fallbackTps1 = ewma(fallbackTps1, instantTps, elapsedSeconds, 60.0);
            fallbackTps5 = ewma(fallbackTps5, instantTps, elapsedSeconds, 300.0);
            fallbackTps15 = ewma(fallbackTps15, instantTps, elapsedSeconds, 900.0);

            double cpuMsPerTick = 0.0;
            if (cpuNow >= 0L && perfLastCpuNanos >= 0L && cpuNow >= perfLastCpuNanos) {
                cpuMsPerTick = ((cpuNow - perfLastCpuNanos) / 1_000_000.0) / expectedTicks;
            }
            double wallMsPerTick = (elapsedNanos / 1_000_000.0) / expectedTicks;
            double overrunMs = Math.max(0.0, wallMsPerTick - 50.0);
            fallbackMspt = Math.max(cpuMsPerTick, overrunMs);
        }

        perfLastWallNanos = now;
        perfLastCpuNanos = cpuNow;

        double[] nativeTps = paperTps();
        Double nativeMspt = paperAverageTickTime();
        double t1 = nativeTps != null && nativeTps.length > 0 ? saneTps(nativeTps[0]) : fallbackTps1;
        double t5 = nativeTps != null && nativeTps.length > 1 ? saneTps(nativeTps[1]) : fallbackTps5;
        double t15 = nativeTps != null && nativeTps.length > 2 ? saneTps(nativeTps[2]) : fallbackTps15;
        double mspt = nativeMspt != null && Double.isFinite(nativeMspt) && nativeMspt >= 0.0
                ? nativeMspt : Math.max(0.0, fallbackMspt);
        return new Perf(t1, t5, t15, mspt);
    }

    private static double[] paperTps() {
        try {
            Object server = Bukkit.getServer();
            Method method = server.getClass().getMethod("getTPS");
            Object value = method.invoke(server);
            return value instanceof double[] arr ? arr : null;
        } catch (Throwable ignored) {
            return null;
        }
    }

    private static Double paperAverageTickTime() {
        try {
            Object server = Bukkit.getServer();
            Method method = server.getClass().getMethod("getAverageTickTime");
            Object value = method.invoke(server);
            return value instanceof Number n ? n.doubleValue() : null;
        } catch (Throwable ignored) {
            return null;
        }
    }

    private static long currentThreadCpuTime() {
        try {
            ThreadMXBean bean = ManagementFactory.getThreadMXBean();
            if (!bean.isCurrentThreadCpuTimeSupported()) return -1L;
            if (!bean.isThreadCpuTimeEnabled()) bean.setThreadCpuTimeEnabled(true);
            return bean.getCurrentThreadCpuTime();
        } catch (Throwable ignored) {
            return -1L;
        }
    }

    private static double ewma(double previous, double value, double dtSeconds, double windowSeconds) {
        double alpha = 1.0 - Math.exp(-Math.max(0.001, dtSeconds) / windowSeconds);
        return previous + alpha * (value - previous);
    }

    private static double saneTps(double value) {
        return Double.isFinite(value) ? clamp(value, 0.0, 20.0) : 20.0;
    }

    private static double clamp(double value, double min, double max) {
        return Math.max(min, Math.min(max, value));
    }

    private record Perf(double tps1, double tps5, double tps15, double mspt) {}

    private int safeChunkCount(World w) { try { return w.getLoadedChunks().length; } catch (Throwable ignored) { return 0; } }
    private int safeEntityCount(World w) { try { return w.getEntities().size(); } catch (Throwable ignored) { return 0; } }
    private boolean safePluginEnabled(String name) { try { return Bukkit.getPluginManager().isPluginEnabled(name); } catch (Throwable ignored) { return false; } }
    private String safeMinecraftVersion() { try { return Bukkit.getMinecraftVersion(); } catch (Throwable ignored) { return "unknown"; } }
    private String safePaperVersion() { try { return Bukkit.getVersion(); } catch (Throwable ignored) { return "unknown"; } }
    private int safePort() { try { return Bukkit.getPort(); } catch (Throwable ignored) { return -1; } }

    private void checkPerformance() {
        if (!getConfig().getBoolean("performance.enabled", true)) return;
        ServerSnapshot s = snapshot;
        if (s == null) return;
        Metrics m = s.metrics();
        boolean bad = m.tps1m() < getConfig().getDouble("performance.low-tps", 18.0)
                || m.mspt() > getConfig().getDouble("performance.high-mspt", 50.0)
                || m.memoryPercent() > getConfig().getDouble("performance.high-memory-percent", 90.0);
        int badNeed = Math.max(1, getConfig().getInt("performance.consecutive-samples", 3));
        int goodNeed = Math.max(1, getConfig().getInt("performance.recovery-samples", 3));
        if (bad) {
            badSamples++;
            goodSamples = 0;
            if (!degraded && badSamples >= badNeed) {
                degraded = true;
                sample();
                maybePerfAlert(false);
            } else if (degraded) {
                maybePerfAlert(false);
            }
        } else {
            badSamples = 0;
            if (degraded && ++goodSamples >= goodNeed) {
                degraded = false;
                goodSamples = 0;
                sample();
                maybePerfAlert(true);
            }
        }
    }

    private void maybePerfAlert(boolean recovered) {
        boolean preferGst = getConfig().getBoolean("integration.gst.prefer-gst-performance-alerts", true);
        if (!recovered && preferGst && gstRelay != null && gstRelay.available()) return;
        long now = System.currentTimeMillis();
        long cooldown = Math.max(10L, getConfig().getInt("performance.alert-cooldown-seconds", 120)) * 1000L;
        if (!recovered && now - lastPerfAlert < cooldown) return;
        lastPerfAlert = now;
        ServerSnapshot s = snapshot;
        if (s == null) return;
        Metrics m = s.metrics();
        String message = "TPS " + fmt(m.tps1m()) + " · MSPT " + fmt(m.mspt()) + " · RAM " + fmt(m.memoryPercent()) + "%";
        emitEvent(recovered ? "performance_recovered" : "performance", recovered ? "성능 정상화" : "성능 경고", message, true);
    }

    private void maybeHeartbeat() {
        int seconds = bridgeHeartbeatSeconds();
        long now = System.currentTimeMillis();
        if (now - lastHeartbeat >= seconds * 1000L) sendHeartbeat(false);
    }

    private int bridgeHeartbeatSeconds() { return bridgeHeartbeatSecondsCache; }

    void sendHeartbeat(boolean force) {
        if (reporter == null || !reporter.enabled()) return;
        long now = System.currentTimeMillis();
        if (!force && now - lastHeartbeat < bridgeHeartbeatSeconds() * 1000L) return;
        lastHeartbeat = now;
        Map<String, String> p = basePayload("heartbeat", "GDS heartbeat", "heartbeat");
        p.put("heartbeat", "true");
        p.put("capabilities", String.join(",", capabilities()));
        reporter.sendAsync(p);
    }

    void emitEvent(String type, String title, String message, boolean directDiscord) {
        long now = System.currentTimeMillis();
        EventRecord record = eventBuffer.add(now, clean(type), clean(title), clean(message), mode());
        Map<String, String> p = basePayload(type, title, message);
        p.put("event_seq", Long.toString(record.sequence()));
        if ("shutdown".equalsIgnoreCase(type)) p.put("planned", "true");
        if (reporter != null) reporter.sendAsync(p);
        if (directDiscord && webhook != null) webhook.sendEvent(title, message, colorFor(type));
        appendEvent(type, title + " | " + message);
    }

    private Map<String, String> basePayload(String event, String title, String message) {
        Map<String, String> p = Text.linkedMap();
        ServerSnapshot s = snapshot;
        p.put("server_id", serverId());
        p.put("server_name", serverName());
        p.put("event", clean(event));
        p.put("title", clean(title));
        p.put("message", clean(message));
        p.put("timestamp", Long.toString(System.currentTimeMillis()));
        p.put("mode", mode());
        p.put("protocol_version", Integer.toString(PROTOCOL_VERSION));
        p.put("plugin_version", VERSION);
        p.put("instance_id", instanceId == null ? "" : instanceId);
        p.put("boot_id", bootId);
        p.put("source", "paper_plugin");
        p.put("maintenance_reason", maintenanceReason);
        p.put("restart_reason", restartReason);
        p.put("restart_due", Long.toString(restartDueMillis));
        if (s != null) {
            Metrics m = s.metrics();
            p.put("tps", fmt(m.tps1m()));
            p.put("tps5", fmt(m.tps5m()));
            p.put("tps15", fmt(m.tps15m()));
            p.put("mspt", fmt(m.mspt()));
            p.put("memory_percent", fmt(m.memoryPercent()));
            p.put("memory_used_bytes", Long.toString(m.memoryUsedBytes()));
            p.put("memory_max_bytes", Long.toString(m.memoryMaxBytes()));
            p.put("online", Integer.toString(m.online()));
            p.put("max_players", Integer.toString(m.maxPlayers()));
            p.put("java_players", Integer.toString(m.javaPlayers()));
            p.put("bedrock_players", Integer.toString(m.bedrockPlayers()));
            p.put("loaded_chunks", Integer.toString(m.loadedChunks()));
            p.put("entities", Integer.toString(m.entities()));
            p.put("uptime_seconds", Long.toString(m.uptimeSeconds()));
            p.put("paper_version", s.paperVersion());
            p.put("minecraft_version", s.minecraftVersion());
            p.put("server_port", Integer.toString(s.serverPort()));
            p.put("discordsrv", Boolean.toString(s.discordSrvAvailable()));
            p.put("gst", Boolean.toString(s.gstAvailable()));
        }
        if (gstRelay != null) {
            GstDiagnosticsSnapshot g = gstRelay.health();
            if (g.available()) {
                p.put("gst_version", g.version());
                p.put("gst_grade", g.grade());
                p.put("gst_lag_active", Boolean.toString(g.lagActive()));
                p.put("gst_incident_count", Long.toString(g.incidentCount()));
                p.put("gst_health_time", Long.toString(g.time()));
            }
        }
        return p;
    }

    String legacyStatusJson() {
        ServerSnapshot s = snapshot;
        if (s == null) return "{\"server_id\":\"" + Text.json(serverId()) + "\",\"mode\":\"STARTING\"}";
        Metrics m = s.metrics();
        return "{\"server_id\":\"" + Text.json(s.serverId()) + "\",\"server_name\":\"" + Text.json(s.serverName()) +
                "\",\"mode\":\"" + Text.json(s.mode()) + "\",\"maintenance_reason\":\"" + Text.json(s.maintenanceReason()) +
                "\",\"restart_reason\":\"" + Text.json(s.restartReason()) + "\",\"restart_due\":" + s.restartDueMillis() +
                ",\"tps\":" + num(m.tps1m()) + ",\"tps5\":" + num(m.tps5m()) + ",\"tps15\":" + num(m.tps15m()) +
                ",\"mspt\":" + num(m.mspt()) + ",\"memory_percent\":" + num(m.memoryPercent()) +
                ",\"online\":" + m.online() + ",\"max_players\":" + m.maxPlayers() + ",\"java_players\":" + m.javaPlayers() +
                ",\"bedrock_players\":" + m.bedrockPlayers() + ",\"loaded_chunks\":" + m.loadedChunks() +
                ",\"entities\":" + m.entities() + ",\"uptime_seconds\":" + m.uptimeSeconds() + ",\"timestamp\":" + m.timestamp() +
                ",\"minecraft_version\":\"" + Text.json(s.minecraftVersion()) + "\",\"paper_version\":\"" + Text.json(s.paperVersion()) +
                "\",\"port\":" + s.serverPort() + ",\"gst\":" + s.gstAvailable() + ",\"discordsrv\":" + s.discordSrvAvailable() + "}";
    }

    String v4StatusJson() {
        ServerSnapshot s = snapshot;
        if (s == null) return "{\"protocol_version\":4,\"plugin_version\":\"" + VERSION + "\",\"mode\":\"STARTING\"}";
        Metrics m = s.metrics();
        StringBuilder b = new StringBuilder(1536);
        b.append('{')
                .append("\"protocol_version\":").append(PROTOCOL_VERSION)
                .append(",\"plugin_version\":\"").append(VERSION).append('"')
                .append(",\"server_id\":\"").append(Text.json(s.serverId())).append('"')
                .append(",\"server_name\":\"").append(Text.json(s.serverName())).append('"')
                .append(",\"instance_id\":\"").append(Text.json(s.instanceId())).append('"')
                .append(",\"boot_id\":\"").append(Text.json(s.bootId())).append('"')
                .append(",\"mode\":\"").append(Text.json(s.mode())).append('"')
                .append(",\"maintenance_reason\":\"").append(Text.json(s.maintenanceReason())).append('"')
                .append(",\"restart_reason\":\"").append(Text.json(s.restartReason())).append('"')
                .append(",\"restart_due\":").append(s.restartDueMillis())
                .append(",\"minecraft_version\":\"").append(Text.json(s.minecraftVersion())).append('"')
                .append(",\"paper_version\":\"").append(Text.json(s.paperVersion())).append('"')
                .append(",\"port\":").append(s.serverPort())
                .append(",\"metrics\":{")
                .append("\"timestamp\":").append(m.timestamp())
                .append(",\"tps_1m\":").append(num(m.tps1m()))
                .append(",\"tps_5m\":").append(num(m.tps5m()))
                .append(",\"tps_15m\":").append(num(m.tps15m()))
                .append(",\"mspt\":").append(num(m.mspt()))
                .append(",\"memory_percent\":").append(num(m.memoryPercent()))
                .append(",\"memory_used_bytes\":").append(m.memoryUsedBytes())
                .append(",\"memory_max_bytes\":").append(m.memoryMaxBytes())
                .append(",\"online\":").append(m.online())
                .append(",\"max_players\":").append(m.maxPlayers())
                .append(",\"java_players\":").append(m.javaPlayers())
                .append(",\"bedrock_players\":").append(m.bedrockPlayers())
                .append(",\"loaded_chunks\":").append(m.loadedChunks())
                .append(",\"entities\":").append(m.entities())
                .append(",\"uptime_seconds\":").append(m.uptimeSeconds()).append('}')
                .append(",\"integrations\":{\"gst\":").append(s.gstAvailable())
                .append(",\"discordsrv\":").append(s.discordSrvAvailable()).append('}')
                .append(",\"bridge\":").append(bridgeJson())
                .append(",\"gst_diagnostics\":").append(gstJson())
                .append(",\"event_sequence\":").append(eventBuffer.latestSequence())
                .append('}');
        return b.toString();
    }

    String playersJson() {
        ServerSnapshot s = snapshot;
        StringBuilder b = new StringBuilder("{\"players\":[");
        if (s != null) {
            for (int i = 0; i < s.players().size(); i++) {
                if (i > 0) b.append(',');
                PlayerSnapshot p = s.players().get(i);
                b.append("{\"name\":\"").append(Text.json(p.name())).append("\",\"uuid\":\"").append(Text.json(p.uuid()))
                        .append("\",\"platform\":\"").append(Text.json(p.platform())).append("\",\"world\":\"").append(Text.json(p.world()))
                        .append("\",\"ping\":").append(p.ping()).append(",\"game_mode\":\"").append(Text.json(p.gameMode())).append("\"}");
            }
        }
        return b.append("]}").toString();
    }

    String worldsJson() {
        ServerSnapshot s = snapshot;
        StringBuilder b = new StringBuilder("{\"worlds\":[");
        if (s != null) {
            for (int i = 0; i < s.worlds().size(); i++) {
                if (i > 0) b.append(',');
                WorldSnapshot w = s.worlds().get(i);
                b.append("{\"name\":\"").append(Text.json(w.name())).append("\",\"loaded_chunks\":").append(w.loadedChunks())
                        .append(",\"entities\":").append(w.entities()).append('}');
            }
        }
        return b.append("]}").toString();
    }

    String pluginsJson() {
        ServerSnapshot s = snapshot;
        StringBuilder b = new StringBuilder("{\"timestamp\":").append(inventoryUpdatedMillis).append(",\"plugins\":[");
        if (s != null) {
            for (int i = 0; i < s.plugins().size(); i++) {
                if (i > 0) b.append(',');
                PluginSnapshot p = s.plugins().get(i);
                b.append("{\"name\":\"").append(Text.json(p.name())).append("\",\"version\":\"").append(Text.json(p.version()))
                        .append("\",\"enabled\":").append(p.enabled())
                        .append(",\"main\":\"").append(Text.json(p.main())).append("\",\"api_version\":\"")
                        .append(Text.json(p.apiVersion())).append("\"}");
            }
        }
        return b.append("]}").toString();
    }

    String datapacksJson() {
        ServerSnapshot s = snapshot;
        StringBuilder b = new StringBuilder("{\"timestamp\":").append(inventoryUpdatedMillis).append(",\"datapacks\":[");
        if (s != null) {
            for (int i = 0; i < s.datapacks().size(); i++) {
                if (i > 0) b.append(',');
                DatapackSnapshot d = s.datapacks().get(i);
                b.append("{\"name\":\"").append(Text.json(d.name())).append("\",\"enabled\":").append(d.enabled())
                        .append(",\"required\":").append(d.required())
                        .append(",\"compatibility\":\"").append(Text.json(d.compatibility()))
                        .append("\",\"source\":\"").append(Text.json(d.source())).append("\"}");
            }
        }
        return b.append("]}").toString();
    }

    String capabilitiesJson() {
        StringBuilder b = new StringBuilder("{\"protocol_version\":").append(PROTOCOL_VERSION)
                .append(",\"plugin_version\":\"").append(VERSION).append("\",\"capabilities\":[");
        List<String> caps = capabilities();
        for (int i = 0; i < caps.size(); i++) {
            if (i > 0) b.append(',');
            b.append('"').append(Text.json(caps.get(i))).append('"');
        }
        return b.append("],\"actions\":[")
                .append(jsonStringArray(allowedActions()))
                .append("]}").toString();
    }

    private List<String> capabilities() {
        return List.of("status", "metrics", "players", "worlds", "plugins", "datapacks", "events", "safe_actions", "maintenance", "restart_countdown", "gst_relay", "gst_diagnostics_v2", "structured_lag_events", "actor_audit", "whitelist_manage", "legacy_ingest", "hmac_outbound");
    }

    String eventsJson(long since) {
        List<EventRecord> list = eventBuffer.since(Math.max(0L, since));
        StringBuilder b = new StringBuilder("{\"latest_sequence\":").append(eventBuffer.latestSequence()).append(",\"events\":[");
        for (int i = 0; i < list.size(); i++) {
            if (i > 0) b.append(',');
            EventRecord e = list.get(i);
            b.append("{\"sequence\":").append(e.sequence()).append(",\"timestamp\":").append(e.timestamp())
                    .append(",\"type\":\"").append(Text.json(e.type())).append("\",\"title\":\"").append(Text.json(e.title()))
                    .append("\",\"message\":\"").append(Text.json(e.message())).append("\",\"mode\":\"").append(Text.json(e.mode())).append("\"}");
        }
        return b.append("]}").toString();
    }

    String diagnosticsJson() {
        List<String> checks = selfTestCache;
        StringBuilder b = new StringBuilder("{\"ok\":").append(checks.stream().noneMatch(x -> x.startsWith("FAIL")))
                .append(",\"checks\":[");
        for (int i = 0; i < checks.size(); i++) {
            if (i > 0) b.append(',');
            b.append('"').append(Text.json(checks.get(i))).append('"');
        }
        return b.append("],\"bridge\":").append(bridgeJson()).append(",\"gst\":").append(gstJson()).append('}').toString();
    }

    String gstJson() {
        GstRelay relay = gstRelay;
        return relay == null ? GstDiagnosticsSnapshot.unavailable().toJson(System.currentTimeMillis(), 30_000L) : relay.healthJson();
    }

    private String bridgeJson() {
        BridgeReporter r = reporter;
        if (r == null) return "{\"enabled\":false}";
        return "{\"enabled\":" + r.enabled() + ",\"endpoint\":\"" + Text.json(redactEndpoint(r.endpoint())) +
                "\",\"in_flight\":" + r.inFlight() + ",\"sent\":" + r.sentCount() + ",\"failed\":" + r.failedCount() +
                ",\"last_success\":" + r.lastSuccessMillis() + ",\"last_failure\":" + r.lastFailureMillis() +
                ",\"last_error\":\"" + Text.json(r.lastError()) + "\"}";
    }

    private String redactEndpoint(String endpoint) {
        if (endpoint == null || endpoint.isBlank()) return "";
        int q = endpoint.indexOf('?');
        return q >= 0 ? endpoint.substring(0, q) + "?…" : endpoint;
    }

    ActionResult performAction(Map<String, String> p) {
        String action = clean(p.getOrDefault("action", "")).toLowerCase(Locale.ROOT);
        if (!allowedActions().contains(action)) return ActionResult.fail("action_not_allowed", "허용되지 않은 작업입니다: " + action);
        try {
            return switch (action) {
                case "broadcast" -> {
                    String msg = limited(p.get("message"), 1000);
                    if (msg.isBlank()) yield ActionResult.fail("invalid_message", "공지 내용이 비어 있습니다.");
                    Bukkit.broadcastMessage(PREFIX + msg);
                    emitEvent("announce", "서버 공지", msg, true);
                    yield ActionResult.ok("공지를 전송했습니다.");
                }
                case "save" -> {
                    boolean ok = Bukkit.dispatchCommand(Bukkit.getConsoleSender(), "save-all flush");
                    emitEvent("save", "서버 저장", ok ? "save-all flush 실행" : "save-all flush 요청 실패", false);
                    yield ok ? ActionResult.ok("서버 저장 명령을 실행했습니다.") : ActionResult.fail("save_failed", "저장 명령 실행에 실패했습니다.");
                }
                case "maintenance" -> {
                    boolean enabled = Text.truthy(p.getOrDefault("enabled", "false"));
                    setMaintenance(enabled, limited(p.get("reason"), 500));
                    yield ActionResult.ok(enabled ? "점검 모드를 켰습니다." : "점검 모드를 해제했습니다.");
                }
                case "restart_schedule" -> {
                    long seconds = parseDuration(p.getOrDefault("duration", ""));
                    if (seconds <= 0 || seconds > MAX_RESTART_SECONDS) yield ActionResult.fail("invalid_duration", "재시작 시간 값이 올바르지 않습니다.");
                    scheduleRestart(seconds, limited(p.get("reason"), 500), null);
                    yield ActionResult.ok(human(seconds) + " 후 재시작 카운트다운을 예약했습니다.");
                }
                case "restart_cancel" -> {
                    boolean existed = cancelRestartInternal();
                    if (existed) emitEvent("restart_cancelled", "재시작 취소", "예약된 재시작이 취소되었습니다.", true);
                    yield ActionResult.ok(existed ? "재시작 예약을 취소했습니다." : "예약된 재시작이 없습니다.");
                }
                case "whitelist" -> {
                    boolean enabled = Text.truthy(p.getOrDefault("enabled", "false"));
                    boolean ok = Bukkit.dispatchCommand(Bukkit.getConsoleSender(), enabled ? "whitelist on" : "whitelist off");
                    emitEvent("whitelist", "화이트리스트", enabled ? "ON" : "OFF", false);
                    yield ok ? ActionResult.ok("화이트리스트를 " + (enabled ? "켰습니다." : "껐습니다.")) : ActionResult.fail("whitelist_failed", "화이트리스트 명령 실행에 실패했습니다.");
                }
                case "whitelist_add", "whitelist_remove" -> {
                    String playerName = limited(p.get("player"), 32);
                    if (!validMinecraftName(playerName)) yield ActionResult.fail("invalid_player", "플레이어 이름 형식이 올바르지 않습니다.");
                    boolean add = "whitelist_add".equals(action);
                    boolean ok = Bukkit.dispatchCommand(Bukkit.getConsoleSender(), "whitelist " + (add ? "add " : "remove ") + playerName);
                    emitEvent(add ? "whitelist_add" : "whitelist_remove", "화이트리스트 변경", (add ? "추가 " : "제거 ") + playerName, false);
                    yield ok ? ActionResult.ok(playerName + " 플레이어를 화이트리스트에서 " + (add ? "추가했습니다." : "제거했습니다."))
                            : ActionResult.fail("whitelist_change_failed", "화이트리스트 변경 명령 실행에 실패했습니다.");
                }
                case "kick" -> {
                    String playerName = limited(p.get("player"), 64);
                    Player player = Bukkit.getPlayerExact(playerName);
                    if (player == null) yield ActionResult.fail("player_not_found", "플레이어를 찾을 수 없습니다.");
                    String reason = limited(p.get("reason"), 300);
                    player.kickPlayer(reason.isBlank() ? "서버 관리자가 연결을 종료했습니다." : reason);
                    emitEvent("player_kick", "플레이어 연결 종료", playerName, false);
                    yield ActionResult.ok(playerName + " 플레이어의 연결을 종료했습니다.");
                }
                default -> ActionResult.fail("unknown_action", "알 수 없는 작업입니다.");
            };
        } catch (Throwable t) {
            getLogger().warning("bridge action failed [" + action + "]: " + t.getMessage());
            return ActionResult.fail("action_failed", t.getMessage() == null ? "작업 실행 실패" : t.getMessage());
        }
    }

    void auditAction(String remote, String requestId, String action, String actor, String actorId, String source, ActionResult result) {
        if (!actionsLogEnabled || fileLog == null) return;
        String line = timestamp() + "\tremote=" + clean(remote) + "\trequest=" + clean(requestId) + "\taction=" + clean(action) +
                "\tactor=" + clean(actor) + "\tactor_id=" + clean(actorId) + "\tsource=" + clean(source) +
                "\tok=" + result.ok() + "\tcode=" + clean(result.code()) + "\tmessage=" + clean(result.message()) + "\n";
        fileLog.append(getDataFolder().toPath().resolve("actions.log"), line);
    }

    private List<String> allowedActions() { return allowedActionsCache; }

    @EventHandler(ignoreCancelled = true)
    public void onJoin(PlayerJoinEvent event) {
        Player p = event.getPlayer();
        boolean bedrock = Compat.isBedrock(p);
        if (!p.hasPlayedBefore() && getConfig().getBoolean("events.first-join", true)) {
            emitEvent("first_join", "첫 접속", p.getName() + " (" + (bedrock ? "Bedrock" : "Java") + ")", true);
        } else if (getConfig().getBoolean("events.join", false) && !suppressDiscordSrvJoinQuit()) {
            emitEvent("join", "접속", p.getName() + " (" + (bedrock ? "Bedrock" : "Java") + ")", true);
        }
    }

    @EventHandler(ignoreCancelled = true)
    public void onQuit(PlayerQuitEvent event) {
        if (getConfig().getBoolean("events.quit", false) && !suppressDiscordSrvJoinQuit()) {
            emitEvent("quit", "퇴장", event.getPlayer().getName(), true);
        }
    }

    @EventHandler(ignoreCancelled = true)
    public void onDeath(PlayerDeathEvent event) {
        if (!getConfig().getBoolean("events.death", false)) return;
        String message = event.getDeathMessage();
        if (message == null || message.isBlank()) message = event.getEntity().getName() + " died";
        emitEvent("death", "사망", message, true);
    }

    private boolean suppressDiscordSrvJoinQuit() {
        return getConfig().getBoolean("integration.discordsrv.suppress-join-quit-when-present", true)
                && safePluginEnabled("DiscordSRV");
    }

    @Override public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!command.getName().equalsIgnoreCase("gds")) return false;
        if (args.length == 0) { sendHelp(sender); return true; }
        String sub = args[0].toLowerCase(Locale.ROOT);
        switch (sub) {
            case "status" -> sendStatus(sender);
            case "stats" -> sendStats(sender);
            case "announce" -> {
                if (!sender.hasPermission("geumyidiscordstatus.announce")) return deny(sender);
                if (args.length < 2) { sender.sendMessage(PREFIX + "§7사용법: /gds announce <내용>"); return true; }
                String msg = join(args, 1);
                emitEvent("announce", "서버 공지", msg, true);
                Bukkit.broadcastMessage(PREFIX + msg);
                sender.sendMessage(PREFIX + "§aMinecraft/GSC/Discord 공지를 전송했습니다.");
            }
            case "maintenance" -> { if (admin(sender)) handleMaintenance(sender, args); }
            case "restart" -> { if (admin(sender)) handleRestart(sender, args); }
            case "cancel" -> { if (admin(sender)) cancelRestart(sender); }
            case "test" -> {
                if (!admin(sender)) return true;
                emitEvent("test", "연동 테스트", "GDS v" + VERSION + " / protocol v" + PROTOCOL_VERSION + " 테스트입니다.", true);
                sendHeartbeat(true);
                sender.sendMessage(PREFIX + "§a비동기 Bridge/Discord 테스트를 전송했습니다.");
            }
            case "endpoint", "api", "bridge" -> {
                if (!admin(sender)) return true;
                String bind = getConfig().getString("api.bind", "127.0.0.1");
                int port = getConfig().getInt("api.port", 8766);
                sender.sendMessage(PREFIX + "§7API: http://" + bind + ":" + port + "/api/v4/status");
                sender.sendMessage(PREFIX + "§7Bridge: " + (reporter != null && reporter.enabled() ? redactEndpoint(reporter.endpoint()) : "비활성"));
                if (reporter != null) sender.sendMessage(PREFIX + "§7전송 성공/실패/대기: §f" + reporter.sentCount() + "/" + reporter.failedCount() + "/" + reporter.inFlight());
            }
            case "health", "selftest" -> {
                if (!admin(sender)) return true;
                sender.sendMessage(PREFIX + "§bSelf-Test");
                selfTestCache = runSelfTest();
                for (String line : selfTestCache) sender.sendMessage(PREFIX + (line.startsWith("FAIL") ? "§c" : line.startsWith("WARN") ? "§e" : "§a") + line);
            }
            case "capabilities" -> {
                if (!admin(sender)) return true;
                sender.sendMessage(PREFIX + "§7Protocol v" + PROTOCOL_VERSION + " · " + String.join(", ", capabilities()));
                sender.sendMessage(PREFIX + "§7Actions: " + String.join(", ", allowedActions()));
            }
            case "reload" -> {
                if (!admin(sender)) return true;
                reloadConfig();
                getConfig().options().copyDefaults(true);
                saveConfig();
                loadRuntimeConfigCache();
                if (reporter != null) reporter.rebuild();
                if (apiServer != null) apiServer.restart();
                startTasks();
                sample();
                selfTestCache = runSelfTest();
                sender.sendMessage(PREFIX + "§a설정을 다시 불러왔습니다.");
            }
            default -> sendHelp(sender);
        }
        return true;
    }

    private void handleMaintenance(CommandSender sender, String[] args) {
        if (args.length < 2) { sender.sendMessage(PREFIX + "§7사용법: /gds maintenance <on|off> [사유]"); return; }
        boolean on;
        if ("on".equalsIgnoreCase(args[1])) on = true;
        else if ("off".equalsIgnoreCase(args[1])) on = false;
        else { sender.sendMessage(PREFIX + "§c'on' 또는 'off'를 사용하세요."); return; }
        setMaintenance(on, args.length >= 3 ? join(args, 2) : "");
        sender.sendMessage(PREFIX + (on ? "§e점검 모드를 켰습니다." : "§a점검 모드를 해제했습니다."));
    }

    private void setMaintenance(boolean on, String reason) {
        maintenance = on;
        maintenanceReason = on ? limited(reason, 500) : "";
        sample();
        emitEvent(on ? "maintenance_on" : "maintenance_off", on ? "점검 모드 시작" : "점검 모드 종료",
                on ? (maintenanceReason.isBlank() ? "점검 중" : maintenanceReason) : "정상 운영으로 복귀", true);
    }

    private void handleRestart(CommandSender sender, String[] args) {
        if (args.length < 2) { sender.sendMessage(PREFIX + "§7사용법: /gds restart <10m|60s|1h> [사유]"); return; }
        long seconds = parseDuration(args[1]);
        if (seconds <= 0 || seconds > MAX_RESTART_SECONDS) { sender.sendMessage(PREFIX + "§c올바른 시간을 입력하세요. 예: 10m"); return; }
        scheduleRestart(seconds, args.length >= 3 ? join(args, 2) : "", sender);
    }

    private void scheduleRestart(long seconds, String reason, CommandSender sender) {
        cancelRestartInternal();
        restarting = true;
        restartReason = reason == null ? "" : reason;
        restartDueMillis = System.currentTimeMillis() + seconds * 1000L;
        sample();
        emitEvent("restart_scheduled", "재시작 예약", human(seconds) + " 후" + (restartReason.isBlank() ? "" : " · " + restartReason), true);
        if (sender != null) sender.sendMessage(PREFIX + "§e" + human(seconds) + " 후 재시작을 예약했습니다.");
        countdownTask = Bukkit.getScheduler().runTaskTimer(this, () -> {
            long left = Math.max(0L, (restartDueMillis - System.currentTimeMillis() + 999L) / 1000L);
            if (left <= 0) {
                if (countdownTask != null) countdownTask.cancel();
                countdownTask = null;
                String reasonNow = restartReason;
                boolean execute = getConfig().getBoolean("restart.execute-command-at-zero", false);
                emitEvent("restart_due", "재시작 시각 도달", reasonNow.isBlank() ? "카운트다운 종료" : reasonNow, true);
                if (execute) {
                    String command = getConfig().getString("restart.command-at-zero", "restart");
                    Bukkit.dispatchCommand(Bukkit.getConsoleSender(), command == null || command.isBlank() ? "restart" : command.trim());
                } else {
                    restarting = false;
                    restartReason = "";
                    restartDueMillis = 0L;
                    sample();
                }
                return;
            }
            if (shouldAnnounce(left)) {
                String msg = "서버 재시작까지 " + human(left) + (restartReason.isBlank() ? "" : " · " + restartReason);
                Bukkit.broadcastMessage(PREFIX + "§e" + msg);
                emitEvent("restart_countdown", "재시작 카운트다운", msg, true);
            }
        }, 0L, 20L);
    }

    private void cancelRestart(CommandSender sender) {
        boolean existed = cancelRestartInternal();
        if (existed) {
            emitEvent("restart_cancelled", "재시작 취소", "예약된 재시작이 취소되었습니다.", true);
            sender.sendMessage(PREFIX + "§a재시작 예약을 취소했습니다.");
        } else sender.sendMessage(PREFIX + "§7예약된 재시작이 없습니다.");
    }

    private boolean cancelRestartInternal() {
        boolean existed = restarting || countdownTask != null;
        if (countdownTask != null) countdownTask.cancel();
        countdownTask = null;
        restarting = false;
        restartReason = "";
        restartDueMillis = 0L;
        sample();
        return existed;
    }

    private void sendStatus(CommandSender sender) {
        ServerSnapshot s = snapshot;
        if (s == null) { sender.sendMessage(PREFIX + "§e상태를 수집하는 중입니다."); return; }
        Metrics m = s.metrics();
        sender.sendMessage("§bGDS §fv" + VERSION + " §7/ Protocol v" + PROTOCOL_VERSION + " §8- §f" + s.serverName());
        sender.sendMessage("§7상태 §f" + s.mode() + " §8| §7TPS §f" + fmt(m.tps1m()) + " §8| §7MSPT §f" + fmt(m.mspt()) + " §8| §7RAM §f" + fmt(m.memoryPercent()) + "%");
        sender.sendMessage("§7Players §f" + m.online() + "/" + m.maxPlayers() + " §8(§aJE " + m.javaPlayers() + "§8 / §bBE " + m.bedrockPlayers() + "§8)");
        sender.sendMessage("§7Chunks §f" + m.loadedChunks() + " §8| §7Entities §f" + m.entities() + " §8| §7Uptime §f" + human(m.uptimeSeconds()));
        sender.sendMessage("§7GST §f" + (s.gstAvailable() ? "ON" : "OFF") + " §8| §7DiscordSRV §f" + (s.discordSrvAvailable() ? "ON" : "OFF"));
        if (gstRelay != null && gstRelay.health().available()) {
            GstDiagnosticsSnapshot g = gstRelay.health();
            sender.sendMessage("§7GST Health §f" + g.grade() + " §8| §7Lag §f" + (g.lagActive() ? "ACTIVE" : "IDLE") + " §8| §7Incidents §f" + g.incidentCount());
        }
    }

    private void sendStats(CommandSender sender) {
        sendStatus(sender);
        ServerSnapshot s = snapshot;
        if (s == null) return;
        sender.sendMessage("§7ID §f" + s.serverId() + " §8| §7MC §f" + s.minecraftVersion() + " §8| §7Port §f" + s.serverPort());
        sender.sendMessage("§7Instance §f" + shortId(instanceId) + " §8| §7Boot §f" + shortId(bootId));
        if (maintenance) sender.sendMessage("§e점검: §f" + maintenanceReason);
        if (restarting) sender.sendMessage("§e재시작: §f" + restartReason + " §8@ §f" + Instant.ofEpochMilli(restartDueMillis));
    }

    private void sendHelp(CommandSender sender) {
        sender.sendMessage("§b§lGeumyiDiscordStatus v" + VERSION + " §7(GSC v4 Bridge)");
        sender.sendMessage("§7/gds status §f- 서버/Bridge 상태");
        sender.sendMessage("§7/gds announce <내용> §f- Minecraft + GSC/Discord 공지");
        sender.sendMessage("§7/gds maintenance on|off [사유] §f- 점검 상태");
        sender.sendMessage("§7/gds restart 10m [사유] §f- 재시작 카운트다운");
        sender.sendMessage("§7/gds cancel §f- 재시작 예약 취소");
        sender.sendMessage("§7/gds test §f- 비동기 연동 테스트");
        sender.sendMessage("§7/gds health §f- 자체 진단");
        sender.sendMessage("§7/gds api §f- API/Bridge 주소 및 통계");
        sender.sendMessage("§7/gds reload §f- 설정 다시 읽기");
    }

    private boolean admin(CommandSender sender) {
        if (sender.hasPermission("geumyidiscordstatus.admin")) return true;
        sender.sendMessage(PREFIX + "§c관리 권한이 없습니다.");
        return false;
    }

    private boolean deny(CommandSender sender) {
        sender.sendMessage(PREFIX + "§c권한이 없습니다.");
        return true;
    }

    private List<String> runSelfTest() {
        List<String> out = new ArrayList<>();
        out.add(snapshot != null ? "OK metrics snapshot" : "WARN metrics snapshot not ready");
        String bind = getConfig().getString("api.bind", "127.0.0.1");
        String token = getConfig().getString("api.token", "");
        boolean loopback = "127.0.0.1".equals(bind) || "localhost".equalsIgnoreCase(bind) || "::1".equals(bind);
        if (!loopback && (token == null || token.isBlank())) out.add("FAIL API external bind without token");
        else out.add("OK API auth/bind");
        if (reporter != null && reporter.enabled()) {
            String secret = reporter.secret();
            if (secret.isBlank() || secret.startsWith("CHANGE_THIS")) out.add("WARN Bridge secret should be changed");
            else out.add("OK Bridge secret configured");
            try { java.net.URI.create(reporter.endpoint()); out.add("OK Bridge endpoint syntax"); }
            catch (Throwable t) { out.add("FAIL Bridge endpoint invalid"); }
        } else out.add("WARN Bridge outbound disabled");
        try {
            Files.createDirectories(getDataFolder().toPath());
            Path test = getDataFolder().toPath().resolve(".write-test-" + ThreadLocalRandom.current().nextInt(100000));
            Files.writeString(test, "ok", StandardCharsets.UTF_8);
            Files.deleteIfExists(test);
            out.add("OK data folder writable");
        } catch (Throwable t) { out.add("FAIL data folder not writable"); }
        if (gstRelay != null && gstRelay.available()) {
            GstDiagnosticsSnapshot g = gstRelay.health();
            if (!g.available()) out.add("WARN GST Diagnostics v2 not ready");
            else if (g.stale(System.currentTimeMillis(), gstRelay.healthMaxAgeMillis())) out.add("WARN GST Diagnostics v2 stale");
            else out.add("OK GST Diagnostics v2 " + g.grade());
        } else out.add("OK GST integration not present");
        out.add("OK network I/O is asynchronous");
        return List.copyOf(out);
    }

    private void maybeMetricsLog() {
        if (!getConfig().getBoolean("logging.metrics-file", true) || fileLog == null) return;
        long now = System.currentTimeMillis();
        long interval = Math.max(10, getConfig().getInt("logging.metrics-interval-seconds", 60)) * 1000L;
        if (now - lastMetricsLog < interval) return;
        lastMetricsLog = now;
        ServerSnapshot s = snapshot;
        if (s == null) return;
        Path path = getDataFolder().toPath().resolve("metrics.csv");
        Metrics m = s.metrics();
        String line = m.timestamp() + "," + s.mode() + "," + fmt(m.tps1m()) + "," + fmt(m.mspt()) + "," + fmt(m.memoryPercent()) + "," +
                m.online() + "," + m.javaPlayers() + "," + m.bedrockPlayers() + "," + m.loadedChunks() + "," + m.entities() + "\n";
        fileLog.appendWithHeader(path, "timestamp,mode,tps,mspt,memory,online,java,bedrock,chunks,entities\n", line);
    }

    private void appendEvent(String type, String message) {
        if (!getConfig().getBoolean("logging.events-file", true) || fileLog == null) return;
        fileLog.append(getDataFolder().toPath().resolve("events.log"), timestamp() + " [" + clean(type) + "] " + clean(message) + "\n");
    }

    private String loadOrCreateInstanceId() {
        try {
            Files.createDirectories(getDataFolder().toPath());
            Path path = getDataFolder().toPath().resolve("instance.id");
            if (Files.isRegularFile(path)) {
                String existing = Files.readString(path, StandardCharsets.UTF_8).trim();
                if (!existing.isBlank()) return existing;
            }
            String id = UUID.randomUUID().toString();
            Files.writeString(path, id + "\n", StandardCharsets.UTF_8);
            return id;
        } catch (IOException e) {
            getLogger().warning("instance.id 저장 실패: " + e.getMessage());
            return UUID.randomUUID().toString();
        }
    }

    String serverId() { return serverIdCache; }

    String serverName() { return serverNameCache; }

    String mode() {
        if (restarting) return "RESTARTING";
        if (maintenance) return "MAINTENANCE";
        if (degraded || (gstRelay != null && gstRelay.degraded())) return "DEGRADED";
        return "ONLINE";
    }

    static boolean validMinecraftName(String value) {
        return value != null && value.matches("[A-Za-z0-9_]{1,16}");
    }

    static String fmt(double value) { return String.format(Locale.ROOT, "%.1f", value); }
    static String num(double value) { return Double.isFinite(value) ? String.format(Locale.ROOT, "%.3f", value) : "0"; }
    static String join(String[] a, int start) { return String.join(" ", Arrays.copyOfRange(a, start, a.length)); }

    static long parseDuration(String raw) {
        if (raw == null) return -1L;
        Matcher m = DURATION.matcher(raw.trim());
        if (!m.matches()) return -1L;
        try {
            long n = Long.parseLong(m.group(1));
            String unit = m.group(2);
            if (unit == null || unit.equalsIgnoreCase("s")) return n;
            if (unit.equalsIgnoreCase("m")) return Math.multiplyExact(n, 60L);
            if (unit.equalsIgnoreCase("h")) return Math.multiplyExact(n, 3600L);
            if (unit.equalsIgnoreCase("d")) return Math.multiplyExact(n, 86400L);
        } catch (Throwable ignored) {}
        return -1L;
    }

    static boolean shouldAnnounce(long seconds) {
        return seconds <= 10 || seconds == 15 || seconds == 30 || seconds == 60 || seconds == 120 || seconds == 300 || seconds == 600 ||
                seconds == 900 || seconds == 1800 || seconds == 3600 || (seconds > 3600 && seconds % 3600 == 0);
    }

    static String human(long seconds) {
        if (seconds < 60) return seconds + "초";
        if (seconds < 3600) {
            long m = seconds / 60, s = seconds % 60;
            return s == 0 ? m + "분" : m + "분 " + s + "초";
        }
        long h = seconds / 3600, rem = seconds % 3600, m = rem / 60;
        return m == 0 ? h + "시간" : h + "시간 " + m + "분";
    }

    static int colorFor(String type) {
        return switch (type == null ? "" : type) {
            case "performance", "gst_alert" -> 0xF1C40F;
            case "shutdown", "restart_due" -> 0xE74C3C;
            case "startup", "performance_recovered", "maintenance_off" -> 0x2ECC71;
            case "maintenance_on", "restart_scheduled", "restart_countdown" -> 0xE67E22;
            default -> 0x3498DB;
        };
    }

    private String jsonStringArray(List<String> values) {
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < values.size(); i++) {
            if (i > 0) b.append(',');
            b.append('"').append(Text.json(values.get(i))).append('"');
        }
        return b.toString();
    }

    private static String clean(String s) { return s == null ? "" : s.replace('\r', ' ').replace('\n', ' ').trim(); }
    private static String limited(String s, int max) { String v = clean(s); return v.length() <= max ? v : v.substring(0, max); }
    private static String shortId(String s) { return s == null ? "" : (s.length() <= 8 ? s : s.substring(0, 8)); }
    private static String timestamp() { return new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.ROOT).format(new Date()); }

    private void loadRuntimeConfigCache() {
        String sid = getConfig().getString("server.id", "survival");
        serverIdCache = sid == null || sid.isBlank() ? "survival" : sid.trim();
        String sname = getConfig().getString("server.name", "금이 서버");
        serverNameCache = sname == null || sname.isBlank() ? "금이 서버" : sname.trim();
        debugEnabled = getConfig().getBoolean("logging.debug", false);
        actionsLogEnabled = getConfig().getBoolean("logging.actions-file", true);
        String bridgeUrl = getConfig().getString("bridge.url", "");
        boolean legacyAgentMode = bridgeUrl == null || bridgeUrl.isBlank();
        bridgeHeartbeatSecondsCache = legacyAgentMode
                ? Math.max(3, getConfig().getInt("agent.heartbeat-seconds", 10))
                : Math.max(3, getConfig().getInt("bridge.heartbeat-seconds", 10));
        List<String> configured = getConfig().getStringList("api.allowed-actions");
        if (configured == null || configured.isEmpty()) {
            allowedActionsCache = List.of("broadcast", "save", "maintenance", "restart_schedule", "restart_cancel", "whitelist", "whitelist_add", "whitelist_remove", "kick");
        } else {
            List<String> out = new ArrayList<>();
            for (String a : configured) if (a != null && !a.isBlank()) out.add(a.trim().toLowerCase(Locale.ROOT));
            allowedActionsCache = List.copyOf(out);
        }
    }

    void debug(String message) {
        if (debugEnabled) getLogger().info("[debug] " + message);
    }
}

