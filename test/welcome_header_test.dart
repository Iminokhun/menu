// Лента кнопок под названием кафе: языки, поиск, обновление, «Оставить
// отзыв». Проверяем две вещи, которых не видно глазами на одном филиале:
// лента держится левого края и не ломается, сколько бы языков филиалу ни
// включили. Переключатель показывает до четырёх языков кнопками подряд —
// на узком телефоне это уже шире половины экрана.
import 'package:cafe_andalus_menu/config/current_branch.dart';
import 'package:cafe_andalus_menu/l10n/app_localizations.dart';
import 'package:cafe_andalus_menu/models/branch.dart';
import 'package:cafe_andalus_menu/screens/welcome_screen.dart';
import 'package:cafe_andalus_menu/widgets/lang_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Телефон и планшет: порог широкой вёрстки — 800 по ширине.
const _phone = Size(360, 800);
const _tablet = Size(1280, 900);

Future<void> _open(
  WidgetTester tester, {
  required List<String> langs,
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  currentBranch.value = Branch(
    id: 'b1',
    slug: 'demo',
    name: 'Демо-кафе',
    languages: langs,
  );
  addTearDown(() => currentBranch.value = null);

  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details.toString());
  addTearDown(() => FlutterError.onError = previous);

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

  // Картинки в тесте не загружаются — эту ошибку гасим и забываем
  tester.takeException();

  FlutterError.onError = previous;
  // Ловим все ошибки, а не одну: takeException хранит только первую, и
  // переполнение вёрстки, случившееся следом за ошибкой картинки,
  // тихо ушло бы в консоль, а тест бы прошёл
  final spill = errors.where((e) => e.contains('overflow')).toList();
  expect(spill, isEmpty, reason: spill.join(' | '));
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final langs in const [
    ['ru'],
    ['ru', 'en'],
    ['ru', 'en', 'ky', 'tr'],
    ['ru', 'en', 'ky', 'tr', 'kk', 'uz'],
  ]) {
    testWidgets('${langs.length} яз.: телефон — лента не вылезает за край', (
      tester,
    ) async {
      await _open(tester, langs: langs, size: _phone);
    });

    testWidgets('${langs.length} яз.: планшет — лента не вылезает за край', (
      tester,
    ) async {
      await _open(tester, langs: langs, size: _tablet);
    });
  }

  // Четыре языка — предел, до которого переключатель показывает их
  // кнопками подряд; на узком телефоне такой ряд занимает почти всю
  // ширину, и обновление честно уезжает вниз, а не за край
  testWidgets('четыре языка на узком телефоне: перенос, а не обрезка', (
    tester,
  ) async {
    await _open(
      tester,
      langs: const ['ru', 'en', 'ky', 'tr'],
      size: const Size(320, 800),
    );

    expect(
      tester.getTopLeft(find.byIcon(Icons.refresh_rounded)).dy,
      greaterThan(tester.getTopLeft(find.byType(LangSwitcher)).dy),
    );
  });

  testWidgets('языки и кнопки — у левого края, под названием', (tester) async {
    await _open(tester, langs: const ['ru', 'en'], size: _phone);

    final name = tester.getTopLeft(find.text('Демо-кафе'));
    final langs = tester.getTopLeft(find.byType(LangSwitcher));
    final search = tester.getTopLeft(find.byIcon(Icons.search_rounded));

    expect(langs.dx, name.dx);
    expect(langs.dy, greaterThan(name.dy));
    // Поиск — справа от языков и в той же строке, а не прижат к правому
    // краю экрана, как было раньше
    expect(search.dx, greaterThan(langs.dx));
    expect(search.dx, lessThan(_phone.width / 2));
  });
}
