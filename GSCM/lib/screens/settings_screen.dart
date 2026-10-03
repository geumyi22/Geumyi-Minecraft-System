import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/connection_store.dart';
import '../core/dashboard_controller.dart';
import '../core/gsc_api.dart';
import '../models/gsc_models.dart';
import '../widgets/section_card.dart';
import '../widgets/status_chip.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api, required this.controller, required this.connection, required this.onLogout});
  final GscApi api;
  final DashboardController controller;
  final StoredConnection connection;
  final Future<void> Function() onLogout;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  GscInfo? info;
  List<TrustedDevice> devices = const [];
  MobileStatus? mobileStatus;
  bool loading = true;
  bool mobileBusy = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final values = await Future.wait<dynamic>([widget.api.info(), widget.api.devices(), widget.api.mobile()]);
      info = values[0] as GscInfo;
      devices = values[1] as List<TrustedDevice>;
      mobileStatus = values[2] as MobileStatus;
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _deviceAction(String action, TrustedDevice d) async {
    final self = d.id == widget.connection.deviceId;
    if (action == 'delete' || (self && action == 'revoke')) {
      final deleting = action == 'delete';
      final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(deleting ? '관리 기기 완전 삭제' : '현재 기기 연결 해제'),
              content: Text(deleting
                  ? '이 기기의 등록 기록을 완전히 삭제합니다. 기존 토큰은 즉시 사용할 수 없고 다시 사용하려면 새 QR/연결 코드로 등록해야 합니다.'
                  : '이 기기의 토큰이 즉시 무효화됩니다. 현재 앱은 로그아웃되며 다시 연결하려면 새 QR/연결 코드가 필요합니다.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(deleting ? '기기 삭제' : '연결 해제')),
              ],
            ),
          ) ??
          false;
      if (!ok) return;
    }
    try {
      await widget.api.deviceAction(action, d.id);
      if (self && (action == 'revoke' || action == 'delete')) { await widget.onLogout(); return; }
      await _load();
    } on GscApiException catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message))); }
  }


  Future<void> _toggleMobile(bool enabled) async {
    if (mobileBusy) return;
    setState(() => mobileBusy = true);
    try {
      mobileStatus = await widget.api.updateMobile(enabled: enabled);
      await widget.controller.refresh(silent: true);
      if (mounted) setState(() {});
    } on GscApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => mobileBusy = false);
    }
  }

  Future<void> _setPairingTtl(int seconds) async {
    if (mobileBusy) return;
    setState(() => mobileBusy = true);
    try {
      mobileStatus = await widget.api.updateMobile(pairingTtlSeconds: seconds);
      await widget.controller.refresh(silent: true);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('새 연결 코드 유효시간을 ${seconds ~/ 60}분으로 변경했습니다.')));
      }
    } on GscApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => mobileBusy = false);
    }
  }

  Future<void> _newPairing() async {
    if (mobileBusy) return;
    setState(() => mobileBusy = true);
    try {
      if (mobileStatus?.enabled != true) {
        mobileStatus = await widget.api.updateMobile(enabled: true);
      }
      final pairing = await widget.api.createPairing();
      mobileStatus = await widget.api.mobile();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('새 기기 연결'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('다른 휴대폰의 GSCM에서 아래 코드를 ${pairing.remainingSeconds ~/ 60}분 안에 입력하거나 GSC PC 화면의 QR 코드를 스캔하세요.'),
              const SizedBox(height: 18),
              Center(child: SelectableText(pairing.code, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 5))),
              const SizedBox(height: 8),
              Center(child: Text('남은 시간 ${pairing.remainingSeconds ~/ 60}분 ${pairing.remainingSeconds % 60}초')),
              if (pairing.claimUri.isNotEmpty) ...[
                const SizedBox(height: 14),
                SelectableText(pairing.claimUri, style: Theme.of(context).textTheme.bodySmall),
              ],
            ]),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: pairing.code));
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('연결 코드를 복사했습니다.')));
              },
              icon: const Icon(Icons.copy),
              label: const Text('코드 복사'),
            ),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('확인')),
          ],
        ),
      );
    } on GscApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => mobileBusy = false);
    }
  }

  String _dt(DateTime? t) => t == null ? '-' : t.toLocal().toString().substring(0, 16);

  @override
  Widget build(BuildContext context) {
    final snap = widget.controller.snapshot;
    return RefreshIndicator(onRefresh: _load, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
      if (loading) const LinearProgressIndicator(),
      SectionCard(title: '연결', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.link), title: Text(widget.api.baseUri.toString()), subtitle: Text('기기: ${widget.connection.deviceName}\nID: ${widget.connection.deviceId}')),
        Wrap(spacing: 8, runSpacing: 8, children: [StatusChip(widget.controller.realtimeUiHealthy ? 'ONLINE' : '재연결 중'), StatusChip(snap?.mobile.enabled == true ? '모바일 허용' : '모바일 꺼짐'), StatusChip(snap?.agentOnline == true ? 'Agent ONLINE' : 'Agent OFFLINE')]),
        if (widget.controller.realtimeDiagnostic != null) ...[const SizedBox(height: 8), Text('마지막 실시간 종료: ${widget.controller.realtimeDiagnostic!}', style: Theme.of(context).textTheme.bodySmall)],
      ])),
      const SizedBox(height: 12),
      SectionCard(title: '버전 / 기능', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('GSC ${info?.version ?? snap?.gscVersion ?? '-'} · Control API v${info?.apiVersion ?? snap?.apiVersion ?? 0}', style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final f in info?.features ?? const <String>[]) Chip(label: Text(f, style: const TextStyle(fontSize: 11)))]),
      ])),
      const SizedBox(height: 12),
      SectionCard(
        title: '모바일 관리',
        icon: Icons.phone_android_rounded,
        trailing: mobileBusy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('LAN / Tailscale 모바일 접속'),
            subtitle: Text(mobileStatus?.enabled == true ? '활성화됨 · 포트 ${mobileStatus?.port ?? 8787}' : '비활성화됨'),
            value: mobileStatus?.enabled ?? false,
            onChanged: mobileBusy ? null : _toggleMobile,
          ),
          if (mobileStatus?.preferredUrl.isNotEmpty == true) ...[
            const SizedBox(height: 2),
            Row(children: [
              const Icon(Icons.link, size: 18),
              const SizedBox(width: 7),
              Expanded(child: SelectableText(mobileStatus!.preferredUrl, style: const TextStyle(fontWeight: FontWeight.w700))),
              IconButton(
                tooltip: '권장 주소 복사',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: mobileStatus!.preferredUrl));
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('권장 접속 주소를 복사했습니다.')));
                },
                icon: const Icon(Icons.copy, size: 18),
              ),
            ]),
          ],
          if ((mobileStatus?.addresses ?? const <String>[]).length > 1) ...[
            const SizedBox(height: 4),
            Text('대체 주소', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            for (final a in mobileStatus!.addresses.where((a) => a != mobileStatus!.preferredUrl))
              Padding(padding: const EdgeInsets.only(bottom: 3), child: SelectableText(a)),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: const <int>{300, 600, 900, 1800}.contains(mobileStatus?.pairingTtlSeconds) ? mobileStatus!.pairingTtlSeconds : 300,
                decoration: const InputDecoration(labelText: '새 연결 코드 유효시간'),
                items: const [
                  DropdownMenuItem(value: 300, child: Text('5분')),
                  DropdownMenuItem(value: 600, child: Text('10분')),
                  DropdownMenuItem(value: 900, child: Text('15분')),
                  DropdownMenuItem(value: 1800, child: Text('30분')),
                ],
                onChanged: mobileBusy ? null : (v) { if (v != null) _setPairingTtl(v); },
              ),
            ),
          ]),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: mobileBusy ? null : _newPairing,
            icon: const Icon(Icons.add_link),
            label: const Text('다른 기기용 연결 코드 생성'),
          ),
          if (mobileStatus?.pairing.active == true) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: .22)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('현재 연결 코드', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 5),
                Row(children: [
                  Expanded(child: SelectableText(mobileStatus!.pairing.code, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: 3))),
                  IconButton(
                    tooltip: '코드 복사',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: mobileStatus!.pairing.code));
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('연결 코드를 복사했습니다.')));
                    },
                    icon: const Icon(Icons.copy),
                  ),
                ]),
                Text('서버 기준 약 ${mobileStatus!.pairing.remainingSeconds}s 남음 · GSC PC 화면의 QR로도 연결 가능', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 12),
      SectionCard(title: '등록된 관리 기기 · ${devices.length}', trailing: IconButton(onPressed: _load, icon: const Icon(Icons.refresh)), child: Column(children: [
        for (final d in devices) ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(d.id == widget.connection.deviceId ? Icons.smartphone : Icons.devices_other),
          title: Row(children: [Flexible(child: Text(d.name, overflow: TextOverflow.ellipsis)), if (d.id == widget.connection.deviceId) const Padding(padding: EdgeInsets.only(left: 6), child: Chip(label: Text('이 기기', style: TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact))]),
          subtitle: Text('${d.revoked ? '폐기됨' : d.role} · 최근 ${_dt(d.lastSeen)}'),
          trailing: PopupMenuButton<String>(onSelected: (v) => _deviceAction(v, d), itemBuilder: (_) => [if (d.revoked) const PopupMenuItem(value: 'restore', child: Text('복구')) else const PopupMenuItem(value: 'revoke', child: Text('토큰 폐기')), const PopupMenuItem(value: 'delete', child: Text('기기 삭제'))]),
        ),
      ])),
      const SizedBox(height: 12),
      SectionCard(title: '보안', child: const Text('장치 토큰은 Android에서는 AndroidKeyStore AES-256-GCM, iOS에서는 Apple Keychain에 안전하게 저장됩니다. GSCM은 GSC :8787만 사용하며 RCON/GDS/Agent 포트에 직접 연결하지 않습니다. 공인 인터넷 포트포워딩 대신 LAN 또는 Tailscale을 사용하세요.')),
      const SizedBox(height: 16),
      OutlinedButton.icon(onPressed: () async { final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('앱에서 연결 해제'), content: const Text('로컬에 저장된 GSC 연결 정보를 삭제합니다. GSC의 등록 기기 토큰은 유지됩니다.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('연결 해제'))])) ?? false; if (ok) await widget.onLogout(); }, icon: const Icon(Icons.logout), label: const Text('이 앱에서 연결 해제')),
    ]));
  }
}
