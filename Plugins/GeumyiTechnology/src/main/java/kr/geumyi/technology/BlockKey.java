package kr.geumyi.technology;

import org.bukkit.Location;
import org.bukkit.World;
import org.bukkit.block.Block;

import java.util.UUID;
import java.util.Objects;

public record BlockKey(UUID worldId, String worldName, int x, int y, int z) {
    public static BlockKey of(Block block) {
        World w = block.getWorld();
        return new BlockKey(w.getUID(), w.getName(), block.getX(), block.getY(), block.getZ());
    }

    public BlockKey offset(int dx, int dy, int dz) {
        return new BlockKey(worldId, worldName, x + dx, y + dy, z + dz);
    }

    public Location toLocation(World world) {
        return new Location(world, x, y, z);
    }

    public String compact() {
        return worldName + " " + x + "," + y + "," + z;
    }

    @Override
    public boolean equals(Object obj) {
        if (this == obj) return true;
        if (!(obj instanceof BlockKey other)) return false;
        return x == other.x && y == other.y && z == other.z && worldId.equals(other.worldId);
    }

    @Override
    public int hashCode() {
        return Objects.hash(worldId, x, y, z);
    }
}
