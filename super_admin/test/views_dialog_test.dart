// Окно просмотров: цифры кафе и филиалов, столбик на каждый день окна
// (включая пустые дни), смена периода и понятное поведение, пока ответ
// не пришёл или не пришёл вовсе.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:super_admin/api_client.dart';
import 'package:super_admin/screens/views_dialog.dart';

const _cafe = {'id': 'cafe-1', 'name': 'Андалус'};

Map<String, Object?> _answer() => {
  'today': '2026-11-23',
  'days': [
    {'day': '2026-11-21', 'people': 4, 'opens': 9},
    {'day': '2026-11-23', 'people': 12, 'opens': 30},
  ],
  'branches': [
    {
      'id': 'b1',
      'name': 'Центр',
      'views_today': 9,
      'views_total': 300,
    },
    {'id': 'b2', 'name': 'Восток', 'views_today': 3, 'views_total': 120},
  ],
};

void main() {
  /// Адреса всех запросов, по порядку
  late List<Uri> requests;

  /// Чем отвечает сервер: null — обычным ответом
  Completer<void>? hold;
  var fails = false;

  /// Ответ вместо обычного, если тесту нужны свои числа
  Map<String, Object?>? answer;

  setUp(() {
    requests = [];
    hold = null;
    fails = false;
    answer = null;
    api.httpClient = MockClient((req) async {
      requests.add(req.url);
      if (hold != null) await hold!.future;
      if (fails) {
        return http.Response.bytes(
          utf8.encode(jsonEncode({'error': 'Сервер сломался'})),
          500,
        );
      }
      return http.Response.bytes(
        utf8.encode(jsonEncode(answer ?? _answer())),
        200,
      );
    });
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showViewsDialog(ctx, _cafe),
            child: const Text('открыть'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
  }

  testWidgets('цифры кафе и филиалов', (tester) async {
    await open(tester);
    expect(requests.single.path, '/api/super/cafes/cafe-1/views');
    expect(requests.single.queryParameters['days'], '30');

    // Сегодня — сумма по филиалам, «всего» — тоже
    expect(find.text('12'), findsOneWidget);
    expect(find.text('сегодня'), findsOneWidget);
    expect(find.text('16'), findsOneWidget); // 4 + 12 за период
    expect(find.text('420'), findsOneWidget); // 300 + 120 всего
    expect(find.text('Центр'), findsOneWidget);
    expect(find.text('сегодня 9 · всего 300'), findsOneWidget);
    expect(find.text('сегодня 3 · всего 120'), findsOneWidget);
  });

  testWidgets('столбик на каждый день окна, включая пустые', (tester) async {
    await open(tester);
    expect(find.byType(Tooltip), findsNWidgets(30));
    // Пустые дни в ответе не приходят, но в ряду обязаны быть
    expect(find.byTooltip('22.11 · 0'), findsOneWidget);
    expect(find.byTooltip('21.11 · 4'), findsOneWidget);
    expect(find.byTooltip('23.11 · 12'), findsOneWidget);

    // Края ряда подписаны: иначе непонятно, где тут сегодня
    expect(find.text('25.10'), findsOneWidget);
    expect(find.text('23.11'), findsOneWidget);
  });

  testWidgets('тысячи разбиты пробелом, а не слиты в кашу', (tester) async {
    answer = {
      'today': '2026-11-23',
      'days': [
        {'day': '2026-11-23', 'people': 1234, 'opens': 5000},
      ],
      'branches': [
        {
          'id': 'b1',
          'name': 'Центр',
          'views_today': 1234,
          'views_total': 9412,
        },
      ],
    };
    await open(tester);
    // Пробел неразрывный: обычный разорвал бы число переносом строки
    expect(find.text('9 412'), findsOneWidget);
    expect(find.text('1 234'), findsNWidgets(2)); // сегодня и за период
    expect(
      find.text('сегодня 1 234 · всего 9 412'),
      findsOneWidget,
    );
  });

  testWidgets('другой период — другой запрос и другой ряд', (tester) async {
    await open(tester);
    await tester.tap(find.text('7 дней'));
    await tester.pumpAndSettle();
    expect(requests.length, 2);
    expect(requests.last.queryParameters['days'], '7');
    expect(find.byType(Tooltip), findsNWidgets(7));
    expect(find.text('за 7 дней'), findsOneWidget);
  });

  testWidgets('пока грузится — полоска, а не пустое окно', (tester) async {
    hold = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showViewsDialog(ctx, _cafe),
            child: const Text('открыть'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('открыть'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(Tooltip), findsNothing);

    hold!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(Tooltip), findsNWidgets(30));
  });

  testWidgets('сервер ответил ошибкой — так и написано', (tester) async {
    fails = true;
    await open(tester);
    expect(find.textContaining('Не загрузилось'), findsOneWidget);
    expect(find.textContaining('Сервер сломался'), findsOneWidget);
    expect(find.byType(Tooltip), findsNothing);
  });
}
