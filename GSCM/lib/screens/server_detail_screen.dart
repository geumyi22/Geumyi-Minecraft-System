import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/dashboard_controller.dart';
import '../core/gsc_api.dart';
import '../models/gsc_models.dart';
import '../widgets/mini_chart.dart';
import '../widgets/section_card.dart';
import '../widgets/status_chip.dart';

class ServerDetailScreen extends StatefulWidget {
  const ServerDetailScreen({
    super.key,
    required this.api,
    required this.controller,
    required this.serverId,
  });

  final GscApi api;
  final DashboardController controller;
  final String serverId;

  @override
  State<ServerDetailScreen> createState() => _ServerDetailScreenState();
}

class _ServerDetailScreenState extends State<ServerDetailScreen> {
  int section = 0;
  bool busy = false;
  final labels = const ['개요', '콘솔', '플레이어', '성능', '진단', '백업', '구성', '업데이트'];

  ServerView? get server => widget.controller.serverById(widget.serverId);

  Future<T?> _guard<T>(Future<T> Function() fn, {String? success}) async {
    if (busy) return null;
    setState(() => busy = true);
    try {
      final result = await fn();
      await widget.controller.refresh(silent: true);
      if (mounted && success != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      }
      return result;
    } on GscApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return null;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> _confirm(
    String title,
    String message, {
    String action = '확인',
    bool dangerous = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: dangerous
                    ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error)
                    : null,
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _action(String action) async {
    final s = server;
    if (s == null) return;
    int? countdown;
    if (action == 'restart' || action == 'stop') {
      countdown = action == 'restart' ? 60 : 30;
    }
    if (action != 'start') {
      final label = action == 'restart'
          ? '재시작'
          : action == 'stop'
              ? '정상 종료'
              : '강제 종료';
      final ok = await _confirm(
        '$label 확인',
        '${s.name}에 $label 작업을 실행합니다.\n현재 접속자: ${s.minecraft.online}명',
        action: label,
        dangerous: action == 'force-stop',
      );
      if (!ok) return;
    }
    await _guard(
      () => widget.api.action(s.id, action, countdownSeconds: countdown),
      success: '작업을 GSC에 요청했습니다.',
    );
  }

  Future<void> _schedule() async {
    final s = server;
    if (s == null) return;
    String action = 'restart';
    final now = DateTime.now();
    DateTime selected = now.add(const Duration(hours: 1));
    int countdown = 60;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('예약 작업'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'restart', label: Text('재시작')),
                  ButtonSegment(value: 'stop', label: Text('종료')),
                ],
                selected: {action},
                onSelectionChanged: (v) => setLocal(() => action = v.first),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(_formatDateTime(selected)),
                subtitle: const Text('휴대폰 로컬 시간 기준'),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 365)),
                    initialDate: selected,
                  );
                  if (d == null || !context.mounted) return;
                  final t = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(selected),
                  );
                  if (t == null) return;
                  setLocal(() => selected = DateTime(d.year, d.month, d.day, t.hour, t.minute));
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: countdown,
                decoration: const InputDecoration(labelText: '작업 전 카운트다운'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('즉시 실행')),
                  DropdownMenuItem(value: 30, child: Text('30초')),
                  DropdownMenuItem(value: 60, child: Text('60초')),
                  DropdownMenuItem(value: 300, child: Text('5분')),
                ],
                onChanged: (v) => setLocal(() => countdown = v ?? countdown),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('예약')),
          ],
        ),
      ),
    );
    if (accepted == true) {
      await _guard(
        () => widget.api.schedule(s.id, action, selected, countdownSeconds: countdown),
        success: '예약을 등록했습니다.',
      );
    }
  }

  static String _formatDateTime(DateTime value) {
    final v = value.toLocal();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${v.year}-${p(v.month)}-${p(v.day)} ${p(v.hour)}:${p(v.minute)}';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final s = server;
          if (s == null) {
            return const Scaffold(body: Center(child: Text('서버 정보를 찾을 수 없습니다.')));
          }
          return Scaffold(
            appBar: AppBar(
              title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                Text('${s.minecraft.online}/${s.minecraft.max}명 · ${s.state}', style: Theme.of(context).textTheme.labelSmall),
              ]),
              actions: [
                IconButton(
                  tooltip: '새로고침',
                  onPressed: busy ? null : () => widget.controller.refresh(),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
              ],
            ),
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Column(children: [
                  Row(children: [
                    StatusChip(s.state),
                    const SizedBox(width: 7),
                    if (s.serverTools.available) StatusChip('GST ${s.serverTools.grade}'),
                    const Spacer(),
                    if (s.activeJob != null) StatusChip(s.activeJob!.status, icon: Icons.sync_rounded),
                  ]),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<int>(
                      segments: [
                        for (var i = 0; i < labels.length; i++) ButtonSegment(value: i, label: Text(labels[i])),
                      ],
                      selected: {section},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) => setState(() => section = v.first),
                    ),
                  ),
                ]),
              ),
              Expanded(
                child: switch (section) {
                  0 => _OverviewSection(
                      server: s,
                      onAction: _action,
                      onSchedule: _schedule,
                      onCancelSchedule: () => _guard(
                        () => widget.api.cancelSchedule(s.id),
                        success: '예약을 취소했습니다.',
                      ),
                    ),
                  1 => _ConsoleSection(api: widget.api, server: s),
                  2 => _PlayersSection(api: widget.api, server: s),
                  3 => _MetricsSection(api: widget.api, server: s),
                  4 => _DiagnosticsSection(api: widget.api, server: s),
                  5 => _BackupsSection(api: widget.api, server: s, confirm: _confirm),
                  6 => _InventorySection(api: widget.api, server: s),
                  _ => _UpdateSection(api: widget.api, server: s, onRestart: () => _action('restart')),
                },
              ),
            ]),
          );
        },
      );
}

