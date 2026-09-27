package kr.geumyi.servertools;

import org.bukkit.Bukkit;
import org.bukkit.GameRule;
import org.bukkit.World;
import org.bukkit.plugin.Plugin;
import org.bukkit.plugin.java.JavaPlugin;

/** Spigot/Paper 26.3 compatible idle world time/weather freeze. */
final class IdleFreezeController {
    private IdleFreezeController() {}

    static void sync(JavaPlugin plugin) {
        if (!plugin.getConfig().getBoolean("idle-freeze.enabled", true)) {
            apply(plugin, true);
            return;
        }
        apply(plugin, !Bukkit.getOnlinePlayers().isEmpty());
    }

    static void onPlayerJoin() {
        JavaPlugin plugin = plugin();
        if (plugin != null && plugin.getConfig().getBoolean("idle-freeze.enabled", true)) apply(plugin, true);
    }

    static void onPlayerQuit() {
        if (Bukkit.getOnlinePlayers().size() > 1) return;
        JavaPlugin plugin = plugin();
        if (plugin != null && plugin.getConfig().getBoolean("idle-freeze.enabled", true)) apply(plugin, false);
    }

    static void onPluginDisable(JavaPlugin plugin) {
        apply(plugin, true);
    }

    private static JavaPlugin plugin() {
        try {
            Plugin p = Bukkit.getPluginManager().getPlugin("GeumyiServerTools");
            return p instanceof JavaPlugin jp ? jp : null;
        } catch (Throwable ignored) {
            return null;
        }
    }

    private static void apply(JavaPlugin plugin, boolean advance) {
        boolean time = plugin.getConfig().getBoolean("idle-freeze.freeze-time", true);
        boolean weather = plugin.getConfig().getBoolean("idle-freeze.freeze-weather", true);
        for (World world : Bukkit.getWorlds()) {
            try { if (time) world.setGameRule(GameRule.ADVANCE_TIME, advance); } catch (Throwable ignored) {}
            try { if (weather) world.setGameRule(GameRule.ADVANCE_WEATHER, advance); } catch (Throwable ignored) {}
        }
    }
}
