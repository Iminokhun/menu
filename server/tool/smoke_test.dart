// Проверка API на живом сервере: права, лимит филиалов, блокировка.
// Запуск: dart run tool/smoke_test.dart <superLogin> <superPassword> [baseUrl]
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:menu_server/billing.dart';

late String base;
var failures = 0;

Future<(int, dynamic)> call(
  String method,
  String path, {
  String? token,
  Object? body,
  List<int>? bytes,
}) async {
  final req = http.Request(method, Uri.parse('$base$path'));
  if (token != null) req.headers['authorization'] = 'Bearer $token';
  if (body != null) {
    req.headers['content-type'] = 'application/json';
    req.body = jsonEncode(body);
  }
  if (bytes != null) req.bodyBytes = bytes;
  final res = await http.Response.fromStream(await req.send());
  final text = utf8.decode(res.bodyBytes);
  return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
}

void expect(String what, bool ok, [Object? info]) {
  stdout.writeln('${ok ? 'OK  ' : 'FAIL'} $what${ok ? '' : '  → $info'}');
  if (!ok) failures++;
}

Future<void> main(List<String> args) async {
  base = args.length > 2 ? args[2] : 'http://localhost:8090';
  final stamp = DateTime.now().millisecondsSinceEpoch;

  var (s, r) = await call('GET', '/api/health');
  expect(
    'health: сервер жив, база и файлы на месте',
    s == 200 && r['status'] == 'ok' && r['db'] == 'ok' && r['files'] == 'ok',
    r,
  );

  (s, r) = await call(
    'POST',
    '/api/auth/login',
    body: {'login': args[0], 'password': args[1]},
  );
  expect('вход superadmin', s == 200, r);
  final st = r['token'] as String;

  (s, r) = await call(
    'POST',
    '/api/auth/login',
    body: {'login': args[0], 'password': 'wrong'},
  );
  expect('неверный пароль → 401', s == 401, r);

  // Два кафе: A с лимитом 1, B с лимитом 2
  (s, r) = await call(
    'POST',
    '/api/super/cafes',
    token: st,
    body: {'name': 'Тест A $stamp', 'max_branches': 1},
  );
  expect('создать кафе A', s == 201, r);
  final cafeA = r['id'];
  (s, r) = await call(
    'POST',
    '/api/super/cafes',
    token: st,
    body: {'name': 'Тест B $stamp', 'max_branches': 2},
  );
  final cafeB = r['id'];

  (s, r) = await call(
    'POST',
    '/api/super/cafes/$cafeA/users',
    token: st,
    body: {'login': 'a$stamp', 'password': 'pass1234'},
  );
  expect('логин для кафе A', s == 201, r);
  (s, r) = await call(
    'POST',
    '/api/super/cafes/$cafeB/users',
    token: st,
    body: {'login': 'b$stamp', 'password': 'pass1234'},
  );
  final userB = r['id'];
  (s, r) = await call(
    'POST',
    '/api/super/cafes/$cafeA/users',
    token: st,
    body: {'login': 'A$stamp', 'password': 'pass1234'},
  );
  expect('повторный логин (без учёта регистра) → 409', s == 409, r);
  (s, r) = await call(
    'POST',
    '/api/super/cafes/$cafeA/users',
    token: st,
    body: {'login': 'x$stamp', 'password': '123'},
  );
  expect('короткий пароль → 400', s == 400, r);

  (s, r) = await call(
    'POST',
    '/api/auth/login',
    body: {'login': 'a$stamp', 'password': 'pass1234'},
  );
  final ta = r['token'];
  (s, r) = await call(
    'POST',
    '/api/auth/login',
    body: {'login': 'b$stamp', 'password': 'pass1234'},
  );
  final tb = r['token'];

  (s, r) = await call('GET', '/api/me', token: ta);
  expect(
    'me: роль cafe_admin, лимит 1, адрес меню',
    s == 200 &&
        r['role'] == 'cafe_admin' &&
        r['cafe']['max_branches'] == 1 &&
        (r['menu_url'] as String).startsWith('http'),
    r,
  );
  // Адрес меню — MENU_URL сервера, а без него адрес самого сервера
  final menuUrl = r['menu_url'];

  // Первый филиал появляется вместе с кафе
  (s, r) = await call('GET', '/api/admin/branches', token: ta);
  final slugA = 'test-a-$stamp';
  expect(
    'кафе A: первый филиал создан сам, со ссылкой QR',
    s == 200 &&
        r.length == 1 &&
        r[0]['slug'] == slugA &&
        r[0]['qr_url'] == '$menuUrl/?branch=$slugA',
    r,
  );
  expect(
    'у нового кафе один язык — русский',
    (r[0]['languages'] as List).join(',') == 'ru',
    r[0]['languages'],
  );
  final branchA = r[0]['id'];
  (s, r) = await call(
    'POST',
    '/api/admin/branches',
    token: ta,
    body: {'name': 'Второй', 'slug': 'a2-$stamp'},
  );
  expect('кафе A: второй филиал сверх лимита → 403', s == 403, r);

  (s, r) = await call(
    'POST',
    '/api/admin/branches',
    token: tb,
    body: {'name': 'Б', 'slug': slugA},
  );
  expect('занятый slug → 409', s == 409, r);

  // Адрес, который сломал бы ссылку QR-кода, не сохраняется
  for (final bad in ['Центр 2', 'a&b', 'a/b', 'x#y', '-a', 'a--b', 'a b']) {
    (s, r) = await call(
      'PATCH',
      '/api/admin/branches/$branchA',
      token: ta,
      body: {'slug': bad},
    );
    expect('адрес «$bad» → 400', s == 400, r);
  }
  (s, r) = await call(
    'POST',
    '/api/admin/branches',
    token: tb,
    body: {'name': 'Б', 'slug': 'Центр 2'},
  );
  expect('новый филиал с адресом «Центр 2» → 400', s == 400, r);
  (s, r) = await call(
    'PATCH',
    '/api/admin/branches/$branchA',
    token: ta,
    body: {'slug': 'Test-A-$stamp-X'},
  );
  expect(
    'большие буквы в адресе становятся маленькими, ссылка QR следом',
    s == 200 &&
        r['slug'] == 'test-a-$stamp-x' &&
        r['qr_url'] == '$menuUrl/?branch=test-a-$stamp-x',
    r,
  );
  (s, r) = await call(
    'PATCH',
    '/api/admin/branches/$branchA',
    token: ta,
    body: {'slug': slugA},
  );

  // Оформление меню филиала
  (s, r) = await call(
    'PATCH',
    '/api/admin/branches/$branchA',
    token: ta,
    body: {
      'theme': 'porcelain',
      'accent': '#c0392b',
      'bg_url': '$base/uploads/x/bg.jpg',
      'card_size': 'large',
      'corners': 'round',
      'title_font': 'playfair',
    },
  );
  expect(
    'оформление сохраняется, цвет — заглавными, фон — полным адресом',
    s == 200 &&
        r['theme'] == 'porcelain' &&
        r['accent'] == '#C0392B' &&
        r['bg_url'] == '$base/uploads/x/bg.jpg' &&
        r['card_size'] == 'large' &&
        r['corners'] == 'round' &&
        r['title_font'] == 'playfair',
    r,
  );
  (s, r) = await call('GET', '/api/public/branch/$slugA');
  expect('гость получает оформление', s == 200 && r['theme'] == 'porcelain', r);
  for (final (field, bad) in [
    ('theme', 'neon'),
    ('accent', '#12345'),
    ('accent', 'red'),
    ('card_size', 'huge'),
    ('corners', 5),
    ('title_font', 'comic-sans'),
  ]) {
    (s, r) = await call(
      'PATCH',
      '/api/admin/branches/$branchA',
      token: ta,
      body: {field: bad},
    );
    expect('оформление: $field = $bad → 400', s == 400, r);
  }
  (s, r) = await call(
    'PATCH',
    '/api/admin/branches/$branchA',
    token: ta,
    body: {
      'theme': '',
      'accent': '',
      'bg_url': '',
      'card_size': '',
      'corners': '',
      'title_font': '',
    },
  );
  expect(
    'сброс оформления «по умолчанию»',
    s == 200 && r['theme'] == '' && r['accent'] == '',
    r,
  );
  (s, r) = await call(
    'POST',
    '/api/admin/branches',
    token: tb,
    body: {'name': 'Центр'},
  );
  expect(
    'филиал без адреса: адрес из названий кафе и филиала',
    s == 201 && r['slug'] == 'test-b-$stamp-centr',
    r,
  );
  final branchB = r['id'];

  (s, r) = await call(
    'POST',
    '/api/admin/categories',
    token: ta,
    body: {'branch_id': branchA, 'name': 'Супы'},
  );
  expect('категория', s == 201, r);
  final catA = r['id'];

  (s, r) = await call(
    'POST',
    '/api/admin/categories',
    token: ta,
    body: {'branch_id': branchA, 'name': 'Холодные', 'parent_id': catA},
  );
  expect('подкатегория', s == 201 && r['parent_id'] == catA, r);
  final subA = r['id'];
  (s, r) = await call(
    'POST',
    '/api/admin/categories',
    token: ta,
    body: {'branch_id': branchA, 'name': 'x', 'parent_id': subA},
  );
  expect('подкатегория в подкатегории → 400', s == 400, r);
  (s, r) = await call(
    'POST',
    '/api/admin/categories',
    token: ta,
    body: {'branch_id': branchA, 'name': 'Напитки'},
  );
  final catDrinks = r['id'];
  (s, r) = await call(
    'PATCH',
    '/api/admin/categories/$catA',
    token: ta,
    body: {'parent_id': catDrinks},
  );
  expect('категорию с подкатегориями — в подкатегории → 400', s == 400, r);
  (s, r) = await call(
    'PATCH',
    '/api/admin/categories/$subA',
    token: ta,
    body: {'parent_id': ''},
  );
  expect(
    'подкатегория → основная (пустой parent_id)',
    s == 200 && r['parent_id'] == null,
    r,
  );
  (s, r) = await call(
    'PATCH',
    '/api/admin/categories/$subA',
    token: ta,
    body: {'parent_id': catDrinks},
  );
  expect(
    'перенос в другую категорию',
    s == 200 && r['parent_id'] == catDrinks,
    r,
  );

  (s, r) = await call(
    'POST',
    '/api/admin/upload?ext=png&prefix=prod_',
    token: ta,
    bytes: utf8.encode('fake image'),
  );
  expect('текст под видом фото → 400', s == 400, r);

  // Большое фото с телефона уменьшается до 1600 px и пережимается в JPEG
  // Шум, как у настоящего снимка: гладкий градиент в PNG и так весит мало
  final noise = Random(1);
  final bigPhoto = img.Image(width: 3000, height: 2000);
  for (final p in bigPhoto) {
    p
      ..r = p.x * 255 ~/ 3000
      ..g = noise.nextInt(256)
      ..b = 128;
  }
  final bigPng = img.encodePng(bigPhoto);
  (s, r) = await call(
    'POST',
    '/api/admin/upload?ext=png&prefix=prod_',
    token: ta,
    bytes: bigPng,
  );
  expect('загрузка фото', s == 201 && (r['url'] as String).endsWith('.jpg'), r);
  final url = r['url'];
  final shrunk = img.decodeImage((await http.get(Uri.parse(url))).bodyBytes);
  expect(
    'фото 3000×2000 сохранено как 1600×1067 и стало меньше',
    shrunk != null &&
        shrunk.width == 1600 &&
        shrunk.height == 1067 &&
        (await http.get(Uri.parse(url))).bodyBytes.length < bigPng.length,
    '${shrunk?.width}×${shrunk?.height}',
  );

  // Логотип с прозрачным фоном остаётся PNG
  final logo = img.Image(width: 64, height: 64, numChannels: 4)
    ..clear(img.ColorRgba8(0, 0, 0, 0));
  (s, r) = await call(
    'POST',
    '/api/admin/upload?ext=png&prefix=logo_',
    token: ta,
    bytes: img.encodePng(logo),
  );
  expect(
    'прозрачный PNG остаётся PNG',
    s == 201 && (r['url'] as String).endsWith('.png'),
    r,
  );

  // Модель с геометрией хранится сжатой и отдаётся с Content-Encoding: gzip
  final bigModel = [
    ...ascii.encode('glTF'),
    2,
    0,
    0,
    0,
    ...List.filled(200000, 7),
  ];
  (s, r) = await call(
    'POST',
    '/api/admin/upload?ext=glb&prefix=model_',
    token: ta,
    bytes: bigModel,
  );
  expect('загрузка большой 3D-модели', s == 201, r);
  final packedUrl = Uri.parse(r['url'] as String);
  final raw = HttpClient()..autoUncompress = false;
  final rawReq = await raw.getUrl(packedUrl);
  rawReq.headers.set('accept-encoding', 'gzip');
  final rawRes = await rawReq.close();
  final rawLen = (await rawRes.fold<List<int>>(
    [],
    (a, b) => a..addAll(b),
  )).length;
  raw.close();
  expect(
    'модель передаётся сжатой',
    rawRes.headers.value('content-encoding') == 'gzip' &&
        rawLen < bigModel.length ~/ 10,
    '${rawRes.headers.value('content-encoding')} $rawLen',
  );
  final unpacked = await http.get(packedUrl);
  expect(
    'после распаковки модель та же, что загружали',
    unpacked.statusCode == 200 &&
        unpacked.bodyBytes.length == bigModel.length &&
        (unpacked.headers['content-type'] ?? '').startsWith(
          'model/gltf-binary',
        ),
    unpacked.headers,
  );

  // 3D-модель: настоящий .glb начинается с «glTF»
  (s, r) = await call(
    'POST',
    '/api/admin/upload?ext=glb&prefix=model_',
    token: ta,
    bytes: [...ascii.encode('glTF'), 2, 0, 0, 0, 12, 0, 0, 0],
  );
  expect('загрузка 3D-модели', s == 201, r);
  final modelUrl = r['url'];
  (s, r) = await call(
    'POST',
    '/api/admin/upload?ext=glb',
    token: ta,
    bytes: utf8.encode('not a model at all'),
  );
  expect('не .glb под видом модели → 400', s == 400, r);
  (s, r) = await call(
    'POST',
    '/api/admin/upload?ext=exe',
    token: ta,
    bytes: utf8.encode('MZ'),
  );
  expect('.exe → 400', s == 400, r);

  (s, r) = await call(
    'POST',
    '/api/admin/products',
    token: ta,
    body: {
      'branch_id': branchA,
      'category_id': catA,
      'name': 'Борщ',
      'price': 350,
      'is_visible': true,
      'image_url': url,
      'model_url': modelUrl,
      'portions': [
        {'name': 'Большая', 'price': 450},
      ],
    },
  );
  expect(
    'товар с 3D-моделью',
    s == 201 &&
        r['image_url'] == url &&
        r['model_url'] == modelUrl &&
        r['portions'] is List,
    r,
  );
  final prodA = r['id'];

  // ---------- Языки меню ----------
  for (final (what, langs) in [
    ('неизвестный язык', ['ru', 'xx']),
    ('пустой список', <String>[]),
    ('повтор', ['ru', 'ru']),
  ]) {
    (s, r) = await call(
      'PATCH',
      '/api/admin/branches/$branchA',
      token: ta,
      body: {'languages': langs},
    );
    expect('языки: $what → 400', s == 400, r);
  }
  (s, r) = await call(
    'PATCH',
    '/api/admin/branches/$branchA',
    token: ta,
    body: {
      'languages': ['ru', 'en', 'ky'],
    },
  );
  expect(
    'языки филиала: ru, en, ky',
    s == 200 && (r['languages'] as List).join(',') == 'ru,en,ky',
    r,
  );
  (s, r) = await call(
    'PATCH',
    '/api/admin/products/$prodA',
    token: ta,
    body: {
      'description': 'Со сметаной',
      'i18n': {
        'en': {'name': 'Borscht', 'description': ''},
        'ky': {'name': 'Борщ'},
      },
    },
  );
  expect(
    'перевод блюда, пустой текст отброшен',
    s == 200 &&
        jsonEncode(r['i18n']) ==
            '{"en":{"name":"Borscht"},"ky":{"name":"Борщ"}}',
    r,
  );
  for (final (what, i18n) in [
    (
      'неизвестный язык',
      {
        'xx': {'name': 'a'},
      },
    ),
    (
      'неизвестное поле',
      {
        'en': {'price': 'a'},
      },
    ),
    (
      'не текст',
      {
        'en': {'name': 5},
      },
    ),
  ]) {
    (s, r) = await call(
      'PATCH',
      '/api/admin/products/$prodA',
      token: ta,
      body: {'i18n': i18n},
    );
    expect('перевод: $what → 400', s == 400, r);
  }
  (s, r) = await call(
    'PATCH',
    '/api/admin/branches/$branchA',
    token: ta,
    body: {
      'languages': ['en', 'ru', 'ky'],
    },
  );
  expect('основной язык — английский', s == 200, r);
  (s, r) = await call(
    'GET',
    '/api/admin/products?branch_id=$branchA',
    token: ta,
  );
  final borscht = (r as List).firstWhere((p) => p['id'] == prodA);
  expect(
    'смена основного языка: английский стал основным, русский — переводом',
    borscht['name'] == 'Borscht' &&
        borscht['description'] == 'Со сметаной' &&
        jsonEncode(borscht['i18n']) ==
            '{"ky":{"name":"Борщ"},"ru":{"name":"Борщ","description":"Со сметаной"}}',
    borscht,
  );
  (s, r) = await call(
    'GET',
    '/api/admin/categories?branch_id=$branchA',
    token: ta,
  );
  final soups = (r as List).firstWhere((c) => c['id'] == catA);
  expect(
    'категория без английского: название прежнее, русский — в переводах',
    soups['name'] == 'Супы' &&
        jsonEncode(soups['i18n']) == '{"ru":{"name":"Супы"}}',
    soups,
  );
  (s, r) = await call(
    'PATCH',
    '/api/admin/branches/$branchA',
    token: ta,
    body: {
      'languages': ['ru', 'en', 'ky'],
    },
  );
  (s, r) = await call(
    'GET',
    '/api/admin/products?branch_id=$branchA',
    token: ta,
  );
  final back = (r as List).firstWhere((p) => p['id'] == prodA);
  expect(
    'обратно на русский — тексты как были',
    back['name'] == 'Борщ' &&
        back['description'] == 'Со сметаной' &&
        jsonEncode(back['i18n']) ==
            '{"ky":{"name":"Борщ"},"en":{"name":"Borscht"}}',
    back,
  );

  // Данные неверного типа не попадают в базу: иначе одна такая строка
  // ломала бы меню гостя целиком
  for (final (what, body) in [
    ('цена текстом', {'price': 'abc'}),
    ('цена меньше 0', {'price': -5}),
    ('дробный порядок', {'sort_order': 1.5}),
    ('название числом', {'name': 5}),
    ('пустое название (null)', {'name': null}),
    ('видимость текстом', {'is_visible': 'yes'}),
    (
      'порция без названия',
      {
        'portions': [
          {'price': 100},
        ],
      },
    ),
    (
      'порция числом',
      {
        'portions': [1],
      },
    ),
  ]) {
    (s, r) = await call(
      'PATCH',
      '/api/admin/products/$prodA',
      token: ta,
      body: body,
    );
    expect('товар: $what → 400', s == 400, r);
  }
  (s, r) = await call(
    'POST',
    '/api/admin/products',
    token: ta,
    body: {'branch_id': 123, 'name': 'x'},
  );
  expect('branch_id числом → 400', s == 400, r);
  (s, r) = await call(
    'PATCH',
    '/api/admin/products/$prodA',
    token: ta,
    body: {'sort_order': 2.0, 'price': 400, 'portions': null},
  );
  expect(
    'целый порядок 2.0, цена 400 и порции null принимаются',
    s == 200 &&
        r['sort_order'] == 2 &&
        r['price'] == 400 &&
        (r['portions'] as List).isEmpty,
    r,
  );
  // Возвращаем порцию: дальше проверяется, что гость видит меню
  (s, r) = await call(
    'PATCH',
    '/api/admin/products/$prodA',
    token: ta,
    body: {
      'portions': [
        {'name': 'Большая', 'price': 450},
      ],
    },
  );

  final photoRes = await http.get(Uri.parse(url));
  expect('картинка отдаётся', photoRes.statusCode == 200, photoRes.statusCode);
  final model = await http.get(Uri.parse(modelUrl));
  expect(
    'модель отдаётся как model/gltf-binary',
    model.statusCode == 200 &&
        (model.headers['content-type'] ?? '').startsWith('model/gltf-binary'),
    model.headers,
  );

  (s, r) = await call('GET', '/api/public/branch/$slugA');
  expect('гость: филиал по slug', s == 200 && r['id'] == branchA, r);
  (s, r) = await call('GET', '/api/public/menu/$branchA');
  expect(
    'гость: меню с 3D-моделью',
    s == 200 &&
        (r['products'] as List).length == 1 &&
        r['products'][0]['model_url'] == modelUrl,
    r,
  );

  // Изоляция кафе
  (s, r) = await call(
    'PATCH',
    '/api/admin/products/$prodA',
    token: tb,
    body: {'price': 1},
  );
  expect('кафе B правит товар кафе A → 404', s == 404, r);
  (s, r) = await call(
    'GET',
    '/api/admin/categories?branch_id=$branchA',
    token: tb,
  );
  expect('кафе B читает категории кафе A → 404', s == 404, r);
  (s, r) = await call(
    'POST',
    '/api/admin/products',
    token: tb,
    body: {'branch_id': branchB, 'category_id': catA, 'name': 'x'},
  );
  expect('товар B в категорию A → 400', s == 400, r);
  (s, r) = await call('GET', '/api/admin/branches');
  expect('без токена → 401', s == 401, r);
  (s, r) = await call('GET', '/api/super/cafes', token: ta);
  expect('админ кафе в /super → 403', s == 403, r);

  // Удаление единственного филиала запрещено
  (s, r) = await call('DELETE', '/api/admin/branches/$branchA', token: ta);
  expect('удалить единственный филиал → 400', s == 400, r);

  // Повышение лимита
  (s, r) = await call(
    'PATCH',
    '/api/super/cafes/$cafeA',
    token: st,
    body: {'max_branches': 2},
  );
  (s, r) = await call(
    'POST',
    '/api/admin/branches',
    token: ta,
    body: {'name': 'Второй', 'slug': 'a2-$stamp'},
  );
  expect(
    'после повышения лимита второй филиал создаётся — с языками первого',
    s == 201 && (r['languages'] as List).join(',') == 'ru,en,ky',
    r,
  );

  // Оплата
  final today = DateTime.now();
  String inDays(int d) => formatDate(today.add(Duration(days: d)));
  (s, r) = await call('GET', '/api/super/cafes', token: st);
  final cafeARow = (r as List).firstWhere((c) => c['id'] == cafeA);
  expect(
    'новое кафе — пробный период 14 дней',
    cafeARow['plan'] == 'trial' &&
        cafeARow['paid_until'] == inDays(14) &&
        cafeARow['access'] == 'ok',
    cafeARow,
  );
  (s, r) = await call('GET', '/api/me', token: ta);
  expect(
    'кафе видит свой срок',
    s == 200 &&
        r['cafe']['paid_until'] == inDays(14) &&
        r['cafe']['access'] == 'ok',
    r,
  );

  (s, r) = await call(
    'POST',
    '/api/super/cafes/$cafeA/payments',
    token: st,
    body: {'period': 'month', 'months': 1, 'amount': 1500, 'note': 'Mbank'},
  );
  expect(
    'оплата месяца продлевает от конца пробного срока',
    s == 201 &&
        r['plan'] == 'paid' &&
        r['paid_until'] == extend(inDays(14), 1, today),
    r,
  );
  (s, r) = await call('GET', '/api/super/cafes/$cafeA/payments', token: st);
  expect(
    'оплата в истории',
    s == 200 &&
        (r as List).length == 1 &&
        r[0]['amount'] == 1500 &&
        r[0]['note'] == 'Mbank',
    r,
  );
  (s, r) = await call('GET', '/api/super/cafes/$cafeA/payments', token: ta);
  expect('админ кафе не видит оплаты платформы → 403', s == 403, r);

  for (final (what, body) in [
    ('период неделя', {'period': 'week', 'months': 1}),
    ('0 месяцев', {'period': 'month', 'months': 0}),
    ('сумма меньше 0', {'period': 'month', 'months': 1, 'amount': -5}),
  ]) {
    (s, r) = await call(
      'POST',
      '/api/super/cafes/$cafeA/payments',
      token: st,
      body: body,
    );
    expect('оплата: $what → 400', s == 400, r);
  }
  (s, r) = await call(
    'PATCH',
    '/api/super/cafes/$cafeA',
    token: st,
    body: {'paid_until': '2026-02-31'},
  );
  expect('несуществующая дата → 400', s == 400, r);

  // Просрочка: 5 дней — льготные, меню работает; 10 дней — выключено
  (s, r) = await call(
    'PATCH',
    '/api/super/cafes/$cafeA',
    token: st,
    body: {'paid_until': inDays(-5)},
  );
  expect(
    'просрочено на 5 дней — льготные дни, меню выключится через 3 дня',
    s == 200 && r['access'] == 'grace' && r['menu_off_in'] == 3,
    r,
  );
  (s, r) = await call('GET', '/api/public/branch/$slugA');
  expect('в льготные дни гость видит меню', s == 200, r);

  (s, r) = await call(
    'PATCH',
    '/api/super/cafes/$cafeA',
    token: st,
    body: {'paid_until': inDays(-10)},
  );
  expect(
    'просрочено на 10 дней — меню выключено',
    s == 200 && r['access'] == 'expired',
    r,
  );
  (s, r) = await call('GET', '/api/public/branch/$slugA');
  expect(
    'гость: «Меню временно недоступно» (403 unpaid)',
    s == 403 && r['code'] == 'unpaid',
    r,
  );
  (s, r) = await call('GET', '/api/public/menu/$branchA');
  expect(
    'гость: меню по id тоже закрыто',
    s == 403 && r['code'] == 'unpaid',
    r,
  );
  (s, r) = await call('GET', '/api/admin/branches', token: ta);
  expect('админ кафе может смотреть', s == 200, r);
  (s, r) = await call(
    'PATCH',
    '/api/admin/branches/$branchA',
    token: ta,
    body: {'slogan': 'новый'},
  );
  expect(
    'админ кафе не может менять (403 unpaid)',
    s == 403 && r['code'] == 'unpaid',
    r,
  );

  (s, r) = await call(
    'POST',
    '/api/super/cafes/$cafeA/payments',
    token: st,
    body: {'period': 'lifetime', 'amount': 30000},
  );
  expect(
    'покупка навсегда — без срока',
    s == 201 &&
        r['plan'] == 'lifetime' &&
        r['paid_until'] == '' &&
        r['access'] == 'ok',
    r,
  );
  (s, r) = await call('GET', '/api/public/branch/$slugA');
  expect('после оплаты меню снова открыто', s == 200, r);

  // Блокировка пользователя и кафе
  (s, r) = await call(
    'PATCH',
    '/api/super/users/$userB',
    token: st,
    body: {'is_active': false},
  );
  (s, r) = await call('GET', '/api/me', token: tb);
  expect('заблокированный пользователь выкинут → 401', s == 401, r);

  (s, r) = await call(
    'PATCH',
    '/api/super/cafes/$cafeA',
    token: st,
    body: {'is_active': false},
  );
  (s, r) = await call('GET', '/api/me', token: ta);
  expect('блок кафе: сессия закрыта → 401', s == 401, r);
  (s, r) = await call('GET', '/api/public/branch/$slugA');
  expect('блок кафе: меню гостю недоступно → 404', s == 404, r);
  (s, r) = await call(
    'POST',
    '/api/auth/login',
    body: {'login': 'a$stamp', 'password': 'pass1234'},
  );
  expect('блок кафе: вход → 403', s == 403, r);

  // Уборка
  await call('DELETE', '/api/super/cafes/$cafeA', token: st);
  await call('DELETE', '/api/super/cafes/$cafeB', token: st);

  stdout.writeln(
    failures == 0 ? '\nВсе проверки прошли' : '\nОшибок: $failures',
  );
  exit(failures == 0 ? 0 : 1);
}
