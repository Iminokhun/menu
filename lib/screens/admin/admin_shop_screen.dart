import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../api/api_client.dart';
import '../../config/current_branch.dart';
import '../../image_upload.dart';
import '../../models/branch.dart';
import '../../widgets/qr_sticker.dart';

/// Настройки филиала: название, слоган, телефон, логотип и ссылка QR.
///
/// Раньше экран правил единственную строку таблицы `shop` через
/// `.eq('id', 1)`. Теперь он правит филиал, выбранный в сайдбаре, —
/// у каждого свои данные и свой QR-код.
class AdminShopScreen extends StatefulWidget {
  const AdminShopScreen({super.key});

  @override
  State<AdminShopScreen> createState() => _AdminShopScreenState();
}

class _AdminShopScreenState extends State<AdminShopScreen> {
  final _nameCtrl = TextEditingController();
  final _sloganCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();
  /// Ссылка QR, которая сейчас записана у филиала
  String _savedQrUrl = '';
  String _logoUrl = '';
  bool _loading = true;
  bool _saving = false;

  /// Данные филиала не загрузились. Форму тогда не показываем: «Сохранить»
  /// записал бы устаревшие поля, а лимит 0 из 0 выглядел бы как конец тарифа.
  String? _loadError;

  /// Адрес сайта с меню, например `https://menu.kg`. Его сообщает сервер,
  /// поэтому ссылку QR-кода кафе не набирает — она собирается сама.
  String? _siteBase;

  /// Название кафе — начало адреса нового филиала: у двух кафе может быть
  /// свой «Центр», а адрес на всю платформу один.
  String _cafeName = '';

  /// Сколько филиалов уже заведено и сколько разрешено тарифом кафе.
  /// Лимит задаёт главный администратор платформы; сервер всё равно не
  /// даст создать лишний, здесь он нужен, чтобы погасить кнопку заранее.
  int _branchCount = 0;
  int _maxBranches = 0;

  static const _accent = Color(0xFFD4AF37);
  static const _bg = Color(0xFF0A0A0A);
  static const _surface = Color(0xFF1A1A1A);

  @override
  void initState() {
    super.initState();
    currentBranch.addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    currentBranch.removeListener(_reload);
    _nameCtrl.dispose();
    _sloganCtrl.dispose();
    _phoneCtrl.dispose();
    _slugCtrl.dispose();
    super.dispose();
  }

  void _reload() => _load();

