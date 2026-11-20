// Кнопка «назад» — системная на телефоне и кнопка браузера в вебе —
// приходит в приложение одним и тем же сигналом: `popRoute`. Проверяем
// не виджеты, а то, куда после него попадает гость.
//
// Переход «каталог → меню кафе» делается подменой экрана в `home`, а не
// Navigator.push, поэтому своей записи в истории браузера у него нет:
// без перехвата «назад» уводила гостя с сайта совсем, хотя вернуться
// было куда — в каталог.
import 'package:cafe_andalus_menu/config/current_branch.dart';
import 'package:cafe_andalus_menu/l10n/app_localizations.dart';
import 'package:cafe_andalus_menu/menu_store.dart';
import 'package:cafe_andalus_menu/models/branch.dart';
import 'package:cafe_andalus_menu/screens/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _branch = Branch(
  id: 'b1',
  slug: 'demo',
  name: 'Демо-кафе',
  orderWhatsapp: '996555112233',
);

/// Тот самый сигнал, который шлёт браузер по кнопке «назад».
Future<void> _back(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _openMenu(
  WidgetTester tester, {
  required bool fromCatalog,
  Size size = const Size(900, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  currentBranch.value = _branch;
  openedFromCatalog.value = fromCatalog;
  addTearDown(() {
    currentBranch.value = null;
    openedFromCatalog.value = false;
  });

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
  tester.takeException();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('пришёл из каталога: «назад» возвращает в каталог', (
    tester,
  ) async {
    await _openMenu(tester, fromCatalog: true);

    await _back(tester);

    // Ровно то же, что делает кнопка «Все кафе»: филиал закрыт, и `home`
    // показывает каталог
    expect(currentBranch.value, isNull);
    expect(openedFromCatalog.value, isFalse);
    expect(menuStore.slug, isNull);
  });

  // Кнопка «Все кафе» — тот же выход, что и «назад», поэтому и стоять
  // должна там, где её ищут: наверху, над названием кафе, а не в ряду
  // мелких иконок под ним
  // 400×900 — телефон: по умолчанию здесь 900×1600, а это, вопреки виду,
  // широкая вёрстка (порог — 800 по ширине), и мобильную шапку так не
  // проверить
  testWidgets('«Все кафе» — над названием кафе, узкий экран', (tester) async {
    await _openMenu(tester, fromCatalog: true, size: const Size(400, 900));

    expect(
      tester.getTopLeft(find.text('Все кафе')).dy,
      lessThan(tester.getTopLeft(find.text('Демо-кафе')).dy),
    );
  });

  testWidgets('«Все кафе» — над названием кафе, широкий экран', (tester) async {
    await _openMenu(
      tester,
      fromCatalog: true,
      size: const Size(1600, 1000),
    );

    expect(
      tester.getTopLeft(find.text('Все кафе')).dy,
      lessThan(tester.getTopLeft(find.text('Демо-кафе')).dy),
    );
  });

  testWidgets('пришёл по QR-коду: «назад» меню не трогает', (tester) async {
    await _openMenu(tester, fromCatalog: false);

    await _back(tester);

    // Возвращать некуда — чужой каталог гостю по QR не предлагаем.
    // «Назад» остаётся кнопкой браузера и уводит туда, откуда он пришёл
    expect(currentBranch.value, isNotNull);
  });
}