class _UpdateSection extends StatefulWidget {
  const _UpdateSection({required this.api, required this.server, required this.onRestart});
  final GscApi api;
  final ServerView server;
  final Future<void> Function() onRestart;

  @override
  State<_UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<_UpdateSection> {
  Map<String, dynamic> status = const {};
  Map<String, dynamic> dryRun = const {};
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh({bool check = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final next = check
          ? await widget.api.checkUpdates(widget.server.id)
          : await widget.api.updateStatus(widget.server.id);
      if (mounted) setState(() => status = next);
    } on GscApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _dryRun() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result = await widget.api.dryRunUpdates(widget.server.id);
      final servers = jMapList(result['servers']);
      final preview = servers.isEmpty ? <String, dynamic>{} : servers.first;
      if (mounted) {
        setState(() => dryRun = preview);
        final count = jMapList(preview['items']).length;
        final players = jInt(preview['players']);
        final blocked = jBool(preview['player_aware_block']);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              blocked
                  ? 'Dry-run: $count개 업데이트 · 접속자 $players명으로 재시작 차단'
                  : 'Dry-run: $count개 업데이트 · 파일 변경/재시작 없음',
            ),
          ),
        );
      }
    } on GscApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _editPolicy() async {
    if (busy) return;
    var policy = (status['policy']?.toString() ?? 'managed').toLowerCase();
    if (!const {'managed', 'hold', 'manual'}.contains(policy)) policy = 'managed';
    var channel = (status['configured_channel']?.toString() ?? 'inherit').toLowerCase();
    if (!const {'inherit', 'stable', 'beta', 'canary'}.contains(channel)) channel = 'inherit';
    final pin = TextEditingController(text: status['pin']?.toString() ?? '');

    final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: Text('${widget.server.name} 업데이트 정책'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: policy,
                      decoration: const InputDecoration(labelText: '실행 정책'),
                      items: const [
                        DropdownMenuItem(value: 'managed', child: Text('관리형 · 다음 시작 시 검증/적용')),
                        DropdownMenuItem(value: 'hold', child: Text('보류')),
                        DropdownMenuItem(value: 'manual', child: Text('수동 관리')),
                      ],
                      onChanged: (v) => setLocal(() => policy = v ?? policy),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: channel,
                      decoration: const InputDecoration(labelText: 'Release 채널'),
                      items: const [
                        DropdownMenuItem(value: 'inherit', child: Text('전체 설정 상속')),
                        DropdownMenuItem(value: 'stable', child: Text('Stable')),
                        DropdownMenuItem(value: 'beta', child: Text('Beta')),
                        DropdownMenuItem(value: 'canary', child: Text('Canary')),
                      ],
                      onChanged: (v) => setLocal(() => channel = v ?? channel),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pin,
                      decoration: const InputDecoration(
                        labelText: 'Release Pin',
                        hintText: '비우면 고정 해제',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('정책 저장만으로 서버를 재시작하지 않습니다. Pin은 해당 Release의 서명된 manifest만 허용합니다.'),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('저장')),
              ],
            ),
          ),
        ) ??
        false;

    if (!accepted) {
      pin.dispose();
      return;
    }
    final pinValue = pin.text.trim();
    pin.dispose();

    setState(() => busy = true);
    try {
      await widget.api.updatePolicy(
        widget.server.id,
        policy: policy,
        channel: channel,
        pin: pinValue,
      );
      final next = await widget.api.updateStatus(widget.server.id);
      if (mounted) {
        setState(() => status = next);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('업데이트 정책을 저장했습니다. 서버는 재시작하지 않았습니다.')),
        );
      }
    } on GscApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _decide(String choice) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result = await widget.api.updateDecision(widget.server.id, choice);
      if (!mounted) return;
      final policy = result['update_policy']?.toString() ?? choice;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('업데이트 정책이 $policy(으)로 저장됐습니다. 서버는 재시작하지 않았습니다.')),
      );
      final next = await widget.api.updateStatus(widget.server.id);
      if (mounted) setState(() => status = next);
    } on GscApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = status['available'];
    final pending = available is List ? available.map((e) => e.toString()).toList() : const <String>[];
    final pinText = status['pin']?.toString() ?? '';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        SectionCard(
          title: '서버 업데이트',
          icon: Icons.system_update_alt,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('상태: ${status['phase'] ?? '확인 전'}'),
              Text('안내: ${status['message'] ?? '상태 확인을 눌러주세요.'}'),
              const SizedBox(height: 4),
              Text(
                '정책: ${status['policy'] ?? 'managed'} · '
                '채널: ${status['configured_channel'] ?? 'inherit'} → ${status['channel'] ?? '-'}'
                '${pinText.isNotEmpty ? ' · Pin $pinText' : ''}',
              ),
              if (pending.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final line in pending) Text('• $line'),
              ],
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton(
                  onPressed: busy ? null : () => _refresh(),
                  child: const Text('상태 확인'),
                ),
                FilledButton.tonal(
                  onPressed: busy ? null : () => _refresh(check: true),
                  child: const Text('업데이트 확인'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : _dryRun,
                  child: const Text('Dry-run'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : _editPolicy,
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('채널 / Pin / 정책'),
                ),
              ]),
              if (dryRun.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  jBool(dryRun['player_aware_block'])
                      ? 'Dry-run: 접속자 ${jInt(dryRun['players'])}명 · 업데이트 재시작 차단'
                      : 'Dry-run: 재시작 안전 조건 통과 · 실제 적용은 하지 않음',
                ),
              ],
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton(
                  onPressed: busy ? null : () => _decide('defer'),
                  child: const Text('보류'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => _decide('manual'),
                  child: const Text('수동 관리'),
                ),
                FilledButton.tonal(
                  onPressed: busy ? null : () => _decide('enable-managed'),
                  child: const Text('다음 시작 시 자동 적용'),
                ),
              ]),
              const SizedBox(height: 8),
              const Text('업데이트는 서명·해시를 검증한 Geumyi 배포에만 적용됩니다. '
                  '보류와 정책 변경은 서버를 재시작하지 않습니다.'),
              if (widget.server.online) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy || widget.server.minecraft.online > 0 ? null : widget.onRestart,
                  icon: const Icon(Icons.restart_alt),
                  label: Text(widget.server.minecraft.online > 0
                      ? '접속자 ${widget.server.minecraft.online}명 · 업데이트 재시작 대기'
                      : '별도로 재시작 요청'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.server,
    required this.onAction,
    required this.onSchedule,
    required this.onCancelSchedule,
  });

  final ServerView server;
  final Future<void> Function(String) onAction;
  final Future<void> Function() onSchedule;
  final Future<Object?> Function() onCancelSchedule;

  String _n(double? v, [int d = 1]) => v == null ? '-' : v.toStringAsFixed(d);

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          SectionCard(
            title: '서버 제어',
            icon: Icons.tune_rounded,
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: server.online ? null : () => onAction('start'),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('시작'),
              ),
              FilledButton.tonalIcon(
                onPressed: server.online ? () => onAction('restart') : null,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('재시작'),
              ),
              FilledButton.tonalIcon(
                onPressed: server.online ? () => onAction('stop') : null,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('정상 종료'),
              ),
              OutlinedButton.icon(
                onPressed: server.online ? () => onAction('force-stop') : null,
                icon: const Icon(Icons.power_settings_new),
                label: const Text('강제 종료'),
              ),
              OutlinedButton.icon(
                onPressed: onSchedule,
                icon: const Icon(Icons.schedule_rounded),
                label: const Text('예약'),
              ),
              if (server.schedule.active)
                OutlinedButton.icon(
                  onPressed: onCancelSchedule,
                  icon: const Icon(Icons.event_busy),
                  label: const Text('예약 취소'),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '실시간 상태',
            icon: Icons.monitor_heart_outlined,
            child: Column(children: [
              Row(children: [
                Expanded(child: MetricTile(label: '접속자', value: '${server.minecraft.online} / ${server.minecraft.max}', icon: Icons.people_alt_outlined)),
                const SizedBox(width: 8),
                Expanded(child: MetricTile(label: 'Ping', value: '${server.minecraft.latencyMs} ms', icon: Icons.network_ping)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: MetricTile(label: 'TPS', value: _n(server.serverTools.tps, 2), icon: Icons.speed_rounded)),
                const SizedBox(width: 8),
                Expanded(child: MetricTile(label: 'MSPT', value: '${_n(server.serverTools.mspt)} ms', icon: Icons.timer_outlined)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: MetricTile(label: 'Java RAM', value: '${server.java.workingSetMb.toStringAsFixed(0)} MB', icon: Icons.memory_rounded)),
                const SizedBox(width: 8),
                Expanded(child: MetricTile(label: '메모리', value: '${_n(server.serverTools.memoryPercent)}%', icon: Icons.memory_rounded, progress: server.serverTools.memoryPercent == null ? null : server.serverTools.memoryPercent! / 100)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: MetricTile(label: 'Chunks', value: '${server.serverTools.loadedChunks}', icon: Icons.grid_view_rounded)),
                const SizedBox(width: 8),
                Expanded(child: MetricTile(label: 'Entities', value: '${server.serverTools.entities}', icon: Icons.groups_2_outlined)),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '연동 / 진단',
            icon: Icons.link,
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              StatusChip(server.serverTools.available ? 'GST ${server.serverTools.grade}' : 'GST OFF'),
              StatusChip(server.bridge.isNotEmpty ? 'GDS ONLINE' : 'GDS 미확인'),
              if (server.rconLimited)
                const StatusChip('RCON 제한', icon: Icons.admin_panel_settings_outlined)
              else
                const StatusChip('RCON OK'),
              if (server.serverTools.lagActive)
                const StatusChip('LAG ACTIVE', icon: Icons.warning_amber_rounded),
              if (server.serverTools.stale)
                const StatusChip('TELEMETRY STALE', icon: Icons.warning_amber_rounded),
            ]),
          ),
          if (server.schedule.active) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: '예약',
              icon: Icons.schedule_rounded,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_rounded),
                title: Text('${server.schedule.action} · ${server.schedule.executeAt == null ? '-' : _ServerDetailScreenState._formatDateTime(server.schedule.executeAt!)}'),
                subtitle: Text('남은 시간 ${server.schedule.remainingSeconds}초 · 카운트다운 ${server.schedule.countdownSeconds}초 · ${server.schedule.phase}'),
              ),
            ),
          ],
          if (server.activeJob != null) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: '현재 작업',
              icon: Icons.sync_rounded,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: StatusChip(server.activeJob!.status),
                title: Text(server.activeJob!.action, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(server.activeJob!.error.isNotEmpty ? server.activeJob!.error : server.activeJob!.message),
              ),
            ),
          ],
          if (server.managementWarnings.isNotEmpty || server.degradationReasons.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: '주의 사항',
              icon: Icons.warning_amber_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final x in server.degradationReasons) Padding(padding: const EdgeInsets.only(bottom: 5), child: Text('• 상태 저하: $x')),
                for (final x in server.managementWarnings) Padding(padding: const EdgeInsets.only(bottom: 5), child: Text('• 관리 제한: $x')),
              ]),
            ),
          ],
        ],
      );
}

