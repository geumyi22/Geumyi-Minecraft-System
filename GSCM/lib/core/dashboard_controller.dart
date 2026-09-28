import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/gsc_models.dart';
import 'gsc_api.dart';

bool isRealtimeTransportFailureKind(String kind) =>
    kind == 'network' || kind == 'refused' || kind == 'timeout';

bool realtimeIndicatorHealthy({
  required bool realtimeConnected,
  required bool disconnectGraceActive,
  required bool transportFailure,
}) =>
    !transportFailure && (realtimeConnected || disconnectGraceActive);

class DashboardController extends ChangeNotifier {
  DashboardController(this.api);
  final GscApi api;

  GscSnapshot? snapshot;
  String? error;
  bool loading = true;
  bool realtimeConnected = false;
  DateTime? lastUpdate;
  String? realtimeDiagnostic;
  DateTime? lastRealtimeConnectedAt;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _reconnectTimer;
  Timer? _refreshDebounce;
  Timer? _pollTimer;
  Timer? _notifyCoalesce;
  Timer? _backgroundGraceTimer;
  Timer? _disconnectGraceTimer;
  bool _disposed = false;
  bool _foreground = true;
  bool _refreshing = false;
  bool _connectingRealtime = false;
  bool _confirmedTransportFailure = false;
  int _connectGeneration = 0;
  int _reconnectAttempt = 0;
  String _lastFingerprint = '';

  Future<void> start() async {
    await refresh();
    if (_disposed) return;
    _ensurePoller();
    unawaited(_connectRealtime());
  }

  void setForeground(bool value) {
    if (_disposed) return;
    if (value) {
      _backgroundGraceTimer?.cancel();
      _backgroundGraceTimer = null;
      final wasForeground = _foreground;
      _foreground = true;
      _ensurePoller();
      if (!wasForeground) {
        unawaited(refresh(silent: true));
      }
      if (!realtimeConnected && !_connectingRealtime) {
        unawaited(_connectRealtime());
      }
      return;
    }
    if (!_foreground) return;
    _foreground = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    // Android can briefly leave the resumed state for overlays, permission UI,
    // notification shade transitions, etc. Keep a healthy socket alive for a
    // short grace period so those transient lifecycle changes do not cause
    // visible REALTIME -> reconnecting churn.
    _backgroundGraceTimer?.cancel();
    _backgroundGraceTimer = Timer(const Duration(seconds: 30), () {
      _backgroundGraceTimer = null;
      if (!_disposed && !_foreground) {
        unawaited(_suspendRealtime());
      }
    });
  }

  Future<void> _suspendRealtime() async {
    _connectGeneration++;
    _connectingRealtime = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _disconnectGraceTimer?.cancel();
    _disconnectGraceTimer = null;
    final sub = _socketSub;
    final socket = _socket;
    _socketSub = null;
    _socket = null;
    await sub?.cancel();
    await socket?.close();
    if (realtimeConnected && !_disposed) {
      realtimeConnected = false;
      notifyListeners();
    }
  }

