package kr.geumyi.technology;

import org.bukkit.Material;

public record IngredientSpec(Kind kind, String id, int amount) {
    public enum Kind { VANILLA, TECH, CHEM }

    public static IngredientSpec vanilla(Material material, int amount) {
        return new IngredientSpec(Kind.VANILLA, material.name(), amount);
    }

    public static IngredientSpec tech(TechItem item, int amount) {
        return new IngredientSpec(Kind.TECH, item.id, amount);
    }

    public static IngredientSpec chem(String chemId, int amount) {
        return new IngredientSpec(Kind.CHEM, chemId, amount);
    }
}
