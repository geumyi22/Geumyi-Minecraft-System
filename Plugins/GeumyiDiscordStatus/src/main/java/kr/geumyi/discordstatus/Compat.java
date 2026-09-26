package kr.geumyi.discordstatus;

import org.bukkit.entity.Player;
import java.lang.reflect.Method;

final class Compat {
    private static volatile Method floodgateGetInstance;
    private static volatile Method floodgateIsPlayer;
    private static volatile boolean floodgateResolved;

    private Compat() {}

    static boolean isBedrock(Player player) {
        try {
            if (!floodgateResolved) resolveFloodgate();
            Method get = floodgateGetInstance;
            Method is = floodgateIsPlayer;
            if (get != null && is != null) {
                Object api = get.invoke(null);
                Object result = is.invoke(api, player.getUniqueId());
                if (result instanceof Boolean b) return b;
            }
        } catch (Throwable ignored) {}
        return false;
    }

    private static synchronized void resolveFloodgate() {
        if (floodgateResolved) return;
        floodgateResolved = true;
        try {
            Class<?> api = Class.forName("org.geysermc.floodgate.api.FloodgateApi");
            floodgateGetInstance = api.getMethod("getInstance");
            floodgateIsPlayer = api.getMethod("isFloodgatePlayer", java.util.UUID.class);
        } catch (Throwable ignored) {
            floodgateGetInstance = null;
            floodgateIsPlayer = null;
        }
    }
}
