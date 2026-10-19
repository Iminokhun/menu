import 'package:flutter/material.dart';
import '../config/current_branch.dart';
import '../l10n/languages.dart';
import '../l10n/translation_service.dart';
import '../models/branch.dart';
import '../theme/theme_config.dart';

/// Языки меню филиала. Один язык — переключателя нет; до [_inlineMax] —
/// кнопками в ряд; больше — одной кнопкой со списком, иначе ряд не
/// поместится на телефоне.
class LangSwitcher extends StatelessWidget {
  final ThemeConfig config;

  const LangSwitcher({super.key, required this.config});

  static const _inlineMax = 4;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Branch?>(
      valueListenable: currentBranch,
      builder: (_, branch, __) {
        final langs = branch?.languages ?? const ['ru'];
        if (langs.length < 2) return const SizedBox.shrink();
        return ValueListenableBuilder<Locale>(
          valueListenable: currentLocale,
          builder: (_, locale, __) {
            final current = locale.languageCode;
            return Container(
              decoration: BoxDecoration(
                color: config.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: config.text.withValues(alpha: 0.12)),
              ),
              child: langs.length <= _inlineMax
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final code in langs)
                          GestureDetector(
                            onTap: () => chooseLanguage(code),
                            child: _chip(code, active: code == current),
                          ),
                      ],
                    )
                  : _menu(langs, current),
            );
          },
        );
      },
    );
  }

  Widget _menu(List<String> langs, String current) {
    return PopupMenuButton<String>(
      tooltip: '',
      initialValue: current,
      onSelected: chooseLanguage,
      color: config.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => [
        for (final code in langs)
          PopupMenuItem(
            value: code,
            child: Text(
              menuLanguage(code)?.nativeName ?? code,
              style: TextStyle(
                color: config.text,
                fontWeight: code == current ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
      ],
      child: _chip(current, active: true, dropdown: true),
    );
  }

  Widget _chip(String code, {required bool active, bool dropdown = false}) {
    // на тёмном фирменном цвете — белым, на светлом — чёрным
    final color = active ? config.onAccent : config.text.withValues(alpha: 0.5);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.fromLTRB(14, 9, dropdown ? 8 : 14, 9),
      decoration: BoxDecoration(
        color: active ? config.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            code.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: color,
            ),
          ),
          if (dropdown) Icon(Icons.expand_more, size: 18, color: color),
        ],
      ),
    );
  }
}
