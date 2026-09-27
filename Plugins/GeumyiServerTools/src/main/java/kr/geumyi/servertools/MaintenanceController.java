package kr.geumyi.servertools;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.util.Properties;

import org.bukkit.Bukkit;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.EventPriority;
import org.bukkit.event.Listener;
import org.bukkit.event.player.PlayerJoinEvent;
import org.bukkit.event.player.PlayerLoginEvent;
import org.bukkit.scheduler.BukkitTask;

/** Persistent, game-side maintenance mode. Does not alter the server whitelist. */
final class MaintenanceController implements Listener {
    private static final String PREFIX = "§8[§6점검§8] §r";

    private final GeumyiServerToolsV110 plugin;
    private final File stateFile;
    private volatile boolean active;
    private volatile String reason = "";
    private BukkitTask reminderTask;

    MaintenanceController(GeumyiServerToolsV110 plugin) {
        this.plugin = plugin;
        this.stateFile = new File(plugin.getDataFolder(), "maintenance.properties");
    }

    void start() {
        loadState();
        Bukkit.getPluginManager().registerEvents(this, plugin);
        restartReminder();
        if (active) {
            plugin.getLogger().warning("Maintenance mode restored from previous session: " + reason);
        }
    }

    void shutdown() {
        if (reminderTask != null) reminderTask.cancel();
        reminderTask = null;
        saveState();
    }

    void reloadSettings() {
        restartReminder();
    }

    boolean isActive() { return active; }
    String reason() { return reason == null ? "" : reason; }

    void enable(String requestedReason) {
        if (!plugin.getConfig().getBoolean("maintenance.enabled", true)) return;
        String r = requestedReason == null ? "" : requestedReason.trim();
        if (r.isBlank()) r = plugin.getConfig().getString("maintenance.default-reason", "서버 점검 중입니다.");
        active = true;
        reason = r;
        saveState();
        announce("§e점검 모드가 시작되었습니다. §f" + r, true);
        restartReminder();
    }

    void disable(String note) {
        boolean was = active;
        active = false;
        reason = "";
        saveState();
        restartReminder();
        if (was) announce("§a점검 모드가 종료되었습니다. §f" + (note == null ? "" : note), false);
    }

    boolean handleCommand(CommandSender sender, String[] args) {
        if (args.length < 2 || args[1].equalsIgnoreCase("status")) {
            sender.sendMessage(PREFIX + (active ? "§e활성 §f- " + reason() : "§a비활성"));
            sender.sendMessage(PREFIX + "§7신규 접속 차단: §f" + plugin.getConfig().getBoolean("maintenance.block-new-joins", true));
            return true;
        }
        if (args[1].equalsIgnoreCase("on")) {
            String r = joinTail(args, 2);
            enable(r);
            sender.sendMessage(PREFIX + "§a점검 모드를 켰습니다.");
            return true;
        }
        if (args[1].equalsIgnoreCase("off")) {
            disable("관리자 명령");
            sender.sendMessage(PREFIX + "§a점검 모드를 껐습니다.");
            return true;
        }
        sender.sendMessage(PREFIX + "§7사용법: /gst maintenance <on|off|status> [사유]");
        return true;
    }

    @EventHandler(priority = EventPriority.HIGHEST)
    public void onLogin(PlayerLoginEvent event) {
        if (!active || !plugin.getConfig().getBoolean("maintenance.block-new-joins", true)) return;
        Player player = event.getPlayer();
        if (player.hasPermission("geumyiservertools.maintenance.bypass")) return;
        String msg = "§6서버 점검 중입니다.\n§f" + reason();
        event.disallow(PlayerLoginEvent.Result.KICK_OTHER, msg);
    }

    @EventHandler
    public void onJoin(PlayerJoinEvent event) {
        if (!active) return;
        Player p = event.getPlayer();
        p.sendMessage(PREFIX + "§e현재 서버가 점검 모드입니다. §f" + reason());
        if (plugin.getConfig().getBoolean("maintenance.show-title", true)) {
            p.sendTitle("§6§l점검 모드", "§f" + reason(), 10, 60, 10);
        }
    }

    private void restartReminder() {
        if (reminderTask != null) reminderTask.cancel();
        reminderTask = null;
        if (!active) return;
        int seconds = Math.max(15, plugin.getConfig().getInt("maintenance.reminder-seconds", 60));
        reminderTask = Bukkit.getScheduler().runTaskTimer(plugin, () -> {
            if (!active) return;
            for (Player p : Bukkit.getOnlinePlayers()) {
                p.sendMessage(PREFIX + "§e점검 중 §7- §f" + reason());
            }
        }, seconds * 20L, seconds * 20L);
    }

    private void announce(String message, boolean title) {
        plugin.getLogger().info(stripColor(message));
        for (Player p : Bukkit.getOnlinePlayers()) {
            p.sendMessage(PREFIX + message);
            if (title && plugin.getConfig().getBoolean("maintenance.show-title", true)) {
                p.sendTitle("§6§l점검 모드", "§f" + reason(), 10, 60, 10);
            }
        }
    }

    private void loadState() {
        if (!plugin.getConfig().getBoolean("maintenance.persist-state", true) || !stateFile.isFile()) return;
        Properties p = new Properties();
        try (FileInputStream in = new FileInputStream(stateFile)) {
            p.load(in);
            active = Boolean.parseBoolean(p.getProperty("active", "false"));
            reason = p.getProperty("reason", "");
        } catch (Exception e) {
            plugin.getLogger().warning("Could not load maintenance state: " + e.getMessage());
        }
    }

    private void saveState() {
        if (!plugin.getConfig().getBoolean("maintenance.persist-state", true)) return;
        try {
            plugin.getDataFolder().mkdirs();
            Properties p = new Properties();
            p.setProperty("active", Boolean.toString(active));
            p.setProperty("reason", reason());
            try (FileOutputStream out = new FileOutputStream(stateFile)) {
                p.store(out, "GeumyiServerTools 1.1 maintenance state");
            }
        } catch (Exception e) {
            plugin.getLogger().warning("Could not save maintenance state: " + e.getMessage());
        }
    }

    private static String joinTail(String[] a, int start) {
        if (a.length <= start) return "";
        StringBuilder b = new StringBuilder();
        for (int i = start; i < a.length; i++) {
            if (b.length() > 0) b.append(' ');
            b.append(a[i]);
        }
        return b.toString().trim();
    }

    private static String stripColor(String s) {
        return s == null ? "" : s.replaceAll("§.", "");
    }
}
