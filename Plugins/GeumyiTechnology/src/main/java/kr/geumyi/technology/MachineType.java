package kr.geumyi.technology;

import java.util.Arrays;

public enum MachineType {
    TECH_WORKBENCH(TechItem.TECH_WORKBENCH, 0, false, false, false),
    POWER_CABLE(TechItem.POWER_CABLE, 0, true, false, false),
    COAL_GENERATOR(TechItem.COAL_GENERATOR, 10_000, true, true, false),
    SOLAR_PANEL(TechItem.SOLAR_PANEL, 5_000, true, true, false),
    BATTERY_BOX(TechItem.BATTERY_BOX, 50_000, true, false, true),
    BATTERY_BOX_MK2(TechItem.BATTERY_BOX_MK2, 200_000, true, false, true),
    CRUSHER(TechItem.CRUSHER, 0, true, false, false),
    ELECTRIC_FURNACE(TechItem.ELECTRIC_FURNACE, 0, true, false, false),
    ELECTROLYZER(TechItem.ELECTROLYZER, 0, true, false, false);

    public final TechItem item;
    public final long capacity;
    public final boolean powerNode;
    public final boolean generator;
    public final boolean battery;

    MachineType(TechItem item, long capacity, boolean powerNode, boolean generator, boolean battery) {
        this.item = item;
        this.capacity = capacity;
        this.powerNode = powerNode;
        this.generator = generator;
        this.battery = battery;
    }

    public static MachineType byItem(TechItem item) {
        if (item == null) return null;
        return Arrays.stream(values()).filter(v -> v.item == item).findFirst().orElse(null);
    }
}
