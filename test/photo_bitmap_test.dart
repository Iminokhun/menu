import 'package:cafe_andalus_menu/photo_bitmap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Заодно проверяет, что обход вообще собирается не для браузера: на
  // планшете и компьютере фото разжимает сам движок, и делает это верно
  test('вне браузера фото разжимает движок', () {
    expect(photoBitmapNeeded, isFalse);
    expect(() => photoBitmapImage('https://example.com/a.jpg', 400),
        throwsUnsupportedError);
  });
}
