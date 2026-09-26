package kr.geumyi.statusagent;

import java.math.BigInteger;
import java.net.URI;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Supplier;

final class DiscordBot implements AutoCloseable {
    private record Pending(String action,String server,String userId,String userName,long expiresAt) {}

    private final HttpClient http;
    private final Properties cfg;
    private final Path stateFile;
    private final Supplier<String> statusEmbed;
    private final Supplier<String> statsText;
    private final Supplier<String> botInfo;
    private final GscClient gsc;
    private final String token,guildId,statusChannelId,eventsChannelId,apiBase,gatewayBase;
    private final boolean commandsEnabled,gatewayEnabled;

    // Keep Gateway timing independent from REST/GSC latency.
    private final ScheduledExecutorService gatewayExec;
    private final ExecutorService ioExec;
    private final AtomicBoolean reconnectQueued=new AtomicBoolean();
    private final AtomicBoolean connecting=new AtomicBoolean();
    private final AtomicBoolean statusWorkerRunning=new AtomicBoolean();
    private final Map<String,Pending> pending=new ConcurrentHashMap<>();

    private volatile java.net.http.WebSocket ws;
    private volatile boolean running,heartbeatAck=true;
    private volatile long sequence=-1;
    private volatile String sessionId="",resumeGatewayUrl="",applicationId="",botUserId="",botUsername="",statusMessageId="";
    private volatile ScheduledFuture<?> heartbeatFuture;
    private volatile String latestStatusEmbed="";
    private final StringBuilder inbound=new StringBuilder();

