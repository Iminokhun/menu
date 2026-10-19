import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../api/api_client.dart';
import '../../config/current_branch.dart';
import '../../image_upload.dart';
import '../../models/json_read.dart';
import 'category_tree.dart';
import 'translations.dart';

class AdminCategoriesScreen extends StatefulWidget {
  const AdminCategoriesScreen({super.key});

  @override
  State<AdminCategoriesScreen> createState() => _AdminCategoriesScreenState();
}

class _AdminCategoriesScreenState extends State<AdminCategoriesScreen> {
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;

  static const _accent = Color(0xFFD4AF37);
  static const _bg = Color(0xFF0A0A0A);
  static const _surface = Color(0xFF1A1A1A);

  @override
  void initState() {
    super.initState();
    // Три экрана админки живут в IndexedStack одновременно, поэтому
    // переключение филиала должно перезагружать каждый из них.
    currentBranch.addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    currentBranch.removeListener(_reload);
    super.dispose();
  }

  void _reload() => _load();

  Future<void> _load() async {
    final branch = currentBranch.value;
    if (branch == null) {
      setState(() {
        _categories = [];
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);
    try {
      final data = await api.list('/api/admin/categories', {'branch_id': branch.id});
      if (!mounted) return;
      setState(() {
        _categories = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('Ошибка загрузки: $e', isError: true);
    }
  }

  Future<String?> _uploadImage() async {
    try {
      return await pickAndUploadImage('cat_');
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

  /// [parentId] — родитель новой категории (кнопка «+» у основной).
  void _showDialog({Map<String, dynamic>? item, String? parentId}) {
    String? parent = item == null ? parentId : item['parent_id'] as String?;
    // Подкатегории — один уровень: родителем может быть только основная
    // категория, а категория со своими подкатегориями остаётся основной
    final hasChildren =
        item != null && _categories.any((c) => c['parent_id'] == item['id']);
    final parents = categoryTree(_categories)
        .where((c) => !isSubcategory(c, _categories) && c['id'] != item?['id'])
        .toList();
    if (!parents.any((c) => c['id'] == parent)) parent = null;
    final languages = currentBranch.value?.languages ?? const ['ru'];
    final name = TextEditingController(text: item?['name'] ?? '');
    final translations = Translations(item?['i18n'], languages, const ['name']);
    final sortOrder = TextEditingController(text: (item?['sort_order'] ?? 0).toString());
    String? imageUrl = item?['image_url'];
    bool uploading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: _surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            item != null
                ? 'Редактировать категорию'
                : parentId != null
                    ? 'Новая подкатегория'
                    : 'Новая категория',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(name, '${Translations.label('Название', languages.first)} *'),
                  for (final lang in translations.languages) ...[
                    const SizedBox(height: 12),
                    _field(translations.controller(lang, 'name'), Translations.label('Название', lang)),
                  ],
                  const SizedBox(height: 12),
                  _field(sortOrder, 'Порядок', isNumber: true),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: parent,
                    dropdownColor: _surface,
                    isExpanded: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Входит в категорию',
                      labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                      helperText: hasChildren
                          ? 'У неё есть подкатегории — она остаётся основной'
                          : null,
                      helperStyle: const TextStyle(color: Colors.white38),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _accent)),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('— нет, это основная категория'),
                      ),
                      for (final c in parents)
                        DropdownMenuItem<String?>(
                          value: c['id'] as String,
                          child: Text(c['name'] ?? '', overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: hasChildren
                        ? null
                        : (v) => setDialogState(() => parent = v),
                  ),
                  const SizedBox(height: 20),

                  // Фото
                  if (imageUrl != null && imageUrl!.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(imageUrl!, height: 100, width: double.infinity, fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: uploading ? null : () async {
                        setDialogState(() => uploading = true);
                        final url = await _uploadImage();
                        // Окно могли закрыть, пока шла загрузка
                        if (!ctx.mounted) return;
                        setDialogState(() {
                          if (url != null) imageUrl = url;
                          uploading = false;
                        });
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
            // Пока фото загружается, окно не закрываем и не сохраняем
            TextButton(
              onPressed: uploading ? null : () => Navigator.pop(ctx),
              child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.black),
              onPressed: uploading ? null : () async {
                if (name.text.trim().isEmpty) {
                  _toast('Введите ${Translations.label('название', languages.first)}', isError: true);
                  return;
                }
                final branch = currentBranch.value;
                if (branch == null) {
                  _toast('Филиал не выбран', isError: true);
                  return;
                }
                final data = {
                  'name': name.text.trim(),
                  'i18n': translations.toJson(),
                  'sort_order': int.tryParse(sortOrder.text) ?? 0,
                  'parent_id': parent,
                  if (imageUrl != null && imageUrl!.isNotEmpty) 'image_url': imageUrl,
                };
                try {
                  if (item == null) {
                    // Новая категория принадлежит текущему филиалу.
                    // При обновлении branch_id не меняем: переносить
                    // категорию между филиалами значило бы тащить за ней
                    // все товары, и составной ключ в базе это запретит.
                    await api.post('/api/admin/categories', {...data, 'branch_id': branch.id});
                  } else {
                    await api.patch('/api/admin/categories/${item['id']}', data);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                  _toast(item == null ? 'Категория добавлена!' : 'Сохранено!');
                } catch (e) {
                  _toast('Ошибка: $e', isError: true);
                }
              },
              child: Text(
                item == null ? 'Добавить' : 'Сохранить',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final hasChildren = _categories.any((c) => c['parent_id'] == item['id']);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Удалить категорию?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Категория "${item['name']}" и все её товары будут удалены.'
          '${hasChildren ? ' Её подкатегории с блюдами останутся и станут основными категориями.' : ''}',
          style: const TextStyle(color: Colors.white70),
        ),
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
      try {
        await api.delete('/api/admin/categories/${item['id']}');
        _load();
        _toast('Категория удалена');
      } catch (e) {
        _toast('Ошибка: $e', isError: true);
      }
    }
  }

  Widget _field(TextEditingController c, String label, {bool isNumber = false}) {
    return TextField(
      controller: c,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _accent)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tree = categoryTree(_categories);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        automaticallyImplyLeading: false,
        title: Text('Категории', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: _load,
            tooltip: 'Обновить',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_categories',
        backgroundColor: _accent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Добавить', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => _showDialog(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _categories.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.category_outlined, color: Colors.white24, size: 64),
                      const SizedBox(height: 16),
                      Text('Нет категорий', style: GoogleFonts.manrope(color: Colors.white38, fontSize: 18)),
                      const SizedBox(height: 8),
                      Text('Нажмите «Добавить» чтобы создать первую', style: GoogleFonts.manrope(color: Colors.white24, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: tree.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
                  itemBuilder: (_, i) {
                    final cat = tree[i];
                    final isSub = isSubcategory(cat, _categories);
                    final hasImage = (cat['image_url'] as String?)?.isNotEmpty == true;
                    final thumb = isSub ? 40.0 : 56.0;
                    return ListTile(
                      // Подкатегория — со сдвигом под своей основной
                      contentPadding: EdgeInsets.only(left: isSub ? 36 : 4, right: 4, top: 8, bottom: 8),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: hasImage
                            ? Image.network(cat['image_url'], width: thumb, height: thumb, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _placeholder(thumb))
                            : _placeholder(thumb),
                      ),
                      title: Text(cat['name'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      subtitle: Text(
                        '${isSub ? 'подкатегория   ·   ' : ''}'
                        '${_translated(cat)}порядок: ${cat['sort_order'] ?? 0}',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!isSub)
                            IconButton(
                              icon: const Icon(Icons.add, color: Colors.white54),
                              onPressed: () => _showDialog(parentId: cat['id'] as String),
                              tooltip: 'Добавить подкатегорию',
                            ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: _accent),
                            onPressed: () => _showDialog(item: cat),
                            tooltip: 'Редактировать',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () => _delete(cat),
                            tooltip: 'Удалить',
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  /// «перевод: EN, KY   ·   » — на какие языки филиала переведено название
  String _translated(Map<String, dynamic> cat) {
    final extra = (currentBranch.value?.languages ?? const ['ru']).skip(1).toList();
    if (extra.isEmpty) return '';
    final done = i18nFromJson(cat['i18n']);
    final missing = extra.where((l) => !done.containsKey(l)).toList();
    return missing.isEmpty
        ? 'переведено   ·   '
        : 'нет перевода: ${missing.map((l) => l.toUpperCase()).join(', ')}   ·   ';
  }

  Widget _placeholder([double size = 56]) => Container(
    width: size, height: size,
    color: Colors.white10,
    child: Icon(Icons.category, color: Colors.white24, size: size / 2),
  );
}
