import 'package:cafe_andalus_menu/widgets/star_rating.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<int?> _tap(WidgetTester tester, int star, {required int value}) async {
  int? picked;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: StarRating(
            value: value,
            color: Colors.amber,
            onChanged: (v) => picked = v,
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byType(InkResponse).at(star - 1));
  await tester.pump();
  return picked;
}

void main() {
  testWidgets('нажатие по N-й звезде отдаёт N', (tester) async {
    expect(await _tap(tester, 1, value: 0), 1);
    expect(await _tap(tester, 3, value: 0), 3);
    expect(await _tap(tester, 5, value: 2), 5);
  });

  testWidgets('без оценки все звёзды пустые', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StarRating(value: 0, color: Colors.amber)),
      ),
    );
    expect(find.byIcon(Icons.star_outline_rounded), findsNWidgets(5));
    expect(find.byIcon(Icons.star_rounded), findsNothing);
  });

  testWidgets('оценка 4 — четыре закрашенных и одна пустая', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StarRating(value: 4, color: Colors.amber)),
      ),
    );
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(4));
    expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);
  });

  testWidgets('только показ: нажатия ничего не делают', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GestureDetector(
            onTap: () => taps++,
            child: const StarRating(value: 3, color: Colors.amber),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.star_rounded).first);
    await tester.pump();
    // Нажатие прошло насквозь к родителю — сама звезда его не перехватила
    expect(taps, 1);
  });
}
