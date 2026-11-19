/// Отзыв — одноразовый: оставил и всё.
///
/// Помним это **на устройстве гостя**, а не на сервере по адресу в сети.
/// В кафе весь зал сидит в одном Wi-Fi и приходит с одного адреса: запрет
/// «один отзыв с адреса» закрыл бы отзывы всем, кроме первого гостя за
/// день. Поэтому запрет на устройстве, а от шквала с одного телефона
/// сервер и так держит свой предел частоты.
///
/// Цена честная: гость, который сменит телефон или очистит браузер,
/// сможет оставить отзыв ещё раз. Накручивать этим нечего — отзывы видит
/// только кафе, публичного рейтинга нет.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Через сколько кнопка возвращается. Сутки, а не «навсегда»: иначе
/// постоянный гость, похваливший официанта однажды, не сможет сказать
/// ни слова больше никогда, и кафе перестанет слышать как раз своих.
const reviewAgainAfter = Duration(hours: 24);

const _prefix = 'review_sent_';

/// Филиалы, по которым с этого устройства уже оставили отзыв, и когда.
final _sent = <String, DateTime>{};

/// Меняется после каждого отзыва: по нему экран прячет кнопку, не
/// перечитывая хранилище
final reviewsLeft = ValueNotifier<int>(0);

/// Прочитать сохранённое. Зовётся один раз при запуске, до первого кадра.
Future<void> loadLeftReviews() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final at = DateTime.tryParse(prefs.getString(key) ?? '');
      if (at != null) _sent[key.substring(_prefix.length)] = at;
    }
  } catch (_) {
    // Хранилище недоступно (приватное окно, запрет на куки) — тогда
    // кнопка просто не прячется. Это лучше, чем не запуститься
  }
  reviewsLeft.value++;
}

/// Оставляли ли уже отзыв этому филиалу с этого устройства.
bool reviewLeftFor(String branchId) {
  final at = _sent[branchId];
  if (at == null) return false;
  if (DateTime.now().difference(at) >= reviewAgainAfter) {
    _sent.remove(branchId);
    return false;
  }
  return true;
}

/// Запомнить отзыв. Кнопка пропадает сразу, не дожидаясь записи на диск.
Future<void> rememberReview(String branchId) async {
  _sent[branchId] = DateTime.now();
  reviewsLeft.value++;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_prefix$branchId',
      DateTime.now().toIso8601String(),
    );
  } catch (_) {
    // Не записалось — кнопка вернётся после перезагрузки страницы.
    // Ради этого падать незачем
  }
}
