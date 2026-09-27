package kr.geumyi.technology;

import org.bukkit.Material;

import java.util.List;

public record RecipeDef(
        String id,
        String name,
        Category category,
        OutputKind outputKind,
        String outputId,
        int outputAmount,
        List<IngredientSpec> ingredients,
        String note
) {
    public enum Category { COMPONENTS, POWER, INDUSTRY, CHEMISTRY }
    public enum OutputKind { TECH, VANILLA, CHEM }

    public static RecipeDef tech(String id, String name, Category category, TechItem out, int amount,
                                 List<IngredientSpec> ingredients, String note) {
        return new RecipeDef(id, name, category, OutputKind.TECH, out.id, amount, ingredients, note);
    }

    public static RecipeDef vanilla(String id, String name, Category category, Material out, int amount,
                                    List<IngredientSpec> ingredients, String note) {
        return new RecipeDef(id, name, category, OutputKind.VANILLA, out.name(), amount, ingredients, note);
    }

    public static RecipeDef chem(String id, String name, Category category, String outId, int amount,
                                 List<IngredientSpec> ingredients, String note) {
        return new RecipeDef(id, name, category, OutputKind.CHEM, outId, amount, ingredients, note);
    }
}
