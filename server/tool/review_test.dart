// Проверка отзывов гостей: право выдаётся филиалу, отзыв никуда не
// пересылается, чужое недоступно, старое удаляется само.
// Запуск: dart run tool/review_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:menu_server/api.dart';
import 'package:menu_server/auth.dart';
import 'package:menu_server/db.dart';
import 'package:menu_server/security.dart';
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';

var failures = 0;

void expect(String what, bool ok, [Object? info]) {
  stdout.writeln('${ok ? 'OK  ' : 'FAIL'} $what${ok ? '' : '  → $info'}');
  if (!ok) failures++;
}

/// Филиал с правом на отзывы
const _branchId = 'branch-1';

/// Второй филиал того же кафе, тоже с правом
const _secondId = 'branch-2';

/// Филиал того же кафе без права: право у каждого филиала своё
const _noRightId = 'branch-3';

/// Филиал чужого кафе
const _alienId = 'branch-4';

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
    "insert into branches (id, cafe_id, slug, name, reviews_enabled) values "
    "('$_branchId', 'cafe-1', 'center', 'Центр', 1)",
  );
  db.execute(
    "insert into branches (id, cafe_id, slug, name, reviews_enabled) values "
    "('$_secondId', 'cafe-1', 'second', 'Второй', 1)",
  );
  db.execute(
    "insert into branches (id, cafe_id, slug, name) values "
    "('$_noRightId', 'cafe-1', 'third', 'Третий')",
  );
  db.execute(
    "insert into branches (id, cafe_id, slug, name, reviews_enabled) values "
    "('$_alienId', 'cafe-2', 'alien', 'Чужой', 1)",
  );
}

Map<String, Object?> _review({
  String branchId = _branchId,
  Object? rating = 4,
  String waiter = 'Айгуль',
  String tableNo = '12',
  String comment = 'Вкусно, но салат несли долго',
  Map<String, Object?> extra = const {},
}) => {
  'branch_id': branchId,
  'rating': rating,
  'waiter': waiter,
  'table_no': tableNo,
  'comment': comment,
  'lang': 'ru',
  ...extra,
};