    DiscordBot(Properties cfg,Path stateFile,Supplier<String> statusEmbed,Supplier<String> statsText,Supplier<String> botInfo,GscClient gsc){
        this.cfg=cfg; this.stateFile=stateFile; this.statusEmbed=statusEmbed; this.statsText=statsText; this.botInfo=botInfo; this.gsc=gsc;
        token=cfg.getProperty("discord.bot_token","").trim(); guildId=cfg.getProperty("discord.guild_id","").trim(); statusChannelId=cfg.getProperty("discord.status_channel_id","").trim(); eventsChannelId=cfg.getProperty("discord.events_channel_id","").trim();
        apiBase=cfg.getProperty("discord.api_base","https://discord.com/api/v10").trim(); gatewayBase=cfg.getProperty("discord.gateway_url","wss://gateway.discord.gg/?v=10&encoding=json").trim();
        commandsEnabled=bool("discord.slash_commands",true); gatewayEnabled=bool("discord.gateway_enabled",true);
        gatewayExec=Executors.newSingleThreadScheduledExecutor(r->{Thread t=new Thread(r,"GSA-Gateway");t.setDaemon(true);return t;});
        ioExec=Executors.newVirtualThreadPerTaskExecutor();
        http=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(8)).version(HttpClient.Version.HTTP_1_1).build();
        loadState();
    }

    boolean configured(){return !token.isBlank();}
    boolean canStatus(){return configured()&&!statusChannelId.isBlank();}
    boolean canEvents(){return configured()&&!eventsChannelId.isBlank();}
    String applicationId(){return applicationId;}
    String botUsername(){return botUsername;}

    void start(){
        if(!configured()){System.out.println("[GSA] Discord token not configured; Discord disabled.");return;}
        running=true;
        gatewayExec.scheduleAtFixedRate(this::cleanupPending,30,30,TimeUnit.SECONDS);
        ioExec.execute(()->{
            try{
                identifyRest();
                if(commandsEnabled&&!guildId.isBlank())registerCommands();
                if(gatewayEnabled)connectGateway(false);
            }catch(Exception e){System.err.println("[GSA] Discord init failed: "+safe(e));}
        });
    }

    private void identifyRest() throws Exception {
        var r=api("GET","/users/@me",null);
        if(r.statusCode()/100!=2)throw new IllegalStateException("Discord /users/@me HTTP "+r.statusCode());
        Map<String,Object> o=Json.obj(Json.parse(r.body()));
        botUserId=Json.str(o.get("id")); botUsername=Json.str(o.get("username")); applicationId=botUserId;
        saveState();
        System.out.println("[GSA] Discord bot authenticated: "+botUsername+" ("+botUserId+")");
    }

    private void registerCommands(){
        List<Map<String,Object>> commands=new ArrayList<>();
        commands.add(cmd("서버상태","등록된 서버 통합 현재 상태",List.of()));
        commands.add(cmd("서버통계","오늘 서버 통계를 확인",List.of()));
        commands.add(cmd("봇정보","GeumyiStatusAgent 정보",List.of()));
        commands.add(cmd("서버헬스","GSC/GST 서버 진단 확인",List.of(serverChoice())));
        commands.add(cmd("서버시작","서버 시작 (관리자)",List.of(serverChoice())));
        commands.add(cmd("서버종료","안전 종료 요청 (관리자)",List.of(serverChoice())));
        commands.add(cmd("서버재시작","안전 재시작 요청 (관리자)",List.of(serverChoice())));
        try{
            // Discord supports bulk overwrite for guild commands. One request avoids
            // repeated create/upsert calls on every Agent restart and removes stale commands.
            var r=api("PUT","/applications/"+applicationId+"/guilds/"+guildId+"/commands",JsonOut.stringify(commands));
            if(r.statusCode()/100!=2) logRest("command bulk overwrite",r);
            else System.out.println("[GSA] Slash commands synchronized ("+commands.size()+")");
        }catch(Exception e){System.err.println("[GSA] command synchronization failed: "+safe(e));}
    }

    private static Map<String,Object> cmd(String name,String desc,List<Map<String,Object>> opts){
        Map<String,Object> m=new LinkedHashMap<>();m.put("name",name);m.put("description",desc);m.put("type",1);m.put("contexts",List.of(0));if(!opts.isEmpty())m.put("options",opts);return m;
    }
    private Map<String,Object> serverChoice(){
        List<Map<String,Object>> choices=new ArrayList<>();
        LinkedHashSet<String> ids=new LinkedHashSet<>();
        for(String raw:cfg.getProperty("servers","playground,survival").split(",")){
            String id=raw.trim();
            if(id.isBlank()||!ids.add(id))continue;
            String gscId=cfg.getProperty("gsc.server_id."+id,"survival".equalsIgnoreCase(id)?"wild":id).trim();
            if(gscId.isBlank())gscId=id;
            String name=cfg.getProperty("server."+id+".name",id).trim();
            if(name.isBlank())name=id;
            if(name.length()>100)name=name.substring(0,100);
            choices.add(Map.of("name",name,"value",gscId));
            if(choices.size()>=25)break;
        }
        if(choices.isEmpty()){
            choices=List.of(Map.of("name","금이 야생","value","wild"),Map.of("name","금이 놀이터","value","playground"));
        }
        return Map.of("type",3,"name","서버","description","대상 서버","required",true,"choices",choices);
    }

    void updateStatus(String embedJson){
        if(!canStatus()||!running)return;
        latestStatusEmbed=embedJson;
        startStatusWorker();
    }

    private void startStatusWorker(){
        if(!statusWorkerRunning.compareAndSet(false,true))return;
        ioExec.execute(()->{
            String sent=null;
            try{
                while(running){
                    String next=latestStatusEmbed;
                    if(next==null||next.isBlank()||Objects.equals(next,sent))break;
                    sent=next;
                    sendStatusNow(next);
                }
            }finally{
                statusWorkerRunning.set(false);
                String newest=latestStatusEmbed;
                if(running&&newest!=null&&!newest.isBlank()&&!Objects.equals(newest,sent))startStatusWorker();
            }
        });
    }

    private void sendStatusNow(String embedJson){
        try{
            String body="{\"embeds\":["+embedJson+"]}"; HttpResponse<String> r;

            // Keep one persistent Discord status message. If the state file was lost
            // or migrated, recover the newest status board created by this bot before
            // creating another message.
            if(statusMessageId.isBlank()){
                String recovered=findExistingStatusMessage();
                if(!recovered.isBlank()){statusMessageId=recovered;saveState();}
            }

            if(!statusMessageId.isBlank()){
                r=api("PATCH","/channels/"+statusChannelId+"/messages/"+statusMessageId,body);
                if(r.statusCode()/100==2)return;
                if(r.statusCode()==404){
                    statusMessageId="";
                    saveState();
                }else{
                    // Important: a transient PATCH failure (429/5xx/permission/network)
                    // must NOT create a duplicate status message. Retry on the next
                    // refresh while keeping the same message id.
                    logRest("status update",r);
                    return;
                }
            }

            r=api("POST","/channels/"+statusChannelId+"/messages",body);
            if(r.statusCode()/100==2){
                String created="";
                try{
                    Map<String,Object> o=Json.obj(Json.parse(r.body()));
                    created=Json.str(o.get("id"));
                }catch(Exception ignored){}
                if(created.isBlank())created=findExistingStatusMessage();
                if(!created.isBlank()){statusMessageId=created;saveState();}
                else System.err.println("[GSA] Discord status create succeeded but message id was unavailable; refusing blind duplicate creation until next recovery scan.");
            }else logRest("status create",r);
        }catch(Exception e){System.err.println("[GSA] status update failed: "+safe(e));}
    }

    private String findExistingStatusMessage(){
        if(botUserId.isBlank()||statusChannelId.isBlank())return"";
        try{
            HttpResponse<String> r=api("GET","/channels/"+statusChannelId+"/messages?limit=50",null);
            if(r.statusCode()/100!=2){logRest("status recovery scan",r);return"";}
            for(Object raw:Json.arr(Json.parse(r.body()))){
                Map<String,Object> m=Json.obj(raw);
                Map<String,Object> author=Json.obj(m.get("author"));
                if(!botUserId.equals(Json.str(author.get("id"))))continue;
                for(Object eraw:Json.arr(m.get("embeds"))){
                    Map<String,Object> e=Json.obj(eraw);
                    if("📡 Geumyi Server Center".equals(Json.str(e.get("title")))){
                        String id=Json.str(m.get("id"));
                        if(!id.isBlank())return id;
                    }
                }
            }
        }catch(Exception e){System.err.println("[GSA] status recovery scan failed: "+safe(e));}
        return"";
    }

    void sendEvent(String title,String description,int color){
        if(!canEvents()||!running)return;
        ioExec.execute(()->{
            try{
                String body=JsonOut.stringify(Map.of("embeds",List.of(Map.of("title",clip(title,256),"description",clip(description,3800),"color",color))));
                var r=api("POST","/channels/"+eventsChannelId+"/messages",body);
                if(r.statusCode()/100!=2)logRest("event",r);
            }catch(Exception e){System.err.println("[GSA] event send failed: "+safe(e));}
        });
    }

    private void connectGateway(boolean resume){
        if(!running||!gatewayEnabled||!connecting.compareAndSet(false,true))return;
        try{
            URI uri=URI.create(resume&&!resumeGatewayUrl.isBlank()?resumeGatewayUrl+"/?v=10&encoding=json":gatewayBase);
            http.newWebSocketBuilder().connectTimeout(Duration.ofSeconds(10)).buildAsync(uri,new Listener()).whenComplete((w,e)->{
                connecting.set(false);
                if(e!=null){System.err.println("[GSA] Gateway connect failed: "+safe(e));scheduleReconnect();}
                else ws=w;
            });
        }catch(Exception e){connecting.set(false);scheduleReconnect();}
    }

    private void gatewayMessage(String text){
        try{
            Map<String,Object> p=Json.obj(Json.parse(text)); int op=Json.integer(p.get("op"),-1); Object s=p.get("s"); if(s!=null)sequence=Json.lng(s,sequence);
            Map<String,Object> d=Json.obj(p.get("d"));
            if(op==10){long interval=Json.lng(d.get("heartbeat_interval"),45000);startHeartbeat(interval); if(!sessionId.isBlank())sendResume();else sendIdentify();return;}
            if(op==11){heartbeatAck=true;return;}
            if(op==7){reconnectNow(true);return;}
            if(op==9){sessionId="";resumeGatewayUrl="";reconnectLater(1200);return;}
            if(op!=0)return;
            String t=Json.str(p.get("t"));
            if("READY".equals(t)){
                sessionId=Json.str(d.get("session_id"));resumeGatewayUrl=Json.str(d.get("resume_gateway_url"));Map<String,Object> u=Json.obj(d.get("user"));
                if(!u.isEmpty()){botUserId=Json.str(u.get("id"));botUsername=Json.str(u.get("username"));}
                saveState();setPresence();System.out.println("[GSA] Gateway READY");
            }else if("INTERACTION_CREATE".equals(t)) handleInteraction(d);
        }catch(Exception e){System.err.println("[GSA] Gateway payload error: "+safe(e));}
    }

    private void startHeartbeat(long ms){
        if(heartbeatFuture!=null)heartbeatFuture.cancel(false);
        heartbeatAck=true;
        long interval=Math.max(1000,ms);
        heartbeatFuture=gatewayExec.scheduleAtFixedRate(()->{
            if(!heartbeatAck){System.err.println("[GSA] Gateway heartbeat ACK missed");reconnectNow(true);return;}
            heartbeatAck=false;sendGateway("{\"op\":1,\"d\":"+(sequence<0?"null":Long.toString(sequence))+"}");
        },interval,interval,TimeUnit.MILLISECONDS);
    }
    private void sendIdentify(){sendGateway(JsonOut.stringify(Map.of("op",2,"d",Map.of("token",token,"intents",1,"properties",Map.of("os",System.getProperty("os.name"),"browser","geumyi-status-agent","device","geumyi-status-agent")))));}
    private void sendResume(){sendGateway(JsonOut.stringify(Map.of("op",6,"d",Map.of("token",token,"session_id",sessionId,"seq",sequence))));}
    private void setPresence(){sendGateway(JsonOut.stringify(Map.of("op",3,"d",Map.of("since",0,"activities",List.of(Map.of("name","Geumyi Server Center","type",3)),"status","online","afk",false))));}
    private void sendGateway(String s){var w=ws;if(w!=null)w.sendText(s,true);}

    private void handleInteraction(Map<String,Object> i){
        int type=Json.integer(i.get("type"),0); String id=Json.str(i.get("id")), itoken=Json.str(i.get("token")); Map<String,Object> data=Json.obj(i.get("data"));
        Member member=member(i);
        if(type==2){
            String name=Json.str(data.get("name"));String server=option(data,"서버");
            switch(name){
                case "서버상태" -> respond(id,itoken,statusPlain(),true);
                case "서버통계" -> respond(id,itoken,statsText.get(),true);
                case "봇정보" -> respond(id,itoken,botInfo.get()+"\nDiscord: "+(botUsername.isBlank()?"연결 중":botUsername)+"\nGSC: "+(gsc.enabled()?"사용":"비활성"),true);
                case "서버헬스" -> healthCommand(id,itoken,server,member);
                case "서버시작" -> adminCommand(id,itoken,"start",server,member);
                case "서버종료" -> adminCommand(id,itoken,"stop",server,member);
                case "서버재시작" -> adminCommand(id,itoken,"restart",server,member);
                default -> respond(id,itoken,"알 수 없는 명령입니다.",true);
            }
        } else if(type==3){String custom=Json.str(data.get("custom_id"));handleButton(id,itoken,custom,member);}
    }

    private void healthCommand(String id,String tok,String server,Member m){
        if(!canInspect(m)){respond(id,tok,"권한이 없습니다. Moderator/Admin 권한이 필요합니다.",true);return;}
        final String target=server.isBlank()?"wild":server;
        deferReply(id,tok,true).whenComplete((ok,err)->{
            if(err!=null||!Boolean.TRUE.equals(ok))return;
            ioExec.execute(()->{
                GscClient.Result r=gsc.health(target);
                editOriginal(tok,r.ok()?"`"+target+"` 진단\n```json\n"+clip(r.body(),1700)+"\n```":"GSC 진단 실패: "+r.error());
            });
        });
    }

    private void adminCommand(String id,String tok,String action,String server,Member m){
        if(!canManage(m)){respond(id,tok,"권한이 없습니다. Discord 관리자 또는 Agent 관리 권한이 필요합니다.",true);return;}
        if(server.isBlank()){respond(id,tok,"서버를 선택해주세요.",true);return;}
        String nonce=UUID.randomUUID().toString().replace("-","").substring(0,12);String cid="gsc:"+action+":"+server+":"+nonce;
        pending.put(cid,new Pending(action,server,m.userId,m.userName,System.currentTimeMillis()+60_000));
        String label=switch(action){case"start"->"시작";case"stop"->"종료";default->"재시작";};
        Map<String,Object> confirm=Map.of("type",2,"style",4,"label",label+" 확인","custom_id",cid);
        Map<String,Object> cancel=Map.of("type",2,"style",2,"label","취소","custom_id","cancel:"+cid);
        Map<String,Object> row=Map.of("type",1,"components",List.of(confirm,cancel));
        Map<String,Object> data=Map.of("content","⚠ **"+displayServer(server)+" 서버 "+label+"** 요청입니다. 60초 안에 확인해주세요.","flags",64,"components",List.of(row));
        callback(id,tok,JsonOut.stringify(Map.of("type",4,"data",data)));
    }

    private void handleButton(String id,String tok,String custom,Member m){
        if(custom.startsWith("cancel:")){
            String key=custom.substring(7);Pending cp=pending.get(key);
            if(cp==null||cp.expiresAt<System.currentTimeMillis()){pending.remove(key);updateInteraction(id,tok,"요청이 만료됐습니다.");return;}
            if(!cp.userId.equals(m.userId)){respond(id,tok,"이 요청을 만든 사용자만 취소할 수 있습니다.",true);return;}
            pending.remove(key);updateInteraction(id,tok,"취소했습니다.");return;
        }
        Pending p=pending.remove(custom);
        if(p==null||p.expiresAt<System.currentTimeMillis()){updateInteraction(id,tok,"요청이 만료됐습니다. 다시 실행해주세요.");return;}
        if(!p.userId.equals(m.userId)){respond(id,tok,"이 확인 버튼은 명령을 요청한 사용자만 사용할 수 있습니다.",true);return;}
        if(!canManage(m)){updateInteraction(id,tok,"권한이 없어 실행하지 않았습니다.");return;}

        // Acknowledge the button immediately, then call GSC off the Gateway path.
        deferUpdate(id,tok).whenComplete((ok,err)->{
            if(err!=null||!Boolean.TRUE.equals(ok))return;
            ioExec.execute(()->{
                int countdown=switch(p.action){case"stop","restart"->30;default->0;};
                String req="discord-"+id;
                GscClient.Result r=gsc.action(p.server,p.action,countdown,m.userId,m.userName,req);
                if(r.ok())editOriginal(tok,"✅ **"+displayServer(p.server)+"** `"+p.action+"` 작업을 GSC에 전달했습니다.\n"+clip(r.body(),700));
                else editOriginal(tok,"❌ GSC 요청 실패: "+r.error()+"\n"+clip(r.body(),500));
            });
        });
    }

    private void cleanupPending(){
        long now=System.currentTimeMillis();
        pending.entrySet().removeIf(e->e.getValue().expiresAt<now);
    }

    private record Member(String userId,String userName,Set<String> roles,boolean administrator,boolean manageGuild){}
    private Member member(Map<String,Object> i){
        Map<String,Object> m=Json.obj(i.get("member"));Map<String,Object> u=Json.obj(m.get("user"));Set<String> roles=new HashSet<>();
        for(Object x:Json.arr(m.get("roles")))roles.add(Json.str(x));BigInteger perms=BigInteger.ZERO;
        try{perms=new BigInteger(Json.str(m.get("permissions")));}catch(Exception ignored){}
        return new Member(Json.str(u.get("id")),Json.str(u.get("username")),roles,perms.testBit(3),perms.testBit(5));
    }
    private boolean canManage(Member m){if(m==null)return false;if(csvSet("discord.owner_user_ids").contains(m.userId))return true;if(m.administrator)return true;Set<String>a=csvSet("discord.admin_role_ids");for(String r:m.roles)if(a.contains(r))return true;return false;}
    private boolean canInspect(Member m){if(canManage(m))return true;if(m!=null&&m.manageGuild)return true;Set<String>a=csvSet("discord.moderator_role_ids");if(m!=null)for(String r:m.roles)if(a.contains(r))return true;return false;}
    private Set<String> csvSet(String key){Set<String>s=new HashSet<>();for(String x:cfg.getProperty(key,"").split(",")){x=x.trim();if(!x.isBlank())s.add(x);}return s;}
    private static String option(Map<String,Object>d,String name){for(Object x:Json.arr(d.get("options"))){Map<String,Object>o=Json.obj(x);if(name.equals(Json.str(o.get("name"))))return Json.str(o.get("value"));}return"";}

    private String statusPlain(){
        try{
            Object parsed=Json.parse("{"+"\"x\":"+statusEmbed.get()+"}");Map<String,Object>e=Json.obj(Json.obj(parsed).get("x"));StringBuilder b=new StringBuilder("**Geumyi Server 상태**\n");
            for(Object f:Json.arr(e.get("fields"))){Map<String,Object>fm=Json.obj(f);b.append("\n**").append(Json.str(fm.get("name"))).append("**\n").append(Json.str(fm.get("value")));}
            return clip(b.toString(),1900);
        }catch(Exception ex){return "상태판 생성 중입니다.";}
    }

    private void respond(String id,String tok,String content,boolean ephemeral){callback(id,tok,JsonOut.stringify(Map.of("type",4,"data",Map.of("content",clip(content,1950),"flags",ephemeral?64:0))));}
    private void updateInteraction(String id,String tok,String content){callback(id,tok,JsonOut.stringify(Map.of("type",7,"data",Map.of("content",clip(content,1950),"components",List.of()))));}
    private CompletableFuture<Boolean> deferReply(String id,String tok,boolean ephemeral){return callback(id,tok,JsonOut.stringify(Map.of("type",5,"data",Map.of("flags",ephemeral?64:0))));}
    private CompletableFuture<Boolean> deferUpdate(String id,String tok){return callback(id,tok,"{\"type\":6}");}

    private CompletableFuture<Boolean> callback(String id,String tok,String payload){
        try{
            HttpRequest req=HttpRequest.newBuilder(URI.create(apiBase+"/interactions/"+id+"/"+tok+"/callback"))
                    .timeout(Duration.ofSeconds(5)).header("Content-Type","application/json; charset=UTF-8")
                    .POST(HttpRequest.BodyPublishers.ofString(payload,StandardCharsets.UTF_8)).build();
            return http.sendAsync(req,HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8)).handle((r,e)->{
                if(e!=null){System.err.println("[GSA] interaction response failed: "+safe(e));return false;}
                if(r.statusCode()/100!=2){logRest("interaction",r);return false;}
                return true;
            });
        }catch(Exception e){System.err.println("[GSA] interaction response failed: "+safe(e));return CompletableFuture.completedFuture(false);}
    }

    private void editOriginal(String tok,String content){
        String body=JsonOut.stringify(Map.of("content",clip(content,1950),"components",List.of()));
        try{
            HttpRequest req=HttpRequest.newBuilder(URI.create(apiBase+"/webhooks/"+applicationId+"/"+tok+"/messages/@original"))
                    .timeout(Duration.ofSeconds(8)).header("Content-Type","application/json; charset=UTF-8")
                    .method("PATCH",HttpRequest.BodyPublishers.ofString(body,StandardCharsets.UTF_8)).build();
            http.sendAsync(req,HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8)).thenAccept(r->{if(r.statusCode()/100!=2)logRest("interaction edit",r);}).exceptionally(e->{System.err.println("[GSA] interaction edit failed: "+safe(e));return null;});
        }catch(Exception e){System.err.println("[GSA] interaction edit failed: "+safe(e));}
    }

    private HttpResponse<String> api(String method,String path,String body)throws Exception{
        HttpRequest.Builder b=HttpRequest.newBuilder(URI.create(apiBase+path)).timeout(Duration.ofSeconds(10)).header("Authorization","Bot "+token).header("User-Agent","GeumyiStatusAgent/0.5.3");
        if(body!=null)b.header("Content-Type","application/json; charset=UTF-8");
        b.method(method,body==null?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofString(body,StandardCharsets.UTF_8));
        return http.send(b.build(),HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
    }
    private void logRest(String what,HttpResponse<String>r){System.err.println("[GSA] Discord "+what+" HTTP "+r.statusCode()+" "+clip(r.body()));}

    private void reconnectNow(boolean resume){
        var w=ws;ws=null;
        if(w!=null)try{w.abort();}catch(Exception ignored){}
        connecting.set(false);
        connectGateway(resume);
    }
    private void reconnectLater(long ms){gatewayExec.schedule(()->connectGateway(!sessionId.isBlank()),ms,TimeUnit.MILLISECONDS);}
    private void scheduleReconnect(){if(!running||!reconnectQueued.compareAndSet(false,true))return;gatewayExec.schedule(()->{reconnectQueued.set(false);connectGateway(!sessionId.isBlank());},3,TimeUnit.SECONDS);}

    private void loadState(){
        statusMessageId=cfg.getProperty("discord.status_message_id","").trim();
        try{
            if(Files.exists(stateFile)){
                Properties p=new Properties();try(var in=Files.newInputStream(stateFile)){p.load(in);}
                statusMessageId=p.getProperty("discord.status_message_id",statusMessageId).trim();sessionId=p.getProperty("discord.session_id","");resumeGatewayUrl=p.getProperty("discord.resume_gateway_url","");
            }
        }catch(Exception ignored){}
    }
    private synchronized void saveState(){
        try{
            Properties p=new Properties();p.setProperty("discord.status_message_id",statusMessageId);p.setProperty("discord.session_id",sessionId);p.setProperty("discord.resume_gateway_url",resumeGatewayUrl);p.setProperty("agent.version","0.5.4");
            Path parent=stateFile.toAbsolutePath().getParent();Files.createDirectories(parent);Path tmp=parent.resolve(stateFile.getFileName().toString()+".tmp");
            try(var out=Files.newOutputStream(tmp,StandardOpenOption.CREATE,StandardOpenOption.TRUNCATE_EXISTING,StandardOpenOption.WRITE)){p.store(out,"GeumyiStatusAgent state");}
            try{Files.move(tmp,stateFile,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);}catch(Exception atomic){Files.move(tmp,stateFile,StandardCopyOption.REPLACE_EXISTING);}
        }catch(Exception e){System.err.println("[GSA] state save failed: "+safe(e));}
    }

    private boolean bool(String k,boolean d){return Boolean.parseBoolean(cfg.getProperty(k,Boolean.toString(d)).trim());}
    private String displayServer(String s){
        for(String raw:cfg.getProperty("servers","playground,survival").split(",")){
            String id=raw.trim();
            if(id.isBlank())continue;
            String gscId=cfg.getProperty("gsc.server_id."+id,"survival".equalsIgnoreCase(id)?"wild":id).trim();
            if(gscId.isBlank())gscId=id;
            if(gscId.equalsIgnoreCase(s)){
                String name=cfg.getProperty("server."+id+".name",id).trim();
                return name.isBlank()?s:name;
            }
        }
        return"wild".equalsIgnoreCase(s)?"금이 야생":"playground".equalsIgnoreCase(s)?"금이 놀이터":s;
    }
    private static String clip(String s){return clip(s,500);}
    private static String clip(String s,int n){if(s==null)return"";s=s.replace("\u0000","");return s.length()<=n?s:s.substring(0,n);}
    private static String safe(Throwable t){String s=t.getMessage();return s==null?t.getClass().getSimpleName():s;}

    @Override public void close(){
        running=false;
        if(heartbeatFuture!=null)heartbeatFuture.cancel(false);
        pending.clear();
        var w=ws;
        if(w!=null)try{w.sendClose(1000,"shutdown").get(1200,TimeUnit.MILLISECONDS);}catch(Exception ignored){}
        gatewayExec.shutdownNow();
        ioExec.shutdownNow();
    }

    private final class Listener implements java.net.http.WebSocket.Listener{
        @Override public void onOpen(java.net.http.WebSocket w){ws=w;connecting.set(false);reconnectQueued.set(false);w.request(1);}
        @Override public CompletionStage<?> onText(java.net.http.WebSocket w,CharSequence data,boolean last){synchronized(inbound){inbound.append(data);if(last){String s=inbound.toString();inbound.setLength(0);gatewayMessage(s);}}w.request(1);return null;}
        @Override public CompletionStage<?> onClose(java.net.http.WebSocket w,int code,String reason){ws=null;connecting.set(false);if(running)scheduleReconnect();return null;}
        @Override public void onError(java.net.http.WebSocket w,Throwable error){ws=null;connecting.set(false);if(running)scheduleReconnect();}
    }
}
