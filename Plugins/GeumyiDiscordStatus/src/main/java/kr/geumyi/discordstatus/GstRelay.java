package kr.geumyi.discordstatus;

import org.bukkit.Bukkit;
import java.io.File;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

final class GstRelay implements AutoCloseable {
    private final GeumyiDiscordStatus plugin;
    private final ExecutorService io;
    private final AtomicBoolean polling = new AtomicBoolean();
    private long alertOffset;
    private long lagOffset;
    private boolean alertInitialized;
    private boolean lagInitialized;
    private volatile GstDiagnosticsSnapshot health = GstDiagnosticsSnapshot.unavailable();

    GstRelay(GeumyiDiscordStatus plugin) {
        this.plugin = plugin;
        this.io = Executors.newSingleThreadExecutor(r -> {
            Thread t = new Thread(r, "GDS-GST-Relay");
            t.setDaemon(true);
            return t;
        });
    }

    boolean available() { return Bukkit.getPluginManager().isPluginEnabled("GeumyiServerTools"); }
    GstDiagnosticsSnapshot health() { return health; }
    boolean degraded() { return health.degraded(); }

    long healthMaxAgeMillis() {
        return Math.max(10L, plugin.getConfig().getLong("integration.gst.health-max-age-seconds", 30L)) * 1000L;
    }

    String healthJson() { return health.toJson(System.currentTimeMillis(), healthMaxAgeMillis()); }

    void pollAsync() {
        if (!plugin.getConfig().getBoolean("integration.gst.enabled", true)) return;
        if (!available() || !polling.compareAndSet(false, true)) return;
        boolean relayExisting = plugin.getConfig().getBoolean("integration.gst.relay-existing-on-startup", false);
        io.execute(() -> {
            try {
                refreshHealth();
                List<GstLagEvent> events = readLagEvents(relayExisting);
                boolean structuredAvailable = lagEventsFile().isFile();
                List<String> legacy = (!structuredAvailable || !plugin.getConfig().getBoolean("integration.gst.relay-lag-events", true))
                        ? readLegacyAlerts(relayExisting) : List.of();
                if (!events.isEmpty() || !legacy.isEmpty()) {
                    Bukkit.getScheduler().runTask(plugin, () -> {
                        for (GstLagEvent e : events) {
                            plugin.emitEvent(e.recovered() ? "gst_lag_recovered" : "gst_lag_incident",
                                    e.recovered() ? "GST 성능 정상화" : "GST 성능 저하 감지", e.message(), true);
                        }
                        for (String line : legacy) plugin.emitEvent("gst_alert", "GST 성능 경고", line, false);
                    });
                }
            } catch (Throwable t) {
                plugin.debug("GST relay failed: " + t.getMessage());
            } finally {
                polling.set(false);
            }
        });
    }

    private void refreshHealth() {
        try {
            File f = new File(runtimeDir(), "health-v2.json");
            if (!f.isFile()) { health = GstDiagnosticsSnapshot.unavailable(); return; }
            String json = Files.readString(f.toPath(), StandardCharsets.UTF_8);
            GstDiagnosticsSnapshot parsed = GstDiagnosticsSnapshot.parse(json);
            health = parsed.available() ? parsed : GstDiagnosticsSnapshot.unavailable();
        } catch (Throwable t) {
            plugin.debug("GST health-v2 read failed: " + t.getMessage());
        }
    }

    private List<GstLagEvent> readLagEvents(boolean relayExisting) throws Exception {
        if (!plugin.getConfig().getBoolean("integration.gst.relay-lag-events", true)) return List.of();
        File file = lagEventsFile();
        if (!file.isFile()) return List.of();
        long len = file.length();
        if (!lagInitialized) {
            lagInitialized = true;
            lagOffset = relayExisting ? 0L : len;
            return List.of();
        }
        if (len < lagOffset) lagOffset = 0L;
        if (len == lagOffset) return List.of();
        List<GstLagEvent> out = new ArrayList<>();
        try (RandomAccessFile raf = new RandomAccessFile(file, "r")) {
            raf.seek(lagOffset);
            String raw;
            while ((raw = raf.readLine()) != null) {
                String line = new String(raw.getBytes(StandardCharsets.ISO_8859_1), StandardCharsets.UTF_8).trim();
                GstLagEvent e = GstLagEvent.parse(line);
                if (e != null) out.add(e);
            }
            lagOffset = raf.getFilePointer();
        }
        return out;
    }

    private List<String> readLegacyAlerts(boolean relayExisting) throws Exception {
        if (!plugin.getConfig().getBoolean("integration.gst.relay-alert-log", true)) return List.of();
        File file = new File(gstDir(), "alerts.log");
        if (!file.isFile()) return List.of();
        long len = file.length();
        if (!alertInitialized) {
            alertInitialized = true;
            alertOffset = relayExisting ? 0L : len;
            return List.of();
        }
        if (len < alertOffset) alertOffset = 0L;
        if (len == alertOffset) return List.of();
        List<String> out = new ArrayList<>();
        try (RandomAccessFile raf = new RandomAccessFile(file, "r")) {
            raf.seek(alertOffset);
            String raw;
            while ((raw = raf.readLine()) != null) {
                String line = new String(raw.getBytes(StandardCharsets.ISO_8859_1), StandardCharsets.UTF_8).trim();
                if (!line.isBlank()) out.add(line);
            }
            alertOffset = raf.getFilePointer();
        }
        return out;
    }

    private File gstDir() { return new File(plugin.getDataFolder().getParentFile(), "GeumyiServerTools"); }
    private File runtimeDir() { return new File(gstDir(), "runtime"); }
    private File lagEventsFile() { return new File(runtimeDir(), "lag-events.jsonl"); }

    @Override public void close() { io.shutdown(); }
}
