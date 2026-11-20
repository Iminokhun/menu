// Проверка заказов гостей: деньги считает сервер, исчезнувшие блюда не
// теряются, повторы отбрасываются, чужое недоступно.
// Запуск: dart run tool/order_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:menu_server/api.dart';
import 'package:menu_server/auth.dart';
import 'package:menu_server/db.dart';
import 'package:menu_server/order.dart';
import 'package:menu_server/security.dart';
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';

var failures = 0;

void expect(String what, bool ok, [Object? info]) {
  stdout.writeln('${ok ? 'OK  ' : 'FAIL'} $what${ok ? '' : '  → $info'}');
  if (!ok) failures++;
}

const _branchId = 'branch-1';
const _otherBranchId = 'branch-2';

/// Второй филиал того же кафе: номер WhatsApp вписан, а права на заказы
/// нет. Главное, что проверяется этой строкой: право у каждого филиала
/// своё, и соседу по кафе оно не достаётся
const _siblingId = 'branch-3';

void _seed(Database db) {
  db.execute(
    "insert into cafes (id, name, is_active, max_branches, plan, paid_until) "
    "values ('cafe-1', 'Тест', 1, 5, 'lifetime', '')",
  );
  db.execute(
    "insert into cafes (id, name, is_active, max_branches, plan, paid_until) "
    "values ('cafe-2', 'Чужое', 1, 5, 'lifetime', '')",
  );
  db.execute(
    "insert into branches (id, cafe_id, slug, name, order_whatsapp, "
    "delivery_price, orders_enabled) values "
    "('$_branchId', 'cafe-1', 'center', 'Центр', '996555112233', 150, 1)",
  );
  db.execute(
    "insert into branches (id, cafe_id, slug, name, order_whatsapp, "
    "delivery_price, orders_enabled) values "
    "('$_siblingId', 'cafe-1', 'second', 'Второй', '996700112233', 100, 0)",
  );
  db.execute(
    "insert into branches (id, cafe_id, slug, name) values "
    "('$_otherBranchId', 'cafe-2', 'other', 'Чужой')",
  );
  db.execute(
    "insert into products (id, branch_id, name, price, portions, is_visible) "
    "values ('p1', '$_branchId', 'Лагман', 280, "
    "'[{\"name\":\"большая\",\"price\":320}]', 1)",
  );
  db.execute(
    "insert into products (id, branch_id, name, price, is_visible) values "
    "('p2', '$_branchId', 'Чай', 120, 1)",
  );
  db.execute(
    "insert into products (id, branch_id, name, price, is_visible) values "
    "('p-hidden', '$_branchId', 'Скрытое', 999, 0)",
  );
  db.execute(
    "insert into products (id, branch_id, name, price, is_visible) values "
    "('p-alien', '$_otherBranchId', 'Чужое блюдо', 777, 1)",
  );
}

Map<String, Object?> _order({
  String type = 'delivery',
  String code = '',
  String name = 'Азамат',
  String phone = '0555112233',
  String address = 'Киевская 95',
  List<Map<String, Object?>>? items,
  Map<String, Object?> extra = const {},
}) => {
  'branch_id': _branchId,
  'code': code,
  'order_type': type,
  'name': name,
  'phone': phone,
  'address': address,
  'comment': '',
  'lang': 'ru',
  'items':
      items ??
      [
        {'product_id': 'p1', 'portion': 'большая', 'qty': 2, 'name': 'Лагман'},
        {'product_id': 'p2', 'portion': '', 'qty': 1, 'name': 'Чай'},
      ],
  ...extra,
};

/// Та же таблица примеров, что в `test/order_message_test.dart` на клиенте:
/// правила обязаны совпадать, иначе админка покажет одно, а сохранится другое.
void _phones() {
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
  const strict = [
    '996555112233',
    null, // код страны не задан — ведущий ноль не домысливаем
    '996555112233',
    '996555112233',
    '996555112233',
    '', // пусто — кафе выключило заказы
    null,
    null,
    null,
  ];
  const lenient = [
    '996555112233',
    '0555112233',
    '996555112233',
    '00996555112233',
    '996555112233',
    null,
    null,
    null,
    null,
  ];
  for (var i = 0; i < samples.length; i++) {
    expect(
      'номер кафе «${samples[i]}»',
      normalizeWaPhone(samples[i]) == strict[i],
      normalizeWaPhone(samples[i]),
    );
    expect(
      'номер гостя «${samples[i]}»',
      cleanGuestPhone(samples[i]) == lenient[i],
      cleanGuestPhone(samples[i]),
    );
  }
  expect(
    'ведущий ноль получает код страны, когда он задан',
    normalizeWaPhone('0555112233', defaultCountryCode: '996') == '996555112233',
  );
}

