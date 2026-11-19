// Форма отзыва: без оценки отправлять нечего, с оценкой уходит ровно один
// отзыв, а что видит гость после отправки — зависит от того, был ли номер
// WhatsApp у филиала.
import 'package:cafe_andalus_menu/l10n/app_localizations.dart';
import 'package:cafe_andalus_menu/models/branch.dart';
import 'package:cafe_andalus_menu/review/review_message.dart';
import 'package:cafe_andalus_menu/review/review_sender.dart';
import 'package:cafe_andalus_menu/screens/review_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _branch = Branch(
  id: 'b1',
  slug: 'center',
  name: 'Андалус, Центр',
  reviewWhatsapp: '996555112233',
  reviewsEnabled: true,
);

/// Подставной отправитель: ничего не открывает и никуда не ходит, только
/// запоминает, с чем его позвали.
class _FakeSender extends ReviewSender {
  int calls = 0;
  ReviewDraft? last;
  final bool ok;

  _FakeSender({super.phone = '', this.ok = true}) : super(canReview: true);

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
        body: ReviewSheet(branch: _branch, sender: sender),
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

  testWidgets('без оценки кнопка не нажимается и отзыв не уходит', (
    tester,
  ) async {
    final sender = _FakeSender();
    await _open(tester, sender);

    expect(_sendButton(tester).onPressed, isNull);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(const Duration(seconds: 1));
    expect(sender.calls, 0);
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

  testWidgets('нет номера: ни WhatsApp, ни кнопки «открыть ещё раз»', (
    tester,
  ) async {
    final sender = _FakeSender();
    await _open(tester, sender);

    await _tapStar(tester, 5);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Спасибо! Кафе увидит ваш отзыв'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('есть номер: подсказка про WhatsApp и запасная кнопка', (
    tester,
  ) async {
    final sender = _FakeSender(phone: '996555112233');
    await _open(tester, sender);

    expect(find.text('ОТПРАВИТЬ В WHATSAPP'), findsOneWidget);
    await _tapStar(tester, 4);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.text('Отзыв готов. Нажмите «Отправить» в WhatsApp'),
      findsOneWidget,
    );
    expect(find.byType(OutlinedButton), findsOneWidget);
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
