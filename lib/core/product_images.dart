import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'app_state.dart';
import 'models.dart';

/// Images des produits gardées sur l'appareil (visibles hors ligne). Le nom du fichier contient la clé d'image du
/// serveur : une image changée sur le site est donc retéléchargée à la synchronisation suivante.
class ProductImageStore {
  ProductImageStore._();

  static final instance = ProductImageStore._();

  Directory? _dir;
  final _pending = <String, Future<File?>>{};
  final _missing = <String>{};

  /// Augmente à chaque image enregistrée : les vignettes encore vides réessaient.
  final updates = ValueNotifier<int>(0);

  /// Dernier état connu de l'image de chaque produit (affiché par un appui long sur le produit).
  final status = <int, String>{};

  void _note(Product item, String message) {
    status[item.variantId] = message;
    debugPrint('Image produit ${item.variantId} : $message');
  }

  Future<Directory> _directory() async {
    if (_dir != null) return _dir!;
    final d = Directory(p.join(await getDatabasesPath(), 'product_images'));
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  String _name(Product item) => '${item.variantId}_${item.imageKey}';

  static String _head(List<int> bytes) => bytes.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

  Future<File?> get(Product item) {
    if (item.imageKey == null) return Future.value(null);
    final key = _name(item);
    return _pending[key] ??= _load(item, key).whenComplete(() => _pending.remove(key));
  }

  Future<File?> _load(Product item, String key) async {
    final file = File(p.join((await _directory()).path, key));
    if (await file.exists()) {
      _note(item, 'fichier sur la tablette (${await file.length()} octets, début ${_head(await file.openRead(0, 8).first)})');
      return file;
    }
    final app = AppState.instance;
    final api = app.api;
    if (!app.online || api == null || _missing.contains(key)) {
      _note(item, 'pas de téléchargement (en ligne : ${app.online}, absente du serveur : ${_missing.contains(key)})');
      return null;
    }
    final url = '${api.baseUrl}/api/pos/v1/products/${item.variantId}/image';
    try {
      final response = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer ${api.token}'}).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        final body = String.fromCharCodes(response.bodyBytes.take(120)).replaceAll(RegExp(r'\s+'), ' ');
        _note(item, 'réponse ${response.statusCode} (${response.headers['content-type']}) : $body · $url');
        if (response.statusCode == 404) _missing.add(key);
        return null;
      }
      final part = File('${file.path}.part');
      await part.writeAsBytes(response.bodyBytes, flush: true);
      await part.rename(file.path);
      _note(item, 'téléchargée (${response.bodyBytes.length} octets, ${response.headers['content-type']}, début ${_head(response.bodyBytes)})');
      updates.value++;
      return file;
    } catch (e) {
      _note(item, 'erreur $e · $url');
      return null;
    }
  }

  /// Après la synchronisation du catalogue : supprime les images inutiles et télécharge les manquantes, une à la fois.
  Future<void> prefetch(List<Product> items) async {
    final d = await _directory();
    final keep = {for (final item in items) if (item.imageKey != null) _name(item)};
    await for (final entry in d.list()) {
      final name = p.basename(entry.path);
      if (entry is File && !name.endsWith('.part') && !keep.contains(name)) {
        try {
          await entry.delete();
        } catch (_) {}
      }
    }
    for (final item in items) {
      if (!AppState.instance.online) break;
      if (item.imageKey != null) await get(item);
    }
  }

  Future<void> clear() async {
    final d = await _directory();
    if (await d.exists()) await d.delete(recursive: true);
    _dir = null;
    _missing.clear();
  }
}

/// Vignette du produit (image gardée sur l'appareil, sinon icône).
class ProductThumb extends StatefulWidget {
  const ProductThumb(this.product, {super.key, this.size = 72});

  final Product product;
  final double size;

  @override
  State<ProductThumb> createState() => _ProductThumbState();
}

class _ProductThumbState extends State<ProductThumb> {
  File? _file;
  bool _wasOnline = false;

  @override
  void initState() {
    super.initState();
    _wasOnline = AppState.instance.online;
    ProductImageStore.instance.updates.addListener(_retry);
    AppState.instance.addListener(_onApp);
    _load();
  }

  @override
  void dispose() {
    ProductImageStore.instance.updates.removeListener(_retry);
    AppState.instance.removeListener(_onApp);
    super.dispose();
  }

  @override
  void didUpdateWidget(ProductThumb old) {
    super.didUpdateWidget(old);
    if (old.product.variantId != widget.product.variantId || old.product.imageKey != widget.product.imageKey) {
      _file = null;
      _load();
    }
  }

  void _retry() {
    if (_file == null) _load();
  }

  void _onApp() {
    final online = AppState.instance.online;
    if (online && !_wasOnline) _retry();
    _wasOnline = online;
  }

  Future<void> _load() async {
    if (widget.product.imageKey == null) {
      ProductImageStore.instance._note(widget.product, 'le serveur n’envoie pas d’image pour ce produit');
      return;
    }
    final file = await ProductImageStore.instance.get(widget.product);
    if (mounted && file != null && _file?.path != file.path) setState(() => _file = file);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: Colors.grey.shade100,
      alignment: Alignment.center,
      child: Icon(Icons.inventory_2_outlined, color: Colors.grey.shade400, size: widget.size * .4),
    );
    if (_file == null) return placeholder;
    return Image.file(
      _file!,
      fit: BoxFit.cover,
      cacheWidth: (widget.size * 3).round(),
      gaplessPlayback: true,
      errorBuilder: (_, error, __) {
        ProductImageStore.instance._note(widget.product, 'image illisible ($error)');
        return placeholder;
      },
    );
  }
}
