package kr.geumyi.chemistry;

import org.bukkit.Bukkit;
import org.bukkit.Color;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.NamespacedKey;
import org.bukkit.Particle;
import org.bukkit.World;
import org.bukkit.block.Block;
import org.bukkit.block.TileState;
import org.bukkit.command.Command;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.HumanEntity;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.block.Action;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockExplodeEvent;
import org.bukkit.event.block.BlockPlaceEvent;
import org.bukkit.event.entity.EntityExplodeEvent;
import org.bukkit.event.inventory.InventoryClickEvent;
import org.bukkit.event.inventory.InventoryCloseEvent;
import org.bukkit.event.inventory.InventoryDragEvent;
import org.bukkit.event.inventory.BrewEvent;
import org.bukkit.event.inventory.PrepareAnvilEvent;
import org.bukkit.event.inventory.PrepareItemCraftEvent;
import org.bukkit.event.player.PlayerInteractEvent;
import org.bukkit.event.player.PlayerInteractEntityEvent;
import org.bukkit.event.player.PlayerItemConsumeEvent;
import org.bukkit.event.player.PlayerJoinEvent;
import org.bukkit.inventory.EquipmentSlot;
import org.bukkit.inventory.Inventory;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.PlayerInventory;
import org.bukkit.inventory.ShapedRecipe;
import org.bukkit.inventory.ShapelessRecipe;
import org.bukkit.inventory.meta.ItemMeta;
import org.bukkit.persistence.PersistentDataContainer;
import org.bukkit.persistence.PersistentDataType;
import org.bukkit.plugin.java.JavaPlugin;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.logging.Level;

/**
 * GeumyiChemistry 0.4.1
 * Paper 26.3 target. Gameplay works without client mods. Optional Java/Bedrock resource packs
 * provide dedicated chemistry icons; server-side PDC remains the authoritative item identity.
 */
public final class GeumyiChemistry extends JavaPlugin implements Listener {
    private static final String VERSION = "0.4.1";
    private static final String P = "§8[§3Chem§8] §r";

    private static final String MAIN_TITLE = "§3§l금이 화학 연구실";
    private static final String ELEMENTS_TITLE = "§3주기율표 §7- ";
    private static final String SPECIES_TITLE = "§5물질 도감 §7- ";
    private static final String REACTION_GUIDE_TITLE = "§e반응식 도감 §7- ";
    private static final String EXTRACT_GUIDE_TITLE = "§6추출 루트 §7- ";
    private static final String EXTRACTOR_TITLE = "§6물질 추출기";
    private static final String ANALYSIS_TITLE = "§d화학 분석실";
    private static final String DISCOVERED_TITLE = "§a발견 도감 §7- ";
    private static final String TECH_TITLE = "§2§l화학 연구 테크트리";

    private static final int[] LAB_INPUTS = {10, 11, 12, 19, 20, 21, 28, 29, 30};
    private static final Set<Integer> LAB_INPUT_SET = intSet(LAB_INPUTS);
    private static final int EXTRACTOR_INPUT = 13;
    private static final int ANALYSIS_INPUT = 13;
    private static final int CATALYST_SLOT = 22;

    private final LinkedHashMap<String, ChemDef> all = new LinkedHashMap<>();
    private final List<ChemDef> elements = new ArrayList<>();
    private final List<ChemDef> species = new ArrayList<>();
    private final List<Reaction> reactions = new ArrayList<>();
    private final LinkedHashMap<String, LinkedHashMap<String, Integer>> extractions = new LinkedHashMap<>();
    private final Map<UUID, Temperature> playerTemperature = new HashMap<>();
    private final Map<UUID, Pressure> playerPressure = new HashMap<>();

    private NamespacedKey chemIdKey;
    private NamespacedKey itemKindKey;
    private NamespacedKey toolIdKey;
    private NamespacedKey itemVersionKey;
    private NamespacedKey labKitRecipeKey;
    private NamespacedKey phPaperRecipeKey;
    private NamespacedKey labBlockKey;
    private final LinkedHashMap<String, NamespacedKey> toolRecipeKeys = new LinkedHashMap<>();

    @Override
    public void onEnable() {
        chemIdKey = new NamespacedKey(this, "chem_id");
        itemKindKey = new NamespacedKey(this, "item_kind");
        toolIdKey = new NamespacedKey(this, "tool_id");
        itemVersionKey = new NamespacedKey(this, "item_version");
        labKitRecipeKey = new NamespacedKey(this, "chemistry_lab_kit");
        phPaperRecipeKey = new NamespacedKey(this, "ph_test_paper");
        labBlockKey = new NamespacedKey(this, "lab_block");
        for (String toolId : ToolDef.CRAFTABLE_IDS) toolRecipeKeys.put(toolId, new NamespacedKey(this, "tool_" + toolId));

        saveDefaultConfig();
        ensureResource("reactions-v4.yml");
        ensureResource("extract-v4.yml");

        try {
            reloadChemistryData();
        } catch (Exception ex) {
            getLogger().log(Level.SEVERE, "Failed to load chemistry data", ex);
        }

        Bukkit.getPluginManager().registerEvents(this, this);
        registerRecipes();
        getLogger().info("GeumyiChemistry " + VERSION + " enabled: " + elements.size() + " elements, "
                + species.size() + " species, " + reactions.size() + " reactions, " + extractions.size() + " extraction routes.");
    }

    private void ensureResource(String name) {
        File f = new File(getDataFolder(), name);
        if (!f.exists()) saveResource(name, false);
    }

    private void reloadChemistryData() throws IOException {
        all.clear();
        elements.clear();
        species.clear();
        reactions.clear();
        extractions.clear();
        loadElements();
        loadSpecies();
        loadReactions(new File(getDataFolder(), "reactions-v4.yml").toPath());
        loadExtractions(new File(getDataFolder(), "extract-v4.yml").toPath());
    }

    private void loadElements() throws IOException {
        try (InputStream in = getResource("elements.csv")) {
            if (in == null) throw new FileNotFoundException("elements.csv");
            try (BufferedReader r = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
                String line;
                boolean first = true;
                while ((line = r.readLine()) != null) {
                    if (first) { first = false; continue; }
                    if (line.isBlank() || line.startsWith("#")) continue;
                    String[] p = line.split(",", -1);
                    if (p.length < 6) continue;
                    int atomic = Integer.parseInt(p[0].trim());
                    String category = categoryKorean(p[4].trim());
                    ChemDef d = new ChemDef(
                            p[1].trim(), p[1].trim(), p[3].trim(), p[2].trim(), p[5].trim(),
                            "원자번호 " + atomic + " · " + category,
                            ChemType.ELEMENT, atomic, MatterState.ELEMENT, category, null, ""
                    );
                    registerChem(d);
                    elements.add(d);
                }
            }
        }
    }

    private void loadSpecies() throws IOException {
        try (InputStream in = getResource("species-v4.csv")) {
            if (in == null) throw new FileNotFoundException("species-v4.csv");
            try (BufferedReader r = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
                String line;
                boolean first = true;
                while ((line = r.readLine()) != null) {
                    if (first) { first = false; continue; }
                    if (line.isBlank() || line.startsWith("#")) continue;
                    String[] p = line.split(",", -1);
                    if (p.length < 10) continue;
                    Double ph = null;
                    if (!p[8].trim().isEmpty()) {
                        try { ph = Double.parseDouble(p[8].trim()); } catch (NumberFormatException ignored) { }
                    }
                    MatterState state = MatterState.from(p[6].trim());
                    ChemDef d = new ChemDef(
                            p[0].trim(), p[1].trim(), p[2].trim(), p[3].trim(), p[4].trim(), p[5].trim(),
                            ChemType.SPECIES, 0, state, p[7].trim(), ph, p[9].trim()
                    );
                    registerChem(d);
                    species.add(d);
                }
            }
        }
    }

    private void registerChem(ChemDef d) {
        if (all.containsKey(d.id)) getLogger().warning("Duplicate chemistry id: " + d.id);
        all.put(d.id, d);
    }

    private String categoryKorean(String c) {
        return switch (c.toLowerCase(Locale.ROOT)) {
            case "nonmetal" -> "비금속";
            case "noble" -> "비활성 기체";
            case "alkali" -> "알칼리 금속";
            case "alkaline" -> "알칼리 토금속";
            case "metalloid" -> "준금속";
            case "halogen" -> "할로젠";
            case "transition" -> "전이 금속";
            case "post" -> "전이후 금속";
            case "lanthanide" -> "란타넘족";
            case "actinide" -> "악티늄족";
            default -> "분류 미정";
        };
    }

    private void loadReactions(Path path) throws IOException {
        List<String> lines = Files.readAllLines(path, StandardCharsets.UTF_8);
        String currentId = null;
        String name = null;
        String note = "";
        LabType lab = LabType.GENERAL;
        Temperature temp = Temperature.ROOM;
        Pressure pressure = Pressure.NORMAL;
        String catalyst = "";
        LinkedHashMap<String, Integer> inputs = new LinkedHashMap<>();
        LinkedHashMap<String, Integer> outputs = new LinkedHashMap<>();

        for (String raw : lines) {
            String trimmed = stripComment(raw).trim();
            if (trimmed.isEmpty() || trimmed.equals("reactions:")) continue;
            int indent = countLeadingSpaces(raw);
            if (indent == 2 && trimmed.endsWith(":")) {
                if (currentId != null) addReaction(currentId, name, lab, temp, pressure, catalyst, inputs, outputs, note);
                currentId = trimmed.substring(0, trimmed.length() - 1).trim();
                name = currentId;
                note = "";
                lab = LabType.GENERAL;
                temp = Temperature.ROOM;
                pressure = Pressure.NORMAL;
                catalyst = "";
                inputs = new LinkedHashMap<>();
                outputs = new LinkedHashMap<>();
            } else if (currentId != null && indent >= 4) {
                int colon = trimmed.indexOf(':');
                if (colon < 0) continue;
                String key = trimmed.substring(0, colon).trim();
                String value = unquote(trimmed.substring(colon + 1).trim());
                switch (key) {
                    case "name" -> name = value;
                    case "note" -> note = value;
                    case "lab" -> lab = LabType.from(value);
                    case "temperature" -> temp = Temperature.from(value);
                    case "pressure" -> pressure = Pressure.from(value);
                    case "catalyst" -> catalyst = value == null ? "" : value.trim();
                    case "inputs" -> inputs = parseAmounts(value);
                    case "outputs" -> outputs = parseAmounts(value);
                }
            }
        }
        if (currentId != null) addReaction(currentId, name, lab, temp, pressure, catalyst, inputs, outputs, note);
    }

