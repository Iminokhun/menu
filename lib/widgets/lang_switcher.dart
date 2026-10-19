import 'package:flutter/material.dart';
import '../l10n/translation_service.dart';
import '../theme/theme_config.dart';

class LangSwitcher extends StatelessWidget {
  final ThemeConfig config;

  const LangSwitcher({super.key, required this.config});

  static const _langs = ['RU', 'EN', 'TR'];

  void _selectLang(String code) {
    currentLocale.value = Locale(code.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: currentLocale,
      builder: (_, locale, __) {
        final current = locale.languageCode.toUpperCase();
        return Container(
          decoration: BoxDecoration(
            color: config.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: config.text.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _langs.map((lang) {
              final isActive = lang == current;
              return GestureDetector(
                onTap: () => _selectLang(lang),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: isActive ? config.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    lang,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      // на тёмном фирменном цвете — белым, на светлом — чёрным
                      color: isActive
                          ? config.onAccent
                          : config.text.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
