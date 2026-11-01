import 'package:cafe_andalus_menu/widgets/fit_words_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<double> _shownSize(WidgetTester tester, String text, double width) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: width,
          child: FitWordsText(text, style: const TextStyle(fontSize: 22, letterSpacing: 1.2)),
        ),
      ),
    ),
  );
  return tester.widget<Text>(find.byType(Text)).style!.fontSize!;
}

/// Ширина слова одной строкой при этом размере шрифта
double _wordWidth(String word, double size) {
  final p = TextPainter(
    text: TextSpan(text: word, style: TextStyle(fontSize: size, letterSpacing: 1.2)),
    textDirection: TextDirection.ltr,
  )..layout();
  return p.width;
}

void main() {
  testWidgets('длинное слово в узкой карточке уменьшается и не рвётся по буквам', (tester) async {
    final size = await _shownSize(tester, 'ЗАВТРАКИ', 100);
    expect(size, lessThan(22));
    expect(_wordWidth('ЗАВТРАКИ', size), lessThanOrEqualTo(100));
  });

  testWidgets('короткое название остаётся в полный размер', (tester) async {
    expect(await _shownSize(tester, 'СУПЫ', 300), 22);
  });

  testWidgets('несколько слов переносятся между словами, по самому длинному', (tester) async {
    final size = await _shownSize(tester, 'ГОРЯЧИЕ ЗАВТРАКИ', 100);
    expect(_wordWidth('ЗАВТРАКИ', size), lessThanOrEqualTo(100));
  });
}
