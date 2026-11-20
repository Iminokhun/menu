// Форма отзыва: без оценки отправлять нечего — форма просит звёзды, но
// кнопку не блокирует, — с оценкой уходит ровно один отзыв, и гость при
// этом никуда со страницы не уходит.
import 'package:cafe_andalus_menu/l10n/app_localizations.dart';
import 'package:cafe_andalus_menu/models/branch.dart';
import 'package:cafe_andalus_menu/review/review_sender.dart';
import 'package:cafe_andalus_menu/screens/review_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _branch = Branch(
  id: 'b1',
  slug: 'center',
  name: 'Андалус, Центр',
  reviewsEnabled: true,
);

/// Подставной отправитель: ничего не открывает и никуда не ходит, только
/// запоминает, с чем его позвали.
class _FakeSender extends ReviewSender {
  int calls = 0;
  ReviewDraft? last;
  final bool ok;

  _FakeSender({this.ok = true}) : super(canReview: true);

  @override
  Future<bool> submit(
    ReviewDraft draft, {
    required Branch branch,
    required String lang,
  }) async {
    calls++;
    last = draft;
    return ok;
  }
}

Future<void> _open(WidgetTester tester, ReviewSender sender) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: Scaffold(
        body: ReviewDialog(branch: _branch, sender: sender),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  tester.takeException();
}

/// Нажать на [n]-ю звезду: пустые звёзды идут подряд слева направо
Future<void> _tapStar(WidgetTester tester, int n) async {
  await tester.tap(find.byIcon(Icons.star_outline_rounded).at(n - 1));
  await tester.pump(const Duration(milliseconds: 300));
}

ElevatedButton _sendButton(WidgetTester tester) =>
    tester.widget<ElevatedButton>(find.byType(ElevatedButton));

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  // Отправка запоминает отзыв на устройстве — хранилище нужно подставное
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('без оценки: кнопка живая, просит звёзды, отзыв не уходит', (
    tester,
  ) async {
    const ask = 'Сначала поставьте оценку звёздами';
    final sender = _FakeSender();
    await _open(tester, sender);

    // Кнопка нажимается всегда: серая кнопка молчит о причине
    expect(_sendButton(tester).onPressed, isNotNull);
    // Пустая форма ни в чём не провинилась — просьбы до нажатия нет
    expect(find.text(ask), findsNothing);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(const Duration(seconds: 1));

    expect(sender.calls, 0);
    expect(find.text(ask), findsOneWidget);
    // Форма осталась на месте, «спасибо» не показано
    expect(find.text('ОТПРАВИТЬ ОТЗЫВ'), findsOneWidget);

    // Звезда поставлена — просьба уходит сразу, а не после нажатия
    await _tapStar(tester, 4);
    expect(find.text(ask), findsNothing);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(const Duration(seconds: 1));
    expect(sender.calls, 1);
    expect(sender.last?.rating, 4);
  });

  testWidgets('оценка и поля уходят ровно одним отзывом', (tester) async {
    final sender = _FakeSender();
    await _open(tester, sender);

    await _tapStar(tester, 3);
    expect(_sendButton(tester).onPressed, isNotNull);

    await tester.enterText(find.byType(TextField).at(0), '  Айгуль  ');
    await tester.enterText(find.byType(TextField).at(1), '12');
    await tester.enterText(find.byType(TextField).at(2), 'Всё понравилось');
    await tester.pump();

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(const Duration(seconds: 1));

    expect(sender.calls, 1);
    expect(sender.last?.rating, 3);
    // Пробелы по краям срезаются здесь, а не на сервере
    expect(sender.last?.waiter, 'Айгуль');
    expect(sender.last?.tableNo, '12');
    expect(sender.last?.comment, 'Всё понравилось');
  });

  testWidgets('в номер стола буквы не вводятся', (tester) async {
    final sender = _FakeSender();
    await _open(tester, sender);

    await _tapStar(tester, 4);
    // Гость пытается вписать «VIP-2»: в поле останутся только цифры
    await tester.enterText(find.byType(TextField).at(1), 'VIP-2');
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(const Duration(seconds: 1));

    expect(sender.last?.tableNo, '2');
  });

  testWidgets('после отправки — спасибо, и никакого WhatsApp', (
    tester,
  ) async {
    final sender = _FakeSender();
    await _open(tester, sender);

    expect(find.text('ОТПРАВИТЬ ОТЗЫВ'), findsOneWidget);
    await _tapStar(tester, 5);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Спасибо! Кафе увидит ваш отзыв'), findsOneWidget);
    // Ни «открыть WhatsApp ещё раз», ни любой другой кнопки, уводящей
    // гостя со страницы, тут быть не должно
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('сервер не принял — спокойное примечание, не ошибка', (
    tester,
  ) async {
    final sender = _FakeSender(ok: false);
    await _open(tester, sender);

    await _tapStar(tester, 1);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Отзыв не сохранился. Попробуйте позже'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
