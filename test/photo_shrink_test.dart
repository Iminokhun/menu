import 'dart:math';
import 'dart:typed_data';

import 'package:cafe_andalus_menu/photo_shrink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Шум: такой JPEG почти не сжимается — файл выходит тяжёлым, как снимок
img.Image _noise(int width, int height, {bool alpha = false}) {
  final rnd = Random(1);
  final image = img.Image(
    width: width,
    height: height,
    numChannels: alpha ? 4 : 3,
  );
  for (final p in image) {
    p
      ..r = rnd.nextInt(256)
      ..g = rnd.nextInt(256)
      ..b = rnd.nextInt(256);
    if (alpha) p.a = rnd.nextInt(256);
  }
  return image;
}

void main() {
  testWidgets('тяжёлое фото уменьшается до 1600 по длинной стороне', (t) async {
    await t.runAsync(() async {
      final big = img.encodeJpg(_noise(3000, 2000), quality: 95);
      expect(big.length, greaterThan(3 * 1024 * 1024));

      final out = await shrinkPhoto(big, 'jpeg');
      expect(out.ext, 'jpg');
      expect(out.bytes.length, lessThan(big.length));
      final decoded = img.decodeJpg(out.bytes)!;
      expect(decoded.width, 1600);
      // Декодер округляет вторую сторону как ему удобнее
      expect(decoded.height, closeTo(1067, 1));
    });
  });

  testWidgets('вертикальное фото: 1600 по высоте', (t) async {
    await t.runAsync(() async {
      final big = img.encodeJpg(_noise(2000, 3000), quality: 95);
      final decoded = img.decodeJpg((await shrinkPhoto(big, 'jpg')).bytes)!;
      expect(decoded.width, closeTo(1067, 1));
      expect(decoded.height, 1600);
    });
  });

  testWidgets('PNG с прозрачностью остаётся PNG', (t) async {
    await t.runAsync(() async {
      final big = img.encodePng(_noise(2000, 2000, alpha: true), level: 0);
      expect(big.length, greaterThan(3 * 1024 * 1024));

      final out = await shrinkPhoto(big, 'png');
      expect(out.ext, 'png');
      final decoded = img.decodePng(out.bytes)!;
      expect(decoded.width, 1600);
      expect(decoded.numChannels, 4);
    });
  });

  test('лёгкое фото уходит как есть', () async {
    final small = img.encodeJpg(_noise(400, 300));
    final out = await shrinkPhoto(small, 'jpg');
    expect(identical(out.bytes, small), isTrue);
  });

  testWidgets('не картинка — возвращается исходный файл', (t) async {
    await t.runAsync(() async {
      final junk = Uint8List(4 * 1024 * 1024);
      final out = await shrinkPhoto(junk, 'jpg');
      expect(identical(out.bytes, junk), isTrue);
      expect(out.ext, 'jpg');
    });
  });
}
