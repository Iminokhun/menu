import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'auth_image.dart';
import 'dish_3d_view.dart';
import 'motion.dart';
import 'live_photo/live_photo_view.dart';
import '../responsive.dart';
import '../models/product.dart';
import '../theme/theme_config.dart';
import '../l10n/app_localizations.dart';
import '../l10n/translation_service.dart';

class LuxuryCard extends StatelessWidget {
  final Product product;
  final ThemeConfig config;
  final Function(Product, Portion?, int) onAdd;

  const LuxuryCard({
    super.key,
    required this.product,
    required this.config,
    required this.onAdd,
  });

  void _showDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) =>
          _ProductDetailDialog(product: product, config: config, onAdd: onAdd),
    );
  }

  int _getProductCountInCart(List<CartItem> cartList) {
    int count = 0;
    for (var item in cartList) {
      if (item.product.id == product.id) count += item.quantity;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final bool isAcc = config.isHighContrast;
    final imageBgColor = config.brightness == Brightness.dark
        ? Colors.black.withValues(alpha: isAcc ? 1.0 : 0.3)
        : config.accent.withValues(alpha: 0.05);

    return Pressable(
      onTap: () {
        HapticFeedback.selectionClick();
        _showDetails(context);
      },
      child: Container(
        decoration: BoxDecoration(
          color: config.glass,
          // 18 = радиус фото (12) + отступ до него (6): углы карточки и
          // фото идут параллельно, а не «разъезжаются»
          borderRadius: BorderRadius.circular(config.radius(18)),
          border: Border.all(
            color: isAcc ? config.accent : Colors.white.withValues(alpha: 0.08),
            width: isAcc ? 2 : 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 4,
              child: Stack(
                children: [
                  Container(
                    margin: const EdgeInsets.all(6),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: imageBgColor,
                      borderRadius: BorderRadius.circular(config.radius(12)),
                    ),
                    // Тонкая светлая кромка: край фото не растворяется в фоне
                    foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(config.radius(12)),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(config.radius(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Hero(
                          tag: product.id,
                          child: AuthImage(
                            url: product.imageUrl,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // У блюда есть 3D-модель — видно ещё в списке
                  if (product.modelUrl.isNotEmpty)
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.view_in_ar, size: 13, color: config.accent),
                            const SizedBox(width: 3),
                            Text('3D',
                                style: GoogleFonts.manrope(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ValueListenableBuilder<List<CartItem>>(
                    valueListenable: globalCart,
                    builder: (context, cartItems, child) {
                      final count = _getProductCountInCart(cartItems);
                      if (count == 0) return const SizedBox.shrink();
                      return Positioned(
                        right: 10,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: config.accent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 4),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.shopping_basket,
                                size: 14,
                                color: config.onAccent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "$count",
                                style: TextStyle(
                                  color: config.onAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValueListenableBuilder<Locale>(
                      valueListenable: currentLocale,
                      builder: (_, locale, __) => Text(
                        product.localizedName(locale.languageCode),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        // Контрастная тема — простой рубленый шрифт для
                        // тех, кто плохо видит; иначе — шрифт, выбранный кафе
                        style: isAcc
                            ? GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: config.accent,
                                height: 1.1,
                              )
                            : config.dishTitleStyle(
                                fontSize: 18 * config.gridScale.clamp(0.85, 1.15),
                                fontWeight: FontWeight.bold,
                                color: config.accent,
                                height: 1.1,
                              ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Builder(
                          builder: (ctx) => Text(
                            "${product.price.toInt()} ${AppLocalizations.of(ctx).som}",
                            style: GoogleFonts.manrope(
                              fontSize: isAcc ? 24 : 20,
                              fontWeight: FontWeight.w900,
                              color: isAcc ? config.accent : config.text,
                              // цифры одной ширины: цены в соседних карточках
                              // стоят ровно и не «прыгают»
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        // Видимый кружок 30 px, а нажимать можно по
                        // квадрату 44 px — по маленькому кружку пальцем
                        // промахиваются и открывают карточку вместо «+»
                        Pressable(
                          pressedScale: 0.85,
                          onTap: () => onAdd(product, null, 1),
                          child: Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.centerRight,
                            child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: config.surface,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: config.accent.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Icon(
                              Icons.add,
                              size: 18,
                              color: config.accent,
                            ),
                          ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Диалог товара
class _ProductDetailDialog extends StatefulWidget {
  final Product product;
  final ThemeConfig config;
  final Function(Product, Portion?, int) onAdd;
  const _ProductDetailDialog({
    required this.product,
    required this.config,
    required this.onAdd,
  });
  @override
  State<_ProductDetailDialog> createState() => _ProductDetailDialogState();
}

class _ProductDetailDialogState extends State<_ProductDetailDialog> {
  Portion? selectedPortion;
  int quantity = 1;

  @override
  void initState() {
    super.initState();
    if (widget.product.portions.isNotEmpty) {
      selectedPortion = widget.product.portions.first;
    }
  }

  double get currentPrice => selectedPortion?.price ?? widget.product.price;
  double get totalPrice => currentPrice * quantity;
  void _increment() => setState(() => quantity++);
  void _decrement() {
    if (quantity > 1) setState(() => quantity--);
  }

  @override
  Widget build(BuildContext context) {
    final conf = widget.config;
    final screen = MediaQuery.of(context).size;
    final isMobile = !Responsive.isWide(screen);
    final inset = isMobile ? 15.0 : 20.0;

    // Размеры — желаемые, но не больше того, что реально есть на экране:
    // иначе на невысоких экранах содержимое диалога не помещается.
    final dialogWidth = math.min(700.0, screen.width - inset * 2);
    final dialogHeight =
        math.min(isMobile ? 600.0 : 550.0, screen.height - inset * 2);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(inset),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: conf.surface,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: conf.accent.withValues(alpha: 0.5)),
        ),
        child: isMobile
            ? _buildMobileLayout(conf)
            : _buildDesktopLayout(conf),
      ),
    );
  }

  /// Кнопки поверх фото: «Смотреть в 3D» — у блюд с 3D-моделью,
  /// «Живое фото» — у любого блюда с фото.
  Widget _withViewButtons(Widget image) {
    final product = widget.product;
    final has3D = product.modelUrl.isNotEmpty;
    final hasPhoto = product.imageUrl.isNotEmpty;
    if (!has3D && !hasPhoto) return image;
    final conf = widget.config;
    final title = product.localizedName(currentLocale.value.languageCode);

    void open(Widget page) {
      HapticFeedback.selectionClick();
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    }

    Widget button(IconData icon, String label, VoidCallback onPressed) => ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label, style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: conf.accent,
            foregroundColor: conf.onAccent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        );

    return Stack(
      children: [
        Positioned.fill(child: image),
        Positioned(
          left: 8,
          right: 8,
          bottom: 14,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              if (has3D)
                button(Icons.view_in_ar, 'Смотреть в 3D',
                    () => open(Dish3DView(product: product, title: title, config: conf))),
              if (hasPhoto)
                button(Icons.motion_photos_on_outlined, 'Живое фото',
                    () => open(LivePhotoView(product: product, title: title, config: conf))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImageSection() {
    return _withViewButtons(Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(25),
          topRight: Radius.circular(25),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Hero(
          tag: widget.product.id,
          child: AuthImage(url: widget.product.imageUrl, fit: BoxFit.contain),
        ),
      ),
    ));
  }

  Widget _buildDesktopImageSection() {
    return _withViewButtons(Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(25),
          bottomLeft: Radius.circular(25),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Hero(
          tag: widget.product.id,
          child: AuthImage(url: widget.product.imageUrl, fit: BoxFit.contain),
        ),
      ),
    ));
  }

  Widget _buildDesktopLayout(ThemeConfig conf) {
    return Row(
      children: [
        Expanded(flex: 5, child: _buildDesktopImageSection()),
        Expanded(flex: 6, child: _buildContentSection(conf, isMobile: false)),
      ],
    );
  }

  Widget _buildMobileLayout(ThemeConfig conf) {
    return Column(
      children: [
        Expanded(flex: 4, child: _buildImageSection()),
        Expanded(flex: 6, child: _buildContentSection(conf, isMobile: true)),
      ],
    );
  }

  Widget _buildContentSection(ThemeConfig conf, {required bool isMobile}) {
    final l = AppLocalizations.of(context);
    final langCode = currentLocale.value.languageCode;
    final productName = widget.product.localizedName(langCode);
    final productDesc = widget.product.localizedDesc(langCode);

    return Padding(
      padding: EdgeInsets.all(isMobile ? 20 : 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  productName,
                  style: conf.dishTitleStyle(
                    fontSize: isMobile ? 26 : 32,
                    fontWeight: FontWeight.bold,
                    color: conf.accent,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                color: conf.text,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 10 : 15),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                productDesc.isEmpty ? l.noDescription : productDesc,
                style: GoogleFonts.manrope(
                  fontSize: isMobile ? 14 : 16,
                  color: conf.text.withValues(alpha: 0.8),
                ),
              ),
            ),
          ),
          SizedBox(height: isMobile ? 15 : 20),
          if (widget.product.portions.isNotEmpty) ...[
            Text(
              l.size,
              style: TextStyle(color: conf.text.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.product.portions.map((p) {
                final isSelected = selectedPortion == p;
                return ChoiceChip(
                  label: Text(p.name),
                  selected: isSelected,
                  onSelected: (v) => setState(() => selectedPortion = p),
                  selectedColor: conf.accent,
                  backgroundColor: conf.bg,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.black : conf.text,
                    fontWeight: FontWeight.bold,
                    fontSize: isMobile ? 12 : 14,
                  ),
                );
              }).toList(),
            ),
            SizedBox(height: isMobile ? 15 : 20),
          ],
          isMobile ? _buildActionsMobile(conf) : _buildActionsDesktop(conf),
        ],
      ),
    );
  }

  Widget _buildActionsDesktop(ThemeConfig conf) {
    return Row(
      children: [
        _buildQuantityControl(conf),
        const SizedBox(width: 20),
        Expanded(child: _buildAddButton(conf)),
      ],
    );
  }

  Widget _buildActionsMobile(ThemeConfig conf) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [_buildQuantityControl(conf)],
        ),
        const SizedBox(height: 15),
        _buildAddButton(conf),
      ],
    );
  }

  Widget _buildQuantityControl(ThemeConfig conf) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: conf.accent.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.remove, color: conf.text),
            onPressed: quantity > 1 ? _decrement : null,
          ),
          // Ширина числа не меняется при 9 → 10: кнопки «−» и «+» не съезжают
          SizedBox(
            width: 34,
            child: Text(
              "$quantity",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: conf.accent,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.add, color: conf.text),
            onPressed: _increment,
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton(ThemeConfig conf) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: () {
          widget.onAdd(widget.product, selectedPortion, quantity);
          Navigator.pop(context);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: conf.accent,
          foregroundColor: conf.onAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Builder(
              builder: (ctx) => Text(
                "${AppLocalizations.of(ctx).add} ",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            Flexible(
              child: Builder(
                builder: (ctx) => Text(
                  "(${totalPrice.toInt()} ${AppLocalizations.of(ctx).som})",
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

