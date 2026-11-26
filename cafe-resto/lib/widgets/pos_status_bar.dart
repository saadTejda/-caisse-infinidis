import 'package:flutter/material.dart';

import 'status_chip.dart';

enum PrinterChip { hidden, connecting, ready, down }

class PosStatusBar extends StatelessWidget {
  const PosStatusBar({
    super.key,
    required this.online,
    required this.sessionOpen,
    required this.pending,
    required this.errors,
    required this.printer,
  });

  final bool? online;
  final bool? sessionOpen;
  final int pending;
  final int errors;
  final PrinterChip printer;

  @override
  Widget build(BuildContext context) {
    final waiting = pending - errors;
    return Material(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Text('Caisse Resto', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (sessionOpen != null)
                        StatusChip(
                          label: sessionOpen! ? 'Ouverte' : 'Fermée',
                          tone: sessionOpen! ? StatusTone.open : StatusTone.closed,
                        ),
                      StatusChip(
                        label: online == null ? 'Vérification' : (online! ? 'En ligne' : 'Hors ligne'),
                        tone: online == null ? StatusTone.neutral : (online! ? StatusTone.online : StatusTone.offline),
                      ),
                      if (waiting > 0) StatusChip(label: waiting == 1 ? '1 à envoyer' : '$waiting à envoyer', tone: StatusTone.pending),
                      if (errors > 0) StatusChip(label: errors == 1 ? '1 erreur' : '$errors erreurs', tone: StatusTone.syncError),
                      if (printer != PrinterChip.hidden) StatusChip(label: _printerLabel(printer), tone: _printerTone(printer)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (online == false)
            Container(
              width: double.infinity,
              color: statusColor(StatusTone.pending).withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                'Mode hors ligne. Les actions partent à la reconnexion.',
                style: TextStyle(color: statusColor(StatusTone.pending), fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  String _printerLabel(PrinterChip value) {
    return switch (value) {
      PrinterChip.connecting => 'Imprimante…',
      PrinterChip.ready => 'Imprimante',
      PrinterChip.down => 'Imprimante coupée',
      PrinterChip.hidden => '',
    };
  }

  StatusTone _printerTone(PrinterChip value) {
    return switch (value) {
      PrinterChip.connecting => StatusTone.connecting,
      PrinterChip.ready => StatusTone.delivered,
      PrinterChip.down => StatusTone.offline,
      PrinterChip.hidden => StatusTone.neutral,
    };
  }
}
