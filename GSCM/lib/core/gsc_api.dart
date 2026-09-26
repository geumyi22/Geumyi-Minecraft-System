import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/gsc_models.dart';

class GscApiException implements Exception {
  GscApiException(this.message, {this.statusCode, this.kind = 'api'});
  final String message;
  final int? statusCode;
  final String kind;
  @override
  String toString() => message;
}

class GscApi {
  GscApi({required String hostUrl, this.token = ''})
      : baseUri = normalizeBase(hostUrl) {
    _client.connectionTimeout = const Duration(seconds: 4);
    _client.idleTimeout = const Duration(seconds: 20);
    _client.maxConnectionsPerHost = 8;
  }

  final Uri baseUri;
  String token;
  final HttpClient _client = HttpClient();

  static Uri normalizeBase(String raw) {
    var value = raw.trim();
    if (!value.contains('://')) {
      value = 'http://$value';
    }
    var uri = Uri.parse(value);
    if (!uri.hasPort) {
      uri = uri.replace(port: 8787);
    }
    return uri.replace(path: '', query: null, fragment: null);
  }

  static bool isSafeRemoteUrl(String raw) {
    try {
      final uri = normalizeBase(raw);
      if (uri.scheme != 'http' && uri.scheme != 'https') return false;
      final host = uri.host.toLowerCase();
      if (host == 'localhost' || host == '127.0.0.1' || host == '::1') return true;
      if (host.endsWith('.ts.net') || host.endsWith('.local')) return true;

      final parts = host.split('.').map(int.tryParse).toList();
      if (parts.length == 4 && parts.every((e) => e != null)) {
        final a = parts[0]!;
        final b = parts[1]!;
        // RFC1918 + Tailscale/CGNAT only. APIPA 169.254/16 and public IPs are
        // intentionally rejected so a broken adapter cannot become the saved host.
        return a == 10 ||
            (a == 192 && b == 168) ||
            (a == 172 && b >= 16 && b <= 31) ||
            (a == 100 && b >= 64 && b <= 127);
      }

      // A single-label host can be a local DNS/NetBIOS name. Dotted public DNS
      // names are rejected unless they are Tailscale (.ts.net) or mDNS (.local).
      return !host.contains('.');
    } catch (_) {
      return false;
    }
  }

