package kr.geumyi.statusagent;

import java.util.*;

final class JsonOut {
    private JsonOut() {}
    static String stringify(Object v) {
        StringBuilder b = new StringBuilder(); write(b, v); return b.toString();
    }
    private static void write(StringBuilder b, Object v) {
        if (v == null) { b.append("null"); return; }
        if (v instanceof String s) { b.append('"').append(escape(s)).append('"'); return; }
        if (v instanceof Number || v instanceof Boolean) { b.append(v); return; }
        if (v instanceof Map<?,?> m) {
            b.append('{'); boolean first=true;
            for (var e: m.entrySet()) { if (!first) b.append(','); first=false; write(b,String.valueOf(e.getKey())); b.append(':'); write(b,e.getValue()); }
            b.append('}'); return;
        }
        if (v instanceof Iterable<?> it) {
            b.append('['); boolean first=true;
            for (Object x: it) { if (!first) b.append(','); first=false; write(b,x); }
            b.append(']'); return;
        }
        if (v.getClass().isArray()) {
            b.append('['); int n=java.lang.reflect.Array.getLength(v);
            for (int i=0;i<n;i++) { if (i>0)b.append(','); write(b,java.lang.reflect.Array.get(v,i)); }
            b.append(']'); return;
        }
        write(b, String.valueOf(v));
    }
    static String escape(String s) {
        StringBuilder b=new StringBuilder(s.length()+16);
        for(char c:s.toCharArray()) switch(c) {
            case '"' -> b.append("\\\""); case '\\' -> b.append("\\\\"); case '\b' -> b.append("\\b"); case '\f' -> b.append("\\f");
            case '\n' -> b.append("\\n"); case '\r' -> b.append("\\r"); case '\t' -> b.append("\\t");
            default -> { if(c<0x20)b.append(String.format("\\u%04x",(int)c)); else b.append(c); }
        }
        return b.toString();
    }
}
