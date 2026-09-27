package kr.geumyi.technology;

import org.bukkit.Bukkit;
import org.bukkit.Material;
import org.bukkit.NamespacedKey;
import org.bukkit.World;
import org.bukkit.block.Block;
import org.bukkit.command.Command;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.HumanEntity;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.block.Action;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockExplodeEvent;
import org.bukkit.event.block.BlockPistonExtendEvent;
import org.bukkit.event.block.BlockPistonRetractEvent;
import org.bukkit.event.block.BlockPlaceEvent;
import org.bukkit.event.entity.EntityExplodeEvent;
import org.bukkit.event.inventory.InventoryClickEvent;
import org.bukkit.event.inventory.InventoryCloseEvent;
import org.bukkit.event.inventory.InventoryDragEvent;
import org.bukkit.event.inventory.PrepareAnvilEvent;
import org.bukkit.event.inventory.PrepareItemCraftEvent;
import org.bukkit.event.player.PlayerInteractEntityEvent;
import org.bukkit.event.player.PlayerInteractEvent;
import org.bukkit.event.player.PlayerItemConsumeEvent;
import org.bukkit.inventory.EquipmentSlot;
import org.bukkit.inventory.Inventory;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.ShapedRecipe;
import org.bukkit.inventory.ShapelessRecipe;
import org.bukkit.inventory.meta.ItemMeta;
import org.bukkit.persistence.PersistentDataContainer;
import org.bukkit.persistence.PersistentDataType;
import org.bukkit.plugin.java.JavaPlugin;

import java.util.*;
import java.util.logging.Level;

/**
 * Geumyi Technology v0.1.3
 * Paper 26.3 target, internal Core/Power/Industry modules.
 * Gameplay is server-side. JE/BE resource packs are optional cosmetics; PDC is authoritative.
 */
public final class GeumyiTechnology extends JavaPlugin implements Listener {
    public static final String VERSION = "0.1.3";
    private static final String PREFIX = "§8[§bGT§8] §r";
    private static final String MAIN_TITLE = "§1§lGeumyi Technology";
    private static final String WORKBENCH_TITLE = "§6§lGT 조립 작업대";
    private static final String TECHTREE_TITLE = "§2§lGT 기술 트리";
    private static final String NETWORK_TITLE = "§b§lGT 전력망 진단";
    private static final String MACHINE_PREFIX = "§8§lGT · ";

    private NamespacedKey techIdKey;
    private NamespacedKey itemKindKey;
    private NamespacedKey itemVersionKey;
    private NamespacedKey manualRecipeKey;
    private NamespacedKey workbenchRecipeKey;
    private NamespacedKey chemistryIdKey;

    private MachineStore store;
    private PowerNetwork power;
    private List<RecipeDef> workbenchRecipes;
    private List<MachineProcess> processes;
    private final Map<UUID, BlockKey> openMachine = new HashMap<>();
    private int secondsSinceSave = 0;

    @Override
    public void onEnable() {
        techIdKey = new NamespacedKey(this, "tech_id");
        itemKindKey = new NamespacedKey(this, "item_kind");
        itemVersionKey = new NamespacedKey(this, "item_version");
        manualRecipeKey = new NamespacedKey(this, "tech_manual");
        workbenchRecipeKey = new NamespacedKey(this, "tech_workbench");
        chemistryIdKey = new NamespacedKey("geumyichemistry", "chem_id");

        saveDefaultConfig();
        workbenchRecipes = TechnologyRecipes.workbenchRecipes();
        processes = TechnologyRecipes.processes();

        store = new MachineStore(this);
        store.load();
        power = new PowerNetwork(this, store);

        Bukkit.getPluginManager().registerEvents(this, this);
        registerStarterRecipes();

        Bukkit.getScheduler().runTaskTimer(this, () -> {
            try {
                power.tickSecond();
                secondsSinceSave++;
                if (secondsSinceSave >= 60) {
                    secondsSinceSave = 0;
                    store.save();
                }
            } catch (Throwable t) {
                getLogger().log(Level.SEVERE, "전력망 tick 처리 중 오류", t);
            }
        }, 20L, 20L);

        Bukkit.getScheduler().runTaskLater(this, () -> {
            int removed = store.validateLoadedBlocks();
            if (removed > 0) store.save();
        }, 40L);

        getLogger().info("GeumyiTechnology " + VERSION + " enabled: " + TechItem.values().length
                + " tech items, " + workbenchRecipes.size() + " assembly recipes, " + processes.size() + " machine processes.");
        getLogger().info("GeumyiChemistry integration: " + (isChemistryAvailable() ? "ACTIVE" : "optional/not detected"));
    }

    @Override
    public void onDisable() {
        if (store != null) store.save();
    }

