import 'package:cafe_andalus_menu/l10n/app_localizations.dart';
import 'package:cafe_andalus_menu/menu_store.dart';
import 'package:cafe_andalus_menu/models/branch.dart';
import 'package:cafe_andalus_menu/models/product.dart';
import 'package:cafe_andalus_menu/screens/menu_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Product group(String id, int order, [String parent = '']) => Product(
  id: id,
  parentId: parent,
  name: id,
  isGroup: true,
  sortOrder: order,
);

Product dish(String name, String category) =>
    Product(id: name, parentId: category, name: name, price: 100);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('подкатегории: «Все» и фильтр по одной', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    menuStore.data.value = MenuData(
      branch: const Branch(id: 'b', slug: 'b', name: 'Тест'),
      items: [
        group('Напитки', 1),
        group('Горячие', 1, 'Напитки'),
        group('Холодные', 2, 'Напитки'),
        dish('Капучино', 'Горячие'),
        dish('Лимонад', 'Холодные'),
      ],
      savedAt: DateTime(2026),
      fromCache: false,
    );
    addTearDown(() => menuStore.data.value = null);

    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('ru'),
        supportedLocales: [Locale('ru')],
        localizationsDelegates: [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: MenuScreen(initialCategoryId: 'Напитки'),
      ),
    );
    // Шрифты Google в тестах не скачиваются — это не ошибка экрана.
    // Подкатегории в меню написаны заглавными
    await tester.pump(const Duration(seconds: 1));
    tester.takeException();

    expect(find.text('ГОРЯЧИЕ'), findsWidgets);
    expect(find.text('ХОЛОДНЫЕ'), findsWidgets);
    expect(find.text('Капучино'), findsWidgets);
    expect(find.text('Лимонад'), findsWidgets);

    await tester.tap(find.text('ХОЛОДНЫЕ').first);
    await tester.pump(const Duration(seconds: 1));
    tester.takeException();
    expect(find.text('Лимонад'), findsWidgets);
    expect(find.text('Капучино'), findsNothing);
  });
}
