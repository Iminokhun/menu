import 'package:flutter/widgets.dart';

import '../../l10n/languages.dart';
import '../../models/json_read.dart';

/// Поля переводов в окне категории или товара: по полю ввода на каждый
/// дополнительный язык филиала и каждое переводимое поле.
///
/// Переводы на языки, которых сейчас нет в филиале, не показываются, но и
/// не теряются: [toJson] возвращает их как были — кафе может вернуть язык.
class Translations {
  final Map<String, Map<String, String>> _initial;
  final Map<String, Map<String, TextEditingController>> _ctrls = {};

  /// [languages] — языки филиала, первый (основной) пропускается: его
  /// тексты — в обычных полях name и description.
  Translations(Object? i18n, List<String> languages, List<String> fields)
      : _initial = i18nFromJson(i18n) {
    for (final lang in languages.skip(1)) {
      _ctrls[lang] = {
        for (final f in fields)
          f: TextEditingController(text: _initial[lang]?[f] ?? ''),
      };
    }
  }

  /// Дополнительные языки филиала по порядку.
  Iterable<String> get languages => _ctrls.keys;

  TextEditingController controller(String lang, String field) =>
      _ctrls[lang]![field]!;

  /// «Название (английский)»
  static String label(String what, String lang) =>
      '$what (${menuLanguage(lang)?.ruName.toLowerCase() ?? lang})';

  Map<String, Map<String, String>> toJson() {
    final out = {
      for (final e in _initial.entries)
        if (!_ctrls.containsKey(e.key)) e.key: e.value,
    };
    _ctrls.forEach((lang, fields) {
      final texts = {
        for (final f in fields.entries)
          if (f.value.text.trim().isNotEmpty) f.key: f.value.text.trim(),
      };
      if (texts.isNotEmpty) out[lang] = texts;
    });
    return out;
  }
}
