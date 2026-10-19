import 'dart:convert';

import 'package:cafe_andalus_menu/api/api_client.dart';
import 'package:cafe_andalus_menu/menu_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Что сейчас «отвечает сервер»
enum Server { up, down, gone, unpaid }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var server = Server.up;
  var dishName = 'Плов';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    server = Server.up;
    dishName = 'Плов';
    api.httpClient = MockClient((req) async {
      switch (server) {
        case Server.down:
          throw http.ClientException('нет сети');
        case Server.gone:
          return http.Response.bytes(
              utf8.encode(jsonEncode({'error': 'Филиал не найден'})), 404);
        case Server.unpaid:
          return http.Response.bytes(
              utf8.encode(jsonEncode({'error': 'Меню временно недоступно', 'code': 'unpaid'})),
              403);
        case Server.up:
          final body = req.url.path.startsWith('/api/public/branch/')
              ? {'id': 'b1', 'slug': 'centr', 'name': 'Центр'}
              : {
                  'categories': [
                    {'id': 'c1', 'name': 'Горячее'},
                  ],
                  'products': [
                    {'id': 'd1', 'category_id': 'c1', 'name': dishName, 'price': 350},
                  ],
                };
          return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
      }
    });
  });

  String? dish(MenuStore s) =>
      s.data.value?.items.where((p) => !p.isGroup).map((p) => p.name).firstOrNull;

  test('свежее меню с сервера сохраняется на устройстве', () async {
    final s = MenuStore();
    await s.open('centr');
    expect(s.status.value, MenuResult.fresh);
    expect(s.data.value!.fromCache, isFalse);
    expect(dish(s), 'Плов');

    // Новый запуск без сети: меню берётся из сохранённой копии
    server = Server.down;
    final offline = MenuStore();
    await offline.open('centr');
    await Future<void>.delayed(Duration.zero);
    while (offline.refreshing.value) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(offline.status.value, MenuResult.offline);
    expect(offline.data.value!.fromCache, isTrue);
    expect(dish(offline), 'Плов');
  });

  test('«Обновить» один раз подтягивает новое блюдо', () async {
    final s = MenuStore();
    await s.open('centr');
    dishName = 'Новое блюдо';
    expect(await s.refresh(), MenuResult.fresh);
    expect(dish(s), 'Новое блюдо');
  });

  test('нет сети и копии нет — offlineNoCache, меню пустое', () async {
    server = Server.down;
    final s = MenuStore();
    await s.open('centr');
    expect(s.status.value, MenuResult.offlineNoCache);
    expect(s.data.value, isNull);
  });

  test('обрыв сети при «Обновить» оставляет показанное меню', () async {
    final s = MenuStore();
    await s.open('centr');
    server = Server.down;
    expect(await s.refresh(), MenuResult.offline);
    expect(dish(s), 'Плов');
    expect(s.data.value!.fromCache, isTrue);
  });

  test('филиал удалён (404) — копия стирается', () async {
    final s = MenuStore();
    await s.open('centr');
    server = Server.gone;
    expect(await s.refresh(), MenuResult.notFound);
    expect(s.data.value, isNull);

    // Даже без сети стёртое меню больше не показывается
    server = Server.down;
    final next = MenuStore();
    await next.open('centr');
    expect(next.status.value, MenuResult.offlineNoCache);
  });

  test('меню не оплачено — unpaid, копия стирается и без интернета не вернётся', () async {
    final s = MenuStore();
    await s.open('centr');
    server = Server.unpaid;
    expect(await s.refresh(), MenuResult.unpaid);
    expect(s.data.value, isNull);

    server = Server.down;
    final next = MenuStore();
    await next.open('centr');
    expect(next.status.value, MenuResult.offlineNoCache);
  });
}