  Future<void> _load() async {
    final branch = currentBranch.value;
    if (branch == null) {
      setState(() => _loading = false);
      return;
    }
    // При первом открытии экран и так в состоянии загрузки, а setState
    // внутри initState недопустим
    if (!_loading || _loadError != null) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final others = await api.list('/api/admin/branches');
      final me = await api.refreshMe();
      final data = others.where((r) => r['id'] == branch.id).firstOrNull;
      if (data == null) {
        throw ApiException(404, 'Филиал не найден в вашем кафе — выберите другой');
      }

      // По числу филиалов блокируется создание новых
      final count = others.length;

      if (!mounted) return;
      setState(() {
        _nameCtrl.text = (data['name'] as String?) ?? '';
        _sloganCtrl.text = (data['slogan'] as String?) ?? '';
        _phoneCtrl.text = (data['phone'] as String?) ?? '';
        _slugCtrl.text = (data['slug'] as String?) ?? '';
        _logoUrl = (data['logo_url'] as String?) ?? '';
        _savedQrUrl = (data['qr_url'] as String?) ?? '';
        _siteBase = me.menuUrl.isEmpty ? null : me.menuUrl;
        _cafeName = me.cafeName;
        _branchCount = count;
        _maxBranches = me.maxBranches;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  Future<String?> _uploadImage(String prefix) async {
    try {
      return await pickAndUploadImage('${prefix}_');
    } catch (e) {
      _toast('Ошибка загрузки: $e', isError: true);
      return null;
    }
  }

  Future<void> _save() async {
    final branch = currentBranch.value;
    if (branch == null) return;

    final slug = _cleanSlug;
    if (slug.isEmpty) {
      _toast('Укажите адрес для ссылки — он нужен для QR-кода', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final row = await api.patch('/api/admin/branches/${branch.id}', {
        'slug': slug,
        'name': _nameCtrl.text.trim(),
        'slogan': _sloganCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'logo_url': _logoUrl,
        'qr_url': _qrLink ?? _savedQrUrl,
      });

      // Сервер вернул обновлённую строку — обновляем текущий филиал, чтобы
      // название и логотип на экране гостя поменялись сразу.
      if (row is Map<String, dynamic>) {
        final updated = Branch.fromJson(row);
        currentBranch.value = updated;
        // slug могли поменять — сохранённая на устройстве настройка
        // иначе указывала бы на филиал, которого больше нет.
        await saveBranchSlug(updated.slug);
      }

      _toast('Настройки сохранены!');
    } catch (e) {
      _toast('Ошибка сохранения: $e', isError: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _addBranch() async {
    // Считаем по базе, а не по значению на экране: филиал могли завести
    // с другого устройства, пока эта админка была открыта.
    final Me me;
    try {
      me = await api.refreshMe();
    } catch (e) {
      _toast('Ошибка: $e', isError: true);
      return;
    }
    if (!mounted) return;

    if (me.branchCount >= me.maxBranches) {
      setState(() {
        _branchCount = me.branchCount;
        _maxBranches = me.maxBranches;
      });
      _toast('По вашему тарифу доступно филиалов: ${me.maxBranches}. '
          'Чтобы открыть ещё, обратитесь к администратору платформы',
          isError: true);
      return;
    }

    final nameCtrl = TextEditingController();
    final slugCtrl = TextEditingController();
    bool slugEditedByHand = false;
    String? errorText;
    bool saving = false;

    final created = await showDialog<Branch>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          Future<void> submit() async {
            final name = nameCtrl.text.trim();
            // Адрес, поправленный руками, приводим к виду, безопасному для ссылки
            final slug = _slugify(slugCtrl.text);
            if (name.isEmpty) {
              setS(() => errorText = 'Введите название филиала');
              return;
            }
            if (slug.isEmpty) {
              setS(() => errorText = 'Адрес для ссылки не может быть пустым');
              return;
            }

            setS(() {
              saving = true;
              errorText = null;
            });
            try {
              final row = await api.post('/api/admin/branches', {'slug': slug, 'name': name});
              if (ctx.mounted) {
                Navigator.pop(ctx, Branch.fromJson(row as Map<String, dynamic>));
              }
            } on ApiException catch (e) {
              // Занятый адрес и лимит тарифа сервер описывает сам
              setS(() {
                saving = false;
                errorText = e.message;
              });
            } catch (e) {
              setS(() {
                saving = false;
                errorText = 'Не удалось создать: $e';
              });
            }
          }

          return AlertDialog(
            backgroundColor: _surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Новый филиал',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    enabled: !saving,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: const InputDecoration(
                      labelText: 'Название филиала',
                      hintText: 'Например: Центр',
                      labelStyle: TextStyle(color: Colors.grey, fontSize: 13),
                      hintStyle: TextStyle(color: Colors.white24),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: _accent)),
                    ),
                    onChanged: (v) {
                      // Пока адрес не правили руками, он следует за названием.
                      // Так заводящему филиал не нужно знать, что это такое.
                      setS(() {
                        if (!slugEditedByHand) {
                          slugCtrl.text = _slugify('$_cafeName $v');
                        }
                        if (errorText != null) errorText = null;
                      });
                    },
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: slugCtrl,
                    enabled: !saving,
                    style: const TextStyle(color: Colors.white70, fontSize: 15),
                    decoration: const InputDecoration(
                      labelText: 'Адрес для ссылки',
                      labelStyle: TextStyle(color: Colors.grey, fontSize: 13),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white12)),
                      focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: _accent)),
                    ),
                    onChanged: (_) => setS(() {
                      slugEditedByHand = true;
                      if (errorText != null) errorText = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Заполняется само. Попадёт в ссылку QR-кода: '
                    '?branch=${_slugify(slugCtrl.text).isEmpty ? '…' : _slugify(slugCtrl.text)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'После печати QR-кодов этот адрес менять нельзя — '
                    'напечатанные коды перестанут открывать меню.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Меню у нового филиала пустое: категории и товары '
                    'заводятся отдельно и от других филиалов не наследуются.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.redAccent, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            errorText!,
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx, null),
                child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _accent, foregroundColor: Colors.black),
                onPressed: saving ? null : submit,
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('Создать',
                        style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (created == null) return;

    // Сразу переключаемся на созданный филиал: иначе человек нажал
    // «Создать» и остался в прежнем, не понимая, получилось ли.
    await saveBranchSlug(created.slug);
    currentBranch.value = created;
    _toast('Филиал «${created.name}» создан, вы уже в нём');
  }

  /// Удаляет текущий филиал вместе со всем его меню.
  ///
  /// Подтверждение требует набрать название филиала: обычное «Вы уверены?»
  /// на необратимом действии нажимают не глядя, а здесь вместе с филиалом
  /// исчезают все его категории и товары — внешний ключ стоит на cascade.
  Future<void> _deleteBranch() async {
    final branch = currentBranch.value;
    if (branch == null) return;

    // Считаем, что именно пропадёт, и сколько филиалов останется
    final rows = await api.list('/api/admin/branches');
    if (!mounted) return;

    if (rows.length <= 1) {
      _toast('Нельзя удалить единственный филиал: меню станет недоступным',
          isError: true);
      return;
    }

    final cats = await api.list('/api/admin/categories', {'branch_id': branch.id});
    final prods = await api.list('/api/admin/products', {'branch_id': branch.id});
    if (!mounted) return;

    final catCount = cats.length;
    final prodCount = prods.length;

    final confirmCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final matches = confirmCtrl.text.trim() == branch.name;
          return AlertDialog(
            backgroundColor: _surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Удалить филиал?',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Вместе с «${branch.name}» будет удалено:',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 10),
                  Text('• категорий: $catCount',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 14)),
                  Text('• товаров: $prodCount',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 14)),
                  const SizedBox(height: 14),
                  const Text(
                    'Восстановить их будет нельзя. Загруженные фотографии '
                    'останутся в хранилище, но ссылок на них не будет.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 18),
                  Text('Введите «${branch.name}», чтобы подтвердить:',
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirmCtrl,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.redAccent)),
                    ),
                    onChanged: (_) => setS(() {}),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  disabledBackgroundColor: Colors.white12,
                  disabledForegroundColor: Colors.white24,
                ),
                onPressed: matches ? () => Navigator.pop(ctx, true) : null,
                child: const Text('Удалить навсегда',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;

    try {
      await api.delete('/api/admin/branches/${branch.id}');

      // Переключаемся на оставшийся филиал: иначе приложение осталось бы
      // с указателем на удалённую строку и показало бы пустое меню.
      final nextBranch = Branch.fromJson(rows.firstWhere((r) => r['id'] != branch.id));
      await saveBranchSlug(nextBranch.slug);
      currentBranch.value = nextBranch;

      _toast('Филиал удалён, вы переключены на «${currentBranch.value?.name}»');
    } catch (e) {
      _toast('Не удалось удалить: $e', isError: true);
    }
  }

  /// Превращает название в адрес для ссылки: «Центр» → `centr`,
  /// «Асанбай» → `asanbay`.
  ///
  /// Нужна, чтобы заводящий филиал вводил только название: слово «slug»
  /// ничего не говорит человеку, который открывает кафе, а ошибиться в нём
  /// дорого — адрес уходит в напечатанные QR-коды.
  String _slugify(String input) {
    const translit = {
      'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'e',
      'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'i', 'к': 'k', 'л': 'l', 'м': 'm',
      'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
      'ф': 'f', 'х': 'h', 'ц': 'c', 'ч': 'ch', 'ш': 'sh', 'щ': 'sch',
      'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
      // кыргызские буквы
      'ң': 'n', 'ө': 'o', 'ү': 'u',
    };

    final buffer = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      if (translit.containsKey(ch)) {
        buffer.write(translit[ch]);
      } else if (RegExp(r'[a-z0-9]').hasMatch(ch)) {
        buffer.write(ch);
      } else {
        buffer.write('-');
      }
    }

    return buffer
        .toString()
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
      duration: const Duration(seconds: 3),
    ));
  }

  Widget _field(TextEditingController c, String label,
      {IconData? icon, ValueChanged<String>? onChanged}) {
    return TextField(
      controller: c,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        prefixIcon: icon != null ? Icon(icon, color: Colors.white38, size: 20) : null,
        enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: _accent, width: 1.5)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
      ),
    );
  }

  /// Адрес в том виде, в каком он сохранится: «Центр 2» → `centr-2`.
  /// Пробел, `&` или `/` в адресе сломали бы ссылку QR-кода.
  String get _cleanSlug => _slugify(_slugCtrl.text);

  /// Ссылка для QR-кода — собирается из адреса сайта и slug филиала.
  String? get _qrLink {
    final slug = _cleanSlug;
    if (_siteBase == null || slug.isEmpty) return null;
    return '$_siteBase/?branch=${Uri.encodeQueryComponent(slug)}';
  }

  Future<void> _stickerAction(
      Future<void> Function({required String title, required String link}) action) async {
    final link = _qrLink ?? _savedQrUrl;
    final title = _nameCtrl.text.trim().isEmpty ? 'Меню' : _nameCtrl.text.trim();
    try {
      await action(title: title, link: link);
    } catch (e) {
      _toast('Не получилось: $e', isError: true);
    }
  }

  Widget _qrCard() {
    final link = _qrLink ?? _savedQrUrl;
    // Записанная ссылка не совпадает с той, что собирается сейчас: поменяли
    // slug или адрес сайта. Напечатанные раньше наклейки ведут по старой.
    final changed = _qrLink != null && _savedQrUrl.isNotEmpty && _savedQrUrl != _qrLink;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ссылка на меню',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text(
            'Собирается сама. Гость сканирует код и попадает в меню этого филиала.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 10),
          SelectableText(
            link.isEmpty ? '—' : link,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          if (changed) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Ссылка изменится после «Сохранить». Сейчас записана:\n'
                      '$_savedQrUrl\n'
                      'Старые наклейки ведут по ней — их нужно перепечатать.',
                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: link.isEmpty
                  ? const SizedBox(
                      width: 160,
                      height: 160,
                      child: Icon(Icons.qr_code_2, size: 70, color: Colors.black26),
                    )
                  : QrImageView(
                      data: link,
                      version: QrVersions.auto,
                      size: 160,
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.white,
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: link.isEmpty ? null : () => _stickerAction(printQrSticker),
                  icon: const Icon(Icons.print_outlined, color: _accent, size: 18),
                  label: const Text('Печать', style: TextStyle(color: _accent)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: _accent)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: link.isEmpty ? null : () => _stickerAction(downloadQrSticker),
                  icon: const Icon(Icons.download_outlined, color: _accent, size: 18),
                  label: const Text('Скачать PDF', style: TextStyle(color: _accent)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: _accent)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _imageCard(String label, String url, String prefix) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (url.isNotEmpty)
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(url, height: 120, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white24, size: 60)),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final newUrl = await _uploadImage(prefix);
                // Пока шла загрузка, могли уйти из раздела
                if (newUrl != null && mounted) {
                  setState(() {
                    if (prefix == 'logo') _logoUrl = newUrl;
                  });
                }
              },
              icon: const Icon(Icons.cloud_upload_outlined, color: _accent, size: 18),
              label: Text(url.isNotEmpty ? 'Заменить' : 'Загрузить', style: const TextStyle(color: _accent)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: _accent)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white24, size: 56),
            const SizedBox(height: 16),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, color: _accent, size: 18),
              label: const Text('Повторить', style: TextStyle(color: _accent)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: _accent)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.manrope(
        color: Colors.white38,
        fontSize: 11,
        letterSpacing: 2,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final branch = currentBranch.value;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        automaticallyImplyLeading: false,
        title: Text(
          branch == null ? 'Филиал' : 'Филиал: ${branch.name}',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        actions: [
          // Кнопку не прячем, а гасим с пояснением: исчезнувший элемент
          // выглядит как сбой, и человек идёт искать его в другом месте.
          if (_loading || _loadError != null)
            const SizedBox.shrink()
          else if (_branchCount >= _maxBranches)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Tooltip(
                message: 'По вашему тарифу доступно филиалов: $_maxBranches. '
                    'Чтобы открыть ещё, обратитесь к администратору платформы.',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, color: Colors.white24, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Филиалов: $_branchCount из $_maxBranches',
                      style: const TextStyle(color: Colors.white24, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            TextButton.icon(
              onPressed: _addBranch,
              icon: const Icon(Icons.add_business_outlined, color: _accent, size: 18),
              label: const Text('Новый филиал', style: TextStyle(color: _accent)),
            ),
            const SizedBox(width: 12),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : branch == null
              ? const Center(
                  child: Text('Филиал не выбран',
                      style: TextStyle(color: Colors.white38, fontSize: 16)),
                )
              : _loadError != null
                  ? _buildLoadError()
                  : SingleChildScrollView(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel('ОСНОВНОЕ'),
                      const SizedBox(height: 12),
                      _field(_nameCtrl, 'Название филиала', icon: Icons.storefront_outlined),
                      const SizedBox(height: 12),
                      _field(_sloganCtrl, 'Слоган / Подзаголовок', icon: Icons.format_quote_outlined),
                      const SizedBox(height: 12),
                      _field(_phoneCtrl, 'Телефон', icon: Icons.phone_outlined),
                      const SizedBox(height: 12),
                      _field(_slugCtrl, 'Адрес для ссылки', icon: Icons.tag,
                          onChanged: (_) => setState(() {})),
                      if (_cleanSlug != _slugCtrl.text.trim()) ...[
                        const SizedBox(height: 6),
                        Text(
                          _cleanSlug.isEmpty
                              ? 'Нужны латинские или русские буквы либо цифры'
                              : 'Сохранится как: $_cleanSlug',
                          style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 30),

                      _sectionLabel('ЛОГОТИП'),
                      const SizedBox(height: 12),
                      _imageCard('Логотип филиала', _logoUrl, 'logo'),
                      const SizedBox(height: 30),

                      _sectionLabel('QR-КОД МЕНЮ'),
                      const SizedBox(height: 12),
                      _qrCard(),
                      const SizedBox(height: 40),

                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: _saving
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            _saving ? 'Сохранение...' : 'СОХРАНИТЬ',
                            style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 1),
                          ),
                        ),
                      ),

                      // Удаление отделено от основного блока и не выделено
                      // цветом: это редкое действие, и промахнуться по нему
                      // должно быть трудно, а не удобно.
                      const SizedBox(height: 50),
                      Divider(color: Colors.white.withValues(alpha: 0.08)),
                      const SizedBox(height: 16),
                      _sectionLabel('ОПАСНАЯ ЗОНА'),
                      const SizedBox(height: 10),
                      const Text(
                        'Удаление заберёт с собой все категории и товары филиала. '
                        'Если нужно просто переименовать зал — меняйте поля выше.',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _deleteBranch,
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent, size: 18),
                          label: const Text('Удалить филиал',
                              style: TextStyle(color: Colors.redAccent)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: Colors.redAccent.withValues(alpha: 0.4)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
    );
  }
}