    private void registerStarterRecipes() {
        try {
            ShapelessRecipe manual = new ShapelessRecipe(manualRecipeKey, createTechItem(TechItem.TECH_MANUAL, 1));
            manual.addIngredient(Material.BOOK);
            manual.addIngredient(Material.REDSTONE);
            manual.addIngredient(Material.COPPER_INGOT);
            Bukkit.addRecipe(manual);

            ShapedRecipe bench = new ShapedRecipe(workbenchRecipeKey, createTechItem(TechItem.TECH_WORKBENCH, 1));
            bench.shape("ICI", "CTC", "ICI");
            bench.setIngredient('I', Material.IRON_INGOT);
            bench.setIngredient('C', Material.COPPER_INGOT);
            bench.setIngredient('T', Material.CRAFTING_TABLE);
            Bukkit.addRecipe(bench);
        } catch (Throwable t) {
            getLogger().log(Level.WARNING, "기초 제작법 등록 실패", t);
        }
    }

    public ItemStack createTechItem(TechItem def, int amount) {
        ItemStack item = new ItemStack(def.material, Math.max(1, Math.min(64, amount)));
        ItemMeta meta = item.getItemMeta();
        if (meta != null) {
            String color = switch (def.kind) {
                case BLOCK -> "§6";
                case COMPONENT -> "§b";
                case MATERIAL -> "§e";
                case TOOL -> "§a";
            };
            meta.setDisplayName("§9§l[TECH] " + color + "§l" + def.displayName);
            List<String> lore = new ArrayList<>();
            lore.add("§8Geumyi Technology · 공식 기술 아이템");
            lore.add("§7분류: §f" + kindName(def.kind));
            lore.add("§7" + def.description);
            if (def.kind == TechItem.Kind.BLOCK) lore.add("§8설치 후 우클릭하여 사용");
            lore.add("§8ID: " + def.id + " · v" + VERSION);
            meta.setLore(lore);
            try { meta.setEnchantmentGlintOverride(true); } catch (Throwable ignored) { }
            try { meta.setItemModel(new NamespacedKey("geumyi_tech", "item/" + def.id)); } catch (Throwable ignored) { }
            PersistentDataContainer pdc = meta.getPersistentDataContainer();
            pdc.set(techIdKey, PersistentDataType.STRING, def.id);
            pdc.set(itemKindKey, PersistentDataType.STRING, def.kind.name().toLowerCase(Locale.ROOT));
            pdc.set(itemVersionKey, PersistentDataType.INTEGER, 1);
            item.setItemMeta(meta);
        }
        return item;
    }

    private String kindName(TechItem.Kind kind) {
        return switch (kind) {
            case BLOCK -> "설치형 장치";
            case COMPONENT -> "부품";
            case MATERIAL -> "가공 재료";
            case TOOL -> "도구";
        };
    }

    private String getTechId(ItemStack item) {
        if (isAir(item)) return null;
        ItemMeta meta = item.getItemMeta();
        if (meta == null) return null;
        return meta.getPersistentDataContainer().get(techIdKey, PersistentDataType.STRING);
    }

    private String getChemId(ItemStack item) {
        if (isAir(item)) return null;
        ItemMeta meta = item.getItemMeta();
        if (meta == null) return null;
        return meta.getPersistentDataContainer().get(chemistryIdKey, PersistentDataType.STRING);
    }

    private boolean isTechItem(ItemStack item) { return getTechId(item) != null; }
    private boolean isAir(ItemStack item) { return item == null || item.getType() == Material.AIR || item.getAmount() <= 0; }

    private boolean isChemistryAvailable() {
        try { return Bukkit.getPluginManager().isPluginEnabled("GeumyiChemistry"); }
        catch (Throwable ignored) { return false; }
    }

    @EventHandler(ignoreCancelled = true)
    public void onBlockPlace(BlockPlaceEvent e) {
        String id = getTechId(e.getItemInHand());
        TechItem item = TechItem.byId(id);
        if (item == null || item.kind != TechItem.Kind.BLOCK) return;
        MachineType type = MachineType.byItem(item);
        if (type == null) return;

        int limit = Math.max(100, getConfig().getInt("safety.max-placed-tech-blocks", 5000));
        if (store.size() >= limit) {
            e.setCancelled(true);
            e.getPlayer().sendMessage(PREFIX + "§c기술 블록 설치 한도(" + limit + ")에 도달했습니다.");
            return;
        }

        MachineData data = new MachineData(BlockKey.of(e.getBlockPlaced()), type);
        store.put(data);
        store.save();
        e.getPlayer().sendMessage(PREFIX + "§f" + item.displayName + "§7 설치 완료.");
    }

    @EventHandler(ignoreCancelled = true)
    public void onBlockBreak(BlockBreakEvent e) {
        MachineData data = store.get(e.getBlock());
        if (data == null) return;
        store.remove(e.getBlock());
        e.setDropItems(false);
        e.setExpToDrop(0);
        e.getBlock().getWorld().dropItemNaturally(e.getBlock().getLocation(), createTechItem(data.type.item, 1));
        store.save();
    }

    @EventHandler
    public void onEntityExplode(EntityExplodeEvent e) {
        e.blockList().removeIf(store::contains);
    }

    @EventHandler
    public void onBlockExplode(BlockExplodeEvent e) {
        e.blockList().removeIf(store::contains);
    }

    @EventHandler(ignoreCancelled = true)
    public void onPistonExtend(BlockPistonExtendEvent e) {
        for (Block b : e.getBlocks()) {
            if (store.contains(b)) { e.setCancelled(true); return; }
        }
    }

