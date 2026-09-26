package kr.geumyi.discordstatus;

record DatapackSnapshot(
    String name,
    boolean enabled,
    boolean required,
    String compatibility,
    String source
) {}