  Uri _uri(String path, [Map<String, String>? query]) => baseUri.replace(
        path: path.startsWith('/') ? path : '/$path',
        queryParameters: query,
      );

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final request = await _client.openUrl(method, _uri(path, query)).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'GSCM/1.0.0 Android');
      if (body != null) request.headers.contentType = ContentType.json;
      if (authenticated && token.isNotEmpty) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(timeout);
      final text = await utf8.decoder.bind(response).join().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final trimmed = text.trim();
        var message = trimmed.isEmpty ? 'GSC가 HTTP ${response.statusCode}을 반환했습니다.' : trimmed;
        var kind = 'http';
        if (response.statusCode == 401) {
          kind = 'auth';
          message = trimmed.contains('pairing') ? '연결 코드가 만료되었거나 올바르지 않습니다.' : '인증이 만료되었거나 해제된 기기입니다.';
        } else if (response.statusCode == 403) {
          kind = 'forbidden';
          message = trimmed.contains('mobile access is disabled') ? 'GSC에서 모바일 연결이 꺼져 있습니다.' : '이 네트워크에서는 GSC 모바일 접속이 허용되지 않습니다.';
        } else if (response.statusCode == 429) {
          kind = 'rate_limit';
          message = '연결 시도가 너무 많습니다. 잠시 후 다시 시도해 주세요.';
        }
        throw GscApiException(message, statusCode: response.statusCode, kind: kind);
      }
      if (text.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw GscApiException('GSC 응답 형식이 올바르지 않습니다.', kind: 'format');
    } on GscApiException {
      rethrow;
    } on TimeoutException {
      throw GscApiException('GSC 응답 시간이 초과되었습니다. Tailscale/Wi-Fi 연결과 GSC 실행 상태를 확인하세요.', kind: 'timeout');
    } on SocketException catch (e) {
      final refused = e.osError?.errorCode == 10061 || e.message.toLowerCase().contains('refused');
      throw GscApiException(
        refused ? 'GSC가 해당 주소의 8787 포트에서 응답하지 않습니다. GSC 4.2.x가 실행 중이고 모바일 연결이 켜졌는지 확인하세요.' : 'GSC에 연결할 수 없습니다: ${e.message}',
        kind: refused ? 'refused' : 'network',
      );
    } on FormatException {
      throw GscApiException('GSC 주소 또는 응답 형식이 올바르지 않습니다.', kind: 'format');
    }
  }

  Future<GscInfo> info() async => GscInfo.fromJson(await _request('GET', '/api/v1/info'));
  Future<GscSnapshot> snapshot() async => GscSnapshot.fromJson(await _request('GET', '/api/v1/snapshot'));
  Future<MobileStatus> mobile() async => MobileStatus.fromJson(await _request('GET', '/api/v1/mobile'));

  Future<MobileStatus> updateMobile({bool? enabled, int? pairingTtlSeconds}) async {
    final body = <String, dynamic>{};
    if (enabled != null) body['enabled'] = enabled;
    if (pairingTtlSeconds != null) body['pairing_ttl_seconds'] = pairingTtlSeconds;
    final json = await _request('POST', '/api/v1/mobile', body: body);
    final nested = jMap(json['mobile']);
    return MobileStatus.fromJson(nested.isEmpty ? json : nested);
  }

  Future<PairingSummary> createPairing() async {
    final json = await _request('POST', '/api/v1/pairing', body: <String, dynamic>{});
    return PairingSummary.fromJson(json);
  }

  Future<PairingSummary> pairing() async => PairingSummary.fromJson(await _request('GET', '/api/v1/pairing'));

  Future<PairingResult> claimPairing({required String code, required String deviceId, required String name}) async {
    final json = await _request('POST', '/api/v1/pairing/claim', authenticated: false, body: {
      'code': code.replaceAll(RegExp(r'\D'), ''),
      'device_id': deviceId,
      'name': name,
    });
    return PairingResult.fromJson(json);
  }

  Future<Map<String, dynamic>> server(String id) => _request('GET', '/api/v1/servers/$id');
  Future<Map<String, dynamic>> serverHealth(String id) => _request('GET', '/api/v1/servers/$id/health');
  Future<List<String>> players(String id) async {
    final json = await _request('GET', '/api/v1/servers/$id/players');
    return jStrings(json['players']);
  }

  Future<ControlJob?> action(String serverId, String action, {int? countdownSeconds}) async {
    final body = <String, dynamic>{'action': action};
    if (countdownSeconds != null) body['countdown_seconds'] = countdownSeconds;
    final json = await _request('POST', '/api/v1/servers/$serverId/actions', body: body);
    final raw = json['job'];
    return raw is Map ? ControlJob.fromJson(Map<String, dynamic>.from(raw)) : null;
  }

  Future<Map<String, dynamic>> command(String serverId, String command) => _request(
        'POST', '/api/v1/servers/$serverId/command', body: {'command': command}, timeout: const Duration(seconds: 15));

  Future<Map<String, dynamic>> playerAction(String serverId, String action, String player, {String reason = ''}) => _request(
        'POST', '/api/v1/servers/$serverId/player-action', body: {'action': action, 'player': player, 'reason': reason});

  Future<String> console(String serverId, {String kind = 'server', int lines = 500}) async {
    final json = await _request('GET', '/api/v1/servers/$serverId/console', query: {'kind': kind, 'lines': '$lines'});
    return jString(json['text']);
  }

  Future<Map<String, dynamic>> inventory(String serverId) => _request('GET', '/api/v1/servers/$serverId/inventory');

  Future<Map<String, dynamic>> schedule(String serverId, String action, DateTime executeAt, {int countdownSeconds = 60}) => _request(
        'POST', '/api/v1/servers/$serverId/schedule', body: {
      'action': action,
      'execute_at': executeAt.toUtc().toIso8601String(),
      'countdown_seconds': countdownSeconds,
    });

  Future<Map<String, dynamic>> cancelSchedule(String serverId) => _request('DELETE', '/api/v1/servers/$serverId/schedule');

  Future<List<MetricPoint>> metrics(String id, {int limit = 240}) async {
    final json = await _request('GET', '/api/v1/metrics', query: {'id': id, 'limit': '$limit'});
    return jMapList(json['points']).map(MetricPoint.fromJson).toList(growable: false);
  }

  Future<List<BackupInfo>> backups(String id) async {
    final json = await _request('GET', '/api/v1/backups', query: {'id': id});
    return jMapList(json['backups']).map(BackupInfo.fromJson).toList(growable: false);
  }

  Future<BackupInfo> createBackup(String id, String scope) async {
    final json = await _request('POST', '/api/v1/backups', body: {'id': id, 'scope': scope}, timeout: const Duration(minutes: 10));
    return BackupInfo.fromJson(jMap(json['backup']));
  }

  Future<BackupInfo> verifyBackup(String id, String file) async {
    final json = await _request('POST', '/api/v1/backups/verify', body: {'id': id, 'file': file}, timeout: const Duration(minutes: 10));
    return BackupInfo.fromJson(jMap(json['backup']));
  }

  Future<String> restoreBackup(String id, String file) async {
    final json = await _request('POST', '/api/v1/backups/restore', body: {'id': id, 'file': file}, timeout: const Duration(minutes: 20));
    return jString(json['checkpoint']);
  }

  Future<List<GscAutomation>> automations() async {
    final json = await _request('GET', '/api/v1/automations');
    return jMapList(json['automations']).map(GscAutomation.fromJson).toList(growable: false);
  }

  Future<List<GscAutomation>> upsertAutomation(GscAutomation automation) async {
    final json = await _request('POST', '/api/v1/automations', body: {'action': 'upsert', 'automation': automation.toJson()});
    return jMapList(json['automations']).map(GscAutomation.fromJson).toList(growable: false);
  }

  Future<List<GscAutomation>> deleteAutomation(String id) async {
    final json = await _request('POST', '/api/v1/automations', body: {'action': 'delete', 'id': id});
    return jMapList(json['automations']).map(GscAutomation.fromJson).toList(growable: false);
  }

  Future<String> runAutomation(String id) async {
    final json = await _request('POST', '/api/v1/automations', body: {'action': 'run', 'id': id}, timeout: const Duration(minutes: 10));
    return jString(json['result']);
  }

  Future<List<ControlJob>> jobs({int limit = 100, String serverId = ''}) async {
    final q = {'limit': '$limit'};
    if (serverId.isNotEmpty) q['id'] = serverId;
    final json = await _request('GET', '/api/v1/jobs', query: q);
    return jMapList(json['jobs']).map(ControlJob.fromJson).toList(growable: false);
  }

  Future<List<GscEvent>> events({int limit = 200, String serverId = ''}) async {
    final q = {'limit': '$limit'};
    if (serverId.isNotEmpty) q['id'] = serverId;
    final json = await _request('GET', '/api/v1/events', query: q);
    return jMapList(json['events']).map(GscEvent.fromJson).toList(growable: false);
  }

  Future<List<AuditEntry>> audit({int limit = 200}) async {
    final json = await _request('GET', '/api/v1/audit', query: {'limit': '$limit'});
    return jMapList(json['audit']).map(AuditEntry.fromJson).toList(growable: false);
  }

  Future<List<TrustedDevice>> devices() async {
    final json = await _request('GET', '/api/v1/devices');
    return jMapList(json['devices']).map(TrustedDevice.fromJson).toList(growable: false);
  }

  Future<void> deviceAction(String action, String id) async {
    await _request('POST', '/api/v1/devices', body: {'action': action, 'id': id});
  }

  Future<WebSocket> connectWebSocket() async {
    final wsScheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
    final uri = baseUri.replace(scheme: wsScheme, path: '/api/v1/ws');
    try {
      final socket = await WebSocket.connect(uri.toString(), headers: {HttpHeaders.authorizationHeader: 'Bearer $token'}).timeout(const Duration(seconds: 7));
      // GSC already sends RFC6455 Ping frames every ~25 seconds. Dart
      // automatically replies with Pong, so a second client-side watchdog is
      // unnecessary and can cause false disconnects on briefly jittery mobile
      // Wi-Fi. Let the server heartbeat own liveness detection.
      socket.pingInterval = null;
      return socket;
    } on TimeoutException {
      throw GscApiException('실시간 연결 시간이 초과되었습니다.', kind: 'timeout');
    } on SocketException catch (e) {
      throw GscApiException('실시간 연결 실패: ${e.message}', kind: 'network');
    }
  }

  void close() => _client.close(force: true);
}
