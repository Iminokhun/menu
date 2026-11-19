import 'dart:convert';

import 'package:cafe_andalus_menu/api/api_client.dart';
import 'package:cafe_andalus_menu/models/branch.dart';
import 'package:cafe_andalus_menu/models/product.dart';
import 'package:cafe_andalus_menu/order/order_delivery.dart';
import 'package:cafe_andalus_menu/order/order_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Когда стоит повторять запись заказа на сервер, а когда — нет.
///
/// Гостю дозволено немного заказов за пять минут, и каждый повтор съедает
/// один из них. После отказа 400 второй заход придёт к тому же ответу,
/// после 429 — сделает только хуже. Повторять имеет смысл лишь тогда,
/// когда сервер не ответил или сам сломался.
const _branch = Branch(
  id: 'b1',
  slug: 'center',
  name: 'Андалус, Центр',
  orderWhatsapp: '996555112233',
  deliveryPrice: 150,
);

OrderDraft _draft() => OrderDraft(
  code: 'A7F3K2',
  type: OrderType.delivery,
  name: 'Азамат',
  phone: '0555112233',
  address: 'Киевская 95',
  deliveryPrice: 150,
  cart: [
    CartItem(
      product: Product(id: 'p1', parentId: '', name: 'Лагман', price: 280),
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int attempts;

  /// Сколько раз запрос дошёл до сервера и что из этого вышло.
  Future<OrderReceipt?> send(http.Response Function() reply) async {
    attempts = 0;
    api.httpClient = MockClient((req) async {
      attempts++;
      return reply();
    });
    return const WaLinkDelivery('996555112233').submit(
      _draft(),
      branch: _branch,
      lang: 'ru',
    );
  }

  http.Response reply(Map<String, Object?> body, int status) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status);

  test('отказ 400: второй раз не ходим', () async {
    final receipt = await send(
      () => reply({'error': 'Неверная позиция заказа'}, 400),
    );
    expect(attempts, 1);
    expect(receipt, isNull);
  });

  test('слишком часто (429): повтор только отнял бы заказ у гостя', () async {
    final receipt = await send(
      () => reply({'error': 'Слишком много заказов', 'code': 'too_often'}, 429),
    );
    expect(attempts, 1);
    expect(receipt, isNull);
  });

  test('сервер сломался (500): пробуем ещё раз', () async {
    final receipt = await send(() => reply({'error': 'Ошибка'}, 500));
    expect(attempts, 2);
    expect(receipt, isNull);
  });

  test('сети не было, со второго раза дошло', () async {
    attempts = 0;
    api.httpClient = MockClient((req) async {
      attempts++;
      if (attempts == 1) throw http.ClientException('нет сети');
      return reply({
        'id': 'o1',
        'code': 'A7F3K2',
        'items_total': 280,
        'delivery_total': 150,
        'total': 430,
        'missing': 0,
      }, 201);
    });
    final receipt = await const WaLinkDelivery('996555112233').submit(
      _draft(),
      branch: _branch,
      lang: 'ru',
    );
    expect(attempts, 2);
    expect(receipt?.total, 430);
  });
}
