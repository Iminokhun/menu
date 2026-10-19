import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../menu_store.dart';
import '../models/product.dart';
import '../theme/theme_config.dart';
import '../theme/current_theme.dart';
import '../widgets/motion.dart';
import '../widgets/theme_background.dart';
import '../widgets/product_card.dart';
import 'search_screen.dart';
import '../l10n/app_localizations.dart';
import '../l10n/translation_service.dart';
import '../widgets/lang_switcher.dart';
import '../responsive.dart';

class MenuScreen extends StatefulWidget {
  final String? initialCategoryId;
  const MenuScreen({super.key, this.initialCategoryId});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  // --- Данные ---
  List<Product> allProducts = [];
  List<Product> rootCategories = [];
  List<Product> visibleSubCategories = [];
  List<Product> currentGrid = [];

  // --- Состояние выбора ---
  String selectedRootId = "";
  String selectedSubId = "";

  @override
  void initState() {
    super.initState();
    currentLocale.addListener(_rebuildOnLocaleChange);
    // Меню уже загружено главным экраном — второй запрос к серверу не нужен.
    // После «Обновить» список здесь тоже меняется.
    menuStore.data.addListener(_loadLocalData);
    _loadLocalData();
  }

  @override
  void dispose() {
    currentLocale.removeListener(_rebuildOnLocaleChange);
    menuStore.data.removeListener(_loadLocalData);
    super.dispose();
  }

  void _rebuildOnLocaleChange() {
    if (mounted) setState(() {});
  }

  String _t(Product p) => p.localizedName(currentLocale.value.languageCode);

  void _loadLocalData() {
    final items = menuStore.data.value?.items;
    if (items != null && items.isNotEmpty) _applyData(List.of(items));
  }

  void _applyData(List<Product> data) {
    if (!mounted) return;
    setState(() {
      data.sort(compareByOrder);
      allProducts = data;

      final allGroupIds = data.where((p) => p.isGroup).map((e) => e.id).toSet();

      rootCategories = data.where((p) {
        if (!p.isGroup) return false;
        return p.parentId.isEmpty || !allGroupIds.contains(p.parentId);
      }).toList();

      rootCategories.sort(compareByOrder);

      // После обновления меню гость остаётся в той категории, где был.
      // Если её убрали — переходим на первую.
      final stillThere = rootCategories.any((c) => c.id == selectedRootId);
      if (!stillThere) {
        final initial = widget.initialCategoryId;
        selectedRootId = selectedRootId.isEmpty &&
                initial != null &&
                rootCategories.any((c) => c.id == initial)
            ? initial
            : (rootCategories.isNotEmpty ? rootCategories[0].id : '');
      }

      _onRootSelected(selectedRootId);
    });
  }

  void _onRootSelected(String rootId) {
    setState(() {
      selectedRootId = rootId;

      visibleSubCategories = allProducts
          .where((p) => p.isGroup && p.parentId == rootId)
          .toList();
      visibleSubCategories.sort(compareByOrder);

      selectedSubId = "";

      _updateGrid();
    });
  }

  void _onSubSelected(String subId) {
    setState(() {
      selectedSubId = subId;
      _updateGrid();
    });
  }

  void _updateGrid() {
    if (allProducts.isEmpty) return;

    setState(() {
      if (selectedSubId.isEmpty) {
        final subIds = visibleSubCategories.map((e) => e.id).toSet();
        currentGrid = allProducts.where((p) {
          if (p.isGroup) return false;
          return p.parentId == selectedRootId || subIds.contains(p.parentId);
        }).toList();
      } else {
        currentGrid = allProducts
            .where((p) => !p.isGroup && p.parentId == selectedSubId)
            .toList();
      }
    });
  }


  void _openSearch() {
    HapticFeedback.selectionClick();
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
  }