    private void addReaction(String id, String name, LabType lab, Temperature temp, Pressure pressure, String catalyst,
                             LinkedHashMap<String, Integer> inputs, LinkedHashMap<String, Integer> outputs, String note) {
        if (inputs.isEmpty() || outputs.isEmpty()) {
            getLogger().warning("Skipped reaction '" + id + "': inputs/outputs missing");
            return;
        }
        boolean valid = true;
        for (String itemId : inputs.keySet()) {
            if (!all.containsKey(itemId)) { getLogger().warning("Reaction '" + id + "' unknown input: " + itemId); valid = false; }
        }
        for (String itemId : outputs.keySet()) {
            if (!all.containsKey(itemId)) { getLogger().warning("Reaction '" + id + "' unknown output: " + itemId); valid = false; }
        }
        if (catalyst != null && !catalyst.isBlank() && !all.containsKey(catalyst)) {
            getLogger().warning("Reaction '" + id + "' unknown catalyst: " + catalyst);
            valid = false;
        }
        if (valid) reactions.add(new Reaction(id, name, lab, temp, pressure, catalyst, inputs, outputs, note));
    }

    private void loadExtractions(Path path) throws IOException {
        List<String> lines = Files.readAllLines(path, StandardCharsets.UTF_8);
        for (String raw : lines) {
            String trimmed = stripComment(raw).trim();
            if (trimmed.isEmpty() || trimmed.equals("extractions:")) continue;
            int indent = countLeadingSpaces(raw);
            if (indent != 2) continue;
            int colon = trimmed.indexOf(':');
            if (colon < 0) continue;
            String material = trimmed.substring(0, colon).trim().toUpperCase(Locale.ROOT);
            LinkedHashMap<String, Integer> outputs = parseAmounts(unquote(trimmed.substring(colon + 1).trim()));
            boolean valid = !outputs.isEmpty();
            for (String id : outputs.keySet()) {
                if (!all.containsKey(id)) { getLogger().warning("Extraction " + material + " unknown output: " + id); valid = false; }
            }
            if (safeMaterialOrNull(material) == null) {
                getLogger().warning("Extraction route uses unknown Material: " + material);
                valid = false;
            }
            if (valid) extractions.put(material, outputs);
        }
    }

    private LinkedHashMap<String, Integer> parseAmounts(String value) {
        LinkedHashMap<String, Integer> map = new LinkedHashMap<>();
        if (value == null || value.isBlank()) return map;
        for (String token : value.split(",")) {
            String[] pair = token.trim().split("=", 2);
            if (pair.length != 2) continue;
            try {
                int amount = Integer.parseInt(pair[1].trim());
                if (amount > 0) map.put(pair[0].trim(), amount);
            } catch (NumberFormatException ignored) { }
        }
        return map;
    }

    private int countLeadingSpaces(String s) {
        int i = 0;
        while (i < s.length() && s.charAt(i) == ' ') i++;
        return i;
    }

    private String stripComment(String s) {
        int i = s.indexOf('#');
        return i < 0 ? s : s.substring(0, i);
    }

    private String unquote(String s) {
        if (s.length() >= 2 && ((s.startsWith("\"") && s.endsWith("\"")) || (s.startsWith("'") && s.endsWith("'")))) {
            return s.substring(1, s.length() - 1);
        }
        return s;
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!command.getName().equalsIgnoreCase("chem")) return false;
        if (args.length == 0) {
            if (!(sender instanceof Player p)) {
                sender.sendMessage(P + "콘솔에서는 §f/chem list, /chem give, /chem reload§r를 사용해 주세요.");
                return true;
            }
            openMain(p);
            return true;
        }

