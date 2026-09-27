package kr.geumyi.technology;

public final class MachineData {
    public final BlockKey key;
    public final MachineType type;
    public long energy;
    public int fuelSeconds;

    public MachineData(BlockKey key, MachineType type) {
        this(key, type, 0L, 0);
    }

    public MachineData(BlockKey key, MachineType type, long energy, int fuelSeconds) {
        this.key = key;
        this.type = type;
        this.energy = Math.max(0L, Math.min(type.capacity, energy));
        this.fuelSeconds = Math.max(0, fuelSeconds);
    }
}
