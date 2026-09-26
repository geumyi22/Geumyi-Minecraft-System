package org.bukkit;
import java.util.Collection;
import java.util.List;
import org.bukkit.command.ConsoleCommandSender;
import org.bukkit.entity.Player;
import org.bukkit.plugin.PluginManager;
import org.bukkit.scheduler.BukkitScheduler;
public final class Bukkit {
  public static PluginManager getPluginManager(){return null;}
  public static BukkitScheduler getScheduler(){return null;}
  public static Server getServer(){return null;}
  public static Collection<? extends Player> getOnlinePlayers(){return java.util.List.of();}
  public static List<World> getWorlds(){return java.util.List.of();}
  public static int getMaxPlayers(){return 0;}
  public static int getPort(){return 0;}
  public static String getVersion(){return "";}
  public static String getMinecraftVersion(){return "";}
  public static int broadcastMessage(String message){return 0;}
  public static ConsoleCommandSender getConsoleSender(){return null;}
  public static boolean dispatchCommand(org.bukkit.command.CommandSender sender, String command){return false;}
  public static Player getPlayerExact(String name){return null;}
}
