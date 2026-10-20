import 'package:flutter_test/flutter_test.dart';
import 'package:cafe_andalus_menu/photo_url.dart';

void main() {
  const photo = 'https://menu.prostoerp.com/uploads/c/1c_b_258_ab12cd34.jpg';

  test('карточке хватает копии — адрес уменьшенной копии', () {
    expect(sizedPhotoUrl(photo, 540), '$photo?w=800');
    // Немного больше копии — всё равно копия
    expect(sizedPhotoUrl(photo, 1000), '$photo?w=800');
    expect(sizedPhotoUrl('http://192.168.0.19:8090/uploads/c/logo.PNG', 120),
        'http://192.168.0.19:8090/uploads/c/logo.PNG?w=800');
  });

  test('крупнее копии или размер неизвестен — само фото', () {
    expect(sizedPhotoUrl(photo, 1001), photo);
    expect(sizedPhotoUrl(photo, null), photo);
  });

  test('не фото с нашего сервера — адрес не меняется', () {
    for (final url in [
      'https://example.com/dish.jpg',
      'https://menu.prostoerp.com/uploads/c/model.glb',
      '$photo?w=800',
      'assets/backgrounds/midnight.jpg',
    ]) {
      expect(sizedPhotoUrl(url, 300), url, reason: url);
    }
  });
}
