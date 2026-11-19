/// Отправка отзыва: ссылка в WhatsApp и запись на сервере.
///
/// В отличие от заказа (`order_delivery.dart`), здесь один класс без
/// наследников: развилка всего одна — есть у филиала номер WhatsApp или нет,
/// и ради неё заводить иерархию незачем.
library;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../api/api_client.dart';
import '../models/branch.dart';
import '../open_link.dart';
import 'review_message.dart';

class ReviewSender {
  /// Номер, куда уходит отзыв. Пусто — WhatsApp не открывается, отзыв
  /// просто сохраняется на сервере.
  final String phone;

  /// Можно ли вообще оставить отзыв в этом филиале.
  final bool canReview;

  const ReviewSender({required this.canReview, this.phone = ''});

  bool get opensWhatsapp => phone.isNotEmpty;

  /// Кнопка отзыва показывается, только когда это браузер и право выдано.
  ///
  /// Вне браузера `openLink` — заглушка (`open_link_io.dart`), а на планшете
  /// в зале отзыв о собственном официанте оставлять некому. Номер в условие
  /// **не входит**, и это не упущение: без номера отзыв всё равно уходит на
  /// сервер и кафе видит его в своей админке.
  static ReviewSender forBranch(Branch? branch) {
    if (branch == null || !kIsWeb || !branch.reviewsEnabled) {
      return const ReviewSender(canReview: false);
    }
    return ReviewSender(
      canReview: true,
      phone: branch.canSendReviewToWhatsapp ? branch.reviewWhatsapp : '',
    );
  }

  /// Ссылка на переписку с уже набранным отзывом — её же можно открыть
  /// повторно, если окно у гостя заблокировалось. Нет номера — нет ссылки.
  String? linkFor(ReviewDraft draft, Branch branch) =>
      opensWhatsapp ? reviewLink(draft, branch: branch) : null;

  /// Отправить отзыв. Возвращает `true`, если он сохранён на сервере.
  ///
  /// ВАЖНО: до `openLink` не должно быть ни одного `await` — браузер
  /// открывает новую вкладку только внутри жеста гостя. Поэтому ссылка
  /// открывается первой строкой, а вызывающий код не ждёт этот Future.
  Future<bool> submit(
    ReviewDraft draft, {
    required Branch branch,
    required String lang,
  }) async {
    final link = linkFor(draft, branch);
    if (link != null) openLink(link);

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
