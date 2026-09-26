package kr.geumyi.discordstatus;

import java.util.List;

record ServerSnapshot(
    String serverId,
    String serverName,
    String instanceId,
    String bootId,
    String pluginVersion,
    int protocolVersion,
    String mode,
    String maintenanceReason,
    String restartReason,
    long restartDueMillis,
    Metrics metrics,
    String minecraftVersion,
    String paperVersion,
    int serverPort,
    boolean gstAvailable,
    boolean discordSrvAvailable,
    List<PlayerSnapshot> players,
    List<WorldSnapshot> worlds,
    List<PluginSnapshot> plugins,
    List<DatapackSnapshot> datapacks
) {}
