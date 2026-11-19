/// Текст отзыва для WhatsApp.
///
/// Чистый Dart, без Flutter: так он дёшево проверяется золотым тестом
/// (test/review_message_test.dart), а когда отправлять отзывы начнёт сам
/// сервер, его текст можно будет сверить с этим слово в слово.
library;

import '../models/branch.dart';
import '../order/order_message.dart' show waLink;

export '../order/order_message.dart' show waLink;

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

/// Длиннее этого ссылки начинают теряться по дороге, особенно на айфоне.
/// Полный отзыв всё равно сохранён на сервере
const _maxTextLength = 1500;

/// Подписи на языке сотрудника, а не гостя: меню может быть открыто хоть
/// по-японски, но разбираться с жалобой будет тот, кто работает в кафе.
/// Чего нет — по-русски, как и в сообщении заказа.
const _labels = <String, Map<String, String>>{
  'ru': {
    'title': 'ОТЗЫВ ГОСТЯ',
    'rating': 'Оценка',
    'outOf': 'из 5',
    'waiter': 'Официант',
    'table': 'Стол',
    'comment': 'Отзыв',
  },
  'en': {
    'title': 'GUEST REVIEW',
    'rating': 'Rating',
    'outOf': 'of 5',
    'waiter': 'Waiter',
    'table': 'Table',
    'comment': 'Review',
  },
  'ky': {
    'title': 'КОНОКТУН ПИКИРИ',
    'rating': 'Баа',
    'outOf': '5 тен',
    'waiter': 'Официант',
    'table': 'Үстөл',
    'comment': 'Пикир',
  },
  'tr': {
    'title': 'MÜŞTERİ YORUMU',
    'rating': 'Puan',
    'outOf': '/ 5',
    'waiter': 'Garson',
    'table': 'Masa',
    'comment': 'Yorum',
  },
};

Map<String, String> _labelsFor(String language) =>
    _labels[language] ?? _labels['ru']!;

/// Жирным — только оценка: ради неё это сообщение и открывают. Выделить
/// больше — значит не выделить ничего (то же правило, что в заказе).
String _bold(String s) => '*$s*';

/// Звёзды обычными знаками, не эмодзи: эмодзи ломаются при вставке в
/// кассовую программу. Цифра рядом страхует и на этот случай.
String stars(int rating) => '${'★' * rating}${'☆' * (5 - rating)}';

/// Текст отзыва для WhatsApp.
///
/// Филиал — первой строкой: у владельца несколько точек, а в списке
/// переписок видно только начало сообщения. Заголовок заглавными, чтобы
/// отзыв не потерялся в потоке заказов.
String buildReviewText(ReviewDraft draft, {required Branch branch}) {
  final l = _labelsFor(branch.mainLanguage);
  final head = <String>[branch.name, l['title']!];
  final body = <String>[
    _bold('${l['rating']}: ${stars(draft.rating)} (${draft.rating} ${l['outOf']})'),
    if (draft.waiter.isNotEmpty) '${l['waiter']}: ${draft.waiter}',
    if (draft.tableNo.isNotEmpty) '${l['table']}: ${draft.tableNo}',
  ];
  final tail = <String>[
    if (draft.comment.isNotEmpty) '${l['comment']}: ${draft.comment}',
  ];
  final text = [head, body, tail]
      .where((block) => block.isNotEmpty)
      .map((block) => block.join('\n'))
      .join('\n\n');
  if (text.length <= _maxTextLength) return text;
  // Режется только сам отзыв: шапка и оценка нужны целиком
  return '${text.substring(0, _maxTextLength - 1)}…';
}

/// Ссылка на переписку с готовым текстом. Номер уже проверен филиалом
/// ([Branch.canSendReviewToWhatsapp]).
String reviewLink(ReviewDraft draft, {required Branch branch}) =>
    waLink(branch.reviewWhatsapp, buildReviewText(draft, branch: branch));
