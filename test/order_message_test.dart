import 'package:cafe_andalus_menu/models/branch.dart';
import 'package:cafe_andalus_menu/models/product.dart';
import 'package:cafe_andalus_menu/order/order_message.dart';
import 'package:flutter_test/flutter_test.dart';

Product _dish(
  String id,
  String name, {
  double price = 0,
  Map<String, Map<String, String>> i18n = const {},
}) => Product(
  id: id,
  parentId: '',
  name: name,
  price: price,
  i18n: i18n,
);

const _branch = Branch(
  id: 'b1',
  slug: 'center',
  name: 'Андалус, Центр',
  address: 'ул. Киевская 95, 2 этаж',
  orderWhatsapp: '996555112233',
  deliveryPrice: 150,
);

OrderDraft _draft({
  OrderType type = OrderType.delivery,
  String comment = '',
  double deliveryPrice = 150,
  List<CartItem>? cart,
}) => OrderDraft(
  code: 'A7F3',
  type: type,
  name: 'Азамат',
  phone: '0555112233',
  address: type == OrderType.delivery ? 'ул. Киевская 95, кв. 12' : '',
  comment: comment,
  deliveryPrice: deliveryPrice,
  cart:
      cart ??
      [
        CartItem(
          product: _dish('p1', 'Лагман', price: 280),
          portion: Portion(name: 'большая', price: 320),
          quantity: 2,
        ),
        CartItem(product: _dish('p2', 'Чай', price: 120)),
      ],
);

