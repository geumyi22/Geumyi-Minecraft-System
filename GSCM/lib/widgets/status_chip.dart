import 'package:flutter/material.dart';

Color statusColor(BuildContext context, String value) {
  final v = value.trim().toUpperCase();
  final ok = v == 'ONLINE' ||
      v == 'HEALTHY' ||
      v == 'COMPLETED' ||
      v == 'OK' ||
      v == 'REALTIME' ||
      v.contains('ONLINE') ||
      v.contains('정상') ||
      v.contains('허용');
  if (ok) return Colors.greenAccent.shade400;

  final busy = v == 'STARTING' ||
      v == 'RESTARTING' ||
      v == 'STOPPING' ||
      v == 'RUNNING' ||
      v == 'QUEUED' ||
      v == 'WATCH' ||
      v == 'WARN' ||
      v.contains('재연결') ||
      v.contains('예약') ||
      v.contains('실행 중');
  if (busy) return Colors.amberAccent.shade400;

  final bad = v == 'DEGRADED' ||
      v == 'CRITICAL' ||
      v == 'FAILED' ||
      v == 'FAIL' ||
      v == 'BOOT_FAILED' ||
      v == 'CRASHED' ||
      v.contains('실패') ||
      v.contains('ERROR') ||
      v.contains('제한');
  if (bad) return Colors.redAccent.shade200;

  if (v == 'MAINTENANCE' || v == 'RECOVERING' || v.contains('주의')) {
    return Colors.orangeAccent.shade200;
  }
  if (v == 'OFFLINE' || v.contains('OFFLINE') || v.contains('꺼짐')) {
    return Theme.of(context).colorScheme.outline;
  }
  return Theme.of(context).colorScheme.outline;
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(context, label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        border: Border.all(color: color.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon ?? Icons.circle, size: 9, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