Future<void> main() async {
  _phones();
  final dir = Directory.systemTemp.createTempSync('menu_orders_');
  try {
    final db = openDb('${dir.path}/menu.db');
    _seed(db);
    // Держим ограничитель филиалов отдельной ссылкой: по числу его ключей
    // видно, оседает ли в памяти присланная строка
    final branchLimiter = SlidingWindowLimiter(
      max: 1000,
      window: const Duration(minutes: 10),
    );
    final api = Api(
      db,
      uploadsDir: dir.path,
      defaultCountryCode: '996',
      // Проверок много, и упираться в предел они не должны: он проверяется
      // отдельно, своим сервером ниже
      orderIpLimiter: SlidingWindowLimiter(
        max: 1000,
        window: const Duration(minutes: 5),
      ),
      orderBranchLimiter: branchLimiter,
    );
    final app = const Pipeline()
        .addMiddleware(errorHandler())
        .addHandler(api.router.call);

    Future<(int, Map<String, Object?>)> post(Object body) async {
      final res = await app(
        Request(
          'POST',
          Uri.parse('http://localhost/api/public/orders'),
          body: jsonEncode(body),
          headers: const {'content-type': 'application/json'},
        ),
      );
      final text = await res.readAsString();
      final decoded = text.isEmpty ? {} : jsonDecode(text);
      return (
        res.statusCode,
        decoded is Map ? Map<String, Object?>.from(decoded) : <String, Object?>{},
      );
    }

    Future<(int, Object?)> get(String path) async {
      final res = await app(Request('GET', Uri.parse('http://localhost$path')));
      final text = await res.readAsString();
      return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
    }

    // --- Доставка: суммы считает сервер ---
    var (status, body) = await post(_order());
    expect('заказ без входа принят', status == 201, '$status $body');
    expect(
      'сумма блюд — по ценам сервера: порция 320×2 + 120',
      body['items_total'] == 760,
      body,
    );
    expect(
      'доставка добавлена из филиала, итог сложился',
      body['delivery_total'] == 150 && body['total'] == 910,
      body,
    );
    expect('исчезнувших блюд нет', body['missing'] == 0, body);

    // --- Клиент не может назначить цену ---
    (status, body) = await post(
      _order(
        extra: {'total': 1, 'delivery_total': 0, 'items_total': 1},
        items: [
          {'product_id': 'p1', 'portion': '', 'qty': 1, 'price': 1, 'sum': 1},
        ],
      ),
    );
    expect(
      'присланные суммы игнорируются — цена взята с сервера',
      status == 201 && body['items_total'] == 280 && body['total'] == 430,
      '$status $body',
    );

    // --- Самовывоз ---
    (status, body) = await post(_order(type: 'pickup'));
    expect(
      'самовывоз: доставка не прибавляется',
      status == 201 && body['delivery_total'] == 0 && body['total'] == 760,
      '$status $body',
    );
    final pickup = db
        .select("select * from orders where order_type = 'pickup'")
        .first;
    expect(
      'самовывоз: адрес не сохраняется, даже если его прислали',
      pickup['address'] == '',
      pickup['address'],
    );

    // --- Исчезнувшие блюда ---
    (status, body) = await post(
      _order(
        items: [
          {'product_id': 'p2', 'portion': '', 'qty': 1, 'name': 'Чай'},
          {'product_id': 'p-hidden', 'portion': '', 'qty': 1, 'name': 'Скрытое'},
          {'product_id': 'p-alien', 'portion': '', 'qty': 1, 'name': 'Чужое'},
          {'product_id': 'нет такого', 'portion': '', 'qty': 1, 'name': '?'},
        ],
      ),
    );
    expect(
      'скрытое, чужое и несуществующее блюдо: заказ принят, но помечен',
      status == 201 && body['missing'] == 3 && body['items_total'] == 120,
      '$status $body',
    );

    // --- Повторная отправка ---
    final (s1, b1) = await post(_order(code: 'A7F3'));
    final (s2, b2) = await post(_order(code: 'A7F3'));
    expect(
      'тот же код за 10 минут — тот же заказ, а не второй',
      s1 == 201 && s2 == 200 && b1['id'] == b2['id'],
      '$s1 $s2 $b1 $b2',
    );
    expect(
      'в базе одна строка с этим кодом',
      db
              .select("select count(*) n from orders where code = 'A7F3'")
              .first['n'] ==
          1,
    );

    // --- Проверки полей ---
    (status, body) = await post(_order(name: '  '));
    expect('без имени — отказ', status == 400, '$status $body');
    (status, body) = await post(_order(phone: '123'));
    expect('кривой телефон — отказ', status == 400, '$status $body');
    (status, body) = await post(_order(address: ''));
    expect('доставка без адреса — отказ', status == 400, '$status $body');
    (status, body) = await post(_order(type: 'eatin'));
    expect('неизвестный способ получения — отказ', status == 400, '$status $body');
    (status, body) = await post(_order(items: const []));
    expect('пустой заказ — отказ', status == 400, '$status $body');
    (status, body) = await post(
      _order(
        items: [
          for (var i = 0; i < 101; i++)
            {'product_id': 'p2', 'portion': '', 'qty': 1, 'name': 'Чай'},
        ],
      ),
    );
    expect('101 позиция — отказ', status == 400, '$status $body');
    (status, body) = await post(
      _order(
        items: [
          {'product_id': 'p2', 'portion': '', 'qty': 0, 'name': 'Чай'},
        ],
      ),
    );
    expect('нулевое количество — отказ', status == 400, '$status $body');

    // --- Заказы выключены у филиала ---
    (status, body) = await post({..._order(), 'branch_id': _otherBranchId});
    expect(
      'филиал без номера WhatsApp заказы не принимает',
      status == 403 && body['code'] == 'orders_off',
      '$status $body',
    );

    // --- Админка кафе видит свои заказы и только свои ---
    db.execute(
      "insert into users (id, cafe_id, login, password_hash, role) values "
      "('u1', 'cafe-1', 'admin1', 'x', 'cafe_admin')",
    );
    db.execute(
      "insert into users (id, cafe_id, login, password_hash, role) values "
      "('u2', 'cafe-2', 'admin2', 'x', 'cafe_admin')",
    );
    final mine = createSession(db, 'u1');
    final alien = createSession(db, 'u2');

    Future<(int, Object?)> admin(
      String method,
      String path,
      String token, [
      Object? body,
    ]) async {
      final res = await app(
        Request(
          method,
          Uri.parse('http://localhost$path'),
          headers: {
            'authorization': 'Bearer $token',
            if (body != null) 'content-type': 'application/json',
          },
          body: body == null ? null : jsonEncode(body),
        ),
      );
      final text = await res.readAsString();
      return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
    }

    var (code, listed) = await admin(
      'GET',
      '/api/admin/orders?branch_id=$_branchId',
      mine,
    );
    expect(
      'кафе видит свои заказы, состав развёрнут из JSON',
      code == 200 &&
          listed is List &&
          listed.isNotEmpty &&
          (listed.first as Map)['items'] is List,
      '$code $listed',
    );

    // Номер гостя лежит так, как он его набрал, а для ссылки «написать»
    // сервер добавляет код страны: иначе wa.me открывает несуществующий чат
    final withPhone = (listed as List)
        .cast<Map>()
        .firstWhere((o) => o['guest_phone'] == '0555112233');
    expect(
      'к заказу добавлен номер в международном виде',
      withPhone['guest_phone_wa'] == '996555112233',
      '${withPhone['guest_phone']} → ${withPhone['guest_phone_wa']}',
    );

    (code, _) = await admin('GET', '/api/admin/orders', mine);
    expect('без филиала — отказ', code == 400, code);

    (code, _) = await admin(
      'GET',
      '/api/admin/orders?branch_id=$_branchId',
      alien,
    );
    expect('чужой филиал для админа не существует', code == 404, code);

    final orderId = (listed.first as Map)['id'] as String;
    (code, _) = await admin('PATCH', '/api/admin/orders/$orderId', mine, {
      'status': 'done',
    });
    expect(
      'заказ отмечается готовым',
      code == 200 &&
          db
                  .select('select status from orders where id = ?', [orderId])
                  .first['status'] ==
              'done',
      code,
    );

    (code, _) = await admin('PATCH', '/api/admin/orders/$orderId', mine, {
      'status': 'что-то своё',
    });
    expect('неизвестная отметка — отказ', code == 400, code);

    (code, _) = await admin('PATCH', '/api/admin/orders/$orderId', alien, {
      'status': 'new',
    });
    expect('чужой заказ не поправить', code == 404, code);

    (code, _) = await admin('PATCH', '/api/admin/orders/$orderId', mine, {
      'total': 1,
      'guest_phone': '000',
    });
    final untouched = db
        .select('select * from orders where id = ?', [orderId])
        .first;
    expect(
      'суммы и контакты в заказе не правятся',
      untouched['total'] != 1 && untouched['guest_phone'] != '000',
      untouched,
    );

    // --- Отбор в списке заказов: период, отметка, способ получения ---
    // Свои строки с явным временем: заказы, отправленные выше, счёт не
    // путают — у них свои коды
    void seedOrder(String id, String type, String status, int daysAgo) {
      db.execute(
        "insert into orders (id, branch_id, code, order_type, guest_name, "
        "guest_phone, status, created_at) values (?, ?, ?, ?, 'Гость', "
        "'0555112233', ?, datetime('now', ?))",
        [id, _branchId, id, type, status, '-$daysAgo days'],
      );
    }

    db.execute("delete from orders where branch_id = '$_branchId'");
    seedOrder('o1', 'delivery', 'new', 0);
    seedOrder('o2', 'pickup', 'new', 0);
    seedOrder('o3', 'delivery', 'done', 3);
    seedOrder('o4', 'pickup', 'done', 20);

    Future<List<String>> orderIds(String query) async {
      final (c, rows) = await admin(
        'GET',
        '/api/admin/orders?branch_id=$_branchId&limit=200&$query',
        mine,
      );
      if (c != 200) return ['код $c'];
      return (rows as List).map((r) => (r as Map)['id'] as String).toList()
        ..sort();
    }

    Future<int> orderCode(String query) async {
      final (c, _) = await admin(
        'GET',
        '/api/admin/orders?branch_id=$_branchId&$query',
        mine,
      );
      return c;
    }

    expect(
      'способ получения: только доставка',
      (await orderIds('order_type=delivery')).join(',') == 'o1,o3',
      await orderIds('order_type=delivery'),
    );
    expect(
      'только самовывоз',
      (await orderIds('order_type=pickup')).join(',') == 'o2,o4',
      await orderIds('order_type=pickup'),
    );
    expect(
      'неизвестный способ — 400',
      await orderCode('order_type=телепорт') == 400,
    );
    expect(
      'пустой способ — отбора нет',
      (await orderIds('order_type=')).length == 4,
    );
    expect(
      'пустая отметка — отбора нет',
      (await orderIds('status=')).length == 4,
    );

    final dayAgo = db
        .select("select datetime('now', '-1 days') t")
        .first['t'] as String;
    expect(
      'период отсекает старые заказы',
      (await orderIds('since=$dayAgo')).join(',') == 'o1,o2',
      await orderIds('since=$dayAgo'),
    );
    expect(
      'период, отметка и способ сужают вместе',
      (await orderIds('since=${db.select("select datetime('now','-5 days') t").first['t']}'
              '&status=done&order_type=delivery'))
              .join(',') ==
          'o3',
      await orderIds('status=done&order_type=delivery'),
    );
    for (final bad in ['вчера', "' or '1'='1"]) {
      expect('since=«$bad» в заказах — 400', await orderCode('since=$bad') == 400);
    }

    final (_, narrowOrders) = await admin(
      'GET',
      '/api/admin/orders?branch_id=$_branchId&order_type=pickup&limit=1',
      mine,
    );
    expect(
      'предел режет отобранное, а не наоборот',
      (narrowOrders as List).length == 1 &&
          (narrowOrders.first as Map)['order_type'] == 'pickup',
      narrowOrders,
    );

    // --- Право на заказы: выдаёт владелец платформы, каждому филиалу своё ---
    db.execute(
      "insert into users (id, login, password_hash, role) values "
      "('u3', 'root', 'x', 'superadmin')",
    );
    final boss = createSession(db, 'u3');

    int right(String id) =>
        db.select('select orders_enabled from branches where id = ?', [
              id,
            ]).first['orders_enabled']
            as int;

    // Сосед по кафе: номер вписан, права нет. Первый филиал кафе при этом
    // заказы принимает — право не делится на всё кафе
    (status, body) = await post({..._order(), 'branch_id': _siblingId});
    expect(
      'сосед по кафе без права заказы не принимает',
      status == 403 && body['code'] == 'orders_off',
      '$status $body',
    );
    var (pubStatus, pubBody) = await get('/api/public/branch/second');
    expect(
      'и номер соседа гостю не показывается',
      pubStatus == 200 && (pubBody as Map)['order_whatsapp'] == '',
      '$pubStatus $pubBody',
    );
    (pubStatus, pubBody) = await get('/api/public/branch/center');
    expect(
      'а у филиала с правом номер виден',
      (pubBody as Map)['order_whatsapp'] == '996555112233',
      pubBody,
    );

    // Включает и выключает только владелец платформы
    (code, _) = await admin('PATCH', '/api/super/branches/$_siblingId', mine, {
      'orders_enabled': true,
    });
    expect(
      'кафе право себе не включает',
      code == 403 && right(_siblingId) == 0,
      code,
    );
    (code, _) = await admin('PATCH', '/api/admin/branches/$_siblingId', mine, {
      'orders_enabled': true,
    });
    expect(
      'и через свои настройки филиала тоже — поле отбрасывается',
      code == 200 && right(_siblingId) == 0,
      code,
    );
    (code, _) = await admin('PATCH', '/api/super/branches/$_siblingId', boss, {
      'orders_enabled': true,
    });
    expect(
      'владелец платформы право выдал — именно этому филиалу',
      code == 200 && right(_siblingId) == 1,
      code,
    );
    // Блюда в заказе — первого филиала, поэтому сохранятся строками
    // «нет в меню»; проверяется здесь только право на приём
    (status, body) = await post({
      ..._order(),
      'branch_id': _siblingId,
      'code': 'SIBOK',
    });
    expect('и сосед начал принимать заказы', status == 201, '$status $body');

    (code, _) = await admin('PATCH', '/api/super/branches/нет-такого', boss, {
      'orders_enabled': true,
    });
    expect('несуществующий филиал — 404', code == 404, code);
    (code, _) = await admin(
      'PATCH',
      '/api/super/branches/$_siblingId',
      boss,
      const <String, Object?>{},
    );
    expect('пустой запрос ничего не меняет — 400', code == 400, code);

    // Снятое право: номер у филиала остаётся на месте — при возврате его
    // не придётся набирать заново
    (code, _) = await admin('PATCH', '/api/super/branches/$_branchId', boss, {
      'orders_enabled': false,
    });
    expect('право снимается', code == 200 && right(_branchId) == 0, code);
    (status, body) = await post(_order(code: 'NORIGHT'));
    expect(
      'без права заказы не принимаются, хотя номер вписан',
      status == 403 && body['code'] == 'orders_off',
      '$status $body',
    );
    (pubStatus, pubBody) = await get('/api/public/branch/center');
    expect(
      'и гостю номер не показывается — кнопки у него просто нет',
      pubStatus == 200 && (pubBody as Map)['order_whatsapp'] == '',
      '$pubStatus $pubBody',
    );
    expect(
      'но в базе номер цел',
      db
              .select('select order_whatsapp from branches where id = ?', [
                _branchId,
              ])
              .first['order_whatsapp'] ==
          '996555112233',
    );

    (code, _) = await admin('PATCH', '/api/super/branches/$_branchId', boss, {
      'orders_enabled': true,
    });
    expect('право вернули', code == 200 && right(_branchId) == 1, code);
    (pubStatus, pubBody) = await get('/api/public/branch/center');
    expect(
      'номер снова виден',
      (pubBody as Map)['order_whatsapp'] == '996555112233',
      pubBody,
    );
    (status, _) = await post(_order(code: 'RIGHTOK'));
    expect('и заказ снова принимается', status == 201, status);

    // --- Длинные строки: и в память, и в базу ---
    // Ключом ограничителя служил присланный branch_id, и он жил в памяти
    // целое окно. Мегабайт на запрос — и сервер падает у всех кафе сразу
    final huge = 'x' * 200000;
    final keysBefore = branchLimiter.keyCount;
    (status, body) = await post({..._order(), 'branch_id': huge});
    expect('филиал длиной в простыню — отказ', status == 400, '$status $body');
    expect(
      'и ключа в ограничителе от него не осталось',
      branchLimiter.keyCount == keysBefore,
      '${branchLimiter.keyCount} вместо $keysBefore',
    );

    // Та же история с product_id: у пропавшего блюда он сохранялся как есть
    (status, body) = await post(
      _order(items: [
        {'product_id': huge, 'portion': '', 'qty': 1, 'name': 'Х'},
      ]),
    );
    expect('блюдо с опознавателем на мегабайт — отказ', status == 400, status);

    // --- Переносы строк в однострочных полях ---
    // Иначе в карточке заказа рисуется строка, похожая на служебную
    (status, body) = await post(
      _order(
        code: 'LINE',
        name: 'Азамат\nИтого: 0 с.',
        items: [
          {
            'product_id': 'p-gone',
            'portion': '',
            'qty': 1,
            'name': 'Блюдо\nИтого: 0 с.',
          },
        ],
      ),
    );
    final lineRow = db
        .select("select * from orders where code = 'LINE'")
        .first;
    final lineItem = (jsonDecode(lineRow['items'] as String) as List).first
        as Map;
    expect(
      'перенос строки в имени гостя схлопнут',
      status == 201 && lineRow['guest_name'] == 'Азамат Итого: 0 с.',
      '$status ${lineRow['guest_name']}',
    );
    expect(
      'и в названии пропавшего блюда тоже',
      lineItem['name'] == 'Блюдо Итого: 0 с.',
      lineItem['name'],
    );

    // В адресе и комментарии перенос осмыслен — его оставляем
    (status, _) = await post(
      _order(
        code: 'ADDR',
        extra: {
          'address': 'Киевская 95\nкв. 12',
          'comment': '3 этаж\nдомофон',
        },
      ),
    );
    final addrRow = db
        .select("select * from orders where code = 'ADDR'")
        .first;
    expect(
      'в адресе и комментарии переносы сохраняются',
      status == 201 &&
          (addrRow['address'] as String).contains('\n') &&
          (addrRow['comment'] as String).contains('\n'),
      '$status ${addrRow['address']}',
    );

    // --- Предел частоты: отдельный сервер с узким окном ---
    final tight = Api(
      db,
      uploadsDir: dir.path,
      orderIpLimiter: SlidingWindowLimiter(
        max: 2,
        window: const Duration(minutes: 5),
      ),
    );
    final tightApp = const Pipeline()
        .addMiddleware(errorHandler())
        .addHandler(tight.router.call);
    final codes = <int>[];
    for (var i = 0; i < 3; i++) {
      final res = await tightApp(
        Request(
          'POST',
          Uri.parse('http://localhost/api/public/orders'),
          body: jsonEncode(_order()),
          headers: const {'content-type': 'application/json'},
        ),
      );
      await res.readAsString();
      codes.add(res.statusCode);
    }
    expect(
      'третий заказ подряд с одного адреса — отказ',
      codes[0] == 201 && codes[1] == 201 && codes[2] == 429,
      codes,
    );

    db.close();
  } finally {
    dir.deleteSync(recursive: true);
  }

  stdout.writeln(
    failures == 0 ? '\nВсе проверки прошли' : '\nОшибок: $failures',
  );
  exit(failures == 0 ? 0 : 1);
}
