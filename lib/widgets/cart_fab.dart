import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/product.dart';
import '../theme/current_theme.dart';

/// Плавающая кнопка корзины: сколько блюд и на какую сумму.
///
/// Живёт отдельным виджетом, потому что нужна и в меню, и в поиске: без неё
/// гость, набравший корзину из поиска, не может её даже открыть.
class CartFab extends StatelessWidget {
  final VoidCallback onPressed;

  const CartFab({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ValueListenableBuilder<List<CartItem>>(
      valueListenable: globalCart,
      builder: (context, cart, child) {
        if (cart.isEmpty) return const SizedBox.shrink();
        final config = appTheme.value;
        return FloatingActionButton.extended(
          heroTag: 'fab_cart',
          onPressed: onPressed,
          backgroundColor: config.accent,
          foregroundColor: config.onAccent,
          elevation: 10,
          icon: const Icon(Icons.shopping_basket),
          label: Row(
            children: [
              Text(
                '${cartCount(cart)} ${l.pcs} | ',
                style: const TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 16,
                ),
              ),
              Text(
                '${money(cartTotal(cart))} ${l.som}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
