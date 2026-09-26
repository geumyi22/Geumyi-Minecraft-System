import 'package:flutter/material.dart';

import '../core/gsc_api.dart';
import '../models/gsc_models.dart';
import '../widgets/status_chip.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, required this.api});
  final GscApi api;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  int tab = 0;
  bool loading = true;
  String query = '';
  String level = 'all';
  List<ControlJob> jobs = const [];
  List<GscEvent> events = const [];
  List<AuditEntry> audit = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final values = await Future.wait<dynamic>([
        widget.api.jobs(limit: 180),
        widget.api.events(limit: 260),
        widget.api.audit(limit: 260),
      ]);
      jobs = values[0] as List<ControlJob>;
      events = values[1] as List<GscEvent>;
      audit = values[2] as List<AuditEntry>;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
    if (mounted) setState(() => loading = false);
  }

  String _time(DateTime? t) {
    if (t == null) return '-';
    final v = t.toLocal();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(v.month)}/${p(v.day)} ${p(v.hour)}:${p(v.minute)}:${p(v.second)}';
  }

  bool _contains(String text) => query.trim().isEmpty || text.toLowerCase().contains(query.trim().toLowerCase());

  @override
  Widget build(BuildContext context) {
    final filteredJobs = jobs.where((j) => _contains('${j.serverId} ${j.action} ${j.status} ${j.message} ${j.error} ${j.requestedBy} ${j.source}')).toList(growable: false);
    final filteredEvents = events.where((e) {
      final levelOk = level == 'all' || e.level.toLowerCase() == level;
      return levelOk && _contains('${e.level} ${e.category} ${e.serverId} ${e.message} ${e.detail}');
    }).toList(growable: false);
    final filteredAudit = audit.where((a) => _contains('${a.actorName} ${a.actorKind} ${a.action} ${a.target} ${a.result} ${a.detail} ${a.source}')).toList(growable: false);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('작업')),
                  ButtonSegment(value: 1, label: Text('이벤트')),
                  ButtonSegment(value: 2, label: Text('감사 로그')),
                ],
                selected: {tab},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => tab = v.first),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(onPressed: _load, tooltip: '새로고침', icon: const Icon(Icons.refresh_rounded)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => query = v),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '서버 · 작업 · 메시지 검색',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            if (tab == 1) ...[
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: level,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('전체')),
                  DropdownMenuItem(value: 'info', child: Text('INFO')),
                  DropdownMenuItem(value: 'warn', child: Text('WARN')),
                  DropdownMenuItem(value: 'error', child: Text('ERROR')),
                ],
                onChanged: (v) => setState(() => level = v ?? 'all'),
              ),
            ],
          ]),
        ]),
      ),
      if (loading) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: switch (tab) {
            0 => _JobsList(items: filteredJobs, time: _time),
            1 => _EventsList(items: filteredEvents, time: _time),
            _ => _AuditList(items: filteredAudit, time: _time),
          },
        ),
      ),
    ]);
  }
}

class _JobsList extends StatelessWidget {
  const _JobsList({required this.items, required this.time});
  final List<ControlJob> items;
  final String Function(DateTime?) time;

  @override
  Widget build(BuildContext context) => ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 100),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final j = items[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: StatusChip(j.status),
              title: Text('${j.serverId} · ${j.action}', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${time(j.requestedAt)} · ${j.requestedBy.isEmpty ? j.source : j.requestedBy}\n${j.error.isNotEmpty ? j.error : j.message}'),
              isThreeLine: true,
            ),
          );
        },
      );
}

class _EventsList extends StatelessWidget {
  const _EventsList({required this.items, required this.time});
  final List<GscEvent> items;
  final String Function(DateTime?) time;

  @override
  Widget build(BuildContext context) => ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 100),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final e = items[i];
          final icon = e.level == 'error'
              ? Icons.error_outline_rounded
              : e.level == 'warn'
                  ? Icons.warning_amber_rounded
                  : Icons.info_outline;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(icon, color: statusColor(context, e.level)),
              title: Text(e.message, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${time(e.time)} · ${e.category}${e.serverId.isEmpty ? '' : ' · ${e.serverId}'}${e.detail.isEmpty ? '' : '\n${e.detail}'}'),
            ),
          );
        },
      );
}

class _AuditList extends StatelessWidget {
  const _AuditList({required this.items, required this.time});
  final List<AuditEntry> items;
  final String Function(DateTime?) time;

  @override
  Widget build(BuildContext context) => ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 100),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final a = items[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(a.result == 'completed' || a.result == 'accepted' ? Icons.verified_outlined : Icons.shield_outlined),
              title: Text(a.action, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${time(a.time)} · ${a.actorName.isEmpty ? a.actorKind : a.actorName} · ${a.result}\n${a.target}${a.detail.isEmpty ? '' : ' · ${a.detail}'}'),
            ),
          );
        },
      );
}
