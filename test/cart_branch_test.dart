// Корзина принадлежит филиалу. Раньше она была одна на всё приложение:
// гость собирал заказ в одном кафе, возвращался в каталог, открывал другое
// — и складывал в ту же корзину чужие блюда. Заказ уходил на номер второго
// кафе, а его меню этих блюд не знает: сервер посчитал бы их по нулевой
// цене и пометил «перезвонить».
import 'dart:convert';

import 'package:cafe_andalus_menu/api/api_client.dart';
import 'package:cafe_andalus_menu/config/current_branch.dart';
import 'package:cafe_andalus_menu/l10n/app_localizations.dart';
import 'package:cafe_andalus_menu/menu_store.dart';
import 'package:cafe_andalus_menu/models/branch.dart';
import 'package:cafe_andalus_menu/models/product.dart';
import 'package:cafe_andalus_menu/screens/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

final _dish = Product(id: 'd1', parentId: '', name: 'Лагман', price: 280);

void fillCart() => globalCart.value = [CartItem(product: _dish)];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    globalCart.value = [];
    forgetCartBranch();
    // Меню филиала: slug из адреса, чтобы два филиала не путались
    api.httpClient = MockClient((req) async {
      final path = req.url.path;
      final body = path.startsWith('/api/public/branch/')
          ? {'id': path.split('/').last, 'slug': path.split('/').last, 'name': 'Кафе'}
          : {
              'categories': [
                {'id': 'c1', 'name': 'Горячее'},
              ],
              'products': [
                {'id': 'd1', 'category_id': 'c1', 'name': 'Лагман', 'price': 280},
              ],
            };
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
    });
  });

  tearDown(() {
    globalCart.value = [];
    forgetCartBranch();
  });

  group('корзина и филиал', () {
    test('другое кафе — корзина обнуляется', () async {
      final s = MenuStore();
      await s.open('maksat');
      fillCart();

      await s.open('andalus');
      expect(globalCart.value, isEmpty);
      // Гостю об этом говорят: молча исчезнувшая корзина выглядит поломкой
      expect(cartDropped.value, isTrue);
    });

    test('тот же филиал — корзина на месте', () async {
      final s = MenuStore();
      await s.open('maksat');
      fillCart();

      // Гость вышел в каталог и вернулся в то же кафе
      s.close();
      await s.open('maksat');
      expect(globalCart.value, hasLength(1));
      expect(cartDropped.value, isFalse);

      // И «Обновить» корзину не роняет
      await s.refresh();
      expect(globalCart.value, hasLength(1));
    });

    test('пустую корзину обнулять не о чем сообщать', () {
      bindCartToBranch('maksat');
      bindCartToBranch('andalus');
      expect(cartDropped.value, isFalse);
    });
  });

  group('сообщение гостю', () {
    setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

    Future<void> openWelcome(WidgetTester tester) async {
      currentBranch.value = const Branch(id: 'b1', slug: 'demo', name: 'Демо-кафе');
      addTearDown(() => currentBranch.value = null);
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('ru'),
          supportedLocales: [Locale('ru')],
          localizationsDelegates: [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: WelcomeScreen(),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      tester.takeException(); // картинки в тесте не грузятся
    }

    const notice = 'Это другое кафе — корзина очищена';

    testWidgets('корзину обнулили до открытия экрана — скажем сразу', (
      tester,
    ) async {
      // Так и бывает в жизни: филиал открывается из каталога, до первого
      // кадра нового экрана
      cartDropped.value = true;
      addTearDown(() => cartDropped.value = false);
      await openWelcome(tester);
      // Меню догружается, сообщение всплывает кадром позже
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(notice), findsOneWidget);
      // Флаг опущен — на следующем экране то же сообщение не всплывёт
      expect(cartDropped.value, isFalse);
    });

    testWidgets('сообщение показывается один раз', (tester) async {
      await openWelcome(tester);
      expect(find.text(notice), findsNothing);

      cartDropped.value = true;
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(notice), findsOneWidget);
    });
  });
}