int _count(Database db, [String? branchId]) => db
    .select(
      branchId == null
          ? 'select count(*) n from reviews'
          : 'select count(*) n from reviews where branch_id = ?',
      branchId == null ? const [] : [branchId],
    )
    .first['n'] as int;

Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('menu_reviews_');
  try {
    final db = openDb('${dir.path}/menu.db');
    _seed(db);
    // Пределы широкие: они проверяются отдельно, своим сервером ниже
    final api = Api(
      db,
      uploadsDir: dir.path,
      defaultCountryCode: '996',
      reviewIpLimiter: SlidingWindowLimiter(
        max: 1000,
        window: const Duration(minutes: 10),
      ),
      reviewBranchLimiter: SlidingWindowLimiter(
        max: 1000,
        window: const Duration(minutes: 10),
      ),
    );
    final app = const Pipeline()
        .addMiddleware(errorHandler())
        .addHandler(api.router.call);

    Future<(int, Map<String, Object?>)> post(Object body) async {
      final res = await app(
        Request(
          'POST',
          Uri.parse('http://localhost/api/public/reviews'),
          body: jsonEncode(body),
          headers: const {'content-type': 'application/json'},
        ),
      );
      final text = await res.readAsString();
      final decoded = text.isEmpty ? {} : jsonDecode(text);
      return (
        res.statusCode,
        decoded is Map
            ? Map<String, Object?>.from(decoded)
            : <String, Object?>{},
      );
    }

    Future<(int, Object?)> get(String path) async {
      final res = await app(Request('GET', Uri.parse('http://localhost$path')));
      final text = await res.readAsString();
      return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
    }

    // --- Отзыв сохраняется ---
    var (status, body) = await post(_review());
    expect('отзыв без входа принят', status == 201, '$status $body');
    final saved = db
        .select('select * from reviews where branch_id = ?', [_branchId])
        .first;
    expect(
      'поля записаны как присланы',
      saved['rating'] == 4 &&
          saved['waiter'] == 'Айгуль' &&
          saved['table_no'] == '12' &&
          saved['comment'] == 'Вкусно, но салат несли долго' &&
          saved['lang'] == 'ru',
      saved,
    );
    expect(
      'в ответе только id и время',
      body.keys.toSet().length == 2 &&
          body.containsKey('id') &&
          body.containsKey('created_at'),
      body,
    );

    // --- Второй филиал того же кафе принимает свои отзывы ---
    (status, body) = await post(_review(branchId: _secondId));
    expect(
      'отзыв второму филиалу принят и лёг именно ему',
      status == 201 && _count(db, _secondId) == 1,
      '$status $body',
    );

    // --- Право у каждого филиала своё ---
    (status, body) = await post(_review(branchId: _noRightId));
    expect(
      'сосед по кафе без права отзывы не принимает',
      status == 403 && body['code'] == 'reviews_off',
      '$status $body',
    );
    expect('и строки не появилось', _count(db, _noRightId) == 0);

    // --- Оценка ---
    for (final bad in [0, 6, -1, '5', 4.5, null]) {
      (status, _) = await post(_review(rating: bad));
      expect('оценка «$bad» — отказ', status == 400, status);
    }
    (status, _) = await post(
      _review(rating: 5, waiter: '', tableNo: '', comment: ''),
    );
    expect('одни звёзды, без полей — принято', status == 201, status);

    // --- Номер стола: только цифры ---
    for (final bad in ['VIP-2', 'терраса', '12А', '1,2', '12345', '1\n2']) {
      (status, _) = await post(_review(tableNo: bad));
      expect('стол «$bad» — отказ', status == 400, status);
    }
    (status, _) = await post(_review(tableNo: '', comment: 'без стола'));
    expect('стол можно не указывать', status == 201, status);
    (status, _) = await post(_review(tableNo: '1024', comment: 'большой зал'));
    expect('четыре цифры — принято', status == 201, status);
    (status, _) = await post(_review(tableNo: ' 3 ', comment: 'с пробелами'));
    expect(
      'пробелы по краям срезаются, а не считаются буквами',
      status == 201 &&
          db
                  .select(
                    "select table_no from reviews where comment = 'с пробелами'",
                  )
                  .first['table_no'] ==
              '3',
      status,
    );

    // --- Филиал ---
    (status, _) = await post(_review(branchId: 'нет-такого'));
    expect('несуществующий филиал — 404', status == 404, status);
    (status, _) = await post(_review(branchId: ''));
    expect('пустой филиал — 400', status == 400, status);
    (status, _) = await post(_review(branchId: 'x' * 200));
    expect('филиал длиной в простыню — 400', status == 400, status);

    // --- Длина и невидимые символы ---
    (status, _) = await post(_review(comment: 'я' * 1001));
    expect('отзыв длиннее 1000 знаков — отказ', status == 400, status);
    (status, _) = await post(_review(comment: 'я' * 1000, tableNo: '7'));
    expect('ровно 1000 знаков — принято', status == 201, status);
    (status, _) = await post(
      _review(waiter: 'Ай\nгуль​', tableNo: '5', comment: 'ок'),
    );
    final lines = db
        .select("select waiter, table_no from reviews where comment = 'ок'")
        .first;
    expect(
      'перенос строки в имени схлопнут, невидимое вырезано',
      status == 201 &&
          lines['waiter'] == 'Ай гуль' &&
          lines['table_no'] == '5',
      lines,
    );

    // --- Повтор ---
    final before = _count(db, _branchId);
    final again = _review(comment: 'Один и тот же отзыв', tableNo: '3');
    await post(again);
    await post(again);
    expect(
      'тот же отзыв дважды — одна строка',
      _count(db, _branchId) == before + 1,
      _count(db, _branchId),
    );

    // --- Кафе не оплачено ---
    db.execute(
      "update cafes set plan = 'month', paid_until = '2020-01-01' "
      "where id = 'cafe-1'",
    );
    (status, body) = await post(_review());
    expect(
      'у неоплаченного кафе отзывы не принимаются',
      status == 403 && body['code'] == 'unpaid',
      '$status $body',
    );
    db.execute(
      "update cafes set plan = 'lifetime', paid_until = '' where id = 'cafe-1'",
    );

    // --- Публичного чтения нет ---
    // Маршрута нет вовсе, поэтому ответ не JSON — читаем его как есть
    final publicRead = await app(
      Request('GET', Uri.parse('http://localhost/api/public/reviews')),
    );
    await publicRead.readAsString();
    expect(
      'читать отзывы снаружи нельзя',
      publicRead.statusCode == 404,
      publicRead.statusCode,
    );

    // --- Админка кафе ---
    db.execute(
      "insert into users (id, cafe_id, login, password_hash, role) values "
      "('u1', 'cafe-1', 'admin1', 'x', 'cafe_admin')",
    );
    db.execute(
      "insert into users (id, cafe_id, login, password_hash, role) values "
      "('u2', 'cafe-2', 'admin2', 'x', 'cafe_admin')",
    );
    db.execute(
      "insert into users (id, login, password_hash, role) values "
      "('u3', 'root', 'x', 'superadmin')",
    );
    final mine = createSession(db, 'u1');
    final alien = createSession(db, 'u2');
    final boss = createSession(db, 'u3');

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
      '/api/admin/reviews?branch_id=$_branchId',
      mine,
    );
    expect(
      'кафе видит свои отзывы, новые сверху',
      code == 200 && listed is List && listed.isNotEmpty,
      '$code $listed',
    );
    (code, _) = await admin(
      'GET',
      '/api/admin/reviews?branch_id=$_alienId',
      mine,
    );
    expect('чужой филиал для админа не существует', code == 404, code);
    (code, _) = await admin(
      'GET',
      '/api/admin/reviews?branch_id=$_branchId',
      alien,
    );
    expect('и наоборот', code == 404, code);
    final anon = await app(
      Request(
        'GET',
        Uri.parse('http://localhost/api/admin/reviews?branch_id=$_branchId'),
      ),
    );
    await anon.readAsString();
    expect(
      'без входа список не отдаётся',
      anon.statusCode == 401,
      anon.statusCode,
    );

    await post(_review(rating: 1, comment: 'Плохо', tableNo: '9'));
    (code, listed) = await admin(
      'GET',
      '/api/admin/reviews?branch_id=$_branchId&max_rating=2',
      mine,
    );
    expect(
      'фильтр «плохие» отдаёт только их',
      code == 200 &&
          (listed as List).isNotEmpty &&
          listed.every((r) => (r as Map)['rating'] as int <= 2),
      listed,
    );
    (code, _) = await admin(
      'GET',
      '/api/admin/reviews?branch_id=$_branchId&max_rating=9',
      mine,
    );
    expect('кривая оценка в фильтре — 400', code == 400, code);
    (code, listed) = await admin(
      'GET',
      '/api/admin/reviews?branch_id=$_branchId&limit=1000',
      mine,
    );
    expect(
      'предел зажат сверху',
      code == 200 && (listed as List).length <= 200,
      (listed as List).length,
    );

    // --- Право выдаёт только владелец платформы ---
    (code, _) = await admin('PATCH', '/api/super/branches/$_noRightId', mine, {
      'reviews_enabled': true,
    });
    expect('кафе право себе не включает', code == 403, code);
    (code, _) = await admin('PATCH', '/api/admin/branches/$_noRightId', mine, {
      'reviews_enabled': true,
    });
    final still = db
        .select('select reviews_enabled from branches where id = ?', [
          _noRightId,
        ])
        .first['reviews_enabled'];
    expect(
      'и через свои настройки филиала тоже — поле отбрасывается',
      code == 200 && still == 0,
      '$code $still',
    );
    (code, _) = await admin('PATCH', '/api/super/branches/$_noRightId', boss, {
      'reviews_enabled': true,
    });
    expect(
      'владелец платформы право выдал',
      code == 200 &&
          db
                  .select('select reviews_enabled from branches where id = ?', [
                    _noRightId,
                  ])
                  .first['reviews_enabled'] ==
              1,
      code,
    );
    (code, _) = await admin('PATCH', '/api/super/branches/$_branchId', boss, {
      'orders_enabled': true,
      'reviews_enabled': false,
    });
    final both = db
        .select(
          'select orders_enabled, reviews_enabled from branches where id = ?',
          [_branchId],
        )
        .first;
    expect(
      'оба права меняются одним запросом',
      code == 200 && both['orders_enabled'] == 1 && both['reviews_enabled'] == 0,
      both,
    );
    (code, _) = await admin(
      'PATCH',
      '/api/super/branches/$_branchId',
      boss,
      const <String, Object?>{},
    );
    expect('пустой запрос ничего не меняет — 400', code == 400, code);
    // Вернуть право: ниже оно ещё понадобится
    await admin('PATCH', '/api/super/branches/$_branchId', boss, {
      'reviews_enabled': true,
    });

    // --- Гостю видно только само право ---
    var (pub, pubBody) = await get('/api/public/branch/center');
    expect(
      'есть право — гость знает, что кнопка должна быть',
      pub == 200 && (pubBody as Map)['reviews_enabled'] == true,
      pubBody,
    );
    expect(
      'номера для пересылки в выдаче нет вовсе',
      !(pubBody as Map).containsKey('review_whatsapp'),
      pubBody,
    );
    await admin('PATCH', '/api/super/branches/$_branchId', boss, {
      'reviews_enabled': false,
    });
    (pub, pubBody) = await get('/api/public/branch/center');
    expect(
      'нет права — кнопки у гостя нет',
      (pubBody as Map)['reviews_enabled'] == false,
      pubBody,
    );
    await admin('PATCH', '/api/super/branches/$_branchId', boss, {
      'reviews_enabled': true,
    });

    // --- Внедрение SQL: текст гостя никогда не попадает в сам запрос ---
    // Все значения уходят отдельными параметрами (`?`), поэтому кавычки и
    // точка с запятой в имени официанта — это просто буквы
    const drop = "'); drop table reviews; --";
    (status, body) = await post(
      _review(waiter: drop, tableNo: '8', comment: "О'Коннор; select 1"),
    );
    expect(
      'отзыв с кавычками и «drop table» принят',
      status == 201,
      '$status $body',
    );
    final tricky = db
        .select("select * from reviews where waiter = ?", [drop])
        .first;
    expect(
      'текст сохранён буква в букву, ничего не выполнилось',
      tricky['waiter'] == drop &&
          tricky['comment'] == "О'Коннор; select 1",
      tricky,
    );
    // В стол внедрять нечего: там только цифры, и проверка отбивает это
    // раньше базы
    (status, _) = await post(_review(tableNo: "1' OR '1'='1"));
    expect('внедрение в номер стола — отказ', status == 400, status);
    expect(
      'таблица reviews на месте',
      db
              .select(
                "select count(*) n from sqlite_master where name = 'reviews'",
              )
              .first['n'] ==
          1,
    );
    expect(
      'и таблица branches тоже',
      db.select('select count(*) n from branches').first['n'] >= 3,
    );
    // Фильтр в админке — тоже параметр, а не кусок запроса
    (code, _) = await admin(
      'GET',
      '/api/admin/reviews?branch_id=$_branchId&max_rating=1 or 1=1',
      mine,
    );
    expect('внедрение в фильтр оценки — 400', code == 400, code);
    (code, _) = await admin(
      'GET',
      "/api/admin/reviews?branch_id=$_branchId&before=' or '1'='1",
      mine,
    );
    final afterInject = db.select('select count(*) n from reviews').first['n'];
    expect(
      'внедрение в курсор ничего не ломает',
      code == 200 && afterInject > 0,
      '$code $afterInject',
    );

    // --- Отзывы живут 40 дней ---
    db.execute(
      "insert into reviews (id, branch_id, rating, comment, created_at) values "
      "('old', '$_branchId', 5, 'Давно', datetime('now', '-41 days'))",
    );
    db.execute(
      "insert into reviews (id, branch_id, rating, comment, created_at) values "
      "('fresh', '$_branchId', 5, 'Недавно', datetime('now', '-39 days'))",
    );
    db.execute(
      "insert into orders (id, branch_id, order_type, guest_name, guest_phone, "
      "created_at) values ('o-old', '$_branchId', 'pickup', 'Гость', '0555', "
      "datetime('now', '-99 days'))",
    );
    final removed = purgeOldReviews(db);
    expect(
      'отзыв старше 40 дней удалён, свежий остался',
      removed == 1 &&
          db.select("select count(*) n from reviews where id = 'old'").first['n'] ==
              0 &&
          db
                  .select("select count(*) n from reviews where id = 'fresh'")
                  .first['n'] ==
              1,
      removed,
    );
    expect(
      'заказы уборка отзывов не трогает',
      db.select("select count(*) n from orders where id = 'o-old'").first['n'] ==
          1,
    );

    // --- Удаление филиала уносит его отзывы ---
    final kept = _count(db, _branchId);
    db.execute("delete from branches where id = '$_secondId'");
    expect(
      'отзывы удалённого филиала ушли с ним, чужие целы',
      _count(db, _secondId) == 0 && _count(db, _branchId) == kept,
    );

    // --- Пределы частоты ---
    final tight = Api(
      db,
      uploadsDir: dir.path,
      reviewIpLimiter: SlidingWindowLimiter(
        max: 2,
        window: const Duration(minutes: 10),
      ),
    );
    final tightApp = const Pipeline()
        .addMiddleware(errorHandler())
        .addHandler(tight.router.call);
    Future<int> send(String path, Object body) async {
      final res = await tightApp(
        Request(
          'POST',
          Uri.parse('http://localhost$path'),
          body: jsonEncode(body),
          headers: const {'content-type': 'application/json'},
        ),
      );
      await res.readAsString();
      return res.statusCode;
    }

    final codes = <int>[];
    for (var i = 0; i < 3; i++) {
      codes.add(await send('/api/public/reviews', _review(comment: 'раз $i')));
    }
    expect(
      'третий отзыв подряд с одного адреса — отказ',
      codes[0] == 201 && codes[1] == 201 && codes[2] == 429,
      codes,
    );

    // Бюджеты раздельные: исчерпанные отзывы не закрывают приём заказов
    db.execute(
      "update branches set orders_enabled = 1, order_whatsapp = '996555112233' "
      "where id = '$_branchId'",
    );
    db.execute(
      "insert into products (id, branch_id, name, price, is_visible) values "
      "('p1', '$_branchId', 'Лагман', 280, 1)",
    );
    final orderCode = await send('/api/public/orders', {
      'branch_id': _branchId,
      'code': 'AAA111',
      'order_type': 'pickup',
      'name': 'Азамат',
      'phone': '0555112233',
      'address': '',
      'comment': '',
      'lang': 'ru',
      'items': [
        {'product_id': 'p1', 'portion': '', 'qty': 1, 'name': 'Лагман'},
      ],
    });
    expect(
      'предел отзывов не мешает заказать',
      orderCode == 201,
      orderCode,
    );

    db.close();
  } finally {
    // Если проверка упала, база осталась открытой и папку Windows не отдаст.
    // Важна причина падения, а не временная папка, — поэтому молча
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }

  stdout.writeln(
    failures == 0 ? '\nВсе проверки прошли' : '\nОшибок: $failures',
  );
  exit(failures == 0 ? 0 : 1);
}