  void _ensurePoller() {
    if (!_foreground || _disposed || _pollTimer != null) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_foreground) unawaited(refresh(silent: true));
    });
  }

  bool _setConfirmedTransportFailure(bool value) {
    if (_confirmedTransportFailure == value) return false;
    _confirmedTransportFailure = value;
    if (value) {
      // Once HTTP/WS has positively confirmed a transport failure, the short
      // WebSocket grace window must no longer keep the header at REALTIME.
      _disconnectGraceTimer?.cancel();
      _disconnectGraceTimer = null;
    }
    return true;
  }

  String _fingerprint(GscSnapshot s) {
    final b = StringBuffer()
      ..write(s.gscVersion)
      ..write('|${s.apiVersion}|${s.agentOnline}|${s.activeJobs}')
      ..write('|${s.host.hostname}:${s.host.cpuPercent.toStringAsFixed(1)}:${s.host.ramUsedGb.toStringAsFixed(2)}:${s.host.diskFreeGb.toStringAsFixed(2)}')
      ..write('|${s.mobile.enabled}:${s.mobile.preferredUrl}:${s.mobile.trustedDevices.length}:${s.mobile.pairing.active}:${s.mobile.pairing.code}');
    for (final v in s.servers) {
      b
        ..write('|${v.id}:${v.state}:${v.online}:${v.desiredRunning}:${v.minecraft.online}:${v.minecraft.max}:${v.minecraft.latencyMs}')
        ..write(':${v.serverTools.available}:${v.serverTools.stale}:${v.serverTools.grade}:${v.serverTools.lagActive}:${v.serverTools.incidentCount}')
        ..write(':${v.serverTools.tps?.toStringAsFixed(2)}:${v.serverTools.mspt?.toStringAsFixed(1)}:${v.serverTools.memoryPercent?.toStringAsFixed(1)}')
        ..write(':${v.java.pid}:${v.java.workingSetMb.toStringAsFixed(0)}:${v.serverTools.loadedChunks}:${v.serverTools.entities}')
        ..write(':${v.activeJob?.id ?? ''}:${v.activeJob?.status ?? ''}:${v.operation}')
        ..write(':${v.schedule.active}:${v.schedule.action}:${v.schedule.phase}:${v.schedule.remainingSeconds}')
        ..write(':${v.pluginCount}:${v.worldCount}:${v.managementWarnings.join(',')}:${v.degradationReasons.join(',')}');
    }
    return b.toString();
  }

  Future<void> refresh({bool silent = false}) async {
    if (_refreshing || _disposed) return;
    _refreshing = true;
    if (!silent) {
      loading = snapshot == null;
      notifyListeners();
    }
    try {
      final next = await api.snapshot();
      final fp = _fingerprint(next);
      final transportChanged = _setConfirmedTransportFailure(false);
      final changed = fp != _lastFingerprint || error != null || snapshot == null || transportChanged;
      snapshot = next;
      _lastFingerprint = fp;
      error = null;
      lastUpdate = DateTime.now();
      if (changed && !_disposed) notifyListeners();
    } on GscApiException catch (e) {
      final transportChanged = _setConfirmedTransportFailure(isRealtimeTransportFailureKind(e.kind));
      final changed = error != e.message || transportChanged;
      error = e.message;
      if (changed && !_disposed) notifyListeners();
    } finally {
      _refreshing = false;
      if (!_disposed && loading) {
        loading = false;
        notifyListeners();
      } else {
        loading = false;
      }
    }
  }

  Future<void> _connectRealtime() async {
    if (_disposed || !_foreground || _connectingRealtime) return;
    if (realtimeConnected && _socket != null) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectingRealtime = true;
    final generation = ++_connectGeneration;
    WebSocket? candidate;
    var failed = false;
    try {
      candidate = await api.connectWebSocket();
      if (_disposed || !_foreground || generation != _connectGeneration) {
        await candidate.close();
        return;
      }

      // Only the newest connection attempt is allowed to become authoritative.
      // Late callbacks from an older socket must never tear down this socket.
      final oldSub = _socketSub;
      final oldSocket = _socket;
      _socket = candidate;
      _socketSub = candidate.listen(
        _onMessage,
        onDone: () => _realtimeLost(candidate!, generation),
        onError: (_) => _realtimeLost(candidate!, generation),
        cancelOnError: true,
      );
      try {
        await oldSub?.cancel();
      } catch (_) {}
      try {
        await oldSocket?.close();
      } catch (_) {}

      _disconnectGraceTimer?.cancel();
      _disconnectGraceTimer = null;
      _setConfirmedTransportFailure(false);
      realtimeConnected = true;
      lastRealtimeConnectedAt = DateTime.now();
      _reconnectAttempt = 0;
      error = null;
      if (!_disposed) notifyListeners();
    } on GscApiException catch (e) {
      failed = true;
      final transportChanged = _setConfirmedTransportFailure(isRealtimeTransportFailureKind(e.kind));
      if (transportChanged && !_disposed) notifyListeners();
      if (generation == _connectGeneration && identical(_socket, candidate)) {
        _socket = null;
        _socketSub = null;
      }
      try {
        await candidate?.close();
      } catch (_) {}
    } catch (_) {
      failed = true;
      if (generation == _connectGeneration && identical(_socket, candidate)) {
        _socket = null;
        _socketSub = null;
      }
      try {
        await candidate?.close();
      } catch (_) {}
    } finally {
      if (generation == _connectGeneration) {
        _connectingRealtime = false;
        if (failed && !_disposed && _foreground) {
          _scheduleRealtimeReconnect();
        }
      }
    }
  }

  void _coalescedNotify() {
    _notifyCoalesce ??= Timer(const Duration(milliseconds: 120), () {
      _notifyCoalesce = null;
      if (!_disposed) notifyListeners();
    });
  }

  void _onMessage(dynamic raw) {
    if (raw is! String || !_foreground) return;
    try {
      final envelope = jsonDecode(raw);
      if (envelope is! Map) return;
      final type = envelope['type']?.toString() ?? '';
      final data = envelope['data'];
      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);
      final transportRecovered = _setConfirmedTransportFailure(false);
      final current = snapshot;
      if (type == 'servers.status' && current != null && map['servers'] is List) {
        snapshot = current.copyWith(servers: jMapList(map['servers']).map(ServerView.fromJson).toList(growable: false));
        _lastFingerprint = _fingerprint(snapshot!);
        lastUpdate = DateTime.now();
        _coalescedNotify();
      } else if (type == 'host.status' && current != null && map['host'] is Map) {
        snapshot = current.copyWith(host: HostStatus.fromJson(jMap(map['host'])), agentOnline: map['agent_online'] is bool ? map['agent_online'] as bool : null);
        _lastFingerprint = _fingerprint(snapshot!);
        lastUpdate = DateTime.now();
        _coalescedNotify();
      } else if (type == 'mobile.updated' && current != null) {
        snapshot = current.copyWith(mobile: MobileStatus.fromJson(map));
        _lastFingerprint = _fingerprint(snapshot!);
        _coalescedNotify();
      } else if (type == 'server.state' || type == 'job.created' || type == 'job.updated' || type == 'event' || type == 'snapshot') {
        if (transportRecovered) _coalescedNotify();
        _scheduleRefresh();
      } else if (transportRecovered) {
        _coalescedNotify();
      }
    } catch (_) {}
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 350), () {
      if (_foreground) unawaited(refresh(silent: true));
    });
  }

  void _realtimeLost(WebSocket socket, int generation) {
    if (_disposed) return;
    // Ignore completion/error events belonging to a superseded socket. This is
    // the key guard against reconnect storms caused by overlapping attempts.
    if (generation != _connectGeneration || !identical(_socket, socket)) return;

    _socket = null;
    _socketSub = null;
    final code = socket.closeCode;
    final reason = socket.closeReason;
    realtimeDiagnostic = 'WS 종료${code == null ? '' : ' #$code'}${reason == null || reason.isEmpty ? '' : ' · $reason'}';

    // A mobile Wi-Fi handoff or a very short radio sleep can close the TCP
    // socket even though connectivity is immediately available again. Keep the
    // UI in REALTIME for a short grace window while reconnecting in the
    // background. Only show "재연결 중" when the outage is persistent.
    _disconnectGraceTimer?.cancel();
    if (realtimeConnected) {
      _disconnectGraceTimer = Timer(const Duration(seconds: 5), () {
        _disconnectGraceTimer = null;
        if (!_disposed && !realtimeConnected && _socket == null) {
          notifyListeners();
        }
      });
    }
    realtimeConnected = false;
    if (_foreground) {
      _scheduleRealtimeReconnect();
    }
  }

  void _scheduleRealtimeReconnect() {
    if (_disposed || !_foreground || _connectingRealtime) return;
    _reconnectTimer?.cancel();
    _reconnectAttempt = (_reconnectAttempt + 1).clamp(1, 6).toInt();
    // Recover quickly from a single Wi-Fi hiccup, then back off normally.
    const delaysMs = <int>[750, 1500, 3000, 6000, 12000, 30000];
    final delay = Duration(milliseconds: delaysMs[_reconnectAttempt - 1]);
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (!_disposed && _foreground) unawaited(_connectRealtime());
    });
  }

  bool get realtimeUiHealthy => realtimeIndicatorHealthy(
        realtimeConnected: realtimeConnected,
        disconnectGraceActive: _disconnectGraceTimer?.isActive ?? false,
        transportFailure: _confirmedTransportFailure,
      );

  ServerView? serverById(String id) {
    for (final s in snapshot?.servers ?? const <ServerView>[]) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _backgroundGraceTimer?.cancel();
    _disconnectGraceTimer?.cancel();
    _refreshDebounce?.cancel();
    _notifyCoalesce?.cancel();
    _pollTimer?.cancel();
    _socketSub?.cancel();
    _socket?.close();
    api.close();
    super.dispose();
  }
}
