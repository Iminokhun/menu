// Админка на телефоне: ни один раздел не должен вылезать за край экрана.
//
// Проверяем пиксели, а не запросы: админку писали под планшет-киоск, и
// каждое переполнение здесь — это кусок экрана, до которого владелец с
// телефона не дотянется. Ошибки собираем через FlutterError.onError, а не
// takeException: тот хранит только первую, а картинок в админке много —
// переполнение ушло бы в консоль, а тест бы прошёл.
//
// Экраны поднимаем поодиночке нарочно: IndexedStack не раскладывает
// скрытых детей, поэтому один тест оболочки проверил бы только открытый
// раздел, а падение не показывало бы пальцем на файл.
import 'dart:convert';

import 'package:cafe_andalus_menu/api/api_client.dart';
import 'package:cafe_andalus_menu/config/current_branch.dart';
import 'package:cafe_andalus_menu/models/branch.dart';
import 'package:cafe_andalus_menu/screens/admin/admin_categories_screen.dart';
import 'package:cafe_andalus_menu/screens/admin/admin_orders_screen.dart';
import 'package:cafe_andalus_menu/screens/admin/admin_products_screen.dart';
import 'package:cafe_andalus_menu/screens/admin/admin_reviews_screen.dart';
import 'package:cafe_andalus_menu/screens/admin/admin_shell.dart';
import 'package:cafe_andalus_menu/screens/admin/admin_shop_screen.dart';
import 'package:cafe_andalus_menu/screens/admin/admin_style_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Телефон в портрете, крупный телефон, тот же телефон в альбоме и
/// планшет-киоск.
const _phone = Size(360, 800);
const _bigPhone = Size(390, 844);
const _landscape = Size(844, 390);
const _desktop = Size(1400, 1000);

const _branch = Branch(
  id: 'b1',
  slug: 'center',
  name: 'Андалус, Центральный',
  reviewsEnabled: true,
  languages: ['ru', 'en', 'ky'],
);

// Данные нарочно длинные: короткие строки помещаются везде и ничего не
// ловят. Два филиала — чтобы появились «Копировать в другой филиал»,
// «Новый филиал» и выбор «сохранить во все филиалы».

Map<String, Object?> _me() => {
  'id': 'u1',
  'login': 'demo',
  'role': 'cafe_admin',
  'menu_url': 'https://menu.prostoerp.com',
  'cafe': {
    'id': 'c1',
    'name': 'Андалус',
    'max_branches': 3,
    'branch_count': 2,
    'plan': 'paid',
    'paid_until': '2026-12-31',
    'access': 'ending',
    'days_left': 3,
    'billing_contact': 'WhatsApp 0555 11 22 33',
  },
};

List<Map<String, Object?>> _orders() => [
  {
    'id': 'o1',
    'code': 'A17',
    'order_type': 'delivery',
    'status': 'new',
    'guest_name': 'Чолпонбек Абдыкадыров',
    'guest_phone': '0555112233',
    'guest_phone_wa': '996555112233',
    'address': 'ул. Киевская 95, кв. 12, второй подъезд',
    'comment': 'Позвонить за десять минут',
    'created_at': '2026-11-21 12:34:56',
    'items': [
      {
        'name': 'Лагман по-уйгурски',
        'portion': 'большая',
        'price': 320,
        'qty': 2,
        'sum': 640,
      },
    ],
    'items_total': 640,
    'delivery_total': 150,
    'total': 790,
  },
];

List<Map<String, Object?>> _reviews() => [
  {
    'id': 'r1',
    'rating': 4,
    'waiter': 'Айгуль',
    'table_no': '12',
    'comment': 'Всё понравилось, но горячее ждали почти сорок минут',
    'created_at': '2026-11-21 12:00:00',
  },
  {
    'id': 'r2',
    'rating': 5,
    'waiter': 'Нурсултан',
    'table_no': '3',
    'comment': 'Спасибо',
    'created_at': '2026-11-21 13:00:00',
  },
];

List<Map<String, Object?>> _categories() => [
  {
    'id': 'c1',
    'name': 'Горячие блюда',
    'parent_id': null,
    'sort_order': 0,
    'image_url': '',
  },
  {
    'id': 'c2',
    'name': 'Супы и бульоны',
    'parent_id': 'c1',
    'sort_order': 1,
    'image_url': '',
  },
];

List<Map<String, Object?>> _products() => [
  {
    'id': 'p1',
    'category_id': 'c1',
    'name': 'Лагман по-уйгурски с бараниной',
    'price': 350,
    'is_visible': true,
    'portions': [],
    'image_url': '',
    'description': '',
    'model_url': 'https://example.com/plov.glb',
  },
  {
    'id': 'p2',
    'category_id': 'c2',
    'name': 'Шурпа',
    'price': 250,
    'is_visible': false,
    'portions': [],
    'image_url': '',
    'description': '',
  },
];

List<Map<String, Object?>> _branches() => [
  {
    'id': 'b1',
    'name': 'Андалус, Центральный',
    'slug': 'center',
    'languages': 'ru,en,ky',
    'card_size': 'large',
  },
  {'id': 'b2', 'name': 'Андалус на Чуй', 'slug': 'chui'},
];

