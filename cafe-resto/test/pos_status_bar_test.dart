import 'package:cafe_resto_caisse/theme/pos_theme.dart';
import 'package:cafe_resto_caisse/widgets/pos_status_bar.dart';
import 'package:cafe_resto_caisse/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chaque statut a sa couleur fixe', () {
    expect(statusColor(StatusTone.waiting), PosColors.warning);
    expect(statusColor(StatusTone.assigned), PosColors.info);
    expect(statusColor(StatusTone.progress), PosColors.progress);
    expect(statusColor(StatusTone.delivered), PosColors.success);
    expect(statusColor(StatusTone.paid), PosColors.paid);
    expect(statusColor(StatusTone.cancelled), PosColors.danger);
    expect(statusColor(StatusTone.pending), PosColors.accent);
    expect(statusColor(StatusTone.syncError), PosColors.danger);
    expect(statusColor(StatusTone.open), PosColors.success);
    expect(statusColor(StatusTone.closed), PosColors.muted);
  });

  testWidgets('la barre montre caisse, réseau, file et imprimante', (tester) async {
    await tester.pumpWidget(_frame(
      const PosStatusBar(
        online: true,
        sessionOpen: true,
        pending: 3,
        errors: 1,
        printer: PrinterChip.ready,
      ),
    ));
    expect(find.text('Caisse Resto'), findsOneWidget);
    expect(find.text('Ouverte'), findsOneWidget);
    expect(find.text('En ligne'), findsOneWidget);
    expect(find.text('2 à envoyer'), findsOneWidget);
    expect(find.text('1 erreur'), findsOneWidget);
    expect(find.text('Imprimante'), findsOneWidget);
    expect(find.text('Mode hors ligne. Les actions partent à la reconnexion.'), findsNothing);
  });

  testWidgets('hors ligne, la barre annonce la reprise et la caisse fermée', (tester) async {
    await tester.pumpWidget(_frame(
      const PosStatusBar(
        online: false,
        sessionOpen: false,
        pending: 0,
        errors: 0,
        printer: PrinterChip.down,
      ),
    ));
    expect(find.text('Fermée'), findsOneWidget);
    expect(find.text('Hors ligne'), findsOneWidget);
    expect(find.text('Imprimante coupée'), findsOneWidget);
    expect(find.text('Mode hors ligne. Les actions partent à la reconnexion.'), findsOneWidget);
    expect(find.textContaining('à envoyer'), findsNothing);
  });
}

Widget _frame(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: 960, child: child),
      ),
    ),
  );
}
