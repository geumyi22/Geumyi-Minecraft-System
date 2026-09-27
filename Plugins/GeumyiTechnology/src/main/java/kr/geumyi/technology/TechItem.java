package kr.geumyi.technology;

import org.bukkit.Material;

import java.util.Arrays;
import java.util.Locale;

public enum TechItem {
    TECH_MANUAL("tech_manual", "기술 매뉴얼", Material.BOOK, Kind.TOOL, "기술 시스템 메인 메뉴를 엽니다."),
    TECH_WORKBENCH("tech_workbench", "기술 조립 작업대", Material.CRAFTING_TABLE, Kind.BLOCK, "부품과 기계를 제작하는 설치형 작업대입니다."),

    COPPER_WIRE("copper_wire", "구리 전선", Material.STRING, Kind.COMPONENT, "전력·전자 부품의 기초 배선입니다."),
    MACHINE_FRAME("machine_frame", "기계 프레임", Material.HEAVY_WEIGHTED_PRESSURE_PLATE, Kind.COMPONENT, "산업 기계의 기본 구조체입니다."),
    BASIC_CIRCUIT("basic_circuit", "기초 회로", Material.COMPARATOR, Kind.COMPONENT, "센서와 제어에 사용하는 기초 전자 회로입니다."),
    ELECTRIC_MOTOR("electric_motor", "전동 모터", Material.PISTON, Kind.COMPONENT, "전기 에너지를 기계 동력으로 바꾸는 부품입니다."),
    HEATING_COIL("heating_coil", "가열 코일", Material.TRIPWIRE_HOOK, Kind.COMPONENT, "전기 가열 장치에 사용하는 저항 코일입니다."),
    BATTERY_CELL("battery_cell", "기초 배터리 셀", Material.REDSTONE_TORCH, Kind.COMPONENT, "전기를 저장하는 기초 셀입니다."),
    HIGH_DENSITY_CELL("high_density_cell", "고밀도 배터리 셀", Material.ECHO_SHARD, Kind.COMPONENT, "화학 샘플을 활용한 고급 저장 셀입니다."),

    IRON_DUST("iron_dust", "철 분말", Material.GUNPOWDER, Kind.MATERIAL, "분쇄 공정으로 얻는 철 가공 재료입니다."),
    COPPER_DUST("copper_dust", "구리 분말", Material.ORANGE_DYE, Kind.MATERIAL, "분쇄 공정으로 얻는 구리 가공 재료입니다."),
    GOLD_DUST("gold_dust", "금 분말", Material.YELLOW_DYE, Kind.MATERIAL, "분쇄 공정으로 얻는 금 가공 재료입니다."),
    SILICON_DUST("silicon_dust", "실리콘 분말", Material.SUGAR, Kind.MATERIAL, "반도체 제작을 위한 정제 전 단계 재료입니다."),
    SILICON_WAFER("silicon_wafer", "실리콘 웨이퍼", Material.QUARTZ, Kind.MATERIAL, "태양전지와 고급 회로의 기판입니다."),

    POWER_CABLE("power_cable", "전력 케이블", Material.IRON_CHAIN, Kind.BLOCK, "인접한 발전기·배터리·기계를 전력망으로 연결합니다."),
    COAL_GENERATOR("coal_generator", "석탄 발전기", Material.FURNACE, Kind.BLOCK, "석탄 연료를 사용해 전력을 생산합니다."),
    SOLAR_PANEL("solar_panel", "태양광 발전기", Material.DAYLIGHT_DETECTOR, Kind.BLOCK, "낮에 하늘이 보이면 전력을 생산합니다."),
    BATTERY_BOX("battery_box", "배터리 박스 MK.I", Material.BARREL, Kind.BLOCK, "전력망의 에너지를 저장합니다."),
    BATTERY_BOX_MK2("battery_box_mk2", "배터리 박스 MK.II", Material.ENDER_CHEST, Kind.BLOCK, "화학 기술을 활용한 대용량 전력 저장 장치입니다."),
    CRUSHER("crusher", "전동 분쇄기", Material.BLAST_FURNACE, Kind.BLOCK, "광물과 암석을 분쇄해 가공 효율을 높입니다."),
    ELECTRIC_FURNACE("electric_furnace", "전기로", Material.SMOKER, Kind.BLOCK, "전력으로 분말과 재료를 정제합니다."),
    ELECTROLYZER("electrolyzer", "산업용 전기분해기", Material.CRAFTER, Kind.BLOCK, "GeumyiChemistry와 연동해 전기분해 반응을 자동화합니다.");

    public enum Kind { TOOL, COMPONENT, MATERIAL, BLOCK }

    public final String id;
    public final String displayName;
    public final Material material;
    public final Kind kind;
    public final String description;

    TechItem(String id, String displayName, Material material, Kind kind, String description) {
        this.id = id;
        this.displayName = displayName;
        this.material = material;
        this.kind = kind;
        this.description = description;
    }

    public static TechItem byId(String id) {
        if (id == null) return null;
        String needle = id.toLowerCase(Locale.ROOT);
        return Arrays.stream(values()).filter(v -> v.id.equals(needle)).findFirst().orElse(null);
    }
}