  void _openCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _CartSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeConfig>(
      valueListenable: appTheme,
      builder: (context, config, child) {

        return Scaffold(
          backgroundColor: config.bg,

          // === ПЛАВАЮЩАЯ КНОПКА КОРЗИНЫ ===
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
          floatingActionButton: ValueListenableBuilder<List<CartItem>>(
            valueListenable: globalCart,
            builder: (context, cartItems, child) {
              if (cartItems.isEmpty) return const SizedBox.shrink();

              double total = cartItems.fold(
                0,
                (sum, item) => sum + (item.price * item.quantity),
              );
              int count = cartItems.fold(0, (sum, item) => sum + item.quantity);

              return FloatingActionButton.extended(
                heroTag: 'fab_cart',
                onPressed: _openCart,
                backgroundColor: config.accent,
                foregroundColor: config.onAccent,
                elevation: 10,
                icon: const Icon(Icons.shopping_basket),
                label: Builder(builder: (ctx) {
                  final l = AppLocalizations.of(ctx);
                  return Row(
                    children: [
                      Text(
                        "$count ${l.pcs} | ",
                        style: const TextStyle(
                          fontWeight: FontWeight.normal,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        "${total.toInt()} ${l.som}",
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  );
                }),
              );
            },
          ),

          body: Stack(
            children: [
              // Фоновое изображение темы (если есть) или просто цвет
              Positioned.fill(child: ThemeBackground(config: config)),

              LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = Responsive.isWideConstraints(constraints);
                  
                  if (isDesktop) {
                    return Row(
                      children: [
                        // ЛЕВАЯ ПАНЕЛЬ (1 УРОВЕНЬ)
                        _buildSidebar(config),

                        // ПРАВАЯ ЧАСТЬ (КОНТЕНТ)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildDesktopHeader(config),
                              if (visibleSubCategories.isNotEmpty)
                                _buildSubCategories(config, isDesktop: true),
                              Expanded(
                                child: _buildProductsGrid(config, isDesktop: true),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        _buildMobileHeader(config),
                        _buildRootCategoriesMobile(config),
                        if (visibleSubCategories.isNotEmpty)
                          _buildSubCategories(config, isDesktop: false),
                        Expanded(
                          child: _buildProductsGrid(config, isDesktop: false),
                        ),
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

  Widget _buildSidebar(ThemeConfig config) {
    return Container(
      width: 110,
      decoration: BoxDecoration(
        color: config.glass,
        border: Border(
          right: BorderSide(
            color: config.text.withValues(alpha: 0.05),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            IconButton(
              icon: Icon(
                Icons.home_rounded,
                color: config.accent,
                size: 36,
              ),
              onPressed: () => Navigator.pop(context),
              tooltip: "На главную",
            ),
            const SizedBox(height: 10),
            IconButton(
              icon: Icon(Icons.search_rounded, color: config.accent, size: 32),
              onPressed: _openSearch,
              tooltip: AppLocalizations.of(context).search,
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: rootCategories.length,
                separatorBuilder: (context, index) => const SizedBox(height: 15),
                itemBuilder: (ctx, i) {
                  final cat = rootCategories[i];
                  final isActive = cat.id == selectedRootId;
                  return _buildSidebarItem(cat, isActive, config);
                },
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(Product cat, bool isActive, ThemeConfig config) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _onRootSelected(cat.id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 8,
        ),
        decoration: BoxDecoration(
          color: isActive ? config.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          border: isActive
              ? null
              : Border.all(
                  color: config.text.withValues(alpha: 0.1),
                ),
        ),
        child: Text(
          _t(cat),
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.black : config.text,
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopHeader(ThemeConfig config) {
    final l = AppLocalizations.of(context);
    final cat = rootCategories.isNotEmpty
        ? rootCategories.firstWhere((c) => c.id == selectedRootId,
            orElse: () => Product(id: '', parentId: '', name: ''))
        : null;
    final title = cat != null ? _t(cat).toUpperCase() : l.menuLoading;

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 50, 40, 20),
      child: Row(
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
          Expanded(
            child: Text(
              title,
              style: config.titleStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: config.text,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          LangSwitcher(config: config),
        ],
      ),
    );
  }

  Widget _buildMobileHeader(ThemeConfig config) {
    final l = AppLocalizations.of(context);
    final cat = rootCategories.isNotEmpty
        ? rootCategories.firstWhere((c) => c.id == selectedRootId,
            orElse: () => Product(id: '', parentId: '', name: ''))
        : null;
    final title = cat != null ? _t(cat).toUpperCase() : l.menuLoading;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: config.accent, size: 24),
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                 title,
                style: config.titleStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: config.text,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: l.search,
              icon: Icon(Icons.search_rounded, color: config.accent, size: 26),
              onPressed: _openSearch,
            ),
            LangSwitcher(config: config),
          ],
        ),
      ),
    );
  }

  Widget _buildRootCategoriesMobile(ThemeConfig config) {
    if (rootCategories.isEmpty) return const SizedBox();
    return Container(
      height: 45,
      margin: const EdgeInsets.only(bottom: 15),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: rootCategories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (ctx, i) {
          final cat = rootCategories[i];
          final isActive = cat.id == selectedRootId;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _onRootSelected(cat.id);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive ? config.accent : config.glass,
                borderRadius: BorderRadius.circular(20),
                border: isActive ? null : Border.all(color: config.text.withValues(alpha: 0.1)),
              ),
              child: Text(
                _t(cat).toUpperCase(),
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isActive ? Colors.black : config.text,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSubCategories(ThemeConfig config, {bool isDesktop = true}) {
    final l = AppLocalizations.of(context);
    return Container(
      height: 45,
      margin: EdgeInsets.only(bottom: isDesktop ? 20 : 10),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: isDesktop ? 40 : 20),
        children: [
          _SubCategoryChip(
            name: l.all,
            isActive: selectedSubId == "",
            config: config,
            onTap: () => _onSubSelected(""),
          ),
          const SizedBox(width: 10),
          ...visibleSubCategories.map(
            (cat) => Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _SubCategoryChip(
                name: _t(cat),
                isActive: selectedSubId == cat.id,
                config: config,
                onTap: () => _onSubSelected(cat.id),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsGrid(ThemeConfig config, {required bool isDesktop}) {
    if (currentGrid.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).emptyCategory,
          style: TextStyle(color: config.text.withValues(alpha: 0.5), fontSize: 16),
        ),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 40 : 20,
        10,
        isDesktop ? 40 : 20,
        100, // padding for floating action button
      ),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: (isDesktop ? 260 : 300) * config.gridScale,
        childAspectRatio: isDesktop ? 0.65 : 0.7,
        crossAxisSpacing: isDesktop ? 25 : 15,
        mainAxisSpacing: isDesktop ? 25 : 15,
      ),
      physics: const BouncingScrollPhysics(),
      itemCount: currentGrid.length,
      itemBuilder: (ctx, i) => FadeSlideIn(
        key: ValueKey(currentGrid[i].id),
        index: i,
        child: LuxuryCard(
          product: currentGrid[i],
          config: config,
          onAdd: addToCart,
        ),
      ),
    );
  }
}

class _SubCategoryChip extends StatelessWidget {
  final String name;
  final bool isActive;
  final ThemeConfig config;
  final VoidCallback onTap;

  const _SubCategoryChip({
    required this.name,
    required this.isActive,
    required this.config,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? config.accent : config.glass,
          borderRadius: BorderRadius.circular(25),
          border: isActive
              ? null
              : Border.all(color: config.text.withValues(alpha: 0.2)),
        ),
        child: Text(
          name.toUpperCase(),
          style: GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.black : config.text,
          ),
        ),
      ),
    );
  }
}

// === ШТОРКА КОРЗИНЫ ===
class _CartSheet extends StatelessWidget {
  const _CartSheet();

  void _removeFromCart(CartItem item) {
    final current = globalCart.value;
    current.remove(item);
    globalCart.value = List.from(current);
  }

  void _clearCart() {
    globalCart.value = [];
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: currentLocale,
      builder: (context, locale, child) {
    final config = appTheme.value;
    final l = AppLocalizations.of(context);

    return ValueListenableBuilder<List<CartItem>>(
      valueListenable: globalCart,
      builder: (context, cart, child) {
        double total = cart.fold(
          0,
          (sum, item) => sum + (item.price * item.quantity),
        );

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                color: config.surface.withValues(alpha: 0.95),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
                border: Border.all(color: config.accent.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(25),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l.yourOrder,
                          style: GoogleFonts.cormorantGaramond(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: config.accent,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(
                            Icons.keyboard_arrow_down,
                            size: 36,
                            color: config.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: cart.isEmpty
                        ? Center(
                            child: Text(
                              l.cartEmpty,
                              style: TextStyle(
                                color: config.text.withValues(alpha: 0.5),
                                fontSize: 18,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(20),
                            itemCount: cart.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 15),
                            itemBuilder: (ctx, i) {
                              final item = cart[i];
                              return Dismissible(
                                key: UniqueKey(),
                                direction: DismissDirection.endToStart,
                                onDismissed: (_) => _removeFromCart(item),
                                background: Container(
                                  color: Colors.red,
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  child: const Icon(
                                    Icons.delete,
                                    color: Colors.white,
                                  ),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(15),
                                  decoration: BoxDecoration(
                                    color: config.bg.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(
                                      color: config.text.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 35,
                                        height: 35,
                                        decoration: BoxDecoration(
                                          color: config.accent,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          "${item.quantity}x",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: config.onAccent,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 15),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.product.localizedName(locale.languageCode),
                                              style: GoogleFonts.manrope(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: config.text,
                                              ),
                                            ),
                                            if (item.portion != null)
                                              Text(
                                                item.portion!.name,
                                                style: TextStyle(
                                                  color: config.text.withValues(
                                                    alpha: 0.5,
                                                  ),
                                                  fontSize: 13,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        "${(item.price * item.quantity).toInt()} ${l.som}",
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: config.text,
                                          fontFeatures: const [FontFeature.tabularFigures()],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                          color: Colors.redAccent,
                                        ),
                                        onPressed: () => _removeFromCart(item),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  if (cart.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: config.bg,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(30),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, -5),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                l.total,
                                style: TextStyle(
                                  color: config.text.withValues(alpha: 0.6),
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                "${total.toInt()} ${l.som}",
                                style: GoogleFonts.manrope(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  color: config.accent,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 60,
                            child: ElevatedButton(
                              onPressed: null, // НЕАКТИВНАЯ КНОПКА
                              style: ElevatedButton.styleFrom(
                                backgroundColor: config.accent,
                                disabledBackgroundColor: config.text.withValues(
                                  alpha: 0.2,
                                ),
                                disabledForegroundColor: config.text.withValues(
                                  alpha: 0.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              child: Text(
                                l.placeOrder,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: _clearCart,
                            child: Text(
                              l.clearCart,
                              style: TextStyle(
                                color: config.text.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
      }, // ValueListenableBuilder<Locale>
    );
  }
}
