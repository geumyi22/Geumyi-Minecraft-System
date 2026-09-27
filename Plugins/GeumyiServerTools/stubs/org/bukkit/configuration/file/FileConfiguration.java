package org.bukkit.configuration.file;
public class FileConfiguration {
  public boolean getBoolean(String path, boolean def){return def;}
  public int getInt(String path, int def){return def;}
  public double getDouble(String path, double def){return def;}
  public long getLong(String path, long def){return def;}
  public String getString(String path, String def){return def;}
  public void addDefault(String path, Object value){}
  public FileConfigurationOptions options(){return new FileConfigurationOptions();}
}
