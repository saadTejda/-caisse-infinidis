import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../theme/pos_theme.dart';

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _products = [];
  String? _error;
  bool _busy = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final categories = await dio.get('/api/v1/categories');
      final products = await dio.get('/api/v1/products');
      setState(() {
        _categories = apiList(categories.data);
        _products = apiList(products.data);
      });
    } on DioException catch (error) {
      setState(() => _error = apiMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveCategory([Map<String, dynamic>? category]) async {
    final name = TextEditingController(text: '${category?['name'] ?? ''}');
    var active = category?['is_active'] != false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Catégorie'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom')),
            StatefulBuilder(
              builder: (context, setLocal) => SwitchListTile(
                value: active,
                title: const Text('Active'),
                onChanged: (value) => setLocal(() => active = value),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final body = {'name': name.text.trim(), 'is_active': active};
    try {
      final dio = ref.read(dioProvider);
      if (category == null) {
        await dio.post('/api/v1/categories', data: body);
      } else {
        await dio.patch('/api/v1/categories/${category['id']}', data: body);
      }
      await _load();
    } on DioException catch (error) {
      _toast(apiMessage(error));
    }
  }

  Future<void> _deleteCategory(Map<String, dynamic> category) async {
    try {
      await ref.read(dioProvider).delete('/api/v1/categories/${category['id']}');
      await _load();
    } on DioException catch (error) {
      _toast(apiMessage(error));
    }
  }

  Future<void> _saveProduct([Map<String, dynamic>? product]) async {
    Map<String, dynamic>? current = product;
    if (product != null) {
      try {
        final response = await ref.read(dioProvider).get('/api/v1/products/${product['id']}');
        current = apiMap(response.data);
      } on DioException catch (error) {
        _toast(apiMessage(error));
        return;
      }
    }
    if (!mounted) return;
    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _ProductEditor(product: current, categories: _categories, products: _products),
    );
    if (draft == null) return;
    try {
      final dio = ref.read(dioProvider);
      if (current == null) {
        await dio.post('/api/v1/products', data: draft);
      } else {
        await dio.patch('/api/v1/products/${current['id']}', data: draft);
      }
      await _load();
    } on DioException catch (error) {
      _toast(apiMessage(error));
    }
  }

  Future<void> _stock(Map<String, dynamic> product) async {
    var type = 'purchase';
    final quantity = TextEditingController(text: '1');
    final counted = TextEditingController(text: '${product['stock_quantity'] ?? '0'}');
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Stock · ${product['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                value: type,
                items: const [
                  DropdownMenuItem(value: 'purchase', child: Text('Réception')),
                  DropdownMenuItem(value: 'inventory', child: Text('Inventaire')),
                  DropdownMenuItem(value: 'waste', child: Text('Perte')),
                  DropdownMenuItem(value: 'adjustment', child: Text('Ajustement')),
                ],
                onChanged: (value) => setLocal(() => type = value ?? type),
              ),
              if (type == 'inventory')
                TextField(controller: counted, decoration: const InputDecoration(labelText: 'Quantité comptée'))
              else
                TextField(controller: quantity, decoration: const InputDecoration(labelText: 'Quantité')),
              TextField(controller: reason, decoration: const InputDecoration(labelText: 'Motif')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final body = {
      'type': type,
      'reason': reason.text.trim().isEmpty ? null : reason.text.trim(),
      if (type == 'inventory') 'counted_quantity': double.tryParse(counted.text.replaceAll(',', '.')) ?? 0,
      if (type != 'inventory') 'quantity': double.tryParse(quantity.text.replaceAll(',', '.')) ?? 0,
    };
    try {
      await ref.read(dioProvider).post('/api/v1/products/${product['id']}/stock', data: body);
      await _load();
    } on DioException catch (error) {
      _toast(apiMessage(error));
    }
  }

  Future<void> _movements(Map<String, dynamic> product) async {
    try {
      final response = await ref.read(dioProvider).get('/api/v1/products/${product['id']}/movements');
      if (!mounted) return;
      final rows = apiList(response.data);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Mouvements · ${product['name']}'),
          content: SizedBox(
            width: 420,
            child: rows.isEmpty
                ? const Text('Aucun mouvement')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final row in rows)
                        ListTile(
                          dense: true,
                          title: Text('${row['type'] ?? ''} · ${row['quantity'] ?? row['counted_quantity'] ?? ''}'),
                          subtitle: Text('${row['reason'] ?? ''} ${row['created_at'] ?? ''}'),
                        ),
                    ],
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
        ),
      );
    } on DioException catch (error) {
      _toast(apiMessage(error));
    }
  }

  Future<void> _image(Map<String, dynamic> product) async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null) return;
    try {
      final form = FormData.fromMap({
        'image': await MultipartFile.fromFile(file.path, filename: file.name),
      });
      await ref.read(dioProvider).post('/api/v1/products/${product['id']}/image', data: form);
      await _load();
    } on DioException catch (error) {
      _toast(apiMessage(error));
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final products = _products.where((product) {
      final query = _query.toLowerCase();
      if (query.isEmpty) return true;
      return ['name', 'sku', 'barcode', 'code'].any((key) => '${product[key] ?? ''}'.toLowerCase().contains(query));
    }).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null) Text(_error!, style: const TextStyle(color: PosColors.danger)),
        if (_busy) const LinearProgressIndicator(),
        const Text('Catégories', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in _categories)
              InputChip(
                label: Text('${category['name']}'),
                avatar: Icon(Icons.circle, size: 10, color: category['is_active'] == false ? PosColors.muted : PosColors.success),
                onPressed: () => _saveCategory(category),
                onDeleted: () => _deleteCategory(category),
              ),
            ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Catégorie'), onPressed: () => _saveCategory()),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Produits', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const Spacer(),
            FilledButton.icon(onPressed: () => _saveProduct(), icon: const Icon(Icons.add), label: const Text('Produit')),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(
            hintText: 'Nom, SKU, code-barres',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => _query = value.trim()),
        ),
        const SizedBox(height: 12),
        if (products.isEmpty)
          const Text('Aucun produit', style: TextStyle(color: PosColors.muted)),
        for (final product in products) _productRow(product),
      ],
    );
  }

  Widget _productRow(Map<String, dynamic> product) {
    final price = product['sale_price'];
    final stock = product['stock_quantity'] ?? product['stock'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: PosColors.line),
      ),
      child: ListTile(
        onTap: () => _saveProduct(product),
        title: Text('${product['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        subtitle: Text('${product['type']} · ${product['unit']}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${price ?? '—'} DH', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                if (stock != null) Text('Stock $stock', style: const TextStyle(color: PosColors.muted, fontSize: 12)),
              ],
            ),
            IconButton(tooltip: 'Stock', icon: const Icon(Icons.inventory_2_outlined), onPressed: () => _stock(product)),
            IconButton(tooltip: 'Mouvements', icon: const Icon(Icons.history), onPressed: () => _movements(product)),
            IconButton(tooltip: 'Image', icon: const Icon(Icons.image_outlined), onPressed: () => _image(product)),
            IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                try {
                  await ref.read(dioProvider).delete('/api/v1/products/${product['id']}');
                  await _load();
                } on DioException catch (error) {
                  _toast(apiMessage(error));
                }
              },
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _ProductEditor extends StatefulWidget {
  const _ProductEditor({required this.product, required this.categories, required this.products});

  final Map<String, dynamic>? product;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> products;

  @override
  State<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<_ProductEditor> {
  late final TextEditingController _name = TextEditingController(text: '${widget.product?['name'] ?? ''}');
  late final TextEditingController _sale = TextEditingController(text: '${widget.product?['sale_price'] ?? ''}');
  late final TextEditingController _cost = TextEditingController(text: '${widget.product?['cost_price'] ?? ''}');
  late final TextEditingController _position = TextEditingController(text: '${widget.product?['pos_position'] ?? ''}');
  late final TextEditingController _minStock = TextEditingController(text: '${widget.product?['min_stock'] ?? ''}');
  late final TextEditingController _initial = TextEditingController();
  late String _type = '${widget.product?['type'] ?? 'sellable'}';
  late String _unit = '${widget.product?['unit'] ?? 'piece'}';
  late int? _categoryId = int.tryParse('${widget.product?['category_id']}');
  late bool _track = widget.product?['track_stock'] == true;
  late bool _active = widget.product?['is_active'] != false;
  late bool _recipe = widget.product?['recipe_enabled'] == true;
  late final List<Map<String, dynamic>> _recipeItems = _copyList(widget.product?['recipe_items']);
  late final List<Map<String, dynamic>> _groups = _copyList(widget.product?['modifier_groups']);

  List<Map<String, dynamic>> _copyList(dynamic raw) {
    if (raw is! List) return [];
    return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<void> _addIngredient() async {
    final others = widget.products.where((item) => item['id'] != widget.product?['id']).toList();
    if (others.isEmpty || !mounted) return;
    var selected = others.first;
    final quantity = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Ingrédient'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<Map<String, dynamic>>(
                value: selected,
                isExpanded: true,
                items: [
                  for (final item in others)
                    DropdownMenuItem(value: item, child: Text('${item['name']}')),
                ],
                onChanged: (value) {
                  if (value != null) setLocal(() => selected = value);
                },
              ),
              TextField(controller: quantity, decoration: const InputDecoration(labelText: 'Quantité')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ajouter')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      _recipeItems.add({
        'component_product_id': selected['id'],
        'quantity': double.tryParse(quantity.text.replaceAll(',', '.')) ?? 1,
        'unit': selected['unit'] ?? 'piece',
      });
    });
  }

  Future<void> _editGroup(int? index) async {
    final source = index == null
        ? <String, dynamic>{
            'name': 'Suppléments',
            'required': false,
            'min_select': 0,
            'max_select': 1,
            'modifiers': <Map<String, dynamic>>[],
          }
        : Map<String, dynamic>.from(_groups[index]);
    final name = TextEditingController(text: '${source['name'] ?? ''}');
    final minimum = TextEditingController(text: '${source['min_select'] ?? 0}');
    final maximum = TextEditingController(text: '${source['max_select'] ?? 1}');
    var requiredGroup = source['required'] == true;
    final modifiers = <Map<String, dynamic>>[
      for (final item in (source['modifiers'] as List? ?? const []))
        if (item is Map) Map<String, dynamic>.from(item),
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Groupe de suppléments'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Nom'),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  SwitchListTile(
                    value: requiredGroup,
                    title: const Text('Obligatoire'),
                    onChanged: (value) => setLocal(() => requiredGroup = value),
                  ),
                  TextField(controller: minimum, decoration: const InputDecoration(labelText: 'Minimum')),
                  TextField(controller: maximum, decoration: const InputDecoration(labelText: 'Maximum')),
                  for (final modifier in modifiers)
                    ListTile(
                      title: Text('${modifier['name']} · ${modifier['price_delta'] ?? 0}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setLocal(() => modifiers.remove(modifier)),
                      ),
                    ),
                  TextButton(
                    onPressed: () async {
                      final option = TextEditingController();
                      final price = TextEditingController(text: '0');
                      final added = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Option'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(controller: option, decoration: const InputDecoration(labelText: 'Nom')),
                              TextField(controller: price, decoration: const InputDecoration(labelText: 'Écart de prix')),
                            ],
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
                            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ajouter')),
                          ],
                        ),
                      );
                      if (added == true && option.text.trim().isNotEmpty) {
                        setLocal(() {
                          modifiers.add({
                            'name': option.text.trim(),
                            'price_delta': double.tryParse(price.text.replaceAll(',', '.')) ?? 0,
                          });
                        });
                      }
                    },
                    child: const Text('Ajouter une option'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            FilledButton(
              onPressed: name.text.trim().isEmpty ? null : () => Navigator.pop(context, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final group = {
      'name': name.text.trim(),
      'required': requiredGroup,
      'min_select': int.tryParse(minimum.text) ?? 0,
      'max_select': int.tryParse(maximum.text) ?? 1,
      'modifiers': modifiers,
    };
    setState(() {
      if (index == null) {
        _groups.add(group);
      } else {
        _groups[index] = group;
      }
    });
  }

  void _save() {
    if (_name.text.trim().isEmpty) return;
    final sale = _sale.text.trim().isEmpty ? null : double.tryParse(_sale.text.replaceAll(',', '.'));
    final cost = _cost.text.trim().isEmpty ? null : double.tryParse(_cost.text.replaceAll(',', '.'));
    Navigator.pop(context, {
      'name': _name.text.trim(),
      'category_id': _categoryId,
      'type': _type,
      'unit': _unit,
      'sale_price': sale,
      'cost_price': cost,
      'track_stock': _track,
      'min_stock': _minStock.text.trim().isEmpty ? null : double.tryParse(_minStock.text.replaceAll(',', '.')),
      if (widget.product == null && _initial.text.trim().isNotEmpty)
        'initial_stock': double.tryParse(_initial.text.replaceAll(',', '.')),
      'recipe_enabled': _recipe,
      'is_active': _active,
      'pos_position': _position.text.trim().isEmpty ? null : int.tryParse(_position.text),
      'recipe_items': [
        for (final item in _recipeItems)
          {
            'component_product_id': item['component_product_id'],
            'quantity': item['quantity'],
            'unit': item['unit'],
          },
      ],
      'modifier_groups': [
        for (final group in _groups)
          {
            'name': group['name'],
            'required': group['required'] == true,
            'min_select': group['min_select'] ?? 0,
            'max_select': group['max_select'] ?? 1,
            'modifiers': [
              for (final modifier in (group['modifiers'] as List? ?? const []))
                if (modifier is Map)
                  {
                    'name': modifier['name'],
                    'price_delta': modifier['price_delta'] ?? 0,
                    'linked_product_id': modifier['linked_product_id'],
                    'quantity': modifier['quantity'],
                    'unit': modifier['unit'],
                  },
            ],
          },
      ],
    });
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration field(String label) => InputDecoration(labelText: label, floatingLabelBehavior: FloatingLabelBehavior.always);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.product == null ? 'Nouveau produit' : '${widget.product!['name']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text('Identité', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  TextField(controller: _name, decoration: field('Nom')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: field('Type'),
                    items: const [
                      DropdownMenuItem(value: 'sellable', child: Text('Vendable')),
                      DropdownMenuItem(value: 'ingredient', child: Text('Ingrédient')),
                      DropdownMenuItem(value: 'both', child: Text('Les deux')),
                    ],
                    onChanged: (value) => setState(() => _type = value ?? _type),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _unit,
                    decoration: field('Unité'),
                    items: const ['piece', 'g', 'kg', 'ml', 'l'].map((unit) => DropdownMenuItem(value: unit, child: Text(unit))).toList(),
                    onChanged: (value) => setState(() => _unit = value ?? _unit),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue: _categoryId,
                    decoration: field('Catégorie'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Sans catégorie')),
                      for (final category in widget.categories)
                        DropdownMenuItem(value: int.tryParse('${category['id']}'), child: Text('${category['name']}')),
                    ],
                    onChanged: (value) => setState(() => _categoryId = value),
                  ),
                  const SizedBox(height: 18),
                  const Text('Prix', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: _sale, keyboardType: TextInputType.number, decoration: field('Prix de vente'))),
                      const SizedBox(width: 12),
                      Expanded(child: TextField(controller: _cost, keyboardType: TextInputType.number, decoration: field('Coût'))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _position, keyboardType: TextInputType.number, decoration: field('Position caisse')),
                  const SizedBox(height: 18),
                  const Text('Stock', style: TextStyle(fontWeight: FontWeight.w800)),
                  SwitchListTile(contentPadding: EdgeInsets.zero, value: _track, title: const Text('Suivre le stock'), onChanged: (value) => setState(() => _track = value)),
                  TextField(controller: _minStock, keyboardType: TextInputType.number, decoration: field('Stock minimum')),
                  if (widget.product == null) ...[
                    const SizedBox(height: 12),
                    TextField(controller: _initial, keyboardType: TextInputType.number, decoration: field('Stock initial')),
                  ],
                  SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, title: const Text('Actif'), onChanged: (value) => setState(() => _active = value)),
                  SwitchListTile(contentPadding: EdgeInsets.zero, value: _recipe, title: const Text('Recette'), onChanged: (value) => setState(() => _recipe = value)),
              if (_recipe)
                TextButton(onPressed: _addIngredient, child: const Text('Ajouter un ingrédient')),
              for (final item in _recipeItems)
                ListTile(
                  title: Text('${item['component_product_id']} · ${item['quantity']} ${item['unit']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _recipeItems.remove(item)),
                  ),
                ),
              TextButton(onPressed: () => _editGroup(null), child: const Text('Ajouter un groupe de suppléments')),
              for (var index = 0; index < _groups.length; index++)
                ListTile(
                  title: Text('${_groups[index]['name']}'),
                  subtitle: Text('${(_groups[index]['modifiers'] as List?)?.length ?? 0} options'),
                  onTap: () => _editGroup(index),
                  trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _groups.removeAt(index))),
                ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _save, child: const Text('Enregistrer')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