void _mockServer() {
  api.me = Me.fromJson(_me());
  api.httpClient = MockClient((req) async {
    final Object body = switch (req.url.path) {
      '/api/me' => _me(),
      '/api/admin/orders' => _orders(),
      '/api/admin/reviews' => _reviews(),
      '/api/admin/reviews/waiters' => [
        {'waiter': 'Айгуль', 'count': 12},
        {'waiter': 'Нурсултан', 'count': 4},
      ],
      '/api/admin/categories' => _categories(),
      '/api/admin/products' => _products(),
      '/api/admin/branches' => _branches(),
      _ => <Object?>[],
    };
    return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
  });
}

/// Поднять виджет заданного размера и вернуть все переполнения вёрстки.
Future<List<String>> _open(
  WidgetTester tester,
  Size size,
  Widget screen,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  _mockServer();
  currentBranch.value = _branch;
  addTearDown(() => currentBranch.value = null);

  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details.toString());
  addTearDown(() => FlutterError.onError = previous);

  // Scaffold — как в оболочке: без него Column экрана остаётся без
  // ограничения по высоте, и тест ловит выдуманное переполнение
  await tester.pumpWidget(
    MaterialApp(home: screen is AdminShell ? screen : Scaffold(body: screen)),
  );
  await tester.pump(const Duration(seconds: 1));

  FlutterError.onError = previous;
  // Картинки в тесте не загружаются — эту ошибку гасим и забываем
  tester.takeException();
  return errors.where((e) => e.contains('overflow')).toList();
}

Widget _screen(int i) => switch (i) {
  0 => const AdminOrdersScreen(active: true),
  1 => const AdminReviewsScreen(active: true),
  2 => const AdminCategoriesScreen(),
  3 => const AdminProductsScreen(),
  4 => const AdminShopScreen(),
  _ => const AdminStyleScreen(),
};

const _names = [
  'заказы',
  'отзывы',
  'категории',
  'товары',
  'филиал',
  'оформление',
];

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final (sizeName, size) in const [
    ('360×800', _phone),
    ('390×844', _bigPhone),
    ('альбом 844×390', _landscape),
  ]) {
    for (var i = 0; i < _names.length; i++) {
      testWidgets('$sizeName: ${_names[i]} — без переполнений', (tester) async {
        final spill = await _open(tester, size, _screen(i));
        expect(spill, isEmpty, reason: spill.join('\n---\n'));
      });
    }
  }

  group('диалоги на телефоне', () {
    // Формы правки — то, ради чего в админку заходят. Раньше каждая
    // носила свою ширину (340, 420, 440, 520) и рассчитывала на монитор
    for (final (name, screen) in const [
      ('товар', 3),
      ('категория', 2),
    ]) {
      testWidgets('$name: форма влезает в экран', (tester) async {
        await _open(tester, _phone, _screen(screen));
        await tester.tap(find.text('Добавить'));
        await tester.pump(const Duration(seconds: 1));

        final errors = <String>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (details) => errors.add(details.toString());
        await tester.pump(const Duration(milliseconds: 300));
        FlutterError.onError = previous;
        tester.takeException();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          tester.getSize(find.byType(AlertDialog)).width,
          lessThanOrEqualTo(360),
        );
        final spill = errors.where((e) => e.contains('overflow')).toList();
        expect(spill, isEmpty, reason: spill.join(' | '));
      });
    }
  });

  group('оболочка', () {
    testWidgets('телефон: нижняя панель вместо боковой колонки', (
      tester,
    ) async {
      final spill = await _open(tester, _phone, const AdminShell());
      expect(spill, isEmpty, reason: spill.join('\n---\n'));

      expect(find.byKey(const Key('nav_orders')), findsOneWidget);
      expect(find.byKey(const Key('nav_more')), findsOneWidget);
      // Панель — внизу и невысокая. Проверяем это числом: без
      // mainAxisSize.min кнопка растягивалась на весь экран, переполнения
      // при этом не было и тест бы прошёл
      final bar = tester.getRect(find.byKey(const Key('nav_orders')));
      expect(bar.height, lessThan(80));
      expect(bar.bottom, closeTo(800, 16));
      // Боковой колонки нет: «Оформление» живёт в шторке «Ещё»
      expect(find.text('Оформление'), findsNothing);
      // Видно, какой филиал правим
      expect(find.text('Андалус, Центральный'), findsOneWidget);
    });

    testWidgets('телефон: «Ещё» открывает редкие разделы', (tester) async {
      await _open(tester, _phone, const AdminShell());

      await tester.tap(find.byKey(const Key('nav_more')));
      await tester.pumpAndSettle();
      for (final item in [
        'Категории',
        'Филиал',
        'Оформление',
        'Сменить филиал',
        'Выйти из админки',
      ]) {
        expect(find.text(item), findsOneWidget, reason: item);
      }

      await tester.tap(find.text('Оформление'));
      await tester.pumpAndSettle();
      tester.takeException();
      // Шторка закрылась, а четвёртая кнопка панели подписана открытым
      // разделом — иначе на телефоне не видно, где ты находишься
      expect(find.text('Сменить филиал'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('nav_more')),
          matching: find.text('Оформление'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('планшет-киоск: боковая колонка цела', (tester) async {
      final spill = await _open(tester, _desktop, const AdminShell());
      expect(spill, isEmpty, reason: spill.join('\n---\n'));

      expect(find.byKey(const Key('nav_more')), findsNothing);
      // Все шесть разделов — кнопками слева, как и было
      for (final item in [
        'Заказы',
        'Отзывы',
        'Категории',
        'Товары',
        'Филиал',
        'Оформление',
      ]) {
        expect(find.text(item), findsWidgets, reason: item);
      }
      expect(find.text('Выйти'), findsOneWidget);
    });
  });
}
