package kr.geumyi.servertools;

import java.util.Arrays;
import java.util.Locale;
import java.util.concurrent.atomic.AtomicBoolean;

import org.bukkit.Bukkit;
import org.bukkit.command.Command;
import org.bukkit.command.CommandSender;
import org.bukkit.scheduler.BukkitTask;
import org.bukkit.plugin.ServicePriority;

/**
 * v1.1 entrypoint. Keeps the proven 0.1.5 core and adds the GSC v4 integration layer.
 */
public final class GeumyiServerToolsV110 extends GeumyiServerTools implements GeumyiServerToolsApi {
    private static final String PREFIX = "§8[§bGST§8] §r";

    private AfkRoomController afkRoom;
    private MaintenanceController maintenance;
    private GscRuntimeBridge runtimeBridge;
    private HealthService healthService;
    private DiagnosticsService diagnosticsService;
    private final AtomicBoolean prepareStopRunning = new AtomicBoolean();
    private BukkitTask prepareStopTask;

    @Override
    public void onEnable() {
        super.onEnable();
        installV4Defaults();

        afkRoom = new AfkRoomController(this);
        afkRoom.start();

        maintenance = new MaintenanceController(this);
        maintenance.start();

        runtimeBridge = new GscRuntimeBridge(this, maintenance);
        runtimeBridge.start();

        diagnosticsService = new DiagnosticsService(this, runtimeBridge);
        diagnosticsService.start();

        healthService = new HealthService(this, maintenance, runtimeBridge, diagnosticsService);
        healthService.runStartupChecks();

        Bukkit.getServicesManager().register(GeumyiServerToolsApi.class, this, this, ServicePriority.Normal);

        runtimeBridge.recordEvent("startup", "GeumyiServerTools 1.1.1 started", "GSC v4.1 diagnostics integration ready");
        getLogger().info("GeumyiServerTools 1.1.1 enabled. Diagnostics v2 and lag recorder are ready.");
    }

    @Override
    public void onDisable() {
        try { Bukkit.getServicesManager().unregisterAll(this); } catch (Throwable ignored) {}
        if (prepareStopTask != null) {
            prepareStopTask.cancel();
            prepareStopTask = null;
        }
        if (diagnosticsService != null) diagnosticsService.shutdown();
        if (runtimeBridge != null) {
            runtimeBridge.recordEvent("shutdown", "GeumyiServerTools stopping", "Plugin disable requested");
            runtimeBridge.stop();
        }
        if (maintenance != null) maintenance.shutdown();
        if (afkRoom != null) afkRoom.shutdown();
        super.onDisable();
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!command.getName().equalsIgnoreCase("gst")) {
            return super.onCommand(sender, command, label, args);
        }

        if (args.length == 0) {
            return super.onCommand(sender, command, label, args);
        }

