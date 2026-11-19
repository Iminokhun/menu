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
    "delivery_price) values "
    "('$_branchId', 'cafe-1', 'center', 'Центр', '996555112233', 150)",
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

    (code, _) = await admin('GET', '/api/admin/orders', mine);
    expect('без филиала — отказ', code == 400, code);

    (code, _) = await admin(
      'GET',
      '/api/admin/orders?branch_id=$_branchId',
      alien,
    );
    expect('чужой филиал для админа не существует', code == 404, code);

    final orderId = ((listed as List).first as Map)['id'] as String;
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
