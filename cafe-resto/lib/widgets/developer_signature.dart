import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/pos_theme.dart';

/// Signature affichée sur l’adresse du serveur et sur la connexion.
class DeveloperSignature extends StatelessWidget {
  const DeveloperSignature({super.key});

  static final _site = Uri.parse('https://www.saadtejda.com');

  Future<void> _open() async {
    await launchUrl(_site, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    const line = TextStyle(color: PosColors.muted, fontSize: 12, height: 1.45);
    return Column(
      children: [
        const SizedBox(height: 18),
        Container(
          width: 42,
          height: 3,
          decoration: BoxDecoration(
            color: PosColors.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Conception & développement : Saad Tejda',
          textAlign: TextAlign.center,
          style: line,
        ),
        const Directionality(
          textDirection: TextDirection.rtl,
          child: Text(
            'تصميم وتطوير : سعد تجدة',
            textAlign: TextAlign.center,
            style: line,
          ),
        ),
        TextButton(
          onPressed: _open,
          child: const Text('www.saadtejda.com'),
        ),
        const Text(
          '0670713978 - 0526600025',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: PosColors.ink,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
