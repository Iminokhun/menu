import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../api/api_client.dart';
import '../config/current_branch.dart';
import '../menu_store.dart';
import '../open_link.dart';
import '../theme/current_theme.dart';
import '../theme/theme_config.dart';
import '../widgets/auth_image.dart';
import '../widgets/motion.dart';
import 'branch_picker_screen.dart';

/// Кафе в каталоге на главной сайта — то, что отдаёт `/api/public/cafes`
class CatalogCafe {
  final String id;
  final String name;
  final String description;
  final String logoUrl;
  final String coverUrl;
  final List<CatalogBranch> branches;

  const CatalogCafe({
    required this.id,
    required this.name,
    required this.description,
    required this.logoUrl,
    required this.coverUrl,
    required this.branches,
  });

  factory CatalogCafe.fromJson(Map<String, dynamic> j) => CatalogCafe(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    description: j['description'] as String? ?? '',
    logoUrl: j['logo_url'] as String? ?? '',
    coverUrl: j['cover_url'] as String? ?? '',
    branches: [
      for (final b in j['branches'] as List? ?? const [])
        CatalogBranch.fromJson(b as Map<String, dynamic>),
    ],
  );
}

class CatalogBranch {
  final String slug;
  final String name;
  final String slogan;
  final String logoUrl;

  /// Где филиал — заполняет кафе в своей админке
  final String address;
  final String mapUrl;
  final String hours;

  const CatalogBranch({
    required this.slug,
    required this.name,
    required this.slogan,
    required this.logoUrl,
    this.address = '',
    this.mapUrl = '',
    this.hours = '',
  });

  factory CatalogBranch.fromJson(Map<String, dynamic> j) => CatalogBranch(
    slug: j['slug'] as String,
    name: j['name'] as String? ?? '',
    slogan: j['slogan'] as String? ?? '',
    logoUrl: j['logo_url'] as String? ?? '',
    address: j['address'] as String? ?? '',
    mapUrl: j['map_url'] as String? ?? '',
    hours: j['hours'] as String? ?? '',
  );

  /// «ул. Киевская 95 · 10:00–23:00» — то, что есть из двух
  String get place => [address, hours].where((s) => s.isNotEmpty).join(' · ');
}

/// Раздел главной. Пока раздел один — «Поесть»: в нём все кафе каталога.
/// Новые разделы добавляются сюда.
class _Section {
  final String title;
  final String subtitle;
  final IconData icon;
  const _Section(this.title, this.subtitle, this.icon);
}

const _sections = [
  _Section('Поесть', 'Кафе и рестораны', Icons.restaurant_rounded),
];

enum _Page { home, cafes, branches }

/// Пока раздел один, выбирать на главной нечего: гость сразу видит
/// список кафе, а плитки разделов появятся вместе со вторым разделом
final _singleSection = _sections.length == 1;
final _firstPage = _singleSection ? _Page.cafes : _Page.home;

/// Где гость был в каталоге — после «Все кафе» он возвращается туда же,
/// а не на главную. Экран пересоздаётся при каждом возврате, поэтому
/// состояние живёт здесь.
_Page _lastPage = _firstPage;
CatalogCafe? _lastCafe;
List<CatalogCafe>? _cachedCafes;

/// Гость уходит из меню кафе обратно в каталог
void backToCatalog() {
  HapticFeedback.selectionClick();
  menuStore.close();
  openedFromCatalog.value = false;
  currentBranch.value = null;
}

