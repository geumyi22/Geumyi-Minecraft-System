package kr.geumyi.discordstatus;

import java.net.URLDecoder;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;

final class Text {
    private Text() {}

    static String json(String s) {
        if (s == null) return "";
        StringBuilder b = new StringBuilder(s.length() + 16);
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"' -> b.append("\\\"");
                case '\\' -> b.append("\\\\");
                case '\b' -> b.append("\\b");
                case '\f' -> b.append("\\f");
                case '\n' -> b.append("\\n");
                case '\r' -> b.append("\\r");
                case '\t' -> b.append("\\t");
                default -> {
                    if (c < 0x20) b.append(String.format("\\u%04x", (int) c));
                    else b.append(c);
                }
            }
        }
        return b.toString();
    }

    static String form(Map<String, String> values) {
        StringBuilder b = new StringBuilder();
        for (Map.Entry<String, String> e : values.entrySet()) {
            if (!b.isEmpty()) b.append('&');
            b.append(enc(e.getKey())).append('=').append(enc(e.getValue() == null ? "" : e.getValue()));
        }
        return b.toString();
    }

    static Map<String, String> parseForm(String body) {
        Map<String, String> out = linkedMap();
        if (body == null || body.isBlank()) return out;
        for (String pair : body.split("&")) {
            int eq = pair.indexOf('=');
            String k = eq >= 0 ? pair.substring(0, eq) : pair;
            String v = eq >= 0 ? pair.substring(eq + 1) : "";
            if (!k.isBlank()) out.put(dec(k), dec(v));
        }
        return out;
    }

    /** Minimal flat JSON object parser for the v4 action endpoint. Nested values are intentionally rejected. */
    static Map<String, String> parseFlatJson(String body) {
        Map<String, String> out = linkedMap();
        if (body == null) return out;
        int i = 0, n = body.length();
        while (i < n && Character.isWhitespace(body.charAt(i))) i++;
        if (i >= n || body.charAt(i++) != '{') throw new IllegalArgumentException("JSON object required");
        while (true) {
            while (i < n && Character.isWhitespace(body.charAt(i))) i++;
            if (i < n && body.charAt(i) == '}') return out;
            Parse pKey = parseJsonString(body, i);
            String key = pKey.value;
            i = pKey.next;
            while (i < n && Character.isWhitespace(body.charAt(i))) i++;
            if (i >= n || body.charAt(i++) != ':') throw new IllegalArgumentException("Expected ':'");
            while (i < n && Character.isWhitespace(body.charAt(i))) i++;
            if (i >= n) throw new IllegalArgumentException("Missing value");
            String value;
            if (body.charAt(i) == '"') {
                Parse pVal = parseJsonString(body, i);
                value = pVal.value;
                i = pVal.next;
            } else {
                int start = i;
                while (i < n && body.charAt(i) != ',' && body.charAt(i) != '}') {
                    char c = body.charAt(i);
                    if (c == '{' || c == '[') throw new IllegalArgumentException("Nested JSON is not supported");
                    i++;
                }
                value = body.substring(start, i).trim();
                if ("null".equals(value)) value = "";
            }
            out.put(key, value);
            while (i < n && Character.isWhitespace(body.charAt(i))) i++;
            if (i < n && body.charAt(i) == ',') { i++; continue; }
            if (i < n && body.charAt(i) == '}') return out;
            throw new IllegalArgumentException("Expected ',' or '}'");
        }
    }

    private static Parse parseJsonString(String s, int i) {
        if (i >= s.length() || s.charAt(i) != '"') throw new IllegalArgumentException("Expected string");
        i++;
        StringBuilder b = new StringBuilder();
        while (i < s.length()) {
            char c = s.charAt(i++);
            if (c == '"') return new Parse(b.toString(), i);
            if (c != '\\') { b.append(c); continue; }
            if (i >= s.length()) throw new IllegalArgumentException("Bad escape");
            char e = s.charAt(i++);
            switch (e) {
                case '"', '\\', '/' -> b.append(e);
                case 'b' -> b.append('\b');
                case 'f' -> b.append('\f');
                case 'n' -> b.append('\n');
                case 'r' -> b.append('\r');
                case 't' -> b.append('\t');
                case 'u' -> {
                    if (i + 4 > s.length()) throw new IllegalArgumentException("Bad unicode escape");
                    b.append((char) Integer.parseInt(s.substring(i, i + 4), 16));
                    i += 4;
                }
                default -> throw new IllegalArgumentException("Bad escape");
            }
        }
        throw new IllegalArgumentException("Unterminated string");
    }

    private static String enc(String s) { return URLEncoder.encode(s, StandardCharsets.UTF_8); }
    private static String dec(String s) { return URLDecoder.decode(s, StandardCharsets.UTF_8); }
    static Map<String, String> linkedMap() { return new LinkedHashMap<>(); }
    static boolean truthy(String s) { return "true".equalsIgnoreCase(s) || "1".equals(s) || "on".equalsIgnoreCase(s) || "yes".equalsIgnoreCase(s); }

    private record Parse(String value, int next) {}
}