    @EventHandler(ignoreCancelled = true)
    public void onPistonRetract(BlockPistonRetractEvent e) {
        for (Block b : e.getBlocks()) {
            if (store.contains(b)) { e.setCancelled(true); return; }
        }
    }

    @EventHandler(ignoreCancelled = true)
    public void onPlayerInteract(PlayerInteractEvent e) {
        if (e.getHand() != null && e.getHand() != EquipmentSlot.HAND) return;
        Action action = e.getAction();
        if (action != Action.RIGHT_CLICK_BLOCK && action != Action.RIGHT_CLICK_AIR) return;

        if (action == Action.RIGHT_CLICK_BLOCK && e.getClickedBlock() != null) {
            MachineData machine = store.get(e.getClickedBlock());
            if (machine != null) {
                e.setCancelled(true);
                openMachineGui(e.getPlayer(), machine);
                return;
            }
        }

        ItemStack item = e.getItem();
        String techId = getTechId(item);
        TechItem def = TechItem.byId(techId);
        if (def == null) return;
        if (def == TechItem.TECH_MANUAL) {
            e.setCancelled(true);
            openMain(e.getPlayer());
            return;
        }
        if (def.kind != TechItem.Kind.BLOCK) {
            // Components/materials are data items, not their vanilla look-alike behavior.
            e.setCancelled(true);
        }
    }

    @EventHandler(ignoreCancelled = true)
    public void onInteractEntity(PlayerInteractEntityEvent e) {
        ItemStack held = e.getPlayer().getInventory().getItemInMainHand();
        if (isTechItem(held)) e.setCancelled(true);
    }

    @EventHandler(ignoreCancelled = true)
    public void onConsume(PlayerItemConsumeEvent e) {
        if (isTechItem(e.getItem())) e.setCancelled(true);
    }

    @EventHandler
    public void onPrepareCraft(PrepareItemCraftEvent e) {
        for (ItemStack item : e.getInventory().getMatrix()) {
            if (isTechItem(item)) {
                e.getInventory().setResult(null);
                return;
            }
        }
    }

    @EventHandler
    public void onPrepareAnvil(PrepareAnvilEvent e) {
        if (isTechItem(e.getInventory().getItem(0)) || isTechItem(e.getInventory().getItem(1))) e.setResult(null);
    }

    @EventHandler
    public void onInventoryDrag(InventoryDragEvent e) {
        String title = e.getView().getTitle();
        if (isOurGui(title)) e.setCancelled(true);
    }

    @EventHandler
    public void onInventoryClose(InventoryCloseEvent e) {
        if (e.getPlayer() instanceof Player p) openMachine.remove(p.getUniqueId());
    }

    @EventHandler
    public void onInventoryClick(InventoryClickEvent e) {
        String title = e.getView().getTitle();
        if (!isOurGui(title)) return;
        e.setCancelled(true);
        if (!(e.getWhoClicked() instanceof Player p)) return;
        int slot = e.getRawSlot();
        if (slot < 0 || slot >= e.getView().getTopInventory().getSize()) return;

        if (title.equals(MAIN_TITLE)) {
            if (slot == 11) openWorkbench(p);
            else if (slot == 13) openTechTree(p);
            else if (slot == 15) openNetworkFromTarget(p);
            else if (slot == 31) showChemistryStatus(p);
            else if (slot == 49) p.closeInventory();
            return;
        }
        if (title.equals(WORKBENCH_TITLE)) {
            if (slot == 49) { openMain(p); return; }
            if (slot >= 0 && slot < workbenchRecipes.size() && slot < 45) {
                craftWorkbenchRecipe(p, workbenchRecipes.get(slot));
                openWorkbench(p);
            }
            return;
        }
        if (title.equals(TECHTREE_TITLE) || title.equals(NETWORK_TITLE)) {
            if (slot == 49) openMain(p);
            return;
        }
        if (title.startsWith(MACHINE_PREFIX)) {
            BlockKey key = openMachine.get(p.getUniqueId());
            MachineData machine = key == null ? null : store.get(key);
            if (machine == null) { p.closeInventory(); return; }
            handleMachineClick(p, machine, slot);
        }
    }

    private boolean isOurGui(String title) {
        return title.equals(MAIN_TITLE) || title.equals(WORKBENCH_TITLE) || title.equals(TECHTREE_TITLE)
                || title.equals(NETWORK_TITLE) || title.startsWith(MACHINE_PREFIX);
    }

    private void openMain(Player p) {
        openMachine.remove(p.getUniqueId());
        Inventory inv = Bukkit.createInventory(null, 54, MAIN_TITLE);
        decorate(inv);
        inv.setItem(11, button(Material.CRAFTING_TABLE, "§6§l조립/제작", List.of(
                "§7부품·발전기·기계를 제작합니다.", "§e클릭하여 제작 목록 열기")));
        inv.setItem(13, button(Material.KNOWLEDGE_BOOK, "§2§l기술 트리", List.of(
                "§7Geumyi Technology의 진행 흐름을 확인합니다.")));
        inv.setItem(15, button(Material.COMPASS, "§b§l전력망 진단", List.of(
                "§7바라보는 기술 블록의 전력망을 확인합니다.")));
        inv.setItem(31, button(isChemistryAvailable() ? Material.LIME_DYE : Material.GRAY_DYE,
                "§d§lChemistry 연동", List.of(
                        isChemistryAvailable() ? "§aGeumyiChemistry 감지됨" : "§7GeumyiChemistry 미감지",
                        "§7Cu / Si / Li / C 샘플을 기술 재료로 사용합니다.",
                        "§7산업용 전기분해기는 Chemistry가 있을 때 활성화됩니다.")));
        inv.setItem(49, button(Material.BARRIER, "§c닫기", List.of()));
        p.openInventory(inv);
    }

