// Сколько отзывов можно оставить с одного устройства: три, потом
// следующий через сутки. Считаем по филиалам и только на устройстве.
import 'dart:convert';

import 'package:cafe_andalus_menu/review/review_once.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _ago(Duration d) =>
    DateTime.now().subtract(d).toIso8601String();

String _marks(List<Duration> ago) =>
    jsonEncode([for (final d in ago) _ago(d)]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('пока отзывов не было — кнопка есть', () async {
    SharedPreferences.setMockInitialValues({});
    await loadLeftReviews();
    expect(reviewLimitReached('b1'), isFalse);
  });

  test('три отзыва можно, четвёртый — нет', () async {
    SharedPreferences.setMockInitialValues({});
    await loadLeftReviews();

    await rememberReview('b1');
    expect(reviewLimitReached('b1'), isFalse, reason: 'после первого');
    await rememberReview('b1');
    expect(reviewLimitReached('b1'), isFalse, reason: 'после второго');
    await rememberReview('b1');
    expect(reviewLimitReached('b1'), isTrue, reason: 'после третьего');
  });

  test('у каждого филиала свой счёт', () async {
    SharedPreferences.setMockInitialValues({});
    await loadLeftReviews();

    for (var i = 0; i < reviewsPerWindow; i++) {
      await rememberReview('b1');
    }

    expect(reviewLimitReached('b1'), isTrue);
    expect(reviewLimitReached('b2'), isFalse);
  });

  test('отметки переживают перезагрузку страницы', () async {
    SharedPreferences.setMockInitialValues({
      'review_sent_b1': _marks(const [
        Duration(hours: 3),
        Duration(hours: 2),
        Duration(hours: 1),
      ]),
    });
    await loadLeftReviews();
    expect(reviewLimitReached('b1'), isTrue);
  });

  test('место освобождается, когда самому старому исполнились сутки', () async {
    SharedPreferences.setMockInitialValues({
      'review_sent_b1': _marks(const [
        Duration(hours: 25), // выпал из окна
        Duration(hours: 5),
        Duration(hours: 1),
      ]),
    });
    await loadLeftReviews();
    expect(reviewLimitReached('b1'), isFalse);

    await rememberReview('b1');
    expect(reviewLimitReached('b1'), isTrue);
  });

  test('все три старше суток — счёт начинается заново', () async {
    SharedPreferences.setMockInitialValues({
      'review_sent_b1': _marks(const [
        Duration(days: 3),
        Duration(days: 2),
        Duration(hours: 30),
      ]),
    });
    await loadLeftReviews();
    expect(reviewLimitReached('b1'), isFalse);
  });

  test('видно, когда кнопка вернётся', () async {
    SharedPreferences.setMockInitialValues({
      'review_sent_b1': _marks(const [
        Duration(hours: 10),
        Duration(hours: 2),
        Duration(hours: 1),
      ]),
    });
    await loadLeftReviews();

    final at = reviewAgainAt('b1');
    expect(at, isNotNull);
    // Сутки от самого старого из трёх, то есть примерно через 14 часов
    final hours = at!.difference(DateTime.now()).inHours;
    expect(hours, inInclusiveRange(13, 14));
    expect(reviewAgainAt('b2'), isNull, reason: 'там кнопка и не пряталась');
  });

  test('отметка от прежней версии — одна дата строкой — не теряется', () async {
    SharedPreferences.setMockInitialValues({
      'review_sent_b1': _ago(const Duration(hours: 1)),
    });
    await loadLeftReviews();
    expect(reviewLimitReached('b1'), isFalse);

    await rememberReview('b1');
    await rememberReview('b1');
    expect(reviewLimitReached('b1'), isTrue, reason: 'старая отметка — первая');
  });

  test('испорченная отметка не ломает запуск', () async {
    SharedPreferences.setMockInitialValues({
      'review_sent_b1': 'вчера',
      'branch_slug': 'demo',
    });
    await loadLeftReviews();
    expect(reviewLimitReached('b1'), isFalse);
  });

  test('экран узнаёт об отзыве сразу, не перечитывая хранилище', () async {
    SharedPreferences.setMockInitialValues({});
    await loadLeftReviews();
    final before = reviewsLeft.value;

    await rememberReview('b9');

    expect(reviewsLeft.value, greaterThan(before));
  });
}
