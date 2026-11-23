// Счётчик просмотров: отметка уходит один раз на открытие меню, метка
// устройства у гостя одна и та же, хозяин кафе себе посетителей не
// добавляет, и ни одна поломка отметки не мешает гостю читать меню.
import 'dart:convert';

import 'package:cafe_andalus_menu/api/api_client.dart';
import 'package:cafe_andalus_menu/menu_store.dart';
import 'package:cafe_andalus_menu/view_ping.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Тела всех отметок о просмотре, по порядку
  late List<Map<String, dynamic>> pings;
  var pingFails = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    forgetViewDevice();
    pings = [];
    pingFails = false;
    api.httpClient = MockClient((req) async {
      if (req.url.path == '/api/public/view') {
        if (pingFails) throw http.ClientException('нет сети');
        pings.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response('', 204);
      }
      if (req.url.path == '/api/auth/login') {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'token': 'тест',
              'user': {'id': 'u1', 'login': 'cafe', 'role': 'cafe_admin'},
            }),
          ),
          200,
        );
      }
      final body = req.url.path.startsWith('/api/public/branch/')
          ? {'id': 'b1', 'slug': 'centr', 'name': 'Центр'}
          : {
              'categories': [
                {'id': 'c1', 'name': 'Горячее'},
              ],
              'products': [
                {'id': 'd1', 'category_id': 'c1', 'name': 'Плов', 'price': 350},
              ],
            };
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
    });
  });

  // Вход живёт в одном ApiClient на всё приложение — после проверки с
  // входом следующая началась бы уже «вошедшей»
  tearDown(() => api.logout());

  test('открытие меню отмечается один раз, обновление — ни разу', () async {
    final s = MenuStore();
    await s.open('centr');
    await pumpEventQueue();
    expect(pings.length, 1);
    expect(pings.single['slug'], 'centr');
    expect((pings.single['device'] as String).length, 32);

    // «Обновить» в зале жмут весь день — это не новые гости
    await s.refresh();
    await pumpEventQueue();
    expect(pings.length, 1);
  });

  test('метка устройства у гостя одна и та же', () async {
    await MenuStore().open('centr');
    await pumpEventQueue();
    final first = pings.single['device'] as String;

    // Перезагрузка страницы: память пуста, но хранилище осталось
    forgetViewDevice();
    await MenuStore().open('centr');
    await pumpEventQueue();
    expect(pings.length, 2);
    expect(pings.last['device'], first);
  });

  test('другой филиал отмечается отдельно', () async {
    final s = MenuStore();
    await s.open('centr');
    await s.open('second');
    await pumpEventQueue();
    expect(pings.map((p) => p['slug']).toList(), ['centr', 'second']);
    // Тот же человек, два филиала — на сервере это два разных счёта
    expect(pings.first['device'], pings.last['device']);
  });

  test('вошедший в админку не считается гостем', () async {
    await api.login('cafe', 'secret');
    await MenuStore().open('centr');
    await pumpEventQueue();
    expect(pings, isEmpty);
  });

  test('упавшая отметка не мешает меню', () async {
    pingFails = true;
    final s = MenuStore();
    await s.open('centr');
    await pumpEventQueue();
    expect(s.status.value, MenuResult.fresh);
    expect(s.data.value, isNotNull);
    expect(pings, isEmpty);
  });
}