void main() {
  group('текст заказа', () {
    test('доставка — весь текст целиком', () {
      expect(
        buildOrderText(_draft(comment: '3 этаж, домофон'), branch: _branch),
        'Андалус, Центр\n'
        'Заказ A7F3\n'
        'ДОСТАВКА\n'
        '\n'
        'Имя: Азамат\n'
        'Телефон: 0555112233\n'
        'Адрес: *ул. Киевская 95, кв. 12*\n'
        '\n'
        '2 x Лагман (большая) — 640 с.\n'
        '1 x Чай — 120 с.\n'
        '\n'
        'Блюда: 760 с.\n'
        'Доставка: 150 с.\n'
        '*Итого: 910 с.*\n'
        '\n'
        'Комментарий: 3 этаж, домофон',
      );
    });

    test('самовывоз: вместо адреса гостя — адрес кафе, доставки нет', () {
      expect(
        buildOrderText(_draft(type: OrderType.pickup), branch: _branch),
        'Андалус, Центр\n'
        'Заказ A7F3\n'
        'САМОВЫВОЗ\n'
        '\n'
        'Имя: Азамат\n'
        'Телефон: 0555112233\n'
        'Забрать: Андалус, Центр — ул. Киевская 95, 2 этаж\n'
        '\n'
        '2 x Лагман (большая) — 640 с.\n'
        '1 x Чай — 120 с.\n'
        '\n'
        '*Итого: 760 с.*',
      );
    });

    test('бесплатная доставка — одна строка «Итого», без разбивки', () {
      final text = buildOrderText(_draft(deliveryPrice: 0), branch: _branch);
      expect(text, contains('Итого: 760 с.'));
      expect(text, isNot(contains('Блюда:')));
      expect(text, isNot(contains('Доставка:')));
    });

    test('название блюда — на языке кафе, а не гостя', () {
      final draft = _draft(
        cart: [
          CartItem(
            product: _dish(
              'p1',
              'Лагман',
              price: 280,
              i18n: {
                'en': {'name': 'Lagman'},
              },
            ),
          ),
        ],
      );
      final text = buildOrderText(draft, branch: _branch);
      expect(text, contains('1 x Лагман'));
      expect(text, isNot(contains('Lagman')));
    });

    test('подписи — на основном языке филиала', () {
      const english = Branch(
        id: 'b2',
        slug: 'en',
        name: 'Andalus',
        languages: ['en'],
        orderWhatsapp: '996555112233',
      );
      final text = buildOrderText(
        _draft(type: OrderType.pickup),
        branch: english,
      );
      expect(text, startsWith('Andalus\nOrder A7F3\nPICKUP\n'));
      expect(text, contains('Name: Азамат'));
    });

    test('подписи для языка без перевода — по-русски', () {
      const japanese = Branch(
        id: 'b3',
        slug: 'ja',
        name: 'Андалус',
        languages: ['ja'],
        orderWhatsapp: '996555112233',
      );
      expect(
        buildOrderText(_draft(type: OrderType.pickup), branch: japanese),
        startsWith('Андалус\nЗаказ A7F3\nСАМОВЫВОЗ\n'),
      );
    });

    test('длинный заказ обрезается, итог и контакты остаются', () {
      final cart = [
        for (var i = 0; i < 100; i++)
          CartItem(
            product: _dish('p$i', 'Блюдо с длинным названием $i', price: 100),
          ),
      ];
      final text = buildOrderText(_draft(cart: cart), branch: _branch);
      expect(text.length, lessThanOrEqualTo(1500));
      expect(text, contains('позиций'));
      // Обрезается список блюд, а не края: филиал сверху и итог снизу целы
      expect(text, startsWith('Андалус, Центр\nЗаказ A7F3\n'));
      expect(text, endsWith('*Итого: 10150 с.*'));
    });
  });

  group('ссылка wa.me', () {
    test('текст переживает кодирование: кириллица и переносы строк', () {
      final text = buildOrderText(_draft(comment: 'без лука'), branch: _branch);
      final uri = Uri.parse(waLink('996555112233', text));
      expect(uri.host, 'wa.me');
      expect(uri.path, '/996555112233');
      expect(uri.queryParameters['text'], text);
    });
  });

  group('телефоны', () {
    // Одна таблица примеров на обе стороны: такая же живёт в
    // server/tool/order_test.dart. Строгое правило — для номера кафе,
    // мягкое — для номера гостя
    const samples = [
      '+996 555 11 22 33',
      '0555112233',
      '(996)555-112233',
      '00996555112233',
      '996555112233',
      '',
      'abc',
      '12345678',
      '1234567890123456',
    ];

    test('номер кафе: строго, с кодом страны', () {
      expect(samples.map((s) => normalizeWaPhone(s)).toList(), [
        '996555112233',
        null, // код страны не задан — ведущий ноль не домысливаем
        '996555112233',
        '996555112233',
        '996555112233',
        '', // пусто — кафе выключило заказы
        null,
        null, // 8 цифр — мало
        null, // 16 цифр — много
      ]);
    });

    test('номер кафе: с кодом страны по умолчанию ноль дополняется', () {
      expect(
        normalizeWaPhone('0555112233', defaultCountryCode: '996'),
        '996555112233',
      );
    });

    test('номер гостя: мягко, местная запись принимается', () {
      expect(samples.map(cleanGuestPhone).toList(), [
        '996555112233',
        '0555112233',
        '996555112233',
        '00996555112233',
        '996555112233',
        null,
        null,
        null, // 8 цифр — мало даже здесь
        null,
      ]);
    });
  });

  // Шесть, а не четыре: на четырёх знаках два гостя в загруженном филиале
  // иногда получали один код, и сервер считал второй заказ повтором первого
  test('код заказа: 6 знаков без похожих друг на друга', () {
    for (var i = 0; i < 200; i++) {
      final code = newOrderCode();
      expect(code, matches(RegExp(r'^[A-Z0-9]{6}$')));
      expect(code, isNot(contains('0')));
      expect(code, isNot(contains('O')));
      expect(code, isNot(contains('1')));
      expect(code, isNot(contains('I')));
    }
  });

  group('позиции для сервера', () {
    test('только что и сколько — денег нет', () {
      final items = orderItemsJson(_draft().cart);
      expect(items, [
        {
          'product_id': 'p1',
          'portion': 'большая',
          'qty': 2,
          'name': 'Лагман',
        },
        {'product_id': 'p2', 'portion': '', 'qty': 1, 'name': 'Чай'},
      ]);
    });

    test('в теле запроса нет ни одной суммы', () {
      final body = _draft().toJson('b1', 'ru');
      expect(body.keys, isNot(contains('total')));
      expect(body.keys, isNot(contains('delivery_price')));
      expect(body['order_type'], 'delivery');
    });

    test('у самовывоза в черновике нет ни адреса, ни доставки', () {
      final draft = _draft(type: OrderType.pickup);
      expect(draft.address, '');
      expect(draft.deliveryTotal, 0);
      expect(draft.total, draft.itemsTotal);
    });
  });
}
