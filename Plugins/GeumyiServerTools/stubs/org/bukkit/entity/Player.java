package org.bukkit.entity;
import org.bukkit.command.CommandSender;
public interface Player extends CommandSender {
  String getName();
  void sendTitle(String title, String subtitle, int fadeIn, int stay, int fadeOut);
}
