// Проверка счётчика просмотров: один человек за день считается один раз,
// там, где меню не показалось, не считается ничего, день кончается по
// местному времени, метки устройств чистятся, а цифры видит только
// владелец платформы.
// Запуск: dart run tool/views_test.dart
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

/// Филиал, по которому считаем
const _slug = 'center';

/// Второй филиал того же кафе: у кафе — сумма, у филиалов — врозь
const _second = 'second';

/// Выключенный филиал работающего кафе
const _off = 'closed';

/// Филиал выключенного кафе
const _blocked = 'blocked';

/// Филиал кафе, у которого кончилась оплата
const _unpaid = 'unpaid';

void _seed(Database db) {
  db.execute(
    "insert into cafes (id, name, is_active, max_branches, plan, paid_until) "
    "values ('cafe-1', 'Тест', 1, 5, 'lifetime', '')",
  );
  db.execute(
    "insert into cafes (id, name, is_active, max_branches, plan, paid_until) "
    "values ('cafe-2', 'Заблокировано', 0, 5, 'lifetime', '')",
  );
  db.execute(
    "insert into cafes (id, name, is_active, max_branches, plan, paid_until) "
    "values ('cafe-3', 'Не оплачено', 1, 5, 'month', '2020-01-01')",
  );
  db.execute(
    "insert into branches (id, cafe_id, slug, name) values "
    "('b1', 'cafe-1', '$_slug', 'Центр')",
  );
  db.execute(
    "insert into branches (id, cafe_id, slug, name) values "
    "('b2', 'cafe-1', '$_second', 'Второй')",
  );
  db.execute(
    "insert into branches (id, cafe_id, slug, name, is_active) values "
    "('b3', 'cafe-1', '$_off', 'Закрыт', 0)",
  );
  db.execute(
    "insert into branches (id, cafe_id, slug, name) values "
    "('b4', 'cafe-2', '$_blocked', 'Чужой')",
  );
  db.execute(
    "insert into branches (id, cafe_id, slug, name) values "
    "('b5', 'cafe-3', '$_unpaid', 'Должник')",
  );
}

/// Строка итогов филиала за день: (людей, открытий)
(int, int) _row(Database db, String branchId, String day) {
  final rows = db.select(
    'select people, opens from branch_views where branch_id = ? and day = ?',
    [branchId, day],
  );
  if (rows.isEmpty) return (0, 0);
  return (rows.first['people'] as int, rows.first['opens'] as int);
}

