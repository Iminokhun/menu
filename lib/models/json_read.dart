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
