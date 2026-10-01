package kr.geumyi.lobby;

import org.bukkit.Bukkit;
import org.bukkit.GameMode;
import org.bukkit.GameRule;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.World;
import org.bukkit.block.Block;
import org.bukkit.command.Command;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockPlaceEvent;
import org.bukkit.event.entity.EntityDamageEvent;
import org.bukkit.event.entity.EntityPickupItemEvent;
import org.bukkit.event.entity.FoodLevelChangeEvent;
import org.bukkit.event.inventory.InventoryClickEvent;
import org.bukkit.event.inventory.InventoryDragEvent;
import org.bukkit.event.player.PlayerDropItemEvent;
import org.bukkit.event.player.PlayerInteractEvent;
import org.bukkit.event.player.PlayerJoinEvent;
import org.bukkit.event.player.PlayerMoveEvent;
import org.bukkit.event.player.PlayerQuitEvent;
import org.bukkit.event.player.PlayerRespawnEvent;
import org.bukkit.inventory.Inventory;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.meta.ItemMeta;
import org.bukkit.plugin.java.JavaPlugin;

import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class GeumyiLobby extends JavaPlugin implements Listener {
    private static final String MENU_TITLE = "§0서버 선택";
    private static final int BUILD_VERSION = 1;

    private final Map<UUID, Long> portalCooldown = new ConcurrentHashMap<>();
    private World lobbyWorld;
    private Location lobbySpawn;
    private String wildServer;
    private String playgroundServer;
    private String otherServer;
    private boolean portalTrigger;
    private HttpClient http;
    private URI serverStateApi;
    private Duration requestTimeout;

    @Override
    public void onEnable() {
        saveDefaultConfig();
        wildServer = getConfig().getString("wild-server", "wild");
        playgroundServer = getConfig().getString("playground-server", "playground");
        otherServer = getConfig().getString("other-server", "other");
        portalTrigger = getConfig().getBoolean("portal-trigger", true);

        int timeoutMillis = Math.max(500, Math.min(10000, getConfig().getInt("request-timeout-millis", 2000)));
        requestTimeout = Duration.ofMillis(timeoutMillis);
        String stateApi = getConfig().getString(
                "gsc-state-api",
                "http://127.0.0.1:8787/api/v4/network/server-state"
        ).trim();
        serverStateApi = URI.create(stateApi);
        if (!"http".equalsIgnoreCase(serverStateApi.getScheme()) || !isLoopbackHost(serverStateApi.getHost())) {
            getLogger().severe("gsc-state-api must use loopback HTTP (127.0.0.1/localhost/::1).");
            getServer().getPluginManager().disablePlugin(this);
            return;
        }
        http = HttpClient.newBuilder()
                .connectTimeout(requestTimeout)
                .version(HttpClient.Version.HTTP_1_1)
                .build();

        getServer().getMessenger().registerOutgoingPluginChannel(this, "BungeeCord");
        getServer().getPluginManager().registerEvents(this, this);

        if (getCommand("lobbyadmin") != null) {
            getCommand("lobbyadmin").setExecutor(this::onLobbyAdmin);
        }

        getServer().getScheduler().runTask(this, this::initializeLobby);
    }

    private boolean isLoopbackHost(String host) {
        if (host == null) {
            return false;
        }
        String h = host.toLowerCase();
        return h.equals("127.0.0.1") || h.equals("localhost") || h.equals("::1")
                || h.equals("0:0:0:0:0:0:0:1");
    }

    private void initializeLobby() {
        String worldName = getConfig().getString("world", "world");
        lobbyWorld = Bukkit.getWorld(worldName);
        if (lobbyWorld == null && !Bukkit.getWorlds().isEmpty()) {
            lobbyWorld = Bukkit.getWorlds().get(0);
            getLogger().warning("Configured lobby world was unavailable; using " + lobbyWorld.getName());
        }
        if (lobbyWorld == null) {
            throw new IllegalStateException("No lobby world is loaded");
        }

        lobbySpawn = new Location(
                lobbyWorld,
                getConfig().getDouble("spawn.x", 0.5),
                getConfig().getDouble("spawn.y", 81.0),
                getConfig().getDouble("spawn.z", 0.5),
                (float) getConfig().getDouble("spawn.yaw", 0.0),
                (float) getConfig().getDouble("spawn.pitch", 0.0)
        );

        lobbyWorld.setSpawnLocation(
                lobbySpawn.getBlockX(),
                lobbySpawn.getBlockY(),
                lobbySpawn.getBlockZ()
        );
        lobbyWorld.setTime(6000L);
        lobbyWorld.setStorm(false);
        lobbyWorld.setThundering(false);
        lobbyWorld.setGameRule(GameRule.DO_DAYLIGHT_CYCLE, false);
        lobbyWorld.setGameRule(GameRule.DO_WEATHER_CYCLE, false);
        lobbyWorld.setGameRule(GameRule.DO_MOB_SPAWNING, false);
        lobbyWorld.setGameRule(GameRule.KEEP_INVENTORY, true);

        if (getConfig().getBoolean("build-on-start", true) && !buildMarker().isFile()) {
            buildLobby();
            writeBuildMarker();
        }

        for (Player player : lobbyWorld.getPlayers()) {
            preparePlayer(player, true);
        }
    }

    private File buildMarker() {
        return new File(getDataFolder(), "lobby-build-v" + BUILD_VERSION + ".marker");
    }

    private void writeBuildMarker() {
        try {
            if (!getDataFolder().isDirectory() && !getDataFolder().mkdirs()) {
                throw new IOException("cannot create plugin data directory");
            }
            if (!buildMarker().createNewFile() && !buildMarker().isFile()) {
                throw new IOException("cannot create build marker");
            }
        } catch (IOException e) {
            getLogger().warning("Could not persist lobby build marker: " + e.getMessage());
        }
    }

    private void setRelative(int x, int y, int z, Material material) {
        int baseX = lobbySpawn.getBlockX();
        int floorY = lobbySpawn.getBlockY() - 1;
        int baseZ = lobbySpawn.getBlockZ();
        Block block = lobbyWorld.getBlockAt(baseX + x, floorY + y, baseZ + z);
        block.setType(material, false);
    }

    private void buildLobby() {
        getLogger().info("Building Day 10 lobby plaza v" + BUILD_VERSION + "...");
        final int radius = 36;

        for (int x = -radius; x <= radius; x++) {
            for (int z = -radius; z <= radius; z++) {
                int d2 = x * x + z * z;
                if (d2 > radius * radius) {
                    continue;
                }

                setRelative(x, -3, z, Material.STONE);
                setRelative(x, -2, z, Material.STONE_BRICKS);
                setRelative(x, -1, z, Material.SMOOTH_STONE);

                Material floor = Material.GRASS_BLOCK;
                if (d2 <= 14 * 14) {
                    floor = Material.SMOOTH_QUARTZ;
                }
                if (Math.abs(z) <= 3 && Math.abs(x) <= 31) {
                    floor = Material.POLISHED_ANDESITE;
                }
                setRelative(x, 0, z, floor);
            }
        }

        // Invisible safety rail around the floating plaza.
        for (int x = -38; x <= 38; x++) {
            for (int z = -38; z <= 38; z++) {
                int d2 = x * x + z * z;
                if (d2 < 36 * 36 || d2 > 38 * 38) {
                    continue;
                }
                for (int y = 1; y <= 4; y++) {
                    setRelative(x, y, z, Material.BARRIER);
                }
            }
        }

        buildCenter();
        buildWildGate();
        buildPlaygroundGate();
        buildOtherGate();
        buildTree(-18, -18);
        buildTree(-18, 18);
        buildTree(18, -18);
        buildTree(18, 18);

        getLogger().info("Lobby plaza build complete.");
    }

    private void buildCenter() {
        int[][] lights = {
                {4, 0}, {-4, 0}, {0, 4}, {0, -4},
                {3, 3}, {3, -3}, {-3, 3}, {-3, -3}
        };
        for (int[] p : lights) {
            setRelative(p[0], 0, p[1], Material.SEA_LANTERN);
        }

        for (int x = -2; x <= 2; x++) {
            for (int z = -2; z <= 2; z++) {
                if (Math.abs(x) == 2 || Math.abs(z) == 2) {
                    setRelative(x, 0, z, Material.GOLD_BLOCK);
                }
            }
        }
        setRelative(0, 0, 0, Material.SEA_LANTERN);
    }

    private void buildWildGate() {
        for (int z : new int[]{-4, 4}) {
            for (int y = 1; y <= 6; y++) {
                setRelative(-27, y, z, Material.OAK_LOG);
            }
        }
        for (int z = -4; z <= 4; z++) {
            setRelative(-27, 7, z, Material.OAK_LOG);
            if (Math.abs(z) >= 2) {
                setRelative(-27, 6, z, Material.OAK_LEAVES);
            }
        }
        for (int x = -31; x <= -27; x++) {
            for (int z = -3; z <= 3; z++) {
                setRelative(x, 0, z, (x + z) % 2 == 0 ? Material.MOSS_BLOCK : Material.GRASS_BLOCK);
            }
        }
        setRelative(-29, 0, 0, Material.EMERALD_BLOCK);
        setRelative(-29, 1, 0, Material.SEA_LANTERN);
    }

    private void buildPlaygroundGate() {
        for (int z : new int[]{-4, 4}) {
            for (int y = 1; y <= 6; y++) {
                setRelative(27, y, z, Material.QUARTZ_PILLAR);
            }
        }
        for (int z = -4; z <= 4; z++) {
            setRelative(27, 7, z, Material.QUARTZ_BLOCK);
        }
        for (int x = 27; x <= 31; x++) {
            for (int z = -3; z <= 3; z++) {
                Material m = ((x + z) & 1) == 0 ? Material.CYAN_CONCRETE : Material.MAGENTA_CONCRETE;
                setRelative(x, 0, z, m);
            }
        }
        setRelative(29, 0, 0, Material.DIAMOND_BLOCK);
        setRelative(29, 1, 0, Material.SEA_LANTERN);
    }

    private void buildOtherGate() {
        // North gate: a third portal without changing the two existing gates.
        for (int x : new int[]{-4, 4}) {
            for (int y = 1; y <= 6; y++) {
                setRelative(x, y, -27, Material.DEEPSLATE_BRICKS);
            }
        }
        for (int x = -4; x <= 4; x++) {
            setRelative(x, 7, -27, Material.POLISHED_DEEPSLATE);
        }
        for (int z = -31; z <= -27; z++) {
            for (int x = -3; x <= 3; x++) {
                setRelative(x, 0, z, ((x + z) & 1) == 0 ? Material.POLISHED_DEEPSLATE : Material.STONE_BRICKS);
            }
        }
        setRelative(0, 0, -29, Material.AMETHYST_BLOCK);
        setRelative(0, 1, -29, Material.SEA_LANTERN);
    }

    private void buildTree(int x, int z) {
        for (int y = 1; y <= 5; y++) {
            setRelative(x, y, z, Material.OAK_LOG);
        }
        for (int dx = -2; dx <= 2; dx++) {
            for (int dz = -2; dz <= 2; dz++) {
                for (int dy = 4; dy <= 6; dy++) {
                    if (Math.abs(dx) + Math.abs(dz) + Math.abs(dy - 5) <= 4) {
                        setRelative(x + dx, dy, z + dz, Material.OAK_LEAVES);
                    }
                }
            }
        }
    }

    private void preparePlayer(Player player, boolean teleport) {
        if (lobbySpawn == null) {
            return;
        }
        if (teleport) {
            player.teleport(lobbySpawn);
        }
        player.setGameMode(GameMode.ADVENTURE);
        player.setFoodLevel(20);
        player.setSaturation(20.0f);
        player.setFireTicks(0);
        player.getInventory().clear();
        player.getInventory().setItem(4, selectorItem());
    }

    private ItemStack selectorItem() {
        ItemStack item = new ItemStack(Material.COMPASS);
        ItemMeta meta = item.getItemMeta();
        if (meta != null) {
            meta.setDisplayName("§b§l서버 선택");
            meta.setLore(List.of(
                    "§7우클릭하여 이동할 서버를 선택합니다.",
                    "§8Lobby는 항상 중앙에서 시작합니다."
            ));
            item.setItemMeta(meta);
        }
        return item;
    }

    private ItemStack menuItem(Material material, String name, List<String> lore) {
        ItemStack item = new ItemStack(material);
        ItemMeta meta = item.getItemMeta();
        if (meta != null) {
            meta.setDisplayName(name);
            meta.setLore(lore);
            item.setItemMeta(meta);
        }
        return item;
    }

    private void openServerMenu(Player player) {
        Inventory inv = Bukkit.createInventory(null, 9, MENU_TITLE);
        inv.setItem(2, menuItem(
                Material.GRASS_BLOCK,
                "§a§l야생 서버",
                List.of("§7마지막으로 있던 위치로 이동", "§e클릭하여 이동")
        ));
        inv.setItem(4, menuItem(
                Material.DIAMOND,
                "§b§l놀이터",
                List.of("§7마지막으로 있던 위치로 이동", "§e클릭하여 이동")
        ));
        inv.setItem(6, menuItem(
                Material.AMETHYST_SHARD,
                "§d§l기타 서버",
                List.of("§7마지막으로 있던 위치로 이동", "§e클릭하여 이동")
        ));
        player.openInventory(inv);
    }

    private void requestServer(Player player, String server) {
        long now = System.currentTimeMillis();
        long last = portalCooldown.getOrDefault(player.getUniqueId(), 0L);
        if (now - last < 1500L) {
            return;
        }
        portalCooldown.put(player.getUniqueId(), now);

        UUID uuid = player.getUniqueId();
        checkServerAsync(server).whenComplete((result, error) -> {
            getServer().getScheduler().runTask(this, () -> {
                Player live = Bukkit.getPlayer(uuid);
                if (live == null || !live.isOnline()) {
                    return;
                }
                if (error != null) {
                    live.sendMessage("§c서버 상태를 확인하지 못했습니다. 잠시 후 다시 시도해주세요.");
                    getLogger().warning("GSC server-state check failed for " + server + ": " + rootMessage(error));
                    return;
                }
                if (!result.allowed()) {
                    String reason = result.reason().isBlank() ? result.state() : result.reason();
                    live.sendMessage("§e현재 해당 서버로 이동할 수 없습니다. §7(" + reason + ")");
                    return;
                }
                sendServerNow(live, server);
            });
        });
    }

    private CompletableFuture<ServerAvailability> checkServerAsync(String server) {
        String query = "id=" + URLEncoder.encode(server, StandardCharsets.UTF_8);
        URI uri = URI.create(serverStateApi.toString() + "?" + query);
        HttpRequest request = HttpRequest.newBuilder(uri)
                .timeout(requestTimeout)
                .GET()
                .build();

        return http.sendAsync(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8))
                .thenApply(response -> {
                    if (response.statusCode() < 200 || response.statusCode() >= 300) {
                        throw new IllegalStateException("GSC server-state HTTP " + response.statusCode());
                    }
                    String body = response.body();
                    boolean allowed = booleanField(body, "move_allowed");
                    String state = stringField(body, "state");
                    String reason = stringField(body, "blocked_reason");
                    return new ServerAvailability(allowed, state, reason);
                });
    }

    private boolean booleanField(String json, String key) {
        Pattern p = Pattern.compile(Pattern.quote("\"" + key + "\"") + "\\s*:\\s*(true|false)");
        Matcher m = p.matcher(json);
        if (!m.find()) {
            throw new IllegalArgumentException("missing boolean field: " + key);
        }
        return Boolean.parseBoolean(m.group(1));
    }

    private String stringField(String json, String key) {
        Pattern p = Pattern.compile(Pattern.quote("\"" + key + "\"") + "\\s*:\\s*\"([^\"]*)\"");
        Matcher m = p.matcher(json);
        return m.find() ? m.group(1) : "";
    }

    private String rootMessage(Throwable error) {
        Throwable cursor = error;
        while (cursor.getCause() != null) {
            cursor = cursor.getCause();
        }
        return cursor.getMessage() == null ? cursor.getClass().getSimpleName() : cursor.getMessage();
    }

    private void sendServerNow(Player player, String server) {
        try {
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            DataOutputStream out = new DataOutputStream(bytes);
            out.writeUTF("Connect");
            out.writeUTF(server);
            player.sendPluginMessage(this, "BungeeCord", bytes.toByteArray());
            player.sendMessage("§7" + server + " 서버로 이동합니다...");
        } catch (IOException e) {
            player.sendMessage("§c서버 이동 요청을 만들지 못했습니다.");
            getLogger().warning("Server transfer failed: " + e.getMessage());
        }
    }

    private record ServerAvailability(boolean allowed, String state, String reason) {}

    private boolean isLobbyPlayer(Player player) {
        return lobbyWorld != null && player.getWorld().equals(lobbyWorld);
    }

    @EventHandler
    public void onJoin(PlayerJoinEvent event) {
        event.setJoinMessage(null);
        getServer().getScheduler().runTask(this, () -> preparePlayer(event.getPlayer(), true));
    }

    @EventHandler
    public void onQuit(PlayerQuitEvent event) {
        event.setQuitMessage(null);
        portalCooldown.remove(event.getPlayer().getUniqueId());
    }

    @EventHandler
    public void onRespawn(PlayerRespawnEvent event) {
        if (lobbySpawn != null) {
            event.setRespawnLocation(lobbySpawn);
        }
    }

    @EventHandler
    public void onInteract(PlayerInteractEvent event) {
        Player player = event.getPlayer();
        if (!isLobbyPlayer(player)) {
            return;
        }
        ItemStack item = event.getItem();
        if (item != null && item.getType() == Material.COMPASS) {
            event.setCancelled(true);
            openServerMenu(player);
        }
    }

    @EventHandler
    public void onMenuClick(InventoryClickEvent event) {
        if (!MENU_TITLE.equals(event.getView().getTitle())) {
            return;
        }
        event.setCancelled(true);
        if (!(event.getWhoClicked() instanceof Player player)) {
            return;
        }
        if (event.getRawSlot() == 2) {
            player.closeInventory();
            requestServer(player, wildServer);
        } else if (event.getRawSlot() == 4) {
            player.closeInventory();
            requestServer(player, playgroundServer);
        } else if (event.getRawSlot() == 6) {
            player.closeInventory();
            requestServer(player, otherServer);
        }
    }

    @EventHandler
    public void onMenuDrag(InventoryDragEvent event) {
        if (MENU_TITLE.equals(event.getView().getTitle())) {
            event.setCancelled(true);
        }
    }

    @EventHandler
    public void onMove(PlayerMoveEvent event) {
        Player player = event.getPlayer();
        if (!isLobbyPlayer(player) || lobbySpawn == null || event.getTo() == null) {
            return;
        }

        Location to = event.getTo();
        double dx = to.getX() - lobbySpawn.getX();
        double dz = to.getZ() - lobbySpawn.getZ();
        if (to.getY() < lobbySpawn.getY() - 20 || dx * dx + dz * dz > 40 * 40) {
            player.teleport(lobbySpawn);
            return;
        }

        if (!portalTrigger) {
            return;
        }
        if (Math.abs(dz) <= 4.5 && dx <= -26.0 && dx >= -33.0) {
            requestServer(player, wildServer);
        } else if (Math.abs(dz) <= 4.5 && dx >= 26.0 && dx <= 33.0) {
            requestServer(player, playgroundServer);
        } else if (Math.abs(dx) <= 4.5 && dz <= -26.0 && dz >= -33.0) {
            requestServer(player, otherServer);
        }
    }

    @EventHandler
    public void onBreak(BlockBreakEvent event) {
        if (isLobbyPlayer(event.getPlayer())) {
            event.setCancelled(true);
        }
    }

    @EventHandler
    public void onPlace(BlockPlaceEvent event) {
        if (isLobbyPlayer(event.getPlayer())) {
            event.setCancelled(true);
        }
    }

    @EventHandler
    public void onDrop(PlayerDropItemEvent event) {
        if (isLobbyPlayer(event.getPlayer())) {
            event.setCancelled(true);
        }
    }

    @EventHandler
    public void onPickup(EntityPickupItemEvent event) {
        if (event.getEntity() instanceof Player player && isLobbyPlayer(player)) {
            event.setCancelled(true);
        }
    }

    @EventHandler
    public void onDamage(EntityDamageEvent event) {
        if (event.getEntity() instanceof Player player && isLobbyPlayer(player)) {
            event.setCancelled(true);
        }
    }

    @EventHandler
    public void onHunger(FoodLevelChangeEvent event) {
        if (event.getEntity() instanceof Player player && isLobbyPlayer(player)) {
            event.setCancelled(true);
            player.setFoodLevel(20);
            player.setSaturation(20.0f);
        }
    }

    private boolean onLobbyAdmin(CommandSender sender, Command command, String label, String[] args) {
        if (!sender.hasPermission("geumyi.lobby.admin")) {
            sender.sendMessage("§c권한이 없습니다.");
            return true;
        }
        if (args.length == 0) {
            sender.sendMessage("§e/lobbyadmin rebuild §7- 로비 구조 재생성");
            sender.sendMessage("§e/lobbyadmin spawn §7- 중앙으로 이동");
            return true;
        }

        if (args[0].equalsIgnoreCase("rebuild")) {
            if (lobbyWorld == null || lobbySpawn == null) {
                sender.sendMessage("§cLobby가 아직 초기화되지 않았습니다.");
                return true;
            }
            buildLobby();
            writeBuildMarker();
            sender.sendMessage("§aLobby 구조를 재생성했습니다.");
            return true;
        }

        if (args[0].equalsIgnoreCase("spawn") && sender instanceof Player player) {
            if (lobbySpawn != null) {
                player.teleport(lobbySpawn);
            }
            return true;
        }

        sender.sendMessage("§c알 수 없는 하위 명령입니다.");
        return true;
    }
}
