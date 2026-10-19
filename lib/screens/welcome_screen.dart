import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../widgets/auth_image.dart';
import '../widgets/motion.dart';
import '../widgets/theme_background.dart';
import '../config/current_branch.dart';
import '../database.dart';
import '../menu_store.dart';
import '../models/branch.dart';
import '../models/product.dart';
import '../theme/theme_config.dart';
import '../theme/current_theme.dart';
import '../l10n/app_localizations.dart';
import '../l10n/translation_service.dart';
import '../widgets/lang_switcher.dart';
import '../responsive.dart';
import 'menu_screen.dart';
import 'search_screen.dart';
import 'admin/admin_shell.dart';
import '../api/api_client.dart';
import '../widgets/admin_login_dialog.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final DatabaseService _db = DatabaseService();

  List<Product> rootCategories = [];

  /// Меню ещё не получено ни с сервера, ни из сохранённой копии
  bool get isLoading => menuStore.data.value == null;
  bool _isNavigating = false;

  // Данные заведения живут в филиале, а не в отдельном состоянии экрана:
  // переключили филиал в админке — здесь сразу новые название и логотип.
  String get shopLogoUrl => currentBranch.value?.logoUrl ?? '';
  String get shopQrUrl => currentBranch.value?.qrUrl ?? '';
  String get shopName => currentBranch.value?.name ?? 'CAFE ANDALUS';
  String get shopSlogan => currentBranch.value?.slogan ?? 'Добро пожаловать';

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    currentLocale.addListener(_rebuildOnLocaleChange);
    currentBranch.addListener(_onBranchChanged);
    menuStore.data.addListener(_applyMenu);
    menuStore.refreshing.addListener(_rebuild);
    // Первый расчёт — без setState: экран ещё строится
    _applyMenu();
    _onBranchChanged();
    _initialized = true;
  }

  /// До конца initState перестраивать экран нельзя и не нужно
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Планшет-киоск держим в альбоме, телефон пусть вращается свободно:
    // в альбоме у телефона остаётся ~390 px высоты, и широкая вёрстка
    // (сайдбар с логотипом и QR) туда не помещается.
    final isTablet = Responsive.isTablet(MediaQuery.of(context).size);
    SystemChrome.setPreferredOrientations(
      isTablet
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : DeviceOrientation.values,
    );
  }

  @override
  void dispose() {
    currentLocale.removeListener(_rebuildOnLocaleChange);
    currentBranch.removeListener(_onBranchChanged);
    menuStore.data.removeListener(_applyMenu);
    menuStore.refreshing.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuildOnLocaleChange() => _rebuild();

  void _rebuild() {
    if (mounted && _initialized) setState(() {});
  }

  /// Филиал меняется, когда его переключили в админке. Меню нужно
  /// перезагрузить целиком: у другого филиала другие категории.
  void _onBranchChanged() {
    final branch = currentBranch.value;
    if (branch != null && branch.slug != menuStore.slug) {
      menuStore.open(branch.slug);
    }
    _rebuild();
  }

  /// Категории верхнего уровня из текущего меню — свежего или сохранённого.
  void _applyMenu() {
    final items = menuStore.data.value?.items ?? const <Product>[];
    final allGroupIds = items.where((p) => p.isGroup).map((e) => e.id).toSet();
    // Список пересобирается с нуля, а не дополняется: при смене
    // филиала иначе остались бы категории прежнего.
    rootCategories = items.where((p) {
      if (!p.isGroup) return false;
      return p.parentId.isEmpty || !allGroupIds.contains(p.parentId);
    }).toList()
      ..sort(compareByOrder);
    _rebuild();
  }

  /// Кнопка «Обновить»: один раз берёт свежее меню с сервера.
  Future<void> _refreshMenu() async {
    HapticFeedback.selectionClick();
    final result = await menuStore.refresh();
    switch (result) {
      case MenuResult.fresh:
        _showToast('Меню обновлено');
      case MenuResult.offline:
        _showToast('Нет связи, показано сохранённое меню', isError: true);
      case MenuResult.offlineNoCache:
        _showToast('Нет связи с сервером', isError: true);
      case MenuResult.notFound:
      case MenuResult.unpaid:
        break; // main.dart сам покажет выбор филиала или «Меню недоступно»
    }
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        width: 400,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _goToMenu(String categoryId) async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);
    HapticFeedback.selectionClick();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MenuScreen(initialCategoryId: categoryId),
      ),
    );

    if (mounted) setState(() => _isNavigating = false);
  }

  /// Вход в админку.
  ///
  /// Логин и пароль выдаёт главный администратор платформы. Пароль
  /// спрашивается при каждом входе: планшет стоит в зале, и сохранённая
  /// сессия означала бы, что админку откроет любой, кто до него дотянулся.
  /// Поэтому токен живёт только в памяти и сбрасывается сразу после
  /// выхода из админки.
  Future<void> _openAdmin() async {
    final me = await showAdminLogin(context);
    if (me != null && mounted) _pushAdmin();
  }

  Future<void> _pushAdmin() async {
    // Планшет мог показывать филиал другого кафе: тогда админка открылась
    // бы на чужом меню, и сервер отказал бы в каждом запросе. Переводим
    // на первый филиал своего кафе.
    final List<Branch> own;
    try {
      own = await _db.getBranches();
    } catch (e) {
      // Без списка своих филиалов нельзя проверить, что админка откроется
      // на своём, а не на чужом меню
      await api.logout();
      _showToast('$e', isError: true);
      return;
    }
    if (!mounted) return;
    if (own.isNotEmpty && !own.any((b) => b.id == currentBranch.value?.id)) {
      await saveBranchSlug(own.first.slug);
      currentBranch.value = own.first;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminShell()),
    );

    await api.logout();
    // Блюда, добавленные в админке, сразу видны гостю
    if (mounted) menuStore.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeConfig>(
      valueListenable: appTheme,
      builder: (context, config, child) {

        return Scaffold(
          backgroundColor: config.bg,
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              Positioned.fill(child: ThemeBackground(config: config)),

              LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = Responsive.isWideConstraints(constraints);

                  if (isDesktop) {
                    return Row(
                      children: [
                        Expanded(flex: 3, child: _buildSidebar(config)),
                        Expanded(
                          flex: 7,
                          child: _buildMainContent(config, isDesktop: true),
                        ),
                      ],
                    );
                  } else {
                    return CustomScrollView(
                      physics: const BouncingScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(child: _buildMobileHeader(config)),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 20,
                          ),
                          sliver: _buildMainContentSliver(config),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 50)),
                      ],
                    );
                  }
                },
              ),

            ],
          ),
        );
      },
    );
  }

  Widget _searchButton(ThemeConfig config) {
    return IconButton(
      tooltip: AppLocalizations.of(context).search,
      onPressed: isLoading ? null : _openSearch,
      icon: Icon(Icons.search_rounded, color: config.accent),
    );
  }

  void _openSearch() {
    HapticFeedback.selectionClick();
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
  }

  /// Сколько категорий в ряд — по размеру карточек, выбранному кафе
  int _categoryColumns(ThemeConfig config, {required bool desktop}) {
    final columns = desktop ? 3 : 2;
    if (config.gridScale < 1) return columns + 1; // мелкие
    if (config.gridScale > 1) return columns - 1; // крупные
    return columns;
  }

  Widget _refreshButton(ThemeConfig config) {
    final busy = menuStore.refreshing.value;
    return IconButton(
      tooltip: 'Обновить меню',
      onPressed: busy ? null : _refreshMenu,
      // Значок и индикатор сменяют друг друга плавно, без «мигания»
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: Tween(begin: 0.6, end: 1.0).animate(anim), child: child),
        ),
        child: busy
            ? SizedBox(
                key: const ValueKey('busy'),
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: config.accent),
              )
            : Icon(
                Icons.refresh_rounded,
                key: const ValueKey('idle'),
                color: config.text.withValues(alpha: 0.5),
              ),
      ),
    );
  }

  /// Показано сохранённое меню — гость и персонал видят, от какого оно числа.
  Widget _offlineNote(ThemeConfig config) {
    final menu = menuStore.data.value;
    if (menu == null || !menu.fromCache) return const SizedBox.shrink();
    final t = menu.savedAt;
    String two(int n) => n.toString().padLeft(2, '0');
    final when = '${two(t.day)}.${two(t.month)}, ${two(t.hour)}:${two(t.minute)}';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 14, color: Colors.orangeAccent.withValues(alpha: 0.9)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Нет связи — меню от $when',
              style: GoogleFonts.manrope(fontSize: 12, color: Colors.orangeAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(ThemeConfig config) {
    return Container(
      decoration: BoxDecoration(
        color: config.glass,
        border: Border(
          right: BorderSide(
            color: config.text.withValues(alpha: 0.05),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(5, 0),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: config.surface,
              boxShadow: [
                BoxShadow(
                  color: config.accent.withValues(alpha: 0.2),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: GestureDetector(
              onLongPress: _openAdmin,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: AuthImage(
                  url: shopLogoUrl,
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),

          const SizedBox(height: 30),

          Text(
            shopName,
            textAlign: TextAlign.center,
            style: config.titleStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: config.text,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),

          Text(
            shopSlogan.toUpperCase(),
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 14,
              letterSpacing: 3,
              fontWeight: FontWeight.w600,
              color: config.accent,
            ),
          ),

          const SizedBox(height: 20),
          // Wrap, а не Row: в узкой боковой панели кнопки переносятся на
          // вторую строку, а не вылезают за край
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              LangSwitcher(config: config),
              _searchButton(config),
              _refreshButton(config),
            ],
          ),
          _offlineNote(config),

          const Spacer(),

          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: config.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: shopQrUrl.isEmpty
                      ? const SizedBox(
                          width: 124,
                          height: 124,
                          child: Icon(Icons.qr_code_2, size: 60, color: Colors.black26),
                        )
                      : QrImageView(
                          data: shopQrUrl,
                          version: QrVersions.auto,
                          size: 124,
                          padding: EdgeInsets.zero,
                          backgroundColor: Colors.white,
                        ),
                ),
                const SizedBox(height: 15),
                Text(
                  AppLocalizations.of(context).menuInPhone,
                  style: GoogleFonts.manrope(
                    color: config.text.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileHeader(ThemeConfig config) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 60, bottom: 20, left: 20, right: 20),
      decoration: BoxDecoration(
        color: config.glass,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shopName,
                      style: config.titleStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: config.text,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      shopSlogan.toUpperCase(),
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600,
                        color: config.accent,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: config.surface,
                ),
                // Долгий тап по логотипу открывает админку — как и в широкой
                // вёрстке. Раньше в мобильной ветке этого не было: телефон
                // принудительно разворачивался в альбом и всегда попадал
                // в широкую, поэтому пропажу никто не замечал.
                child: GestureDetector(
                  onLongPress: _openAdmin,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(100),
                    child: AuthImage(
                      url: shopLogoUrl,
                      width: 55,
                      height: 55,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              LangSwitcher(config: config),
              const SizedBox(width: 8),
              _searchButton(config),
              _refreshButton(config),
            ],
          ),
          _offlineNote(config),
        ],
      ),
    );
  }

  Widget _buildMainContent(ThemeConfig config, {bool isDesktop = true}) {
    return Container(
      padding: isDesktop
          ? const EdgeInsets.fromLTRB(40, 50, 40, 40)
          : EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 5,
                height: 35,
                decoration: BoxDecoration(
                  color: config.accent,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              const SizedBox(width: 15),
              Text(
                AppLocalizations.of(context).catalog,
                style: config.titleStyle(
                  fontSize: 32,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w800,
                  color: config.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Expanded(
            child: isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: config.accent,
                      strokeWidth: 3,
                    ),
                  )
                : GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _categoryColumns(config, desktop: true),
                      childAspectRatio: 0.85,
                      crossAxisSpacing: isDesktop ? 25 : 15,
                      mainAxisSpacing: isDesktop ? 25 : 15,
                    ),
                    itemCount: rootCategories.length,
                    itemBuilder: (context, index) {
                      final cat = rootCategories[index];
                      return FadeSlideIn(
                        key: ValueKey(cat.id),
                        index: index,
                        child: _CategoryCard(
                          category: cat,
                          config: config,
                          onTap: () => _goToMenu(cat.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContentSliver(ThemeConfig config) {
    if (isLoading) {
      return SliverFillRemaining(
        child: Center(
          child: CircularProgressIndicator(
            color: config.accent,
            strokeWidth: 3,
          ),
        ),
      );
    }
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _categoryColumns(config, desktop: false),
        childAspectRatio: 0.85,
        crossAxisSpacing: 15,
        mainAxisSpacing: 15,
      ),
      delegate: SliverChildBuilderDelegate((context, index) {
        final cat = rootCategories[index];
        return FadeSlideIn(
          key: ValueKey(cat.id),
          index: index,
          child: _CategoryCard(
            category: cat,
            config: config,
            onTap: () => _goToMenu(cat.id),
          ),
        );
      }, childCount: rootCategories.length),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final Product category;
  final ThemeConfig config;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.category,
    required this.config,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Hero(
        tag: 'category_${category.id}',
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(config.radius(30)),
            color: config.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 25,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          // Тонкая светлая кромка: тёмное фото не сливается с тёмным фоном
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(config.radius(30)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(config.radius(30)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                AuthImage(url: category.imageUrl, fit: BoxFit.cover),

                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.1),
                        Colors.black.withValues(alpha: 0.85),
                      ],
                      stops: const [0.3, 0.6, 1.0],
                    ),
                  ),
                ),

                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(height: 4, color: config.accent),
                ),

                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(25.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ValueListenableBuilder<Locale>(
                          valueListenable: currentLocale,
                          builder: (_, locale, __) {
                            return Text(
                              category.localizedName(locale.languageCode).toUpperCase(),
                              textAlign: TextAlign.center,
                              // длинное название не вылезает за карточку
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: config.titleStyle(
                                // в мелких карточках и шрифт мельче
                                fontSize: 22 * config.gridScale.clamp(0.8, 1.15),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: Colors.white,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: config.accent.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Builder(
                            builder: (ctx) => Text(
                              AppLocalizations.of(ctx).open,
                              style: GoogleFonts.manrope(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: config.onAccent,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
