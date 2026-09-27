package kr.geumyi.technology;

import org.bukkit.Material;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

import static kr.geumyi.technology.IngredientSpec.chem;
import static kr.geumyi.technology.IngredientSpec.tech;
import static kr.geumyi.technology.IngredientSpec.vanilla;

public final class TechnologyRecipes {
    private TechnologyRecipes() {}

    public static List<RecipeDef> workbenchRecipes() {
        ArrayList<RecipeDef> r = new ArrayList<>();

        r.add(RecipeDef.tech("wire_from_copper", "구리 전선 제작", RecipeDef.Category.COMPONENTS,
                TechItem.COPPER_WIRE, 4,
                List.of(vanilla(Material.COPPER_INGOT, 1)),
                "기초 배선. 모든 전력 장치의 출발점입니다."));
        r.add(RecipeDef.tech("machine_frame", "기계 프레임 제작", RecipeDef.Category.COMPONENTS,
                TechItem.MACHINE_FRAME, 1,
                List.of(vanilla(Material.IRON_INGOT, 4), vanilla(Material.COPPER_INGOT, 2), vanilla(Material.REDSTONE, 2)),
                "산업 기계의 구조체입니다."));
        r.add(RecipeDef.tech("basic_circuit", "기초 회로 제작", RecipeDef.Category.COMPONENTS,
                TechItem.BASIC_CIRCUIT, 1,
                List.of(tech(TechItem.COPPER_WIRE, 2), vanilla(Material.REDSTONE, 3), vanilla(Material.QUARTZ, 1)),
                "제어 회로와 센서에 사용합니다."));
        r.add(RecipeDef.tech("electric_motor", "전동 모터 제작", RecipeDef.Category.COMPONENTS,
                TechItem.ELECTRIC_MOTOR, 1,
                List.of(tech(TechItem.COPPER_WIRE, 4), vanilla(Material.IRON_INGOT, 2), vanilla(Material.REDSTONE, 1)),
                "분쇄기 등 회전 기계의 핵심 부품입니다."));
        r.add(RecipeDef.tech("heating_coil", "가열 코일 제작", RecipeDef.Category.COMPONENTS,
                TechItem.HEATING_COIL, 1,
                List.of(tech(TechItem.COPPER_WIRE, 4), vanilla(Material.IRON_NUGGET, 4)),
                "전기로의 발열 부품입니다."));
        r.add(RecipeDef.tech("battery_cell", "기초 배터리 셀 제작", RecipeDef.Category.COMPONENTS,
                TechItem.BATTERY_CELL, 1,
                List.of(tech(TechItem.COPPER_WIRE, 2), vanilla(Material.REDSTONE, 3), vanilla(Material.IRON_INGOT, 1)),
                "배터리 박스 MK.I의 저장 셀입니다."));

        r.add(RecipeDef.tech("power_cable", "전력 케이블 제작", RecipeDef.Category.POWER,
                TechItem.POWER_CABLE, 6,
                List.of(tech(TechItem.COPPER_WIRE, 3), vanilla(Material.BLACK_WOOL, 1)),
                "서로 맞닿은 발전기·배터리·기계를 연결합니다."));
        r.add(RecipeDef.tech("coal_generator", "석탄 발전기 조립", RecipeDef.Category.POWER,
                TechItem.COAL_GENERATOR, 1,
                List.of(tech(TechItem.MACHINE_FRAME, 1), tech(TechItem.ELECTRIC_MOTOR, 1), tech(TechItem.BASIC_CIRCUIT, 1), vanilla(Material.FURNACE, 1)),
                "석탄/목탄/석탄 블록으로 전력을 생산합니다."));
        r.add(RecipeDef.tech("battery_box", "배터리 박스 MK.I 조립", RecipeDef.Category.POWER,
                TechItem.BATTERY_BOX, 1,
                List.of(tech(TechItem.MACHINE_FRAME, 1), tech(TechItem.BATTERY_CELL, 4), tech(TechItem.BASIC_CIRCUIT, 1)),
                "50,000 GT를 저장합니다."));
        r.add(RecipeDef.tech("solar_panel", "태양광 발전기 조립", RecipeDef.Category.POWER,
                TechItem.SOLAR_PANEL, 1,
                List.of(tech(TechItem.MACHINE_FRAME, 1), tech(TechItem.SILICON_WAFER, 4), tech(TechItem.BASIC_CIRCUIT, 2), vanilla(Material.GLASS, 4)),
                "낮에 하늘이 보이면 자동 발전합니다."));

        r.add(RecipeDef.tech("crusher", "전동 분쇄기 조립", RecipeDef.Category.INDUSTRY,
                TechItem.CRUSHER, 1,
                List.of(tech(TechItem.MACHINE_FRAME, 1), tech(TechItem.ELECTRIC_MOTOR, 2), tech(TechItem.BASIC_CIRCUIT, 1), vanilla(Material.IRON_INGOT, 4)),
                "광석 2개를 분말 3개로 가공하는 기본 산업 기계입니다."));
        r.add(RecipeDef.tech("electric_furnace", "전기로 조립", RecipeDef.Category.INDUSTRY,
                TechItem.ELECTRIC_FURNACE, 1,
                List.of(tech(TechItem.MACHINE_FRAME, 1), tech(TechItem.HEATING_COIL, 2), tech(TechItem.BASIC_CIRCUIT, 1), vanilla(Material.FURNACE, 1)),
                "전력을 사용해 분말과 실리콘을 정제합니다."));
        r.add(RecipeDef.tech("electrolyzer", "산업용 전기분해기 조립", RecipeDef.Category.INDUSTRY,
                TechItem.ELECTROLYZER, 1,
                List.of(tech(TechItem.MACHINE_FRAME, 1), tech(TechItem.BASIC_CIRCUIT, 2), tech(TechItem.COPPER_WIRE, 4), vanilla(Material.GLASS, 2)),
                "GeumyiChemistry 샘플을 전력으로 전기분해합니다."));

        r.add(RecipeDef.tech("chem_copper_wire", "화학 Cu → 구리 전선", RecipeDef.Category.CHEMISTRY,
                TechItem.COPPER_WIRE, 4,
                List.of(chem("Cu", 1)),
                "GeumyiChemistry의 Cu 샘플을 기술 재료로 직접 사용합니다."));
        r.add(RecipeDef.tech("chem_silicon_wafer", "화학 Si → 실리콘 웨이퍼", RecipeDef.Category.CHEMISTRY,
                TechItem.SILICON_WAFER, 2,
                List.of(chem("Si", 2), vanilla(Material.REDSTONE, 1)),
                "화학에서 정제한 Si를 반도체 웨이퍼로 가공합니다."));
        r.add(RecipeDef.tech("high_density_cell", "고밀도 배터리 셀", RecipeDef.Category.CHEMISTRY,
                TechItem.HIGH_DENSITY_CELL, 1,
                List.of(chem("Li", 2), chem("C", 1), tech(TechItem.COPPER_WIRE, 2), vanilla(Material.REDSTONE, 2)),
                "Li/C 화학 샘플을 활용한 고급 배터리 셀입니다."));
        r.add(RecipeDef.tech("battery_box_mk2", "배터리 박스 MK.II 조립", RecipeDef.Category.CHEMISTRY,
                TechItem.BATTERY_BOX_MK2, 1,
                List.of(tech(TechItem.MACHINE_FRAME, 1), tech(TechItem.HIGH_DENSITY_CELL, 4), tech(TechItem.BASIC_CIRCUIT, 2), vanilla(Material.ENDER_PEARL, 2)),
                "200,000 GT를 저장하는 Chemistry 연동 고급 배터리입니다."));

        return Collections.unmodifiableList(r);
    }