class _ConsoleSection extends StatefulWidget {
  const _ConsoleSection({required this.api, required this.server});

  final GscApi api;
  final ServerView server;

  @override
  State<_ConsoleSection> createState() => _ConsoleSectionState();
}

class _ConsoleSectionState extends State<_ConsoleSection> {
  String text = '';
  String query = '';
  String level = 'ALL';
  bool loading = true;
  bool launcher = false;
  bool autoRefresh = false;
  int lines = 800;
  Timer? timer;
  final command = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    timer?.cancel();
    command.dispose();
    super.dispose();
  }

  void _setAutoRefresh(bool value) {
    timer?.cancel();
    timer = null;
    setState(() => autoRefresh = value);
    if (value) {
      timer = Timer.periodic(const Duration(seconds: 4), (_) => _load(silent: true));
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => loading = true);
    try {
      final next = await widget.api.console(
        widget.server.id,
        kind: launcher ? 'launcher' : 'server',
        lines: lines,
      );
      if (mounted) setState(() => text = next);
    } catch (e) {
      if (mounted && !silent) {
        setState(() => text = e.toString());
      }
    } finally {
      if (mounted && !silent) setState(() => loading = false);
    }
  }

  Future<void> _send() async {
    final v = command.text.trim();
    if (v.isEmpty) return;
    try {
      final r = await widget.api.command(widget.server.id, v);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(jString(r['response'], '명령 전송 완료'))),
        );
      }
      command.clear();
      await _load();
    } on GscApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String get shown {
    Iterable<String> rows = text.split('\n');
    if (level != 'ALL') {
      final needle = level == 'WARN' ? RegExp(r'\bWARN(?:ING)?\b', caseSensitive: false) : RegExp('\\b$level\\b', caseSensitive: false);
      rows = rows.where((line) => needle.hasMatch(line));
    }
    if (query.trim().isNotEmpty) {
      final q = query.trim().toLowerCase();
      rows = rows.where((line) => line.toLowerCase().contains(q));
    }
    return rows.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => query = v),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '로그 검색',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(onPressed: () => _load(), tooltip: '새로고침', icon: const Icon(Icons.refresh_rounded)),
            PopupMenuButton<bool>(
              initialValue: launcher,
              tooltip: '로그 종류',
              onSelected: (v) {
                setState(() => launcher = v);
                _load();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: false, child: Text('Minecraft 로그')),
                PopupMenuItem(value: true, child: Text('Launcher 로그')),
              ],
            ),
          ]),
          const SizedBox(height: 7),
          Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ALL', label: Text('전체')),
                    ButtonSegment(value: 'INFO', label: Text('INFO')),
                    ButtonSegment(value: 'WARN', label: Text('WARN')),
                    ButtonSegment(value: 'ERROR', label: Text('ERROR')),
                  ],
                  selected: {level},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() => level = v.first),
                ),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<int>(
              tooltip: '불러올 줄 수',
              initialValue: lines,
              onSelected: (v) {
                setState(() => lines = v);
                _load();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 300, child: Text('300줄')),
                PopupMenuItem(value: 800, child: Text('800줄')),
                PopupMenuItem(value: 1500, child: Text('1500줄')),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: Text('$lines줄', style: Theme.of(context).textTheme.labelMedium),
              ),
            ),
            IconButton(
              tooltip: autoRefresh ? '자동 갱신 끄기' : '4초 자동 갱신',
              onPressed: () => _setAutoRefresh(!autoRefresh),
              icon: Icon(autoRefresh ? Icons.sync_rounded : Icons.sync_rounded),
            ),
          ]),
        ]),
      ),
      Expanded(
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: .08)),
          ),
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : Stack(children: [
                  SingleChildScrollView(
                    reverse: true,
                    child: SelectableText(
                      shown,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.35),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton.filledTonal(
                      tooltip: '현재 표시 로그 복사',
                      onPressed: shown.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(ClipboardData(text: shown));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('표시 중인 로그를 복사했습니다.')));
                              }
                            },
                      icon: const Icon(Icons.copy, size: 18),
                    ),
                  ),
                ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: command,
              enabled: !widget.server.rconLimited,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                labelText: widget.server.rconLimited ? 'RCON 관리 제한' : '콘솔 명령',
                prefixIcon: const Icon(Icons.terminal),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: widget.server.rconLimited ? null : _send,
            icon: const Icon(Icons.send),
            label: const Text('전송'),
          ),
        ]),
      ),
    ]);
  }
}