    private void openWorkbench(Player p) {
        openMachine.remove(p.getUniqueId());
        Inventory inv = Bukkit.createInventory(null, 54, WORKBENCH_TITLE);
        fillBottom(inv);
        for (int i = 0; i < workbenchRecipes.size() && i < 45; i++) {
            RecipeDef r = workbenchRecipes.get(i);
            ItemStack icon = outputPreview(r);
            ItemMeta meta = icon.getItemMeta();
            if (meta != null) {
                meta.setDisplayName(categoryColor(r.category()) + "§l" + r.name());
                List<String> lore = new ArrayList<>();
                lore.add("§8분류: " + categoryName(r.category()));
                lore.add("§7필요 재료:");
                for (IngredientSpec ing : r.ingredients()) lore.add("§f • " + ingredientName(ing) + " §7×" + ing.amount());
                if (!r.note().isBlank()) lore.add("§8" + r.note());
                if (hasAll(p, r.ingredients())) lore.add("§a✔ 제작 가능 · 클릭하여 제작");
                else lore.add("§c✘ 재료 부족");
                meta.setLore(lore);
                icon.setItemMeta(meta);
            }
            inv.setItem(i, icon);
        }
        inv.setItem(49, button(Material.BARRIER, "§c메인으로", List.of()));
        p.openInventory(inv);
    }

    private void openTechTree(Player p) {
        openMachine.remove(p.getUniqueId());
        Inventory inv = Bukkit.createInventory(null, 54, TECHTREE_TITLE);
        decorate(inv);
        inv.setItem(10, button(Material.BOOK, "§aTier 0 · 시작", List.of(
                "§7기술 매뉴얼", "§7기술 조립 작업대", "§f바닐라 재료로 진입")));
        inv.setItem(12, button(Material.FURNACE, "§eTier 1 · 기초 전력", List.of(
                "§7구리 전선 → 케이블", "§7석탄 발전기", "§7배터리 박스 MK.I")));
        inv.setItem(14, button(Material.BLAST_FURNACE, "§6Tier 2 · 산업 가공", List.of(
                "§7전동 분쇄기", "§7전기로", "§7광물 수율 향상")));
        inv.setItem(16, button(Material.DAYLIGHT_DETECTOR, "§bTier 3 · 반도체/태양광", List.of(
                "§7석영 → 실리콘 분말 → 웨이퍼", "§7태양광 발전기")));
        inv.setItem(30, button(Material.BREWING_STAND, "§dTier 4 · 화학 연동", List.of(
                "§7Chemistry Cu/Si/Li/C 사용", "§7고밀도 배터리", "§7산업용 전기분해기")));
        inv.setItem(32, button(Material.ENDER_CHEST, "§5Tier 4 · 고급 저장", List.of(
                "§7배터리 박스 MK.II", "§7200,000 GT 저장")));
        inv.setItem(49, button(Material.BARRIER, "§c메인으로", List.of()));
        p.openInventory(inv);
    }

    private void showChemistryStatus(Player p) {
        p.closeInventory();
        if (isChemistryAvailable()) {
            p.sendMessage(PREFIX + "§aGeumyiChemistry 연동 활성화됨.");
            p.sendMessage(PREFIX + "§7조립 작업대에서 §fCu·Si·Li·C§7 샘플을 기술 부품으로 사용할 수 있습니다.");
            p.sendMessage(PREFIX + "§7산업용 전기분해기에서 H₂O / NaCl / Al₂O₃ 공정을 사용할 수 있습니다.");
        } else {
            p.sendMessage(PREFIX + "§7GeumyiChemistry가 없어도 기본 전력/산업 진행은 가능합니다.");
        }
    }

    private void openNetworkFromTarget(Player p) {
        Block b = p.getTargetBlockExact(8);
        MachineData data = b == null ? null : store.get(b);
        if (data == null || !data.type.powerNode) {
            p.closeInventory();
            p.sendMessage(PREFIX + "§e8블록 이내의 설치된 전력 장치를 바라봐 주세요.");
            return;
        }
        openNetworkGui(p, data);
    }