int _count(Database db, String table) =>
    db.select('select count(*) as n from $table').first['n'] as int;

Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('menu_views_');
  try {
    final db = openDb('${dir.path}/menu.db');
    _seed(db);
    // tzOffsetHours: 0 — чтобы «сегодня» у сервера и у теста считалось
    // одинаково; сам сдвиг проверяется отдельно, через localDay.
    // Пределы широкие: они проверяются своим сервером ниже
    final api = Api(
      db,
      uploadsDir: dir.path,
      tzOffsetHours: 0,
      viewIpLimiter: SlidingWindowLimiter(
        max: 10000,
        window: const Duration(minutes: 10),
      ),
      viewBranchLimiter: SlidingWindowLimiter(
        max: 10000,
        window: const Duration(minutes: 10),
      ),
    );
    final app = const Pipeline()
        .addMiddleware(errorHandler())
        .addHandler(api.router.call);

    final today = localDay(DateTime.now(), 0);

    Future<int> view(String slug, String device) async {
      final res = await app(
        Request(
          'POST',
          Uri.parse('http://localhost/api/public/view'),
          body: jsonEncode({'slug': slug, 'device': device}),
          headers: const {'content-type': 'application/json'},
        ),
      );
      await res.readAsString();
      return res.statusCode;
    }

    // --- Один просмотр ---
    expect('отметка принята', await view(_slug, 'dev-1') == 204);
    expect(
      'один человек, одно открытие',
      _row(db, 'b1', today) == (1, 1),
      _row(db, 'b1', today),
    );

    // --- То же устройство второй раз за день ---
    await view(_slug, 'dev-1');
    expect(
      'тот же человек не считается дважды',
      _row(db, 'b1', today) == (1, 2),
      _row(db, 'b1', today),
    );

    // --- Другое устройство ---
    await view(_slug, 'dev-2');
    expect(
      'другое устройство — другой человек',
      _row(db, 'b1', today) == (2, 3),
      _row(db, 'b1', today),
    );

    // --- Второй филиал считается отдельно ---
    await view(_second, 'dev-1');
    expect(
      'у филиалов цифры врозь',
      _row(db, 'b2', today) == (1, 1),
      _row(db, 'b2', today),
    );

    // --- Где меню не показалось, не считается ничего ---
    final before = _count(db, 'branch_views');
    expect(
      'неизвестный филиал — 404',
      await view('нет-такого', 'dev-3') == 404,
    );
    expect('выключенный филиал — 404', await view(_off, 'dev-3') == 404);
    expect('выключенное кафе — 404', await view(_blocked, 'dev-3') == 404);
    expect('кончилась оплата — 403', await view(_unpaid, 'dev-3') == 403);
    expect(
      'ни одной новой строки',
      _count(db, 'branch_views') == before,
      _count(db, 'branch_views'),
    );

    // --- Мусор в теле ---
    expect('без филиала — 400', await view('', 'dev-3') == 400);
    expect('без устройства — 400', await view(_slug, '') == 400);
    expect(
      'длинная метка устройства — 400',
      await view(_slug, 'd' * 200) == 400,
    );

    // --- День кончается по местному времени ---
    // 23:30 в Бишкеке (+6) — это 17:30 UTC того же числа, а 00:30 уже
    // следующего — 18:30 UTC прежнего. По UTC это один день, по местному
    // времени разные: именно за этим и нужен TZ_OFFSET_H
    final evening = DateTime.utc(2026, 11, 21, 17, 30);
    final night = DateTime.utc(2026, 11, 21, 18, 30);
    expect(
      'вечер — свой день',
      localDay(evening, 6) == '2026-11-21',
      localDay(evening, 6),
    );
    expect(
      'после полуночи — следующий',
      localDay(night, 6) == '2026-11-22',
      localDay(night, 6),
    );
    expect(
      'по UTC это был бы один день',
      localDay(evening, 0) == localDay(night, 0),
    );

    // --- Разные дни — разные строки, «всего» — их сумма ---
    countView(db, branchId: 'b1', device: 'dev-9', day: '2026-11-01');
    countView(db, branchId: 'b1', device: 'dev-9', day: '2026-11-02');
    final total =
        db.select(
              'select sum(people) as n from branch_views where branch_id = ?',
              ['b1'],
            ).first['n']
            as int;
    expect('«всего» — сумма по дням', total == 4, total);

    // --- Чистка меток ---
    countView(db, branchId: 'b1', device: 'dev-8', day: '2020-01-01');
    final marks = _count(db, 'branch_view_devices');
    final purged = purgeOldViewDevices(db);
    expect('старые метки удалены', purged > 0, purged);
    expect('остались только свежие', _count(db, 'branch_view_devices') < marks);
    expect(
      'итоги чистка не трогает',
      db
              .select(
                "select people from branch_views where branch_id = 'b1' "
                "and day = '2020-01-01'",
              )
              .first['people'] ==
          1,
    );

    // --- Цифры в списке кафе ---
    db.execute(
      "insert into users (id, login, password_hash, role) values "
      "('u1', 'boss', 'x', 'superadmin')",
    );
    db.execute(
      "insert into users (id, cafe_id, login, password_hash, role) values "
      "('u2', 'cafe-1', 'cafe', 'x', 'cafe_admin')",
    );
    final boss = createSession(db, 'u1');
    final cafeAdmin = createSession(db, 'u2');

    Future<(int, Object?)> get(String path, String token) async {
      final res = await app(
        Request(
          'GET',
          Uri.parse('http://localhost$path'),
          headers: {'authorization': 'Bearer $token'},
        ),
      );
      final text = await res.readAsString();
      return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
    }

    var (status, body) = await get('/api/super/cafes', boss);
    final cafes = List<Map<String, dynamic>>.from(body as List);
    final mine = cafes.firstWhere((c) => c['id'] == 'cafe-1');
    final branches = List<Map<String, dynamic>>.from(mine['branches'] as List);
    expect('список кафе отдан', status == 200);
    expect(
      'у кафе есть «сегодня»',
      mine['views_today'] == 3,
      mine['views_today'],
    );
    // 2 за сегодня у b1, по одному за 1 и 2 ноября и за 2020-й (их
    // дописали проверки выше) и 1 за сегодня у b2
    expect(
      'у кафе есть «всего»',
      mine['views_total'] == 6,
      mine['views_total'],
    );
    expect(
      'у филиала свои цифры',
      branches.firstWhere((b) => b['id'] == 'b2')['views_today'] == 1,
    );
    expect(
      'у филиала без просмотров ноль, а не null',
      branches.firstWhere((b) => b['id'] == 'b3')['views_total'] == 0,
    );
    expect(
      'у кафе без просмотров ноль, а не null',
      cafes.firstWhere((c) => c['id'] == 'cafe-2')['views_today'] == 0,
    );

    // --- Подробности по кафе ---
    (status, body) = await get('/api/super/cafes/cafe-1/views?days=30', boss);
    var m = Map<String, Object?>.from(body as Map);
    expect('подробности отданы', status == 200);
    expect('есть ряд по дням', (m['days'] as List).isNotEmpty);
    expect(
      'в ряду только дни запрошенного окна',
      (m['days'] as List).every((d) => (d as Map)['day'] != '2020-01-01'),
      m['days'],
    );
    expect(
      'есть все филиалы кафе',
      (m['branches'] as List).length == 3,
      (m['branches'] as List).length,
    );

    (status, body) = await get('/api/super/cafes/cafe-1/views?days=365', boss);
    m = Map<String, Object?>.from(body as Map);
    expect(
      'окно пошире достаёт и старые дни',
      (m['days'] as List).length > 1,
      (m['days'] as List).length,
    );

    (status, _) = await get('/api/super/cafes/cafe-1/views', cafeAdmin);
    expect('кафе чужих цифр не видит — 403', status == 403, status);

    // --- Удалили филиал — просмотры ушли с ним ---
    db.execute("delete from branches where id = 'b2'");
    expect(
      'просмотры удалённого филиала не остались',
      db.select("select 1 from branch_views where branch_id = 'b2'").isEmpty,
    );

    db.close();

    // --- Предел частоты: шквал по одному филиалу ---
    final db2 = openDb('${dir.path}/limits.db');
    _seed(db2);
    final tight = Api(
      db2,
      uploadsDir: dir.path,
      tzOffsetHours: 0,
      viewBranchLimiter: SlidingWindowLimiter(
        max: 2,
        window: const Duration(minutes: 10),
      ),
    );
    final app2 = const Pipeline()
        .addMiddleware(errorHandler())
        .addHandler(tight.router.call);
    Future<int> view2(String device) async {
      final res = await app2(
        Request(
          'POST',
          Uri.parse('http://localhost/api/public/view'),
          body: jsonEncode({'slug': _slug, 'device': device}),
          headers: const {'content-type': 'application/json'},
        ),
      );
      await res.readAsString();
      return res.statusCode;
    }

    expect('первая отметка проходит', await view2('a') == 204);
    expect('вторая проходит', await view2('b') == 204);
    expect('третья упирается в предел', await view2('c') == 429);
    expect(
      'сверх предела в базу не пишется',
      _row(db2, 'b1', today) == (2, 2),
      _row(db2, 'b1', today),
    );
    db2.close();
  } finally {
    // На Windows папку не отдать, если база осталась открытой после
    // неудачной проверки. Сама неудача важнее временной папки
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }

  stdout.writeln(
    failures == 0 ? '\nВсе проверки прошли' : '\nОшибок: $failures',
  );
  exit(failures == 0 ? 0 : 1);
}
