// Живое фото открывается нажатием по самому фото. Кнопки «Живое фото»
// больше нет: гость тычет в блюдо, а не ищет подпись под ним. Кнопка
// «Смотреть в 3D» остаётся — о 3D-модели по фото не догадаться.
//
// Живое фото открывается во встроенном браузере, которого в тестах нет,
// поэтому проверяем, что открывается именно оно, по маршруту — не давая
// странице построиться.
import 'package:cafe_andalus_menu/l10n/app_localizations.dart';
import 'package:cafe_andalus_menu/models/branch.dart';
import 'package:cafe_andalus_menu/models/product.dart';
import 'package:cafe_andalus_menu/theme/theme_config.dart';
import 'package:cafe_andalus_menu/widgets/live_photo/live_photo_view.dart';
import 'package:cafe_andalus_menu/widgets/product_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Product _dish({String image = 'http://x/lagman.jpg', String model = ''}) =>
    Product(
      id: 'p1',
      parentId: 'c1',
      name: 'Лагман',
      price: 250,
      imageUrl: image,
      modelUrl: model,
    );

/// Куда нас увели
class _Pushes extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route);
}

/// Открыть карточку блюда и вернуть наблюдателя с уже забытым открытием
/// самой карточки — дальше считаем только то, что открыл гость
Future<_Pushes> _openDish(WidgetTester tester, Product dish) async {
  // Узкий экран — как у гостя в телефоне (до 800 точек это «телефонная»
  // раскладка), но с запасом по ширине: шрифты в тестах не те, что в
  // приложении, и на точной ширине телефона строка цены не умещается
  tester.view.physicalSize = const Size(500, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final obs = _Pushes();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorObservers: [obs],
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 280,
            height: 380,
            child: LuxuryCard(
              product: dish,
              config: ThemeConfig.forStyle(const BranchStyle()),
              onAdd: (_, __, ___) => AddToCart.added,
            ),
          ),
        ),
      ),
    ),
  );
  // Переводы подгружаются не сразу: до этого на экране пусто
  await tester.pumpAndSettle();
  await tester.tap(find.byType(LuxuryCard));
  await tester.pumpAndSettle();
  expect(find.byType(Dialog), findsOneWidget);
  obs.pushed.clear();
  return obs;
}

/// Что открылось бы, не трогая саму страницу: строим только виджет
Widget _pushedPage(WidgetTester tester, _Pushes obs) {
  final route = obs.pushed.single;
  expect(route, isA<MaterialPageRoute<dynamic>>());
  return (route as MaterialPageRoute<dynamic>).builder(
    tester.element(find.byType(Dialog)),
  );
}

void main() {
  testWidgets('нажатие по фото открывает живое фото', (tester) async {
    final obs = await _openDish(tester, _dish());

    // Кнопки нет, а подсказка есть — иначе о живом фото никто не узнает
    expect(find.widgetWithText(ElevatedButton, 'Живое фото'), findsNothing);
    expect(find.text('Живое фото'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dish_photo')));
    expect(obs.pushed.length, 1);
    expect(_pushedPage(tester, obs), isA<LivePhotoView>());

    // Не даём встроенному браузеру открыться в тесте
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('у блюда без фото нажимать нечего', (tester) async {
    final obs = await _openDish(tester, _dish(image: ''));

    expect(find.text('Живое фото'), findsNothing);
    expect(find.byKey(const Key('dish_photo')), findsNothing);
    expect(obs.pushed, isEmpty);
  });

  testWidgets('кнопка 3D остаётся у блюда с моделью', (tester) async {
    await _openDish(tester, _dish(model: 'http://x/lagman.glb'));

    expect(
      find.widgetWithText(ElevatedButton, 'Смотреть в 3D'),
      findsOneWidget,
    );
    // И фото при этом по-прежнему живое
    expect(find.text('Живое фото'), findsOneWidget);
  });
}
