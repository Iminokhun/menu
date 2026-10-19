/// Чтение полей из ответа сервера, терпимое к типам.
///
/// Прямое `json['x'] as int` бросает исключение на `1.0` или `"1"`, и тогда
/// пропадает весь список, в котором оказалась такая строка. Здесь значение
/// неожиданного типа превращается в значение по умолчанию.
library;

String jsonStr(Object? v, [String fallback = '']) => v is String ? v : fallback;

double jsonDouble(Object? v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

int jsonInt(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num && v.isFinite) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

/// Переводы `{"en": {"name": "…"}}`. Пустые тексты и значения не того
/// типа пропускаются — блюдо тогда показывается на основном языке.
Map<String, Map<String, String>> i18nFromJson(Object? v) {
  if (v is! Map) return const {};
  return {
    for (final MapEntry(:key, :value) in v.entries)
      if (key is String && value is Map)
        key: {
          for (final MapEntry(key: field, value: text) in value.entries)
            if (field is String && text is String && text.isNotEmpty)
              field: text,
        },
  };
}

/// Список строк; всё, что не строка, пропускается.
List<String> jsonStrings(Object? v) =>
    v is List ? [for (final x in v) if (x is String) x] : const [];
