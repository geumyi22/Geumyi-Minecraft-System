package kr.geumyi.statusagent;

import java.util.*;

final class Json {
    private Json() {}

    static Object parse(String text) {
        if (text == null) return null;
        Parser p = new Parser(text);
        Object v = p.value();
        p.ws();
        if (!p.end()) throw new IllegalArgumentException("Trailing JSON at " + p.i);
        return v;
    }

    @SuppressWarnings("unchecked")
    static Map<String,Object> obj(Object v) { return v instanceof Map<?,?> ? (Map<String,Object>) v : Map.of(); }
    @SuppressWarnings("unchecked")
    static List<Object> arr(Object v) { return v instanceof List<?> ? (List<Object>) v : List.of(); }
    static String str(Object v) { return v == null ? "" : String.valueOf(v); }
    static long lng(Object v, long d) {
        if (v instanceof Number n) return n.longValue();
        try { return Long.parseLong(str(v)); } catch (Exception e) { return d; }
    }
    static int integer(Object v, int d) {
        if (v instanceof Number n) return n.intValue();
        try { return Integer.parseInt(str(v)); } catch (Exception e) { return d; }
    }
    static boolean bool(Object v, boolean d) { return v instanceof Boolean b ? b : d; }

    private static final class Parser {
        final String s; int i;
        Parser(String s) { this.s=s; }
        boolean end(){ return i>=s.length(); }
        void ws(){ while(!end() && Character.isWhitespace(s.charAt(i))) i++; }
        Object value(){
            ws(); if(end()) throw err("Unexpected end");
            char c=s.charAt(i);
            if(c=='{') return object(); if(c=='[') return array(); if(c=='"') return string();
            if(c=='t' && take("true")) return Boolean.TRUE;
            if(c=='f' && take("false")) return Boolean.FALSE;
            if(c=='n' && take("null")) return null;
            if(c=='-' || Character.isDigit(c)) return number();
            throw err("Unexpected character " + c);
        }
        Map<String,Object> object(){
            LinkedHashMap<String,Object> m=new LinkedHashMap<>(); i++; ws();
            if(!end() && s.charAt(i)=='}'){ i++; return m; }
            while(true){ ws(); if(end()||s.charAt(i)!='"') throw err("Object key expected"); String k=string(); ws();
                if(end()||s.charAt(i)!=':') throw err(": expected"); i++; m.put(k,value()); ws();
                if(!end()&&s.charAt(i)==','){i++;continue;} if(!end()&&s.charAt(i)=='}'){i++;return m;} throw err("} expected"); }
        }
        List<Object> array(){
            ArrayList<Object> a=new ArrayList<>(); i++; ws(); if(!end()&&s.charAt(i)==']'){i++;return a;}
            while(true){ a.add(value()); ws(); if(!end()&&s.charAt(i)==','){i++;continue;} if(!end()&&s.charAt(i)==']'){i++;return a;} throw err("] expected"); }
        }
        String string(){
            StringBuilder b=new StringBuilder(); i++;
            while(!end()){
                char c=s.charAt(i++); if(c=='"') return b.toString();
                if(c!='\\'){ b.append(c); continue; }
                if(end()) throw err("Bad escape"); char e=s.charAt(i++);
                switch(e){
                    case '"'->b.append('"'); case '\\'->b.append('\\'); case '/'->b.append('/');
                    case 'b'->b.append('\b'); case 'f'->b.append('\f'); case 'n'->b.append('\n'); case 'r'->b.append('\r'); case 't'->b.append('\t');
                    case 'u'->{ if(i+4>s.length()) throw err("Bad unicode"); b.append((char)Integer.parseInt(s.substring(i,i+4),16)); i+=4; }
                    default->throw err("Bad escape " + e);
                }
            }
            throw err("Unclosed string");
        }
        Number number(){
            int st=i; if(s.charAt(i)=='-')i++; while(!end()&&Character.isDigit(s.charAt(i)))i++;
            boolean fp=false; if(!end()&&s.charAt(i)=='.'){fp=true;i++;while(!end()&&Character.isDigit(s.charAt(i)))i++;}
            if(!end()&&(s.charAt(i)=='e'||s.charAt(i)=='E')){fp=true;i++;if(!end()&&(s.charAt(i)=='+'||s.charAt(i)=='-'))i++;while(!end()&&Character.isDigit(s.charAt(i)))i++;}
            String n=s.substring(st,i); return fp?Double.parseDouble(n):Long.parseLong(n);
        }
        boolean take(String x){ if(s.startsWith(x,i)){i+=x.length();return true;} return false; }
        IllegalArgumentException err(String m){ return new IllegalArgumentException(m+" at "+i); }
    }
}
