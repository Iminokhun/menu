// Отбор в списке заказов: что именно экран просит у сервера.
//
// Проверяем запросы, а не пиксели. Расчёт периода общий с отзывами
// (lib/screens/admin/admin_filters.dart) и проверен там; здесь —
// раскладка отметки и способа получения на параметры.
import 'dart:convert';

import 'package:cafe_andalus_menu/api/api_client.dart';
import 'package:cafe_andalus_menu/config/current_branch.dart';
import 'package:cafe_andalus_menu/models/branch.dart';
import 'package:cafe_andalus_menu/screens/admin/admin_orders_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _branch = Branch(id: 'b1', slug: 'center', name: 'Андалус, Центр');

late List<Uri> requests;
late List<Map<String, Object?>> orders;

Map<String, String> get lastQuery => requests.last.queryParameters;

Future<void> _open(WidgetTester tester, {Size size = const Size(1400, 1000)}) async {
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
  orders = [];
  api.httpClient = MockClient((req) async {
    requests.add(req.url);
    return http.Response.bytes(utf8.encode(jsonEncode(orders)), 200);
  });
  currentBranch.value = _branch;
  addTearDown(() => currentBranch.value = null);

  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: AdminOrdersScreen(active: true))),
  );
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

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump(const Duration(seconds: 1));
  tester.takeException();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('экран открывается на новых заказах', (tester) async {
    await _open(tester);

    expect(lastQuery['status'], 'new');
    expect(lastQuery.containsKey('order_type'), isFalse);
    expect(lastQuery.containsKey('since'), isFalse);
  });

  testWidgets('отметка и способ получения уходят параметрами', (tester) async {
    await _open(tester);

    await _tap(tester, 'Все заказы');
    expect(lastQuery.containsKey('status'), isFalse);

    await _tap(tester, 'Готовые');
    expect(lastQuery['status'], 'done');

    await _tap(tester, 'Самовывоз');
    expect(lastQuery['order_type'], 'pickup');
    expect(lastQuery['status'], 'done');

    await _tap(tester, 'Доставка');
    expect(lastQuery['order_type'], 'delivery');

    await _tap(tester, 'Любой способ');
    expect(lastQuery.containsKey('order_type'), isFalse);
  });

  testWidgets('период считается так же, как в отзывах', (tester) async {
    await _open(tester);
    await _tap(tester, 'Сегодня');

    final now = DateTime.now();
    expect(
      DateTime.parse('${lastQuery['since']}Z'),
      DateTime(now.year, now.month, now.day).toUtc(),
    );
  });

  // На телефоне те же девять кнопок заняли бы четыре ряда, поэтому группы
  // свёрнуты в кнопки с меню. Проверяем, что отбор от этого не изменился:
  // выбор в меню уходит на сервер тем же параметром
  testWidgets('телефон: отбор выбирается в меню', (tester) async {
    await _open(tester, size: const Size(360, 800));
    // Свёрнутый вид: девяти кнопок нет, есть три с подписью выбранного
    expect(find.text('Готовые'), findsNothing);
    expect(find.text('Новые'), findsOneWidget);

    await _tapSettle(tester, 'Новые');
    await _tapSettle(tester, 'Готовые');
    expect(lastQuery['status'], 'done');

    await _tapSettle(tester, 'Любой способ');
    await _tapSettle(tester, 'Доставка');
    expect(lastQuery['order_type'], 'delivery');
    expect(lastQuery['status'], 'done');

    // Сброс возвращает всё к рабочему виду
    await _tap(tester, 'Сбросить');
    expect(lastQuery['status'], 'new');
    expect(lastQuery.containsKey('order_type'), isFalse);
  });

  testWidgets('пусто под отбором: объяснение и возврат к новым', (
    tester,
  ) async {
    await _open(tester);
    await _tap(tester, 'Готовые');

    expect(find.text('Под этот отбор заказов нет.'), findsOneWidget);
    expect(find.textContaining('Готовые'), findsWidgets);

    await _tap(tester, 'Вернуться к новым');
    expect(lastQuery['status'], 'new');
    expect(find.textContaining('Новых заказов нет'), findsOneWidget);
  });
}
