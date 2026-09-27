package kr.geumyi.servertools;

import java.lang.reflect.Field;
import java.time.Instant;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;
import java.util.Locale;

import org.bukkit.Bukkit;
import org.bukkit.World;
import org.bukkit.command.CommandSender;
import org.bukkit.scheduler.BukkitTask;

/**
 * GST 1.1 diagnostics layer. Reuses the proven core PerformanceMonitor instead of sampling Paper twice.
 */
final class DiagnosticsService {
    private static final String PREFIX = "§8[§bGST§8] §r";

    private final GeumyiServerToolsV110 plugin;
    private final GscRuntimeBridge bridge;
    private final LagDetector detector = new LagDetector();
    private final Deque<LagIncident> recent = new ArrayDeque<>();
    private BukkitTask pollTask;
    private Field monitorField;
    private long lastProcessedTimestamp;
    private volatile MetricsSnapshot latest;
    private volatile double recentPeakMspt;
    private volatile double recentMinTps = 20.0;
    private volatile String healthGrade = "UNKNOWN";
    private volatile LagIncident activeIncident;
    private volatile LagIncident lastIncident;

    DiagnosticsService(GeumyiServerToolsV110 plugin, GscRuntimeBridge bridge) {
        this.plugin = plugin;
        this.bridge = bridge;
    }

    void start() {
        resolveMonitorField();
        restartTask();
    }

    void shutdown() {
        if (pollTask != null) pollTask.cancel();
        pollTask = null;
    }

    void reloadSettings() {
        restartTask();
    }

    private void restartTask() {
        if (pollTask != null) pollTask.cancel();
        pollTask = null;
        if (!plugin.getConfig().getBoolean("lag-recorder.enabled", true)) return;
        int seconds = Math.max(1, plugin.getConfig().getInt("lag-recorder.poll-seconds", 2));
        pollTask = Bukkit.getScheduler().runTaskTimer(plugin, this::poll, 20L, seconds * 20L);
    }

    private void poll() {
        MetricsSnapshot s = coreSnapshot();
        if (s == null || s.timestamp() <= 0 || s.timestamp() == lastProcessedTimestamp) return;
        lastProcessedTimestamp = s.timestamp();
        latest = s;
        recomputeWindow();

        double lowTps = plugin.getConfig().getDouble("monitor.low-tps", 18.0);
        double highMspt = plugin.getConfig().getDouble("monitor.high-mspt", 50.0);
        double highMem = plugin.getConfig().getDouble("monitor.high-memory-percent", 85.0);
        int trigger = Math.max(1, plugin.getConfig().getInt("monitor.consecutive-samples", 3));
        int recovery = Math.max(1, plugin.getConfig().getInt("lag-recorder.recovery-samples", 3));

        LagDetector.Transition t = detector.update(s.timestamp(), s.tps1m(), s.mspt(), s.memoryPercent(),
                lowTps, highMspt, highMem, trigger, recovery);
        if (t == LagDetector.Transition.STARTED) startIncident(s, lowTps, highMspt, highMem);
        else if (t == LagDetector.Transition.RECOVERED) recoverIncident(s);

        healthGrade = grade(s, detector.active(), lowTps, highMspt, highMem);
        if (bridge != null) bridge.updateDiagnostics(snapshot());
    }

    private void startIncident(MetricsSnapshot s, double lowTps, double highMspt, double highMem) {
        String reason = reason(s, lowTps, highMspt, highMem);
        WorldHotspot hot = hottestWorld();
        LagIncident incident = new LagIncident(detector.incidentCount(), s.timestamp(), 0L,
                LagDetector.severity(s.tps1m(), s.mspt(), s.memoryPercent()), reason,
                s.tps1m(), s.mspt(), s.memoryPercent(), s.onlinePlayers(), s.loadedChunks(), s.entities(),
                hot.name(), hot.loadedChunks(), hot.entities());
        activeIncident = incident;
        lastIncident = incident;
        pushRecent(incident);
        if (bridge != null) {
            bridge.recordLagIncident("start", incident);
            bridge.recordEvent("lag_incident_start", "Lag incident detected", incident.summary());
            bridge.flushSoon();
        }
        plugin.getLogger().warning("[LagRecorder] START " + incident.summary());
    }

    private void recoverIncident(MetricsSnapshot s) {
        LagIncident current = activeIncident;
        if (current == null) return;
        LagIncident recovered = current.withRecoveredAt(s.timestamp());
        activeIncident = null;
        lastIncident = recovered;
        replaceRecent(recovered);
        if (bridge != null) {
            bridge.recordLagIncident("recovered", recovered);
            bridge.recordEvent("lag_incident_recovered", "Lag incident recovered", recovered.summary());
            bridge.flushSoon();
        }
        plugin.getLogger().info("[LagRecorder] RECOVERED " + recovered.summary());
    }

