package kr.geumyi.statusagent;

import java.net.URI;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.*;

final class GscClient {
    record Result(boolean ok, int status, String body, String error) {}
    private final HttpClient http;
    private final String base;
    private final String token;
    private final boolean enabled;
    private final Duration requestTimeout;

    GscClient(Properties cfg) {
        String raw=cfg.getProperty("gsc.base_url","http://127.0.0.1:8787/api/v1").trim();
        while(raw.endsWith("/")) raw=raw.substring(0,raw.length()-1);
        this.base=raw;
        this.token=cfg.getProperty("gsc.token","").trim();
        this.enabled=Boolean.parseBoolean(cfg.getProperty("gsc.enabled","true"));
        int timeout=intCfg(cfg,"gsc.timeout_ms",2500,500,15000);
        this.requestTimeout=Duration.ofMillis(timeout);
        this.http=HttpClient.newBuilder().connectTimeout(requestTimeout).version(HttpClient.Version.HTTP_1_1).build();
    }
    boolean enabled(){ return enabled; }
    Result get(String path) { return request("GET",path,null,null,null,null); }
    Result action(String server,String action,int countdown,String actorId,String actorName,String requestId) {
        Map<String,Object> body=new LinkedHashMap<>(); body.put("action",action); if(countdown>=0) body.put("countdown_seconds",countdown);
        return request("POST","/servers/"+url(server)+"/actions",JsonOut.stringify(body),actorId,actorName,requestId);
    }
    Result command(String server,String command,String actorId,String actorName,String requestId) {
        return request("POST","/servers/"+url(server)+"/command",JsonOut.stringify(Map.of("command",command)),actorId,actorName,requestId);
    }
    Result health(String server){ return get("/servers/"+url(server)+"/health"); }
    Result server(String server){ return get("/servers/"+url(server)); }
    private Result request(String method,String path,String body,String actorId,String actorName,String requestId){
        if(!enabled) return new Result(false,0,"","GSC integration disabled");
        try{
            HttpRequest.Builder b=HttpRequest.newBuilder(URI.create(base+path)).timeout(requestTimeout).header("Accept","application/json").header("User-Agent","GeumyiStatusAgent/0.5.4");
            if(!token.isBlank()) b.header("Authorization","Bearer "+token);
            if(actorId!=null&&!actorId.isBlank()) b.header("X-GSC-Actor-Id",actorId);
            if(actorName!=null&&!actorName.isBlank()) {
                String clipped=clip(actorName,80);
                if(isAsciiHeaderSafe(clipped)) b.header("X-GSC-Actor",clipped);
                b.header("X-GSC-Actor-B64",Base64.getUrlEncoder().withoutPadding().encodeToString(clipped.getBytes(StandardCharsets.UTF_8)));
            }
            b.header("X-GSC-Source","discord-agent");
            if(requestId!=null&&!requestId.isBlank()) b.header("X-GSC-Request-Id",clip(requestId,100));
            if(body!=null) b.header("Content-Type","application/json; charset=UTF-8");
            b.method(method, body==null?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofString(body, StandardCharsets.UTF_8));
            HttpResponse<String> r=http.send(b.build(),HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            return new Result(r.statusCode()>=200&&r.statusCode()<300,r.statusCode(),r.body(),r.statusCode()>=200&&r.statusCode()<300?"":"HTTP "+r.statusCode());
        }catch(Exception e){ return new Result(false,0,"",safe(e)); }
    }
    private static String url(String s){ return java.net.URLEncoder.encode(s,StandardCharsets.UTF_8); }
    private static String clip(String s,int n){ return s.length()<=n?s:s.substring(0,n); }
    private static boolean isAsciiHeaderSafe(String s){
        for(int i=0;i<s.length();i++){ char c=s.charAt(i); if(c<0x20||c>0x7e) return false; }
        return true;
    }
    private static String safe(Throwable t){ String s=t.getMessage(); return s==null?t.getClass().getSimpleName():s; }
    private static int intCfg(Properties p,String k,int d,int min,int max){ try{return Math.max(min,Math.min(max,Integer.parseInt(p.getProperty(k,Integer.toString(d)).trim())));}catch(Exception e){return d;} }
}