    private void openNetworkGui(Player p, MachineData data) {
        openMachine.remove(p.getUniqueId());
        Set<MachineData> component = power.component(data.key);
        long stored = power.storedEnergy(data.key);
        long capacity = power.capacity(data.key);
        int cables = 0, generators = 0, batteries = 0, consumers = 0;
        for (MachineData d : component) {
            if (d.type == MachineType.POWER_CABLE) cables++;
            else if (d.type.generator) generators++;
            else if (d.type.battery) batteries++;
            else consumers++;
        }
        Inventory inv = Bukkit.createInventory(null, 54, NETWORK_TITLE);
        decorate(inv);
        inv.setItem(13, button(Material.REDSTONE, "§b§l전력 " + formatEnergy(stored) + " / " + formatEnergy(capacity), List.of(
                energyBar(stored, capacity), "§7노드: §f" + component.size(), "§7위치: §f" + data.key.compact())));
        inv.setItem(28, button(Material.FURNACE, "§6발전기 §f" + generators, List.of()));
        inv.setItem(30, button(Material.BARREL, "§e배터리 §f" + batteries, List.of()));
        inv.setItem(32, button(Material.IRON_CHAIN, "§7케이블 §f" + cables, List.of()));
        inv.setItem(34, button(Material.BLAST_FURNACE, "§c소비 장치 §f" + consumers, List.of()));
        inv.setItem(49, button(Material.BARRIER, "§c메인으로", List.of()));
        p.openInventory(inv);
    }

    private void openMachineGui(Player p, MachineData machine) {
        if (machine.type == MachineType.TECH_WORKBENCH) { openWorkbench(p); return; }
        if (machine.type == MachineType.POWER_CABLE) {
            openNetworkGui(p, machine);
            return;
        }
        openMachine.put(p.getUniqueId(), machine.key);
        Inventory inv = Bukkit.createInventory(null, 54, MACHINE_PREFIX + machine.type.item.displayName);
        decorate(inv);

        long stored = power.storedEnergy(machine.key);
        long cap = power.capacity(machine.key);
        inv.setItem(4, button(Material.REDSTONE, "§b전력망: " + formatEnergy(stored) + " / " + formatEnergy(cap), List.of(
                energyBar(stored, cap), "§7연결 노드: §f" + power.nodeCount(machine.key), "§7위치: §f" + machine.key.compact())));

        if (machine.type == MachineType.COAL_GENERATOR) {
            inv.setItem(20, button(Material.COAL, "§6석탄 1개 투입", List.of("§7+80초 연료", "§7발전: §f" + getConfig().getInt("power.coal-output-per-second", 40) + " GT/s")));
            inv.setItem(22, button(Material.CHARCOAL, "§6목탄 1개 투입", List.of("§7+80초 연료")));
            inv.setItem(24, button(Material.COAL_BLOCK, "§6석탄 블록 1개 투입", List.of("§7+720초 연료")));
            inv.setItem(31, button(Material.CLOCK, "§e남은 연료: §f" + machine.fuelSeconds + "초", List.of(
                    "§7내부 버퍼: §f" + formatEnergy(machine.energy) + " / " + formatEnergy(machine.type.capacity))));
        } else if (machine.type == MachineType.SOLAR_PANEL) {
            inv.setItem(22, button(Material.SUNFLOWER, power.solarActive(machine) ? "§a§l발전 중" : "§7발전 대기", List.of(
                    "§7맑은 낮 출력: §f" + getConfig().getInt("power.solar-output-per-second", 12) + " GT/s",
                    "§7비/뇌우 시 약 1/3 출력", "§7하늘이 가려지면 발전하지 않습니다.")));
        } else if (machine.type == MachineType.BATTERY_BOX || machine.type == MachineType.BATTERY_BOX_MK2) {
            inv.setItem(22, button(Material.REDSTONE_TORCH, "§e§l저장 상태", List.of(
                    "§7장치 저장량: §f" + formatEnergy(machine.energy),
                    "§7장치 용량: §f" + formatEnergy(machine.type.capacity),
                    "§7같은 전력망의 발전 에너지를 자동 저장합니다.")));
        } else {
            List<MachineProcess> available = processesFor(machine.type);
            for (int i = 0; i < available.size() && i < 36; i++) {
                MachineProcess process = available.get(i);
                int slot = 9 + i;
                ItemStack icon = processPreview(process);
                ItemMeta meta = icon.getItemMeta();
                if (meta != null) {
                    meta.setDisplayName("§e§l" + process.name());
                    List<String> lore = new ArrayList<>();
                    lore.add("§7전력 소비: §b" + formatEnergy(process.energyCost()));
                    lore.add("§7입력:");
                    for (IngredientSpec ing : process.inputs()) lore.add("§f • " + ingredientName(ing) + " §7×" + ing.amount());
                    lore.add("§7출력: §f" + processOutputName(process));
                    if (!process.note().isBlank()) lore.add("§8" + process.note());
                    boolean chemOkay = process.outputKind() != RecipeDef.OutputKind.CHEM || isChemistryAvailable();
                    if (chemOkay && hasAll(p, process.inputs()) && stored >= process.energyCost()) lore.add("§a✔ 실행 가능 · 클릭");
                    else lore.add("§c✘ 재료/전력/연동 조건 확인");
                    meta.setLore(lore);
                    icon.setItemMeta(meta);
                }
                inv.setItem(slot, icon);
            }
        }
        inv.setItem(49, button(Material.BARRIER, "§c닫기", List.of()));
        p.openInventory(inv);
    }

