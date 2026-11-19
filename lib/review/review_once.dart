/// Сколько отзывов гость может оставить и когда сможет снова.
///
/// Помним это **на устройстве гостя**, а не на сервере по адресу в сети.
/// В кафе весь зал сидит в одном Wi-Fi и приходит с одного адреса: запрет
/// «три отзыва с адреса» закрыл бы отзывы всем, кроме первых гостей за
/// день. Поэтому запрет на устройстве, а от шквала с одного телефона
/// сервер и так держит свой предел частоты.
///
/// Цена честная: гость, который сменит телефон или очистит браузер,
/// сможет оставить отзыв ещё раз. Накручивать этим нечего — отзывы видит
/// только кафе, публичного рейтинга нет.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сколько отзывов подряд можно оставить одному филиалу с одного
/// устройства, прежде чем кнопка спрячется.
const reviewsPerWindow = 3;

/// Через сколько после **первого** из этих трёх кнопка возвращается.
/// Не «навсегда»: постоянный гость, похваливший официанта однажды, иначе
/// не сказал бы ни слова больше никогда, и кафе перестало бы слышать как
/// раз своих.
const reviewWindow = Duration(hours: 24);

const _prefix = 'review_sent_';

/// Когда с этого устройства оставляли отзывы, по филиалам. Старше окна
/// не храним — список сам себя подрезает.
final _sent = <String, List<DateTime>>{};

/// Меняется после каждого отзыва: по нему экран прячет кнопку, не
/// перечитывая хранилище
final reviewsLeft = ValueNotifier<int>(0);

List<DateTime> _parse(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  // Раньше хранилась одна дата строкой — читаем и её, чтобы отметка,
  // поставленная прошлой версией, не пропала
  final single = DateTime.tryParse(raw);
  if (single != null) return [single];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return [];
    return [
      for (final v in list)
        if (v is String && DateTime.tryParse(v) != null) DateTime.parse(v),
    ];
  } catch (_) {
    return [];
  }
}

/// Только те отзывы, что ещё в окне; остальные забываем
List<DateTime> _fresh(List<DateTime> all) {
  final edge = DateTime.now().subtract(reviewWindow);
  return all.where((t) => t.isAfter(edge)).toList()..sort();
}

/// Прочитать сохранённое. Зовётся один раз при запуске, до первого кадра.
Future<void> loadLeftReviews() async {
  _sent.clear();
  try {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final times = _fresh(_parse(prefs.getString(key)));
      if (times.isNotEmpty) _sent[key.substring(_prefix.length)] = times;
    }
  } catch (_) {
    // Хранилище недоступно (приватное окно, запрет на куки) — тогда
    // кнопка просто не прячется. Это лучше, чем не запуститься
  }
  reviewsLeft.value++;
}

/// Исчерпал ли гость свои отзывы этому филиалу.
bool reviewLimitReached(String branchId) {
  final times = _sent[branchId];
  if (times == null) return false;
  final fresh = _fresh(times);
  if (fresh.isEmpty) {
    _sent.remove(branchId);
  } else {
    _sent[branchId] = fresh;
  }
  return fresh.length >= reviewsPerWindow;
}

/// Когда кнопка вернётся, если она спрятана. Иначе `null`.
DateTime? reviewAgainAt(String branchId) {
  final times = _fresh(_sent[branchId] ?? const []);
  if (times.length < reviewsPerWindow) return null;
  // Окно скользящее: место освободится, когда самому старому из трёх
  // отзывов исполнятся сутки
  return times.first.add(reviewWindow);
}

/// Запомнить отзыв. Кнопка прячется сразу, не дожидаясь записи на диск.
Future<void> rememberReview(String branchId) async {
  final times = _fresh(_sent[branchId] ?? const [])..add(DateTime.now());
  _sent[branchId] = times;
  reviewsLeft.value++;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_prefix$branchId',
      jsonEncode([for (final t in times) t.toIso8601String()]),
    );
  } catch (_) {
    // Не записалось — отметка вернётся к прежней после перезагрузки
    // страницы. Ради этого падать незачем
  }
}
