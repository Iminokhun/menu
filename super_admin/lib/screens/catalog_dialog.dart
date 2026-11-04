import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api_client.dart';
import '../photo_shrink.dart';

/// Карточка кафе в каталоге на главной сайта: показывать ли кафе гостям,
/// описание, логотип и обложка. Возвращает true, если что-то изменилось.
Future<bool> showCatalogDialog(BuildContext context, Map<String, dynamic> cafe) async {
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CatalogDialog(cafe: cafe),
  );
  return changed == true;
}

class _CatalogDialog extends StatefulWidget {
  final Map<String, dynamic> cafe;
  const _CatalogDialog({required this.cafe});

  @override
  State<_CatalogDialog> createState() => _CatalogDialogState();
}

class _CatalogDialogState extends State<_CatalogDialog> {
  static const _accent = Color(0xFFD4AF37);
  static const _surface = Color(0xFF1A1A1A);

  /// Совпадает с лимитом на сервере
  static const _maxDescription = 300;

  late Map<String, dynamic> _cafe = widget.cafe;
  late bool _listed = _cafe['show_in_catalog'] == true;
  late final _description =
      TextEditingController(text: (_cafe['description'] as String?) ?? '');

  /// Картинки сохраняются сразу при загрузке — диалог надо закрыть с true,
  /// даже если «Сохранить» не нажали
  bool _changed = false;
  bool _busy = false;
  String? _error;

  String get _id => _cafe['id'] as String;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickImage(String kind) async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dot = file.name.lastIndexOf('.');
      final ext = dot > 0 ? file.name.substring(dot + 1).toLowerCase() : 'jpg';
      // Тяжёлый снимок уменьшается здесь: сервер больше 10 МБ не примет
      final photo = await shrinkPhoto(await file.readAsBytes(), ext);
      final r = await api.upload('/api/super/cafes/$_id/upload', photo.bytes, {'kind': kind, 'ext': photo.ext});
      _cafe = Map<String, dynamic>.from(r as Map);
      _changed = true;
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _removeImage(String field) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await api.patch('/api/super/cafes/$_id', {field: ''});
      _cafe = Map<String, dynamic>.from(r as Map);
      _changed = true;
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.patch('/api/super/cafes/$_id', {
        'show_in_catalog': _listed,
        'description': _description.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Каталог: «${_cafe['name']}»',
          style: const TextStyle(color: Colors.white, fontSize: 18)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: _accent,
                value: _listed,
                onChanged: _busy ? null : (v) => setState(() => _listed = v),
                title: const Text('Показывать в каталоге',
                    style: TextStyle(color: Colors.white, fontSize: 15)),
                subtitle: const Text(
                    'Гости увидят кафе на главной в разделе «Поесть». '
                    'Неоплаченное кафе там не показывается',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _description,
                enabled: !_busy,
                maxLines: 3,
                maxLength: _maxDescription,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Короткое описание',
                  hintText: 'Например: восточная кухня, завтраки весь день',
                  hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
                  labelStyle: TextStyle(color: Colors.grey, fontSize: 13),
                  counterStyle: TextStyle(color: Colors.white38),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _accent)),
                ),
              ),
              const SizedBox(height: 12),
              _imageRow('Логотип', 'logo', 'logo_url', square: true),
              const SizedBox(height: 12),
              _imageRow('Обложка', 'cover', 'cover_url', square: false),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, _changed),
          child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.black),
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Text('Сохранить', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  /// Превью картинки и кнопки «Загрузить» / «Убрать». Без логотипа кафе
  /// в каталоге показывается логотип его первого филиала.
  Widget _imageRow(String label, String kind, String field, {required bool square}) {
    final path = (_cafe[field] as String?) ?? '';
    final w = square ? 64.0 : 128.0;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: w,
            height: 64,
            color: Colors.white10,
            child: path.isEmpty
                ? const Icon(Icons.image_outlined, color: Colors.white24)
                : Image.network(api.fileUrl(path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined, color: Colors.white24)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ),
        TextButton(
          onPressed: _busy ? null : () => _pickImage(kind),
          child: Text(path.isEmpty ? 'Загрузить' : 'Заменить',
              style: const TextStyle(color: _accent)),
        ),
        if (path.isNotEmpty)
          IconButton(
            tooltip: 'Убрать',
            onPressed: _busy ? null : () => _removeImage(field),
            icon: const Icon(Icons.close, color: Colors.white38, size: 18),
          ),
      ],
    );
  }
}