class _PlayersSection extends StatefulWidget {
  const _PlayersSection({required this.api, required this.server});

  final GscApi api;
  final ServerView server;

  @override
  State<_PlayersSection> createState() => _PlayersSectionState();
}

class _PlayersSectionState extends State<_PlayersSection> {
  List<String> players = const [];
  bool loading = true;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      players = await widget.api.players(widget.server.id);
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<String?> _reason(String title) async {
    final ctrl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          maxLength: 180,
          decoration: const InputDecoration(labelText: '사유 (선택)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('실행')),
        ],
      ),
    );
    ctrl.dispose();
    return value;
  }

  Future<void> _act(String action, String player) async {
    if (busy) return;
    var reason = '';
    if (action == 'kick' || action == 'ban') {
      final r = await _reason(action == 'kick' ? '$player 킥' : '$player 밴');
      if (r == null) return;
      reason = r;
    }
    setState(() => busy = true);
    try {
      await widget.api.playerAction(widget.server.id, action, player, reason: reason);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('플레이어 작업 완료')));
      await _load();
    } on GscApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _manual() async {
    final ctrl = TextEditingController();
    String action = 'whitelist_add';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('플레이어 직접 관리'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: ctrl, decoration: const InputDecoration(labelText: '플레이어 이름')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: action,
              items: const [
                DropdownMenuItem(value: 'whitelist_add', child: Text('화이트리스트 추가')),
                DropdownMenuItem(value: 'whitelist_remove', child: Text('화이트리스트 삭제')),
                DropdownMenuItem(value: 'op', child: Text('OP 부여')),
                DropdownMenuItem(value: 'deop', child: Text('OP 해제')),
                DropdownMenuItem(value: 'pardon', child: Text('밴 해제')),
              ],
              onChanged: (v) => setLocal(() => action = v ?? action),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('실행')),
          ],
        ),
      ),
    );
    final player = ctrl.text.trim();
    ctrl.dispose();
    if (ok == true && player.isNotEmpty) await _act(action, player);
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            SectionCard(
              title: '접속 플레이어 · ${players.length}',
              icon: Icons.people_alt_outlined,
              trailing: OutlinedButton.icon(
                onPressed: widget.server.rconLimited || busy ? null : _manual,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('직접 관리'),
              ),
              child: loading
                  ? const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
                  : players.isEmpty
                      ? const Center(child: Padding(padding: EdgeInsets.all(30), child: Text('접속 중인 플레이어가 없습니다.')))
                      : Column(children: [
                          for (final p in players)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const CircleAvatar(child: Icon(Icons.person)),
                              title: Text(p, style: const TextStyle(fontWeight: FontWeight.w800)),
                              subtitle: Text(widget.server.rconLimited ? 'RCON 관리 제한' : '관리 가능'),
                              trailing: PopupMenuButton<String>(
                                enabled: !widget.server.rconLimited && !busy,
                                onSelected: (v) => _act(v, p),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'kick', child: Text('킥')),
                                  PopupMenuItem(value: 'whitelist_add', child: Text('화이트리스트 추가')),
                                  PopupMenuItem(value: 'whitelist_remove', child: Text('화이트리스트 삭제')),
                                  PopupMenuDivider(),
                                  PopupMenuItem(value: 'op', child: Text('OP 부여')),
                                  PopupMenuItem(value: 'deop', child: Text('OP 해제')),
                                  PopupMenuDivider(),
                                  PopupMenuItem(value: 'ban', child: Text('밴')),
                                  PopupMenuItem(value: 'pardon', child: Text('밴 해제')),
                                ],
                              ),
                            ),
                        ]),
            ),
            if (widget.server.rconLimited) ...[
              const SizedBox(height: 12),
              const SectionCard(
                title: '관리 제한',
                icon: Icons.admin_panel_settings_outlined,
                child: Text('Minecraft/RCON 관리 채널을 사용할 수 없어 킥·화이트리스트·OP·밴 기능이 비활성화되어 있습니다. 서버 자체 상태와 GST 진단은 계속 정상적으로 볼 수 있습니다.'),
              ),
            ],
          ],
        ),
      );
}

