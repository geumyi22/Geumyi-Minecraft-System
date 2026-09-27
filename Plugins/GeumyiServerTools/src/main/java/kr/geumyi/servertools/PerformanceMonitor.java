package kr.geumyi.servertools;

import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;
import java.lang.reflect.Method;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;
import java.util.Locale;

import org.bukkit.Bukkit;
import org.bukkit.World;

/**
 * Cross-platform performance sampler for Spigot/Paper 26.3.
 *
 * Paper metrics are used reflectively when present. On plain Spigot, TPS is
 * derived from the wall-clock time taken to execute the configured number of
 * server ticks, while MSPT is estimated from Server-thread CPU time plus tick
 * overrun. This avoids hard-linking Paper-only methods into the class file.
 */
final class PerformanceMonitor {
    private final GeumyiServerTools plugin;
    private final Deque<MetricsSnapshot> history = new ArrayDeque<>();
    private MetricsSnapshot latest;
    private int badSamples;
    private long lastAlert;

    private long lastWallNanos;
    private long lastCpuNanos = -1L;
    private double fallbackTps1 = 20.0;
    private double fallbackTps5 = 20.0;
    private double fallbackTps15 = 20.0;

    PerformanceMonitor(GeumyiServerTools plugin) {
        this.plugin = plugin;
    }

    void sample() {
        Perf perf = measurePerformance();
        double tps1 = perf.tps1();
        double tps5 = perf.tps5();
        double tps15 = perf.tps15();
        double mspt = perf.mspt();

        Runtime rt = Runtime.getRuntime();
        long maxMemory = Math.max(1L, rt.maxMemory());
        long usedMemory = Math.max(0L, rt.totalMemory() - rt.freeMemory());

        int loadedChunks = 0;
        int entities = 0;
        for (World world : Bukkit.getWorlds()) {
            try { loadedChunks += world.getLoadedChunks().length; } catch (Throwable ignored) {}
            try { entities += world.getEntities().size(); } catch (Throwable ignored) {}
        }

        latest = new MetricsSnapshot(
                System.currentTimeMillis(), tps1, tps5, tps15, mspt,
                usedMemory, maxMemory, Bukkit.getOnlinePlayers().size(), loadedChunks, entities);
        history.addLast(latest);

        int historySize = Math.max(12, plugin.getConfig().getInt("monitor.history-size", 120));
        while (history.size() > historySize) history.removeFirst();

        double lowTps = plugin.getConfig().getDouble("monitor.low-tps", 18.0);
        double highMspt = plugin.getConfig().getDouble("monitor.high-mspt", 50.0);
        double highMemory = plugin.getConfig().getDouble("monitor.high-memory-percent", 85.0);
        boolean bad = tps1 < lowTps || mspt > highMspt || latest.memoryPercent() > highMemory;
        if (bad) badSamples++; else badSamples = 0;

        int needed = Math.max(1, plugin.getConfig().getInt("monitor.consecutive-samples", 3));
        long cooldown = Math.max(10, plugin.getConfig().getInt("monitor.alert-cooldown-seconds", 60)) * 1000L;
        if (badSamples >= needed && System.currentTimeMillis() - lastAlert >= cooldown
                && plugin.getConfig().getBoolean("notifications.performance-alerts", true)) {
            lastAlert = System.currentTimeMillis();
            plugin.alertAdmins("§c성능 경고 §7TPS §f" + fmt(tps1)
                    + " §8| §7MSPT §f" + fmt(mspt)
                    + " §8| §7RAM §f" + fmt(latest.memoryPercent()) + "%");
        }
    }

    MetricsSnapshot latest() {
        if (latest == null) sample();
        return latest;
    }

    List<MetricsSnapshot> history() {
        return new ArrayList<>(history);
    }

    String healthText() {
        MetricsSnapshot s = latest();
        if (s.tps1m() >= 19.0 && s.mspt() < 40.0 && s.memoryPercent() < 80.0) return "§a정상";
        if (s.tps1m() >= 18.0 && s.mspt() < 50.0 && s.memoryPercent() < 90.0) return "§e주의";
        return "§c성능 저하";
    }

