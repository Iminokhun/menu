// Отзыв одноразовый: оставил — и кнопки больше нет. Помним на устройстве,
// по филиалу, и ровно на сутки.
import 'package:cafe_andalus_menu/review/review_once.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('пока отзыва не было — кнопка есть', () async {
    SharedPreferences.setMockInitialValues({});
    await loadLeftReviews();
    expect(reviewLeftFor('b1'), isFalse);
  });

  test('после отзыва кнопка пропадает, и только у своего филиала', () async {
    SharedPreferences.setMockInitialValues({});
    await loadLeftReviews();

    await rememberReview('b1');

    expect(reviewLeftFor('b1'), isTrue);
    expect(reviewLeftFor('b2'), isFalse);
  });

  test('отметка переживает перезагрузку страницы', () async {
    SharedPreferences.setMockInitialValues({
      'review_sent_b1': DateTime.now().toIso8601String(),
    });
    await loadLeftReviews();
    expect(reviewLeftFor('b1'), isTrue);
  });

  test('через сутки кнопка возвращается', () async {
    SharedPreferences.setMockInitialValues({
      'review_sent_b1': DateTime.now()
          .subtract(reviewAgainAfter + const Duration(minutes: 1))
          .toIso8601String(),
      'review_sent_b2': DateTime.now()
          .subtract(reviewAgainAfter - const Duration(minutes: 1))
          .toIso8601String(),
    });
    await loadLeftReviews();
    expect(reviewLeftFor('b1'), isFalse);
    expect(reviewLeftFor('b2'), isTrue);
  });

  test('испорченная отметка не ломает запуск', () async {
    SharedPreferences.setMockInitialValues({
      'review_sent_b1': 'вчера',
      'branch_slug': 'demo',
    });
    await loadLeftReviews();
    expect(reviewLeftFor('b1'), isFalse);
  });

  test('экран узнаёт об отзыве сразу, не перечитывая хранилище', () async {
    SharedPreferences.setMockInitialValues({});
    await loadLeftReviews();
    final before = reviewsLeft.value;

    await rememberReview('b9');

    expect(reviewsLeft.value, greaterThan(before));
  });
}
