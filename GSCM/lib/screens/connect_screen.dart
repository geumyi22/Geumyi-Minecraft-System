import 'package:flutter/material.dart';

import '../core/connection_store.dart';
import '../core/gsc_api.dart';
import 'qr_scan_screen.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, required this.store, required this.onConnected});
  final ConnectionStore store;
  final Future<void> Function(StoredConnection connection) onConnected;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final host = TextEditingController();
  final code = TextEditingController();
  final name = TextEditingController();
  bool busy = false;
  bool manualOpen = false;
  String? error;
  List<String> qrHosts = const <String>[];

  @override
  void initState() {
    super.initState();
    widget.store.defaultDeviceName().then((v) {
      if (mounted && name.text.isEmpty) name.text = v;
    });
  }

  @override
  void dispose() {
    host.dispose();
    code.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final result = await Navigator.of(context).push<QrScanResult>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (result == null || !mounted) return;
    host.text = result.host;
    code.text = result.code;
    qrHosts = result.hosts;
    await _connect();
  }

  Future<void> _connect() async {
    if (busy) return;
    final rawHost = host.text.trim();
    final rawCode = code.text.replaceAll(RegExp(r'\D'), '');
    final candidates = <String>[
      rawHost,
      ...qrHosts,
    ].where((e) => e.trim().isNotEmpty).map((e) => e.trim()).toSet().toList(growable: false);
    if (candidates.isEmpty || !candidates.any(GscApi.isSafeRemoteUrl)) {
      setState(() {
        manualOpen = true;
        error = 'LAN 또는 Tailscale 주소를 입력해 주세요. 예: 192.168.0.20:8787 또는 100.x.x.x:8787';
      });
      return;
    }
    if (rawCode.length != 8) {
      setState(() {
        manualOpen = true;
        error = '연결 코드는 8자리입니다. GSC에서 새 코드를 생성해 주세요.';
      });
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final deviceId = await widget.store.deviceId();
    final deviceName = name.text.trim().isEmpty ? await widget.store.defaultDeviceName() : name.text.trim();
    GscApiException? lastNetworkError;
    for (final candidate in candidates) {
      if (!GscApi.isSafeRemoteUrl(candidate)) continue;
      final api = GscApi(hostUrl: candidate);
      try {
        final result = await api.claimPairing(code: rawCode, deviceId: deviceId, name: deviceName);
        if (!result.ok || result.deviceToken.isEmpty) {
          throw GscApiException('GSC에서 기기 토큰을 발급하지 못했습니다.');
        }
        api.token = result.deviceToken;
        final info = await api.info();
        if (info.apiVersion < 1 || !info.features.contains('pairing-v2')) {
          throw GscApiException('GSC 4.2.x 이상이 필요합니다.');
        }
        final saved = StoredConnection(
          hostUrl: api.baseUri.toString(),
          deviceToken: result.deviceToken,
          deviceId: result.deviceId,
          deviceName: deviceName,
        );
        await widget.onConnected(saved);
        api.close();
        if (mounted) setState(() => busy = false);
        return;
      } on GscApiException catch (e) {
        api.close();
        if (e.kind == 'network' || e.kind == 'refused' || e.kind == 'timeout') {
          lastNetworkError = e;
          continue;
        }
        if (mounted) {
          setState(() {
            error = e.message;
            busy = false;
          });
        }
        return;
      }
    }
    if (mounted) {
      setState(() {
        busy = false;
        manualOpen = true;
        error = lastNetworkError?.message ?? 'GSC에 연결할 수 없습니다. Wi-Fi/Tailscale 상태를 확인해 주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [cs.primary.withValues(alpha: .24), const Color(0xFF0E2236)]),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: cs.primary.withValues(alpha: .30)),
                  ),
                  child: Column(children: [
                    Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(color: cs.primary.withValues(alpha: .14), shape: BoxShape.circle),
                      child: Icon(Icons.dns_rounded, size: 40, color: cs.primary),
                    ),
                    const SizedBox(height: 16),
                    Text('GSCM', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: .5)),
                    const SizedBox(height: 5),
                    Text('Geumyi Server Center Mobile', style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 10),
                    Text('서버 상태 확인부터 콘솔 · 플레이어 · 백업 · 자동화까지 휴대폰에서 관리합니다.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: busy ? null : _scan,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Padding(padding: EdgeInsets.symmetric(vertical: 5), child: Text('GSC QR 스캔으로 바로 연결', style: TextStyle(fontWeight: FontWeight.w800))),
                ),
                const SizedBox(height: 10),
                Text('GSC에서 “5분 연결 코드 + QR”을 만든 뒤 스캔하면 주소와 코드를 자동 입력합니다.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 18),
                Card(
                  child: ExpansionTile(
                    initiallyExpanded: manualOpen,
                    onExpansionChanged: (v) => setState(() => manualOpen = v),
                    leading: const Icon(Icons.tune_rounded),
                    title: const Text('수동 연결', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: const Text('QR을 못 쓰는 경우 주소 + 8자리 코드 입력'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      TextField(controller: host, keyboardType: TextInputType.url, autocorrect: false, decoration: const InputDecoration(labelText: 'GSC 주소', hintText: '192.168.0.20:8787 또는 100.x.x.x:8787', prefixIcon: Icon(Icons.lan_rounded))),
                      const SizedBox(height: 12),
                      TextField(controller: code, keyboardType: TextInputType.number, maxLength: 8, decoration: const InputDecoration(labelText: '8자리 연결 코드', prefixIcon: Icon(Icons.password_rounded), counterText: '')),
                      const SizedBox(height: 12),
                      TextField(controller: name, maxLength: 40, decoration: const InputDecoration(labelText: '이 기기 이름', prefixIcon: Icon(Icons.phone_android_rounded), counterText: '')),
                      const SizedBox(height: 14),
                      FilledButton.tonalIcon(onPressed: busy ? null : _connect, icon: const Icon(Icons.link_rounded), label: const Text('수동 연결')),
                    ],
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: cs.errorContainer.withValues(alpha: .55), borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.error.withValues(alpha: .35))),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.error_outline_rounded, color: cs.error),
                      const SizedBox(width: 10),
                      Expanded(child: Text(error!, style: TextStyle(color: cs.onErrorContainer))),
                    ]),
                  ),
                ],
                if (busy) ...[
                  const SizedBox(height: 14),
                  const LinearProgressIndicator(minHeight: 3),
                  const SizedBox(height: 8),
                  const Text('GSC에 기기를 등록하고 있습니다…', textAlign: TextAlign.center),
                ],
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.shield_outlined, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Flexible(child: Text('GSCM은 GSC의 8787 포트만 사용합니다. RCON/GDS/Agent는 휴대폰에 직접 노출하지 않습니다.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
