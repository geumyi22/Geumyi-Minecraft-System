package org.bukkit.plugin;
public interface ServicesManager {
  <T> void register(Class<T> service, T provider, Plugin plugin, ServicePriority priority);
  void unregisterAll(Plugin plugin);
}