        String sub = args[0].toLowerCase(Locale.ROOT);
        switch (sub) {
            case "reactor", "general", "반응기" -> { if (requirePlayer(sender)) openLab((Player) sender, LabType.GENERAL); return true; }
            case "solution", "용액" -> { if (requirePlayer(sender)) openLab((Player) sender, LabType.SOLUTION); return true; }
            case "gas", "기체" -> { if (requirePlayer(sender)) openLab((Player) sender, LabType.GAS); return true; }
            case "precip", "precipitation", "앙금" -> { if (requirePlayer(sender)) openLab((Player) sender, LabType.PRECIPITATION); return true; }
            case "acid", "acidbase", "산염기" -> { if (requirePlayer(sender)) openLab((Player) sender, LabType.ACID_BASE); return true; }
            case "redox", "산화환원" -> { if (requirePlayer(sender)) openLab((Player) sender, LabType.REDOX); return true; }
            case "electrolysis", "electro", "전기분해" -> { if (requirePlayer(sender)) openLab((Player) sender, LabType.ELECTROLYSIS); return true; }
            case "thermal", "열분해" -> { if (requirePlayer(sender)) openLab((Player) sender, LabType.THERMAL); return true; }
            case "extractor", "추출기" -> { if (requirePlayer(sender)) openExtractor((Player) sender); return true; }
            case "routes", "추출루트" -> { if (requirePlayer(sender)) openExtractionGuide((Player) sender, 0); return true; }
            case "elements", "원소" -> { if (requirePlayer(sender)) openElements((Player) sender, parsePage(args)); return true; }
            case "species", "화합물", "물질" -> { if (requirePlayer(sender)) openSpecies((Player) sender, parsePage(args)); return true; }
            case "reactions", "반응식" -> { if (requirePlayer(sender)) openReactionGuide((Player) sender, parsePage(args)); return true; }
            case "analysis", "분석" -> { if (requirePlayer(sender)) openAnalysis((Player) sender); return true; }
            case "discovered", "도감" -> { if (requirePlayer(sender)) openDiscovered((Player) sender, parsePage(args)); return true; }
            case "recipe", "제작법" -> { sendToolRecipes(sender); return true; }
            case "tech", "research", "테크", "연구" -> { if (requirePlayer(sender)) openTechTree((Player) sender); return true; }
            case "find", "search", "검색" -> { return commandFind(sender, args); }
            case "list" -> {
                sender.sendMessage(P + "§f등록: §b원소 " + elements.size() + "개§f, §d물질 " + species.size()
                        + "개§f, §c반응 " + reactions.size() + "개§f, §6추출 루트 " + extractions.size() + "개");
                return true;
            }
            case "refreshitems", "아이템갱신" -> {
                if (!requirePlayer(sender)) return true;
                int count = migratePlayerInventory((Player) sender);
                sender.sendMessage(P + "§a화학 아이템 " + count + "개를 v" + VERSION + " 외형으로 갱신했습니다.");
                return true;
            }
            case "give" -> { return commandGive(sender, args); }
            case "givetool" -> { return commandGiveTool(sender, args); }
            case "reload" -> {
                if (!sender.hasPermission("geumyi.chem.admin")) { sender.sendMessage(P + "§c권한이 없습니다."); return true; }
                try {
                    reloadConfig();
                    reloadChemistryData();
                    registerRecipes();
                    sender.sendMessage(P + "§a데이터 재로드 완료. §7(" + reactions.size() + " reactions, " + extractions.size() + " routes)");
                } catch (Exception ex) {
                    sender.sendMessage(P + "§c재로드 실패: " + ex.getMessage());
                    getLogger().log(Level.SEVERE, "Chemistry reload failed", ex);
                }
                return true;
            }
            default -> { sendHelp(sender); return true; }
        }
    }

    private int parsePage(String[] args) {
        if (args.length < 2) return 0;
        try { return Math.max(0, Integer.parseInt(args[1]) - 1); }
        catch (NumberFormatException ignored) { return 0; }
    }

    private boolean commandGive(CommandSender sender, String[] args) {
        if (!sender.hasPermission("geumyi.chem.admin")) { sender.sendMessage(P + "§c권한이 없습니다."); return true; }
        if (args.length < 3) { sender.sendMessage(P + "사용법: §f/chem give <플레이어> <ID> [수량]"); return true; }
        Player target = Bukkit.getPlayer(args[1]);
        if (target == null) { sender.sendMessage(P + "§c온라인 플레이어를 찾을 수 없습니다."); return true; }
        ChemDef def = getChemDef(args[2]);
        if (def == null) { sender.sendMessage(P + "§c알 수 없는 화학 ID: §f" + args[2]); return true; }
        int amount = 1;
        if (args.length >= 4) {
            try { amount = Math.max(1, Math.min(4096, Integer.parseInt(args[3]))); } catch (NumberFormatException ignored) { }
        }
        giveChem(target, def.id, amount);
        sender.sendMessage(P + "§a" + target.getName() + "§f에게 §b" + def.id + " §7x" + amount + "§f 지급했습니다.");
        return true;
    }

    private boolean commandGiveTool(CommandSender sender, String[] args) {
        if (!sender.hasPermission("geumyi.chem.admin")) { sender.sendMessage(P + "§c권한이 없습니다."); return true; }
        if (args.length < 3) { sender.sendMessage(P + "사용법: §f/chem givetool <플레이어> <도구ID>"); return true; }
        Player target = Bukkit.getPlayer(args[1]);
        if (target == null) { sender.sendMessage(P + "§c온라인 플레이어를 찾을 수 없습니다."); return true; }
        String tool = args[2].toLowerCase(Locale.ROOT);
        ItemStack item = createToolItem(tool);
        if (item == null) { sender.sendMessage(P + "§c알 수 없는 도구 ID입니다."); return true; }
        giveVanilla(target, item);
        sender.sendMessage(P + "§a도구 지급 완료: §f" + tool);
        return true;
    }

    @Override
    public List<String> onTabComplete(CommandSender sender, Command command, String alias, String[] args) {
        if (!command.getName().equalsIgnoreCase("chem")) return Collections.emptyList();
        if (args.length == 1) {
            return complete(args[0], List.of("reactor", "solution", "gas", "precip", "acidbase", "redox", "electrolysis", "thermal",
                    "extractor", "routes", "elements", "species", "reactions", "analysis", "discovered", "tech", "find", "recipe", "list", "refreshitems", "give", "givetool", "reload"));
        }
        if (args.length == 3 && args[0].equalsIgnoreCase("give")) return complete(args[2], new ArrayList<>(all.keySet()));
        if (args.length == 3 && args[0].equalsIgnoreCase("givetool")) return complete(args[2], new ArrayList<>(ToolDef.ALL_IDS));
        return Collections.emptyList();
    }

    private List<String> complete(String prefix, List<String> choices) {
        String p = prefix.toLowerCase(Locale.ROOT);
        ArrayList<String> out = new ArrayList<>();
        for (String s : choices) if (s.toLowerCase(Locale.ROOT).startsWith(p)) out.add(s);
        return out;
    }

    private void sendHelp(CommandSender s) {
        s.sendMessage("§3§lGeumyiChemistry §7v" + VERSION);
        s.sendMessage("§f/chem §7- 메인 GUI (화학 실험 키트 우클릭으로도 열림)");
        s.sendMessage("§f/chem extractor §7- 야생 재료 추출");
        s.sendMessage("§f/chem gas / precip / acidbase / redox / electrolysis / thermal §7- 분야별 실험실");
        s.sendMessage("§f/chem elements / species / reactions / routes / analysis / discovered §7- 도감·분석");
        s.sendMessage("§f/chem tech §7- 장비 기반 연구 테크트리");
        s.sendMessage("§f/chem find <검색어> §7- 물질/반응 빠른 검색");
        s.sendMessage("§f/chem recipe §7- 실험대·실험장비 제작법");
        if (s.hasPermission("geumyi.chem.admin")) s.sendMessage("§c관리자: §f/chem give, /chem givetool, /chem reload");
    }

    private boolean requirePlayer(CommandSender sender) {
        if (sender instanceof Player) return true;
        sender.sendMessage(P + "§c이 명령은 플레이어만 사용할 수 있습니다.");
        return false;
    }

    private void sendToolRecipes(CommandSender s) {
        s.sendMessage("§3§l[화학 실험 키트] §7유리병/구리/책/철/레드스톤");
        s.sendMessage("§3§l[설치형 화학 실험대] §7양조기 + 구리 주괴 + 책");
        s.sendMessage("§9§l[비커] §7유리병 + 구리 주괴");
        s.sendMessage("§b§l[시험관] §7유리병 + 철 조각");
        s.sendMessage("§b§l[기체 포집기] §7유리병 + 철 주괴 + 레드스톤");
        s.sendMessage("§c§l[가열기] §7화로 + 블레이즈 가루 + 구리 주괴");
        s.sendMessage("§3§l[전기분해 장치] §7구리 주괴 + 레드스톤 + 유리병");
        s.sendMessage("§6§l[여과 장치] §7호퍼 + 종이 + 유리병");
        s.sendMessage("§d§l[증류 장치] §7양조기 + 유리병 + 구리 주괴");
        s.sendMessage("§e§l[전자저울] §7철 주괴 + 레드스톤 + 돌 압력판");
        s.sendMessage("§5§l[압력 챔버] §7철 블록 + 유리 + 레드스톤 블록");
        s.sendMessage("§d§l[pH 시험지] §7종이 + 빨간색 염료 + 파란색 염료");
        s.sendMessage("§8장비는 분야별 실험실 해금 조건입니다. /chem tech");
    }

    private boolean commandFind(CommandSender sender, String[] args) {
        if (args.length < 2) { sender.sendMessage(P + "사용법: §f/chem find <물질명/화학식/반응명>"); return true; }
        String q = String.join(" ", Arrays.copyOfRange(args, 1, args.length)).toLowerCase(Locale.ROOT);
        int shown = 0;
        sender.sendMessage("§3§l[화학 검색] §f" + String.join(" ", Arrays.copyOfRange(args, 1, args.length)));
        for (ChemDef d : all.values()) {
            String hay = (d.id + " " + d.formula + " " + d.korean + " " + d.english).toLowerCase(Locale.ROOT);
            if (!hay.contains(q)) continue;
            sender.sendMessage("§b물질 §f" + d.formula + " " + d.korean + " §8[" + d.id + "]");
            if (++shown >= 12) break;
        }
        if (shown < 12) {
            for (Reaction r : reactions) {
                String hay = (r.id + " " + r.name + " " + formatReaction(r)).toLowerCase(Locale.ROOT);
                if (!hay.contains(q)) continue;
                sender.sendMessage("§e반응 §f" + r.name + " §8- " + formatReaction(r));
                if (++shown >= 12) break;
            }
        }
        if (shown == 0) sender.sendMessage("§7검색 결과가 없습니다.");
        else if (shown >= 12) sender.sendMessage("§8상위 12개만 표시했습니다.");
        return true;
    }

    private void openMain(Player p) {
        Inventory inv = Bukkit.createInventory(null, 54, MAIN_TITLE);
        decorate(inv);
        inv.setItem(10, button("BOOK", "§3§l주기율표", List.of("§7118개 원소", "§8원소 샘플은 야생 추출 또는 반응으로 획득")));
        inv.setItem(12, button("KNOWLEDGE_BOOK", "§5§l물질 도감", List.of("§7기체·수용액·염·산화물·앙금 등 " + species.size() + "종")));
        inv.setItem(14, button("PAPER", "§e§l반응식 도감", List.of("§7균형 반응식 " + reactions.size() + "개", "§7실험실 종류·온도 조건 확인")));
        inv.setItem(16, button("WRITABLE_BOOK", "§a§l발견 도감", List.of("§7직접 얻은 화학 물질 기록")));

        inv.setItem(28, button("FURNACE", "§6§l야생 물질 추출기", List.of("§7바닐라 재료 → 화학 샘플", "§7지원 루트: " + extractions.size() + "개")));
        inv.setItem(30, labButton(LabType.GENERAL));
        inv.setItem(32, labButton(LabType.GAS));
        inv.setItem(34, labButton(LabType.PRECIPITATION));

        inv.setItem(37, labButton(LabType.SOLUTION));
        inv.setItem(39, labButton(LabType.ACID_BASE));
        inv.setItem(41, labButton(LabType.REDOX));
        inv.setItem(43, labButton(LabType.ELECTROLYSIS));
        inv.setItem(45, labButton(LabType.THERMAL));

        inv.setItem(47, button("REDSTONE_TORCH", "§2§l연구 테크트리", List.of("§7실험 장비 보유 여부와 분야별 해금 상태", "§7장비를 제작하면 해당 실험실 사용 가능")));
        inv.setItem(49, button("COMPASS", "§d§l화학 분석실", List.of("§7물질 상태·분류·pH·앙금 색 분석", "§7pH 시험지 우클릭으로도 바로 열 수 있음")));
        inv.setItem(51, button("SPYGLASS", "§e§l검색 안내", List.of("§7/chem find <물질명/화학식/반응명>")));
        inv.setItem(53, createToolItem("lab_kit"));
        p.openInventory(inv);
    }

    private void openTechTree(Player p) {
        Inventory inv = Bukkit.createInventory(null, 54, TECH_TITLE);
        decorate(inv);
        inv.setItem(4, createToolItem("lab_bench"));
        int[] slots = {10,12,14,16,28,30,32,34};
        int i = 0;
        for (LabType lab : LabType.values()) {
            String req = requiredTool(lab);
            boolean unlocked = req == null || hasTool(p, req) || p.hasPermission("geumyi.chem.admin");
            String toolName = req == null ? "없음" : ToolDef.nameOf(req);
            inv.setItem(slots[i++], button(unlocked ? "LIME_DYE" : "RED_DYE",
                    (unlocked ? "§a§l해금 · " : "§c§l잠김 · ") + lab.display,
                    List.of("§7필요 장비: §f" + toolName, "§7반응식: §f" + countReactions(lab) + "개",
                            unlocked ? "§a사용 가능" : "§c장비를 인벤토리에 보유해야 사용 가능")));
        }
        inv.setItem(40, button(hasTool(p, "filter") ? "LIME_DYE" : "RED_DYE", "§6§l야생 추출", List.of("§7필요 장비: §f여과 장치")));
        inv.setItem(42, button(hasTool(p, "ph_paper") ? "LIME_DYE" : "RED_DYE", "§d§l분석", List.of("§7필요 장비: §fpH 시험지")));
        inv.setItem(49, button("BARRIER", "§c메인으로", List.of()));
        p.openInventory(inv);
    }

    private ItemStack labButton(LabType lab) {
        return button(lab.icon, lab.color + "§l" + lab.display, List.of("§7" + lab.description, "§7등록 반응: §f" + countReactions(lab) + "개"));
    }

    private int countReactions(LabType lab) {
        int n = 0;
        for (Reaction r : reactions) if (r.lab == lab) n++;
        return n;
    }

    private void openElements(Player p, int page) {
        int maxPage = maxPage(elements.size(), 45);
        page = clampPage(page, maxPage);
        Inventory inv = Bukkit.createInventory(null, 54, ELEMENTS_TITLE + (page + 1) + "/" + (maxPage + 1));
        int start = page * 45;
        for (int slot = 0; slot < 45 && start + slot < elements.size(); slot++) inv.setItem(slot, createChemItem(elements.get(start + slot), 1));
        fillBottomBar(inv);
        navigation(inv, page, maxPage);
        p.openInventory(inv);
    }

    private void openSpecies(Player p, int page) {
        int maxPage = maxPage(species.size(), 45);
        page = clampPage(page, maxPage);
        Inventory inv = Bukkit.createInventory(null, 54, SPECIES_TITLE + (page + 1) + "/" + (maxPage + 1));
        int start = page * 45;
        for (int slot = 0; slot < 45 && start + slot < species.size(); slot++) inv.setItem(slot, createChemItem(species.get(start + slot), 1));
        fillBottomBar(inv);
        navigation(inv, page, maxPage);
        p.openInventory(inv);
    }

    private void openReactionGuide(Player p, int page) {
        int maxPage = maxPage(reactions.size(), 45);
        page = clampPage(page, maxPage);
        Inventory inv = Bukkit.createInventory(null, 54, REACTION_GUIDE_TITLE + (page + 1) + "/" + (maxPage + 1));
        int start = page * 45;
        for (int slot = 0; slot < 45 && start + slot < reactions.size(); slot++) {
            Reaction r = reactions.get(start + slot);
            ArrayList<String> lore = new ArrayList<>();
            lore.add("§7분야: " + r.lab.color + r.lab.display);
            lore.add("§7조건: " + r.temperature.display + " §8/ " + r.pressure.display);
            if (!r.catalyst.isEmpty()) {
                ChemDef cat = all.get(r.catalyst);
                lore.add("§7촉매: §f" + (cat == null ? r.catalyst : cat.formula + " " + cat.korean) + " §8(소모 안 됨)");
            }
            lore.add("§f" + formatReaction(r));
            if (!r.note.isEmpty()) lore.add("§7결과: §f" + r.note);
            inv.setItem(slot, button(r.lab.icon, r.lab.color + "§l" + r.name, lore));
        }
        fillBottomBar(inv);
        navigation(inv, page, maxPage);
        p.openInventory(inv);
    }

    private void openExtractionGuide(Player p, int page) {
        List<Map.Entry<String, LinkedHashMap<String, Integer>>> entries = new ArrayList<>(extractions.entrySet());
        int maxPage = maxPage(entries.size(), 45);
        page = clampPage(page, maxPage);
        Inventory inv = Bukkit.createInventory(null, 54, EXTRACT_GUIDE_TITLE + (page + 1) + "/" + (maxPage + 1));
        int start = page * 45;
        for (int slot = 0; slot < 45 && start + slot < entries.size(); slot++) {
            Map.Entry<String, LinkedHashMap<String, Integer>> e = entries.get(start + slot);
            Material m = safeMaterial(e.getKey());
            inv.setItem(slot, button(m.name(), "§6§l" + e.getKey(), List.of("§7추출 결과:", "§f" + formatAmounts(e.getValue()), "§8게임플레이용 추출/연구 모델")));
        }
        fillBottomBar(inv);
        navigation(inv, page, maxPage);
        p.openInventory(inv);
    }

    private void openDiscovered(Player p, int page) {
        Set<String> ids = loadDiscovered(p.getUniqueId());
        ArrayList<ChemDef> found = new ArrayList<>();
        for (ChemDef d : all.values()) if (ids.contains(d.id)) found.add(d);
        int maxPage = maxPage(found.size(), 45);
        page = clampPage(page, maxPage);
        Inventory inv = Bukkit.createInventory(null, 54, DISCOVERED_TITLE + (page + 1) + "/" + (maxPage + 1));
        int start = page * 45;
        for (int slot = 0; slot < 45 && start + slot < found.size(); slot++) inv.setItem(slot, createChemItem(found.get(start + slot), 1));
        fillBottomBar(inv);
        if (found.isEmpty()) inv.setItem(22, button("BOOK", "§7아직 발견한 물질이 없습니다", List.of("§7추출기와 실험실에서 물질을 얻어보세요.")));
        navigation(inv, page, maxPage);
        p.openInventory(inv);
    }

    private void openExtractor(Player p) {
        if (!checkEquipment(p, "filter", "야생 물질 추출기")) return;
        Inventory inv = Bukkit.createInventory(null, 54, EXTRACTOR_TITLE);
        decorate(inv);
        inv.setItem(EXTRACTOR_INPUT, null);
        inv.setItem(22, button("FURNACE", "§6§l1개 추출", List.of("§7입력 슬롯의 바닐라 재료 1개를 처리")));
        inv.setItem(24, button("BLAST_FURNACE", "§c§l스택 추출", List.of("§7입력 슬롯의 재료를 한 번에 처리", "§7최대 " + getConfig().getInt("extraction-batch-limit", 64) + "개")));
        inv.setItem(31, button("PAPER", "§e§l지원 재료 목록", List.of("§7현재 " + extractions.size() + "개 야생/연구 루트")));
        inv.setItem(49, button("BARRIER", "§c메인으로", List.of("§7남은 입력 재료는 자동 반환됩니다.")));
        p.openInventory(inv);
    }

    private void openLab(Player p, LabType lab) {
        if (!isLabEnabled(lab) && !p.hasPermission("geumyi.chem.admin")) {
            p.sendMessage(P + "§c현재 이 실험실은 비활성화되어 있습니다.");
            return;
        }
        String required = requiredTool(lab);
        if (required != null && !checkEquipment(p, required, lab.display)) return;
        Inventory inv = Bukkit.createInventory(null, 54, lab.title);
        decorate(inv);
        for (int slot : LAB_INPUTS) inv.setItem(slot, null);
        inv.setItem(CATALYST_SLOT, null);
        Temperature t = playerTemperature.getOrDefault(p.getUniqueId(), Temperature.ROOM);
        Pressure pressure = playerPressure.getOrDefault(p.getUniqueId(), Pressure.NORMAL);
        inv.setItem(23, temperatureButton(t));
        inv.setItem(24, button("LIME_DYE", "§a§l반응 실행", List.of("§7입력 + 온도 + 압력 + 촉매 조건을 검사", "§7조건 불일치 시 재료는 소모되지 않음")));
        inv.setItem(25, pressureButton(pressure));
        inv.setItem(26, button("KNOWLEDGE_BOOK", "§e사용법", List.of("§71. 왼쪽 9칸에 반응물", "§72. 촉매가 필요하면 22번 슬롯", "§73. 온도/압력 조건 선택", "§74. 반응 실행 · /chem reactions")));
        inv.setItem(49, button("BARRIER", "§c메인으로", List.of("§7남은 반응물·촉매는 자동 반환됩니다.")));
        p.openInventory(inv);
    }

    private String requiredTool(LabType lab) {
        return switch (lab) {
            case GENERAL -> "beaker";
            case SOLUTION -> "distiller";
            case GAS -> "gas_collector";
            case PRECIPITATION -> "test_tube";
            case ACID_BASE -> "ph_paper";
            case REDOX -> "scale";
            case ELECTROLYSIS -> "electrolyzer";
            case THERMAL -> "heater";
        };
    }

    private boolean checkEquipment(Player p, String toolId, String feature) {
        if (p.hasPermission("geumyi.chem.admin") || hasTool(p, toolId)) return true;
        p.sendMessage(P + "§c" + feature + " 사용에 §f" + ToolDef.nameOf(toolId) + "§c 장비가 필요합니다. §7/chem recipe");
        return false;
    }

    private boolean hasTool(Player p, String toolId) {
        for (ItemStack item : p.getInventory().getContents()) if (toolId.equals(getToolId(item))) return true;
        return false;
    }

    private ItemStack pressureButton(Pressure p) {
        return p == Pressure.NORMAL
                ? button("GLASS_BOTTLE", "§f§l압력: 일반", List.of("§7클릭 → §5고압"))
                : button("HEAVY_CORE", "§5§l압력: 고압", List.of("§7클릭 → §f일반"));
    }

    private boolean isLabEnabled(LabType lab) {
        String key = "labs." + lab.name().toLowerCase(Locale.ROOT) + ".enabled";
        return getConfig().getBoolean(key, true);
    }

    private ItemStack temperatureButton(Temperature t) {
        return t == Temperature.ROOM
                ? button("ICE", "§b§l조건: 상온", List.of("§7클릭 → §c가열"))
                : button("MAGMA_CREAM", "§c§l조건: 가열", List.of("§7클릭 → §b상온"));
    }

    private void openAnalysis(Player p) {
        if (!checkEquipment(p, "ph_paper", "화학 분석실")) return;
        Inventory inv = Bukkit.createInventory(null, 54, ANALYSIS_TITLE);
        decorate(inv);
        inv.setItem(ANALYSIS_INPUT, null);
        inv.setItem(22, button("SPYGLASS", "§d§l분석 실행", List.of("§7화학 샘플을 소비하지 않고", "§7상태·분류·pH·앙금 정보를 확인")));
        inv.setItem(31, button("PAPER", "§7분석 대기 중", List.of("§7왼쪽 입력 칸에 화학 샘플을 넣으세요.")));
        inv.setItem(49, button("BARRIER", "§c메인으로", List.of("§7입력 샘플은 자동 반환됩니다.")));
        p.openInventory(inv);
    }

    private int maxPage(int size, int pageSize) { return Math.max(0, (Math.max(1, size) - 1) / pageSize); }
    private int clampPage(int page, int maxPage) { return Math.max(0, Math.min(maxPage, page)); }

    private void navigation(Inventory inv, int page, int maxPage) {
        if (page > 0) inv.setItem(45, button("ARROW", "§e이전 페이지", List.of()));
        inv.setItem(49, button("BARRIER", "§c메인으로", List.of()));
        if (page < maxPage) inv.setItem(53, button("ARROW", "§e다음 페이지", List.of()));
    }

    private void decorate(Inventory inv) {
        ItemStack pane = button("GRAY_STAINED_GLASS_PANE", "§8 ", List.of());
        for (int i = 0; i < inv.getSize(); i++) inv.setItem(i, pane.clone());
    }

    private void fillBottomBar(Inventory inv) {
        ItemStack pane = button("GRAY_STAINED_GLASS_PANE", "§8 ", List.of());
        for (int i = 45; i < 54; i++) inv.setItem(i, pane.clone());
    }

    private ItemStack button(String material, String name, List<String> lore) {
        ItemStack item = new ItemStack(safeMaterial(material), 1);
        ItemMeta meta = item.getItemMeta();
        if (meta != null) {
            meta.setDisplayName(name);
            if (!lore.isEmpty()) meta.setLore(lore);
            item.setItemMeta(meta);
        }
        return item;
    }

    private ItemStack createChemItem(ChemDef def, int amount) {
        ItemStack item = new ItemStack(safeMaterial(def.material), Math.max(1, Math.min(64, amount)));
        ItemMeta meta = item.getItemMeta();
        if (meta != null) {
            boolean ko = getConfig().getBoolean("show-korean-names", true);
            String shownName = ko ? def.korean : def.english;
            String secondary = ko ? def.english : def.korean;
            String color = colorFor(def);
            meta.setDisplayName("§3§l[CHEM] " + color + "§l" + def.formula + " §f" + shownName);
            ArrayList<String> lore = new ArrayList<>();
            lore.add("§8Geumyi Chemistry · 공식 화학 샘플");
            lore.add("§7영문: §f" + secondary);
            if (def.type == ChemType.ELEMENT) {
                lore.add("§7종류: §b원소 §8| §7원자번호: §f" + def.atomicNumber);
                lore.add("§7분류: §f" + def.group);
            } else {
                lore.add("§7상태: §f" + def.state.display + " §8| §7분류: §f" + groupDisplay(def.group));
                if (def.ph != null) lore.add("§7pH 모델: §f" + cleanNumber(def.ph));
                if (!def.precipitateColor.isEmpty()) lore.add("§7앙금 색: §f" + def.precipitateColor);
            }
            lore.add("§7" + def.description);
            lore.add("§8ID: " + def.id + " · v" + VERSION);
            meta.setLore(lore);
            applyItemModel(meta, (def.type == ChemType.ELEMENT ? "element/" : "species/") + safeModelId(def.id));
            try { meta.setEnchantmentGlintOverride(true); } catch (Throwable ignored) { }
            PersistentDataContainer pdc = meta.getPersistentDataContainer();
            pdc.set(itemKindKey, PersistentDataType.STRING, "substance");
            pdc.set(chemIdKey, PersistentDataType.STRING, def.id);
            pdc.set(itemVersionKey, PersistentDataType.INTEGER, 4);
            item.setItemMeta(meta);
        }
        return item;
    }

    private String colorFor(ChemDef d) {
        if (d.type == ChemType.ELEMENT) return "§b";
        return switch (d.state) {
            case GAS -> "§f";
            case AQUEOUS, LIQUID -> "§9";
            case PRECIPITATE -> "§e";
            default -> "§d";
        };
    }

    private String groupDisplay(String g) {
        return switch (g.toUpperCase(Locale.ROOT)) {
            case "GAS" -> "기체";
            case "ACID" -> "산";
            case "BASE" -> "염기";
            case "SALT" -> "염";
            case "OXIDE" -> "산화물";
            case "PRECIPITATE" -> "앙금";
            case "SOLVENT" -> "용매";
            case "HALOGEN" -> "할로젠";
            case "SULFIDE" -> "황화물";
            default -> g;
        };
    }

    private String cleanNumber(double d) {
        if (Math.rint(d) == d) return Integer.toString((int) d);
        return Double.toString(d);
    }

    private ItemStack createToolItem(String id) {
        ToolDef def = ToolDef.byId(id);
        if (def == null) return null;
        ItemStack item = new ItemStack(safeMaterial(def.material), 1);
        ItemMeta meta = item.getItemMeta();
        if (meta != null) {
            meta.setDisplayName(def.color + "§l[CHEM] " + def.name);
            ArrayList<String> lore = new ArrayList<>();
            lore.addAll(def.lore);
            lore.add("§8Geumyi Chemistry · 장비 · v" + VERSION);
            meta.setLore(lore);
            applyItemModel(meta, "tool/" + safeModelId(def.id));
            try { meta.setEnchantmentGlintOverride(true); } catch (Throwable ignored) { }
            PersistentDataContainer pdc = meta.getPersistentDataContainer();
            pdc.set(itemKindKey, PersistentDataType.STRING, "tool");
            pdc.set(toolIdKey, PersistentDataType.STRING, def.id);
            pdc.set(itemVersionKey, PersistentDataType.INTEGER, 4);
            item.setItemMeta(meta);
        }
        return item;
    }

    private void applyItemModel(ItemMeta meta, String path) {
        if (!getConfig().getBoolean("resource-pack.use-item-models", true)) return;
        try { meta.setItemModel(new NamespacedKey("geumyi_chem", path)); }
        catch (Throwable ignored) { }
    }

    private String safeModelId(String id) {
        return id.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9._/-]", "_");
    }

    private Material safeMaterial(String name) {
        Material m = safeMaterialOrNull(name);
        return m == null ? Material.PAPER : m;
    }

    private Material safeMaterialOrNull(String name) {
        try { return Material.valueOf(name.toUpperCase(Locale.ROOT)); }
        catch (IllegalArgumentException ex) { return null; }
    }

    private ChemDef getChemDef(String id) {
        if (id == null) return null;
        ChemDef exact = all.get(id);
        if (exact != null) return exact;
        for (ChemDef d : all.values()) if (d.id.equalsIgnoreCase(id) || d.formula.equalsIgnoreCase(id)) return d;
        return null;
    }

    private String getChemId(ItemStack item) {
        if (isAir(item)) return null;
        ItemMeta meta = item.getItemMeta();
        if (meta == null) return null;
        return meta.getPersistentDataContainer().get(chemIdKey, PersistentDataType.STRING);
    }

    private String getToolId(ItemStack item) {
        if (isAir(item)) return null;
        ItemMeta meta = item.getItemMeta();
        if (meta == null) return null;
        return meta.getPersistentDataContainer().get(toolIdKey, PersistentDataType.STRING);
    }

    private boolean isAir(ItemStack item) { return item == null || item.getType() == Material.AIR; }

    @EventHandler
    public void onPlayerInteract(PlayerInteractEvent e) {
        if (e.getHand() != null && e.getHand() != EquipmentSlot.HAND) return;
        Action action = e.getAction();
        if (action != Action.RIGHT_CLICK_AIR && action != Action.RIGHT_CLICK_BLOCK) return;
        if (action == Action.RIGHT_CLICK_BLOCK && e.getClickedBlock() != null && isLabBenchBlock(e.getClickedBlock())) {
            e.setCancelled(true);
            openMain(e.getPlayer());
            return;
        }
        ItemStack item = e.getItem();
        if (isAir(item)) return;

        String tool = getToolId(item);
        if (tool != null) {
            if (tool.equals("lab_bench") && action == Action.RIGHT_CLICK_BLOCK) return; // allow normal brewing-stand placement
            e.setCancelled(true);
            if (tool.equals("lab_kit")) openMain(e.getPlayer());
            else if (tool.equals("ph_paper")) openAnalysis(e.getPlayer());
            else if (tool.equals("lab_bench")) e.getPlayer().sendMessage(P + "§7블록 면을 우클릭해 설치하세요.");
            else e.getPlayer().sendMessage(P + "§7실험 장비입니다. §f/chem tech§7에서 해금 상태를 확인하세요.");
            return;
        }
        if (getChemId(item) != null && getConfig().getBoolean("protect-chem-items-from-vanilla-use", true)) {
            e.setCancelled(true);
            e.getPlayer().sendMessage(P + "§7화학 샘플은 일반 아이템으로 사용할 수 없습니다. 화학 실험 키트를 사용하세요.");
        }
    }

    @EventHandler
    public void onPlayerInteractEntity(PlayerInteractEntityEvent e) {
        if (!getConfig().getBoolean("protect-chem-items-from-vanilla-use", true)) return;
        ItemStack item = e.getPlayer().getInventory().getItem(e.getHand());
        if (getChemId(item) != null || getToolId(item) != null) {
            e.setCancelled(true);
            e.getPlayer().sendMessage(P + "§7화학 샘플/장비는 일반 엔티티 상호작용에 사용할 수 없습니다.");
        }
    }

    @EventHandler
    public void onBlockPlace(BlockPlaceEvent e) {
        ItemStack item = e.getItemInHand();
        String tool = getToolId(item);
        if ("lab_bench".equals(tool)) {
            if (e.getBlockPlaced().getState() instanceof TileState tile) {
                tile.getPersistentDataContainer().set(labBlockKey, PersistentDataType.STRING, "lab_bench");
                tile.update(true, false);
            } else {
                e.setCancelled(true);
                e.getPlayer().sendMessage(P + "§c이 서버 버전에서는 화학 실험대 상태를 저장할 수 없습니다.");
            }
            return;
        }
        if (getChemId(item) != null || tool != null) {
            if (getConfig().getBoolean("protect-chem-items-from-vanilla-use", true)) e.setCancelled(true);
        }
    }

    private boolean isLabBenchBlock(Block block) {
        if (block == null) return false;
        if (!(block.getState() instanceof TileState tile)) return false;
        return "lab_bench".equals(tile.getPersistentDataContainer().get(labBlockKey, PersistentDataType.STRING));
    }

    @EventHandler
    public void onLabBenchBreak(BlockBreakEvent e) {
        if (!isLabBenchBlock(e.getBlock())) return;
        e.setDropItems(false);
        e.getBlock().getWorld().dropItemNaturally(e.getBlock().getLocation(), createToolItem("lab_bench"));
    }

    @EventHandler
    public void onLabBenchExplode(BlockExplodeEvent e) {
        e.blockList().removeIf(this::isLabBenchBlock);
    }

    @EventHandler
    public void onLabBenchEntityExplode(EntityExplodeEvent e) {
        e.blockList().removeIf(this::isLabBenchBlock);
    }

    @EventHandler
    public void onConsume(PlayerItemConsumeEvent e) {
        if (getChemId(e.getItem()) != null || getToolId(e.getItem()) != null) {
            if (getConfig().getBoolean("protect-chem-items-from-vanilla-use", true)) {
                e.setCancelled(true);
                e.getPlayer().sendMessage(P + "§c화학 샘플은 음식/물약처럼 사용할 수 없습니다.");
            }
        }
    }

    @EventHandler
    public void onBrew(BrewEvent e) {
        if (!getConfig().getBoolean("protect-chem-items-from-vanilla-use", true)) return;
        for (ItemStack item : e.getContents().getContents()) {
            if (getChemId(item) != null || getToolId(item) != null) {
                e.setCancelled(true);
                return;
            }
        }
    }

    @EventHandler
    public void onPrepareAnvil(PrepareAnvilEvent e) {
        if (!getConfig().getBoolean("protect-chem-items-from-vanilla-use", true)) return;
        for (ItemStack item : e.getInventory().getContents()) {
            if (getChemId(item) != null || getToolId(item) != null) {
                e.setResult(null);
                return;
            }
        }
    }

    @EventHandler
    public void onPrepareCraft(PrepareItemCraftEvent e) {
        if (!getConfig().getBoolean("protect-chem-items-from-vanilla-use", true)) return;
        for (ItemStack item : e.getInventory().getMatrix()) {
            if (getChemId(item) != null || getToolId(item) != null) {
                e.getInventory().setResult(null);
                return;
            }
        }
    }

    @EventHandler
    public void onJoin(PlayerJoinEvent e) {
        if (getConfig().getBoolean("migrate-items-on-join", true)) migratePlayerInventory(e.getPlayer());
    }

    @EventHandler
    public void onInventoryClick(InventoryClickEvent e) {
        String title = e.getView().getTitle();
        if (!isChemGui(title)) return;
        HumanEntity human = e.getWhoClicked();
        if (!(human instanceof Player p)) return;
        int raw = e.getRawSlot();
        int topSize = e.getView().getTopInventory().getSize();

        LabType currentLab = labFromTitle(title);
        if (currentLab != null) {
            if (e.isShiftClick()) { e.setCancelled(true); return; }
            if (raw >= topSize) return;
            if (LAB_INPUT_SET.contains(raw) || raw == CATALYST_SLOT) return;
            e.setCancelled(true);
            if (raw == 23) {
                Temperature next = playerTemperature.getOrDefault(p.getUniqueId(), Temperature.ROOM) == Temperature.ROOM
                        ? Temperature.HEATED : Temperature.ROOM;
                playerTemperature.put(p.getUniqueId(), next);
                e.getView().getTopInventory().setItem(23, temperatureButton(next));
            } else if (raw == 24) {
                runReaction(p, e.getView().getTopInventory(), currentLab);
            } else if (raw == 25) {
                Pressure next = playerPressure.getOrDefault(p.getUniqueId(), Pressure.NORMAL) == Pressure.NORMAL ? Pressure.HIGH : Pressure.NORMAL;
                if (next == Pressure.HIGH && !p.hasPermission("geumyi.chem.admin") && !hasTool(p, "pressure_chamber")) {
                    p.sendMessage(P + "§c고압 조건에는 §f압력 챔버§c가 필요합니다. §7/chem recipe");
                    return;
                }
                playerPressure.put(p.getUniqueId(), next);
                e.getView().getTopInventory().setItem(25, pressureButton(next));
            } else if (raw == 49) {
                returnItems(p, e.getView().getTopInventory(), LAB_INPUTS);
                returnItems(p, e.getView().getTopInventory(), new int[]{CATALYST_SLOT});
                openMain(p);
            }
            return;
        }

        if (title.equals(EXTRACTOR_TITLE)) {
            if (e.isShiftClick()) { e.setCancelled(true); return; }
            if (raw >= topSize) return;
            if (raw == EXTRACTOR_INPUT) return;
            e.setCancelled(true);
            if (raw == 22) runExtraction(p, e.getView().getTopInventory(), false);
            else if (raw == 24) runExtraction(p, e.getView().getTopInventory(), true);
            else if (raw == 31) {
                returnItems(p, e.getView().getTopInventory(), new int[]{EXTRACTOR_INPUT});
                openExtractionGuide(p, 0);
            } else if (raw == 49) {
                returnItems(p, e.getView().getTopInventory(), new int[]{EXTRACTOR_INPUT});
                openMain(p);
            }
            return;
        }

        if (title.equals(ANALYSIS_TITLE)) {
            if (e.isShiftClick()) { e.setCancelled(true); return; }
            if (raw >= topSize) return;
            if (raw == ANALYSIS_INPUT) return;
            e.setCancelled(true);
            if (raw == 22) runAnalysis(p, e.getView().getTopInventory());
            else if (raw == 49) {
                returnItems(p, e.getView().getTopInventory(), new int[]{ANALYSIS_INPUT});
                openMain(p);
            }
            return;
        }

        e.setCancelled(true);
        if (title.equals(MAIN_TITLE)) {
            switch (raw) {
                case 10 -> openElements(p, 0);
                case 12 -> openSpecies(p, 0);
                case 14 -> openReactionGuide(p, 0);
                case 16 -> openDiscovered(p, 0);
                case 28 -> openExtractor(p);
                case 30 -> openLab(p, LabType.GENERAL);
                case 32 -> openLab(p, LabType.GAS);
                case 34 -> openLab(p, LabType.PRECIPITATION);
                case 37 -> openLab(p, LabType.SOLUTION);
                case 39 -> openLab(p, LabType.ACID_BASE);
                case 41 -> openLab(p, LabType.REDOX);
                case 43 -> openLab(p, LabType.ELECTROLYSIS);
                case 45 -> openLab(p, LabType.THERMAL);
                case 47 -> openTechTree(p);
                case 49 -> openAnalysis(p);
                default -> { }
            }
            return;
        }

        if (title.equals(TECH_TITLE)) {
            if (raw == 49) openMain(p);
            return;
        }

        if (title.startsWith(ELEMENTS_TITLE)) {
            handlePagedChemClick(p, e, title, elements, PageKind.ELEMENTS);
            return;
        }
        if (title.startsWith(SPECIES_TITLE)) {
            handlePagedChemClick(p, e, title, species, PageKind.SPECIES);
            return;
        }
        if (title.startsWith(REACTION_GUIDE_TITLE)) {
            int page = pageFromTitle(title);
            int max = maxPage(reactions.size(), 45);
            if (raw == 45 && page > 0) openReactionGuide(p, page - 1);
            else if (raw == 49) openMain(p);
            else if (raw == 53 && page < max) openReactionGuide(p, page + 1);
            return;
        }
        if (title.startsWith(EXTRACT_GUIDE_TITLE)) {
            int page = pageFromTitle(title);
            int max = maxPage(extractions.size(), 45);
            if (raw == 45 && page > 0) openExtractionGuide(p, page - 1);
            else if (raw == 49) openMain(p);
            else if (raw == 53 && page < max) openExtractionGuide(p, page + 1);
            return;
        }
        if (title.startsWith(DISCOVERED_TITLE)) {
            int page = pageFromTitle(title);
            int max = maxPage(loadDiscovered(p.getUniqueId()).size(), 45);
            if (raw == 45 && page > 0) openDiscovered(p, page - 1);
            else if (raw == 49) openMain(p);
            else if (raw == 53 && page < max) openDiscovered(p, page + 1);
        }
    }

    private void handlePagedChemClick(Player p, InventoryClickEvent e, String title, List<ChemDef> data, PageKind kind) {
        int raw = e.getRawSlot();
        int page = pageFromTitle(title);
        int max = maxPage(data.size(), 45);
        if (raw == 45 && page > 0) {
            if (kind == PageKind.ELEMENTS) openElements(p, page - 1); else openSpecies(p, page - 1);
        } else if (raw == 49) {
            openMain(p);
        } else if (raw == 53 && page < max) {
            if (kind == PageKind.ELEMENTS) openElements(p, page + 1); else openSpecies(p, page + 1);
        } else if (raw >= 0 && raw < 45 && e.isShiftClick() && p.hasPermission("geumyi.chem.admin")) {
            String id = getChemId(e.getView().getTopInventory().getItem(raw));
            if (id != null) giveChem(p, id, 1);
        }
    }

    @EventHandler
    public void onInventoryDrag(InventoryDragEvent e) {
        String title = e.getView().getTitle();
        if (labFromTitle(title) != null || title.equals(EXTRACTOR_TITLE) || title.equals(ANALYSIS_TITLE)) {
            // Disable GUI drags. This is deliberately conservative for Java/Geyser parity and duplication safety.
            e.setCancelled(true);
        }
    }

    @EventHandler
    public void onInventoryClose(InventoryCloseEvent e) {
        HumanEntity human = e.getPlayer();
        if (!(human instanceof Player p)) return;
        String title = e.getView().getTitle();
        if (labFromTitle(title) != null) {
            returnItems(p, e.getInventory(), LAB_INPUTS);
            returnItems(p, e.getInventory(), new int[]{CATALYST_SLOT});
        }
        else if (title.equals(EXTRACTOR_TITLE)) returnItems(p, e.getInventory(), new int[]{EXTRACTOR_INPUT});
        else if (title.equals(ANALYSIS_TITLE)) returnItems(p, e.getInventory(), new int[]{ANALYSIS_INPUT});
    }

    private boolean isChemGui(String title) {
        return title.equals(MAIN_TITLE) || title.startsWith(ELEMENTS_TITLE) || title.startsWith(SPECIES_TITLE)
                || title.startsWith(REACTION_GUIDE_TITLE) || title.startsWith(EXTRACT_GUIDE_TITLE)
                || title.equals(EXTRACTOR_TITLE) || title.equals(ANALYSIS_TITLE) || title.equals(TECH_TITLE) || title.startsWith(DISCOVERED_TITLE)
                || labFromTitle(title) != null;
    }

    private LabType labFromTitle(String title) {
        for (LabType lab : LabType.values()) if (lab.title.equals(title)) return lab;
        return null;
    }

    private int pageFromTitle(String title) {
        int dash = title.lastIndexOf("- ");
        if (dash < 0) return 0;
        String part = title.substring(dash + 2).trim();
        int slash = part.indexOf('/');
        if (slash < 0) return 0;
        try { return Math.max(0, Integer.parseInt(part.substring(0, slash).trim()) - 1); }
        catch (NumberFormatException ex) { return 0; }
    }

    private void runReaction(Player p, Inventory inv, LabType lab) {
        LinkedHashMap<String, Integer> present = new LinkedHashMap<>();
        for (int slot : LAB_INPUTS) {
            ItemStack stack = inv.getItem(slot);
            if (isAir(stack)) continue;
            String id = getChemId(stack);
            if (id == null) { failReaction(p, "실험실에는 [CHEM] 화학 샘플만 넣어주세요."); return; }
            present.merge(id, stack.getAmount(), Integer::sum);
        }
        if (present.isEmpty()) { failReaction(p, "입력 재료가 없습니다."); return; }

        String catalystId = getChemId(inv.getItem(CATALYST_SLOT));
        if (!isAir(inv.getItem(CATALYST_SLOT)) && catalystId == null) { failReaction(p, "촉매 슬롯에는 [CHEM] 화학 샘플만 넣어주세요."); return; }
        Temperature currentTemp = playerTemperature.getOrDefault(p.getUniqueId(), Temperature.ROOM);
        Pressure currentPressure = playerPressure.getOrDefault(p.getUniqueId(), Pressure.NORMAL);
        Reaction best = null;
        Reaction materialMatch = null;
        int bestScore = -1;
        for (Reaction r : reactions) {
            if (r.lab != lab || !matchesInputs(present, r.inputs)) continue;
            if (materialMatch == null || r.requiredTotal() > materialMatch.requiredTotal()) materialMatch = r;
            if (r.temperature != currentTemp || r.pressure != currentPressure) continue;
            if (!r.catalyst.isEmpty() && !r.catalyst.equals(catalystId)) continue;
            int score = r.requiredTotal() + (r.catalyst.isEmpty() ? 0 : 5) + (r.pressure == Pressure.HIGH ? 2 : 0);
            if (score > bestScore) { best = r; bestScore = score; }
        }

        if (best == null) {
            if (materialMatch != null) {
                ArrayList<String> cond = new ArrayList<>();
                cond.add(materialMatch.temperature.display);
                cond.add(materialMatch.pressure.display);
                if (!materialMatch.catalyst.isEmpty()) {
                    ChemDef cat = all.get(materialMatch.catalyst);
                    cond.add("§6촉매 " + (cat == null ? materialMatch.catalyst : cat.formula));
                }
                failReaction(p, "반응물은 맞지만 조건이 다릅니다. 필요: " + String.join(" §8/ ", cond));
            } else failReaction(p, "이 실험실에서 일치하는 반응식을 찾지 못했습니다. /chem reactions");
            return;
        }

        int batches = Integer.MAX_VALUE;
        for (Map.Entry<String, Integer> req : best.inputs.entrySet()) batches = Math.min(batches, present.getOrDefault(req.getKey(), 0) / req.getValue());
        int limit = Math.max(1, getConfig().getInt("reaction-batch-limit", 16));
        batches = Math.max(1, Math.min(limit, batches));
        consumeInputs(inv, best.inputs, batches);
        for (Map.Entry<String, Integer> out : best.outputs.entrySet()) giveChem(p, out.getKey(), out.getValue() * batches);
        p.sendMessage(P + "§a반응 성공! §f" + best.name + (batches > 1 ? " §7×" + batches : ""));
        p.sendMessage(P + "§8" + formatReaction(best));
        if (!best.note.isEmpty()) p.sendMessage(P + "§7관찰: §f" + best.note);
        playObservation(p, best);
    }

    private void failReaction(Player p, String message) {
        p.sendMessage(P + "§c" + message);
        try { p.getWorld().spawnParticle(Particle.SMOKE, p.getLocation().add(0, 1.1, 0), 6, 0.18, 0.12, 0.18, 0.01); } catch (Throwable ignored) { }
    }

    private void playObservation(Player p, Reaction r) {
        Location loc = p.getLocation().add(0, 1.1, 0);
        try {
            switch (r.lab) {
                case GAS -> p.getWorld().spawnParticle(Particle.CLOUD, loc, 14, 0.28, 0.25, 0.28, 0.02);
                case PRECIPITATION -> {
                    Color c = precipitateColorFor(r);
                    p.getWorld().spawnParticle(Particle.DUST, loc, 18, 0.28, 0.20, 0.28, 0.0, new Particle.DustOptions(c, 1.2f));
                }
                case THERMAL -> p.getWorld().spawnParticle(Particle.FLAME, loc, 14, 0.25, 0.18, 0.25, 0.02);
                case ELECTROLYSIS -> p.getWorld().spawnParticle(Particle.ELECTRIC_SPARK, loc, 16, 0.25, 0.20, 0.25, 0.05);
                case ACID_BASE, SOLUTION -> p.getWorld().spawnParticle(Particle.BUBBLE_POP, loc, 12, 0.25, 0.18, 0.25, 0.02);
                default -> p.getWorld().spawnParticle(Particle.END_ROD, loc, 10, 0.20, 0.18, 0.20, 0.01);
            }
            p.playSound(p.getLocation(), "block.brewing_stand.brew", 0.6f, 1.2f);
        } catch (Throwable ignored) { }
    }

    private Color precipitateColorFor(Reaction r) {
        for (String id : r.outputs.keySet()) {
            ChemDef d = all.get(id);
            if (d == null || d.precipitateColor.isEmpty()) continue;
            String x = d.precipitateColor;
            if (x.contains("노란")) return Color.YELLOW;
            if (x.contains("파란")) return Color.BLUE;
            if (x.contains("적갈") || x.contains("갈")) return Color.fromRGB(150, 70, 45);
            if (x.contains("검")) return Color.BLACK;
        }
        return Color.WHITE;
    }

    private boolean matchesInputs(Map<String, Integer> present, Map<String, Integer> required) {
        for (String presentId : present.keySet()) if (!required.containsKey(presentId)) return false;
        for (Map.Entry<String, Integer> req : required.entrySet()) if (present.getOrDefault(req.getKey(), 0) < req.getValue()) return false;
        return true;
    }

    private void consumeInputs(Inventory inv, Map<String, Integer> required, int batches) {
        HashMap<String, Integer> left = new HashMap<>();
        for (Map.Entry<String, Integer> e : required.entrySet()) left.put(e.getKey(), e.getValue() * batches);
        for (int slot : LAB_INPUTS) {
            ItemStack stack = inv.getItem(slot);
            String id = getChemId(stack);
            if (id == null) continue;
            int need = left.getOrDefault(id, 0);
            if (need <= 0) continue;
            int take = Math.min(need, stack.getAmount());
            int remain = stack.getAmount() - take;
            if (remain <= 0) inv.setItem(slot, null); else stack.setAmount(remain);
            left.put(id, need - take);
        }
    }

    private String formatReaction(Reaction r) { return formatAmounts(r.inputs) + " → " + formatAmounts(r.outputs); }

    private String formatAmounts(Map<String, Integer> map) {
        ArrayList<String> parts = new ArrayList<>();
        for (Map.Entry<String, Integer> e : map.entrySet()) {
            ChemDef d = all.get(e.getKey());
            String formula = d == null ? e.getKey() : d.formula;
            parts.add((e.getValue() == 1 ? "" : e.getValue()) + formula);
        }
        return String.join(" + ", parts);
    }

    private void runExtraction(Player p, Inventory inv, boolean wholeStack) {
        ItemStack input = inv.getItem(EXTRACTOR_INPUT);
        if (isAir(input)) { p.sendMessage(P + "§e추출할 바닐라 재료를 넣어주세요."); return; }
        if (getChemId(input) != null || getToolId(input) != null) {
            p.sendMessage(P + "§c추출기는 일반 바닐라 재료 전용입니다.");
            return;
        }
        String material = input.getType().name();
        Map<String, Integer> outputs = extractions.get(material);
        if (outputs == null || outputs.isEmpty()) {
            p.sendMessage(P + "§c지원되지 않는 추출 재료입니다: §f" + material + " §7(/chem routes)");
            return;
        }

        int limit = Math.max(1, getConfig().getInt("extraction-batch-limit", 64));
        int count = wholeStack ? Math.min(input.getAmount(), limit) : 1;
        int remain = input.getAmount() - count;
        if (remain <= 0) inv.setItem(EXTRACTOR_INPUT, null); else input.setAmount(remain);

        for (Map.Entry<String, Integer> out : outputs.entrySet()) giveChem(p, out.getKey(), out.getValue() * count);
        returnContainers(p, material, count);
        p.sendMessage(P + "§a추출 완료" + (count > 1 ? " §7×" + count : "") + ": §f" + formatScaledAmounts(outputs, count));
    }

    private String formatScaledAmounts(Map<String, Integer> map, int scale) {
        LinkedHashMap<String, Integer> scaled = new LinkedHashMap<>();
        for (Map.Entry<String, Integer> e : map.entrySet()) scaled.put(e.getKey(), e.getValue() * scale);
        return formatAmounts(scaled);
    }

    private void returnContainers(Player p, String material, int count) {
        if (material.equals("WATER_BUCKET") || material.equals("MILK_BUCKET")) giveVanillaAmount(p, Material.BUCKET, count);
        else if (material.equals("HONEY_BOTTLE")) giveVanillaAmount(p, Material.GLASS_BOTTLE, count);
    }

    private void giveVanillaAmount(Player p, Material material, int amount) {
        int left = amount;
        while (left > 0) {
            int n = Math.min(material.getMaxStackSize(), left);
            giveVanilla(p, new ItemStack(material, n));
            left -= n;
        }
    }

    private void runAnalysis(Player p, Inventory inv) {
        ItemStack input = inv.getItem(ANALYSIS_INPUT);
        if (isAir(input)) { p.sendMessage(P + "§e분석할 화학 샘플을 넣어주세요."); return; }
        String id = getChemId(input);
        ChemDef d = id == null ? null : all.get(id);
        if (d == null) { p.sendMessage(P + "§c[CHEM] 화학 샘플만 분석할 수 있습니다."); return; }

        ArrayList<String> lore = new ArrayList<>();
        lore.add("§7ID: §f" + d.id);
        if (d.type == ChemType.ELEMENT) {
            lore.add("§7종류: §b원소");
            lore.add("§7원자번호: §f" + d.atomicNumber);
            lore.add("§7분류: §f" + d.group);
        } else {
            lore.add("§7상태: §f" + d.state.display);
            lore.add("§7분류: §f" + groupDisplay(d.group));
            if (d.ph != null) lore.add("§7pH 모델: §f" + cleanNumber(d.ph) + " §8(" + phLabel(d.ph) + ")");
            else lore.add("§7pH: §8해당 없음/미정");
            if (!d.precipitateColor.isEmpty()) lore.add("§7앙금 색: §f" + d.precipitateColor);
        }
        lore.add("§7" + d.description);
        inv.setItem(31, button(d.material, "§d§l분석 결과: §f" + d.formula + " " + d.korean, lore));
        p.sendMessage(P + "§a분석 완료: §f" + d.formula + " " + d.korean);
    }

    private String phLabel(double ph) {
        if (ph < 7.0) return "산성";
        if (ph > 7.0) return "염기성";
        return "중성";
    }

    private void registerRecipes() {
        try { Bukkit.removeRecipe(labKitRecipeKey); } catch (Throwable ignored) { }
        try { Bukkit.removeRecipe(phPaperRecipeKey); } catch (Throwable ignored) { }
        for (NamespacedKey key : toolRecipeKeys.values()) try { Bukkit.removeRecipe(key); } catch (Throwable ignored) { }

        if (getConfig().getBoolean("recipes.lab-kit-enabled", true)) {
            ShapedRecipe kit = new ShapedRecipe(labKitRecipeKey, createToolItem("lab_kit"));
            kit.shape(" G ", "CBC", "IRI");
            kit.setIngredient('G', Material.GLASS_BOTTLE); kit.setIngredient('C', Material.COPPER_INGOT); kit.setIngredient('B', Material.BOOK);
            kit.setIngredient('I', Material.IRON_INGOT); kit.setIngredient('R', Material.REDSTONE); Bukkit.addRecipe(kit);
        }
        if (getConfig().getBoolean("recipes.ph-paper-enabled", true)) {
            ShapelessRecipe ph = new ShapelessRecipe(phPaperRecipeKey, createToolItem("ph_paper"));
            ph.addIngredient(Material.PAPER); ph.addIngredient(Material.RED_DYE); ph.addIngredient(Material.BLUE_DYE); Bukkit.addRecipe(ph);
        }
        addShapelessTool("lab_bench", Material.BREWING_STAND, Material.COPPER_INGOT, Material.BOOK);
        addShapelessTool("beaker", Material.GLASS_BOTTLE, Material.COPPER_INGOT);
        addShapelessTool("test_tube", Material.GLASS_BOTTLE, Material.IRON_NUGGET);
        addShapelessTool("gas_collector", Material.GLASS_BOTTLE, Material.IRON_INGOT, Material.REDSTONE);
        addShapelessTool("heater", Material.FURNACE, Material.BLAZE_POWDER, Material.COPPER_INGOT);
        addShapelessTool("electrolyzer", Material.COPPER_INGOT, Material.REDSTONE, Material.GLASS_BOTTLE);
        addShapelessTool("filter", Material.HOPPER, Material.PAPER, Material.GLASS_BOTTLE);
        addShapelessTool("distiller", Material.BREWING_STAND, Material.GLASS_BOTTLE, Material.COPPER_INGOT);
        addShapelessTool("scale", Material.IRON_INGOT, Material.REDSTONE, Material.STONE_PRESSURE_PLATE);
        addShapelessTool("pressure_chamber", Material.IRON_BLOCK, Material.GLASS, Material.REDSTONE_BLOCK);
    }

    private void addShapelessTool(String id, Material... ingredients) {
        NamespacedKey key = toolRecipeKeys.get(id);
        if (key == null) return;
        ItemStack result = createToolItem(id);
        if (result == null) return;
        ShapelessRecipe r = new ShapelessRecipe(key, result);
        for (Material material : ingredients) r.addIngredient(material);
        Bukkit.addRecipe(r);
    }

    private int migratePlayerInventory(Player p) {
        int count = migrateInventory(p.getInventory());
        count += migrateInventory(p.getEnderChest());
        return count;
    }

    private int migrateInventory(Inventory inv) {
        int changed = 0;
        ItemStack[] contents = inv.getContents();
        for (int i = 0; i < contents.length; i++) {
            ItemStack item = contents[i];
            if (isAir(item)) continue;
            String chem = getChemId(item);
            if (chem != null && all.containsKey(chem)) {
                ItemStack fresh = createChemItem(all.get(chem), item.getAmount());
                inv.setItem(i, fresh);
                changed++;
                continue;
            }
            String tool = getToolId(item);
            if (tool != null) {
                ItemStack fresh = createToolItem(tool);
                if (fresh != null) {
                    fresh.setAmount(item.getAmount());
                    inv.setItem(i, fresh);
                    changed++;
                }
            }
        }
        return changed;
    }

    private void returnItems(Player p, Inventory inv, int[] slots) {
        for (int slot : slots) {
            ItemStack stack = inv.getItem(slot);
            if (isAir(stack)) continue;
            inv.setItem(slot, null);
            giveVanilla(p, stack);
        }
    }

    private void giveChem(Player p, String id, int amount) {
        ChemDef def = all.get(id);
        if (def == null) {
            p.sendMessage(P + "§c알 수 없는 화학 ID: §f" + id);
            return;
        }
        int left = Math.max(1, amount);
        while (left > 0) {
            int n = Math.min(64, left);
            giveVanilla(p, createChemItem(def, n));
            left -= n;
        }
        recordDiscovery(p.getUniqueId(), def.id);
    }

    private void giveVanilla(Player p, ItemStack stack) {
        PlayerInventory inventory = p.getInventory();
        Map<Integer, ItemStack> leftovers = inventory.addItem(stack);
        if (!leftovers.isEmpty()) {
            World world = p.getWorld();
            Location loc = p.getLocation();
            for (ItemStack left : leftovers.values()) world.dropItemNaturally(loc, left);
            p.sendMessage(P + "§e인벤토리가 가득 차 일부 아이템을 발밑에 떨어뜨렸습니다.");
        }
    }

    private File discoveryFile(UUID uuid) {
        File dir = new File(getDataFolder(), "discoveries");
        if (!dir.exists()) dir.mkdirs();
        return new File(dir, uuid + ".txt");
    }

    private Set<String> loadDiscovered(UUID uuid) {
        LinkedHashSet<String> out = new LinkedHashSet<>();
        File f = discoveryFile(uuid);
        if (!f.exists()) return out;
        try {
            for (String line : Files.readAllLines(f.toPath(), StandardCharsets.UTF_8)) {
                String id = line.trim();
                if (!id.isEmpty()) out.add(id);
            }
        } catch (IOException ex) {
            getLogger().warning("Could not read discovery file for " + uuid + ": " + ex.getMessage());
        }
        return out;
    }

    private void recordDiscovery(UUID uuid, String id) {
        Set<String> ids = loadDiscovered(uuid);
        if (!ids.add(id)) return;
        File f = discoveryFile(uuid);
        try {
            Files.write(f.toPath(), ids, StandardCharsets.UTF_8);
        } catch (IOException ex) {
            getLogger().warning("Could not save discovery file for " + uuid + ": " + ex.getMessage());
        }
    }

    private static Set<Integer> intSet(int[] ints) {
        HashSet<Integer> set = new HashSet<>();
        for (int i : ints) set.add(i);
        return Collections.unmodifiableSet(set);
    }

    private enum PageKind { ELEMENTS, SPECIES }
    private enum ChemType { ELEMENT, SPECIES }

    private enum MatterState {
        ELEMENT("원소 샘플"), GAS("기체"), LIQUID("액체"), AQUEOUS("수용액"), SOLID("고체"), PRECIPITATE("앙금");
        final String display;
        MatterState(String display) { this.display = display; }
        static MatterState from(String s) {
            if (s == null) return SOLID;
            try { return valueOf(s.trim().toUpperCase(Locale.ROOT)); }
            catch (IllegalArgumentException ex) { return SOLID; }
        }
    }

    private enum Temperature {
        ROOM("§b상온"), HEATED("§c가열");
        final String display;
        Temperature(String display) { this.display = display; }
        static Temperature from(String s) {
            if (s == null) return ROOM;
            try { return valueOf(s.trim().toUpperCase(Locale.ROOT)); }
            catch (IllegalArgumentException ex) { return ROOM; }
        }
    }

    private enum Pressure {
        NORMAL("§f일반 압력"), HIGH("§5고압");
        final String display;
        Pressure(String display) { this.display = display; }
        static Pressure from(String s) {
            if (s == null || s.isBlank()) return NORMAL;
            try { return valueOf(s.trim().toUpperCase(Locale.ROOT)); }
            catch (IllegalArgumentException ex) { return NORMAL; }
        }
    }

    private enum LabType {
        GENERAL("범용 반응실", "§c범용 반응실", "BREWING_STAND", "§c", "기본 합성·분해와 일반 반응"),
        SOLUTION("용액 제조실", "§9용액 제조실", "GLASS_BOTTLE", "§9", "고체 염의 용해·결정 회수"),
        GAS("기체 실험실", "§b기체 실험실", "GHAST_TEAR", "§b", "기체 생성·연소·기체 간 반응"),
        PRECIPITATION("앙금 실험실", "§e앙금 실험실", "WHITE_CONCRETE_POWDER", "§e", "수용액을 섞어 앙금 생성"),
        ACID_BASE("산·염기 실험실", "§d산·염기 실험실", "FERMENTED_SPIDER_EYE", "§d", "산·염기·중화·탄산염 반응"),
        REDOX("산화·환원 실험실", "§6산화·환원 실험실", "IRON_INGOT", "§6", "산화물 생성·환원·금속 치환"),
        ELECTROLYSIS("전기분해실", "§3전기분해실", "REDSTONE_TORCH", "§3", "물·염류의 전기분해 모델"),
        THERMAL("열분해실", "§c열분해실", "BLAZE_POWDER", "§c", "가열에 의한 분해·결정 회수");

        final String display;
        final String title;
        final String icon;
        final String color;
        final String description;
        LabType(String display, String title, String icon, String color, String description) {
            this.display = display; this.title = title; this.icon = icon; this.color = color; this.description = description;
        }
        static LabType from(String s) {
            if (s == null) return GENERAL;
            try { return valueOf(s.trim().toUpperCase(Locale.ROOT)); }
            catch (IllegalArgumentException ex) { return GENERAL; }
        }
    }

    private static final class ChemDef {
        final String id;
        final String formula;
        final String korean;
        final String english;
        final String material;
        final String description;
        final ChemType type;
        final int atomicNumber;
        final MatterState state;
        final String group;
        final Double ph;
        final String precipitateColor;

        ChemDef(String id, String formula, String korean, String english, String material, String description,
                ChemType type, int atomicNumber, MatterState state, String group, Double ph, String precipitateColor) {
            this.id = id; this.formula = formula; this.korean = korean; this.english = english; this.material = material;
            this.description = description; this.type = type; this.atomicNumber = atomicNumber; this.state = state;
            this.group = group; this.ph = ph; this.precipitateColor = precipitateColor;
        }
    }

    private static final class Reaction {
        final String id;
        final String name;
        final LabType lab;
        final Temperature temperature;
        final Pressure pressure;
        final String catalyst;
        final LinkedHashMap<String, Integer> inputs;
        final LinkedHashMap<String, Integer> outputs;
        final String note;

        Reaction(String id, String name, LabType lab, Temperature temperature, Pressure pressure, String catalyst,
                 LinkedHashMap<String, Integer> inputs, LinkedHashMap<String, Integer> outputs, String note) {
            this.id = id; this.name = name; this.lab = lab; this.temperature = temperature; this.pressure = pressure;
            this.catalyst = catalyst == null ? "" : catalyst;
            this.inputs = inputs; this.outputs = outputs; this.note = note == null ? "" : note;
        }

        int requiredTotal() { int n = 0; for (int amount : inputs.values()) n += amount; return n; }
    }

    private static final class ToolDef {
        final String id, name, material, color;
        final List<String> lore;
        ToolDef(String id, String name, String material, String color, List<String> lore) {
            this.id=id; this.name=name; this.material=material; this.color=color; this.lore=lore;
        }
        static final LinkedHashMap<String, ToolDef> MAP = new LinkedHashMap<>();
        static final List<String> ALL_IDS;
        static final List<String> CRAFTABLE_IDS;
        static {
            add("lab_kit","화학 실험 키트","BREWING_STAND","§3", List.of("§7우클릭: §f휴대용 화학 연구실 열기"));
            add("ph_paper","pH 시험지","PAPER","§d", List.of("§7우클릭: §f화학 분석실 열기", "§7산·염기 실험실 해금 장비"));
            add("lab_bench","설치형 화학 실험대","BREWING_STAND","§3", List.of("§7블록에 설치 후 우클릭: §f연구실 열기", "§7파괴 시 장비 아이템으로 회수"));
            add("beaker","비커","GLASS_BOTTLE","§9", List.of("§7범용/용액 실험실 해금 장비"));
            add("test_tube","시험관 세트","GLASS_BOTTLE","§e", List.of("§7앙금 실험실 해금 장비"));
            add("gas_collector","기체 포집기","GHAST_TEAR","§b", List.of("§7기체 실험실 해금 장비"));
            add("heater","화학 가열기","BLAZE_POWDER","§c", List.of("§7열분해 실험실 해금 장비"));
            add("electrolyzer","전기분해 장치","REDSTONE_TORCH","§3", List.of("§7전기분해 실험실 해금 장비"));
            add("filter","여과 장치","HOPPER","§6", List.of("§7야생 물질 추출기 해금 장비"));
            add("distiller","용액 조제·증류 장치","BREWING_STAND","§d", List.of("§7용액 실험실 해금 장비", "§7용액 조제·분리 콘텐츠용 장비"));
            add("scale","전자저울","LIGHT_WEIGHTED_PRESSURE_PLATE","§e", List.of("§7산화·환원 실험실 해금 장비"));
            add("pressure_chamber","압력 챔버","HEAVY_CORE","§5", List.of("§7고압 반응 조건용 연구 장비"));
            ALL_IDS = List.copyOf(MAP.keySet());
            CRAFTABLE_IDS = List.of("lab_bench","beaker","test_tube","gas_collector","heater","electrolyzer","filter","distiller","scale","pressure_chamber");
        }
        static void add(String id,String name,String mat,String color,List<String> lore){ MAP.put(id,new ToolDef(id,name,mat,color,lore)); }
        static ToolDef byId(String id){ return id==null?null:MAP.get(id.toLowerCase(Locale.ROOT)); }
        static String nameOf(String id){ ToolDef d=byId(id); return d==null?id:d.name; }
    }
}
