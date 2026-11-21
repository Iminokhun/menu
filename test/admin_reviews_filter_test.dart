// Отбор в списке отзывов: что именно экран просит у сервера.
//
// Проверяем запросы, а не пиксели: вся новая логика — это раскладка
// кнопок на параметры и граница периода, где легко промахнуться с
// часовым поясом и с «сегодня и шесть предыдущих».
import 'dart:convert';

import 'package:cafe_andalus_menu/api/api_client.dart';
import 'package:cafe_andalus_menu/config/current_branch.dart';
import 'package:cafe_andalus_menu/models/branch.dart';
import 'package:cafe_andalus_menu/screens/admin/admin_reviews_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _branch = Branch(
  id: 'b1',
  slug: 'center',
  name: 'Андалус, Центр',
  reviewsEnabled: true,
);

/// Запросы к списку отзывов, в порядке отправки
late List<Uri> requests;

/// Что сервер отдаёт на список; по умолчанию пусто
late List<Map<String, Object?>> reviews;

Map<String, String> get lastQuery => requests.last.queryParameters;

Future<void> _open(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
}) async {
  // Размер задаём дважды: view.physicalSize видит MediaQuery (от него
  // зависит выбор вёрстки), а setSurfaceSize — слой всплывающих меню.
  // С одним только physicalSize меню открывалось за левым краем экрана
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    tester.view.reset();
    await tester.binding.setSurfaceSize(null);
  });

  requests = [];
  reviews = [];
  api.httpClient = MockClient((req) async {
    final Object body;
    if (req.url.path.endsWith('/waiters')) {
      body = [
        {'waiter': 'Айгуль', 'count': 3},
        {'waiter': 'Нурбек', 'count': 1},
      ];
    } else {
      requests.add(req.url);
      body = reviews;
    }
    return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
  });
  currentBranch.value = _branch;
  addTearDown(() => currentBranch.value = null);

  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: AdminReviewsScreen(active: true))),
  );
  await tester.pump(const Duration(seconds: 1));
  tester.takeException();
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump(const Duration(seconds: 1));
  tester.takeException();
}

/// Нажать и дождаться, пока всё доедет: всплывающее меню открывается
/// анимацией, и до её конца пункт не принимает нажатий.
Future<void> _tapSettle(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
  tester.takeException();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // На телефоне восемь кнопок отбора заняли бы три ряда, поэтому период и
  // оценка свёрнуты в кнопки с меню — как официант. Проверяем, что отбор
  // от этого не изменился: выбор уходит на сервер теми же параметрами
  testWidgets('телефон: отбор выбирается в меню', (tester) async {
    await _open(tester, size: const Size(360, 800));
    // Свёрнутый вид: отдельных кнопок «5 и 4» и «Сегодня» нет
    expect(find.text('5 и 4'), findsNothing);
    expect(find.text('Сегодня'), findsNothing);
    expect(find.text('Любая оценка'), findsOneWidget);

    await _tapSettle(tester, 'Любая оценка');
    await _tapSettle(tester, '2 и 1');
    expect(lastQuery['max_rating'], '2');
    // На кнопке видно, что выбрано: «3» или «2 и 1» сами по себе непонятны
    expect(find.text('Оценка: 2 и 1'), findsOneWidget);

    await _tapSettle(tester, 'За всё время');
    await _tapSettle(tester, '7 дней');
    expect(lastQuery.containsKey('since'), isTrue);
    expect(lastQuery['max_rating'], '2');

    await _tapSettle(tester, 'Сбросить');
    expect(lastQuery.containsKey('since'), isFalse);
    expect(lastQuery.containsKey('max_rating'), isFalse);
  });

  testWidgets('без отбора лишних параметров в запросе нет', (tester) async {
    await _open(tester);

    expect(lastQuery.containsKey('since'), isFalse);
    expect(lastQuery.containsKey('min_rating'), isFalse);
    expect(lastQuery.containsKey('max_rating'), isFalse);
    expect(lastQuery.containsKey('waiter'), isFalse);
    expect(lastQuery['branch_id'], 'b1');
  });

  testWidgets('корзины оценок раскладываются в min_rating и max_rating', (
    tester,
  ) async {
    await _open(tester);

    await _tap(tester, '5 и 4');
    expect(lastQuery['min_rating'], '4');
    expect(lastQuery.containsKey('max_rating'), isFalse);

    await _tap(tester, '3');
    expect(lastQuery['min_rating'], '3');
    expect(lastQuery['max_rating'], '3');

    await _tap(tester, '2 и 1');
    expect(lastQuery.containsKey('min_rating'), isFalse);
    expect(lastQuery['max_rating'], '2');
  });

  testWidgets('«Сегодня» — это местная полночь, переведённая в UTC', (
    tester,
  ) async {
    await _open(tester);
    await _tap(tester, 'Сегодня');

    final now = DateTime.now();
    final expected = DateTime(now.year, now.month, now.day).toUtc();
    final got = DateTime.parse('${lastQuery['since']}Z');
    expect(got, expected);
  });

  testWidgets('«7 дней» — сегодня и шесть предыдущих, а не семь', (
    tester,
  ) async {
    await _open(tester);
    await _tap(tester, '7 дней');

    final now = DateTime.now();
    final expected = DateTime(now.year, now.month, now.day - 6).toUtc();
    expect(DateTime.parse('${lastQuery['since']}Z'), expected);
  });

  testWidgets('пусто под отбором: объяснение и сброс', (tester) async {
    await _open(tester);
    await _tap(tester, '2 и 1');

    expect(find.text('Под этот отбор отзывов нет.'), findsOneWidget);
    expect(find.textContaining('оценка 2 и 1'), findsOneWidget);

    await _tap(tester, 'Показать все отзывы');
    expect(lastQuery.containsKey('max_rating'), isFalse);
    expect(lastQuery.containsKey('since'), isFalse);
    expect(find.text('Отзывов пока нет.'), findsOneWidget);
  });

  testWidgets('при отборе по оценке средняя не показывается', (tester) async {
    await _open(tester);
    reviews = [
      {'id': 'r1', 'rating': 2, 'waiter': '', 'table_no': '', 'comment': 'п'},
    ];

    await _tap(tester, '2 и 1');
    expect(find.textContaining('Средняя'), findsNothing);
    expect(find.textContaining('Показано: 1'), findsOneWidget);

    await _tap(tester, 'Любая оценка');
    expect(find.textContaining('Средняя по показанным'), findsOneWidget);
  });
}
