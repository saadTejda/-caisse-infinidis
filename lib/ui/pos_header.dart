import 'package:flutter/material.dart';

import '../core/app_state.dart';

/// En-tête de la caisse : logo et « Gestion Caisse · SAAD TEJDA » à gauche, magasin ou dépôt et état de la caisse à droite.
class PosHeader extends StatelessWidget {
  const PosHeader({super.key, required this.app, required this.wide});

  final AppState app;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      _Logo(url: (app.company['logo'] ?? '').toString()),
      const SizedBox(width: 10),
      if (wide) ...[
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Gestion Caisse', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Text('SAAD TEJDA · www.saadtejda.com', style: TextStyle(fontSize: 11, letterSpacing: .6, color: scheme.onSurfaceVariant)),
        ]),
        const Spacer(),
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 380), child: _StoreBadge(app: app)),
      ] else
        Expanded(child: Align(alignment: Alignment.centerLeft, child: _StoreBadge(app: app))),
    ]);
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mark = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]), borderRadius: BorderRadius.circular(10)),
      child: const Text('ST', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
    );
    return SizedBox(
      width: 42,
      height: 42,
      child: url.isEmpty
          ? mark
          : DecoratedBox(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: scheme.outlineVariant)),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Image.network(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => mark),
              ),
            ),
    );
  }
}

class _StoreBadge extends StatelessWidget {
  const _StoreBadge({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final store = app.store;
    final open = app.session != null;
    final depot = store?['kind'] == 'depot';
    final status = open ? 'Caisse ouverte' : 'Caisse fermée';
    final color = open ? Colors.green.shade700 : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: open ? Colors.green.withOpacity(.08) : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: open ? Colors.green.withOpacity(.35) : scheme.outlineVariant),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(depot ? Icons.warehouse_outlined : Icons.storefront_outlined, size: 22, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((store?['name'] ?? 'Aucun magasin').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, size: 8, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text('${depot ? 'Dépôt' : 'Magasin'} · $status · ${app.user?['name'] ?? ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: color)),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}