class _MetricsSection extends StatefulWidget {
  const _MetricsSection({required this.api, required this.server});

  final GscApi api;
  final ServerView server;

  @override
  State<_MetricsSection> createState() => _MetricsSectionState();
}

class _MetricsSectionState extends State<_MetricsSection> {
  List<MetricPoint> points = const [];
  bool loading = true;
  int limit = 240;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      points = await widget.api.metrics(widget.server.id, limit: limit);
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  double _max(List<double> values, double floor) {
    if (values.isEmpty) return floor;
    final value = values.reduce((a, b) => a > b ? a : b);
    return value < floor ? floor : value;
  }

  @override
  Widget build(BuildContext context) {
    final tps = points.map((e) => e.tps).where((e) => e > 0).toList(growable: false);
    final mspt = points.map((e) => e.mspt).where((e) => e >= 0).toList(growable: false);
    final ram = points.map((e) => e.javaRamMb).where((e) => e >= 0).toList(growable: false);
    final players = points.map((e) => e.players.toDouble()).toList(growable: false);
    final entities = points.map((e) => e.entities.toDouble()).toList(growable: false);
    final chunks = points.map((e) => e.loadedChunks.toDouble()).toList(growable: false);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Row(children: [
            Text('성능 히스토리', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const Spacer(),
            PopupMenuButton<int>(
              initialValue: limit,
              onSelected: (v) {
                setState(() => limit = v);
                _load();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 120, child: Text('최근 120포인트')),
                PopupMenuItem(value: 240, child: Text('최근 240포인트')),
                PopupMenuItem(value: 480, child: Text('최근 480포인트')),
              ],
              child: Chip(label: Text('$limit 포인트')),
            ),
          ]),
          const SizedBox(height: 10),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          SectionCard(
            title: 'TPS',
            icon: Icons.speed_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tps.isEmpty ? '-' : tps.last.toStringAsFixed(2), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              MiniLineChart(values: tps, min: 0, max: 20),
            ]),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'MSPT',
            icon: Icons.timer_outlined,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(mspt.isEmpty ? '-' : '${mspt.last.toStringAsFixed(1)} ms', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              MiniLineChart(values: mspt, min: 0, max: _max(mspt, 50).clamp(50, 250).toDouble()),
            ]),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Java 메모리',
            icon: Icons.memory_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ram.isEmpty ? '-' : '${ram.last.toStringAsFixed(0)} MB', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              MiniLineChart(values: ram, min: 0, max: _max(ram, 1024) * 1.12),
            ]),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '월드 부하',
            icon: Icons.public_rounded,
            child: Column(children: [
              Row(children: [
                Expanded(child: MetricTile(label: 'Players', value: players.isEmpty ? '-' : players.last.toInt().toString())),
                const SizedBox(width: 8),
                Expanded(child: MetricTile(label: 'Chunks', value: chunks.isEmpty ? '-' : chunks.last.toInt().toString())),
                const SizedBox(width: 8),
                Expanded(child: MetricTile(label: 'Entities', value: entities.isEmpty ? '-' : entities.last.toInt().toString())),
              ]),
              const SizedBox(height: 12),
              Text('Entities', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 5),
              MiniLineChart(values: entities, min: 0, max: _max(entities, 100) * 1.1, height: 90),
            ]),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticsSection extends StatefulWidget {
  const _DiagnosticsSection({required this.api, required this.server});

  final GscApi api;
  final ServerView server;

  @override
  State<_DiagnosticsSection> createState() => _DiagnosticsSectionState();
}

