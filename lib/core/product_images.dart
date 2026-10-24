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

  Future<Directory> _directory() async {
    if (_dir != null) return _dir!;
    final d = Directory(p.join(await getDatabasesPath(), 'product_images'));
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  String _name(Product item) => '${item.variantId}_${item.imageKey}';

  Future<File?> get(Product item) {
    if (item.imageKey == null) return Future.value(null);
    final key = _name(item);
    return _pending[key] ??= _load(item, key).whenComplete(() => _pending.remove(key));
  }

  Future<File?> _load(Product item, String key) async {
    final file = File(p.join((await _directory()).path, key));
    if (await file.exists()) return file;
    final app = AppState.instance;
    final api = app.api;
    if (!app.online || api == null || _missing.contains(key)) return null;
    try {
      final response = await http.get(
        Uri.parse('${api.baseUrl}/api/pos/v1/products/${item.variantId}/image'),
        headers: {'Authorization': 'Bearer ${api.token}'},
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        if (response.statusCode == 404) _missing.add(key);
        return null;
      }
      final part = File('${file.path}.part');
      await part.writeAsBytes(response.bodyBytes, flush: true);
      await part.rename(file.path);
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Après la synchronisation du catalogue : supprime les images inutiles et télécharge les manquantes, une à la fois.
  Future<void> prefetch(List<Product> items) async {
    final d = await _directory();
    final keep = {for (final item in items) if (item.imageKey != null) _name(item)};
    await for (final entry in d.list()) {
      if (entry is File && !keep.contains(p.basename(entry.path))) {
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ProductThumb old) {
    super.didUpdateWidget(old);
    if (old.product.variantId != widget.product.variantId || old.product.imageKey != widget.product.imageKey) {
      _file = null;
      _load();
    }
  }

  Future<void> _load() async {
    final file = await ProductImageStore.instance.get(widget.product);
    if (mounted && file != null) setState(() => _file = file);
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
      errorBuilder: (_, __, ___) => placeholder,
    );
  }
}
