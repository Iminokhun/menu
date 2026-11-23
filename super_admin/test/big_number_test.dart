// Крупная цифра: как число разбивается тройками и что подпись не
// отрывается от цифры. Цифры тут крупные и видны издалека — ошибка в
// разрядах будет стоить разговора с кафе «у вас тысяча гостей в день».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_admin/big_number.dart';

void main() {
  test('число разбито тройками', () {
    expect(bigNumber(0), '0');
    expect(bigNumber(7), '7');
    expect(bigNumber(999), '999');
    expect(bigNumber(1000), '1 000');
    expect(bigNumber(9412), '9 412');
    expect(bigNumber(1234567), '1 234 567');
  });

  test('разделитель неразрывный — иначе число разорвёт переносом', () {
    expect(bigNumber(9412).contains(' '), isFalse);
  });

  testWidgets('цифра и подпись — вместе', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BigStat(9412, 'сегодня'))),
    );
    expect(find.text('9 412'), findsOneWidget);
    expect(find.text('сегодня'), findsOneWidget);
  });
}
