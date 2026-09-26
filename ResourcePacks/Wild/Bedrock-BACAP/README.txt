BACAP Korean - Bedrock Test Pack

Source:
BACAP Language Pack 1.21.zip

Converted entries:
3621

Skipped source lines:
0

What this is:
- An experimental Bedrock resource pack.
- Java BACAP Korean translations were converted to:
  texts/ko_KR.lang
- The original pack icon was reused when available.

Important:
This conversion makes a valid Bedrock-style language resource pack, but BACAP/Geyser must
actually send a translation component whose lookup key matches these BACAP source strings
for the Korean text to appear. Because the original BACAP language pack uses English
phrases such as "Adventuring Time" as translation keys rather than normal dotted
Minecraft localization keys, not every advancement is guaranteed to translate through
Geyser.

How to test:
1. Open the .mcpack on a Bedrock device/client and import it.
2. Enable it under Global Resources, or attach it to the relevant world/resource-pack setup.
3. Set the Bedrock client language to Korean.
4. Join the Java server through Geyser and trigger/open BACAP advancements.
5. Check whether advancement titles/descriptions appear in Korean.

If nothing changes:
The Bedrock pack itself may be loading correctly, but Geyser/BACAP may be sending already
resolved literal text instead of a translatable lookup key. In that case a resource-pack-only
conversion cannot intercept the text; the server/Geyser text path would need a different solution.

FINAL validation fixes:
- Added required en_US fallback language and texts/en_US.lang.
- languages.json now lists en_US and ko_KR.
- Removed/sanitized BACAP legacy rename markers from language values: 54 changed, 2 obsolete empty entries removed.
- Pack version bumped to 1.0.1.

Geyser recommendation:
For Java translatable components, Geyser's locale override mechanism is more reliable than relying on a Bedrock .lang pack.
Use the accompanying ko_kr.json in plugins/Geyser-Spigot/locales/overrides/ and restart Geyser.
