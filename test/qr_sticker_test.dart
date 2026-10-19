import 'dart:convert';

import 'package:cafe_andalus_menu/widgets/qr_sticker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // В тестах сети нет вообще — раньше шрифт качался из Google, и сборка
  // PDF здесь падала бы так же, как на планшете без интернета
  test('PDF с QR-кодом собирается без интернета, с кириллицей', () async {
    final pdf = await buildQrSticker(
      title: 'Бишкек Кофе — Центр',
      link: 'https://menu.kg/?branch=bishkek-kofe-centr',
    );
    expect(ascii.decode(pdf.sublist(0, 5)), '%PDF-');
    expect(pdf.length, greaterThan(10000)); // шрифт вшит в файл
  });
}