/// Главная сайта для гостя: разделы → кафе → филиал → меню.
///
/// Экран не переходит в меню сам — как и [BranchPickerScreen], он только
/// открывает филиал в [menuStore], а подмену на меню делает `home` в
/// main.dart. Шаги каталога сменяются внутри экрана, не в Navigator:
/// иначе страницы каталога остались бы лежать поверх меню.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  _Page _page = _lastPage;
  CatalogCafe? _cafe = _lastCafe;
  List<CatalogCafe>? _cafes = _cachedCafes;
  bool _loading = false;
  String? _error;

  /// Какой филиал сейчас открывается — на его карточке крутится индикатор
  String? _opening;

  @override
  void initState() {
    super.initState();
    if (_page != _Page.home) _loadCafes();
  }

  void _go(_Page page, {CatalogCafe? cafe}) {
    setState(() {
      _page = _lastPage = page;
      if (cafe != null) _cafe = _lastCafe = cafe;
    });
  }

  void _back() {
    HapticFeedback.selectionClick();
    _go(switch (_page) {
      _Page.branches => _Page.cafes,
      _ => _firstPage,
    });
  }

  Future<void> _openSection() async {
    HapticFeedback.selectionClick();
    _go(_Page.cafes);
    await _loadCafes();
  }

  /// Список обновляется при каждом заходе, но уже полученный виден сразу
  Future<void> _loadCafes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await api.list('/api/public/cafes');
      final cafes = rows.map(CatalogCafe.fromJson).toList();
      if (!mounted) return;
      setState(() => _cafes = _cachedCafes = cafes);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e is ApiException && e.isOffline
            ? 'Нет связи с сервером'
            : '$e',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openCafe(CatalogCafe cafe) {
    HapticFeedback.selectionClick();
    // Один филиал — выбирать не из чего, сразу меню
    if (cafe.branches.length == 1) {
      _lastCafe = cafe;
      _openBranch(cafe.branches.first);
    } else {
      _go(_Page.branches, cafe: cafe);
    }
  }

  Future<void> _openBranch(CatalogBranch branch) async {
    if (_opening != null) return;
    setState(() => _opening = branch.slug);
    openedFromCatalog.value = true;
    await menuStore.open(branch.slug);
    // Меню открылось — экран уже сменился на меню кафе
    if (currentBranch.value != null || !mounted) return;
    final message = switch (menuStore.status.value) {
      MenuResult.unpaid => 'Меню этого кафе временно недоступно',
      MenuResult.offlineNoCache => 'Нет связи с сервером',
      _ => 'Меню не найдено',
    };
    menuStore.close();
    openedFromCatalog.value = false;
    setState(() => _opening = null);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    // Кафе могло пропасть из каталога — список стоит перечитать
    _loadCafes();
  }

  void _staffLogin() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BranchPickerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeConfig>(
      valueListenable: appTheme,
      builder: (context, config, child) => PopScope(
        // «Назад» ведёт по шагам каталога: филиалы → кафе → главная.
        // Шаги сменяются внутри экрана, своих записей в истории браузера
        // у них нет. А вот с первой страницы возвращать некуда: там
        // «назад» работает как обычно и уводит гостя на страницу,
        // с которой он пришёл — иначе он заперт на сайте
        canPop: _page == _firstPage,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: Scaffold(
          backgroundColor: config.bg,
          body: SafeArea(
            // Новый шаг проявляется и чуть поднимается, уходящий гаснет
            // быстрее и без движения — переход не тянет внимание на себя
            child: AnimatedSwitcher(
              duration: _still(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 240),
              reverseDuration: _still(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.015),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(_page),
                child: switch (_page) {
                  _Page.home => _buildHome(config),
                  _Page.cafes => _buildCafes(config),
                  _Page.branches => _buildBranches(config),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// «Уменьшить движение» в настройках телефона — без анимации
  static bool _still(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Карточка каталога — одна поверхность для разделов, кафе и филиалов.
  /// Тонкая нейтральная рамка отделяет её от фона, двойная мягкая тень
  /// даёт объём; фирменный цвет остаётся значкам и стрелкам. Пока
  /// открывается другое кафе, карточка приглушена и не нажимается.
  Widget _card(
    ThemeConfig config, {
    required double radius,
    required VoidCallback onTap,
    bool busy = false,
    required Widget child,
  }) {
    final dark = config.brightness == Brightness.dark;
    final locked = _opening != null;
    return AnimatedOpacity(
      opacity: locked && !busy ? 0.5 : 1,
      duration: const Duration(milliseconds: 150),
      child: Pressable(
        pressedScale: 0.98,
        onTap: locked ? null : onTap,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: config.surface,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: config.text.withValues(alpha: dark ? 0.08 : 0.07),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.22 : 0.04),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.18 : 0.06),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  /// Логотип с тонкой нейтральной обводкой внутрь: светлый или тёмный край
  /// картинки не сливается с карточкой
  Widget _framed(
    ThemeConfig config, {
    required double radius,
    required Widget child,
  }) {
    final edge =
        (config.brightness == Brightness.dark ? Colors.white : Colors.black)
            .withValues(alpha: 0.1);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: edge),
        ),
        child: child,
      ),
    );
  }

  /// Колонка по центру: на телефоне во всю ширину, на большом экране
  /// не растягивается
  Widget _column(List<Widget> children) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: children,
      ),
    ),
  );

  Widget _header(ThemeConfig config, String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Назад',
            onPressed: _back,
            icon: Icon(Icons.arrow_back_rounded, color: config.accent),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: config.text,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: config.text.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ главная

  Widget _buildHome(ThemeConfig config) {
    return _column([
      _brand(config, subtitle: 'Меню кафе и ресторанов'),
      for (final s in _sections)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _sectionTile(s, config),
        ),
      _staffLink(config),
    ]);
  }

  /// Шапка главной: знак и название menu.kg
  Widget _brand(ThemeConfig config, {required String subtitle}) {
    return Column(
      children: [
        const SizedBox(height: 28),
        // Знак и название — одной строкой, как вывеска
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Знак круглый: квадратный тёмный фон картинки срезается
            ClipOval(
              child: Image.asset('assets/icon/icon.png', width: 52, height: 52),
            ),
            const SizedBox(width: 12),
            Text(
              'menu.kg',
              style: GoogleFonts.outfit(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                height: 1,
                color: config.text,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: 15,
            color: config.text.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _staffLink(ThemeConfig config) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Center(
        child: TextButton(
          onPressed: _staffLogin,
          child: Text(
            'Вход для сотрудников',
            style: GoogleFonts.manrope(
              fontSize: 13,
              color: config.text.withValues(alpha: 0.45),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTile(_Section s, ThemeConfig config) {
    return _card(
      config,
      radius: 22,
      onTap: _openSection,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: config.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(s.icon, color: config.accent, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title,
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: config.text,
                    ),
                  ),
                  Text(
                    s.subtitle,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: config.text.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 18,
              color: config.accent,
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ кафе

  Widget _buildCafes(ThemeConfig config) {
    final cafes = _cafes;
    return _column([
      if (_singleSection)
        _brand(config, subtitle: 'Выберите, где поесть')
      else
        _header(config, _sections.first.title),
      if (cafes == null && _loading)
        Padding(
          padding: const EdgeInsets.only(top: 60),
          child: Center(child: CircularProgressIndicator(color: config.accent)),
        )
      else if (cafes == null || (cafes.isEmpty && _error != null))
        _message(
          config,
          icon: Icons.wifi_off_rounded,
          title: _error ?? 'Не удалось загрузить',
          retry: true,
        )
      else if (cafes.isEmpty)
        _message(
          config,
          icon: Icons.storefront_outlined,
          title: 'Здесь пока нет кафе',
        )
      else
        for (final (i, c) in cafes.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: FadeSlideIn(index: i, child: _cafeCard(c, config)),
          ),
      if (_singleSection) _staffLink(config),
    ]);
  }

  Widget _cafeCard(CatalogCafe cafe, ThemeConfig config) {
    final opening =
        cafe.branches.length == 1 && _opening == cafe.branches.first.slug;
    return _card(
      config,
      radius: 22,
      busy: opening,
      onTap: () => _openCafe(cafe),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Обложка прижата к краям карточки и скругляется вместе с ней;
          // снизу — волосяная линия, чтобы фото не растекалось в текст
          if (cafe.coverUrl.isNotEmpty)
            DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: config.text.withValues(alpha: 0.08),
                  ),
                ),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 7,
                child: AuthImage(url: cafe.coverUrl, fit: BoxFit.cover),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _framed(
                  config,
                  radius: 14,
                  child: AuthImage(
                    url: cafe.logoUrl.isNotEmpty
                        ? cafe.logoUrl
                        : cafe.branches.first.logoUrl,
                    width: 56,
                    height: 56,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cafe.name,
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: config.text,
                        ),
                      ),
                      if (cafe.description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          cafe.description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            height: 1.35,
                            color: config.text.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                      // Один филиал — его адрес; несколько — сколько их и
                      // первые два адреса, остальные видны на следующем шаге
                      if (cafe.branches.length == 1 &&
                          cafe.branches.first.place.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _placeLine(config, cafe.branches.first.place),
                      ],
                      if (cafe.branches.length > 1) ...[
                        const SizedBox(height: 6),
                        Text(
                          _branchCount(cafe.branches.length),
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: config.accent,
                          ),
                        ),
                        for (final b
                            in cafe.branches
                                .where((b) => b.address.isNotEmpty)
                                .take(2)) ...[
                          const SizedBox(height: 4),
                          _placeLine(config, b.address),
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (cafe.branches.length == 1 &&
                    cafe.branches.first.mapUrl.isNotEmpty)
                  _mapButton(config, cafe.branches.first.mapUrl),
                _arrowOrSpinner(config, opening),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _branchCount(int n) {
    final mod10 = n % 10, mod100 = n % 100;
    final word = mod10 == 1 && mod100 != 11
        ? 'филиал'
        : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
        ? 'филиала'
        : 'филиалов';
    return '$n $word';
  }

  // ------------------------------------------------------------ филиалы

  Widget _buildBranches(ThemeConfig config) {
    final cafe = _cafe;
    if (cafe == null) return _buildCafes(config);
    return _column([
      _header(config, cafe.name, subtitle: 'Выберите филиал'),
      for (final (i, b) in cafe.branches.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: FadeSlideIn(index: i, child: _branchTile(b, config)),
        ),
    ]);
  }

  Widget _branchTile(CatalogBranch branch, ThemeConfig config) {
    return _card(
      config,
      radius: 20,
      busy: _opening == branch.slug,
      onTap: () => _openBranch(branch),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _framed(
              config,
              radius: 14,
              child: AuthImage(url: branch.logoUrl, width: 56, height: 56),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    branch.name,
                    style: GoogleFonts.outfit(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: config.text,
                    ),
                  ),
                  // Гостю, выбирающему филиал, важнее где он, чем слоган
                  if (branch.place.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _placeLine(config, branch.place),
                  ] else if (branch.slogan.isNotEmpty)
                    Text(
                      branch.slogan,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: config.text.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
            ),
            if (branch.mapUrl.isNotEmpty) _mapButton(config, branch.mapUrl),
            _arrowOrSpinner(config, _opening == branch.slug),
          ],
        ),
      ),
    );
  }

  /// Адрес и часы работы — мелко, со значком места
  Widget _placeLine(ThemeConfig config, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            Icons.place_outlined,
            size: 14,
            color: config.text.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              height: 1.3,
              color: config.text.withValues(alpha: 0.6),
            ),
          ),
        ),
      ],
    );
  }

  /// «Как добраться» — карта филиала в новой вкладке. Своя кнопка поверх
  /// карточки: нажатие на неё не открывает меню. Поле нажатия 44×44.
  Widget _mapButton(ThemeConfig config, String url) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: IconButton(
        tooltip: 'Как добраться',
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        style: IconButton.styleFrom(
          backgroundColor: config.accent.withValues(alpha: 0.12),
        ),
        onPressed: () {
          HapticFeedback.selectionClick();
          openLink(url);
        },
        icon: Icon(Icons.directions_outlined, size: 20, color: config.accent),
      ),
    );
  }

  /// Стрелка и индикатор сменяют друг друга плавно, без «мигания»
  Widget _arrowOrSpinner(ThemeConfig config, bool busy) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 180),
    transitionBuilder: (child, anim) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween(begin: 0.6, end: 1.0).animate(anim),
        child: child,
      ),
    ),
    child: busy
        ? SizedBox(
            key: const ValueKey('busy'),
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: config.accent,
            ),
          )
        : Icon(
            Icons.arrow_forward_ios_rounded,
            key: const ValueKey('idle'),
            size: 18,
            color: config.accent,
          ),
  );

  Widget _message(
    ThemeConfig config, {
    required IconData icon,
    required String title,
    bool retry = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 50),
      child: Column(
        children: [
          Icon(icon, size: 56, color: config.text.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: config.text,
            ),
          ),
          if (retry) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _loading ? null : _loadCafes,
              icon: Icon(Icons.refresh, color: config.accent, size: 18),
              label: Text('Повторить', style: TextStyle(color: config.accent)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: config.accent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
