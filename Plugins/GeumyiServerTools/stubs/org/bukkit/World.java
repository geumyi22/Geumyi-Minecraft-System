package org.bukkit;
import java.util.List;
import org.bukkit.entity.Entity;
public interface World {
  String getName();
  Chunk[] getLoadedChunks();
  List<Entity> getEntities();
  <T> boolean setGameRule(GameRule<T> rule, T newValue);
}
