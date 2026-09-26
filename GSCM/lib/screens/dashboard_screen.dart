import 'package:flutter/material.dart';

import '../core/dashboard_controller.dart';
import '../core/gsc_api.dart';
import '../models/gsc_models.dart';
import '../widgets/section_card.dart';
import '../widgets/server_card.dart';
import '../widgets/status_chip.dart';
import 'server_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.controller});
  final DashboardController controller;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final Set<String> busyServers = <String>{};

  Future<bool> _confirm(ServerView server, String action) async {
    if (action == 'start') return true;
    final label = action == 'restart' ? '재시작' : '정상 종료';
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('$label 확인'),
            content: Text('${server.name} 서버에 $label 작업을 요청합니다.\n현재 접속자: ${server.minecraft.online}명'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(label)),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _quickAction(ServerView server, String action) async {
    if (busyServers.contains(server.id)) return;
    if (!await _confirm(server, action)) return;
    setState(() => busyServers.add(server.id));
    try {
      await widget.controller.api.action(
        server.id,
        action,
        countdownSeconds: action == 'restart' ? 60 : action == 'stop' ? 30 : null,
      );
      await widget.controller.refresh(silent: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${server.name} · 작업을 GSC에 요청했습니다.')));
      }
    } on GscApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busyServers.remove(server.id));
    }
  }

  void _open(ServerView server) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServerDetailScreen(
          api: widget.controller.api,
          controller: widget.controller,
          serverId: server.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final snap = widget.controller.snapshot;
          if (widget.controller.loading && snap == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap == null) {
            return RefreshIndicator(
              onRefresh: widget.controller.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 110),
                  Icon(Icons.cloud_off_rounded, size: 68, color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 18),
                  Text('GSC에 연결할 수 없습니다.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(widget.controller.error ?? '네트워크 연결을 확인하세요.', textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  Center(child: FilledButton.icon(onPressed: widget.controller.refresh, icon: const Icon(Icons.refresh_rounded), label: const Text('다시 연결'))),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: widget.controller.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                _OverviewHero(snapshot: snap, realtime: widget.controller.realtimeUiHealthy, error: widget.controller.error, lastUpdate: widget.controller.lastUpdate),
                const SizedBox(height: 12),
                _HostCard(host: snap.host, agentOnline: snap.agentOnline),
                const SizedBox(height: 14),
                Row(children: [
                  Text('Minecraft 서버', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const Spacer(),
                  Text('${snap.servers.where((s) => s.online).length}/${snap.servers.length} online', style: Theme.of(context).textTheme.bodySmall),
                ]),
                const SizedBox(height: 10),
                ...snap.servers.map(
                  (server) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ServerCard(
                      server: server,
                      onTap: () => _open(server),
                      onStart: busyServers.contains(server.id) ? null : () => _quickAction(server, 'start'),
                      onRestart: busyServers.contains(server.id) ? null : () => _quickAction(server, 'restart'),
                      onStop: busyServers.contains(server.id) ? null : () => _quickAction(server, 'stop'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
}

class _OverviewHero extends StatelessWidget {
  const _OverviewHero({required this.snapshot, required this.realtime, required this.error, required this.lastUpdate});
  final GscSnapshot snapshot;
  final bool realtime;
  final String? error;
  final DateTime? lastUpdate;

  String _clock(DateTime? value) {
    if (value == null) return '-';
    final t = value.toLocal();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bad = snapshot.servers.where((s) => const {'CRASHED', 'BOOT_FAILED', 'DEGRADED'}.contains(s.state)).length;
    final allGood = bad == 0 && snapshot.servers.every((s) => s.online || !s.desiredRunning);
    final label = allGood ? '시스템 정상' : bad > 0 ? '확인 필요 $bad' : '대기 중';
    final color = allGood ? Colors.greenAccent.shade400 : bad > 0 ? cs.error : Colors.amberAccent.shade400;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [const Color(0xFF123251), const Color(0xFF0B1A29), color.withValues(alpha: .08)]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 46, height: 46, decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(15)), child: Icon(allGood ? Icons.check_circle_outline_rounded : Icons.monitor_heart_outlined, color: color)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            Text('GSC ${snapshot.gscVersion} · Control API v${snapshot.apiVersion}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ])),
          StatusChip(realtime ? 'REALTIME' : '재연결 중', icon: realtime ? Icons.bolt_rounded : Icons.wifi_off_rounded),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _HeroMetric(label: '온라인 서버', value: '${snapshot.servers.where((s) => s.online).length}/${snapshot.servers.length}', icon: Icons.dns_rounded)),
          const SizedBox(width: 8),
          Expanded(child: _HeroMetric(label: '활성 작업', value: '${snapshot.activeJobs}', icon: Icons.sync_rounded)),
          const SizedBox(width: 8),
          Expanded(child: _HeroMetric(label: '최근 갱신', value: _clock(lastUpdate), icon: Icons.schedule_rounded)),
        ]),
        if (error != null) ...[
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: cs.errorContainer.withValues(alpha: .28), borderRadius: BorderRadius.circular(12)), child: Text(error!, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ]),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .16), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: .07))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, size: 14), const SizedBox(width: 5), Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall))]),
          const SizedBox(height: 5),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
        ]),
      );
}

class _HostCard extends StatelessWidget {
  const _HostCard({required this.host, required this.agentOnline});
  final HostStatus host;
  final bool agentOnline;

  @override
  Widget build(BuildContext context) => SectionCard(
        title: host.hostname.isEmpty ? '서버 PC' : host.hostname,
        icon: Icons.computer_rounded,
        trailing: StatusChip(agentOnline ? 'Agent ONLINE' : 'Agent OFFLINE'),
        child: Column(children: [
          Row(children: [
            Expanded(child: MetricTile(label: 'CPU', value: '${host.cpuPercent.toStringAsFixed(0)}%', icon: Icons.memory_rounded, progress: host.cpuPercent / 100)),
            const SizedBox(width: 8),
            Expanded(child: MetricTile(label: 'RAM', value: '${host.ramUsedGb.toStringAsFixed(1)} / ${host.ramTotalGb.toStringAsFixed(1)} GB', icon: Icons.storage_rounded, progress: host.ramPercent / 100)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: MetricTile(label: '디스크', value: '${host.diskFreeGb.toStringAsFixed(0)} GB 남음', icon: Icons.storage_rounded, progress: host.diskPercent / 100)),
            const SizedBox(width: 8),
            Expanded(child: MetricTile(label: '가동 시간', value: host.uptime.isEmpty ? '-' : host.uptime, icon: Icons.timelapse_rounded)),
          ]),
        ]),
      );
}