        String sub = args[0].toLowerCase(Locale.ROOT);
        switch (sub) {
            case "afkroom" -> {
                if (!admin(sender)) return true;
                if (afkRoom == null) {
                    sender.sendMessage(PREFIX + "§cAFK 공간 모듈이 준비되지 않았습니다.");
                    return true;
                }
                return afkRoom.handleCommand(sender, args);
            }
            case "maintenance", "maint" -> {
                if (!admin(sender)) return true;
                if (maintenance == null) {
                    sender.sendMessage(PREFIX + "§c점검 모듈이 준비되지 않았습니다.");
                    return true;
                }
                boolean result = maintenance.handleCommand(sender, args);
                if (runtimeBridge != null) runtimeBridge.flushSoon();
                return result;
            }
            case "health", "selftest" -> {
                if (!admin(sender)) return true;
                if (healthService != null) healthService.sendReport(sender);
                return true;
            }
            case "bridge", "runtime" -> {
                if (!admin(sender)) return true;
                if (runtimeBridge != null) runtimeBridge.sendStatus(sender);
                return true;
            }
            case "diagnose", "diag" -> {
                if (!admin(sender)) return true;
                if (diagnosticsService != null) diagnosticsService.sendDiagnostics(sender);
                return true;
            }
            case "lag", "lagspike" -> {
                if (!admin(sender)) return true;
                if (diagnosticsService != null) diagnosticsService.sendLagStatus(sender);
                return true;
            }
            case "preparestop", "prepare-stop" -> {
                if (!admin(sender)) return true;
                handlePrepareStop(sender, Arrays.copyOfRange(args, 1, args.length));
                return true;
            }
            case "resume" -> {
                if (!admin(sender)) return true;
                if (prepareStopTask != null) {
                    prepareStopTask.cancel();
                    prepareStopTask = null;
                }
                if (maintenance != null) maintenance.disable("관리자가 정상 운영으로 복귀했습니다.");
                if (runtimeBridge != null) {
                    runtimeBridge.clearStopReady();
                    runtimeBridge.recordEvent("resume", "Normal operation resumed", senderName(sender));
                    runtimeBridge.flushSoon();
                }
                prepareStopRunning.set(false);
                sender.sendMessage(PREFIX + "§a정상 운영 상태로 복귀했습니다.");
                return true;
            }
            case "reload" -> {
                boolean handled = super.onCommand(sender, command, label, args);
                if (sender.hasPermission("geumyiservertools.admin")) {
                    if (maintenance != null) maintenance.reloadSettings();
                    if (runtimeBridge != null) runtimeBridge.reloadSettings();
                    if (diagnosticsService != null) diagnosticsService.reloadSettings();
                    if (healthService != null) healthService.runStartupChecks();
                }
                return handled;
            }
            case "help" -> {
                boolean handled = super.onCommand(sender, command, label, args);
                sendV4Help(sender);
                return handled;
            }
            case "status" -> {
                boolean handled = super.onCommand(sender, command, label, args);
                if (runtimeBridge != null) runtimeBridge.sendCompactStatus(sender);
                return handled;
            }
            default -> {
                return super.onCommand(sender, command, label, args);
            }
        }
    }

    @Override
    public String version() { return "1.1.1"; }

    @Override
    public boolean maintenanceActive() { return maintenance != null && maintenance.isActive(); }

    @Override
    public String maintenanceReason() { return maintenance == null ? "" : maintenance.reason(); }

    @Override
    public void setMaintenance(boolean enabled, String reason) {
        if (maintenance == null) return;
        if (enabled) maintenance.enable(reason);
        else maintenance.disable(reason == null ? "companion plugin request" : reason);
        if (runtimeBridge != null) {
            runtimeBridge.recordEvent(enabled ? "maintenance_on" : "maintenance_off",
                    enabled ? "Maintenance enabled through GST service API" : "Maintenance disabled through GST service API",
                    reason == null ? "" : reason);
            runtimeBridge.flushSoon();
        }
    }

    @Override
    public String runtimeSessionId() { return runtimeBridge == null ? "" : runtimeBridge.sessionId(); }

    @Override
    public boolean runtimeHealthy() { return runtimeBridge == null || runtimeBridge.isHealthy(); }

    @Override
    public String performanceSnapshotJson() { return diagnosticsService == null ? "{}" : diagnosticsService.performanceJson(); }

    @Override
    public boolean lagIncidentActive() { return diagnosticsService != null && diagnosticsService.lagActive(); }

    @Override
    public long lagIncidentCount() { return diagnosticsService == null ? 0L : diagnosticsService.lagIncidentCount(); }

    @Override
    public String runtimeStatusJson() { return runtimeBridge == null ? "{}" : runtimeBridge.lastStatusJson(); }

    private void handlePrepareStop(CommandSender sender, String[] reasonParts) {
        if (!prepareStopRunning.compareAndSet(false, true)) {
            sender.sendMessage(PREFIX + "§e이미 안전 종료 준비가 진행 중입니다.");
            return;
        }

        String reason = String.join(" ", reasonParts).trim();
        if (reason.isBlank()) reason = getConfig().getString("prepare-stop.default-reason", "서버 점검/재시작 준비");

        if (runtimeBridge != null) {
            runtimeBridge.clearStopReady();
            runtimeBridge.recordEvent("prepare_stop", "Safe stop preparation started", reason);
        }
        if (getConfig().getBoolean("prepare-stop.enable-maintenance", true) && maintenance != null) {
            maintenance.enable(reason);
        }

        boolean saveOk = true;
        if (getConfig().getBoolean("prepare-stop.save-all-flush", true)) {
            try {
                saveOk = Bukkit.dispatchCommand(Bukkit.getConsoleSender(), "save-all flush");
            } catch (Throwable t) {
                saveOk = false;
                getLogger().warning("save-all flush failed during preparestop: " + t.getMessage());
            }
        }

        final boolean saved = saveOk;
        long delay = Math.max(1L, getConfig().getLong("prepare-stop.ready-delay-ticks", 40L));
        String finalReason = reason;
        prepareStopTask = Bukkit.getScheduler().runTaskLater(this, () -> {
            if (runtimeBridge != null) {
                runtimeBridge.markStopReady(saved, finalReason);
                runtimeBridge.recordEvent(saved ? "stop_ready" : "stop_ready_warning",
                        saved ? "Server is ready for managed stop" : "Stop preparation finished with save warning",
                        finalReason);
                runtimeBridge.flushSoon();
            }
            sender.sendMessage(PREFIX + (saved
                    ? "§a저장 및 안전 종료 준비가 완료되었습니다. GSC에서 서버를 종료/재시작해도 됩니다."
                    : "§e종료 준비는 완료됐지만 save-all flush 결과를 확인해야 합니다."));
            prepareStopRunning.set(false);
            prepareStopTask = null;
        }, delay);

        sender.sendMessage(PREFIX + "§e안전 종료 준비를 시작했습니다. §7(save-all flush + GSC ready marker)");
    }

    private void sendV4Help(CommandSender sender) {
        sender.sendMessage("§8§m----------------------------------------");
        sender.sendMessage("§b§lGST 1.1 / GSC v4.1 연동 명령");
        sender.sendMessage("§7/gst maintenance <on|off|status> [사유] §f- 게임 내 점검 모드");
        sender.sendMessage("§7/gst preparestop [사유] §f- 저장 후 안전 종료 준비");
        sender.sendMessage("§7/gst resume §f- 점검/종료 준비 해제");
        sender.sendMessage("§7/gst health §f- Java/디스크/GSC 연동 자체진단");
        sender.sendMessage("§7/gst bridge §f- GSC v4 runtime bridge 상태");
        sender.sendMessage("§7/gst diagnose §f- TPS/MSPT/메모리/청크/엔티티 통합 진단");
        sender.sendMessage("§7/gst lag §f- Lag Spike Recorder 상태/최근 incident");
    }

    private boolean admin(CommandSender sender) {
        if (sender.hasPermission("geumyiservertools.admin")) return true;
        sender.sendMessage(PREFIX + "§c권한이 없습니다.");
        return false;
    }

    private String senderName(CommandSender sender) {
        try {
            return sender.getClass().getSimpleName();
        } catch (Throwable ignored) {
            return "admin";
        }
    }

    private void installV4Defaults() {
        var c = getConfig();
        c.addDefault("maintenance.enabled", true);
        c.addDefault("maintenance.block-new-joins", true);
        c.addDefault("maintenance.reminder-seconds", 60);
        c.addDefault("maintenance.show-title", true);
        c.addDefault("maintenance.default-reason", "서버 점검 중입니다.");
        c.addDefault("maintenance.persist-state", true);
        c.addDefault("prepare-stop.enable-maintenance", true);
        c.addDefault("prepare-stop.save-all-flush", true);
        c.addDefault("prepare-stop.ready-delay-ticks", 40L);
        c.addDefault("prepare-stop.default-reason", "서버 점검/재시작 준비");
        c.addDefault("gsc-v4.enabled", true);
        c.addDefault("gsc-v4.interval-seconds", 5);
        c.addDefault("gsc-v4.runtime-directory", "runtime");
        c.addDefault("gsc-v4.event-log-max-mb", 5);
        c.addDefault("gsc-v4.disk-warning-free-gb", 5);
        c.addDefault("gsc-v4.write-ready-marker", true);
        c.addDefault("lag-recorder.enabled", true);
        c.addDefault("lag-recorder.poll-seconds", 2);
        c.addDefault("lag-recorder.recovery-samples", 3);
        c.addDefault("lag-recorder.window-samples", 60);
        c.addDefault("lag-recorder.incident-history", 20);
        c.addDefault("lag-recorder.event-log-max-mb", 5);
        c.options().copyDefaults(true);
        saveConfig();
    }
}
