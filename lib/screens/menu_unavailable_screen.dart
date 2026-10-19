import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../menu_store.dart';
import '../theme/current_theme.dart';

/// Меню кафе выключено (не оплачено). Гостю о причине не сообщаем —
/// просто «временно недоступно»: долги кафе гостей не касаются.
/// Если кафе оплатит, «Повторить» сразу вернёт меню.
class MenuUnavailableScreen extends StatelessWidget {
  const MenuUnavailableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final config = appTheme.value;
    return Scaffold(
      backgroundColor: config.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.restaurant_menu_rounded,
                    size: 64, color: config.accent.withValues(alpha: 0.6)),
                const SizedBox(height: 20),
                Text(
                  'Меню временно недоступно',
                  textAlign: TextAlign.center,
                  style: config.titleStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: config.text,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Пожалуйста, обратитесь к персоналу заведения.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    color: config.text.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 30),
                ValueListenableBuilder<bool>(
                  valueListenable: menuStore.refreshing,
                  builder: (context, busy, _) => OutlinedButton.icon(
                    onPressed: busy ? null : menuStore.refresh,
                    icon: busy
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: config.accent),
                          )
                        : Icon(Icons.refresh, color: config.accent, size: 18),
                    label: Text('Повторить', style: TextStyle(color: config.accent)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: config.accent),
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
