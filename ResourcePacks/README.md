# Current resource pack source

Recovered from the mc-2026.09.26-v3 FINAL bundle, expanded with image/sound bytes preserved.

- Wild/Java: 26.3 BACAP + ChemTech pack.
- Wild/Bedrock-BACAP and Wild/Bedrock-ChemTech: companion Bedrock packs.
- Wild/Geumyi_Wild_Geyser_CustomItem_Mappings.json: custom item mapping.
- Playground/Java: 26.3 Java pack.
- Playground/Bedrock: bundled 26.50 Bedrock pack.

JSON, lang, PNG, OGG and pack metadata are editable source assets and belong in Git. To package, archive the *contents* of each pack directory so pack.mcmeta (Java) or manifest.json (Bedrock) is at the archive root. Output ZIP/MCPACK files stay in Releases. Cross-platform copies required by each pack are retained; Git deduplicates identical file objects.

Language JSON normalization: 31 BACAP language files contained hash comments; comments and author credits are preserved in ResourcePacks/Wild/LANGUAGE-COMMENTS.md. Raw string control characters were escaped and one misplaced quote pair in zh_tw was corrected. Translation text was not rewritten. All 488 JSON/pack metadata files then parsed successfully.
