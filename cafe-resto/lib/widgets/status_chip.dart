import 'package:flutter/material.dart';

import '../theme/pos_theme.dart';

enum StatusTone {
  waiting,
  assigned,
  progress,
  delivered,
  paid,
  cancelled,
  pending,
  syncError,
  online,
  offline,
  open,
  closed,
  neutral,
  connecting,
}

Color statusColor(StatusTone tone) {
  return switch (tone) {
    StatusTone.waiting => PosColors.warning,
    StatusTone.assigned => PosColors.info,
    StatusTone.progress => PosColors.progress,
    StatusTone.delivered || StatusTone.online || StatusTone.open => PosColors.success,
    StatusTone.paid => PosColors.paid,
    StatusTone.cancelled || StatusTone.syncError || StatusTone.offline => PosColors.danger,
    StatusTone.pending || StatusTone.connecting => PosColors.accent,
    StatusTone.closed || StatusTone.neutral => PosColors.muted,
  };
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.tone});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(tone);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800, height: 1),
          ),
        ],
      ),
    );
  }
}
