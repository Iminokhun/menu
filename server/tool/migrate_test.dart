// Проверка обновления старой базы: openDb() должен досоздать новые колонки
// в базе, созданной прежней версией сервера, и не потерять данные.
// Запуск: dart run tool/migrate_test.dart
import 'dart:io';

import 'package:menu_server/billing.dart';
import 'package:menu_server/db.dart';
import 'package:sqlite3/sqlite3.dart';

var failures = 0;

void expect(String what, bool ok, [Object? info]) {
  stdout.writeln('${ok ? 'OK  ' : 'FAIL'} $what${ok ? '' : '  → $info'}');
  if (!ok) failures++;
}

/// Таблицы в том виде, в каком их создавал сервер до 3D-моделей:
/// у products нет колонки model_url.
const _oldSchema = '''
create table cafes (
  id           text primary key,
  name         text    not null,
  is_active    integer not null default 1,
  max_branches integer not null default 1,
  created_at   text    not null default (datetime('now'))
);
create table branches (
  id         text primary key,
  cafe_id    text not null references cafes(id) on delete cascade,
  slug       text not null unique collate nocase,
  name       text    not null default '',
  slogan     text    not null default '',
  phone      text    not null default '',
  logo_url   text    not null default '',
  qr_url     text    not null default '',
  is_active  integer not null default 1,
  sort_order integer not null default 0
);
create table categories (
  id         text primary key,
  branch_id  text not null references branches(id) on delete cascade,
  parent_id  text references categories(id) on delete set null,
  name       text    not null default '',
  name_en    text    not null default '',
  name_tr    text    not null default '',
  image_url  text    not null default '',
  is_visible integer not null default 1,
  sort_order integer not null default 0
);
create table products (
  id          text primary key,
  branch_id   text not null references branches(id) on delete cascade,
  category_id text references categories(id) on delete cascade,
  name        text    not null default '',
  name_en     text    not null default '',
  name_tr     text    not null default '',
  description text    not null default '',
  desc_en     text    not null default '',
  desc_tr     text    not null default '',
  price       real    not null default 0,
  image_url   text    not null default '',
  is_visible  integer not null default 1,
  sort_order  integer not null default 0,
  portions    text    not null default '[]'
);
''';

Set<String> columns(Database db) => db
    .select('pragma table_info(products)')
    .map((r) => r['name'] as String)
    .toSet();

void main() {
  final dir = Directory.systemTemp.createTempSync('menu_migrate_');
  final path = '${dir.path}/menu.db';
  try {
    // База прежней версии с одним кафе и одним блюдом
    final old = sqlite3.open(path);
    old.execute(_oldSchema);
    old.execute("insert into cafes (id, name) values ('c', 'Андалус')");
    old.execute(
      "insert into branches (id, cafe_id, slug, name) values ('b', 'c', 'center', 'Центр')",
    );
    old.execute(
      "insert into categories (id, branch_id, name) values ('k', 'b', 'Горячее')",
    );
    old.execute(
      '''insert into products (id, branch_id, category_id, name, price, portions)
                   values ('p', 'b', 'k', 'Плов', 350, '[{"name":"Большая","price":450}]')''',
    );
    expect('старая база без model_url', !columns(old).contains('model_url'));
    old.close();

    // Новая версия сервера открывает её
    final db = openDb(path);
    expect('колонка model_url добавлена', columns(db).contains('model_url'));
    final row = db.select("select * from products where id = 'p'").first;
    expect(
      'старое блюдо на месте, model_url пустой',
      row['name'] == 'Плов' &&
          row['price'] == 350 &&
          row['portions'] == '[{"name":"Большая","price":450}]' &&
          row['model_url'] == '',
      row,
    );
    db.execute(
      '''insert into products (id, branch_id, category_id, name, model_url)
                  values ('p2', 'b', 'k', 'Авокадо', '/uploads/c/m.glb')''',
    );
    expect(
      'новое блюдо с 3D-моделью сохраняется',
      db
              .select("select model_url from products where id = 'p2'")
              .first['model_url'] ==
          '/uploads/c/m.glb',
    );
    expect(
      'остальные данные целы',
      db.select('select count(*) n from cafes').first['n'] == 1 &&
          db.select('select count(*) n from branches').first['n'] == 1 &&
          db.select('select count(*) n from categories').first['n'] == 1,
    );
    final cafe = db
        .select("select plan, paid_until from cafes where id = 'c'")
        .first;
    final month = formatDate(DateTime.now().add(const Duration(days: 30)));
    expect(
      'старое кафе получило пробный месяц, а не выключенное меню',
      cafe['plan'] == 'trial' && cafe['paid_until'] == month,
      cafe,
    );
    expect(
      'таблица истории оплат создана',
      db
          .select("select 1 from sqlite_master where name = 'payments'")
          .isNotEmpty,
    );
    final branchCols = db
        .select('pragma table_info(branches)')
        .map((r) => r['name'])
        .toSet();
    expect(
      'у филиалов появились колонки оформления',
      branchCols.containsAll(styleColumns) &&
          db
                  .select("select theme, accent from branches where id = 'b'")
                  .first['theme'] ==
              '',
      branchCols,
    );
    expect(
      'новые таблицы созданы (users, sessions)',
      db
              .select(
                "select count(*) n from sqlite_master where name in ('users', 'sessions')",
              )
              .first['n'] ==
          2,
    );
    db.close();

    // Повторный запуск ничего не ломает
    Object? again;
    try {
      final db2 = openDb(path);
      expect(
        'повторный запуск: колонка одна, блюд два',
        columns(db2).where((c) => c == 'model_url').length == 1 &&
            db2.select('select count(*) n from products').first['n'] == 2,
      );
      db2.close();
    } catch (e) {
      again = e;
    }
    expect('повторный запуск без ошибки', again == null, again);
  } finally {
    dir.deleteSync(recursive: true);
  }

  stdout.writeln(
    failures == 0 ? '\nВсе проверки прошли' : '\nОшибок: $failures',
  );
  exit(failures == 0 ? 0 : 1);
}
