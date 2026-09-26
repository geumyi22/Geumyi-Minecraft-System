package kr.geumyi.discordstatus;

record PlayerSnapshot(
    String name,
    String uuid,
    String platform,
    String world,
    int ping,
    String gameMode
) {}
