package kr.geumyi.lobby;

import java.util.List;
import java.util.function.BiConsumer;
import java.util.function.Supplier;
import org.bukkit.Bukkit;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.inventory.InventoryClickEvent;
import org.bukkit.event.inventory.InventoryDragEvent;
import org.bukkit.inventory.Inventory;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.meta.ItemMeta;
import org.bukkit.plugin.java.JavaPlugin;

/**
 * Player-facing GUI; routing is delegated to the existing GSC-gated transfer method.
 * Does not offer unverified live-status counts or any administrator operations.
 */
public final class GeumyiLobbyMenu implements Listener {
    private static final String HOME = "§0금이 | 네트워크";
    private static final String SERVERS = "§0금이 | 서버 소개";
    private static final String GUIDE = "§0금이 | 이용 방법";
    private static final String SYSTEM = "§0금이 | 시스템 안내";
    private static final String RULES = "§0금이 | 기본 규칙";
    private static final String HELP = "§0금이 | 도움말";

    private final JavaPlugin plugin;
    private final BiConsumer<Player, String> transfer;
    private final Supplier<Location> spawn;
    private final String wild;
    private final String playground;
    private final String other;

    public GeumyiLobbyMenu(JavaPlugin plugin, BiConsumer<Player, String> transfer,
                           Supplier<Location> spawn, String wild, String playground, String other) {
        this.plugin = plugin;
        this.transfer = transfer;
        this.spawn = spawn;
        this.wild = wild;
        this.playground = playground;
        this.other = other;
    }

    private static ItemStack item(Material type, String name, String... lore) {
        ItemStack stack = new ItemStack(type);
        ItemMeta meta = stack.getItemMeta();
        if (meta != null) {
            meta.setDisplayName(name);
            meta.setLore(List.of(lore));
            stack.setItemMeta(meta);
        }
        return stack;
    }

    private Inventory page(String title) {
        Inventory inv = Bukkit.createInventory(null, 54, title);
        ItemStack background = item(Material.GRAY_STAINED_GLASS_PANE, "§8 ");
        ItemStack border = item(Material.BLACK_STAINED_GLASS_PANE, "§8 ");
        for (int i = 0; i < 54; i++) inv.setItem(i, background);
        for (int i = 0; i < 9; i++) {
            inv.setItem(i, border);
            inv.setItem(i + 45, border);
        }
        inv.setItem(4, item(Material.NETHER_STAR, "§6§lGEUMYI NETWORK",
                "§7야생 · 놀이터 · 기타 · 로비", "§7Java / Bedrock 연동 네트워크"));
        inv.setItem(49, item(Material.ARROW, "§e메인 메뉴로", "§7돌아가기"));
        inv.setItem(53, item(Material.BARRIER, "§c닫기", "§7메뉴를 닫습니다."));
        return inv;
    }

    public void open(Player player) {
        Inventory inv = page(HOME);
        inv.setItem(20, item(Material.GRASS_BLOCK, "§a§l01  야생 서버",
                "§f생존 · 탐험 · 건축", "§7Technology · Chemistry 콘텐츠", "§7마지막 위치로 복귀 지원", "§e클릭하여 이동"));
        inv.setItem(22, item(Material.DIAMOND, "§b§l02  놀이터 서버",
                "§f창작 · 건축 · 실험 공간", "§7야생과 분리된 독립 월드", "§7마지막 위치로 복귀 지원", "§e클릭하여 이동"));
        inv.setItem(24, item(Material.AMETHYST_SHARD, "§d§l03  기타 서버",
                "§f확장형 별도 콘텐츠 서버", "§7온라인 상태일 때만 이동 가능", "§7마지막 위치로 복귀 지원", "§e클릭하여 이동"));
        inv.setItem(29, item(Material.BOOK, "§e서버 소개",
                "§7각 서버의 역할과 특징", "§e클릭: 상세 설명"));
        inv.setItem(31, item(Material.COMPASS, "§b처음 오셨나요?",
                "§7나침반 · 이동 · 복귀 · 핫바", "§e클릭: 사용 안내"));
        inv.setItem(33, item(Material.REDSTONE, "§c네트워크 시스템",
                "§7GSC · GSCM · Velocity · Geyser", "§e클릭: 기술 안내"));
        inv.setItem(38, item(Material.WRITABLE_BOOK, "§6기본 규칙",
                "§7서로 배려하는 안전한 플레이", "§e클릭: 규칙 확인"));
        inv.setItem(40, item(Material.OAK_SIGN, "§a도움말 / FAQ",
                "§7접속 오류 · 서버 이동 문제", "§e클릭: 해결 방법"));
        inv.setItem(42, item(Material.CLOCK, "§f중앙 스폰으로",
                "§7로비 스폰 위치로 돌아갑니다.", "§e클릭: 로비 중앙"));
        player.openInventory(inv);
    }