    void sendDiagnostics(CommandSender sender) {
        MetricsSnapshot s = coreSnapshot();
        sender.sendMessage("§8§m----------------------------------------");
        sender.sendMessage("§b§lGeumyiServerTools 1.1 Diagnostics");
        if (s == null) {
            sender.sendMessage(PREFIX + "§e성능 샘플이 아직 준비되지 않았습니다.");
            return;
        }
        recomputeWindow();
        String grade = grade(s, detector.active(),
                plugin.getConfig().getDouble("monitor.low-tps", 18.0),
                plugin.getConfig().getDouble("monitor.high-mspt", 50.0),
                plugin.getConfig().getDouble("monitor.high-memory-percent", 85.0));
        sender.sendMessage("§7Health: " + gradeColor(grade) + grade);
        sender.sendMessage("§7TPS: §f" + fmt(s.tps1m()) + " §8(5m " + fmt(s.tps5m()) + " / 15m " + fmt(s.tps15m()) + ")");
        sender.sendMessage("§7MSPT: §f" + fmt(s.mspt()) + " ms §8| §7최근 peak: §f" + fmt(recentPeakMspt) + " ms");
        sender.sendMessage("§7Memory: §f" + fmt(s.memoryPercent()) + "% §8| §7Players: §f" + s.onlinePlayers());
        sender.sendMessage("§7Loaded chunks: §f" + s.loadedChunks() + " §8| §7Entities: §f" + s.entities());
        WorldHotspot hot = hottestWorld();
        if (!hot.name().isBlank()) {
            sender.sendMessage("§7엔티티/로드 청크 기준 최대 월드: §f" + hot.name() + " §8| §7chunks §f" + hot.loadedChunks() + " §8| §7entities §f" + hot.entities());
        }
        sender.sendMessage("§7Lag recorder: " + (detector.active() ? "§cACTIVE" : "§aIDLE") + " §8| §7incidents: §f" + detector.incidentCount());
        LagIncident last = lastIncident;
        if (last != null) sender.sendMessage("§7최근 incident: §f#" + last.id() + " " + last.severity() + " §8- §7" + last.reason());
        sender.sendMessage("§7최근 window min TPS / peak MSPT: §f" + fmt(recentMinTps) + " / " + fmt(recentPeakMspt) + " ms");
    }

    void sendLagStatus(CommandSender sender) {
        sender.sendMessage("§8§m----------------------------------------");
        sender.sendMessage("§b§lGST Lag Spike Recorder");
        sender.sendMessage("§7상태: " + (detector.active() ? "§cINCIDENT ACTIVE" : "§a정상 감시 중"));
        sender.sendMessage("§7이번 서버 세션 incident: §f" + detector.incidentCount());
        List<LagIncident> list = recentIncidents();
        if (list.isEmpty()) {
            sender.sendMessage("§7기록된 lag incident가 없습니다.");
            return;
        }
        sender.sendMessage("§7최근 기록:");
        int shown = 0;
        for (int i = list.size() - 1; i >= 0 && shown < 5; i--, shown++) {
            LagIncident e = list.get(i);
            String state = e.recoveredAt() > 0 ? "§aRECOVERED" : "§cACTIVE";
            sender.sendMessage("§8#" + e.id() + " " + state + " §7" + Instant.ofEpochMilli(e.startedAt())
                    + " §8| §f" + e.severity() + " §8| §7" + e.reason());
        }
    }

    DiagnosticsSnapshot snapshot() {
        MetricsSnapshot s = latest != null ? latest : coreSnapshot();
        if (s == null) return DiagnosticsSnapshot.empty(detector.incidentCount(), detector.active());
        String g = healthGrade;
        if (g == null || g.equals("UNKNOWN")) {
            g = grade(s, detector.active(),
                    plugin.getConfig().getDouble("monitor.low-tps", 18.0),
                    plugin.getConfig().getDouble("monitor.high-mspt", 50.0),
                    plugin.getConfig().getDouble("monitor.high-memory-percent", 85.0));
        }
        return new DiagnosticsSnapshot(System.currentTimeMillis(), g, detector.active(), detector.incidentCount(),
                s.tps1m(), s.tps5m(), s.tps15m(), s.mspt(), recentPeakMspt, recentMinTps,
                s.memoryPercent(), s.onlinePlayers(), s.loadedChunks(), s.entities(), lastIncident);
    }