    public static List<MachineProcess> processes() {
        ArrayList<MachineProcess> p = new ArrayList<>();
        p.add(new MachineProcess("crush_cobble", "조약돌 → 자갈", MachineType.CRUSHER, 80,
                List.of(vanilla(Material.COBBLESTONE, 1)), RecipeDef.OutputKind.VANILLA, Material.GRAVEL.name(), 1,
                "기본 파쇄"));
        p.add(new MachineProcess("crush_gravel", "자갈 → 모래", MachineType.CRUSHER, 80,
                List.of(vanilla(Material.GRAVEL, 1)), RecipeDef.OutputKind.VANILLA, Material.SAND.name(), 1,
                "기본 파쇄"));
        p.add(new MachineProcess("crush_iron", "철 원석 2 → 철 분말 3", MachineType.CRUSHER, 300,
                List.of(vanilla(Material.RAW_IRON, 2)), RecipeDef.OutputKind.TECH, TechItem.IRON_DUST.id, 3,
                "전력 기반 광물 수율 향상"));
        p.add(new MachineProcess("crush_copper", "구리 원석 2 → 구리 분말 3", MachineType.CRUSHER, 300,
                List.of(vanilla(Material.RAW_COPPER, 2)), RecipeDef.OutputKind.TECH, TechItem.COPPER_DUST.id, 3,
                "전력 기반 광물 수율 향상"));
        p.add(new MachineProcess("crush_gold", "금 원석 2 → 금 분말 3", MachineType.CRUSHER, 350,
                List.of(vanilla(Material.RAW_GOLD, 2)), RecipeDef.OutputKind.TECH, TechItem.GOLD_DUST.id, 3,
                "전력 기반 광물 수율 향상"));
        p.add(new MachineProcess("crush_quartz", "석영 2 → 실리콘 분말", MachineType.CRUSHER, 250,
                List.of(vanilla(Material.QUARTZ, 2)), RecipeDef.OutputKind.TECH, TechItem.SILICON_DUST.id, 1,
                "게임플레이용 반도체 원료 정제 모델"));

        p.add(new MachineProcess("smelt_iron_dust", "철 분말 → 철 주괴", MachineType.ELECTRIC_FURNACE, 120,
                List.of(tech(TechItem.IRON_DUST, 1)), RecipeDef.OutputKind.VANILLA, Material.IRON_INGOT.name(), 1,
                "전기로 정제"));
        p.add(new MachineProcess("smelt_copper_dust", "구리 분말 → 구리 주괴", MachineType.ELECTRIC_FURNACE, 120,
                List.of(tech(TechItem.COPPER_DUST, 1)), RecipeDef.OutputKind.VANILLA, Material.COPPER_INGOT.name(), 1,
                "전기로 정제"));
        p.add(new MachineProcess("smelt_gold_dust", "금 분말 → 금 주괴", MachineType.ELECTRIC_FURNACE, 150,
                List.of(tech(TechItem.GOLD_DUST, 1)), RecipeDef.OutputKind.VANILLA, Material.GOLD_INGOT.name(), 1,
                "전기로 정제"));
        p.add(new MachineProcess("refine_silicon", "실리콘 분말 → 실리콘 웨이퍼", MachineType.ELECTRIC_FURNACE, 400,
                List.of(tech(TechItem.SILICON_DUST, 1), vanilla(Material.REDSTONE, 1)), RecipeDef.OutputKind.TECH, TechItem.SILICON_WAFER.id, 1,
                "게임플레이용 반도체 정제 공정"));

        p.add(new MachineProcess("electrolyze_water", "2H₂O → 2H₂ + O₂", MachineType.ELECTROLYZER, 800,
                List.of(chem("H2O", 2)), RecipeDef.OutputKind.CHEM, "H2+2,O2+1", 1,
                "GeumyiChemistry 필요 · 물 전기분해"));
        p.add(new MachineProcess("electrolyze_salt", "2NaCl → 2Na + Cl₂", MachineType.ELECTROLYZER, 1_200,
                List.of(chem("NaCl", 2)), RecipeDef.OutputKind.CHEM, "Na+2,Cl2+1", 1,
                "GeumyiChemistry 필요 · 게임플레이 전기분해 모델"));
        p.add(new MachineProcess("electrolyze_alumina", "2Al₂O₃ → 4Al + 3O₂", MachineType.ELECTROLYZER, 2_000,
                List.of(chem("Al2O3", 2)), RecipeDef.OutputKind.CHEM, "Al+4,O2+3", 1,
                "GeumyiChemistry 필요 · 고에너지 전기분해"));

        return Collections.unmodifiableList(p);
    }
}