    List<String> recommendations() {
        MetricsSnapshot s = latest();
        List<String> out = new ArrayList<>();
        if (s.mspt() > 50.0) out.add("MSPT가 50ms를 넘었습니다. /gst scan으로 무거운 청크를 확인하세요.");
        if (s.tps1m() < 18.0) out.add("TPS가 낮습니다. 엔티티 수와 플러그인 작업량을 확인하세요.");
        if (s.memoryPercent() > 90.0) out.add("힙 메모리 사용률이 90%를 넘었습니다. 메모리 압박과 GC를 확인하세요.");
        if (s.entities() > Math.max(1000, s.loadedChunks() * 12)) out.add("로드된 청크 대비 엔티티가 많습니다. 몹/아이템 밀집 구역을 확인하세요.");
        if (out.isEmpty()) out.add("현재 뚜렷한 성능 병목 신호는 없습니다.");
        return out;
    }

    private Perf measurePerformance() {
        long now = System.nanoTime();
        long cpuNow = currentThreadCpuTime();
        int intervalSeconds = Math.max(1, plugin.getConfig().getInt("monitor.interval-seconds", 5));
        double fallbackMspt = 0.0;

        if (lastWallNanos != 0L) {
            long elapsedNanos = Math.max(1L, now - lastWallNanos);
            double elapsedSeconds = elapsedNanos / 1_000_000_000.0;
            double expectedSeconds = intervalSeconds;
            boolean normalInterval = elapsedSeconds >= expectedSeconds * 0.65;
            double expectedTicks = normalInterval ? intervalSeconds * 20.0 : Math.max(1.0, elapsedSeconds * 20.0);
            double instantTps = normalInterval ? clamp(expectedTicks / elapsedSeconds, 0.0, 20.0) : 20.0;

            fallbackTps1 = ewma(fallbackTps1, instantTps, elapsedSeconds, 60.0);
            fallbackTps5 = ewma(fallbackTps5, instantTps, elapsedSeconds, 300.0);
            fallbackTps15 = ewma(fallbackTps15, instantTps, elapsedSeconds, 900.0);

            double cpuMsPerTick = 0.0;
            if (cpuNow >= 0L && lastCpuNanos >= 0L && cpuNow >= lastCpuNanos) {
                cpuMsPerTick = ((cpuNow - lastCpuNanos) / 1_000_000.0) / expectedTicks;
            }
            double wallMsPerTick = (elapsedNanos / 1_000_000.0) / expectedTicks;
            double overrunMs = Math.max(0.0, wallMsPerTick - 50.0);
            fallbackMspt = Math.max(cpuMsPerTick, overrunMs);
        }

        lastWallNanos = now;
        lastCpuNanos = cpuNow;

        double[] paperTps = paperTps();
        Double paperMspt = paperAverageTickTime();
        double t1 = paperTps != null && paperTps.length > 0 ? saneTps(paperTps[0]) : fallbackTps1;
        double t5 = paperTps != null && paperTps.length > 1 ? saneTps(paperTps[1]) : fallbackTps5;
        double t15 = paperTps != null && paperTps.length > 2 ? saneTps(paperTps[2]) : fallbackTps15;
        double mspt = paperMspt != null && Double.isFinite(paperMspt) && paperMspt >= 0.0
                ? paperMspt : Math.max(0.0, fallbackMspt);
        return new Perf(t1, t5, t15, mspt);
    }

    private static double[] paperTps() {
        try {
            Object server = Bukkit.class.getMethod("getServer").invoke(null);
            Method method = server.getClass().getMethod("getTPS");
            Object value = method.invoke(server);
            return value instanceof double[] arr ? arr : null;
        } catch (Throwable ignored) {
            return null;
        }
    }

    private static Double paperAverageTickTime() {
        try {
            Object server = Bukkit.class.getMethod("getServer").invoke(null);
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

    private static String fmt(double value) {
        return String.format(Locale.ROOT, "%.1f", value);
    }

    private record Perf(double tps1, double tps5, double tps15, double mspt) {}
}