    private void openInfo(Player player, String title) {
        Inventory inv = page(title);
        if (SERVERS.equals(title)) {
            inv.setItem(19, item(Material.GRASS_BLOCK, "§a야생 | Wild",
                    "§7자원 수집 · 생존 · 탐험 · 건축", "§7기술 및 화학 전용 콘텐츠", "§7서버별 저장 데이터와 위치 관리"));
            inv.setItem(21, item(Material.DIAMOND, "§b놀이터 | Playground",
                    "§7자유로운 건축·시험 환경", "§7야생과 분리된 서버", "§7이전 위치 복귀 지원"));
            inv.setItem(23, item(Material.AMETHYST_SHARD, "§d기타 | Other",
                    "§7추가 콘텐츠와 이벤트용 공간", "§7서버가 OFFLINE이면 이동 차단", "§7관리자가 켜면 접속 가능"));
            inv.setItem(25, item(Material.BEACON, "§6중앙 로비 | Lobby",
                    "§7네트워크의 공통 입구", "§7플레이어를 중앙 스폰으로 안내", "§7건축 및 아이템 보호"));
            inv.setItem(31, item(Material.ENDER_EYE, "§e접속 구조",
                    "§7공개 입장 → 로비 → 서버 이동", "§7Velocity 네트워크에서 분기", "§7Java 및 Bedrock 플레이어 지원"));
        } else if (GUIDE.equals(title)) {
            inv.setItem(19, item(Material.COMPASS, "§b1 | 나침반",
                    "§7로비 중앙 핫바의 나침반 우클릭", "§7서버 선택과 설명, 도움말 확인"));
            inv.setItem(21, item(Material.GRASS_BLOCK, "§a2 | 서버 선택",
                    "§7야생·놀이터·기타 중 하나 선택", "§7GSC가 서버 상태를 확인하고 이동", "§7오프라인 상태면 이동할 수 없음"));
            inv.setItem(23, item(Material.RECOVERY_COMPASS, "§e3 | 이전 위치",
                    "§7다른 서버로 이동한 뒤 재입장하면", "§7해당 서버의 마지막 위치로 복귀", "§8연결 플러그인에 따라 동작"));
            inv.setItem(25, item(Material.OAK_DOOR, "§6 4 | 로비 복귀",
                    "§7다른 서버에서 /lobby 사용", "§7로비 재입장 시 중앙 스폰으로 이동"));
            inv.setItem(31, item(Material.SHIELD, "§f5 | 로비 보호",
                    "§7모험 모드 · 블록 설치/파괴 제한", "§7배고픔·피해·아이템 드롭 방지"));
        } else if (SYSTEM.equals(title)) {
            inv.setItem(19, item(Material.ENDER_EYE, "§bVelocity",
                    "§7서버 사이 이동을 중계하는 프록시", "§7중앙 로비에서 각 서버로 분기"));
            inv.setItem(21, item(Material.HEART_OF_THE_SEA, "§3Geyser / Floodgate",
                    "§7베드락 플레이어의 접속을 지원", "§7에디션별 차이는 발생할 수 있음"));
            inv.setItem(23, item(Material.REDSTONE, "§cGSC",
                    "§7서버 실행·상태·작업·백업 관리", "§7업데이트 및 복구 기능", "§8관리자 전용 도구"));
            inv.setItem(25, item(Material.CLOCK, "§eGSCM",
                    "§7관리자용 모바일 원격 모니터링", "§7상태·콘솔·작업 흐름 확인", "§8권한이 부여된 기기만 사용"));
            inv.setItem(31, item(Material.CHEST, "§6백업과 복구",
                    "§7운영자는 보호된 복구 지점을 관리", "§7월드 손실 방지를 우선함", "§8실제 백업 상태는 관리자 확인 필요"));
        } else if (RULES.equals(title)) {
            inv.setItem(20, item(Material.SHIELD, "§a서로 배려하기",
                    "§7괴롭힘·도배·의도적인 방해 금지", "§7다른 플레이어의 작품과 자산 존중"));
            inv.setItem(22, item(Material.TNT, "§c악의적인 파괴 금지",
                    "§7월드와 서버의 안정성을 해치지 않기", "§7버그를 악용하지 말고 신고하기"));
            inv.setItem(24, item(Material.WRITABLE_BOOK, "§e운영 규정",
                    "§7상세 정책은 운영자 공지를 따릅니다.", "§7여기서는 기본 안내를 제공합니다."));
        } else if (HELP.equals(title)) {
            inv.setItem(19, item(Material.BARRIER, "§c서버 이동이 안 되면",
                    "§7대상 서버 OFFLINE/점검 상태일 수 있음", "§7잠시 후 다시 시도하거나 관리자 문의"));
            inv.setItem(21, item(Material.COMPASS, "§b나침반이 없다면",
                    "§7로비 재입장 시 다시 지급됩니다.", "§7반복 발생 시 관리자에게 제보"));
            inv.setItem(23, item(Material.OAK_DOOR, "§e로비로 돌아가기",
                    "§7각 서버에서 /lobby 입력", "§7문제가 있으면 관리자에게 문의"));
            inv.setItem(25, item(Material.BOOK, "§f오류 신고하기",
                    "§7서버 이름과 발생 시간을 알려주세요.", "§7가능하면 화면·로그를 함께 보내주세요."));
            inv.setItem(31, item(Material.RECOVERY_COMPASS, "§6진행 내용이 사라졌다면",
                    "§7임의 초기화·복구 시도를 하지 마세요.", "§7운영자에게 백업 확인을 요청하세요."));
        }
        player.openInventory(inv);
    }

