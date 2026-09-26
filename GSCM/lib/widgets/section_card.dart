import 'package:flutter/material.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
    this.icon,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final content = <Widget>[];
    final sectionTitle = title;
    if (sectionTitle != null) {
      final header = <Widget>[
        if (icon != null) ...[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            sectionTitle,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ];
      if (trailing != null) header.add(trailing!);
      content
        ..add(Row(children: header))
        ..add(const SizedBox(height: 13));
    }
    content.add(child);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: content),
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.label, required this.value, this.icon, this.progress, this.compact = false});
  final String label;
  final String value;
  final IconData? icon;
  final double? progress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1622),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF20374F)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: cs.primary),
            const SizedBox(width: 6),
          ],
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant))),
        ]),
        SizedBox(height: compact ? 5 : 7),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        if (progress != null) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress!.clamp(0, 1).toDouble(), minHeight: 4, borderRadius: BorderRadius.circular(99)),
        ],
      ]),
    );
  }
}
