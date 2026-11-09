import 'package:flutter/material.dart';

/// Nom du logiciel et coordonnées du développeur, identiques au pied de page du site.
class DeveloperFooter extends StatelessWidget {
  const DeveloperFooter({super.key});

  static const product = 'Application Saad Tejda';
  static const credits = 'Développé par Saad Tejda · www.saadtejda.com';
  static const phones = '+212 526 600 025 · +212 670 713 978';

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(product, textAlign: TextAlign.center, style: style?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(credits, textAlign: TextAlign.center, style: style),
        Text(phones, textAlign: TextAlign.center, style: style),
      ]),
    );
  }
}
