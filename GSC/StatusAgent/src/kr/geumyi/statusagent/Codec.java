package kr.geumyi.statusagent;

import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;

final class Codec {
    private Codec() {}

    static Map<String,String> parseForm(String s) {
        Map<String,String> out = new LinkedHashMap<>();
        if (s == null || s.isBlank()) return out;
        for (String part : s.split("&")) {
            int idx = part.indexOf('=');
            String k = idx >= 0 ? part.substring(0, idx) : part;
            String v = idx >= 0 ? part.substring(idx + 1) : "";
            out.put(URLDecoder.decode(k, StandardCharsets.UTF_8), URLDecoder.decode(v, StandardCharsets.UTF_8));
        }
        return out;
    }

    static String json(String s) {
        if (s == null) return "";
        StringBuilder out = new StringBuilder(s.length() + 16);
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"' -> out.append("\\\"");
                case '\\' -> out.append("\\\\");
                case '\b' -> out.append("\\b");
                case '\f' -> out.append("\\f");
                case '\n' -> out.append("\\n");
                case '\r' -> out.append("\\r");
                case '\t' -> out.append("\\t");
                default -> {
                    if (c < 0x20) out.append(String.format("\\u%04x", (int)c));
                    else out.append(c);
                }
            }
        }
        return out.toString();
    }

    static int i(Map<String,String> m, String k, int d) {
        try { return Integer.parseInt(m.getOrDefault(k, Integer.toString(d))); } catch (Exception e) { return d; }
    }
    static long l(Map<String,String> m, String k, long d) {
        try { return Long.parseLong(m.getOrDefault(k, Long.toString(d))); } catch (Exception e) { return d; }
    }
    static double d(Map<String,String> m, String k, double d) {
        try { return Double.parseDouble(m.getOrDefault(k, Double.toString(d))); } catch (Exception e) { return d; }
    }
    static boolean b(Map<String,String> m, String k, boolean d) {
        String v = m.get(k); return v == null ? d : Boolean.parseBoolean(v);
    }
}
