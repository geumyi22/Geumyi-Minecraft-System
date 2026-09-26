package kr.geumyi.discordstatus;

import java.util.Map;

public final class CoreTests {
    private static int tests;
    public static void main(String[] args) {
        eq(GeumyiDiscordStatus.parseDuration("10m"), 600L, "10m");
        eq(GeumyiDiscordStatus.parseDuration("1h"), 3600L, "1h");
        eq(GeumyiDiscordStatus.parseDuration("2d"), 172800L, "2d");
        eq(GeumyiDiscordStatus.parseDuration("bad"), -1L, "bad duration");
        ok(GeumyiDiscordStatus.shouldAnnounce(60), "announce 60");
        ok(!GeumyiDiscordStatus.shouldAnnounce(59), "no announce 59");
        ok(GeumyiDiscordStatus.validMinecraftName("Steve_01"), "valid player name");
        ok(!GeumyiDiscordStatus.validMinecraftName("Steve;stop"), "reject unsafe player name");
        eq(Text.json("a\"b\nc"), "a\\\"b\\nc", "json escape");
        Map<String,String> f = Text.parseForm("action=broadcast&message=hello+world");
        eq(f.get("message"), "hello world", "form decode");
        Map<String,String> j = Text.parseFlatJson("{\"action\":\"maintenance\",\"enabled\":true,\"reason\":\"test\"}");
        eq(j.get("action"), "maintenance", "json action");
        eq(j.get("enabled"), "true", "json bool");
        EventBuffer b = new EventBuffer(32);
        b.add(1L, "a", "A", "m1", "ONLINE");
        b.add(2L, "b", "B", "m2", "ONLINE");
        eq(b.since(1).size(), 1, "event since");
        ok(BridgeReporter.constantTimeEquals("abc", "abc"), "secure eq true");
        ok(!BridgeReporter.constantTimeEquals("abc", "abd"), "secure eq false");

        String health = "{\"schema\":2,\"plugin\":\"GeumyiServerTools\",\"version\":\"1.1.0\",\"time\":1000," +
                "\"grade\":\"DEGRADED\",\"lag_active\":true,\"incident_count\":3," +
                "\"performance\":{\"tps_1m\":17.5,\"tps_5m\":19.2,\"tps_15m\":19.8,\"mspt\":61.2,\"recent_peak_mspt\":81.4,\"recent_min_tps\":16.9,\"memory_percent\":72.5}," +
                "\"counts\":{\"players\":4,\"loaded_chunks\":1200,\"entities\":700}," +
                "\"last_incident\":{\"id\":3,\"severity\":\"CRITICAL\",\"reason\":\"MSPT 61.2ms\",\"recovered_at\":0}}";
        GstDiagnosticsSnapshot g = GstDiagnosticsSnapshot.parse(health);
        ok(g.available(), "gst health available");
        eq(g.version(), "1.1.0", "gst version");
        eq(g.grade(), "DEGRADED", "gst grade");
        ok(g.lagActive(), "gst lag active");
        eq(g.incidentCount(), 3L, "gst incidents");
        eq(g.players(), 4, "gst players");
        eq(g.lastIncidentId(), 3L, "gst last incident");
        ok(g.toJson(2000, 30000).contains("\"grade\":\"DEGRADED\""), "gst json");

        String lag = "{\"schema\":1,\"event\":\"start\",\"session_id\":\"abc\",\"time\":123,\"id\":7,\"started_at\":123,\"recovered_at\":0," +
                "\"severity\":\"CRITICAL\",\"reason\":\"TPS 14.0\",\"tps_1m\":14.0,\"mspt\":90.0,\"memory_percent\":50.0," +
                "\"players\":5,\"loaded_chunks\":1000,\"entities\":800,\"hottest_world\":{\"name\":\"world_nether\",\"loaded_chunks\":500,\"entities\":600}}";
        GstLagEvent e = GstLagEvent.parse(lag);
        ok(e != null, "lag event parse");
        eq(e.id(), 7L, "lag id");
        eq(e.hottestWorld(), "world_nether", "lag hottest world");
        ok(!e.recovered(), "lag start");
        ok(e.message().contains("MSPT 90.0ms"), "lag message");

        System.out.println("PASS " + tests + " core tests");
    }
    static void ok(boolean v, String name) { tests++; if (!v) throw new AssertionError(name); }
    static void eq(Object a, Object b, String name) { tests++; if (!java.util.Objects.equals(a,b)) throw new AssertionError(name+": "+a+" != "+b); }
}
