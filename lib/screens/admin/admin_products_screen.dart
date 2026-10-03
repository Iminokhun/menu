import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../image_upload.dart';

class AdminProductsScreen extends StatefulWidget {
  const AdminProductsScreen({super.key});

  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _categories = [];
  String? _filterCategoryId;
  bool _loading = true;

  static const _accent = Color(0xFFD4AF37);
  static const _bg = Color(0xFF0A0A0A);
  static const _surface = Color(0xFF1A1A1A);

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _client.from('categories').select().order('sort_order'),
        _client.from('products').select().order('sort_order'),
      ]);
      setState(() {
        _categories = List<Map<String, dynamic>>.from(results[0]);
        _products = List<Map<String, dynamic>>.from(results[1]);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      _toast('Ошибка загрузки: $e', isError: true);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filterCategoryId == null) return _products;
    return _products.where((p) => p['category_id'] == _filterCategoryId).toList();
  }

  String _catName(String? id) {
    if (id == null) return '—';
    return _categories.firstWhere((c) => c['id'] == id, orElse: () => {})['name'] ?? '—';
  }

  Future<String?> _uploadImage() async {
    try {
      return await pickAndUploadImage('prod_');
    } catch (e) {
      _toast('Ошибка загрузки фото: $e', isError: true);
      return null;
    }
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
      duration: const Duration(seconds: 2),
    ));
  }

  void _showDialog({Map<String, dynamic>? item}) {
    final nameRu = TextEditingController(text: item?['name'] ?? '');
    final nameEn = TextEditingController(text: item?['name_en'] ?? '');
    final nameTr = TextEditingController(text: item?['name_tr'] ?? '');
    final descRu = TextEditingController(text: item?['description'] ?? '');
    final descEn = TextEditingController(text: item?['desc_en'] ?? '');
    final descTr = TextEditingController(text: item?['desc_tr'] ?? '');
    final price = TextEditingController(text: (item?['price'] ?? '').toString());
    final sortOrder = TextEditingController(text: (item?['sort_order'] ?? 0).toString());
    String? imageUrl = item?['image_url'];
    String? selectedCatId = item?['category_id'] ?? (_categories.isNotEmpty ? _categories.first['id'] : null);
    bool isVisible = item?['is_visible'] ?? true;
    bool uploading = false;

    // Инициализация порций из jsonb
    final List<Map<String, dynamic>> portions = [];
    final rawPortions = item?['portions'];
    if (rawPortions != null && rawPortions is List) {
      for (final p in rawPortions) {
        portions.add({'name': p['name'] ?? '', 'price': (p['price'] ?? 0).toDouble()});
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: _surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            item == null ? 'Новый товар' : 'Редактировать товар',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Категория
                  const Text('Категория *', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: selectedCatId,
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _accent)),
                    ),
                    items: _categories.map((c) => DropdownMenuItem(
                      value: c['id'] as String,
                      child: Text(c['name'] ?? ''),
                    )).toList(),
                    onChanged: (v) => setS(() => selectedCatId = v),
                  ),
                  const SizedBox(height: 16),

                  // Названия
                  _sectionLabel('НАЗВАНИЕ'),
                  const SizedBox(height: 8),
                  _field(nameRu, 'Название (RU) *'),
                  const SizedBox(height: 8),
                  _field(nameEn, 'Название (EN)'),
                  const SizedBox(height: 8),
                  _field(nameTr, 'Название (TR)'),
                  const SizedBox(height: 16),

                  // Описания
                  _sectionLabel('ОПИСАНИЕ'),
                  const SizedBox(height: 8),
                  _field(descRu, 'Описание (RU)', maxLines: 2),
                  const SizedBox(height: 8),
                  _field(descEn, 'Описание (EN)', maxLines: 2),
                  const SizedBox(height: 8),
                  _field(descTr, 'Описание (TR)', maxLines: 2),
                  const SizedBox(height: 16),

                  // Цена и порядок
                  _sectionLabel('ЦЕНА И СОРТИРОВКА'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _field(price, 'Цена (сом)', isNumber: true)),
                      const SizedBox(width: 12),
                      Expanded(child: _field(sortOrder, 'Порядок', isNumber: true)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Порции
                  _sectionLabel('ПОРЦИИ'),
                  const SizedBox(height: 4),
                  const Text(
                    'Если есть порции — цена выше игнорируется',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  if (portions.isNotEmpty) ...[
                    ...portions.asMap().entries.map((entry) {
                      final i = entry.key;
                      final p = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${p['name']}  —  ${p['price']} сом',
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _showPortionDialog(
                                ctx: ctx,
                                setS: setS,
                                portions: portions,
                                index: i,
                              ),
                              child: const Icon(Icons.edit_outlined, color: _accent, size: 18),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => setS(() => portions.removeAt(i)),
                              child: const Icon(Icons.close, color: Colors.redAccent, size: 18),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 4),
                  ],
                  TextButton.icon(
                    onPressed: () => _showPortionDialog(ctx: ctx, setS: setS, portions: portions),
                    icon: const Icon(Icons.add, color: _accent, size: 18),
                    label: const Text('Добавить порцию', style: TextStyle(color: _accent)),
                  ),
                  const SizedBox(height: 16),

                  // Видимость
                  _sectionLabel('ВИДИМОСТЬ'),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => setS(() => isVisible = !isVisible),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            color: isVisible ? _accent : Colors.white38,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            isVisible ? 'Товар виден в меню' : 'Товар скрыт из меню',
                            style: TextStyle(
                              color: isVisible ? Colors.white : Colors.white38,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          Switch(
                            value: isVisible,
                            onChanged: (v) => setS(() => isVisible = v),
                            activeColor: _accent,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Фото
                  _sectionLabel('ФОТО'),
                  const SizedBox(height: 8),
                  if (imageUrl != null && imageUrl!.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(imageUrl!, height: 90, width: double.infinity, fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: uploading ? null : () async {
                        setS(() => uploading = true);
                        final url = await _uploadImage();
                        if (url != null) setS(() => imageUrl = url);
                        setS(() => uploading = false);
                      },
                      icon: uploading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _accent))
                          : const Icon(Icons.cloud_upload_outlined, color: _accent),
                      label: Text(
                        uploading ? 'Загрузка...' : (imageUrl != null && imageUrl!.isNotEmpty ? 'Заменить фото' : 'Загрузить фото'),
                        style: const TextStyle(color: _accent),
                      ),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: _accent)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.black),
              onPressed: () async {
                if (nameRu.text.trim().isEmpty || selectedCatId == null) {
                  _toast('Заполните обязательные поля', isError: true);
                  return;
                }
                final data = {
                  'category_id': selectedCatId,
                  'name': nameRu.text.trim(),
                  'name_en': nameEn.text.trim(),
                  'name_tr': nameTr.text.trim(),
                  'description': descRu.text.trim(),
                  'desc_en': descEn.text.trim(),
                  'desc_tr': descTr.text.trim(),
                  'price': double.tryParse(price.text) ?? 0,
                  'sort_order': int.tryParse(sortOrder.text) ?? 0,
                  'is_visible': isVisible,
                  'portions': portions,
                  if (imageUrl != null && imageUrl!.isNotEmpty) 'image_url': imageUrl,
                };
                try {
                  if (item == null) {
                    await _client.from('products').insert(data);
                  } else {
                    await _client.from('products').update(data).eq('id', item['id']);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadAll();
                  _toast(item == null ? 'Товар добавлен!' : 'Сохранено!');
                } catch (e) {
                  _toast('Ошибка: $e', isError: true);
                }
              },
              child: Text(item == null ? 'Добавить' : 'Сохранить', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showPortionDialog({
    required BuildContext ctx,
    required StateSetter setS,
    required List<Map<String, dynamic>> portions,
    int? index,
  }) {
    final nameCtrl = TextEditingController(text: index != null ? portions[index]['name'] : '');
    final priceCtrl = TextEditingController(text: index != null ? portions[index]['price'].toString() : '');

    showDialog(
      context: ctx,
      builder: (pCtx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          index == null ? 'Новая порция' : 'Редактировать порцию',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(nameCtrl, 'Название порции (напр. 150г)'),
            const SizedBox(height: 12),
            _field(priceCtrl, 'Цена (сом)', isNumber: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(pCtx),
            child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.black),
            onPressed: () {
              final name = nameCtrl.text.trim();
              final price = double.tryParse(priceCtrl.text) ?? 0;
              if (name.isEmpty) return;
              setS(() {
                if (index == null) {
                  portions.add({'name': name, 'price': price});
                } else {
                  portions[index] = {'name': name, 'price': price};
                }
              });
              Navigator.pop(pCtx);
            },
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Удалить товар?', style: TextStyle(color: Colors.white)),
        content: Text('«${item['name']}» будет удалён.', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _client.from('products').delete().eq('id', item['id']);
      _loadAll();
      _toast('Товар удалён');
    }
  }

  Widget _field(TextEditingController c, String label, {bool isNumber = false, int maxLines = 1}) {
    return TextField(
      controller: c,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _accent)),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.manrope(
        color: Colors.white38,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        automaticallyImplyLeading: false,
        title: Text('Товары', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          if (_categories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: DropdownButton<String?>(
                value: _filterCategoryId,
                dropdownColor: const Color(0xFF2A2A2A),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                underline: const SizedBox(),
                hint: const Text('Все категории', style: TextStyle(color: Colors.white54, fontSize: 13)),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Все категории', style: TextStyle(color: Colors.white54))),
                  ..._categories.map((c) => DropdownMenuItem(
                    value: c['id'] as String,
                    child: Text(c['name'] ?? ''),
                  )),
                ],
                onChanged: (v) => setState(() => _filterCategoryId = v),
              ),
            ),
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white54), onPressed: _loadAll),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_products',
        backgroundColor: _accent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Добавить', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: _categories.isEmpty ? null : () => _showDialog(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.fastfood_outlined, color: Colors.white24, size: 64),
                      const SizedBox(height: 16),
                      Text('Нет товаров', style: GoogleFonts.manrope(color: Colors.white38, fontSize: 18)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
                  itemBuilder: (_, i) {
                    final p = _filtered[i];
                    final hasImage = (p['image_url'] as String?)?.isNotEmpty == true;
                    final isHidden = p['is_visible'] == false;
                    final portionsCount = (p['portions'] as List?)?.length ?? 0;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      leading: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: hasImage
                                ? Image.network(p['image_url'], width: 56, height: 56, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _placeholder())
                                : _placeholder(),
                          ),
                          if (isHidden)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(Icons.visibility_off, color: Colors.white38, size: 12),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        p['name'] ?? '',
                        style: TextStyle(
                          color: isHidden ? Colors.white38 : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        [
                          _catName(p['category_id']),
                          if (portionsCount > 0) '$portionsCount пор.' else '${p['price']} сом',
                          if (isHidden) 'скрыт',
                        ].join('  ·  '),
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.edit_outlined, color: _accent), onPressed: () => _showDialog(item: p)),
                          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => _delete(p)),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Widget _placeholder() => Container(
    width: 56, height: 56,
    color: Colors.white10,
    child: const Icon(Icons.fastfood, color: Colors.white24, size: 28),
  );
}
