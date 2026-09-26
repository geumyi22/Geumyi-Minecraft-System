package kr.geumyi.statusagent;

import com.sun.net.httpserver.*;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.io.*;
import java.net.*;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

public final class GeumyiStatusAgent {
    public static final String VERSION="0.5.4";
    private final Properties cfg=new Properties();
    private final Map<String,ServerState> states=new ConcurrentHashMap<>();
    private final Map<String,String> lastTransition=new ConcurrentHashMap<>();
    private final Set<String> offlineEpisodeNotified=ConcurrentHashMap.newKeySet();
    private final Set<String> recentNonces=ConcurrentHashMap.newKeySet();
    private final Map<String,Long> recentDiscordEvents=new ConcurrentHashMap<>();
    private final ScheduledExecutorService scheduler=Executors.newScheduledThreadPool(3,r->{Thread t=new Thread(r,"GSA-Core");t.setDaemon(true);return t;});
    private final Path baseDir,configFile,outageStateFile;
    private final MetricsLog metrics;
    private final ZoneId zone;
    private final GscClient gsc;
    private DiscordBot discord;
    private HttpServer http;
    private ExecutorService httpExecutor;
    private final AtomicBoolean stopping=new AtomicBoolean();
    private final HttpClient localHttp=HttpClient.newBuilder().connectTimeout(Duration.ofMillis(700)).version(HttpClient.Version.HTTP_1_1).build();
    private final java.util.concurrent.atomic.AtomicLong ingestAccepted=new java.util.concurrent.atomic.AtomicLong();
    private final java.util.concurrent.atomic.AtomicLong ingestRejected=new java.util.concurrent.atomic.AtomicLong();
    private volatile String lastIngestRejectReason="";
    private volatile long lastIngestRejectMillis;
    private String sharedSecret="";
    private long lastMetricsWrite;
    private LocalDate lastSummaryDate;
    private final long agentStartedMillis=System.currentTimeMillis();
    private volatile boolean loopbackSecretWarningPrinted;

