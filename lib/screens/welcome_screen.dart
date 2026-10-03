import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../widgets/auth_image.dart';
import '../database.dart';
import '../models/product.dart';
import '../theme/theme_config.dart';
import '../theme/current_theme.dart';
import '../l10n/app_localizations.dart';
import '../l10n/translation_service.dart';
import '../widgets/lang_switcher.dart';
import '../responsive.dart';
import 'menu_screen.dart';
import 'admin/admin_shell.dart';
// ignore: unused_import
import 'about_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final DatabaseService _db = DatabaseService();

  List<Product> rootCategories = [];

  bool isLoading = true;
  bool _isRebooting = false;
  bool _isNavigating = false;

  String shopLogoUrl = '';
  String shopQrUrl = '';
  String shopName = '';
  String shopSlogan = '';
  String shopPhone = '';

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    currentLocale.addListener(_rebuildOnLocaleChange);
    _loadFromSupabase();
  }

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
    super.dispose();
  }

  void _rebuildOnLocaleChange() {
    if (mounted) setState(() {});
  }

  Future<void> _loadFromSupabase() async {
    setState(() => isLoading = true);
    try {
      final info = await _db.getShopInfo();
      final products = await _db.getAllProducts();

      if (mounted) {
        setState(() {
          shopLogoUrl = info['logo_url'] ?? '';
          shopQrUrl = info['qr_url'] ?? '';
          shopName = (info['name']?.isEmpty ?? true) ? 'CAFE ANDALUS' : info['name']!;
          shopSlogan = (info['slogan']?.isEmpty ?? true) ? 'Добро пожаловать' : info['slogan']!;
          shopPhone = info['phone'] ?? '';

          if (products.isNotEmpty) {
            final allGroupIds = products.where((p) => p.isGroup).map((e) => e.id).toSet();
            rootCategories = products.where((p) {
              if (!p.isGroup) return false;
              return p.parentId.isEmpty || !allGroupIds.contains(p.parentId);
            }).toList();
            rootCategories.sort(compareByOrder);
          }
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        _showToast('Ошибка загрузки: $e', isError: true);
      }
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

  void _showAdminPin() {
    final pinCtrl = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          void tryEnter() {
            if (pinCtrl.text.trim() == '200229') {
              Navigator.pop(ctx);
              if (!mounted) return;
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminShell()))
                  .then((_) => _loadFromSupabase());
            } else {
              setS(() => errorText = 'Неверный PIN-код');
            }
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.admin_panel_settings, color: Color(0xFFD4AF37), size: 20),
                SizedBox(width: 8),
                Text('Режим администратора', style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: pinCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
                    textAlign: TextAlign.center,
                    onChanged: (_) {
                      if (errorText != null) setS(() => errorText = null);
                    },
                    onSubmitted: (_) => tryEnter(),
                    decoration: const InputDecoration(
                      hintText: '• • • • • •',
                      hintStyle: TextStyle(color: Colors.white24),
                      counterText: '',
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFD4AF37))),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          errorText!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
                onPressed: tryEnter,
                child: const Text('Войти', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _changeTheme(AppThemeType type) async {
    Navigator.pop(context);
    setState(() => _isRebooting = true);
    await Future.delayed(const Duration(milliseconds: 300));
    currentTheme.value = type;
    await Future.delayed(const Duration(milliseconds: 1000));
    if (mounted) setState(() => _isRebooting = false);
  }

  void _showThemePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(30),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Wrap(
            spacing: 15,
            runSpacing: 15,
            alignment: WrapAlignment.center,
            children: AppThemeType.values
                .where((t) => t != AppThemeType.highContrast)
                .map((type) {
                  final theme = ThemeConfig.palettes[type]!;
                  return ChoiceChip(
                    label: Text(theme.name),
                    selected: currentTheme.value == type,
                    onSelected: (v) => _changeTheme(type),
                    selectedColor: theme.accent,
                    backgroundColor: Colors.grey,
                    labelStyle: TextStyle(
                      color: currentTheme.value == type ? Colors.black : Colors.grey,
                    ),
                  );
                })
                .toList(),
          ),
        );
      },
    );
  }

  Widget _buildLoadingOverlay() {
    if (!_isRebooting) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 20),
            Text(
              l.applyingTheme,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeType>(
      valueListenable: currentTheme,
      builder: (context, themeType, child) {
        final config = ThemeConfig.palettes[themeType]!;

        return Scaffold(
          backgroundColor: config.bg,
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              if (config.bgImage.isNotEmpty)
                Positioned.fill(
                  child: Image.network(
                    config.bgImage,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(),
                  ),
                ),
              Positioned.fill(child: Container(color: config.bgOverlay)),

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
                        SliverToBoxAdapter(child: const SizedBox(height: 50)),
                      ],
                    );
                  }
                },
              ),

              _buildLoadingOverlay(),
            ],
          ),
        );
      },
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
              onLongPress: _showAdminPin,
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

          GestureDetector(
            onLongPress: _showThemePicker,
            child: Text(
              shopName,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: config.text,
                height: 1.1,
              ),
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
          LangSwitcher(config: config),

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
                    GestureDetector(
                      onLongPress: _showThemePicker,
                      child: Text(
                        shopName,
                        style: GoogleFonts.outfit(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: config.text,
                          height: 1.1,
                        ),
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
                  onLongPress: _showAdminPin,
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
            ],
          ),
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
                style: GoogleFonts.outfit(
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
                      crossAxisCount: isDesktop ? 3 : 2,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: isDesktop ? 25 : 15,
                      mainAxisSpacing: isDesktop ? 25 : 15,
                    ),
                    itemCount: rootCategories.length,
                    itemBuilder: (context, index) {
                      final cat = rootCategories[index];
                      return _CategoryCard(
                        category: cat,
                        config: config,
                        onTap: () => _goToMenu(cat.id),
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
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 15,
        mainAxisSpacing: 15,
      ),
      delegate: SliverChildBuilderDelegate((context, index) {
        final cat = rootCategories[index];
        return _CategoryCard(
          category: cat,
          config: config,
          onTap: () => _goToMenu(cat.id),
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
    return GestureDetector(
      onTap: onTap,
      child: Hero(
        tag: 'category_${category.id}',
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            color: config.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 25,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
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
                              style: GoogleFonts.outfit(
                                fontSize: 22,
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
                                color: config.bg,
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
