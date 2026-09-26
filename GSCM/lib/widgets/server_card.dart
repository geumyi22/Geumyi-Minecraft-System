import 'package:flutter/material.dart';

import '../models/gsc_models.dart';
import 'section_card.dart';
import 'status_chip.dart';

class ServerCard extends StatelessWidget {
  const ServerCard({
    super.key,
    required this.server,
    required this.onTap,
    this.onStart,
    this.onRestart,
    this.onStop,
  });

  final ServerView server;
  final VoidCallback onTap;
  final VoidCallback? onStart;
  final VoidCallback? onRestart;
  final VoidCallback? onStop;

  String _num(double? value, {int digits = 1}) => value == null ? '-' : value.toStringAsFixed(digits);

  @override
  Widget build(BuildContext context) {
    final gst = server.serverTools;
    final cs = Theme.of(context).colorScheme;
    final busy = server.activeJob != null || server.operation.isNotEmpty;
    final status = statusColor(context, server.state);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(height: 3, color: status.withValues(alpha: .8)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: status.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
                  child: Icon(server.id == 'wild' ? Icons.public_rounded : Icons.sports_esports_rounded, color: status),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(server.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text('${server.minecraft.version.isEmpty ? 'Minecraft' : server.minecraft.version} · ${server.pluginCount} plugins · ${server.worldCount} worlds', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
                StatusChip(server.state),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: MetricTile(label: '접속', value: '${server.minecraft.online} / ${server.minecraft.max}', icon: Icons.people_alt_outlined, compact: true)),
                const SizedBox(width: 8),
                Expanded(child: MetricTile(label: 'TPS', value: _num(gst.tps, digits: 2), icon: Icons.speed_rounded, compact: true)),
                const SizedBox(width: 8),
                Expanded(child: MetricTile(label: 'MSPT', value: '${_num(gst.mspt)} ms', icon: Icons.timer_outlined, compact: true)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: MetricTile(label: 'Java RAM', value: '${server.java.workingSetMb.toStringAsFixed(0)} MB', icon: Icons.memory_rounded, compact: true)),
                const SizedBox(width: 8),
                Expanded(child: MetricTile(label: 'Chunks', value: '${gst.loadedChunks}', icon: Icons.grid_view_rounded, compact: true)),
                const SizedBox(width: 8),
                Expanded(child: MetricTile(label: 'Entities', value: '${gst.entities}', icon: Icons.groups_2_outlined, compact: true)),
              ]),
              const SizedBox(height: 11),
              Wrap(spacing: 7, runSpacing: 7, children: [
                StatusChip(gst.available ? 'GST ${gst.grade}' : 'GST OFF'),
                StatusChip(server.bridge.isNotEmpty ? 'GDS ONLINE' : 'GDS 미확인'),
                if (server.rconLimited) const StatusChip('RCON 제한', icon: Icons.admin_panel_settings_outlined),
                if (server.schedule.active) StatusChip('예약 ${server.schedule.action}', icon: Icons.schedule_rounded),
                if (server.activeJob != null) StatusChip(server.activeJob!.status, icon: Icons.sync_rounded),
                if (server.serverTools.lagActive) const StatusChip('LAG ACTIVE', icon: Icons.warning_amber_rounded),
              ]),
              if (server.degradationReasons.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: cs.errorContainer.withValues(alpha: .28), borderRadius: BorderRadius.circular(12)),
                  child: Text('주의: ${server.degradationReasons.join(', ')}', style: TextStyle(color: cs.onErrorContainer, fontSize: 12)),
                ),
              ],
              const SizedBox(height: 12),
              Row(children: [
                if (!server.online)
                  Expanded(child: FilledButton.tonalIcon(onPressed: busy ? null : onStart, icon: const Icon(Icons.play_arrow_rounded), label: const Text('시작')))
                else ...[
                  Expanded(child: FilledButton.tonalIcon(onPressed: busy ? null : onRestart, icon: const Icon(Icons.restart_alt_rounded), label: const Text('재시작'))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(onPressed: busy ? null : onStop, icon: const Icon(Icons.stop_circle_outlined), label: const Text('종료'))),
                ],
                const SizedBox(width: 8),
                IconButton.filledTonal(onPressed: onTap, tooltip: '상세 관리', icon: const Icon(Icons.chevron_right_rounded)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
