import 'package:flutter_test/flutter_test.dart';
import 'package:gscm/core/gsc_api.dart';
import 'package:gscm/models/gsc_models.dart';

void main() {
  test('server model keeps corrected max players and management warning separate', () {
    final server = ServerView.fromJson({
      'id': 'wild',
      'name': '금이 야생',
      'state': 'ONLINE',
      'online': true,
      'desired_running': true,
      'minecraft': {'ok': true, 'online': 2, 'max': 6, 'reported_max': 2026, 'configured_max': 6},
      'java': {'pid': 123, 'working_set_mb': 2048},
      'server_tools': {'available': true, 'grade': 'HEALTHY', 'performance': {'tps_1m': 20.0, 'mspt': 8.0}},
      'management_warnings': ['rcon_unavailable'],
      'degradation_reasons': [],
      'schedule': {'active': false},
    });
    expect(server.minecraft.max, 6);
    expect(server.minecraft.reportedMax, 2026);
    expect(server.rconLimited, isTrue);
    expect(server.state, 'ONLINE');
  });

  test('safe remote URL accepts LAN and Tailscale but rejects public IPv4', () {
    expect(GscApi.isSafeRemoteUrl('100.84.252.113:8787'), isTrue);
    expect(GscApi.isSafeRemoteUrl('192.168.0.10:8787'), isTrue);
    expect(GscApi.isSafeRemoteUrl('8.8.8.8:8787'), isFalse);
    expect(GscApi.isSafeRemoteUrl('https://8.8.8.8:8787'), isFalse);
    expect(GscApi.isSafeRemoteUrl('169.254.101.252:8787'), isFalse);
  });

  test('automation serializes GSC 4.2 schema', () {
    const automation = GscAutomation(id: 'a', serverId: 'wild', name: '새벽 백업', action: 'backup_restart', time: '04:00', days: [1,2,3,4,5], backupScope: 'world', enabled: true, lastRunDate: '', lastResult: '');
    final json = automation.toJson();
    expect(json['server_id'], 'wild');
    expect(json['action'], 'backup_restart');
    expect(json['days'], [1,2,3,4,5]);
  });
}
