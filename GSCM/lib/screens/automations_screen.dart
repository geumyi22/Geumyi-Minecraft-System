import 'package:flutter/material.dart';

import '../core/dashboard_controller.dart';
import '../core/gsc_api.dart';
import '../models/gsc_models.dart';
import '../widgets/status_chip.dart';

class AutomationsScreen extends StatefulWidget {
  const AutomationsScreen({super.key, required this.api, required this.controller});
  final GscApi api;
  final DashboardController controller;

  @override
  State<AutomationsScreen> createState() => _AutomationsScreenState();
}

class _AutomationsScreenState extends State<AutomationsScreen> {
  List<GscAutomation> items = const [];
  bool loading = true;
  String? busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      items = await widget.api.automations();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
    if (mounted) setState(() => loading = false);
  }

  String _actionLabel(String a) => switch (a) {
        'backup' => '백업',
        'restart' => '재시작',
        'backup_restart' => '백업 후 재시작',
        'stop' => '종료',
        'start' => '시작',
        _ => a,
      };

  String _days(List<int> days) => days.isEmpty
      ? '매일'
      : days.map((d) {
          final i = d < 0 ? 0 : (d > 6 ? 6 : d);
          return const ['일', '월', '화', '수', '목', '금', '토'][i];
        }).join('·');

  Future<void> _edit([GscAutomation? existing]) async {
    final servers = widget.controller.snapshot?.servers ?? const <ServerView>[];
    if (servers.isEmpty) return;
    String serverId = existing?.serverId ?? servers.first.id;
    String action = existing?.action ?? 'backup_restart';
    String time = existing?.time ?? '04:00';
    String scope = existing?.backupScope ?? 'world';
    bool enabled = existing?.enabled ?? true;
    Set<int> days = {...?existing?.days};
    final nameCtrl = TextEditingController(text: existing?.name ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existing == null ? '자동화 추가' : '자동화 수정'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '이름')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: serverId,
                  decoration: const InputDecoration(labelText: '서버'),
                  items: servers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                  onChanged: (v) => setLocal(() => serverId = v ?? serverId),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: action,
                  decoration: const InputDecoration(labelText: '작업'),
                  items: const [
                    DropdownMenuItem(value: 'backup', child: Text('백업')),
                    DropdownMenuItem(value: 'restart', child: Text('재시작')),
                    DropdownMenuItem(value: 'backup_restart', child: Text('백업 후 재시작')),
                    DropdownMenuItem(value: 'stop', child: Text('종료')),
                    DropdownMenuItem(value: 'start', child: Text('시작')),
                  ],
                  onChanged: (v) => setLocal(() => action = v ?? action),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: time,
                  decoration: const InputDecoration(labelText: '시간 (HH:MM)'),
                  onChanged: (v) => time = v,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: scope,
                  decoration: const InputDecoration(labelText: '백업 범위'),
                  items: const [
                    DropdownMenuItem(value: 'world', child: Text('월드')),
                    DropdownMenuItem(value: 'config', child: Text('설정')),
                    DropdownMenuItem(value: 'full', child: Text('전체')),
                  ],
                  onChanged: (v) => setLocal(() => scope = v ?? scope),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('실행 요일', style: Theme.of(context).textTheme.labelLarge),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  children: [
                    for (var i = 0; i < 7; i++)
                      FilterChip(
                        label: Text(const ['일', '월', '화', '수', '목', '금', '토'][i]),
                        selected: days.contains(i),
                        onSelected: (v) => setLocal(() => v ? days.add(i) : days.remove(i)),
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('자동화 사용'),
                  value: enabled,
                  onChanged: (v) => setLocal(() => enabled = v),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('저장')),
          ],
        ),
      ),
    );
    if (ok != true) {
      nameCtrl.dispose();
      return;
    }

    final next = GscAutomation(
      id: existing?.id ?? '',
      serverId: serverId,
      name: nameCtrl.text.trim(),
      action: action,
      time: time.trim(),
      days: days.toList()..sort(),
      backupScope: scope,
      enabled: enabled,
      lastRunDate: existing?.lastRunDate ?? '',
      lastResult: existing?.lastResult ?? '',
    );
    nameCtrl.dispose();

    try {
      setState(() => busyId = existing?.id ?? '__new__');
      items = await widget.api.upsertAutomation(next);
      if (mounted) setState(() {});
    } on GscApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busyId = null);
    }
  }

  Future<void> _toggle(GscAutomation a, bool enabled) async {
    setState(() => busyId = a.id);
    try {
      final next = GscAutomation(
        id: a.id,
        serverId: a.serverId,
        name: a.name,
        action: a.action,
        time: a.time,
        days: a.days,
        backupScope: a.backupScope,
        enabled: enabled,
        lastRunDate: a.lastRunDate,
        lastResult: a.lastResult,
      );
      items = await widget.api.upsertAutomation(next);
      if (mounted) setState(() {});
    } on GscApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busyId = null);
    }
  }

  Future<void> _delete(GscAutomation a) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('자동화 삭제'),
            content: Text('${a.name.isEmpty ? _actionLabel(a.action) : a.name} 자동화를 삭제합니다.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    setState(() => busyId = a.id);
    try {
      items = await widget.api.deleteAutomation(a.id);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => busyId = null);
    }
  }

  Future<void> _run(GscAutomation a) async {
    setState(() => busyId = a.id);
    try {
      final result = await widget.api.runAutomation(a.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: busyId == null ? () => _edit() : null,
          icon: const Icon(Icons.add),
          label: const Text('자동화'),
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
            children: [
              if (loading) const LinearProgressIndicator(minHeight: 2),
              if (!loading && items.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(30),
                    child: Center(child: Text('등록된 자동화가 없습니다.')),
                  ),
                ),
              ...items.map(
                (a) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 2, 2, 2),
                    child: ListTile(
                      leading: busyId == a.id
                          ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2))
                          : StatusChip(a.enabled ? 'ONLINE' : 'OFFLINE', icon: a.enabled ? Icons.schedule_rounded : Icons.pause_circle_outline),
                      title: Text(
                        a.name.isEmpty ? '${a.serverId} ${_actionLabel(a.action)}' : a.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${a.serverId} · ${_actionLabel(a.action)} · ${a.time} · ${_days(a.days)}'
                        '${a.lastRunDate.isEmpty ? '' : '\n마지막 실행: ${a.lastRunDate}'}'
                        '${a.lastResult.isEmpty ? '' : ' · ${a.lastResult}'}',
                      ),
                      isThreeLine: a.lastRunDate.isNotEmpty || a.lastResult.isNotEmpty,
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Switch.adaptive(
                          value: a.enabled,
                          onChanged: busyId == null ? (v) => _toggle(a, v) : null,
                        ),
                        PopupMenuButton<String>(
                          enabled: busyId == null,
                          onSelected: (v) {
                            if (v == 'edit') {
                              _edit(a);
                            } else if (v == 'run') {
                              _run(a);
                            } else {
                              _delete(a);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'run', child: Text('지금 실행')),
                            PopupMenuItem(value: 'edit', child: Text('수정')),
                            PopupMenuDivider(),
                            PopupMenuItem(value: 'delete', child: Text('삭제')),
                          ],
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
