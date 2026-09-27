package kr.geumyi.servertools;

import java.io.File;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

import org.bukkit.Bukkit;
import org.bukkit.command.CommandSender;
import org.bukkit.plugin.Plugin;

final class HealthService {
    private static final String PREFIX = "§8[§bGST§8] §r";
    private final GeumyiServerToolsV110 plugin;
    private final MaintenanceController maintenance;
    private final GscRuntimeBridge bridge;
    private final DiagnosticsService diagnostics;
    private volatile List<Check> last = List.of();
    private volatile long lastRun;

    HealthService(GeumyiServerToolsV110 plugin, MaintenanceController maintenance, GscRuntimeBridge bridge, DiagnosticsService diagnostics) {
        this.plugin = plugin;
        this.maintenance = maintenance;
        this.bridge = bridge;
        this.diagnostics = diagnostics;
    }

    void runStartupChecks() {
        last = runChecks();
        lastRun = System.currentTimeMillis();
        for (Check c : last) {
            if (c.level().equals("WARN")) plugin.getLogger().warning("[SelfTest] " + c.name() + ": " + c.detail());
            else if (c.level().equals("FAIL")) plugin.getLogger().severe("[SelfTest] " + c.name() + ": " + c.detail());
        }
        if (bridge != null) bridge.recordEvent("selftest", "GST self-test completed", summary(last));
    }

    void sendReport(CommandSender sender) {
        last = runChecks();
        lastRun = System.currentTimeMillis();
        sender.sendMessage("§8§m----------------------------------------");
        sender.sendMessage("§b§lGeumyiServerTools 1.1 Health / Self-Test");
        for (Check c : last) {
            String color = c.level().equals("PASS") ? "§a" : c.level().equals("WARN") ? "§e" : "§c";
            sender.sendMessage(color + c.level() + " §7" + c.name() + " §8- §f" + c.detail());
        }
        sender.sendMessage("§7점검 시각: §f" + Instant.ofEpochMilli(lastRun));
        sender.sendMessage("§7요약: §f" + summary(last));
    }

    private List<Check> runChecks() {
        List<Check> out = new ArrayList<>();

        int major = GscRuntimeBridge.javaMajor(System.getProperty("java.version", ""));
        out.add(new Check(major >= 25 ? "PASS" : "WARN", "Java", System.getProperty("java.version", "unknown") + " (Paper 26.3 권장 25+)"));

        File data = plugin.getDataFolder();
        boolean dirOk = data.exists() || data.mkdirs();
        boolean writable = dirOk && data.canWrite();
        out.add(new Check(writable ? "PASS" : "FAIL", "Plugin data", data.getAbsolutePath() + (writable ? " writable" : " NOT writable")));

        long free = data.getUsableSpace();
        long warnGb = Math.max(1, plugin.getConfig().getInt("gsc-v4.disk-warning-free-gb", 5));
        boolean diskOk = free <= 0 || free >= warnGb * 1024L * 1024L * 1024L;
        out.add(new Check(diskOk ? "PASS" : "WARN", "Disk free", human(free) + " free"));

        String gds = pluginVersion("GeumyiDiscordStatus");
        String gdsLevel = gds.isBlank() ? "WARN" : (gds.startsWith("1.") ? "PASS" : "WARN");
        String gdsDetail = gds.isBlank() ? "미감지 (선택 기능)" : (gds.startsWith("1.") ? "v" + gds + " enabled" : "v" + gds + " - GSC v4 연동은 1.x 권장");
        out.add(new Check(gdsLevel, "GeumyiDiscordStatus", gdsDetail));

        boolean bridgeOk = bridge == null || !bridge.isEnabled() || bridge.isHealthy();
        out.add(new Check(bridgeOk ? "PASS" : "WARN", "GSC v4 runtime", bridge == null ? "not initialized" : (bridge.isEnabled() ? bridge.runtimeDir().toAbsolutePath().toString() : "disabled")));

        if (diagnostics != null) {
            DiagnosticsService.DiagnosticsSnapshot d = diagnostics.snapshot();
            String level = d.grade().equals("CRITICAL") ? "WARN" : "PASS";
            out.add(new Check(level, "Diagnostics v2", d.grade() + " / lag_active=" + d.lagActive() + " / incidents=" + d.incidentCount()));
        } else {
            out.add(new Check("WARN", "Diagnostics v2", "not initialized"));
        }

        out.add(new Check("PASS", "Maintenance", maintenance.isActive() ? "ON - " + maintenance.reason() : "OFF"));
        if (bridge != null && bridge.previousUncleanShutdown()) {
            out.add(new Check("WARN", "Previous shutdown", "이전 GST 세션의 READY 마커가 남아 있어 비정상 종료 가능성이 있습니다."));
        }
        out.add(new Check("PASS", "Minecraft", Bukkit.getBukkitVersion() + " / " + Bukkit.getVersion()));
        return List.copyOf(out);
    }

    private String pluginVersion(String name) {
        try {
            Plugin p = Bukkit.getPluginManager().getPlugin(name);
            if (p == null || !p.isEnabled()) return "";
            return p.getDescription().getVersion();
        } catch (Throwable ignored) { return ""; }
    }

    private static String summary(List<Check> checks) {
        long fail = checks.stream().filter(c -> c.level().equals("FAIL")).count();
        long warn = checks.stream().filter(c -> c.level().equals("WARN")).count();
        return fail > 0 ? ("FAIL " + fail + " / WARN " + warn) : warn > 0 ? ("PASS with " + warn + " warning(s)") : "ALL PASS";
    }

    private static String human(long b) {
        if (b < 0) return "unknown";
        double gb = b / 1024.0 / 1024.0 / 1024.0;
        return String.format(java.util.Locale.ROOT, "%.1f GiB", gb);
    }

    private record Check(String level, String name, String detail) {}
}