    String performanceJson() {
        DiagnosticsSnapshot d = snapshot();
        return d.toJson();
    }

    boolean lagActive() { return detector.active(); }
    long lagIncidentCount() { return detector.incidentCount(); }

    private MetricsSnapshot coreSnapshot() {
        try {
            PerformanceMonitor m = coreMonitor();
            return m == null ? null : m.latest();
        } catch (Throwable t) {
            return latest;
        }
    }

    @SuppressWarnings("unchecked")
    private List<MetricsSnapshot> coreHistory() {
        try {
            PerformanceMonitor m = coreMonitor();
            if (m == null) return List.of();
            return m.history();
        } catch (Throwable t) {
            return List.of();
        }
    }

    private PerformanceMonitor coreMonitor() throws Exception {
        if (monitorField == null) resolveMonitorField();
        if (monitorField == null) return null;
        Object v = monitorField.get(plugin);
        return v instanceof PerformanceMonitor p ? p : null;
    }

    private void resolveMonitorField() {
        try {
            Field f = GeumyiServerTools.class.getDeclaredField("monitor");
            f.setAccessible(true);
            monitorField = f;
        } catch (Throwable t) {
            plugin.getLogger().warning("Diagnostics could not access core PerformanceMonitor: " + t.getMessage());
        }
    }

    private void recomputeWindow() {
        List<MetricsSnapshot> history = coreHistory();
        int wanted = Math.max(5, plugin.getConfig().getInt("lag-recorder.window-samples", 60));
        double peak = 0.0;
        double min = 20.0;
        int start = Math.max(0, history.size() - wanted);
        for (int i = start; i < history.size(); i++) {
            MetricsSnapshot x = history.get(i);
            if (finite(x.mspt())) peak = Math.max(peak, x.mspt());
            if (finite(x.tps1m()) && x.tps1m() > 0) min = Math.min(min, x.tps1m());
        }
        recentPeakMspt = peak;
        recentMinTps = min;
    }

    private void pushRecent(LagIncident incident) {
        int max = Math.max(5, plugin.getConfig().getInt("lag-recorder.incident-history", 20));
        recent.addLast(incident);
        while (recent.size() > max) recent.removeFirst();
    }

    private void replaceRecent(LagIncident incident) {
        List<LagIncident> copy = new ArrayList<>(recent);
        for (int i = 0; i < copy.size(); i++) {
            if (copy.get(i).id() == incident.id()) copy.set(i, incident);
        }
        recent.clear();
        recent.addAll(copy);
    }

    private List<LagIncident> recentIncidents() { return List.copyOf(recent); }

    private WorldHotspot hottestWorld() {
        String name = "";
        int chunks = 0;
        int entities = 0;
        long score = -1;
        for (World w : Bukkit.getWorlds()) {
            int c = 0, e = 0;
            try { c = w.getLoadedChunks().length; } catch (Throwable ignored) {}
            try { e = w.getEntities().size(); } catch (Throwable ignored) {}
            long s = (long)e * 8L + c;
            if (s > score) {
                score = s;
                name = w.getName();
                chunks = c;
                entities = e;
            }
        }
        return new WorldHotspot(name == null ? "" : name, chunks, entities);
    }

    private static String reason(MetricsSnapshot s, double lowTps, double highMspt, double highMem) {
        List<String> causes = new ArrayList<>();
        if (finite(s.mspt()) && s.mspt() >= highMspt) causes.add("MSPT " + fmt(s.mspt()) + "ms");
        if (finite(s.tps1m()) && s.tps1m() > 0 && s.tps1m() < lowTps) causes.add("TPS " + fmt(s.tps1m()));
        if (finite(s.memoryPercent()) && s.memoryPercent() >= highMem) causes.add("Memory " + fmt(s.memoryPercent()) + "%");
        return causes.isEmpty() ? "performance threshold exceeded" : String.join(", ", causes);
    }

    private static String grade(MetricsSnapshot s, boolean active, double lowTps, double highMspt, double highMem) {
        if (active || s.mspt() >= 100 || (s.tps1m() > 0 && s.tps1m() < 15) || s.memoryPercent() >= 95) return "CRITICAL";
        if (LagDetector.bad(s.tps1m(), s.mspt(), s.memoryPercent(), lowTps, highMspt, highMem)) return "DEGRADED";
        if (s.mspt() >= highMspt * 0.75 || (s.tps1m() > 0 && s.tps1m() < 19.0) || s.memoryPercent() >= highMem * 0.9) return "WATCH";
        return "HEALTHY";
    }