    private void handleMachineClick(Player p, MachineData machine, int slot) {
        if (slot == 49) { p.closeInventory(); return; }
        if (machine.type == MachineType.COAL_GENERATOR) {
            if (slot == 20) addFuel(p, machine, Material.COAL, 80);
            else if (slot == 22) addFuel(p, machine, Material.CHARCOAL, 80);
            else if (slot == 24) addFuel(p, machine, Material.COAL_BLOCK, 720);
            openMachineGui(p, machine);
            return;
        }
        if (machine.type == MachineType.SOLAR_PANEL || machine.type == MachineType.BATTERY_BOX || machine.type == MachineType.BATTERY_BOX_MK2) return;

        int index = slot - 9;
        List<MachineProcess> list = processesFor(machine.type);
        if (index >= 0 && index < list.size()) {
            runMachineProcess(p, machine, list.get(index));
            openMachineGui(p, machine);
        }
    }

    private void addFuel(Player p, MachineData machine, Material material, int seconds) {
        if (!consumeVanilla(p, material, 1)) {
            p.sendMessage(PREFIX + "§c" + prettyMaterial(material) + "이(가) 없습니다.");
            return;
        }
        int max = Math.max(720, getConfig().getInt("power.max-fuel-seconds", 7200));
        machine.fuelSeconds = Math.min(max, machine.fuelSeconds + seconds);
        store.save();
        p.sendMessage(PREFIX + "§a연료 투입 완료. 남은 연료 " + machine.fuelSeconds + "초");
    }

    private void runMachineProcess(Player p, MachineData machine, MachineProcess process) {
        if (process.outputKind() == RecipeDef.OutputKind.CHEM && !isChemistryAvailable()) {
            p.sendMessage(PREFIX + "§c이 공정은 GeumyiChemistry가 필요합니다.");
            return;
        }
        if (!hasAll(p, process.inputs())) {
            p.sendMessage(PREFIX + "§c입력 재료가 부족합니다.");
            return;
        }
        if (!power.consume(machine.key, process.energyCost())) {
            p.sendMessage(PREFIX + "§c전력이 부족합니다. 필요: " + formatEnergy(process.energyCost()));
            return;
        }
        if (!consumeIngredients(p, process.inputs())) {
            p.sendMessage(PREFIX + "§c재료 확인 중 상태가 바뀌어 공정을 취소했습니다.");
            return;
        }
        giveProcessOutput(p, process);
        store.save();
        p.sendMessage(PREFIX + "§a공정 완료: §f" + process.name() + " §7(-" + formatEnergy(process.energyCost()) + ")");
    }

    private void craftWorkbenchRecipe(Player p, RecipeDef r) {
        if (r.category() == RecipeDef.Category.CHEMISTRY && !isChemistryAvailable()) {
            p.sendMessage(PREFIX + "§c이 제작법은 GeumyiChemistry가 필요합니다.");
            return;
        }
        if (!hasAll(p, r.ingredients())) {
            p.sendMessage(PREFIX + "§c재료가 부족합니다: " + r.name());
            return;
        }
        if (!consumeIngredients(p, r.ingredients())) {
            p.sendMessage(PREFIX + "§c재료 상태가 변경되어 제작을 취소했습니다.");
            return;
        }
        giveRecipeOutput(p, r);
        p.sendMessage(PREFIX + "§a제작 완료: §f" + r.name());
    }

    private boolean hasAll(Player p, List<IngredientSpec> ingredients) {
        Map<String, Integer> needs = new LinkedHashMap<>();
        for (IngredientSpec ing : ingredients) {
            String key = ing.kind().name() + ":" + ing.id();
            needs.merge(key, ing.amount(), Integer::sum);
        }
        for (Map.Entry<String, Integer> e : needs.entrySet()) {
            String[] parts = e.getKey().split(":", 2);
            IngredientSpec.Kind kind = IngredientSpec.Kind.valueOf(parts[0]);
            if (countIngredient(p, kind, parts[1]) < e.getValue()) return false;
        }
        return true;
    }

    private int countIngredient(Player p, IngredientSpec.Kind kind, String id) {
        int n = 0;
        for (ItemStack item : p.getInventory().getContents()) {
            if (matchesIngredient(item, kind, id)) n += item.getAmount();
        }
        return n;
    }

    private boolean matchesIngredient(ItemStack item, IngredientSpec.Kind kind, String id) {
        if (isAir(item)) return false;
        return switch (kind) {
            case VANILLA -> item.getType().name().equals(id) && !isTechItem(item) && getChemId(item) == null;
            case TECH -> id.equalsIgnoreCase(getTechId(item));
            case CHEM -> id.equalsIgnoreCase(getChemId(item));
        };
    }

    private boolean consumeIngredients(Player p, List<IngredientSpec> ingredients) {
        if (!hasAll(p, ingredients)) return false;
        for (IngredientSpec ing : ingredients) {
            int left = ing.amount();
            ItemStack[] contents = p.getInventory().getContents();
            for (int i = 0; i < contents.length && left > 0; i++) {
                ItemStack item = contents[i];
                if (!matchesIngredient(item, ing.kind(), ing.id())) continue;
                int take = Math.min(left, item.getAmount());
                int remain = item.getAmount() - take;
                left -= take;
                if (remain <= 0) p.getInventory().setItem(i, null);
                else { item.setAmount(remain); p.getInventory().setItem(i, item); }
            }
        }
        return true;
    }

