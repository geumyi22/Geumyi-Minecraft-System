package org.bukkit.event.player;
import org.bukkit.entity.Player;
public class PlayerLoginEvent {
  public enum Result { ALLOWED, KICK_BANNED, KICK_FULL, KICK_WHITELIST, KICK_OTHER }
  public Player getPlayer(){return null;}
  public void disallow(Result result, String message){}
}
