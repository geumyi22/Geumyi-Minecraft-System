package kr.geumyi.discordstatus;

import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

record GstLagEvent(String event, String sessionId, long time, long id, long startedAt, long recoveredAt,
                   String severity, String reason, double tps1m, double mspt, double memoryPercent,
                   int players, int loadedChunks, int entities, String hottestWorld) {
    static GstLagEvent parse(String json) {
        if (json == null || json.isBlank()) return null;
        String event = s(json, "event");
        long id = l(json, "id");
        if (event.isBlank() || id <= 0) return null;
        return new GstLagEvent(event, s(json, "session_id"), l(json, "time"), id, l(json, "started_at"), l(json, "recovered_at"),
                s(json, "severity"), s(json, "reason"), d(json, "tps_1m"), d(json, "mspt"), d(json, "memory_percent"),
                (int) l(json, "players"), (int) l(json, "loaded_chunks"), (int) l(json, "entities"), nestedString(json, "hottest_world", "name"));
    }

    boolean recovered() { return "recovered".equalsIgnoreCase(event) || recoveredAt > 0; }

    String message() {
        StringBuilder b = new StringBuilder("#").append(id);
        if (!severity.isBlank()) b.append(' ').append(severity);
        if (!reason.isBlank()) b.append(" · ").append(reason);
        if (Double.isFinite(tps1m)) b.append(" · TPS ").append(fmt(tps1m));
        if (Double.isFinite(mspt)) b.append(" · MSPT ").append(fmt(mspt)).append("ms");
        if (Double.isFinite(memoryPercent)) b.append(" · RAM ").append(fmt(memoryPercent)).append('%');
        b.append(" · P ").append(players).append(" · C ").append(loadedChunks).append(" · E ").append(entities);
        if (!hottestWorld.isBlank()) b.append(" · ").append(hottestWorld);
        return b.toString();
    }

    private static String s(String json, String key) {
        Matcher m = Pattern.compile("\\\"" + Pattern.quote(key) + "\\\"\\s*:\\s*\\\"((?:\\\\.|[^\\\"\\\\])*)\\\"").matcher(json);
        return m.find() ? m.group(1).replace("\\\"", "\"").replace("\\\\", "\\") : "";
    }
    private static long l(String json, String key) {
        Matcher m = Pattern.compile("\\\"" + Pattern.quote(key) + "\\\"\\s*:\\s*(-?\\d+)").matcher(json);
        try { return m.find() ? Long.parseLong(m.group(1)) : 0L; } catch (NumberFormatException e) { return 0L; }
    }
    private static double d(String json, String key) {
        Matcher m = Pattern.compile("\\\"" + Pattern.quote(key) + "\\\"\\s*:\\s*(-?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:[eE][+-]?\\d+)?|null)").matcher(json);
        try { return m.find() && !"null".equalsIgnoreCase(m.group(1)) ? Double.parseDouble(m.group(1)) : Double.NaN; }
        catch (NumberFormatException e) { return Double.NaN; }
    }
    private static String nestedString(String json, String object, String key) {
        Matcher m = Pattern.compile("\\\"" + Pattern.quote(object) + "\\\"\\s*:\\s*\\{([^{}]*)\\}", Pattern.DOTALL).matcher(json);
        return m.find() ? s(m.group(1), key) : "";
    }
    private static String fmt(double d) { return String.format(Locale.ROOT, "%.1f", d); }
}