    private boolean consumeVanilla(Player p, Material material, int amount) {
        return consumeIngredients(p, List.of(IngredientSpec.vanilla(material, amount)));
    }

    private void giveRecipeOutput(Player p, RecipeDef r) {
        if (r.outputKind() == RecipeDef.OutputKind.TECH) {
            TechItem t = TechItem.byId(r.outputId());
            if (t != null) giveItem(p, createTechItem(t, r.outputAmount()));
        } else if (r.outputKind() == RecipeDef.OutputKind.VANILLA) {
            giveItem(p, new ItemStack(Material.valueOf(r.outputId()), r.outputAmount()));
        } else {
            giveChem(p, r.outputId(), r.outputAmount());
        }
    }

    private void giveProcessOutput(Player p, MachineProcess process) {
        if (process.outputKind() == RecipeDef.OutputKind.TECH) {
            TechItem t = TechItem.byId(process.outputId());
            if (t != null) giveItem(p, createTechItem(t, process.outputAmount()));
        } else if (process.outputKind() == RecipeDef.OutputKind.VANILLA) {
            giveItem(p, new ItemStack(Material.valueOf(process.outputId()), process.outputAmount()));
        } else {
            String[] outputs = process.outputId().split(",");
            for (String part : outputs) {
                String[] p2 = part.trim().split("\\+");
                if (p2.length != 2) continue;
                try { giveChem(p, p2[0], Integer.parseInt(p2[1])); }
                catch (NumberFormatException ignored) { }
            }
        }
    }

    private void giveChem(Player p, String chemId, int amount) {
        if (!isChemistryAvailable()) return;
        Bukkit.dispatchCommand(Bukkit.getConsoleSender(), "chem give " + p.getName() + " " + chemId + " " + Math.max(1, amount));
    }

    private void giveItem(Player p, ItemStack item) {
        Map<Integer, ItemStack> overflow = p.getInventory().addItem(item);
        for (ItemStack rest : overflow.values()) p.getWorld().dropItemNaturally(p.getLocation(), rest);
    }

    private List<MachineProcess> processesFor(MachineType type) {
        ArrayList<MachineProcess> out = new ArrayList<>();
        for (MachineProcess p : processes) if (p.machine() == type) out.add(p);
        return out;
    }

    private ItemStack outputPreview(RecipeDef r) {
        try {
            if (r.outputKind() == RecipeDef.OutputKind.TECH) {
                TechItem t = TechItem.byId(r.outputId());
                if (t != null) return createTechItem(t, Math.min(64, r.outputAmount()));
            }
            if (r.outputKind() == RecipeDef.OutputKind.VANILLA) return new ItemStack(Material.valueOf(r.outputId()), 1);
        } catch (Exception ignored) { }
        return new ItemStack(Material.PAPER, 1);
    }

    private ItemStack processPreview(MachineProcess p) {
        if (p.outputKind() == RecipeDef.OutputKind.TECH) {
            TechItem t = TechItem.byId(p.outputId());
            if (t != null) return createTechItem(t, 1);
        }
        if (p.outputKind() == RecipeDef.OutputKind.VANILLA) {
            try { return new ItemStack(Material.valueOf(p.outputId()), 1); } catch (Exception ignored) { }
        }
        return new ItemStack(Material.POTION, 1);
    }

    private String processOutputName(MachineProcess p) {
        if (p.outputKind() == RecipeDef.OutputKind.TECH) {
            TechItem t = TechItem.byId(p.outputId());
            return t == null ? p.outputId() : t.displayName + " ×" + p.outputAmount();
        }
        if (p.outputKind() == RecipeDef.OutputKind.VANILLA) return prettyMaterial(Material.valueOf(p.outputId())) + " ×" + p.outputAmount();
        return p.outputId().replace("+", " ×").replace(",", " + ");
    }

    private String ingredientName(IngredientSpec ing) {
        return switch (ing.kind()) {
            case VANILLA -> prettyMaterial(Material.valueOf(ing.id()));
            case TECH -> {
                TechItem t = TechItem.byId(ing.id());
                yield t == null ? ing.id() : "[TECH] " + t.displayName;
            }
            case CHEM -> "[CHEM] " + ing.id();
        };
    }

    private String prettyMaterial(Material m) {
        String s = m.name().toLowerCase(Locale.ROOT).replace('_', ' ');
        String[] words = s.split(" ");
        StringBuilder b = new StringBuilder();
        for (String w : words) {
            if (w.isEmpty()) continue;
            if (!b.isEmpty()) b.append(' ');
            b.append(Character.toUpperCase(w.charAt(0))).append(w.substring(1));
        }
        return b.toString();
    }

    private String categoryName(RecipeDef.Category c) {
        return switch (c) {
            case COMPONENTS -> "기초 부품";
            case POWER -> "전력";
            case INDUSTRY -> "산업 기계";
            case CHEMISTRY -> "Chemistry 연동";
        };
    }

    private String categoryColor(RecipeDef.Category c) {
        return switch (c) {
            case COMPONENTS -> "§b";
            case POWER -> "§e";
            case INDUSTRY -> "§6";
            case CHEMISTRY -> "§d";
        };
    }

