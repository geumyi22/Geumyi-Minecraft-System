package org.bukkit.plugin.java;
import java.io.File;
import java.util.logging.Logger;
import org.bukkit.Server;
import org.bukkit.command.*;
import org.bukkit.configuration.file.FileConfiguration;
import org.bukkit.plugin.Plugin;
import org.bukkit.plugin.PluginDescriptionFile;
public class JavaPlugin implements Plugin {
  public void onEnable(){}
  public void onDisable(){}
  public boolean onCommand(CommandSender sender, Command command, String label, String[] args){return false;}
  public void saveDefaultConfig(){}
  public void saveConfig(){}
  public void reloadConfig(){}
  public FileConfiguration getConfig(){return new FileConfiguration();}
  public Logger getLogger(){return Logger.getLogger("stub");}
  public File getDataFolder(){return new File(".");}
  public Server getServer(){return null;}
  public String getName(){return "Stub";}
  public boolean isEnabled(){return true;}
  public PluginDescriptionFile getDescription(){return new PluginDescriptionFile();}
}
