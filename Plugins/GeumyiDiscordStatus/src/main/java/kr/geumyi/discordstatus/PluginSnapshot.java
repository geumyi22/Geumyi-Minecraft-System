package kr.geumyi.discordstatus;

record PluginSnapshot(
    String name,
    String version,
    boolean enabled,
    String main,
    String apiVersion
) {}
