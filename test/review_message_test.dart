// Золотой текст отзыва. Сверять дословно: когда отправлять отзывы начнёт
// сам сервер, его текст обязан совпасть с этим слово в слово.
import 'package:cafe_andalus_menu/models/branch.dart';
import 'package:cafe_andalus_menu/review/review_message.dart';
import 'package:flutter_test/flutter_test.dart';

const _branch = Branch(
  id: 'b1',
  slug: 'center',
  name: 'Андалус, Центр',
  reviewWhatsapp: '996555112233',
  reviewsEnabled: true,
);

void main() {
  test('полный отзыв', () {
    const draft = ReviewDraft(
      rating: 4,
      waiter: 'Айгуль',
      tableNo: '12',
      comment: 'Вкусно, но салат несли сорок минут.',
    );
    expect(
      buildReviewText(draft, branch: _branch),
      'Андалус, Центр\n'
      'ОТЗЫВ ГОСТЯ\n'
      '\n'
      '*Оценка: ★★★★☆ (4 из 5)*\n'
      'Официант: Айгуль\n'
      'Стол: 12\n'
      '\n'
      'Отзыв: Вкусно, но салат несли сорок минут.',
    );
  });

  test('одни звёзды: ни пустых строк, ни лишних подписей', () {
    expect(
      buildReviewText(const ReviewDraft(rating: 5), branch: _branch),
      'Андалус, Центр\n'
      'ОТЗЫВ ГОСТЯ\n'
      '\n'
      '*Оценка: ★★★★★ (5 из 5)*',
    );
  });

  test('одна звезда — четыре пустых', () {
    expect(stars(1), '★☆☆☆☆');
    expect(stars(5), '★★★★★');
  });

  test('подписи — на языке филиала, а не гостя', () {
    const kyrgyz = Branch(
      id: 'b2',
      slug: 'osh',
      name: 'Ош',
      languages: ['ky', 'en'],
      reviewWhatsapp: '996555112233',
      reviewsEnabled: true,
    );
    final text = buildReviewText(
      const ReviewDraft(rating: 3, waiter: 'Азамат'),
      branch: kyrgyz,
    );
    expect(text, contains('КОНОКТУН ПИКИРИ'));
    expect(text, contains('Официант: Азамат'));
    expect(text, isNot(contains('ОТЗЫВ ГОСТЯ')));
  });

  test('язык, которого нет в подписях, — по-русски', () {
    const japanese = Branch(
      id: 'b3',
      slug: 'jp',
      name: 'Сакура',
      languages: ['ja'],
      reviewsEnabled: true,
    );
    expect(
      buildReviewText(const ReviewDraft(rating: 2), branch: japanese),
      contains('ОТЗЫВ ГОСТЯ'),
    );
  });

  test('слишком длинный отзыв обрезается', () {
    final long = buildReviewText(
      ReviewDraft(rating: 5, comment: 'я' * 3000),
      branch: _branch,
    );
    expect(long.length, 1500);
    expect(long.endsWith('…'), isTrue);
    // Шапка и оценка на месте — режется только текст гостя
    expect(long, startsWith('Андалус, Центр\nОТЗЫВ ГОСТЯ'));
    expect(long, contains('*Оценка: ★★★★★ (5 из 5)*'));
  });

  test('ссылка несёт тот же текст и номер филиала', () {
    const draft = ReviewDraft(rating: 5, tableNo: '7');
    final link = reviewLink(draft, branch: _branch);
    final uri = Uri.parse(link);
    expect(uri.host, 'wa.me');
    expect(uri.path, '/996555112233');
    expect(
      uri.queryParameters['text'],
      buildReviewText(draft, branch: _branch),
    );
  });

  test('тело запроса — поля с именами из базы', () {
    const draft = ReviewDraft(
      rating: 4,
      waiter: 'Айгуль',
      tableNo: '12',
      comment: 'Хорошо',
    );
    expect(draft.toJson('b1', 'ru'), {
      'branch_id': 'b1',
      'rating': 4,
      'waiter': 'Айгуль',
      'table_no': '12',
      'comment': 'Хорошо',
      'lang': 'ru',
    });
  });
}