    private GeumyiStatusAgent(Path configFile)throws IOException{
        this.configFile=configFile.toAbsolutePath().normalize();this.baseDir=Optional.ofNullable(this.configFile.getParent()).orElse(Path.of(".").toAbsolutePath());
        try(var in=Files.newBufferedReader(this.configFile,StandardCharsets.UTF_8)){cfg.load(in);} sharedSecret=cfg.getProperty("secret","").trim();
        zone=ZoneId.of(cfg.getProperty("timezone","Asia/Seoul").trim()); metrics=new MetricsLog(baseDir.resolve("data/metrics"),zone);outageStateFile=baseDir.resolve("data/offline-alert-state.properties");gsc=new GscClient(cfg);
        initServers();loadOfflineAlertState();
    }
    public static void main(String[] args)throws Exception{
        Path cfg=args.length>0?Path.of(args[0]):Path.of("agent.properties");
        if(!Files.exists(cfg)){System.err.println("[GSA] Missing config: "+cfg.toAbsolutePath());System.exit(2);}
        GeumyiStatusAgent a=new GeumyiStatusAgent(cfg);Runtime.getRuntime().addShutdownHook(new Thread(a::stop,"GSA-Shutdown"));a.start();new CountDownLatch(1).await();
    }
    private void initServers(){
        for(String id:configuredOrder()){
            String name=cfg.getProperty("server."+id+".name",id).trim();states.put(id,new ServerState(id,name));lastTransition.put(id,"STARTING");
        }
    }
    private void start()throws IOException{
        startHttp();
        discord=new DiscordBot(cfg,baseDir.resolve("data/agent-state.properties"),this::buildStatusEmbed,this::buildStatsText,this::buildBotInfo,gsc);discord.start();
        int interval=intCfg("update_interval_seconds",15,3,300);scheduler.scheduleAtFixedRate(this::monitorAllSafe,1,interval,TimeUnit.SECONDS);scheduler.scheduleAtFixedRate(this::cleanupNonces,1,1,TimeUnit.MINUTES);scheduler.scheduleAtFixedRate(this::dailySummarySafe,30,60,TimeUnit.SECONDS);
        System.out.println("[GSA] GeumyiStatusAgent "+VERSION+" started; HTTP "+cfg.getProperty("listen.bind","127.0.0.1")+":"+cfg.getProperty("listen.port","8877"));
    }
    private void startHttp()throws IOException{
        String bind=cfg.getProperty("listen.bind","127.0.0.1").trim();int port=intCfg("listen.port",8877,1,65535);http=HttpServer.create(new InetSocketAddress(bind,port),64);
        http.createContext("/ingest",this::ingest);http.createContext("/state",this::stateEndpoint);http.createContext("/health",ex->reply(ex,200,"application/json; charset=utf-8",healthJson()));http.createContext("/shutdown",this::shutdownEndpoint);
        httpExecutor=Executors.newVirtualThreadPerTaskExecutor();
        http.setExecutor(httpExecutor);http.start();
    }
    private void shutdownEndpoint(HttpExchange ex)throws IOException{
        if(!"POST".equalsIgnoreCase(ex.getRequestMethod())){reply(ex,405,"text/plain; charset=utf-8","method not allowed");return;}
        boolean loopback=ex.getRemoteAddress()!=null&&ex.getRemoteAddress().getAddress()!=null&&ex.getRemoteAddress().getAddress().isLoopbackAddress();
        if(!loopback){reply(ex,403,"application/json; charset=utf-8","{\"ok\":false,\"error\":\"loopback required\"}");return;}
        if(!boolCfg("allow_loopback_shutdown",true)){reply(ex,403,"application/json; charset=utf-8","{\"ok\":false,\"error\":\"loopback shutdown disabled\"}");return;}
        reply(ex,202,"application/json; charset=utf-8","{\"ok\":true,\"message\":\"shutdown scheduled\"}");
        Thread.ofVirtual().name("GSA-GracefulShutdown").start(()->{
            try{Thread.sleep(120);}catch(InterruptedException ignored){Thread.currentThread().interrupt();}
            stop();
            System.exit(0);
        });
    }
    private void ingest(HttpExchange ex)throws IOException{
        if(!"POST".equalsIgnoreCase(ex.getRequestMethod())){reply(ex,405,"text/plain","method not allowed");return;}
        byte[] raw=ex.getRequestBody().readNBytes(256*1024);String body=new String(raw,StandardCharsets.UTF_8);
        String authError=ingestAuthorizationError(ex,body);
        if(authError!=null){ingestRejected.incrementAndGet();lastIngestRejectReason=authError;lastIngestRejectMillis=System.currentTimeMillis();reply(ex,401,"application/json","{\"ok\":false,\"error\":\"unauthorized\"}");return;}
        ingestAccepted.incrementAndGet();
        Map<String,String> p=Codec.parseForm(body);String id=p.getOrDefault("server_id","").trim();if(id.isBlank()){reply(ex,400,"application/json","{\"ok\":false,\"error\":\"server_id required\"}");return;}
        ServerState s=states.computeIfAbsent(id,k->new ServerState(k,p.getOrDefault("server_name",k)));updateFromPayload(s,p);String event=p.getOrDefault("event","heartbeat");if(!"heartbeat".equalsIgnoreCase(event))processEvent(s,event,p);
        reply(ex,200,"application/json","{\"ok\":true,\"agent_version\":\""+VERSION+"\"}");
    }
    private String ingestAuthorizationError(HttpExchange ex,String body){
        InetAddress ra=ex.getRemoteAddress()==null?null:ex.getRemoteAddress().getAddress();boolean loop=ra!=null&&ra.isLoopbackAddress();String got=first(ex,"X-GDS-Secret");
        if(sharedSecret.isBlank()){
            if(loop&&boolCfg("allow_loopback_ingest_without_matching_secret",false)){if(!loopbackSecretWarningPrinted){System.err.println("[GSA] WARNING: loopback ingest without secret is enabled.");loopbackSecretWarningPrinted=true;}return null;}return "agent shared secret is blank";
        }
        if(!constant(sharedSecret,got))return "shared secret mismatch";
        String ts=first(ex,"X-GDS-Timestamp"),nonce=first(ex,"X-GDS-Nonce"),sig=first(ex,"X-GDS-Signature");
        if(ts.isBlank()||nonce.isBlank()||sig.isBlank()) return boolCfg("allow_legacy_secret_only_ingest",true)&&loop?null:"missing HMAC headers";
        try{
            long t=Long.parseLong(ts);if(Math.abs(System.currentTimeMillis()-t)>120_000)return "timestamp outside replay window";if(nonce.length()>120||nonce.isBlank())return "invalid nonce";if(!recentNonces.add(nonce))return "replayed nonce";
            return constant(hmac(sharedSecret,ts+"\n"+nonce+"\n"+body),sig)?null:"HMAC signature mismatch";
        }catch(Exception e){return "invalid HMAC metadata";}
    }
    private void cleanupNonces(){if(recentNonces.size()>5000)recentNonces.clear();long cut=System.currentTimeMillis()-3_600_000L;recentDiscordEvents.entrySet().removeIf(e->e.getValue()<cut);}
    private void updateFromPayload(ServerState s,Map<String,String>p){
        long now=System.currentTimeMillis();s.lastHeartbeatMillis=now;s.pluginReachable=true;s.name=p.getOrDefault("server_name",s.name);s.mode=p.getOrDefault("mode",s.mode);s.lastEvent=p.getOrDefault("event",s.lastEvent);s.lastMessage=p.getOrDefault("message",s.lastMessage);s.online=Codec.i(p,"online",s.online);s.maxPlayers=Codec.i(p,"max_players",s.maxPlayers);s.javaPlayers=Codec.i(p,"java_players",s.javaPlayers);s.bedrockPlayers=Codec.i(p,"bedrock_players",s.bedrockPlayers);s.tps=Codec.d(p,"tps",s.tps);s.mspt=Codec.d(p,"mspt",s.mspt);s.memory=Codec.d(p,"memory_percent",s.memory);s.uptimeSeconds=Codec.l(p,"uptime_seconds",s.uptimeSeconds);s.version=p.getOrDefault("minecraft_version",p.getOrDefault("paper_version",s.version));s.reportedJavaPort=Codec.i(p,"server_port",s.reportedJavaPort);s.loadedChunks=Codec.i(p,"loaded_chunks",s.loadedChunks);s.entities=Codec.i(p,"entities",s.entities);
        s.plannedShutdown=Codec.b(p,"planned",s.plannedShutdown)||"shutdown".equalsIgnoreCase(p.getOrDefault("event",""));
        for(String k:List.of("gst_version","gst_grade","gst_lag_active","gst_incident_count","gst_health_time","protocol_version","plugin_version","maintenance_reason","restart_reason","restart_due","instance_id","boot_id")){String v=p.get(k);if(v!=null)s.extras.put(k,v);}
    }
    private void processEvent(ServerState s,String event,Map<String,String>p){
        s.lastEventMillis=System.currentTimeMillis();s.lastEvent=event;s.lastMessage=p.getOrDefault("message","");String title=p.getOrDefault("title",event);String msg=p.getOrDefault("message","");
        if("startup".equalsIgnoreCase(event)||"started".equalsIgnoreCase(event)){s.plannedShutdown=false;offlineEpisodeNotified.remove(s.id);}
        if("shutdown".equalsIgnoreCase(event)){s.plannedShutdown=true;}
        if(discord!=null&&discord.canEvents()){
            int dedupe=intCfg("discord.event_dedupe_seconds",30,0,3600);String key=s.id+"|"+event+"|"+title+"|"+msg;long now=System.currentTimeMillis();Long last=recentDiscordEvents.put(key,now);
            if(dedupe==0||last==null||now-last>=dedupe*1000L){
                int color=colorFor(event);String extra="\n서버: **"+s.name+"**";
                String grade=s.extras.getOrDefault("gst_grade","");if(!grade.isBlank())extra+=" · GST `"+grade+"`";
                discord.sendEvent(title,msg+extra,color);
            }
        }
        appendEvent(s,event,title+" | "+msg);
    }
    private void monitorAllSafe(){try{long now=System.currentTimeMillis();for(ServerState s:states.values())monitorOne(s,now);if(discord!=null&&discord.canStatus())discord.updateStatus(buildStatusEmbed());writeMetricsSafe();}catch(Throwable t){System.err.println("[GSA] monitor error: "+safe(t));}}
    private void monitorOne(ServerState s,long now){
        int port=intCfg("server."+s.id+".java_port",s.reportedJavaPort,0,65535);String host=cfg.getProperty("server."+s.id+".host","127.0.0.1").trim();int timeout=intCfg("ping_timeout_ms",1500,250,10000);
        if(port>0){MinecraftPing.Result pr=MinecraftPing.ping(host,port,timeout);s.minecraftReachable=pr.reachable();if(pr.reachable()){if(s.online<=0)s.online=pr.online();if(s.maxPlayers<=0)s.maxPlayers=pr.max();if((s.version==null||s.version.isBlank())&&pr.version()!=null)s.version=pr.version();}}
        int offlineAfter=intCfg("offline_after_seconds",35,10,600);boolean fresh=now-s.lastHeartbeatMillis<=offlineAfter*1000L;
        if(!fresh) probeLocalGds(s); else if(fresh) s.extras.put("gds_api_reachable","true");
        derive(s,now);applyGscState(s);maybeTransition(s);
    }
    private void probeLocalGds(ServerState s){
        int def="playground".equalsIgnoreCase(s.id)?8765:8766;int port=intCfg("server."+s.id+".gds_api_port",def,0,65535);if(port<=0){s.extras.put("gds_api_reachable","false");return;}
        try{
            HttpRequest req=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/v4/status")).timeout(Duration.ofMillis(900)).header("Accept","application/json").build();
            HttpResponse<String> r=localHttp.send(req,HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));boolean ok=r.statusCode()>=200&&r.statusCode()<300;s.extras.put("gds_api_reachable",Boolean.toString(ok));
            if(ok){try{Map<String,Object> o=Json.obj(Json.parse(r.body()));String pv=Json.str(o.get("plugin_version"));if(!pv.isBlank())s.extras.put("plugin_version",pv);String rid=Json.str(o.get("server_id"));if(!rid.isBlank())s.extras.put("gds_reported_server_id",rid);Object metrics=o.get("metrics");if(metrics instanceof Map<?,?> mm){Object v=mm.get("tps_1m");if(v!=null)s.tps=jsonDouble(v,s.tps);v=mm.get("mspt");if(v!=null)s.mspt=jsonDouble(v,s.mspt);v=mm.get("memory_percent");if(v!=null)s.memory=jsonDouble(v,s.memory);v=mm.get("online");if(v!=null)s.online=(int)Json.lng(v,s.online);v=mm.get("max_players");if(v!=null)s.maxPlayers=(int)Json.lng(v,s.maxPlayers);v=mm.get("uptime_seconds");if(v!=null)s.uptimeSeconds=Json.lng(v,s.uptimeSeconds);}Object gst=o.get("gst_diagnostics");if(gst instanceof Map<?,?> gm){for(String k:List.of("version","grade","lag_active","incident_count","time")){Object v=gm.get(k);if(v!=null)s.extras.put("gst_"+("time".equals(k)?"health_time":k),String.valueOf(v));}}Object bridge=o.get("bridge");if(bridge instanceof Map<?,?> bm){Object v=bm.get("last_success");if(v!=null)s.extras.put("gds_bridge_last_success",String.valueOf(v));v=bm.get("last_failure");if(v!=null)s.extras.put("gds_bridge_last_failure",String.valueOf(v));}}catch(Exception ignored){}}
        }catch(Exception e){s.extras.put("gds_api_reachable","false");}
    }
    private void derive(ServerState s,long now){
        int offlineAfter=intCfg("offline_after_seconds",35,10,600);boolean fresh=now-s.lastHeartbeatMillis<=offlineAfter*1000L;boolean apiFallback=Boolean.parseBoolean(s.extras.getOrDefault("gds_api_reachable","false"));s.pluginReachable=fresh||apiFallback;s.extras.put("heartbeat_fresh",Boolean.toString(fresh));
        String m=s.mode==null?"":s.mode.toUpperCase(Locale.ROOT);String next;
        if(fresh){if(m.contains("MAINT"))next="MAINTENANCE";else if(m.contains("START"))next="STARTING";else if(m.contains("RESTART"))next="RESTARTING";else if("DEGRADED".equalsIgnoreCase(s.extras.get("gst_grade"))||"CRITICAL".equalsIgnoreCase(s.extras.get("gst_grade"))||Boolean.parseBoolean(s.extras.getOrDefault("gst_lag_active","false")))next="DEGRADED";else next="ONLINE";}
        else if(apiFallback&&s.minecraftReachable)next="DEGRADED";else if(s.minecraftReachable)next="DEGRADED";else if(s.plannedShutdown)next="OFFLINE";else next="OFFLINE";
        s.derivedState=next;
    }
    private void applyGscState(ServerState s){
        if(!gsc.enabled())return;
        String gid=cfg.getProperty("gsc.server_id."+s.id,"survival".equals(s.id)?"wild":s.id).trim();
        GscClient.Result r=gsc.server(gid); if(!r.ok())return;
        try{
            Map<String,Object> o=Json.obj(Json.parse(r.body()));
            Map<String,Object> gst=Json.obj(o.get("server_tools"));
            if(!gst.isEmpty()){String grade=Json.str(gst.get("grade"));if(!grade.isBlank())s.extras.put("gst_grade",grade);s.extras.put("gst_lag_active",Boolean.toString(Json.bool(gst.get("lag_active"),false)));s.extras.put("gst_incident_count",Long.toString(Json.lng(gst.get("incident_count"),0)));}
            Map<String,Object> mc=Json.obj(o.get("minecraft"));
            if(!mc.isEmpty()){long mx=Json.lng(mc.get("max"),0);if(mx>0&&mx<=Integer.MAX_VALUE)s.maxPlayers=(int)mx;long on=Json.lng(mc.get("online"),-1);if(on>=0&&on<=Integer.MAX_VALUE)s.online=(int)on;}
            Object mw=o.get("management_warnings");
            if(mw instanceof List<?> xs){StringJoiner j=new StringJoiner(",");for(Object x:xs){String v=String.valueOf(x);if(!v.isBlank())j.add(v);}s.extras.put("gsc_management_warnings",j.toString());}
            String st=Json.str(o.get("state"));
            if(!st.isBlank()){
                s.extras.put("gsc_state",st);
                boolean fresh=Boolean.parseBoolean(s.extras.getOrDefault("heartbeat_fresh","false"));
                boolean api=Boolean.parseBoolean(s.extras.getOrDefault("gds_api_reachable","false"));
                String grade=s.extras.getOrDefault("gst_grade","");
                boolean gstBad="DEGRADED".equalsIgnoreCase(grade)||"CRITICAL".equalsIgnoreCase(grade)||Boolean.parseBoolean(s.extras.getOrDefault("gst_lag_active","false"));
                boolean localHealthy=fresh&&api&&!gstBad;
                boolean substantive=false;
                Object dr=o.get("degradation_reasons");
                if(dr instanceof List<?> xs){for(Object x:xs){String v=String.valueOf(x);if(v.equals("minecraft_status")||v.equals("gds_api")||v.equals("servertools")){substantive=true;break;}}}
                // GSC <=4.1.4 could label a healthy server DEGRADED solely because RCON
                // was unavailable. Do not let a management-only warning override fresh
                // Minecraft/GDS/GST health. Lifecycle/terminal states still win.
                if(!"DEGRADED".equalsIgnoreCase(st)||!localHealthy||substantive)s.derivedState=st;
            }
        }catch(Exception ignored){}
    }
    private void maybeTransition(ServerState s){String prev=lastTransition.put(s.id,s.derivedState);if(Objects.equals(prev,s.derivedState))return;appendEvent(s,"state",String.valueOf(prev)+" -> "+s.derivedState);
        if("OFFLINE".equals(s.derivedState)&&!s.plannedShutdown&&System.currentTimeMillis()-agentStartedMillis>intCfg("startup_grace_seconds",30,0,600)*1000L&&offlineEpisodeNotified.add(s.id)){saveOfflineAlertState();if(discord!=null)discord.sendEvent("🔴 서버 오프라인 감지",s.name+" 서버가 응답하지 않습니다.\n마지막 heartbeat: "+age(s.lastHeartbeatMillis),0xE74C3C);}
        if("ONLINE".equals(s.derivedState)||"DEGRADED".equals(s.derivedState)){if(offlineEpisodeNotified.remove(s.id)){saveOfflineAlertState();if(discord!=null)discord.sendEvent("🟢 서버 응답 복구",s.name+" 서버 연결이 복구되었습니다.",0x2ECC71);}}
    }
    private void stateEndpoint(HttpExchange ex)throws IOException{if(!"GET".equalsIgnoreCase(ex.getRequestMethod())){reply(ex,405,"text/plain","method not allowed");return;}if(!authorizedRead(ex)){reply(ex,401,"application/json","{\"error\":\"unauthorized\"}");return;}reply(ex,200,"application/json; charset=utf-8",stateJson());}
    private boolean authorizedRead(HttpExchange ex){if(ex.getRemoteAddress().getAddress().isLoopbackAddress()&&boolCfg("allow_unauthenticated_loopback_state",true))return true;String want=cfg.getProperty("state_api_secret",sharedSecret).trim();String got=first(ex,"Authorization");if(got.startsWith("Bearer "))got=got.substring(7).trim();if(got.isBlank())got=first(ex,"X-Agent-Secret");return !want.isBlank()&&constant(want,got);}
    private String stateJson(){List<Object> list=new ArrayList<>();for(String id:configuredOrder()){ServerState s=states.get(id);if(s==null)continue;Map<String,Object>m=new LinkedHashMap<>();m.put("id",s.id);m.put("name",s.name);m.put("state",s.derivedState);m.put("mode",s.mode);m.put("last_heartbeat",s.lastHeartbeatMillis);m.put("minecraft_reachable",s.minecraftReachable);m.put("plugin_reachable",s.pluginReachable);m.put("heartbeat_fresh",Boolean.parseBoolean(s.extras.getOrDefault("heartbeat_fresh","false")));m.put("gds_api_reachable",Boolean.parseBoolean(s.extras.getOrDefault("gds_api_reachable","false")));m.put("online",s.online);m.put("max_players",s.maxPlayers);m.put("tps",finite(s.tps));m.put("mspt",finite(s.mspt));m.put("memory_percent",finite(s.memory));m.put("uptime_seconds",s.uptimeSeconds);m.put("version",s.version);m.put("gst",new LinkedHashMap<>(s.extras));list.add(m);}return JsonOut.stringify(Map.of("agent_version",VERSION,"time",System.currentTimeMillis(),"servers",list,"gsc_enabled",gsc.enabled()));}
    private String healthJson(){Map<String,Object> h=new LinkedHashMap<>();h.put("ok",true);h.put("version",VERSION);h.put("uptime_seconds",(System.currentTimeMillis()-agentStartedMillis)/1000);h.put("discord_configured",discord!=null&&discord.configured());h.put("gsc_enabled",gsc.enabled());h.put("servers",states.size());h.put("ingest_accepted",ingestAccepted.get());h.put("ingest_rejected",ingestRejected.get());h.put("last_ingest_reject_reason",lastIngestRejectReason);h.put("last_ingest_reject_time",lastIngestRejectMillis);return JsonOut.stringify(h);}
    private String buildStatusEmbed(){
        List<Object> fields=new ArrayList<>();for(String id:configuredOrder()){ServerState s=states.get(id);if(s==null)continue;fields.add(Map.of("name",iconForState(s.derivedState)+" "+s.name,"value",fieldValue(s),"inline",true));}
        Map<String,Object> e=new LinkedHashMap<>();e.put("title","📡 Geumyi Server Center");e.put("description","Agent `"+VERSION+"` · "+ZonedDateTime.now(zone).toLocalDateTime().withNano(0));e.put("color",overallColor());e.put("fields",fields);e.put("footer",Map.of("text","GSCM-ready · GSC Control API only"));return JsonOut.stringify(e);
    }
    private String fieldValue(ServerState s){StringBuilder b=new StringBuilder();b.append("상태: **").append(label(s.derivedState)).append("**\n");b.append("인원: `").append(s.online).append('/').append(s.maxPlayers>0?s.maxPlayers:"?").append("`\n");if(s.tps>0)b.append("TPS `").append(fmt(s.tps)).append("` · MSPT `").append(fmt(s.mspt)).append("`\n");if(s.memory>0)b.append("RAM `").append(fmt(s.memory)).append("%`\n");String g=s.extras.getOrDefault("gst_grade","");if(!g.isBlank())b.append("GST `").append(g).append("`").append(Boolean.parseBoolean(s.extras.getOrDefault("gst_lag_active","false"))?" ⚠":"").append("\n");if(s.extras.getOrDefault("gsc_management_warnings","").contains("rcon_unavailable"))b.append("관리: `RCON 제한`\n");if(Boolean.parseBoolean(s.extras.getOrDefault("heartbeat_fresh","false")))b.append("Heartbeat: ").append(age(s.lastHeartbeatMillis));else if(Boolean.parseBoolean(s.extras.getOrDefault("gds_api_reachable","false")))b.append("GDS API: 정상 · heartbeat 재연결 중");else b.append("Heartbeat: ").append(age(s.lastHeartbeatMillis));return b.toString();}
    private String buildStatsText(){StringBuilder b=new StringBuilder("**오늘 서버 통계**\n");LocalDate d=LocalDate.now(zone);for(String id:configuredOrder()){ServerState s=states.get(id);if(s==null)continue;MetricsLog.Summary x=metrics.summarize(d,id);b.append("\n**").append(s.name).append("**\n가동률 `").append(fmt(x.uptimePercent())).append("%` · 최고 동접 `").append(x.peakPlayers()).append("` · 평균 TPS `").append(fmt(x.avgTps())).append("`");}return b.toString();}
    private String buildBotInfo(){return "**GeumyiStatusAgent "+VERSION+"**\nHTTP `"+cfg.getProperty("listen.bind","127.0.0.1")+":"+cfg.getProperty("listen.port","8877")+"`\nGSC Control API `"+cfg.getProperty("gsc.base_url","http://127.0.0.1:8787/api/v1")+"`";}
    private void writeMetricsSafe(){long now=System.currentTimeMillis();if(now-lastMetricsWrite<60_000)return;lastMetricsWrite=now;for(ServerState s:states.values())try{metrics.append(s);}catch(Exception e){System.err.println("[GSA] metrics append: "+safe(e));}}
    private void dailySummarySafe(){if(!boolCfg("daily_summary.enabled",true)||discord==null||!discord.canEvents())return;ZonedDateTime z=ZonedDateTime.now(zone);int h=intCfg("daily_summary.hour",0,0,23),m=intCfg("daily_summary.minute",5,0,59);if(z.getHour()!=h||z.getMinute()!=m)return;LocalDate target=z.toLocalDate().minusDays(1);if(target.equals(lastSummaryDate))return;lastSummaryDate=target;StringBuilder b=new StringBuilder();for(String id:configuredOrder()){ServerState s=states.get(id);MetricsLog.Summary x=metrics.summarize(target,id);if(s!=null)b.append("**").append(s.name).append("** — 가동률 ").append(fmt(x.uptimePercent())).append("%, 최고 동접 ").append(x.peakPlayers()).append(", 평균 TPS ").append(fmt(x.avgTps())).append("\n");}discord.sendEvent("📊 일일 서버 요약 · "+target,b.toString(),0x3498DB);}
    private void appendEvent(ServerState s,String type,String msg){try{Path d=baseDir.resolve("data/events");Files.createDirectories(d);String line=Instant.now()+"\t"+s.id+"\t"+type+"\t"+msg.replace('\n',' ')+System.lineSeparator();Files.writeString(d.resolve("events-"+LocalDate.now(zone)+".log"),line,StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.APPEND);}catch(Exception ignored){}}
    private void loadOfflineAlertState(){try{if(!Files.exists(outageStateFile))return;for(String line:Files.readAllLines(outageStateFile,StandardCharsets.UTF_8)){line=line.trim();if(!line.isBlank())offlineEpisodeNotified.add(line);}}catch(Exception ignored){}}
    private synchronized void saveOfflineAlertState(){try{Files.write(outageStateFile,new TreeSet<>(offlineEpisodeNotified),StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING);}catch(Exception ignored){}}
    private void stop(){
        if(!stopping.compareAndSet(false,true))return;
        try{if(http!=null)http.stop(0);}catch(Exception ignored){}
        try{if(discord!=null)discord.close();}catch(Exception ignored){}
        scheduler.shutdownNow();
        if(httpExecutor!=null)httpExecutor.shutdownNow();
    }
    private void reply(HttpExchange ex,int status,String ct,String body)throws IOException{byte[] b=body.getBytes(StandardCharsets.UTF_8);ex.getResponseHeaders().set("Content-Type",ct);ex.getResponseHeaders().set("Cache-Control","no-store");ex.sendResponseHeaders(status,b.length);try(OutputStream out=ex.getResponseBody()){out.write(b);}}
    private List<String> configuredOrder(){
        LinkedHashSet<String> ordered=new LinkedHashSet<>();
        for(String s:cfg.getProperty("servers","playground,survival").split(",")){s=s.trim();if(!s.isBlank())ordered.add(s);}
        ArrayList<String> discovered=new ArrayList<>(states.keySet());
        discovered.sort(String.CASE_INSENSITIVE_ORDER);
        ordered.addAll(discovered);
        return new ArrayList<>(ordered);
    }
    private int intCfg(String k,int d,int min,int max){try{return Math.max(min,Math.min(max,Integer.parseInt(cfg.getProperty(k,Integer.toString(d)).trim())));}catch(Exception e){return d;}}
    private boolean boolCfg(String k,boolean d){return Boolean.parseBoolean(cfg.getProperty(k,Boolean.toString(d)).trim());}
    private int overallColor(){boolean crit=false,warn=false;for(ServerState s:states.values()){if("OFFLINE".equals(s.derivedState))crit=true;else if("DEGRADED".equals(s.derivedState)||"STARTING".equals(s.derivedState)||"MAINTENANCE".equals(s.derivedState))warn=true;}return crit?0xE74C3C:warn?0xF1C40F:0x2ECC71;}
    private static Object finite(double d){return Double.isFinite(d)?d:0.0;}private static double jsonDouble(Object v,double d){try{return v instanceof Number n?n.doubleValue():Double.parseDouble(String.valueOf(v));}catch(Exception e){return d;}}private static String fmt(double d){return Double.isFinite(d)?String.format(Locale.ROOT,"%.2f",d):"0.00";}
    private static String age(long t){if(t<=0)return"없음";long s=Math.max(0,(System.currentTimeMillis()-t)/1000);if(s<60)return s+"초 전";if(s<3600)return(s/60)+"분 전";return(s/3600)+"시간 전";}
    private static String iconForState(String s){return switch(String.valueOf(s)){case"ONLINE"->"🟢";case"DEGRADED"->"🟡";case"STARTING","RESTARTING"->"🔵";case"MAINTENANCE"->"🛠️";default->"🔴";};}
    private static String label(String s){return switch(String.valueOf(s)){case"ONLINE"->"온라인";case"DEGRADED"->"성능/연동 저하";case"STARTING"->"시작 중";case"RESTARTING"->"재시작 중";case"MAINTENANCE"->"점검 중";default->"오프라인";};}
    private static int colorFor(String e){e=e.toLowerCase(Locale.ROOT);if(e.contains("recover")||e.contains("start"))return 0x2ECC71;if(e.contains("lag")||e.contains("performance")||e.contains("warn"))return 0xF1C40F;if(e.contains("shutdown")||e.contains("offline")||e.contains("error")||e.contains("crash"))return 0xE74C3C;return 0x3498DB;}
    private static String first(HttpExchange ex,String k){String v=ex.getRequestHeaders().getFirst(k);return v==null?"":v.trim();}
    private static boolean constant(String a,String b){return a!=null&&b!=null&&MessageDigest.isEqual(a.getBytes(StandardCharsets.UTF_8),b.getBytes(StandardCharsets.UTF_8));}
    private static String hmac(String secret,String data)throws Exception{Mac m=Mac.getInstance("HmacSHA256");m.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8),"HmacSHA256"));StringBuilder b=new StringBuilder();for(byte x:m.doFinal(data.getBytes(StandardCharsets.UTF_8)))b.append(String.format("%02x",x&255));return b.toString();}
    private static String safe(Throwable t){String s=t.getMessage();return s==null?t.getClass().getSimpleName():s;}
}
