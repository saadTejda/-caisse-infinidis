import 'package:flutter/material.dart';

import '../theme/pos_theme.dart';

class MatchText extends StatelessWidget {
  const MatchText({
    super.key,
    required this.text,
    required this.query,
    this.style,
    this.maxLines = 1,
  });

  final String text;
  final String query;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final base = style ?? const TextStyle(fontWeight: FontWeight.w800, color: PosColors.ink);
    final needle = query.trim();
    final index = needle.isEmpty ? -1 : text.toLowerCase().indexOf(needle.toLowerCase());
    if (index < 0) {
      return Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: base);
    }
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: text.substring(0, index)),
          TextSpan(text: text.substring(index, index + needle.length), style: base.copyWith(backgroundColor: const Color(0xFFFDE68A))),
          TextSpan(text: text.substring(index + needle.length)),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
