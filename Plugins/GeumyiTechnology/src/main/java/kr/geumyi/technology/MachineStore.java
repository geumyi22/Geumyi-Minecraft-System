package kr.geumyi.technology;

import org.bukkit.Bukkit;
import org.bukkit.Material;
import org.bukkit.World;
import org.bukkit.block.Block;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.*;
import java.util.logging.Logger;

public final class MachineStore {
    private final GeumyiTechnology plugin;
    private final Logger logger;
    private final LinkedHashMap<BlockKey, MachineData> machines = new LinkedHashMap<>();
    private final File file;

    public MachineStore(GeumyiTechnology plugin) {
        this.plugin = plugin;
        this.logger = plugin.getLogger();
        this.file = new File(plugin.getDataFolder(), "machines.tsv");
    }

    public Collection<MachineData> all() {
        return Collections.unmodifiableCollection(machines.values());
    }

    public MachineData get(BlockKey key) {
        return machines.get(key);
    }

    public MachineData get(Block block) {
        return machines.get(BlockKey.of(block));
    }

    public boolean contains(Block block) {
        return machines.containsKey(BlockKey.of(block));
    }

    public void put(MachineData data) {
        machines.put(data.key, data);
    }

    public MachineData remove(BlockKey key) {
        return machines.remove(key);
    }

    public MachineData remove(Block block) {
        return machines.remove(BlockKey.of(block));
    }

    public int size() {
        return machines.size();
    }

    public void load() {
        machines.clear();
        if (!file.isFile()) return;
        int loaded = 0;
        int skipped = 0;
        try (BufferedReader reader = Files.newBufferedReader(file.toPath(), StandardCharsets.UTF_8)) {
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.isBlank() || line.startsWith("#")) continue;
                String[] p = line.split("\\t", -1);
                if (p.length < 8) { skipped++; continue; }
                try {
                    UUID worldId = UUID.fromString(p[0]);
                    String worldName = p[1];
                    int x = Integer.parseInt(p[2]);
                    int y = Integer.parseInt(p[3]);
                    int z = Integer.parseInt(p[4]);
                    MachineType type = MachineType.valueOf(p[5]);
                    long energy = Long.parseLong(p[6]);
                    int fuel = Integer.parseInt(p[7]);
                    BlockKey key = new BlockKey(worldId, worldName, x, y, z);
                    MachineData data = new MachineData(key, type, energy, fuel);
                    machines.put(key, data);
                    loaded++;
                } catch (Exception ex) {
                    skipped++;
                }
            }
        } catch (IOException ex) {
            logger.warning("machines.tsv 로드 실패: " + ex.getMessage());
        }
        if (skipped > 0) logger.warning("기계 데이터 " + skipped + "개를 건너뛰었습니다.");
        logger.info("기계 데이터 " + loaded + "개 로드됨.");
    }

    public void save() {
        if (!plugin.getDataFolder().exists() && !plugin.getDataFolder().mkdirs()) return;
        File temp = new File(file.getParentFile(), file.getName() + ".tmp");
        try (BufferedWriter writer = Files.newBufferedWriter(temp.toPath(), StandardCharsets.UTF_8)) {
            writer.write("# worldUUID\tworldName\tx\ty\tz\ttype\tenergy\tfuelSeconds\n");
            for (MachineData d : machines.values()) {
                writer.write(d.key.worldId() + "\t" + sanitize(d.key.worldName()) + "\t" + d.key.x() + "\t" + d.key.y() + "\t" + d.key.z()
                        + "\t" + d.type.name() + "\t" + d.energy + "\t" + d.fuelSeconds + "\n");
            }
        } catch (IOException ex) {
            logger.warning("기계 데이터 저장 실패: " + ex.getMessage());
            return;
        }
        try {
            Files.move(temp.toPath(), file.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING, java.nio.file.StandardCopyOption.ATOMIC_MOVE);
        } catch (Exception atomicFail) {
            try {
                Files.move(temp.toPath(), file.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
            } catch (IOException ex) {
                logger.warning("기계 데이터 교체 실패: " + ex.getMessage());
            }
        }
    }

    public int validateLoadedBlocks() {
        int removed = 0;
        Iterator<Map.Entry<BlockKey, MachineData>> it = machines.entrySet().iterator();
        while (it.hasNext()) {
            Map.Entry<BlockKey, MachineData> e = it.next();
            MachineData d = e.getValue();
            World w = Bukkit.getWorld(d.key.worldId());
            if (w == null) w = Bukkit.getWorld(d.key.worldName());
            if (w == null) continue; // world may load later
            Block b = w.getBlockAt(d.key.x(), d.key.y(), d.key.z());
            Material expected = d.type.item.material;
            if (b.getType() != expected) {
                it.remove();
                removed++;
            }
        }
        if (removed > 0) logger.warning("실제 블록과 일치하지 않는 기계 데이터 " + removed + "개를 정리했습니다.");
        return removed;
    }

    private String sanitize(String s) {
        return s == null ? "world" : s.replace('\t', '_').replace('\n', '_').replace('\r', '_');
    }
}
