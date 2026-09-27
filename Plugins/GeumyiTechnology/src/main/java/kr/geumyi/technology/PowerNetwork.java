package kr.geumyi.technology;

import org.bukkit.Bukkit;
import org.bukkit.World;

import java.util.*;

public final class PowerNetwork {
    private static final int[][] DIRS = {
            {1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}
    };

    private final GeumyiTechnology plugin;
    private final MachineStore store;

    public PowerNetwork(GeumyiTechnology plugin, MachineStore store) {
        this.plugin = plugin;
        this.store = store;
    }

    public Set<MachineData> component(BlockKey start) {
        MachineData root = store.get(start);
        if (root == null || !root.type.powerNode) return Collections.emptySet();
        LinkedHashSet<MachineData> out = new LinkedHashSet<>();
        ArrayDeque<BlockKey> q = new ArrayDeque<>();
        HashSet<BlockKey> visited = new HashSet<>();
        q.add(start);
        visited.add(start);
        while (!q.isEmpty()) {
            BlockKey key = q.removeFirst();
            MachineData here = store.get(key);
            if (here == null || !here.type.powerNode) continue;
            out.add(here);
            for (int[] d : DIRS) {
                BlockKey n = key.offset(d[0], d[1], d[2]);
                if (visited.add(n)) {
                    MachineData next = store.get(n);
                    if (next != null && next.type.powerNode) q.addLast(n);
                }
            }
        }
        return out;
    }

    public long storedEnergy(BlockKey start) {
        long total = 0L;
        for (MachineData d : component(start)) if (d.type.capacity > 0) total += d.energy;
        return total;
    }

    public long capacity(BlockKey start) {
        long total = 0L;
        for (MachineData d : component(start)) if (d.type.capacity > 0) total += d.type.capacity;
        return total;
    }

    public int nodeCount(BlockKey start) {
        return component(start).size();
    }

    public boolean consume(BlockKey start, long amount) {
        if (amount <= 0) return true;
        Set<MachineData> component = component(start);
        long total = 0L;
        for (MachineData d : component) if (d.type.capacity > 0) total += d.energy;
        if (total < amount) return false;

        long left = amount;
        // generators first, then batteries: generation buffers are consumed before reserve storage.
        ArrayList<MachineData> ordered = new ArrayList<>(component);
        ordered.sort(Comparator.comparingInt(d -> d.type.generator ? 0 : (d.type.battery ? 1 : 2)));
        for (MachineData d : ordered) {
            if (left <= 0) break;
            if (d.type.capacity <= 0 || d.energy <= 0) continue;
            long take = Math.min(left, d.energy);
            d.energy -= take;
            left -= take;
        }
        return left == 0;
    }

    public void tickSecond() {
        int coalOut = Math.max(1, plugin.getConfig().getInt("power.coal-output-per-second", 40));
        int solarOut = Math.max(1, plugin.getConfig().getInt("power.solar-output-per-second", 12));

        for (MachineData d : store.all()) {
            if (d.type == MachineType.COAL_GENERATOR) {
                if (d.fuelSeconds > 0 && d.energy < d.type.capacity) {
                    d.fuelSeconds--;
                    d.energy = Math.min(d.type.capacity, d.energy + coalOut);
                }
            } else if (d.type == MachineType.SOLAR_PANEL) {
                if (solarActive(d)) {
                    int out = solarOut;
                    World w = worldOf(d.key);
                    if (w != null && w.hasStorm()) out = Math.max(1, out / 3);
                    d.energy = Math.min(d.type.capacity, d.energy + out);
                }
            }
        }

        // Balance each network once. Stored energy fills batteries first, then generator buffers.
        HashSet<BlockKey> visited = new HashSet<>();
        for (MachineData seed : store.all()) {
            if (!seed.type.powerNode || visited.contains(seed.key)) continue;
            Set<MachineData> component = component(seed.key);
            for (MachineData d : component) visited.add(d.key);
            rebalance(component);
        }
    }

    private void rebalance(Set<MachineData> component) {
        long total = 0L;
        for (MachineData d : component) if (d.type.capacity > 0) total += d.energy;
        if (total <= 0) return;

        ArrayList<MachineData> storages = new ArrayList<>();
        for (MachineData d : component) if (d.type.capacity > 0) storages.add(d);
        storages.sort(Comparator.comparingInt(d -> d.type.battery ? 0 : 1));
        for (MachineData d : storages) d.energy = 0;
        for (MachineData d : storages) {
            if (total <= 0) break;
            long put = Math.min(total, d.type.capacity);
            d.energy = put;
            total -= put;
        }
    }

    public boolean solarActive(MachineData d) {
        if (d.type != MachineType.SOLAR_PANEL) return false;
        World w = worldOf(d.key);
        if (w == null) return false;
        long time = w.getTime();
        if (time >= 12_300L && time <= 23_850L) return false;
        int topY = w.getHighestBlockYAt(d.key.x(), d.key.z());
        return topY <= d.key.y();
    }

    private World worldOf(BlockKey key) {
        World w = Bukkit.getWorld(key.worldId());
        if (w == null) w = Bukkit.getWorld(key.worldName());
        return w;
    }
}
