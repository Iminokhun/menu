import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../api/api_client.dart';
import '../../config/current_branch.dart';
import '../../image_upload.dart';
import '../../models/branch.dart';
import '../../theme/theme_config.dart';
import '../../widgets/auth_image.dart';
import '../../widgets/theme_background.dart';

/// «Оформление»: тема, фирменный цвет, фон, карточки и шрифт меню филиала.
///
/// Настройка хранится на сервере у филиала, поэтому все гости и планшеты
/// этого филиала видят одно и то же меню. Сверху — живой предпросмотр:
/// он меняется сразу, ещё до «Сохранить».
class AdminStyleScreen extends StatefulWidget {
  const AdminStyleScreen({super.key});

  @override
  State<AdminStyleScreen> createState() => _AdminStyleScreenState();
}

class _AdminStyleScreenState extends State<AdminStyleScreen> {
  static const _accent = Color(0xFFD4AF37);
  static const _bg = Color(0xFF0A0A0A);
  static const _surface = Color(0xFF1A1A1A);

  static const _themeNames = {
    'midnight': 'Тёмная',
    'porcelain': 'Светлая',
    'royal': 'Королевская',
    'sea': 'Морская',
    'sakura': 'Сакура',
    'highContrast': 'Контрастная',
  };

  /// Готовые фирменные цвета — чтобы не подбирать код цвета вручную
  static const _swatches = [
    '#D4AF37', '#C0392B', '#E67E22', '#F1C40F', '#27AE60',
    '#16A085', '#2980B9', '#8E44AD', '#E84393', '#795548',
  ];

  static const _fonts = {
    'classic': 'Классический',
    'montserrat': 'Montserrat',
    'playfair': 'Playfair Display',
    'oswald': 'Oswald',
    'lora': 'Lora',
  };

