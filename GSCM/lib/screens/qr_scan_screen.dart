import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScanResult {
  const QrScanResult({required this.host, required this.code, this.hosts = const <String>[]});
  final String host;
  final String code;
  final List<String> hosts;
}

QrScanResult? parseGscmClaim(String raw) {
  try {
    final uri = Uri.parse(raw.trim());
    if (uri.scheme.toLowerCase() != 'gscm' || uri.host.toLowerCase() != 'pair') return null;
    final host = uri.queryParameters['host']?.trim() ?? '';
    final code = (uri.queryParameters['code'] ?? '').replaceAll(RegExp(r'\D'), '');
    final rawHosts = uri.queryParameters['hosts']?.trim() ?? '';
    final hosts = <String>{
      if (host.isNotEmpty) host,
      ...rawHosts.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
    }.toList(growable: false);
    if (host.isEmpty || code.length != 8) return null;
    return QrScanResult(host: host, code: code, hosts: hosts);
  } catch (_) {
    return null;
  }
}

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool finished = false;
  bool torchOn = false;
  String? error;
  DateTime? lastInvalid;

  void _detect(BarcodeCapture capture) {
    if (finished) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null) continue;
      final parsed = parseGscmClaim(value);
      if (parsed != null) {
        finished = true;
        controller.stop();
        Navigator.of(context).pop(parsed);
        return;
      }
    }
    final now = DateTime.now();
    if (lastInvalid == null || now.difference(lastInvalid!) > const Duration(seconds: 1)) {
      lastInvalid = now;
      if (mounted && error == null) setState(() => error = 'GSC에서 생성한 GSCM 연결 QR을 화면 안에 맞춰 주세요.');
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR로 연결'),
        actions: [
          IconButton(
            tooltip: '플래시',
            onPressed: () async {
              await controller.toggleTorch();
              if (mounted) setState(() => torchOn = !torchOn);
            },
            icon: Icon(torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded),
          ),
        ],
      ),
      body: Stack(children: [
        MobileScanner(controller: controller, onDetect: _detect),
        Container(color: Colors.black.withValues(alpha: .13)),
        Center(
          child: Container(
            width: 270,
            height: 270,
            decoration: BoxDecoration(
              border: Border.all(color: cs.primary, width: 3),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: .20), blurRadius: 20, spreadRadius: 2)],
            ),
          ),
        ),
        Positioned(
          left: 18,
          right: 18,
          bottom: 28,
          child: Card(
            color: const Color(0xE615202C),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.qr_code_2_rounded), SizedBox(width: 8), Text('GSC의 연결 QR을 스캔하세요', style: TextStyle(fontWeight: FontWeight.w800))]),
                const SizedBox(height: 7),
                Text('GSC → GSCM 모바일 연결 → “5분 연결 코드 + QR”', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(color: cs.error), textAlign: TextAlign.center),
                ],
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