    private boolean recognized(String title) {
        return HOME.equals(title) || SERVERS.equals(title) || GUIDE.equals(title)
                || SYSTEM.equals(title) || RULES.equals(title) || HELP.equals(title);
    }

    @EventHandler
    public void click(InventoryClickEvent event) {
        String title = event.getView().getTitle();
        if (!recognized(title)) return;
        event.setCancelled(true);
        if (!(event.getWhoClicked() instanceof Player player)) return;
        int slot = event.getRawSlot();
        if (slot < 0 || slot >= 54) return;
        if (slot == 53) {
            player.closeInventory();
            return;
        }
        if (!HOME.equals(title)) {
            if (slot == 49) open(player);
            return;
        }
        switch (slot) {
            case 20 -> { player.closeInventory(); transfer.accept(player, wild); }
            case 22 -> { player.closeInventory(); transfer.accept(player, playground); }
            case 24 -> { player.closeInventory(); transfer.accept(player, other); }
            case 29 -> openInfo(player, SERVERS);
            case 31 -> openInfo(player, GUIDE);
            case 33 -> openInfo(player, SYSTEM);
            case 38 -> openInfo(player, RULES);
            case 40 -> openInfo(player, HELP);
            case 42 -> {
                player.closeInventory();
                Location point = spawn.get();
                if (point != null) player.teleport(point);
            }
            default -> { }
        }
    }

    @EventHandler
    public void drag(InventoryDragEvent event) {
        if (recognized(event.getView().getTitle())) event.setCancelled(true);
    }
}
