import 'package:flutter/material.dart';

class MiniLineChart extends StatelessWidget {
  const MiniLineChart({super.key, required this.values, required this.min, required this.max, this.height = 120});
  final List<double> values;
  final double min;
  final double max;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _ChartPainter(values: values, min: min, max: max, color: Theme.of(context).colorScheme.primary)),
      );
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.values, required this.min, required this.max, required this.color});
  final List<double> values;
  final double min;
  final double max;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = Colors.white.withValues(alpha: .07)..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.length < 2) return;
    final span = (max - min).abs() < .0001 ? 1.0 : max - min;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final normalized = ((values[i] - min) / span).clamp(0.0, 1.0).toDouble();
      final y = size.height * (1 - normalized);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.2..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
  }
  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) => oldDelegate.values != values || oldDelegate.min != min || oldDelegate.max != max || oldDelegate.color != color;
}
