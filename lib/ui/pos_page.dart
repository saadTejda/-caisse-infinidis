import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../core/product_images.dart';
import '../main.dart';
import '../printing/printer_service.dart';
import 'contact_picker.dart';
import 'history_page.dart';
import 'movement_dialog.dart';
import 'payment_sheet.dart';
import 'return_page.dart';
import 'pending_page.dart';
import 'printer_settings.dart';
import 'scanner_page.dart';
import 'session_dialog.dart';
import 'setup_page.dart';
import 'sync_dialog.dart';

class PosPage extends StatefulWidget {
  const PosPage({super.key});

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  final app = AppState.instance;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final List<CartLine> _cart = [];
  List<Product> _products = [];
  Contact? _contact;
  String? _discountType;
  double _discountValue = 0;
  int? _category;
  int _tab = 0;
  bool _paying = false;
  String? _seenSync;
  int _seenCatalog = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _seenSync = app.lastSync;
    app.addListener(_onApp);
    _loadProducts();
    _startup();
  }

  @override
  void dispose() {
    app.removeListener(_onApp);
    _debounce?.cancel();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onApp() {
    if (app.lastSync != _seenSync || app.catalogVersion != _seenCatalog) {
      _seenSync = app.lastSync;
      _seenCatalog = app.catalogVersion;
      _loadProducts();
    }
    if (mounted) setState(() {});
  }

  Future<void> _startup() async {
    if (!await app.checkOnline()) return;
    try {
      await app.syncAll();
    } on ApiException catch (e) {
      if (mounted && !e.network) toast(context, e.message, error: true);
    }
  }

  Future<void> _loadProducts() async {
    final items = await app.db.products(query: _search.text, categoryId: _category);
    if (mounted) setState(() => _products = items);
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _loadProducts);
  }

  /// Douchette (clavier) ou saisie + Entrée : code exact → ajout direct au panier.
  Future<void> _onSearchSubmitted(String value) async {
    final code = value.trim();
    if (code.isEmpty) return;
    final p = await app.db.productByCode(code);
    if (p != null) {
      _add(p);
      _search.clear();
      await _loadProducts();
    } else if (RegExp(r'^T-\d{4}-\d{4,}$', caseSensitive: false).hasMatch(code) && app.abilities['return'] == true) {
      _search.clear();
      await _loadProducts();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReturnPage(number: code)));
    } else {
      await _loadProducts();
      if (_products.length == 1) {
        _add(_products.first);
        _search.clear();
        await _loadProducts();
      } else if (_products.isEmpty && mounted) {
        toast(context, 'Aucun produit pour « $code ». Synchronisez les produits s’il vient d’être créé.', error: true);
      }
    }
    _searchFocus.requestFocus();
  }

  Future<void> _scanCamera() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScannerPage()));
    if (code == null) return;
    final p = await app.db.productByCode(code);
    if (!mounted) return;
    if (p == null) {
      toast(context, 'Code $code inconnu sur la tablette.', error: true);
    } else {
      _add(p);
    }
  }

  void _add(Product p) {
    if (p.price == null) {
      toast(context, '${p.label} n’a pas de prix de vente.', error: true);
      return;
    }
    setState(() {
      final line = _cart.where((l) => l.product.variantId == p.variantId).firstOrNull;
      if (line != null) {
        line.quantity++;
      } else {
        _cart.add(CartLine(p, 1));
      }
    });
    final inCart = _cart.firstWhere((l) => l.product.variantId == p.variantId).quantity;
    if (inCart > p.storeAvailable + p.depotAvailable && app.pricing['allow_negative'] != true && app.online) {
      toast(context, 'Stock insuffisant pour ${p.label} (magasin ${p.storeAvailable}, dépôt ${p.depotAvailable}).', error: true);
    }
  }

  void _qty(CartLine line, int delta) {
    setState(() {
      line.quantity += delta;
      if (line.quantity <= 0) _cart.remove(line);
    });
  }

  Totals get _totals => _totalsWith(0);

  Totals _totalsWith(double shipping) => Totals.compute(_cart,
      vat: app.pricing['vat'] == true,
      includesTax: app.pricing['includes_tax'] != false,
      discountType: _discountType,
      discountValue: _discountValue,
      shipping: shipping,
      shippingRate: app.shippingRate);

  Future<void> _editQty(CartLine line) async {
    final c = TextEditingController(text: '${line.quantity}');
    final v = await showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(line.product.label),
        content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantité')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, int.tryParse(c.text.trim())), child: const Text('OK')),
        ],
      ),
    );
    if (v == null) return;
    setState(() {
      if (v <= 0) {
        _cart.remove(line);
      } else {
        line.quantity = v;
      }
    });
  }

  Future<void> _editDiscount() async {
    String type = _discountType ?? 'percent';
    final c = TextEditingController(text: _discountValue > 0 ? _discountValue.toString() : '');
    final max = app.abilities['discount_max'];
    final result = await showDialog<(String?, double)>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setState) => AlertDialog(
          title: const Text('Remise sur le ticket'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<String>(
              segments: [const ButtonSegment(value: 'percent', label: Text('%')), ButtonSegment(value: 'amount', label: Text(app.currency))],
              selected: {type},
              onSelectionChanged: (s) => setState(() => type = s.first),
            ),
            const SizedBox(height: 12),
            TextField(controller: c, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Valeur')),
            if (max != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Remise maximale autorisée : $max %', style: Theme.of(d).textTheme.bodySmall)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, (null, 0.0)), child: const Text('Sans remise')),
            FilledButton(onPressed: () => Navigator.pop(d, (type, toNum(c.text))), child: const Text('Appliquer')),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      _discountType = result.$2 > 0 ? result.$1 : null;
      _discountValue = result.$2 > 0 ? result.$2 : 0;
    });
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty || _paying) return;
    if (app.session == null) {
      toast(context, 'La caisse n’est pas ouverte.', error: true);
      return;
    }
    final pay = await showPayment(context, totalsFor: _totalsWith, contact: _contact);
    if (pay == null || !mounted) return;
    setState(() => _paying = true);
    try {
      final result = await app.checkout(
        lines: _cart,
        totals: pay.totals,
        payment: pay.payload,
        contact: pay.contact,
        discountType: _discountType,
        discountValue: _discountValue,
      );
      setState(() {
        _cart.clear();
        _contact = null;
        _discountType = null;
        _discountValue = 0;
        _tab = 0;
      });
      await _loadProducts();
      final printer = PrinterService.instance.config;
      String? printError;
      if (printer != null && printer.ready && printer.autoPrint) {
        try {
          await PrinterService.instance.printTicket(result.ticket, openDrawer: pay.cash);
        } catch (e) {
          printError = e.toString();
        }
      }
      if (!mounted) return;
      await _done(result, printError);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.message.startsWith('Connectez-vous')) {
        await showOnlineRequired(context, e.message);
      } else {
        await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            icon: const Icon(Icons.error_outline, color: Colors.red, size: 40),
            title: const Text('Vente refusée'),
            content: Text(e.message),
            actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _paying = false);
      _searchFocus.requestFocus();
    }
  }

  Future<void> _done(SaleResult r, String? printError) async {
    final t = r.ticket;
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(r.offline ? Icons.cloud_off : Icons.check_circle, color: r.offline ? Colors.orange : Colors.green, size: 44),
        title: Text('Vente ${t['number']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${t['total']} ${app.currency}', style: Theme.of(c).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          if (toNum(t['change']) > 0) Text('Rendu : ${t['change']} ${app.currency}', style: Theme.of(c).textTheme.titleLarge),
          if (toNum(t['due']) > 0) Text('Reste dû (crédit) : ${t['due']} ${app.currency}'),
          if (t['shipment'] is Map)
            Text('À livrer · colis ${(t['shipment'] as Map)['code']} · à encaisser ${t['cod']} ${app.currency}', textAlign: TextAlign.center),
          if (r.message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(r.message!, textAlign: TextAlign.center)),
          if (printError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Impression : $printError', style: const TextStyle(color: Colors.red))),
        ]),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.print_outlined),
            label: const Text('Imprimer'),
            onPressed: () async {
              try {
                await PrinterService.instance.printTicket(t);
              } catch (e) {
                if (context.mounted) toast(context, e.toString(), error: true);
              }
            },
          ),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Nouvelle vente')),
        ],
      ),
    );
  }

  Future<void> _menu(String action) async {
    switch (action) {
      case 'history':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryPage()));
        await _loadProducts();
      case 'return':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReturnPage()));
        await _loadProducts();
      case 'movement':
        await showCashMovement(context);
      case 'printer':
        await showPrinterSettings(context);
      case 'close':
        await showCloseSession(context);
      case 'store':
        await _pickStore();
      case 'server':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SetupPage(changing: true)));
      case 'logout':
        if (app.pending > 0) {
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Ventes en attente'),
              content: Text('${app.pending} vente(s) hors ligne ne sont pas encore envoyées. Elles resteront sur la tablette et partiront à la prochaine connexion.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Se déconnecter')),
              ],
            ),
          );
          if (ok != true) return;
        }
        await app.logout();
    }
  }

  Future<void> _pickStore() async {
    if (!await app.checkOnline()) {
      if (mounted) await showOnlineRequired(context, 'Connectez-vous à Internet pour changer de magasin.');
      return;
    }
    if (!mounted) return;
    final id = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Magasin'),
        children: [
          for (final s in app.stores)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, (s['id'] as num).toInt()),
              child: Text('${s['name']}${s['id'] == app.store?['id'] ? '  ✓' : ''}'),
            ),
        ],
      ),
    );
    if (id == null || id == app.store?['id']) return;
    setState(() => _cart.clear());
    try {
      await app.changeStore(id);
      await _loadProducts();
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 860;
    final session = app.session;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((app.store?['name'] ?? 'Caisse').toString(), style: const TextStyle(fontSize: 17)),
          Text('${app.user?['name'] ?? ''} · ${session == null ? 'caisse fermée' : 'caisse ouverte'}', style: const TextStyle(fontSize: 12)),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Chip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(app.online ? Icons.wifi : Icons.wifi_off, size: 16, color: app.online ? Colors.green : Colors.red),
              label: Text(app.online ? 'En ligne' : 'Hors ligne'),
            ),
          ),
          IconButton(
            tooltip: 'Ventes hors ligne',
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PendingPage()));
              if (mounted) setState(() {});
            },
            icon: Badge(
              isLabelVisible: app.pending + app.errors > 0,
              backgroundColor: app.errors > 0 ? Colors.red : Colors.orange,
              label: Text('${app.pending + app.errors}'),
              child: const Icon(Icons.cloud_upload_outlined),
            ),
          ),
          if (session != null)
            IconButton(tooltip: 'Historique de la caisse', onPressed: () => _menu('history'), icon: const Icon(Icons.receipt_long_outlined)),
          IconButton(
            tooltip: 'Synchroniser',
            onPressed: () => showSyncDialog(context),
            icon: app.syncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
          ),
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => [
              if (session != null) const PopupMenuItem(value: 'history', child: ListTile(leading: Icon(Icons.receipt_long_outlined), title: Text('Historique de la caisse'))),
              if (session != null && app.abilities['return'] == true)
                const PopupMenuItem(value: 'return', child: ListTile(leading: Icon(Icons.assignment_return_outlined), title: Text('Retour d’articles'))),
              if (session != null && app.abilities['expense'] == true)
                const PopupMenuItem(value: 'movement', child: ListTile(leading: Icon(Icons.swap_vert), title: Text('Mouvement de caisse (dépense, entrée, sortie)'))),
              const PopupMenuItem(value: 'printer', child: ListTile(leading: Icon(Icons.print_outlined), title: Text('Imprimante'))),
              if (app.stores.length > 1) const PopupMenuItem(value: 'store', child: ListTile(leading: Icon(Icons.store_outlined), title: Text('Changer de magasin'))),
              if (session != null && app.abilities['open_close'] == true)
                const PopupMenuItem(value: 'close', child: ListTile(leading: Icon(Icons.lock_outline), title: Text('Clôturer la caisse'))),
              const PopupMenuItem(value: 'server', child: ListTile(leading: Icon(Icons.dns_outlined), title: Text('Serveur'))),
              const PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text('Se déconnecter'))),
            ],
          ),
        ],
      ),
      body: app.store == null
          ? _empty(Icons.store_mall_directory_outlined, 'Aucun magasin lié à votre compte.', 'Demandez à l’administrateur de vous rattacher à un magasin, puis synchronisez.',
              action: OutlinedButton.icon(onPressed: () => showSyncDialog(context), icon: const Icon(Icons.sync), label: const Text('Synchroniser')))
          : session == null
              ? _closed()
              : wide
                  ? Row(children: [
                      Expanded(child: _productsPanel(wide)),
                      const VerticalDivider(width: 1),
                      SizedBox(width: 400, child: _cartPanel()),
                    ])
                  : IndexedStack(index: _tab, children: [_productsPanel(wide), _cartPanel()]),
      bottomNavigationBar: !wide && session != null && app.store != null
          ? NavigationBar(
              selectedIndex: _tab,
              height: 64,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [
                const NavigationDestination(icon: Icon(Icons.grid_view), label: 'Produits'),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: _cart.isNotEmpty,
                    label: Text('${_cart.fold<int>(0, (s, l) => s + l.quantity)}'),
                    child: const Icon(Icons.shopping_cart_outlined),
                  ),
                  label: 'Panier · ${_totals.total.toStringAsFixed(2)}',
                ),
              ],
            )
          : null,
    );
  }

  Widget _empty(IconData icon, String title, String text, {Widget? action}) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 64, color: Colors.black38),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action],
          ]),
        ),
      );

  Widget _closed() {
    final canOpen = app.abilities['open_close'] == true;
    return _empty(
      Icons.lock_clock_outlined,
      'Caisse fermée',
      !app.online
          ? 'Connectez-vous à Internet pour ouvrir la caisse. Si elle a été ouverte sur un autre appareil, synchronisez.'
          : canOpen
              ? 'Ouvrez la caisse avec le fond de caisse pour commencer à vendre.'
              : 'Demandez à un responsable d’ouvrir la caisse, puis synchronisez.',
      action: Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.center, children: [
        if (canOpen) FilledButton.icon(onPressed: () => showOpenSession(context), icon: const Icon(Icons.lock_open), label: const Text('Ouvrir la caisse')),
        OutlinedButton.icon(onPressed: () => showSyncDialog(context), icon: const Icon(Icons.sync), label: const Text('Synchroniser')),
      ]),
    );
  }

  Widget _productsPanel(bool wide) {
    final cur = app.currency;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              focusNode: _searchFocus,
              autofocus: wide,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Scanner ou chercher (nom, SKU, code-barres)',
                prefixIcon: const Icon(Icons.qr_code_scanner),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          _loadProducts();
                        },
                      ),
              ),
              onChanged: _onSearchChanged,
              onSubmitted: _onSearchSubmitted,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(tooltip: 'Scanner avec la caméra', onPressed: _scanCamera, icon: const Icon(Icons.photo_camera_outlined)),
        ]),
      ),
      if (app.categories.isNotEmpty) _categoryBar(),
      Expanded(
        child: _products.isEmpty
            ? _empty(Icons.inventory_2_outlined, 'Aucun produit',
                _search.text.isEmpty && _category == null ? 'Synchronisez les produits pour remplir la caisse.' : 'Aucun résultat.',
                action: _search.text.isEmpty
                    ? OutlinedButton.icon(onPressed: () => showSyncDialog(context), icon: const Icon(Icons.sync), label: const Text('Synchroniser'))
                    : null)
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 240, mainAxisExtent: 104, crossAxisSpacing: 8, mainAxisSpacing: 8),
                itemCount: _products.length,
                itemBuilder: (context, i) => _tile(_products[i], cur),
              ),
      ),
    ]);
  }

  /// Filtre par catégorie (sur les produits de la tablette, donc aussi hors ligne).
  Widget _categoryBar() {
    Widget chip(int? id, String label, Color? color) {
      final selected = _category == id;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          selected: selected,
          label: Text(label),
          avatar: color == null ? null : CircleAvatar(backgroundColor: color, radius: 6),
          onSelected: (_) {
            setState(() => _category = id);
            _loadProducts();
          },
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        children: [
          chip(null, 'Toutes', null),
          for (final c in app.categories) chip((c['id'] as num).toInt(), c['name'].toString(), _parseColor((c['color'] ?? '').toString())),
          chip(0, 'Sans catégorie', null),
        ],
      ),
    );
  }

  Widget _tile(Product p, String cur) {
    final low = p.storeAvailable <= 0;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade300)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _add(p),
        onLongPress: () => showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(p.label),
            content: Text('SKU ${p.sku} · code ${p.barcode}\nStock magasin ${p.storeAvailable} · dépôt ${p.depotAvailable}\n'
                'Clé d’image : ${p.imageKey ?? 'aucune'}\n${ProductImageStore.instance.status(p.variantId) ?? 'pas encore chargée'}'),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer'))],
          ),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 5, color: _parseColor(p.color) ?? Colors.blueGrey.shade200),
          SizedBox(width: 88, child: ProductThumb(p, key: ValueKey('${p.variantId}_${p.imageKey}'), size: 88)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (p.variant.isNotEmpty) Text(p.variant, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                const Spacer(),
                Row(children: [
                  Expanded(child: Text(p.price == null ? 'Sans prix' : '${p.price!.toStringAsFixed(2)} $cur', style: const TextStyle(fontWeight: FontWeight.bold))),
                  Text('${p.storeAvailable}', style: TextStyle(fontSize: 12, color: low ? Colors.red : Colors.green.shade700, fontWeight: FontWeight.w600)),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _cartPanel() {
    final cur = app.currency;
    final t = _totals;
    final count = _cart.fold<int>(0, (s, l) => s + l.quantity);
    final canDiscount = app.abilities['discount'] == true;
    return Container(
      color: Colors.grey.shade50,
      child: Column(children: [
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(_contact?.name ?? 'Client de passage'),
          subtitle: _contact != null && _contact!.phone.isNotEmpty ? Text(_contact!.phone) : null,
          trailing: _contact != null ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _contact = null)) : const Icon(Icons.chevron_right),
          onTap: () async {
            final c = await pickContact(context);
            if (c != null) setState(() => _contact = c);
          },
        ),
        const Divider(height: 1),
        Expanded(
          child: _cart.isEmpty
              ? const Center(child: Text('Panier vide', style: TextStyle(color: Colors.black45)))
              : ListView.separated(
                  itemCount: _cart.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => _cartLine(_cart[i], cur),
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(children: [
            _row('Articles', '$count'),
            if (canDiscount || t.discount > 0)
              InkWell(
                onTap: canDiscount && _cart.isNotEmpty ? _editDiscount : null,
                child: _row(
                  _discountType == null
                      ? 'Remise (toucher pour ajouter)'
                      : 'Remise${_discountType == 'percent' ? ' ${_discountValue.toStringAsFixed(_discountValue % 1 == 0 ? 0 : 2)} %' : ''}',
                  t.discount > 0 ? '-${t.discount.toStringAsFixed(2)}' : '—',
                ),
              ),
            if (app.pricing['vat'] == true) _row(app.pricing['includes_tax'] != false ? 'dont TVA' : 'TVA', t.tax.toStringAsFixed(2)),
            const SizedBox(height: 4),
            _row('Total', '${t.total.toStringAsFixed(2)} $cur', big: true),
            const SizedBox(height: 10),
            Row(children: [
              OutlinedButton(
                onPressed: _cart.isEmpty
                    ? null
                    : () => setState(() {
                          _cart.clear();
                          _discountType = null;
                          _discountValue = 0;
                        }),
                child: const Icon(Icons.delete_sweep_outlined),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 56), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  onPressed: _cart.isEmpty || _paying || app.abilities['sell'] == false ? null : _checkout,
                  icon: _paying
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.point_of_sale),
                  label: Text('Encaisser ${t.total.toStringAsFixed(2)}'),
                ),
              ),
            ]),
            if (!app.online)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Hors ligne : les ventes sont gardées sur la tablette et envoyées au retour de la connexion. Crédit indisponible.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.deepOrange)),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _cartLine(CartLine l, String cur) => Dismissible(
        key: ValueKey(l.product.variantId),
        direction: DismissDirection.endToStart,
        background: Container(color: Colors.red.shade100, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16), child: const Icon(Icons.delete_outline)),
        onDismissed: (_) => setState(() => _cart.remove(l)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: 40, height: 40, child: ProductThumb(l.product, size: 40))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.product.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
                Text('${(l.product.price ?? 0).toStringAsFixed(2)} $cur', style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ]),
            ),
            IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove_circle_outline), onPressed: () => _qty(l, -1)),
            InkWell(
              onTap: () => _editQty(l),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text('${l.quantity}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            ),
            IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_circle_outline), onPressed: () => _qty(l, 1)),
            SizedBox(width: 78, child: Text(l.gross.toStringAsFixed(2), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        ),
      );

  Widget _row(String label, String value, {bool big = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: big ? 20 : 14, fontWeight: big ? FontWeight.bold : FontWeight.normal))),
          Text(value, style: TextStyle(fontSize: big ? 22 : 14, fontWeight: big ? FontWeight.bold : FontWeight.w500)),
        ]),
      );

  Color? _parseColor(String hex) {
    final h = hex.replaceFirst('#', '');
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }
}