class _DiagnosticsSectionState extends State<_DiagnosticsSection> {
  Map<String, dynamic>? health;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      health = await widget.api.serverHealth(widget.server.id);
    } on GscApiException catch (e) {
      error = e.message;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = health ?? const <String, dynamic>{};
    final checks = jMapList(h['checks']);
    final overall = jString(h['overall'], 'unknown').toUpperCase();
    final bridge = jMap(h['bridge']);
    final gst = jMap(h['server_tools']);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          SectionCard(
            title: 'Preflight / Health',
            icon: Icons.monitor_heart_outlined,
            trailing: StatusChip(overall),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (loading) const LinearProgressIndicator(minHeight: 2),
              if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              if (!loading && checks.isEmpty && error == null) const Text('진단 항목이 없습니다.'),
              for (final c in checks)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    jString(c['status']) == 'ok'
                        ? Icons.check_circle_outline_rounded
                        : jString(c['status']) == 'warn'
                            ? Icons.warning_amber_rounded
                            : Icons.error_outline_rounded,
                    color: statusColor(context, jString(c['status'])),
                  ),
                  title: Text(jString(c['label'], jString(c['key'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(jString(c['message'])),
                  trailing: StatusChip(jString(c['status'], 'unknown').toUpperCase()),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'ServerTools Diagnostics',
            icon: Icons.speed_rounded,
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              StatusChip(widget.server.serverTools.available ? 'GST ${widget.server.serverTools.grade}' : 'GST OFF'),
              if (widget.server.serverTools.stale) const StatusChip('STALE'),
              if (widget.server.serverTools.lagActive) const StatusChip('LAG ACTIVE'),
              Chip(label: Text('v${widget.server.serverTools.version.isEmpty ? '-' : widget.server.serverTools.version}')),
              Chip(label: Text('Incidents ${widget.server.serverTools.incidentCount}')),
              if (gst.isNotEmpty) Chip(label: Text('진단 데이터 ${gst.length} fields')),
            ]),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'GDS Bridge',
            icon: Icons.link,
            child: bridge.isEmpty
                ? const Text('GDS Bridge 응답이 없습니다. 서버가 오프라인이면 정상일 수 있습니다.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in bridge.entries.take(12))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: SelectableText('${entry.key}: ${entry.value}'),
                        ),
                    ],
                  ),
          ),
          if (widget.server.managementWarnings.isNotEmpty || widget.server.degradationReasons.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'GSC 판정',
              icon: Icons.shield_outlined,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (widget.server.degradationReasons.isEmpty) const Text('상태 저하 사유 없음'),
                for (final x in widget.server.degradationReasons) Text('• 상태 저하: $x'),
                for (final x in widget.server.managementWarnings) Text('• 관리 경고: $x'),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _BackupsSection extends StatefulWidget {
  const _BackupsSection({required this.api, required this.server, required this.confirm});

  final GscApi api;
  final ServerView server;
  final Future<bool> Function(String, String, {String action, bool dangerous}) confirm;

  @override
  State<_BackupsSection> createState() => _BackupsSectionState();
}

class _BackupsSectionState extends State<_BackupsSection> {
  List<BackupInfo> items = const [];
  List<BackupInfo> trashItems = const [];
  bool loading = true;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final result = await Future.wait([
        widget.api.backups(widget.server.id),
        widget.api.trashedBackups(widget.server.id),
      ]);
      items = result[0];
      trashItems = result[1];
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  String _size(int bytes) {
    if (bytes > 1073741824) return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
    if (bytes > 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  Future<void> _create(String scope) async {
    setState(() => busy = true);
    try {
      await widget.api.createBackup(widget.server.id, scope);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('백업 완료')));
      await _load();
    } on GscApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _verify(BackupInfo b) async {
    setState(() => busy = true);
    try {
      await widget.api.verifyBackup(widget.server.id, b.file);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('백업 검증 통과')));
      await _load();
    } on GscApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _restore(BackupInfo b) async {
    final ok = await widget.confirm(
      '백업 복원',
      '${b.file}\n\n현재 서버 데이터를 이 백업으로 복원합니다. GSC가 복원 전 체크포인트를 자동 생성합니다.',
      action: '복원',
      dangerous: true,
    );
    if (!ok) return;
    setState(() => busy = true);
    try {
      final cp = await widget.api.restoreBackup(widget.server.id, b.file);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('복원 완료 · 체크포인트 $cp')));
      }
      await _load();
    } on GscApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _backupAction(BackupInfo b, String action) async {
    if (action == 'trash') {
      if (b.protected) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('보호된 백업입니다. 먼저 보호를 해제하세요.')));
        return;
      }
      final ok = await widget.confirm(
        '백업을 휴지통으로 이동',
        '${b.file}\n\n즉시 영구 삭제하지 않고 GSC 휴지통으로 이동합니다. 나중에 복구할 수 있습니다.',
        action: '휴지통으로 이동',
        dangerous: true,
      );
      if (!ok) return;
    } else if (action == 'delete-permanent') {
      final ok = await widget.confirm(
        '백업 영구 삭제',
        '${b.file}\n\n이 작업은 되돌릴 수 없습니다. 휴지통의 백업 파일을 영구 삭제합니다.',
        action: '영구 삭제',
        dangerous: true,
      );
      if (!ok) return;
    }
    setState(() => busy = true);
    try {
      await widget.api.backupAction(widget.server.id, b.file, action);
      if (mounted) {
        final labels = <String, String>{
          'protect': '백업 보호 지정 완료',
          'unprotect': '백업 보호 해제 완료',
          'trash': '휴지통으로 이동 완료',
          'restore-trash': '휴지통에서 복구 완료',
          'delete-permanent': '백업 영구 삭제 완료',
        };
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(labels[action] ?? '백업 작업 완료')));
      }
      await _load();
    } on GscApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            SectionCard(
              title: '새 백업',
              icon: Icons.archive_outlined,
              trailing: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.tonal(onPressed: busy ? null : () => _create('world'), child: const Text('월드')),
                FilledButton.tonal(onPressed: busy ? null : () => _create('config'), child: const Text('설정')),
                FilledButton.tonal(onPressed: busy ? null : () => _create('full'), child: const Text('전체')),
              ]),
            ),
            const SizedBox(height: 12),
            if (loading)
              const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
            else if (items.isEmpty)
              const SectionCard(child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('백업이 없습니다.'))))
            else
              ...items.map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      leading: Icon(b.protected ? Icons.lock_outline : (b.verified ? Icons.verified_outlined : Icons.archive_outlined)),
                      title: Text(b.file, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${b.kind == 'checkpoint' ? '체크포인트' : '백업'} · ${b.scope} · ${_size(b.size)} · ${b.created == null ? '-' : _ServerDetailScreenState._formatDateTime(b.created!)}'
                        '${b.protected ? '\n보호됨 · 휴지통 이동 차단' : ''}'
                        '${b.sha256.isEmpty ? '' : '\nSHA256 ${b.sha256.substring(0, b.sha256.length < 16 ? b.sha256.length : 16)}…'}',
                      ),
                      isThreeLine: b.sha256.isNotEmpty || b.protected,
                      trailing: PopupMenuButton<String>(
                        enabled: !busy,
                        onSelected: (v) {
                          if (v == 'verify') {
                            _verify(b);
                          } else if (v == 'restore') {
                            _restore(b);
                          } else {
                            _backupAction(b, v);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'verify', child: Text('무결성 검증')),
                          const PopupMenuItem(value: 'restore', child: Text('이 백업으로 복원')),
                          PopupMenuItem(value: b.protected ? 'unprotect' : 'protect', child: Text(b.protected ? '보호 해제' : '보호 지정')),
                          const PopupMenuDivider(),
                          const PopupMenuItem(value: 'trash', child: Text('휴지통으로 이동')),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (!loading) ...[
              const SizedBox(height: 12),
              SectionCard(
                title: '휴지통 · ${trashItems.length}',
                icon: Icons.delete_outline,
                child: trashItems.isEmpty
                    ? const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('휴지통이 비어 있습니다.')))
                    : Column(
                        children: trashItems
                            .map(
                              (b) => ListTile(
                                leading: const Icon(Icons.delete_outline),
                                title: Text(b.file, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text('${b.kind == 'checkpoint' ? '체크포인트' : '백업'} · ${b.scope} · ${_size(b.size)}'),
                                trailing: PopupMenuButton<String>(
                                  enabled: !busy,
                                  onSelected: (v) => _backupAction(b, v),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'restore-trash', child: Text('휴지통에서 복구')),
                                    PopupMenuDivider(),
                                    PopupMenuItem(value: 'delete-permanent', child: Text('영구 삭제')),
                                  ],
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
              ),
            ],
          ],
        ),
      );
}