    private String formatEnergy(long e) {
        if (e >= 1_000_000) return String.format(Locale.US, "%.2f MGT", e / 1_000_000.0);
        if (e >= 1_000) return String.format(Locale.US, "%.1f kGT", e / 1_000.0);
        return e + " GT";
    }

    private String energyBar(long value, long max) {
        if (max <= 0) return "§8[----------] §70%";
        int fill = (int) Math.max(0, Math.min(10, Math.round(value * 10.0 / max)));
        return "§8[§a" + "■".repeat(fill) + "§7" + "■".repeat(10 - fill) + "§8] §f" + Math.round(value * 100.0 / max) + "%";
    }

    private ItemStack button(Material material, String name, List<String> lore) {
        ItemStack item = new ItemStack(material, 1);
        ItemMeta meta = item.getItemMeta();
        if (meta != null) {
            meta.setDisplayName(name);
            if (!lore.isEmpty()) meta.setLore(lore);
            item.setItemMeta(meta);
        }
        return item;
    }

    private void decorate(Inventory inv) {
        ItemStack pane = button(Material.GRAY_STAINED_GLASS_PANE, "§8 ", List.of());
        for (int i = 0; i < inv.getSize(); i++) inv.setItem(i, pane.clone());
    }

    private void fillBottom(Inventory inv) {
        ItemStack pane = button(Material.GRAY_STAINED_GLASS_PANE, "§8 ", List.of());
        for (int i = 45; i < 54; i++) inv.setItem(i, pane.clone());
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!command.getName().equalsIgnoreCase("gtech")) return false;
        if (args.length == 0) {
            if (sender instanceof Player p) openMain(p);
            else sender.sendMessage("GeumyiTechnology " + VERSION + " · /gtech list|give|reload|validate");
            return true;
        }

        String sub = args[0].toLowerCase(Locale.ROOT);
        if (sub.equals("recipes") || sub.equals("craft")) {
            if (sender instanceof Player p) openWorkbench(p);
            else sender.sendMessage("Player only.");
            return true;
        }
        if (sub.equals("tech") || sub.equals("tree")) {
            if (sender instanceof Player p) openTechTree(p);
            return true;
        }
        if (sub.equals("status")) {
            if (sender instanceof Player p) openNetworkFromTarget(p);
            else sender.sendMessage("Placed tech blocks: " + store.size());
            return true;
        }
        if (sub.equals("recipe")) {
            sender.sendMessage(PREFIX + "§f기술 매뉴얼: §7책 + 레드스톤 + 구리 주괴");
            sender.sendMessage(PREFIX + "§f기술 조립 작업대: §74 철 주괴 + 4 구리 주괴 + 제작대");
            sender.sendMessage(PREFIX + "§7이후 제작은 기술 조립 작업대에서 진행합니다.");
            return true;
        }
        if (sub.equals("list")) {
            sender.sendMessage(PREFIX + "§f기술 아이템 " + TechItem.values().length + "종:");
            StringBuilder line = new StringBuilder();
            for (TechItem t : TechItem.values()) {
                if (!line.isEmpty()) line.append("§7, ");
                line.append("§b").append(t.id);
                if (line.length() > 150) { sender.sendMessage(line.toString()); line.setLength(0); }
            }
            if (!line.isEmpty()) sender.sendMessage(line.toString());
            return true;
        }

        if (!sender.hasPermission("geumyi.tech.admin")) {
            sender.sendMessage(PREFIX + "§c관리자 권한이 필요합니다.");
            return true;
        }

        if (sub.equals("give")) {
            if (args.length < 3) {
                sender.sendMessage(PREFIX + "§c사용법: /gtech give <player> <tech_id> [amount]");
                return true;
            }
            Player target = Bukkit.getPlayerExact(args[1]);
            TechItem item = TechItem.byId(args[2]);
            if (target == null) { sender.sendMessage(PREFIX + "§c플레이어를 찾을 수 없습니다."); return true; }
            if (item == null) { sender.sendMessage(PREFIX + "§c알 수 없는 tech_id입니다. /gtech list"); return true; }
            int amount = 1;
            if (args.length >= 4) {
                try { amount = Math.max(1, Math.min(64, Integer.parseInt(args[3]))); }
                catch (NumberFormatException ignored) { }
            }
            giveItem(target, createTechItem(item, amount));
            sender.sendMessage(PREFIX + "§a지급 완료: " + target.getName() + " ← " + item.id + " ×" + amount);
            return true;
        }
        if (sub.equals("reload")) {
            reloadConfig();
            sender.sendMessage(PREFIX + "§a설정을 다시 불러왔습니다.");
            return true;
        }
        if (sub.equals("validate")) {
            int removed = store.validateLoadedBlocks();
            store.save();
            sender.sendMessage(PREFIX + "§a검증 완료. 정리된 유실 데이터: " + removed + "개 · 현재 기술 블록: " + store.size() + "개");
            return true;
        }

        sender.sendMessage(PREFIX + "§7/gtech · /gtech recipes · /gtech tech · /gtech status · /gtech recipe");
        return true;
    }
}
