package org.bukkit.entity;
import java.util.UUID;
import org.bukkit.GameMode;
import org.bukkit.World;
import org.bukkit.command.CommandSender;
public interface Player extends CommandSender {
  String getName(); UUID getUniqueId(); World getWorld(); int getPing(); GameMode getGameMode(); boolean hasPlayedBefore(); void kickPlayer(String message);
}
