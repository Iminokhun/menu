/// Отправка отзыва: только запись на сервер.
///
/// В WhatsApp отзыв не пересылается — гость ничего не открывает и никуда
/// не уходит со страницы. Кафе читает отзывы в своей админке, в разделе
/// «Отзывы». Это заодно убирает две беды пересылки ссылкой: гость мог
/// поправить текст перед отправкой, а мог и вовсе её не отправить.
library;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../api/api_client.dart';
import '../models/branch.dart';

/// Отзыв, который заполнил гость. Пустые поля — обычное дело: обязательна
/// только оценка.
class ReviewDraft {
  final int rating;
  final String waiter;
  final String tableNo;
  final String comment;

  const ReviewDraft({
    required this.rating,
    this.waiter = '',
    this.tableNo = '',
    this.comment = '',
  });

  /// Тело запроса `POST /api/public/reviews`. Имена полей — как в базе.
  Map<String, Object?> toJson(String branchId, String lang) => {
    'branch_id': branchId,
    'rating': rating,
    'waiter': waiter,
    'table_no': tableNo,
    'comment': comment,
    'lang': lang,
  };
}

class ReviewSender {
  /// Можно ли вообще оставить отзыв в этом филиале.
  final bool canReview;

  const ReviewSender({required this.canReview});

  /// Кнопка отзыва показывается, только когда это браузер и право выдано.
  ///
  /// Вне браузера — планшет в зале, где отзыв о собственном официанте
  /// оставлять некому.
  static ReviewSender forBranch(Branch? branch) =>
      ReviewSender(canReview: branch != null && kIsWeb && branch.reviewsEnabled);

  /// Отправить отзыв. Возвращает `true`, если он сохранён на сервере.
  Future<bool> submit(
    ReviewDraft draft, {
    required Branch branch,
    required String lang,
  }) async {
    try {
      await api.post('/api/public/reviews', draft.toJson(branch.id, lang));
      return true;
    } on ApiException catch (e) {
      // Повторяем только когда сервер не ответил или сам сломался: чаще
      // всего это моргнувшая сеть. На 400 второй раз придёт тот же отказ,
      // а на 429 повтор съест ещё одну из немногих попыток гостя.
      // Сервер отбрасывает повтор того же отзыва за две минуты, поэтому
      // дважды он не сохранится
      if (!e.isOffline) return false;
      try {
        await Future<void>.delayed(const Duration(seconds: 2));
        await api.post('/api/public/reviews', draft.toJson(branch.id, lang));
        return true;
      } on ApiException {
        return false;
      }
    }
  }
}
