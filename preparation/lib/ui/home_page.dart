import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/sounds.dart';
import '../printing/label_printer.dart';
import 'scanner_page.dart';
import 'settings_page.dart';

/// Bandeau du dernier résultat (scan, action) : ok, bad, warn, info.
class Notice {
  Notice(this.tone, this.title, [this.text = '']);

  final String tone;
  final String title;
  final String text;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final app = AppState.instance;
  final _scan = TextEditingController();
  final _focus = FocusNode();
  bool _keyboard = false;
  bool _busy = false;
  bool _immersive = false;
  int _tab = 0;
  String? _openProduct;
  Notice? _notice;
  Timer? _noticeTimer;
  int _packaging = 0;
  int _packages = 1;
  int _weight = 0;
  dynamic _adopted;

  static const _weights = [500, 1000, 1900, 3000, 5000, 10000, 14000, 30000];
  static const _cardShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16)), side: BorderSide(color: Color(0xFFE2E8F0)));

  @override
  void initState() {
    super.initState();
    app.addListener(_onState);
    _focus.addListener(_hideKeyboard);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refocus());
  }

  /// La douchette tape comme un clavier : le clavier de l'écran reste caché tant qu'on ne le demande pas.
  void _hideKeyboard() {
    if (_focus.hasFocus && !_keyboard) {
      Future<void>.delayed(const Duration(milliseconds: 50), () => SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    }
  }

  @override
  void dispose() {
    app.removeListener(_onState);
    _noticeTimer?.cancel();
    _scan.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onState() {
    if (app.newOrders > 0) {
      final n = app.newOrders;
      app.newOrders = 0;
      Sounds.play('info');
      if (app.order == null) _say('info', '$n nouvelle(s) commande(s) à préparer');
    }
    final order = app.order;
    if (order != null && order['id'] != _adopted) {
      _adopted = order['id'];
      _packaging = asInt(order['packaging_id']) > 0 ? asInt(order['packaging_id']) : (app.packagings.isNotEmpty ? asInt(app.packagings.first['id']) : 0);
      _packages = asInt(order['packages']) > 0 ? asInt(order['packages']) : 1;
      _weight = asInt(order['weight_grams']);
    }
    if (order == null) _adopted = null;
    if (mounted) setState(() {});
  }

  void _say(String tone, String title, [String text = '']) {
    _noticeTimer?.cancel();
    setState(() => _notice = Notice(tone, title, text));
    if (tone != 'bad') {
      _noticeTimer = Timer(const Duration(seconds: 6), () {
        if (mounted && _notice?.title == title) setState(() => _notice = null);
      });
    }
  }

  void _refocus() {
    if (!mounted) return;
    _focus.requestFocus();
    _hideKeyboard();
  }

  bool get _needsWeight => app.order?['courier_kind'] == 'amana' && _weight <= 0;

  Future<void> _onScan(String raw) async {
    final text = raw.trim();
    _scan.clear();
    if (text.isEmpty || _busy) {
      _refocus();
      return;
    }
    if (app.order != null && app.locked) {
      await _run(() async {
        final message = await app.confirmLabel(text);
        Sounds.play('done');
        _say('ok', message, 'Commande suivante…');
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await _next();
      });
    } else if (app.order != null) {
      await _run(() async {
        final data = await app.scan(text);
        final result = data['result'];
        if (result == 'added') {
          Sounds.play(app.complete ? 'done' : 'ok');
          _say('ok', (data['message'] ?? '').toString(), app.complete ? 'Tout est scanné.' : '');
          if (app.complete && app.settings.autoFinish && !_needsWeight) await _finishNow();
        } else {
          Sounds.play('error');
          _say('bad', (data['message'] ?? 'Mauvais produit.').toString());
        }
      });
    } else {
      await _open(text);
    }
    _refocus();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      Sounds.play('error');
      _say('bad', e.message);
    } on PrintException catch (e) {
      Sounds.play('warn');
      _say('warn', 'Impression : ${e.message}', 'Touchez « Imprimer l’étiquette » pour réessayer.');
    } catch (e) {
      Sounds.play('error');
      _say('bad', e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
      _refocus();
    }
  }

  Future<void> _open(dynamic codeOrId) async {
    await _run(() async {
      final order = await app.open('$codeOrId');
      setState(() => _tab = 0);
      Sounds.play('info');
      _say('info', 'Commande ${order['code']} ouverte',
          order['prep'] == 'prepared' ? 'Déjà préparée : scannez l’étiquette collée.' : '${asInt(order['total']) - asInt(order['done'])} article(s) à scanner.');
    });
  }

  Future<void> _next() async {
    final next = app.nextInQueue();
    if (next == null) {
      app.setOrder(null);
      _say('ok', 'Plus aucune commande à préparer.', 'Les nouvelles arrivent toutes seules ici.');
      return;
    }
    await _open(next['id']);
  }

  Future<void> _finishNow({bool force = false, String reason = ''}) async {
    if (_needsWeight) {
      Sounds.play('warn');
      _say('warn', 'Poids obligatoire pour Amana', 'Choisissez le poids du colis, puis « Préparé ».');
      return;
    }
    await app.finish(packagingId: _packaging, packages: _packages, weight: _weight > 0 ? _weight : null, force: force, reason: reason);
    Sounds.play('done');
    final courier = (app.order?['courier'] ?? '').toString();
    _say('ok', '${app.order?['code']} préparée · collez l’étiquette ${courier.isNotEmpty ? '« $courier »' : 'boutique'}', 'Puis scannez-la pour passer à la suivante.');
    if (app.settings.autoPrint) await _print(asInt(app.order?['id']));
  }

  Future<void> _print(int id) async {
    try {
      await LabelPrinter.printLabels([id]);
    } on PrintException catch (e) {
      Sounds.play('warn');
      _say('warn', 'Impression : ${e.message}', 'Touchez « Imprimer l’étiquette » pour réessayer.');
    } on ApiException catch (e) {
      Sounds.play('warn');
      _say('warn', 'Impression : ${e.message}');
    }
  }

  Future<void> _camera() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => ScannerPage(title: app.order == null ? 'Scanner une commande' : (app.locked ? 'Scanner l’étiquette collée' : 'Scanner un article'))));
    if (code != null) await _onScan(code);
  }

  Future<void> _hold() async {
    final other = TextEditingController();
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Problème sur ${app.order?['code']}', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('La commande est mise en attente avec le motif : le responsable la voit dans « En attente ».'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in app.holdReasons.isNotEmpty ? app.holdReasons : const ['Article manquant', 'Article abîmé'])
              ActionChip(label: Text(r), avatar: const Icon(Icons.report_problem_outlined, size: 18), onPressed: () => Navigator.pop(c, r)),
          ]),
          const SizedBox(height: 12),
          TextField(controller: other, decoration: const InputDecoration(labelText: 'Autre motif'), onSubmitted: (v) => Navigator.pop(c, v)),
          const SizedBox(height: 8),
          FilledButton(onPressed: () => Navigator.pop(c, other.text), child: const Text('Mettre en attente')),
        ]),
      ),
    );
    if (reason == null || reason.trim().isEmpty) {
      _refocus();
      return;
    }
    await _run(() async {
      final code = app.order?['code'];
      await app.hold(reason.trim());
      Sounds.play('warn');
      _say('warn', '$code mise en attente', reason.trim());
      await _next();
    });
  }

  Future<void> _force() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Forcer « Préparé »'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Motif (obligatoire)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, controller.text), child: const Text('Forcer')),
        ],
      ),
    );
    if (reason == null || reason.trim().isEmpty) {
      _refocus();
      return;
    }
    await _run(() => _finishNow(force: true, reason: reason.trim()));
  }

  Future<void> _pickWeight() async {
    final controller = TextEditingController(text: _weight > 0 ? '$_weight' : '');
    final grams = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Poids du colis'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [for (final w in _weights) ChoiceChip(label: Text(_kg(w)), selected: _weight == w, onSelected: (_) => Navigator.pop(c, w))]),
          const SizedBox(height: 12),
          TextField(controller: controller, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Autre poids (grammes)')),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(c, int.tryParse(controller.text.trim()) ?? 0), child: const Text('OK'))],
      ),
    );
    if (grams != null) setState(() => _weight = grams.clamp(0, 100000));
    _refocus();
  }

  String _kg(int grams) => grams >= 1000 ? '${(grams / 1000).toStringAsFixed(grams % 1000 == 0 ? 0 : 1)} kg' : '$grams g';

  void _toggleImmersive() {
    setState(() => _immersive = !_immersive);
    SystemChrome.setEnabledSystemUIMode(_immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: _immersive
          ? null
          : AppBar(
              title: Text(app.serverName.isNotEmpty ? 'Préparation · ${app.serverName}' : 'Préparation'),
              actions: [
                if (!app.online) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.cloud_off, color: Colors.red)),
                IconButton(tooltip: 'Actualiser', onPressed: () => app.refresh(), icon: const Icon(Icons.refresh)),
                IconButton(tooltip: 'Plein écran', onPressed: _toggleImmersive, icon: const Icon(Icons.fullscreen)),
                IconButton(
                  tooltip: 'Réglages',
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
                    if (mounted) setState(() {});
                    _refocus();
                  },
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(children: [
            if (_immersive) Align(alignment: Alignment.centerRight, child: IconButton(onPressed: _toggleImmersive, icon: const Icon(Icons.fullscreen_exit))),
            _stats(scheme),
            const SizedBox(height: 8),
            _scanBar(scheme),
            if (_notice != null) ...[const SizedBox(height: 8), _noticeBar()],
            if (app.feedError != null && !app.online) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Hors ligne : ${app.feedError}', style: const TextStyle(color: Colors.red))),
            const SizedBox(height: 8),
            _tabs(),
            const SizedBox(height: 8),
            Expanded(child: _content()),
          ]),
        ),
      ),
    );
  }

  Widget _stats(ColorScheme scheme) {
    final c = app.counts;
    final t = app.today;
    Widget box(String value, String label, {Color? color}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color ?? const Color(0xFF0F172A))),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            ]),
          ),
        );
    return Row(children: [
      box('${asInt(c['todo'])}', 'À préparer'),
      box('${asInt(c['progress'])}', 'En cours'),
      box('${asInt(c['hold'])}', 'En attente', color: asInt(c['hold']) > 0 ? Colors.orange.shade800 : null),
      box('${asInt(t['prepared'])}', 'Aujourd’hui · moi ${asInt(t['mine'])}', color: scheme.primary),
      box('${asInt(t['rate'])} %', 'Taux du jour'),
    ]);
  }

  Widget _scanBar(ColorScheme scheme) {
    final label = app.order != null && app.locked;
    final hint = app.order == null ? 'Scannez l’étiquette d’une commande' : (label ? 'Scannez l’étiquette collée sur ${app.order!['code']}' : 'Scannez un article de ${app.order!['code']}');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: label ? Colors.green : scheme.primary, width: 2)),
      child: Row(children: [
        Icon(label ? Icons.sell_outlined : Icons.qr_code_scanner, size: 30, color: label ? Colors.green : scheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _scan,
            focusNode: _focus,
            autofocus: true,
            keyboardType: _keyboard ? TextInputType.text : TextInputType.none,
            textInputAction: TextInputAction.go,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            decoration: InputDecoration(border: InputBorder.none, hintText: hint, isDense: true),
            onSubmitted: _onScan,
          ),
        ),
        if (_busy) const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))),
        IconButton(
          tooltip: _keyboard ? 'Masquer le clavier' : 'Taper le code',
          onPressed: () {
            setState(() => _keyboard = !_keyboard);
            _focus.unfocus();
            Future<void>.delayed(const Duration(milliseconds: 80), _refocus);
          },
          icon: Icon(_keyboard ? Icons.keyboard_hide_outlined : Icons.keyboard_outlined),
        ),
        FilledButton.icon(onPressed: _busy ? null : _camera, icon: const Icon(Icons.photo_camera_outlined), label: const Text('Caméra')),
      ]),
    );
  }

  Widget _noticeBar() {
    final n = _notice!;
    final colors = {
      'ok': (const Color(0xFFECFDF5), const Color(0xFF065F46), Icons.check_circle),
      'bad': (const Color(0xFFFEF2F2), const Color(0xFF991B1B), Icons.cancel),
      'warn': (const Color(0xFFFFFBEB), const Color(0xFF92400E), Icons.warning_amber_rounded),
      'info': (const Color(0xFFEFF6FF), const Color(0xFF1E40AF), Icons.info),
    };
    final (bg, fg, icon) = colors[n.tone] ?? colors['info']!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: n.tone == 'bad' ? Border.all(color: const Color(0xFFFCA5A5), width: 2) : null),
      child: Row(children: [
        Icon(icon, color: fg, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n.title, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 16)),
            if (n.text.isNotEmpty) Text(n.text, style: TextStyle(color: fg)),
          ]),
        ),
        IconButton(onPressed: () => setState(() => _notice = null), icon: Icon(Icons.close, color: fg)),
      ]),
    );
  }

  Widget _tabs() {
    final c = app.counts;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: 0, icon: const Icon(Icons.list_alt), label: Text('À préparer (${asInt(c['todo']) + asInt(c['progress']) + asInt(c['hold'])})')),
          ButtonSegment(value: 1, icon: const Icon(Icons.layers_outlined), label: Text('Par produit (${app.products.length})')),
          ButtonSegment(value: 2, icon: const Icon(Icons.task_alt), label: Text('Préparées aujourd’hui (${app.done.length})')),
        ],
        selected: {_tab},
        onSelectionChanged: (v) {
          setState(() => _tab = v.first);
          _refocus();
        },
      ),
    );
  }

  Widget _content() {
    if (_tab == 1) return _productsView();
    if (_tab == 2) return _doneView();
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 900;
      if (wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 330, child: _queueView()),
          const SizedBox(width: 10),
          Expanded(child: app.order != null ? _orderView() : _welcome()),
        ]);
      }
      return app.order != null ? _orderView(back: true) : _queueView();
    });
  }

  Widget _image(dynamic variantId, bool has, double size) {
    final placeholder = Container(width: size, height: size, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.shopping_bag_outlined, color: const Color(0xFF94A3B8), size: size * 0.45));
    if (!has || variantId == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(app.imageUrl(variantId), headers: app.api!.authHeaders, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder),
    );
  }

  Widget _queueView() {
    final rows = app.queue;
    if (rows.isEmpty) {
      return _empty(Icons.inbox_outlined, 'Rien à préparer', 'Les commandes envoyées « À préparer » arrivent ici toutes seules.');
    }
    return RefreshIndicator(
      onRefresh: app.refresh,
      child: ListView.separated(
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, i) {
          final r = rows[i];
          final first = asMap(r['first']);
          final active = app.order?['id'] == r['id'];
          final hold = r['prep'] == 'on_hold';
          final articles = asInt(r['articles']);
          return Card(
            elevation: 0,
            color: active ? const Color(0xFFECFDF5) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: active ? Theme.of(context).colorScheme.primary : const Color(0xFFE2E8F0), width: active ? 2 : 1)),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _open(r['id']),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  _image(first['variant_id'], first['image'] == true, 56),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text((r['code'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w800))),
                        Text((r['waiting'] ?? '').toString(), style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                      ]),
                      Text('${r['customer']} · ${r['city']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      Text((r['courier'] ?? '').toString().isNotEmpty ? '🛵 ${r['courier']}' : 'Livreur non choisi',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: (r['courier'] ?? '').toString().isNotEmpty ? Theme.of(context).colorScheme.primary : Colors.red)),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: articles > 0 ? asInt(r['prepared']) / articles : 0, minHeight: 4, borderRadius: BorderRadius.circular(4)),
                      const SizedBox(height: 4),
                      Wrap(spacing: 4, runSpacing: 4, children: [
                        _chip('${asInt(r['prepared'])}/$articles article(s)'),
                        if (r['prep'] == 'started') _chip('En cours', color: Colors.blue),
                        if (r['short'] == true) _chip('Rupture', color: Colors.red),
                        if (hold) _chip('En attente', color: Colors.orange),
                      ]),
                    ]),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _chip(String text, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: (color ?? Colors.blueGrey).withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color ?? Colors.blueGrey.shade700)),
      );

  Widget _empty(IconData icon, String title, [String text = '']) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: const Color(0xFF94A3B8)),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (text.isNotEmpty) Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF64748B))),
          ]),
        ),
      );

  Widget _welcome() => Card(
        elevation: 0,
        shape: _cardShape,
        color: Colors.white,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.qr_code_scanner, size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              const Text('Scannez l’étiquette d’une commande', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Text('ou touchez-la dans la file. Ensuite, scannez chaque article : bip clair si c’est bon, son d’erreur sinon.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              if (app.queue.isNotEmpty) FilledButton.icon(onPressed: _next, icon: const Icon(Icons.play_arrow), label: const Text('Commencer par la plus ancienne')),
            ]),
          ),
        ),
      );

  Widget _orderView({bool back = false}) {
    final o = app.order!;
    final total = asInt(o['total']);
    final doneCount = asInt(o['done']);
    final lines = asList(o['lines']);
    final courier = (o['courier'] ?? '').toString();
    final api = o['courier_kind'] != 'internal' && courier.isNotEmpty;
    return Card(
      elevation: 0,
      shape: _cardShape,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (back) IconButton.outlined(onPressed: () => app.setOrder(null), icon: const Icon(Icons.arrow_back)),
            if (back) const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((o['code'] ?? '').toString(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                Text('${o['customer']} · ${o['city']} · ${o['cod']} DH', style: const TextStyle(color: Color(0xFF64748B))),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: courier.isEmpty ? const Color(0xFFFEF2F2) : (api ? const Color(0xFFE0F2FE) : const Color(0xFFEEF2FF)), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('ÉTIQUETTE', style: TextStyle(fontSize: 10, letterSpacing: 0.6, color: Color(0xFF475569))),
                Text(courier.isNotEmpty ? courier : 'Boutique', style: TextStyle(fontWeight: FontWeight.bold, color: courier.isEmpty ? Colors.red.shade800 : const Color(0xFF1E3A8A))),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: LinearProgressIndicator(value: total > 0 ? (app.locked ? 1 : doneCount / total) : 0, minHeight: 14, borderRadius: BorderRadius.circular(8), color: app.complete || app.locked ? Colors.green : null)),
            const SizedBox(width: 10),
            Text('$doneCount / $total', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (o['short'] == true) _chip('Rupture au dépôt', color: Colors.red),
            if (o['open_package'] == true) _chip('Ouverture autorisée'),
            if (o['exchange'] == true) _chip('Échange'),
            if ((o['hold_reason'] ?? '').toString().isNotEmpty) _chip('En attente : ${o['hold_reason']}', color: Colors.orange),
            if (o['forced'] == true) _chip('Forcé : ${o['force_reason']}', color: Colors.red),
          ]),
          if ((o['notes'] ?? '').toString().isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(10)),
              child: Text('📝 ${o['notes']}', style: const TextStyle(color: Color(0xFF92400E))),
            ),
          if (app.locked) _labelPanel(o),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: lines.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, i) => _line(lines[i]),
            ),
          ),
          if (!app.locked) _footer(o),
        ]),
      ),
    );
  }

  Widget _labelPanel(Map<String, dynamic> o) {
    final courier = (o['courier'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.green, width: 2)),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 8, children: [
        const Icon(Icons.print, size: 36, color: Color(0xFF065F46)),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Collez l’étiquette ${courier.isNotEmpty ? '« $courier »' : 'boutique'} sur le colis', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF065F46))),
            Text('Puis scannez-la : la commande suivante s’ouvre toute seule. ${asInt(o['packages'])} colis · ${o['prepared_by']}', style: const TextStyle(color: Color(0xFF065F46))),
          ]),
        ),
        FilledButton.icon(onPressed: _busy ? null : () => _run(() => _print(asInt(o['id']))), icon: const Icon(Icons.print), label: const Text('Imprimer l’étiquette')),
        OutlinedButton.icon(onPressed: _busy ? null : _next, icon: const Icon(Icons.skip_next), label: const Text('Suivante')),
        TextButton.icon(onPressed: _busy ? null : () => _run(app.resume), icon: const Icon(Icons.undo), label: const Text('Rouvrir')),
      ]),
    );
  }

  Widget _line(Map<String, dynamic> l) {
    final qty = asInt(l['quantity']);
    final prepared = asInt(l['prepared']);
    final full = prepared >= qty;
    final short = l['short'] == true;
    final fromSale = l['from_sale'] == true;
    final codes = [l['sku'], l['barcode']].where((v) => (v ?? '').toString().isNotEmpty).join(' · ');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: short ? const Color(0xFFFEF2F2) : (full ? const Color(0xFFF0FDF4) : Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: short ? const Color(0xFFFCA5A5) : (full ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0)), width: 1.5),
      ),
      child: Row(children: [
        _image(l['variant_id'], l['image'] == true, 76),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((l['label'] ?? '').toString(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(fromSale ? 'Vente caisse : stock déjà sorti au magasin' : (codes.isNotEmpty ? codes : 'Sans code : validez à la main'),
                style: TextStyle(color: fromSale ? Colors.green.shade700 : const Color(0xFF64748B))),
          ]),
        ),
        Column(children: [
          Text('$prepared', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: full ? Colors.green.shade700 : null)),
          Text('/ $qty', style: const TextStyle(color: Color(0xFF64748B))),
        ]),
        const SizedBox(width: 8),
        if (!app.locked && !fromSale)
          Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton.outlined(onPressed: prepared > 0 && !_busy ? () => _run(() => app.setLine(asInt(l['id']), prepared - 1)) : null, icon: const Icon(Icons.remove)),
              IconButton.outlined(onPressed: !full && !_busy ? () => _run(() => _addLine(l, prepared + 1)) : null, icon: const Icon(Icons.add)),
            ]),
            TextButton(onPressed: !full && !_busy ? () => _run(() => _addLine(l, qty)) : null, child: const Text('Tout valider')),
          ])
        else
          const Icon(Icons.check_circle, color: Colors.green, size: 34),
      ]),
    );
  }

  Future<void> _addLine(Map<String, dynamic> l, int quantity) async {
    await app.setLine(asInt(l['id']), quantity);
    Sounds.play(app.complete ? 'done' : 'ok');
    if (app.complete && app.settings.autoFinish && !_needsWeight) await _finishNow();
  }

  Widget _footer(Map<String, dynamic> o) {
    final packagings = app.packagings;
    final hold = o['prep'] == 'on_hold';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.end, alignment: WrapAlignment.spaceBetween, children: [
        if (packagings.isNotEmpty)
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<int>(
              value: packagings.any((p) => asInt(p['id']) == _packaging) ? _packaging : null,
              decoration: const InputDecoration(labelText: 'Emballage'),
              items: [for (final p in packagings) DropdownMenuItem(value: asInt(p['id']), child: Text((p['label'] ?? '').toString(), overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _packaging = v ?? 0),
            ),
          ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('Colis '),
          IconButton(onPressed: _packages > 1 ? () => setState(() => _packages--) : null, icon: const Icon(Icons.remove_circle_outline)),
          Text('$_packages', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          IconButton(onPressed: _packages < 50 ? () => setState(() => _packages++) : null, icon: const Icon(Icons.add_circle_outline)),
        ]),
        OutlinedButton.icon(
          onPressed: _pickWeight,
          icon: Icon(Icons.scale_outlined, color: _needsWeight ? Colors.red : null),
          label: Text(_weight > 0 ? 'Poids ${_kg(_weight)}' : (o['courier_kind'] == 'amana' ? 'Poids obligatoire' : 'Poids'), style: TextStyle(color: _needsWeight ? Colors.red : null)),
        ),
        if (hold)
          OutlinedButton.icon(onPressed: _busy ? null : () => _run(app.resume), icon: const Icon(Icons.play_arrow), label: const Text('Reprendre'))
        else
          OutlinedButton.icon(onPressed: _busy ? null : _hold, icon: const Icon(Icons.report_problem_outlined, color: Colors.orange), label: const Text('Problème')),
        if (!app.complete && app.abilities['force'] == true) OutlinedButton.icon(onPressed: _busy ? null : _force, icon: const Icon(Icons.warning_amber, color: Colors.red), label: const Text('Forcer')),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(220, 56), backgroundColor: Colors.green.shade700),
          onPressed: _busy || !app.complete ? null : () => _run(_finishNow),
          icon: const Icon(Icons.check_circle_outline),
          label: Text(app.settings.autoPrint ? 'Préparé + étiquette' : 'Préparé', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }

  Widget _productsView() {
    final rows = app.products;
    if (rows.isEmpty) return _empty(Icons.layers_outlined, 'Aucun article à prélever');
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final p = rows[i];
        final open = _openProduct == p['key'];
        final orders = asList(p['orders']);
        return Card(
          elevation: 0,
          shape: _cardShape,
          color: Colors.white,
          child: Column(children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _openProduct = open ? null : p['key'].toString()),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  _image(p['variant_id'], p['image'] == true, 68),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text((p['label'] ?? '').toString(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      Text((p['reference'] ?? '').toString().isNotEmpty ? p['reference'].toString() : 'Sans référence', style: const TextStyle(color: Color(0xFF64748B))),
                      Text('${orders.length} commande(s)${p['short'] == true ? ' · rupture' : ''}', style: TextStyle(color: p['short'] == true ? Colors.red : const Color(0xFF64748B))),
                    ]),
                  ),
                  Column(children: [
                    Text('${asInt(p['quantity'])}', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
                    const Text('à prélever', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                  ]),
                  Icon(open ? Icons.expand_less : Icons.expand_more),
                ]),
              ),
            ),
            if (open)
              for (final o in orders)
                ListTile(
                  dense: true,
                  title: Text((o['code'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Text('× ${asInt(o['quantity'])}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  onTap: () => _open(o['id']),
                ),
          ]),
        );
      },
    );
  }

  Widget _doneView() {
    final rows = app.done;
    if (rows.isEmpty) return _empty(Icons.task_alt, 'Aucune commande préparée aujourd’hui');
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final d = rows[i];
        final collected = d['collected'] == true;
        final labelled = d['labelled'] == true;
        return Card(
          elevation: 0,
          shape: _cardShape,
          color: Colors.white,
          child: ListTile(
            leading: Icon(collected ? Icons.local_shipping_outlined : Icons.check_circle, color: collected ? Colors.blue : Colors.green, size: 32),
            title: Text('${d['code']} · ${d['customer']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${d['at']} · ${d['by']} · ${asInt(d['packages'])} colis · ${(d['courier'] ?? '').toString().isNotEmpty ? d['courier'] : 'livreur non choisi'}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              _chip(collected ? 'Remis' : (labelled ? 'Étiquette imprimée' : 'Sans étiquette'), color: collected ? Colors.blue : (labelled ? Colors.green : Colors.orange)),
              IconButton(tooltip: 'Réimprimer l’étiquette', onPressed: _busy ? null : () => _run(() => _print(asInt(d['id']))), icon: const Icon(Icons.print_outlined)),
            ]),
          ),
        );
      },
    );
  }
}
