package org.bukkit.configuration.file;
import java.util.List;
public class FileConfiguration {
  public boolean getBoolean(String path, boolean def){return def;}
  public int getInt(String path, int def){return def;}
  public long getLong(String path, long def){return def;}
  public double getDouble(String path, double def){return def;}
  public String getString(String path, String def){return def;}
  public List<String> getStringList(String path){return java.util.List.of();}
  public boolean contains(String path){return false;}
  public void set(String path, Object value){}
  public FileConfigurationOptions options(){return new FileConfigurationOptions();}
}