class _InventorySection extends StatefulWidget {
  const _InventorySection({required this.api, required this.server});

  final GscApi api;
  final ServerView server;

  @override
  State<_InventorySection> createState() => _InventorySectionState();
}

class _InventorySectionState extends State<_InventorySection> {
  Map<String, dynamic>? data;
  bool loading = true;
  String query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      data = await widget.api.inventory(widget.server.id);
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final allPlugins = jMapList(d?['plugins']);
    final packs = jMapList(d?['datapacks']);
    final ext = jMap(d?['extensions']);
    final q = query.trim().toLowerCase();
    final plugins = q.isEmpty
        ? allPlugins
        : allPlugins.where((p) {
            final hay = '${jString(p['name'])} ${jString(p['file'])} ${jString(p['version'])}'.toLowerCase();
            return hay.contains(q);
          }).toList(growable: false);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          if (loading) const LinearProgressIndicator(minHeight: 2),
          SectionCard(
            title: 'GSC 연동',
            icon: Icons.extension,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in ext.entries)
                    StatusChip(
                      '${entry.key}: ${jBool(jMap(entry.value)['installed']) ? jString(jMap(entry.value)['version'], '설치됨') : '없음'}',
                      icon: jBool(jMap(entry.value)['installed']) ? Icons.check_circle_outline_rounded : Icons.extension_off,
                    ),
                ],
              ),
              if (widget.server.id == 'wild') ...[
                const SizedBox(height: 10),
                Text('Technology / Chemistry는 야생 서버 전용 확장입니다.', style: Theme.of(context).textTheme.bodySmall),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '플러그인 · ${allPlugins.length}',
            icon: Icons.extension,
            trailing: SizedBox(
              width: 150,
              child: TextField(
                onChanged: (v) => setState(() => query = v),
                decoration: const InputDecoration(isDense: true, hintText: '검색', prefixIcon: Icon(Icons.search)),
              ),
            ),
            child: Column(children: [
              if (plugins.isEmpty) const Padding(padding: EdgeInsets.all(18), child: Text('일치하는 플러그인이 없습니다.')),
              for (final p in plugins)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(jBool(p['enabled']) ? Icons.extension : Icons.extension_off),
                  title: Text(jString(p['name'], jString(p['file'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${jString(p['version'], '?')} · ${jBool(p['managed']) ? 'GSC 관리' : '외부'} · ${jBool(p['enabled']) ? '사용' : '비활성'}'),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '데이터팩 · ${packs.length}',
            icon: Icons.inventory_2_outlined,
            child: Column(children: [
              if (packs.isEmpty)
                const Text('데이터팩 없음')
              else
                for (final p in packs)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(jBool(p['enabled']) ? Icons.inventory_2_outlined : Icons.inventory_2),
                    title: Text(jString(p['file'])),
                    subtitle: Text('pack_format ${jInt(p['pack_format'])} · ${jString(p['description'])}'),
                  ),
            ]),
          ),
        ],
      ),
    );
  }
}
