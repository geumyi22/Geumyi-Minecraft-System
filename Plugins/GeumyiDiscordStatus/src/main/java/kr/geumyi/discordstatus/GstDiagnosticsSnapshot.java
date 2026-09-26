package kr.geumyi.discordstatus;

import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

record GstDiagnosticsSnapshot(boolean available, long time, String version, String grade, boolean lagActive,
                              long incidentCount, double tps1m, double tps5m, double tps15m, double mspt,
                              double recentPeakMspt, double recentMinTps, double memoryPercent,
                              int players, int loadedChunks, int entities,
                              long lastIncidentId, String lastIncidentSeverity, String lastIncidentReason,
                              long lastIncidentRecoveredAt) {
    private static final Pattern STRING = Pattern.compile("\\\"%s\\\"\\s*:\\s*\\\"((?:\\\\.|[^\\\"\\\\])*)\\\"");
    private static final Pattern NUMBER = Pattern.compile("\\\"%s\\\"\\s*:\\s*(-?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:[eE][+-]?\\d+)?|null)");
    private static final Pattern BOOL = Pattern.compile("\\\"%s\\\"\\s*:\\s*(true|false)", Pattern.CASE_INSENSITIVE);
    private static final Pattern OBJECT = Pattern.compile("\\\"%s\\\"\\s*:\\s*\\{([^{}]*)\\}", Pattern.DOTALL);

    static GstDiagnosticsSnapshot unavailable() {
        return new GstDiagnosticsSnapshot(false, 0L, "", "UNKNOWN", false, 0L,
                Double.NaN, Double.NaN, Double.NaN, Double.NaN, Double.NaN, Double.NaN, Double.NaN,
                0, 0, 0, 0L, "", "", 0L);
    }

    static GstDiagnosticsSnapshot parse(String json) {
        if (json == null || json.isBlank()) return unavailable();
        long time = longValue(json, "time", 0L);
        String version = stringValue(json, "version", "");
        String grade = stringValue(json, "grade", "UNKNOWN").toUpperCase(Locale.ROOT);
        boolean lag = boolValue(json, "lag_active", false);
        long incidents = longValue(json, "incident_count", 0L);
        String perf = objectValue(json, "performance");
        String counts = objectValue(json, "counts");
        String incident = objectValue(json, "last_incident");
        return new GstDiagnosticsSnapshot(true, time, version, grade, lag, incidents,
                doubleValue(perf, "tps_1m"), doubleValue(perf, "tps_5m"), doubleValue(perf, "tps_15m"),
                doubleValue(perf, "mspt"), doubleValue(perf, "recent_peak_mspt"), doubleValue(perf, "recent_min_tps"),
                doubleValue(perf, "memory_percent"),
                (int) longValue(counts, "players", 0L), (int) longValue(counts, "loaded_chunks", 0L), (int) longValue(counts, "entities", 0L),
                longValue(incident, "id", 0L), stringValue(incident, "severity", ""), stringValue(incident, "reason", ""),
                longValue(incident, "recovered_at", 0L));
    }

    boolean degraded() { return "DEGRADED".equals(grade) || "CRITICAL".equals(grade); }

    boolean stale(long now, long maxAgeMillis) {
        return available && time > 0 && now - time > Math.max(1L, maxAgeMillis);
    }

    long ageSeconds(long now) { return time <= 0 ? -1L : Math.max(0L, (now - time) / 1000L); }

    String toJson(long now, long maxAgeMillis) {
        StringBuilder b = new StringBuilder(768);
        b.append('{').append("\"available\":").append(available)
                .append(",\"version\":\"").append(Text.json(version)).append('"')
                .append(",\"time\":").append(time)
                .append(",\"age_seconds\":").append(ageSeconds(now))
                .append(",\"stale\":").append(stale(now, maxAgeMillis))
                .append(",\"grade\":\"").append(Text.json(grade)).append('"')
                .append(",\"lag_active\":").append(lagActive)
                .append(",\"incident_count\":").append(incidentCount)
                .append(",\"performance\":{")
                .append("\"tps_1m\":").append(num(tps1m)).append(",\"tps_5m\":").append(num(tps5m))
                .append(",\"tps_15m\":").append(num(tps15m)).append(",\"mspt\":").append(num(mspt))
                .append(",\"recent_peak_mspt\":").append(num(recentPeakMspt)).append(",\"recent_min_tps\":").append(num(recentMinTps))
                .append(",\"memory_percent\":").append(num(memoryPercent)).append('}')
                .append(",\"counts\":{\"players\":").append(players).append(",\"loaded_chunks\":").append(loadedChunks)
                .append(",\"entities\":").append(entities).append('}');
        if (lastIncidentId > 0) {
            b.append(",\"last_incident\":{\"id\":").append(lastIncidentId)
                    .append(",\"severity\":\"").append(Text.json(lastIncidentSeverity)).append('"')
                    .append(",\"reason\":\"").append(Text.json(lastIncidentReason)).append('"')
                    .append(",\"recovered_at\":").append(lastIncidentRecoveredAt).append('}');
        } else b.append(",\"last_incident\":null");
        return b.append('}').toString();
    }

    private static String objectValue(String json, String key) {
        if (json == null || json.isBlank()) return "";
        Matcher m = Pattern.compile(String.format(OBJECT.pattern(), Pattern.quote(key)), Pattern.DOTALL).matcher(json);
        return m.find() ? m.group(1) : "";
    }

    private static String stringValue(String json, String key, String def) {
        if (json == null || json.isBlank()) return def;
        Matcher m = Pattern.compile(String.format(STRING.pattern(), Pattern.quote(key))).matcher(json);
        return m.find() ? unescape(m.group(1)) : def;
    }

    private static long longValue(String json, String key, long def) {
        if (json == null || json.isBlank()) return def;
        Matcher m = Pattern.compile(String.format(NUMBER.pattern(), Pattern.quote(key))).matcher(json);
        if (!m.find() || "null".equalsIgnoreCase(m.group(1))) return def;
        try { return Math.round(Double.parseDouble(m.group(1))); } catch (NumberFormatException e) { return def; }
    }

    private static double doubleValue(String json, String key) {
        if (json == null || json.isBlank()) return Double.NaN;
        Matcher m = Pattern.compile(String.format(NUMBER.pattern(), Pattern.quote(key))).matcher(json);
        if (!m.find() || "null".equalsIgnoreCase(m.group(1))) return Double.NaN;
        try { return Double.parseDouble(m.group(1)); } catch (NumberFormatException e) { return Double.NaN; }
    }

    private static boolean boolValue(String json, String key, boolean def) {
        if (json == null || json.isBlank()) return def;
        Matcher m = Pattern.compile(String.format(BOOL.pattern(), Pattern.quote(key)), Pattern.CASE_INSENSITIVE).matcher(json);
        return m.find() ? Boolean.parseBoolean(m.group(1)) : def;
    }

    private static String unescape(String s) {
        if (s == null || s.indexOf('\\') < 0) return s == null ? "" : s;
        StringBuilder b = new StringBuilder(s.length());
        boolean esc = false;
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (!esc) { if (c == '\\') esc = true; else b.append(c); continue; }
            esc = false;
            switch (c) {
                case 'n' -> b.append('\n'); case 'r' -> b.append('\r'); case 't' -> b.append('\t');
                case 'b' -> b.append('\b'); case 'f' -> b.append('\f'); case '"', '\\', '/' -> b.append(c);
                default -> b.append(c);
            }
        }
        if (esc) b.append('\\');
        return b.toString();
    }

    private static String num(double d) { return Double.isFinite(d) ? String.format(Locale.ROOT, "%.4f", d) : "null"; }
}
