package kr.geumyi.network;

import org.bukkit.Bukkit;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.World;
import org.bukkit.block.Block;
import org.bukkit.command.Command;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.player.PlayerJoinEvent;
import org.bukkit.event.player.PlayerQuitEvent;
import org.bukkit.plugin.java.JavaPlugin;

import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Locale;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class GeumyiNetwork extends JavaPlugin implements Listener {
    private HttpClient http;
    private URI locationApi;
    private String serverId;
    private String lobbyServer;
    private boolean restoreOnJoin;
    private boolean saveOnQuit;
    private Duration requestTimeout;

    @Override
    public void onEnable() {
        saveDefaultConfig();

        serverId = getConfig().getString("server-id", "wild").trim().toLowerCase(Locale.ROOT);
        lobbyServer = getConfig().getString("lobby-server", "lobby").trim();
        restoreOnJoin = getConfig().getBoolean("restore-on-join", true);
        saveOnQuit = getConfig().getBoolean("save-on-quit", true);

        int timeoutMillis = Math.max(500, Math.min(10000, getConfig().getInt("request-timeout-millis", 2500)));
        requestTimeout = Duration.ofMillis(timeoutMillis);

        String api = getConfig().getString(
                "location-api",
                "http://127.0.0.1:8787/api/v4/player-location"
        ).trim();
        locationApi = URI.create(api);
        if (!"http".equalsIgnoreCase(locationApi.getScheme())
                || !isLoopbackHost(locationApi.getHost())) {
            getLogger().severe("location-api must use loopback HTTP (127.0.0.1/localhost/::1).");
            getServer().getPluginManager().disablePlugin(this);
            return;
        }
        if (serverId.isBlank() || "lobby".equals(serverId)) {
            getLogger().severe("GeumyiNetwork backend server-id must be a non-Lobby server.");
            getServer().getPluginManager().disablePlugin(this);
            return;
        }

        http = HttpClient.newBuilder()
                .connectTimeout(requestTimeout)
                .version(HttpClient.Version.HTTP_1_1)
                .build();

        getServer().getMessenger().registerOutgoingPluginChannel(this, "BungeeCord");
        getServer().getPluginManager().registerEvents(this, this);

        if (getCommand("lobby") != null) {
            getCommand("lobby").setExecutor(this::onLobbyCommand);
        }

        int seconds = Math.max(15, Math.min(600, getConfig().getInt("save-interval-seconds", 60)));
        long ticks = seconds * 20L;
        getServer().getScheduler().runTaskTimer(this, () -> {
            for (Player player : Bukkit.getOnlinePlayers()) {
                saveSnapshotAsync(PlayerSnapshot.of(player));
            }
        }, ticks, ticks);

        getLogger().info("GeumyiNetwork 0.1.0 enabled for backend=" + serverId);
    }

    private boolean isLoopbackHost(String host) {
        if (host == null) {
            return false;
        }
        String h = host.toLowerCase(Locale.ROOT);
        return h.equals("127.0.0.1") || h.equals("localhost") || h.equals("::1")
                || h.equals("0:0:0:0:0:0:0:1");
    }

    @EventHandler
    public void onJoin(PlayerJoinEvent event) {
        if (!restoreOnJoin) {
            return;
        }
        Player player = event.getPlayer();
        UUID uuid = player.getUniqueId();

        loadLocationAsync(uuid).whenComplete((saved, error) -> {
            getServer().getScheduler().runTask(this, () -> {
                Player live = Bukkit.getPlayer(uuid);
                if (live == null || !live.isOnline()) {
                    return;
                }
                if (error != null) {
                    getLogger().warning("Location restore API failed for " + uuid + ": " + rootMessage(error));
                    return;
                }
                Location target = saved.flatMap(this::resolveSafeLocation)
                        .orElseGet(this::defaultSpawn);
                if (target != null) {
                    live.teleport(target);
                }
            });
        });
    }

    @EventHandler
    public void onQuit(PlayerQuitEvent event) {
        if (!saveOnQuit) {
            return;
        }
        saveSnapshotAsync(PlayerSnapshot.of(event.getPlayer()));
    }

    private boolean onLobbyCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player player)) {
            sender.sendMessage("§c플레이어만 사용할 수 있습니다.");
            return true;
        }
        if (!player.hasPermission("geumyi.network.lobby")) {
            player.sendMessage("§c권한이 없습니다.");
            return true;
        }

        UUID uuid = player.getUniqueId();
        PlayerSnapshot snapshot = PlayerSnapshot.of(player);
        player.sendMessage("§7현재 위치를 저장하고 Lobby로 이동합니다...");

        saveSnapshotAsync(snapshot).whenComplete((ok, error) -> {
            getServer().getScheduler().runTask(this, () -> {
                Player live = Bukkit.getPlayer(uuid);
                if (live == null || !live.isOnline()) {
                    return;
                }
                if (error != null || !Boolean.TRUE.equals(ok)) {
                    live.sendMessage("§c위치 저장에 실패해 Lobby 이동을 취소했습니다.");
                    if (error != null) {
                        getLogger().warning("/lobby save failed for " + uuid + ": " + rootMessage(error));
                    }
                    return;
                }
                connect(live, lobbyServer);
            });
        });
        return true;
    }

    private void connect(Player player, String targetServer) {
        try {
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            DataOutputStream out = new DataOutputStream(bytes);
            out.writeUTF("Connect");
            out.writeUTF(targetServer);
            player.sendPluginMessage(this, "BungeeCord", bytes.toByteArray());
        } catch (IOException e) {
            player.sendMessage("§cLobby 이동 요청을 만들지 못했습니다.");
            getLogger().warning("Proxy transfer failed: " + e.getMessage());
        }
    }

    private CompletableFuture<Boolean> saveSnapshotAsync(PlayerSnapshot snapshot) {
        String body = "{"
                + "\"uuid\":\"" + jsonEscape(snapshot.uuid().toString()) + "\","
                + "\"server_id\":\"" + jsonEscape(serverId) + "\","
                + "\"world\":\"" + jsonEscape(snapshot.world()) + "\","
                + "\"x\":" + snapshot.x() + ","
                + "\"y\":" + snapshot.y() + ","
                + "\"z\":" + snapshot.z() + ","
                + "\"yaw\":" + snapshot.yaw() + ","
                + "\"pitch\":" + snapshot.pitch()
                + "}";

        HttpRequest request = HttpRequest.newBuilder(locationApi)
                .timeout(requestTimeout)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(body, StandardCharsets.UTF_8))
                .build();

        return http.sendAsync(request, HttpResponse.BodyHandlers.discarding())
                .thenApply(response -> response.statusCode() >= 200 && response.statusCode() < 300);
    }

    private CompletableFuture<Optional<SavedLocation>> loadLocationAsync(UUID uuid) {
        String query = "uuid=" + URLEncoder.encode(uuid.toString(), StandardCharsets.UTF_8)
                + "&server_id=" + URLEncoder.encode(serverId, StandardCharsets.UTF_8);
        URI uri = URI.create(locationApi.toString() + "?" + query);
        HttpRequest request = HttpRequest.newBuilder(uri)
                .timeout(requestTimeout)
                .GET()
                .build();

        return http.sendAsync(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8))
                .thenApply(response -> {
                    if (response.statusCode() == 404) {
                        return Optional.empty();
                    }
                    if (response.statusCode() < 200 || response.statusCode() >= 300) {
                        throw new IllegalStateException("location API HTTP " + response.statusCode());
                    }
                    return Optional.of(parseSavedLocation(response.body()));
                });
    }

    private SavedLocation parseSavedLocation(String json) {
        String world = stringField(json, "world");
        double x = numberField(json, "x");
        double y = numberField(json, "y");
        double z = numberField(json, "z");
        float yaw = (float) numberField(json, "yaw");
        float pitch = (float) numberField(json, "pitch");
        if (world.isBlank()) {
            throw new IllegalArgumentException("location API returned empty world");
        }
        return new SavedLocation(world, x, y, z, yaw, pitch);
    }

    private Optional<Location> resolveSafeLocation(SavedLocation saved) {
        World world = Bukkit.getWorld(saved.world());
        if (world == null) {
            return Optional.empty();
        }

        Location exact = new Location(
                world,
                saved.x(),
                saved.y(),
                saved.z(),
                saved.yaw(),
                saved.pitch()
        );
        if (isSafe(exact)) {
            world.getChunkAt(exact);
            return Optional.of(exact);
        }

        int baseX = exact.getBlockX();
        int baseY = exact.getBlockY();
        int baseZ = exact.getBlockZ();
        for (int distance = 1; distance <= 8; distance++) {
            for (int direction : new int[]{1, -1}) {
                int y = baseY + distance * direction;
                Location candidate = new Location(
                        world,
                        baseX + 0.5,
                        y,
                        baseZ + 0.5,
                        saved.yaw(),
                        saved.pitch()
                );
                if (isSafe(candidate)) {
                    world.getChunkAt(candidate);
                    return Optional.of(candidate);
                }
            }
        }
        return Optional.ofNullable(safeSpawn(world));
    }

    private boolean isSafe(Location location) {
        World world = location.getWorld();
        if (world == null) {
            return false;
        }
        int y = location.getBlockY();
        if (y <= world.getMinHeight() || y + 1 >= world.getMaxHeight()) {
            return false;
        }
        if (!world.getWorldBorder().isInside(location)) {
            return false;
        }

        Block feet = world.getBlockAt(location.getBlockX(), y, location.getBlockZ());
        Block head = world.getBlockAt(location.getBlockX(), y + 1, location.getBlockZ());
        Block below = world.getBlockAt(location.getBlockX(), y - 1, location.getBlockZ());

        if (dangerous(feet.getType()) || dangerous(head.getType()) || dangerous(below.getType())) {
            return false;
        }
        if (!feet.isPassable() || !head.isPassable()) {
            return false;
        }
        boolean swimming = feet.getType() == Material.WATER || head.getType() == Material.WATER;
        return swimming || below.getType().isSolid();
    }

    private boolean dangerous(Material material) {
        return switch (material) {
            case LAVA, FIRE, SOUL_FIRE, CAMPFIRE, SOUL_CAMPFIRE,
                    CACTUS, MAGMA_BLOCK, SWEET_BERRY_BUSH, WITHER_ROSE,
                    POWDER_SNOW -> true;
            default -> false;
        };
    }

    private Location safeSpawn(World world) {
        Location spawn = world.getSpawnLocation().clone().add(0.5, 0.0, 0.5);
        if (isSafe(spawn)) {
            return spawn;
        }
        int x = spawn.getBlockX();
        int z = spawn.getBlockZ();
        int y = world.getHighestBlockYAt(x, z) + 1;
        Location surface = new Location(world, x + 0.5, y, z + 0.5, spawn.getYaw(), spawn.getPitch());
        if (isSafe(surface)) {
            return surface;
        }
        return spawn;
    }

    private Location defaultSpawn() {
        if (Bukkit.getWorlds().isEmpty()) {
            return null;
        }
        return safeSpawn(Bukkit.getWorlds().get(0));
    }

    private String stringField(String json, String key) {
        Pattern p = Pattern.compile("\\\"" + Pattern.quote(key) + "\\\"\\s*:\\s*\\\"([^\\\"]*)\\\"");
        Matcher m = p.matcher(json);
        return m.find() ? jsonUnescape(m.group(1)) : "";
    }

    private double numberField(String json, String key) {
        Pattern p = Pattern.compile("\\\"" + Pattern.quote(key) + "\\\"\\s*:\\s*(-?[0-9]+(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)");
        Matcher m = p.matcher(json);
        if (!m.find()) {
            throw new IllegalArgumentException("missing numeric field: " + key);
        }
        return Double.parseDouble(m.group(1));
    }

    private String jsonEscape(String value) {
        return value.replace("\\", "\\\\").replace("\"", "\\\"");
    }

    private String jsonUnescape(String value) {
        return value.replace("\\\"", "\"").replace("\\\\", "\\");
    }

    private String rootMessage(Throwable error) {
        Throwable cursor = error;
        while (cursor.getCause() != null) {
            cursor = cursor.getCause();
        }
        return cursor.getMessage() == null ? cursor.getClass().getSimpleName() : cursor.getMessage();
    }

    private record PlayerSnapshot(
            UUID uuid,
            String world,
            double x,
            double y,
            double z,
            float yaw,
            float pitch
    ) {
        static PlayerSnapshot of(Player player) {
            Location l = player.getLocation();
            return new PlayerSnapshot(
                    player.getUniqueId(),
                    l.getWorld().getName(),
                    l.getX(),
                    l.getY(),
                    l.getZ(),
                    l.getYaw(),
                    l.getPitch()
            );
        }
    }

    private record SavedLocation(
            String world,
            double x,
            double y,
            double z,
            float yaw,
            float pitch
    ) {}
}
