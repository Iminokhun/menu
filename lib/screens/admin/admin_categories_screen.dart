import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../image_upload.dart';

class AdminCategoriesScreen extends StatefulWidget {
  const AdminCategoriesScreen({super.key});

  @override
  State<AdminCategoriesScreen> createState() => _AdminCategoriesScreenState();
}

class _AdminCategoriesScreenState extends State<AdminCategoriesScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;

  static const _accent = Color(0xFFD4AF37);
  static const _bg = Color(0xFF0A0A0A);
  static const _surface = Color(0xFF1A1A1A);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _client.from('categories').select().order('sort_order');
      setState(() {
        _categories = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
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

  void _showDialog({Map<String, dynamic>? item}) {
    final nameRu = TextEditingController(text: item?['name'] ?? '');
    final nameEn = TextEditingController(text: item?['name_en'] ?? '');
    final nameTr = TextEditingController(text: item?['name_tr'] ?? '');
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
            item == null ? 'Новая категория' : 'Редактировать категорию',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(nameRu, 'Название (RU) *'),
                  const SizedBox(height: 12),
                  _field(nameEn, 'Название (EN)'),
                  const SizedBox(height: 12),
                  _field(nameTr, 'Название (TR)'),
                  const SizedBox(height: 12),
                  _field(sortOrder, 'Порядок', isNumber: true),
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
                        if (url != null) setDialogState(() => imageUrl = url);
                        setDialogState(() => uploading = false);
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
                if (nameRu.text.trim().isEmpty) {
                  _toast('Введите название (RU)', isError: true);
                  return;
                }
                final data = {
                  'name': nameRu.text.trim(),
                  'name_en': nameEn.text.trim(),
                  'name_tr': nameTr.text.trim(),
                  'sort_order': int.tryParse(sortOrder.text) ?? 0,
                  if (imageUrl != null && imageUrl!.isNotEmpty) 'image_url': imageUrl,
                };
                try {
                  if (item == null) {
                    await _client.from('categories').insert(data);
                  } else {
                    await _client.from('categories').update(data).eq('id', item['id']);
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Удалить категорию?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Категория "${item['name']}" и все её товары будут удалены.',
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
      await _client.from('categories').delete().eq('id', item['id']);
      _load();
      _toast('Категория удалена');
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
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
                  itemBuilder: (_, i) {
                    final cat = _categories[i];
                    final hasImage = (cat['image_url'] as String?)?.isNotEmpty == true;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: hasImage
                            ? Image.network(cat['image_url'], width: 56, height: 56, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _placeholder())
                            : _placeholder(),
                      ),
                      title: Text(cat['name'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      subtitle: Text(
                        '${cat['name_en'] ?? '—'}  /  ${cat['name_tr'] ?? '—'}   ·   порядок: ${cat['sort_order'] ?? 0}',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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

  Widget _placeholder() => Container(
    width: 56, height: 56,
    color: Colors.white10,
    child: const Icon(Icons.category, color: Colors.white24, size: 28),
  );
}