    private static String gradeColor(String g) {
        return switch (g) {
            case "CRITICAL" -> "§c";
            case "DEGRADED", "WATCH" -> "§e";
            default -> "§a";
        };
    }

    private static boolean finite(double d) { return !Double.isNaN(d) && !Double.isInfinite(d); }
    private static String fmt(double d) { return finite(d) ? String.format(Locale.ROOT, "%.2f", d) : "n/a"; }

    record WorldHotspot(String name, int loadedChunks, int entities) {}

    record LagIncident(long id, long startedAt, long recoveredAt, String severity, String reason,
                       double tps1m, double mspt, double memoryPercent, int players, int loadedChunks, int entities,
                       String hottestWorld, int hottestWorldChunks, int hottestWorldEntities) {
        LagIncident withRecoveredAt(long time) {
            return new LagIncident(id, startedAt, time, severity, reason, tps1m, mspt, memoryPercent, players,
                    loadedChunks, entities, hottestWorld, hottestWorldChunks, hottestWorldEntities);
        }
        String summary() {
            return "#" + id + " " + severity + " " + reason + " | TPS=" + fmt(tps1m) + " MSPT=" + fmt(mspt)
                    + " MEM=" + fmt(memoryPercent) + "% players=" + players + " chunks=" + loadedChunks + " entities=" + entities;
        }
        String toJson(String eventType) { return toJson(eventType, ""); }
        String toJson(String eventType, String sessionId) {
            String session = sessionId == null || sessionId.isBlank() ? "" : "\"session_id\":\"" + GscRuntimeBridge.json(sessionId) + "\",";
            long eventTime = recoveredAt > 0 ? recoveredAt : startedAt;
            return "{" +
                    "\"schema\":1,\"event\":\"" + GscRuntimeBridge.json(eventType) + "\"," + session +
                    "\"time\":" + eventTime + ",\"id\":" + id + ",\"started_at\":" + startedAt + ",\"recovered_at\":" + recoveredAt + "," +
                    "\"severity\":\"" + GscRuntimeBridge.json(severity) + "\",\"reason\":\"" + GscRuntimeBridge.json(reason) + "\"," +
                    "\"tps_1m\":" + num(tps1m) + ",\"mspt\":" + num(mspt) + ",\"memory_percent\":" + num(memoryPercent) + "," +
                    "\"players\":" + players + ",\"loaded_chunks\":" + loadedChunks + ",\"entities\":" + entities + "," +
                    "\"hottest_world\":{\"name\":\"" + GscRuntimeBridge.json(hottestWorld) + "\",\"loaded_chunks\":" + hottestWorldChunks + ",\"entities\":" + hottestWorldEntities + "}" +
                    "}";
        }
    }

    record DiagnosticsSnapshot(long time, String grade, boolean lagActive, long incidentCount,
                               double tps1m, double tps5m, double tps15m, double mspt,
                               double recentPeakMspt, double recentMinTps, double memoryPercent,
                               int players, int loadedChunks, int entities, LagIncident lastIncident) {
        static DiagnosticsSnapshot empty(long count, boolean active) {
            return new DiagnosticsSnapshot(System.currentTimeMillis(), "UNKNOWN", active, count,
                    Double.NaN, Double.NaN, Double.NaN, Double.NaN, Double.NaN, Double.NaN, Double.NaN,
                    0, 0, 0, null);
        }
        String toJson() {
            String last = lastIncident == null ? "null" : lastIncident.toJson(lastIncident.recoveredAt() > 0 ? "recovered" : "start");
            return "{" +
                    "\"schema\":2,\"plugin\":\"GeumyiServerTools\",\"version\":\"1.1.1\"," +
                    "\"time\":" + time + ",\"grade\":\"" + GscRuntimeBridge.json(grade) + "\"," +
                    "\"lag_active\":" + lagActive + ",\"incident_count\":" + incidentCount + "," +
                    "\"performance\":{\"tps_1m\":" + num(tps1m) + ",\"tps_5m\":" + num(tps5m) + ",\"tps_15m\":" + num(tps15m) +
                    ",\"mspt\":" + num(mspt) + ",\"recent_peak_mspt\":" + num(recentPeakMspt) + ",\"recent_min_tps\":" + num(recentMinTps) +
                    ",\"memory_percent\":" + num(memoryPercent) + "}," +
                    "\"counts\":{\"players\":" + players + ",\"loaded_chunks\":" + loadedChunks + ",\"entities\":" + entities + "}," +
                    "\"last_incident\":" + last + "}";
        }
    }

    private static String num(double d) {
        return finite(d) ? String.format(Locale.ROOT, "%.4f", d) : "null";
    }
}