  BranchStyle _saved = const BranchStyle();
  BranchStyle _draft = const BranchStyle();
  String _branchName = '';
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;
  String? _loadError;
  final _hexCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    currentBranch.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    currentBranch.removeListener(_load);
    _hexCtrl.dispose();
    super.dispose();
  }

  bool get _changed => _draft != _saved;

  Future<void> _load() async {
    final branch = currentBranch.value;
    if (branch == null) return;
    if (!_loading || _loadError != null) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final rows = await api.list('/api/admin/branches');
      final row = rows.where((r) => r['id'] == branch.id).firstOrNull;
      if (row == null) throw ApiException(404, 'Филиал не найден в вашем кафе');
      final b = Branch.fromJson(row);
      if (!mounted) return;
      setState(() {
        _saved = _draft = b.style;
        _branchName = b.name;
        _hexCtrl.text = b.style.accent;
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

  void _set(BranchStyle s) => setState(() => _draft = s);

  Future<void> _uploadBackground() async {
    setState(() => _uploading = true);
    try {
      final url = await pickAndUploadImage('bg_');
      if (url != null && mounted) _set(_draft.copyWith(bgUrl: url));
    } catch (e) {
      _toast('Не удалось загрузить фото: $e', isError: true);
    }
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _save() async {
    final branch = currentBranch.value;
    if (branch == null) return;
    setState(() => _saving = true);
    try {
      final row = await api.patch('/api/admin/branches/${branch.id}', _draft.toJson());
      final updated = Branch.fromJson(row as Map<String, dynamic>);
      // Филиал с новым оформлением — меню на этом устройстве меняется сразу
      currentBranch.value = updated;
      if (mounted) setState(() => _saved = _draft = updated.style);
      _toast('Оформление сохранено');
    } catch (e) {
      _toast('Не сохранилось: $e', isError: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
    ));
  }

  // ------------------------------------------------------------------ экран

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        automaticallyImplyLeading: false,
        title: Text('Оформление',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          if (_changed && !_loading)
            TextButton(
              onPressed: () => setState(() {
                _draft = _saved;
                _hexCtrl.text = _saved.accent;
              }),
              child: const Text('Отменить изменения', style: TextStyle(color: Colors.white54)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _loadError != null
              ? _error()
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(30, 24, 30, 30),
                        children: [
                          _Preview(style: _draft, cafeName: _branchName),
                          const SizedBox(height: 30),
                          _label('ТЕМА'),
                          _themes(),
                          const SizedBox(height: 28),
                          _label('ФИРМЕННЫЙ ЦВЕТ'),
                          _hint('Кнопки, цены и акценты. В контрастной теме цвет не меняется.'),
                          _colors(),
                          const SizedBox(height: 28),
                          _label('ФОН'),
                          _background(),
                          const SizedBox(height: 28),
                          _label('РАЗМЕР КАРТОЧЕК'),
                          _choice(const {'small': 'Мелкие', '': 'Обычные', 'large': 'Крупные'},
                              _draft.cardSize, (v) => _set(_draft.copyWith(cardSize: v))),
                          const SizedBox(height: 28),
                          _label('УГЛЫ'),
                          _choice(const {'sharp': 'Острые', '': 'Мягкие', 'round': 'Круглые'},
                              _draft.corners, (v) => _set(_draft.copyWith(corners: v))),
                          const SizedBox(height: 28),
                          _label('ШРИФТ НАЗВАНИЙ'),
                          _fontList(),
                        ],
                      ),
                    ),
                    _saveBar(),
                  ],
                ),
    );
  }

  Widget _error() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white24, size: 56),
            const SizedBox(height: 16),
            Text(_loadError!, style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, color: _accent, size: 18),
              label: const Text('Повторить', style: TextStyle(color: _accent)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: _accent)),
            ),
          ],
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: GoogleFonts.manrope(
                color: Colors.white38, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w700)),
      );

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(color: Colors.white38, fontSize: 12)),
      );

  Widget _themes() {
    final current = _draft.theme.isEmpty ? 'midnight' : _draft.theme;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final type in AppThemeType.values)
          Builder(builder: (_) {
            final t = ThemeConfig.palettes[type]!;
            final selected = current == type.name;
            return InkWell(
              onTap: () => _set(_draft.copyWith(theme: type.name == 'midnight' ? '' : type.name)),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 120,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: t.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? _accent : Colors.white12,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      _dot(t.surface),
                      const SizedBox(width: 4),
                      _dot(t.accent),
                      const SizedBox(width: 4),
                      _dot(t.text),
                    ]),
                    const SizedBox(height: 10),
                    Text(_themeNames[type.name] ?? type.name,
                        style: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _dot(Color c) => Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
      );

  Widget _colors() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceChip(
          label: const Text('Как в теме'),
          selected: _draft.accent.isEmpty,
          onSelected: (_) {
            _hexCtrl.text = '';
            _set(_draft.copyWith(accent: ''));
          },
        ),
        for (final hex in _swatches)
          Tooltip(
            message: hex,
            child: InkWell(
              onTap: () {
                _hexCtrl.text = hex;
                _set(_draft.copyWith(accent: hex));
              },
              customBorder: const CircleBorder(),
              // Видимый кружок 32 px, нажимать можно по 44 px вокруг
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: ThemeConfig.parseHexColor(hex),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _draft.accent == hex ? Colors.white : Colors.white24,
                        width: _draft.accent == hex ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        SizedBox(
          width: 130,
          child: TextField(
            controller: _hexCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: const InputDecoration(
              isDense: true,
              hintText: '#AA3355',
              hintStyle: TextStyle(color: Colors.white24),
              labelText: 'Свой цвет',
              labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: _accent)),
            ),
            onChanged: (v) {
              final hex = v.trim().toUpperCase();
              // Цвет меняем, только когда код набран полностью
              if (ThemeConfig.parseHexColor(hex) != null) _set(_draft.copyWith(accent: hex));
            },
          ),
        ),
      ],
    );
  }

  Widget _background() {
    final custom = _draft.bgUrl.isNotEmpty && _draft.bgUrl != 'none';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ChoiceChip(
              label: const Text('Как в теме'),
              selected: _draft.bgUrl.isEmpty,
              onSelected: (_) => _set(_draft.copyWith(bgUrl: '')),
            ),
            ChoiceChip(
              label: const Text('Однотонный'),
              selected: _draft.bgUrl == 'none',
              onSelected: (_) => _set(_draft.copyWith(bgUrl: 'none')),
            ),
            ActionChip(
              avatar: _uploading
                  ? const SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.photo_outlined, size: 18),
              label: Text(custom ? 'Заменить фото' : 'Своё фото'),
              onPressed: _uploading ? null : _uploadBackground,
            ),
          ],
        ),
        if (custom) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AuthImage(url: _draft.bgUrl, width: 220, height: 120, fit: BoxFit.cover),
          ),
        ],
      ],
    );
  }

  Widget _choice(Map<String, String> options, String value, ValueChanged<String> onPick) {
    return Wrap(
      spacing: 10,
      children: [
        for (final e in options.entries)
          ChoiceChip(
            label: Text(e.value),
            selected: value == e.key,
            onSelected: (_) => onPick(e.key),
          ),
      ],
    );
  }

  Widget _fontList() {
    final current = _draft.titleFont.isEmpty ? 'classic' : _draft.titleFont;
    return Column(
      children: [
        for (final e in _fonts.entries)
          Builder(builder: (_) {
            final selected = current == e.key;
            final preview = ThemeConfig.forStyle(_draft.copyWith(titleFont: e.key));
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => _set(_draft.copyWith(titleFont: e.key == 'classic' ? '' : e.key)),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: selected ? _accent : Colors.white12, width: selected ? 2 : 1),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Плов по-узбекски',
                          style: preview.dishTitleStyle(
                              fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                      Text(e.value, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      if (selected) ...[
                        const SizedBox(width: 10),
                        const Icon(Icons.check_circle, color: _accent, size: 20),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _saveBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(30, 12, 30, 20),
      decoration: BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: _changed && !_saving && !_uploading ? _save : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.black,
            disabledBackgroundColor: Colors.white10,
            disabledForegroundColor: Colors.white30,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: _saving
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Icon(Icons.save_outlined),
          label: Text(
            _saving ? 'Сохранение...' : (_changed ? 'СОХРАНИТЬ' : 'СОХРАНЕНО'),
            style: GoogleFonts.manrope(fontWeight: FontWeight.w800, letterSpacing: 1),
          ),
        ),
      ),
    );
  }
}

/// Мини-меню с выбранным оформлением: шапка кафе, категория и блюдо.
class _Preview extends StatelessWidget {
  final BranchStyle style;
  final String cafeName;

  const _Preview({required this.style, required this.cafeName});

  @override
  Widget build(BuildContext context) {
    final c = ThemeConfig.forStyle(style);
    final cardW = 120 * c.gridScale;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 260,
        decoration: BoxDecoration(color: c.bg, border: Border.all(color: Colors.white12)),
        child: Stack(
          children: [
            Positioned.fill(child: ThemeBackground(config: c)),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cafeName.isEmpty ? 'Ваше кафе' : cafeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: c.titleStyle(fontSize: 26, fontWeight: FontWeight.w800, color: c.text)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // категория
                        Container(
                          width: cardW,
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(c.radius(22)),
                          ),
                          alignment: Alignment.bottomCenter,
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('ГОРЯЧЕЕ',
                                  style: c.titleStyle(
                                      fontSize: 13, fontWeight: FontWeight.w800, color: c.text)),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: c.accent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('ОТКРЫТЬ',
                                    style: TextStyle(
                                        fontSize: 8, fontWeight: FontWeight.bold, color: c.onAccent)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        // блюдо
                        Container(
                          width: cardW,
                          decoration: BoxDecoration(
                            color: c.glass,
                            borderRadius: BorderRadius.circular(c.radius(18)),
                            border: Border.all(color: c.text.withValues(alpha: 0.1)),
                          ),
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: c.text.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(c.radius(12)),
                                  ),
                                  child: Center(
                                    child: Icon(Icons.restaurant_rounded,
                                        color: c.text.withValues(alpha: 0.25)),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text('Плов',
                                  style: c.dishTitleStyle(
                                      fontSize: 15, fontWeight: FontWeight.bold, color: c.accent)),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text('350 с.',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                            color: c.text)),
                                  ),
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                                    child: Icon(Icons.add, size: 14, color: c.onAccent),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
