double jDouble(Object? value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

int jInt(Object? value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

bool jBool(Object? value, [bool fallback = false]) => value is bool ? value : fallback;
String jString(Object? value, [String fallback = '']) => value?.toString() ?? fallback;
Map<String, dynamic> jMap(Object? value) => value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Map<String, dynamic>> jMapList(Object? value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false)
    : const [];
List<String> jStrings(Object? value) => value is List ? value.map((e) => e.toString()).toList(growable: false) : const [];

class GscInfo {
  const GscInfo({required this.version, required this.apiVersion, required this.features, required this.mobile});
  final String version;
  final int apiVersion;
  final List<String> features;
  final MobileStatus mobile;

  factory GscInfo.fromJson(Map<String, dynamic> json) => GscInfo(
        version: jString(json['gsc_version']),
        apiVersion: jInt(json['api_version']),
        features: jStrings(json['features']),
        mobile: MobileStatus.fromJson(jMap(json['mobile'])),
      );
}

class PairingResult {
  const PairingResult({required this.ok, required this.deviceId, required this.deviceToken});
  final bool ok;
  final String deviceId;
  final String deviceToken;
  factory PairingResult.fromJson(Map<String, dynamic> json) => PairingResult(
        ok: jBool(json['ok']),
        deviceId: jString(json['device_id']),
        deviceToken: jString(json['device_token']),
      );
}

class PairingSummary {
  const PairingSummary({required this.active, required this.code, required this.expires, required this.remainingSeconds, required this.claimUri});
  final bool active;
  final String code;
  final DateTime? expires;
  final int remainingSeconds;
  final String claimUri;
  factory PairingSummary.fromJson(Map<String, dynamic> json) => PairingSummary(
        active: jBool(json['active']),
        code: jString(json['code']),
        expires: DateTime.tryParse(jString(json['expires'])),
        remainingSeconds: jInt(json['remaining_seconds']),
        claimUri: jString(json['claim_uri']),
      );
}

class TrustedDevice {
  const TrustedDevice({required this.id, required this.name, required this.created, required this.lastSeen, required this.revoked, required this.role});
  final String id;
  final String name;
  final DateTime? created;
  final DateTime? lastSeen;
  final bool revoked;
  final String role;
  factory TrustedDevice.fromJson(Map<String, dynamic> json) => TrustedDevice(
        id: jString(json['id']),
        name: jString(json['name']),
        created: DateTime.tryParse(jString(json['created'])),
        lastSeen: DateTime.tryParse(jString(json['last_seen'])),
        revoked: jBool(json['revoked']),
        role: jString(json['role'], 'admin'),
      );
}

class MobileStatus {
  const MobileStatus({required this.enabled, required this.port, required this.addresses, required this.preferredUrl, required this.pairingTtlSeconds, required this.pairing, required this.trustedDevices});
  final bool enabled;
  final int port;
  final List<String> addresses;
  final String preferredUrl;
  final int pairingTtlSeconds;
  final PairingSummary pairing;
  final List<TrustedDevice> trustedDevices;
  factory MobileStatus.fromJson(Map<String, dynamic> json) => MobileStatus(
        enabled: jBool(json['enabled']),
        port: jInt(json['port'], 8787),
        addresses: jStrings(json['addresses']),
        preferredUrl: jString(json['preferred_url']),
        pairingTtlSeconds: jInt(json['pairing_ttl_seconds'], 300),
        pairing: PairingSummary.fromJson(jMap(json['pairing'])),
        trustedDevices: jMapList(json['trusted_devices']).map(TrustedDevice.fromJson).toList(growable: false),
      );
}

class HostStatus {
  const HostStatus({required this.hostname, required this.os, required this.uptime, required this.cpuPercent, required this.ramUsedGb, required this.ramTotalGb, required this.diskFreeGb, required this.diskTotalGb, required this.ipv4});
  final String hostname;
  final String os;
  final String uptime;
  final double cpuPercent;
  final double ramUsedGb;
  final double ramTotalGb;
  final double diskFreeGb;
  final double diskTotalGb;
  final List<String> ipv4;
  double get ramPercent => ramTotalGb <= 0 ? 0 : (ramUsedGb / ramTotalGb * 100).clamp(0, 100).toDouble();
  double get diskUsedGb => (diskTotalGb - diskFreeGb).clamp(0, double.infinity).toDouble();
  double get diskPercent => diskTotalGb <= 0 ? 0 : (diskUsedGb / diskTotalGb * 100).clamp(0, 100).toDouble();
  factory HostStatus.fromJson(Map<String, dynamic> json) => HostStatus(
        hostname: jString(json['hostname']),
        os: jString(json['os']),
        uptime: jString(json['uptime']),
        cpuPercent: jDouble(json['cpu_percent']),
        ramUsedGb: jDouble(json['ram_used_gb']),
        ramTotalGb: jDouble(json['ram_total_gb']),
        diskFreeGb: jDouble(json['disk_free_gb']),
        diskTotalGb: jDouble(json['disk_total_gb']),
        ipv4: jStrings(json['ipv4']),
      );
}

class MinecraftStatus {
  const MinecraftStatus({required this.ok, required this.version, required this.online, required this.max, required this.latencyMs, required this.players, required this.motd, required this.reportedMax, required this.configuredMax, required this.maxSource});
  final bool ok;
  final String version;
  final int online;
  final int max;
  final int latencyMs;
  final List<String> players;
  final String motd;
  final int reportedMax;
  final int configuredMax;
  final String maxSource;
  factory MinecraftStatus.fromJson(Map<String, dynamic> json) => MinecraftStatus(
        ok: jBool(json['ok']),
        version: jString(json['version']),
        online: jInt(json['online']),
        max: jInt(json['max']),
        latencyMs: jInt(json['latency_ms']),
        players: jStrings(json['players']),
        motd: jString(json['motd']),
        reportedMax: jInt(json['reported_max']),
        configuredMax: jInt(json['configured_max']),
        maxSource: jString(json['max_source']),
      );
}

class JavaStatus {
  const JavaStatus({required this.pid, required this.workingSetMb, required this.privateMb, required this.threads, required this.startTime});
  final int pid;
  final double workingSetMb;
  final double privateMb;
  final int threads;
  final DateTime? startTime;
  factory JavaStatus.fromJson(Map<String, dynamic> json) => JavaStatus(
        pid: jInt(json['pid']),
        workingSetMb: jDouble(json['working_set_mb']),
        privateMb: jDouble(json['private_mb']),
        threads: jInt(json['threads']),
        startTime: DateTime.tryParse(jString(json['start_time'])),
      );
}

class ServerToolsStatus {
  const ServerToolsStatus({required this.available, required this.stale, required this.grade, required this.version, required this.lagActive, required this.incidentCount, required this.tps, required this.mspt, required this.memoryPercent, required this.loadedChunks, required this.entities});
  final bool available;
  final bool stale;
  final String grade;
  final String version;
  final bool lagActive;
  final int incidentCount;
  final double? tps;
  final double? mspt;
  final double? memoryPercent;
  final int loadedChunks;
  final int entities;

  factory ServerToolsStatus.fromJson(Map<String, dynamic> json) {
    final p = jMap(json['performance']);
    double? nullable(String key) {
      final v = p[key];
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '');
    }
    return ServerToolsStatus(
      available: jBool(json['available']),
      stale: jBool(json['stale']),
      grade: jString(json['grade'], 'UNKNOWN').toUpperCase(),
      version: jString(json['version']),
      lagActive: jBool(json['lag_active']),
      incidentCount: jInt(json['incident_count']),
      tps: nullable('tps_1m'),
      mspt: nullable('mspt'),
      memoryPercent: nullable('memory_percent'),
      loadedChunks: jInt(p['loaded_chunks']),
      entities: jInt(p['entities']),
    );
  }
}

class ScheduleStatus {
  const ScheduleStatus({required this.active, required this.action, required this.executeAt, required this.countdownSeconds, required this.phase, required this.remainingSeconds});
  final bool active;
  final String action;
  final DateTime? executeAt;
  final int countdownSeconds;
  final String phase;
  final int remainingSeconds;
  factory ScheduleStatus.fromJson(Map<String, dynamic> json) => ScheduleStatus(
        active: jBool(json['active']),
        action: jString(json['action']),
        executeAt: DateTime.tryParse(jString(json['execute_at'])),
        countdownSeconds: jInt(json['countdown_seconds']),
        phase: jString(json['phase']),
        remainingSeconds: jInt(json['remaining_seconds']),
      );
}

class ControlJob {
  const ControlJob({required this.id, required this.serverId, required this.action, required this.status, required this.message, required this.error, required this.requestedAt, required this.finishedAt, required this.requestedBy, required this.source});
  final String id;
  final String serverId;
  final String action;
  final String status;
  final String message;
  final String error;
  final DateTime? requestedAt;
  final DateTime? finishedAt;
  final String requestedBy;
  final String source;
  bool get done => const {'completed', 'failed', 'cancelled', 'interrupted'}.contains(status);
  bool get successful => status == 'completed';
  factory ControlJob.fromJson(Map<String, dynamic> json) => ControlJob(
        id: jString(json['id']),
        serverId: jString(json['server_id']),
        action: jString(json['action']),
        status: jString(json['status']),
        message: jString(json['message']),
        error: jString(json['error']),
        requestedAt: DateTime.tryParse(jString(json['requested_at'])),
        finishedAt: DateTime.tryParse(jString(json['finished_at'])),
        requestedBy: jString(json['requested_by']),
        source: jString(json['source']),
      );
}

class ServerView {
  const ServerView({required this.id, required this.name, required this.state, required this.online, required this.desiredRunning, required this.minecraft, required this.java, required this.serverTools, required this.managementWarnings, required this.degradationReasons, required this.activeJob, required this.schedule, required this.pluginCount, required this.worldCount, required this.bridge, required this.operation});
  final String id;
  final String name;
  final String state;
  final bool online;
  final bool desiredRunning;
  final MinecraftStatus minecraft;
  final JavaStatus java;
  final ServerToolsStatus serverTools;
  final List<String> managementWarnings;
  final List<String> degradationReasons;
  final ControlJob? activeJob;
  final ScheduleStatus schedule;
  final int pluginCount;
  final int worldCount;
  final Map<String, dynamic> bridge;
  final String operation;
  bool get rconLimited => managementWarnings.contains('rcon_unavailable');
  factory ServerView.fromJson(Map<String, dynamic> json) {
    final active = json['active_job'];
    return ServerView(
      id: jString(json['id']),
      name: jString(json['name']),
      state: jString(json['state'], 'OFFLINE').toUpperCase(),
      online: jBool(json['online']),
      desiredRunning: jBool(json['desired_running']),
      minecraft: MinecraftStatus.fromJson(jMap(json['minecraft'])),
      java: JavaStatus.fromJson(jMap(json['java'])),
      serverTools: ServerToolsStatus.fromJson(jMap(json['server_tools'])),
      managementWarnings: jStrings(json['management_warnings']),
      degradationReasons: jStrings(json['degradation_reasons']),
      activeJob: active is Map ? ControlJob.fromJson(Map<String, dynamic>.from(active)) : null,
      schedule: ScheduleStatus.fromJson(jMap(json['schedule'])),
      pluginCount: jInt(json['plugin_count']),
      worldCount: jInt(json['world_count']),
      bridge: jMap(json['bridge']),
      operation: jString(json['operation']),
    );
  }
}

class GscSnapshot {
  const GscSnapshot({required this.gscVersion, required this.apiVersion, required this.timestamp, required this.host, required this.agentOnline, required this.servers, required this.activeJobs, required this.mobile});
  final String gscVersion;
  final int apiVersion;
  final DateTime? timestamp;
  final HostStatus host;
  final bool agentOnline;
  final List<ServerView> servers;
  final int activeJobs;
  final MobileStatus mobile;
  factory GscSnapshot.fromJson(Map<String, dynamic> json) => GscSnapshot(
        gscVersion: jString(json['gsc_version']),
        apiVersion: jInt(json['api_version']),
        timestamp: DateTime.tryParse(jString(json['timestamp'])),
        host: HostStatus.fromJson(jMap(json['host'])),
        agentOnline: jBool(json['agent_online']),
        servers: jMapList(json['servers']).map(ServerView.fromJson).toList(growable: false),
        activeJobs: jInt(json['active_jobs']),
        mobile: MobileStatus.fromJson(jMap(json['mobile'])),
      );
  GscSnapshot copyWith({HostStatus? host, bool? agentOnline, List<ServerView>? servers, int? activeJobs, MobileStatus? mobile}) => GscSnapshot(
        gscVersion: gscVersion,
        apiVersion: apiVersion,
        timestamp: DateTime.now(),
        host: host ?? this.host,
        agentOnline: agentOnline ?? this.agentOnline,
        servers: servers ?? this.servers,
        activeJobs: activeJobs ?? this.activeJobs,
        mobile: mobile ?? this.mobile,
      );
}

class MetricPoint {
  const MetricPoint({required this.time, required this.online, required this.players, required this.javaRamMb, required this.tps, required this.mspt, required this.memoryPercent, required this.loadedChunks, required this.entities});
  final DateTime? time;
  final bool online;
  final int players;
  final double javaRamMb;
  final double tps;
  final double mspt;
  final double memoryPercent;
  final int loadedChunks;
  final int entities;
  factory MetricPoint.fromJson(Map<String, dynamic> json) => MetricPoint(
        time: DateTime.tryParse(jString(json['time'])),
        online: jBool(json['online']),
        players: jInt(json['players']),
        javaRamMb: jDouble(json['java_ram_mb']),
        tps: jDouble(json['tps']),
        mspt: jDouble(json['mspt']),
        memoryPercent: jDouble(json['memory_percent']),
        loadedChunks: jInt(json['loaded_chunks']),
        entities: jInt(json['entities']),
      );
}

class BackupInfo {
  const BackupInfo({
    required this.file,
    required this.scope,
    required this.created,
    required this.size,
    required this.verified,
    required this.sha256,
    required this.kind,
    required this.protected,
    required this.trashed,
    required this.sourceReason,
  });
  final String file;
  final String scope;
  final DateTime? created;
  final int size;
  final bool verified;
  final String sha256;
  final String kind;
  final bool protected;
  final bool trashed;
  final String sourceReason;
  factory BackupInfo.fromJson(Map<String, dynamic> json) => BackupInfo(
        file: jString(json['file']),
        scope: jString(json['scope']),
        created: DateTime.tryParse(jString(json['created'])),
        size: jInt(json['size']),
        verified: jBool(json['verified']),
        sha256: jString(json['sha256']),
        kind: jString(json['kind'], 'backup'),
        protected: jBool(json['protected']),
        trashed: jBool(json['trashed']),
        sourceReason: jString(json['source_reason']),
      );
}

class GscAutomation {
  const GscAutomation({required this.id, required this.serverId, required this.name, required this.action, required this.time, required this.days, required this.backupScope, required this.enabled, required this.lastRunDate, required this.lastResult});
  final String id;
  final String serverId;
  final String name;
  final String action;
  final String time;
  final List<int> days;
  final String backupScope;
  final bool enabled;
  final String lastRunDate;
  final String lastResult;
  factory GscAutomation.fromJson(Map<String, dynamic> json) => GscAutomation(
        id: jString(json['id']),
        serverId: jString(json['server_id']),
        name: jString(json['name']),
        action: jString(json['action']),
        time: jString(json['time']),
        days: json['days'] is List ? (json['days'] as List).map(jInt).toList(growable: false) : const [],
        backupScope: jString(json['backup_scope'], 'world'),
        enabled: jBool(json['enabled']),
        lastRunDate: jString(json['last_run_date']),
        lastResult: jString(json['last_result']),
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'server_id': serverId,
        'name': name,
        'action': action,
        'time': time,
        'days': days,
        'backup_scope': backupScope,
        'enabled': enabled,
      };
}

class GscEvent {
  const GscEvent({required this.seq, required this.time, required this.level, required this.category, required this.serverId, required this.message, required this.detail});
  final int seq;
  final DateTime? time;
  final String level;
  final String category;
  final String serverId;
  final String message;
  final String detail;
  factory GscEvent.fromJson(Map<String, dynamic> json) => GscEvent(
        seq: jInt(json['seq']),
        time: DateTime.tryParse(jString(json['time'])),
        level: jString(json['level']),
        category: jString(json['category']),
        serverId: jString(json['server_id']),
        message: jString(json['message']),
        detail: jString(json['detail']),
      );
}

class AuditEntry {
  const AuditEntry({required this.seq, required this.time, required this.actorName, required this.actorKind, required this.action, required this.target, required this.result, required this.detail, required this.source});
  final int seq;
  final DateTime? time;
  final String actorName;
  final String actorKind;
  final String action;
  final String target;
  final String result;
  final String detail;
  final String source;
  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
        seq: jInt(json['seq']),
        time: DateTime.tryParse(jString(json['time'])),
        actorName: jString(json['actor_name']),
        actorKind: jString(json['actor_kind']),
        action: jString(json['action']),
        target: jString(json['target']),
        result: jString(json['result']),
        detail: jString(json['detail']),
        source: jString(json['source']),
      );
}
