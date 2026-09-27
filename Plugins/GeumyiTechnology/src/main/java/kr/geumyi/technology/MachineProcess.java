package kr.geumyi.technology;

import java.util.List;

public record MachineProcess(
        String id,
        String name,
        MachineType machine,
        long energyCost,
        List<IngredientSpec> inputs,
        RecipeDef.OutputKind outputKind,
        String outputId,
        int outputAmount,
        String note
) {}
