import 'package:cafe_andalus_menu/l10n/app_localizations.dart';
import 'package:cafe_andalus_menu/models/branch.dart';
import 'package:cafe_andalus_menu/models/product.dart';
import 'package:cafe_andalus_menu/order/order_delivery.dart';
import 'package:cafe_andalus_menu/order/order_message.dart';
import 'package:cafe_andalus_menu/screens/checkout_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Подставная отправка: ничего не открывает и никуда не ходит, только
/// запоминает, с чем её позвали.
class _FakeDelivery extends OrderDelivery {
  final OrderReceipt? receipt;
  int calls = 0;
  OrderDraft? last;

  _FakeDelivery({this.receipt});

  @override
  bool get canOrder => true;

  @override
  bool get opensWhatsapp => true;

  @override
  Future<OrderReceipt?> submit(
    OrderDraft draft, {
    required Branch branch,
    required String lang,
  }) async {
    calls++;
    last = draft;
    return receipt;
  }
}

const _branch = Branch(
  id: 'b1',
  slug: 'center',
  name: 'Андалус, Центр',
  address: 'ул. Киевская 95, 2 этаж',
  orderWhatsapp: '996555112233',
  deliveryPrice: 150,
);

Future<void> _open(WidgetTester tester, OrderDelivery delivery) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  globalCart.value = [
    CartItem(
      product: Product(id: 'p1', parentId: '', name: 'Лагман', price: 280),
      quantity: 2,
    ),
  ];
  addTearDown(() => globalCart.value = []);

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
        body: CheckoutSheet(branch: _branch, delivery: delivery),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  tester.takeException();
}

Future<void> _tapSend(WidgetTester tester) async {
  await tester.tap(find.text('ОТПРАВИТЬ В WHATSAPP'));
  await tester.pump(const Duration(seconds: 1));
  tester.takeException();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('кому доступен заказ', () {
    // Тесты идут не в браузере, значит kIsWeb == false — это ровно случай
    // планшета в зале: ссылку там открыть нечем (open_link_io.dart —
    // заглушка), поэтому и кнопки быть не должно
    test('вне браузера заказ недоступен, даже если номер задан', () {
      expect(OrderDelivery.forBranch(_branch).canOrder, isFalse);
    });

    test('без филиала — тоже недоступен', () {
      expect(OrderDelivery.forBranch(null).canOrder, isFalse);
    });

    test('филиал без номера: заказ недоступен', () {
      const noNumber = Branch(id: 'b', slug: 'b', name: 'Без номера');
      expect(OrderDelivery.forBranch(noNumber).canOrder, isFalse);
    });
  });

  testWidgets('пустые поля: ошибки у полей, заказ не уходит', (tester) async {
    final delivery = _FakeDelivery();
    await _open(tester, delivery);

    await _tapSend(tester);

    expect(find.text('Укажите имя'), findsOneWidget);
    expect(find.text('Укажите телефон'), findsOneWidget);
    expect(find.text('Укажите адрес доставки'), findsOneWidget);
    expect(delivery.calls, 0);
  });

  testWidgets('заполненная доставка уходит один раз и с адресом', (
    tester,
  ) async {
    final delivery = _FakeDelivery();
    await _open(tester, delivery);

    await tester.enterText(find.byType(TextField).at(0), 'Азамат');
    await tester.enterText(find.byType(TextField).at(1), '0555112233');
    await tester.enterText(find.byType(TextField).at(2), 'Киевская 95');
    await _tapSend(tester);

    expect(delivery.calls, 1);
    expect(delivery.last!.type, OrderType.delivery);
    expect(delivery.last!.address, 'Киевская 95');
    expect(delivery.last!.phone, '0555112233');
    expect(delivery.last!.deliveryTotal, 150);
    // Корзина очищена: иначе гость отправит второй такой же заказ
    expect(globalCart.value, isEmpty);
    expect(find.text('Открыть WhatsApp ещё раз'), findsNothing);
  });

  testWidgets('самовывоз: адреса не спрашивают, доставку не считают', (
    tester,
  ) async {
    final delivery = _FakeDelivery();
    await _open(tester, delivery);

    await tester.tap(find.text('Самовывоз'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Адрес доставки'), findsNothing);
    expect(find.textContaining('Андалус, Центр'), findsWidgets);
    expect(find.text('Доставка:'), findsNothing);

    await tester.enterText(find.byType(TextField).at(0), 'Азамат');
    await tester.enterText(find.byType(TextField).at(1), '0555112233');
    await _tapSend(tester);

    expect(delivery.calls, 1);
    expect(delivery.last!.type, OrderType.pickup);
    expect(delivery.last!.address, '');
    expect(delivery.last!.deliveryTotal, 0);
  });

  testWidgets('исчезнувшие блюда: гостю об этом говорят', (tester) async {
    final delivery = _FakeDelivery(
      receipt: const OrderReceipt(
        id: 'o1',
        code: 'A7F3',
        itemsTotal: 0,
        deliveryTotal: 150,
        total: 150,
        missing: 1,
      ),
    );
    await _open(tester, delivery);

    await tester.enterText(find.byType(TextField).at(0), 'Азамат');
    await tester.enterText(find.byType(TextField).at(1), '0555112233');
    await tester.enterText(find.byType(TextField).at(2), 'Киевская 95');
    await _tapSend(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('перезвонит'), findsOneWidget);
  });

  testWidgets('заказ не сохранился — гостя не пугаем, но говорим', (
    tester,
  ) async {
    final delivery = _FakeDelivery(); // receipt == null
    await _open(tester, delivery);

    await tester.enterText(find.byType(TextField).at(0), 'Азамат');
    await tester.enterText(find.byType(TextField).at(1), '0555112233');
    await tester.enterText(find.byType(TextField).at(2), 'Киевская 95');
    await _tapSend(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('WhatsApp'), findsWidgets);
    expect(find.textContaining('не сохранился'), findsOneWidget);
  });
}
