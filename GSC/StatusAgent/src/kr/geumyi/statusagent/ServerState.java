package kr.geumyi.statusagent;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

final class ServerState {
    final String id;
    volatile String name;
    volatile long lastHeartbeatMillis;
    volatile long lastEventMillis;
    volatile String mode = "UNKNOWN";
    volatile String lastEvent = "";
    volatile String lastMessage = "";
    volatile boolean plannedShutdown = false;
    volatile boolean pluginReachable = false;
    volatile boolean minecraftReachable = false;
    volatile String derivedState = "UNKNOWN";
    volatile int online = 0;
    volatile int maxPlayers = 0;
    volatile int javaPlayers = 0;
    volatile int bedrockPlayers = 0;
    volatile double tps = 0.0;
    volatile double mspt = 0.0;
    volatile double memory = 0.0;
    volatile long uptimeSeconds = 0L;
    volatile String version = "";
    volatile int reportedJavaPort = 0;
    volatile int loadedChunks = 0;
    volatile int entities = 0;
    final Map<String, String> extras = new ConcurrentHashMap<>();

    ServerState(String id, String name) {
        this.id = id;
        this.name = name;
    }
}
