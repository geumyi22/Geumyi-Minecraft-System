package org.bukkit;
import java.util.Collection;
import java.util.List;
import org.bukkit.entity.Player;
public interface Server {
  int getMaxPlayers(); Collection<? extends Player> getOnlinePlayers(); List<World> getWorlds(); String getVersion();
}
