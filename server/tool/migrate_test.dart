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
      "insert into categories (id, branch_id, name, name_en) values ('k', 'b', 'Горячее', 'Hot')",
    );
    old.execute(
      '''insert into products (id, branch_id, category_id, name, name_en, name_tr,
                               description, desc_en, price, portions)
                   values ('p', 'b', 'k', 'Плов', 'Pilaf', 'Pilav', 'С мясом',
                           'With meat', 350, '[{"name":"Большая","price":450}]')''',
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
    final catalog = db
        .select(
          "select show_in_catalog, description, logo_url, cover_url from cafes where id = 'c'",
        )
        .first;
    expect(
      'старое кафе не попало в каталог само, поля карточки пустые',
      catalog['show_in_catalog'] == 0 &&
          catalog['description'] == '' &&
          catalog['logo_url'] == '' &&
          catalog['cover_url'] == '',
      catalog,
    );
    expect(
      'таблица истории оплат создана',
      db
          .select("select 1 from sqlite_master where name = 'payments'")
          .isNotEmpty,
    );
    expect(
      'таблицы счётчика просмотров созданы',
      db
          .select(
            "select name from sqlite_master where name in "
            "('branch_views', 'branch_view_devices')",
          )
          .length ==
          2,
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
      'у филиалов появились пустые адрес, ссылка на карту и часы',
      branchCols.containsAll(locationColumns) &&
          db
                  .select("select address, map_url, hours from branches where id = 'b'")
                  .first
                  .values
                  .every((v) => v == ''),
      branchCols,
    );
    expect(
      'старый филиал сохранил три языка',
      db
              .select("select languages from branches where id = 'b'")
              .first['languages'] ==
          '["ru","en","tr"]',
    );
    final cat = db.select("select * from categories where id = 'k'").first;
    expect(
      'переводы категории — в i18n, старых колонок нет',
      cat['i18n'] == '{"en":{"name":"Hot"}}' && !cat.containsKey('name_en'),
      cat,
    );
    expect(
      'переводы блюда — в i18n, пустой турецкий описания не появился',
      row['i18n'] ==
              '{"en":{"name":"Pilaf","description":"With meat"},"tr":{"name":"Pilav"}}' &&
          !columns(db).any((c) => c.endsWith('_en') || c.endsWith('_tr')),
      row,
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
    // Заказы с сайта: таблица создаётся сама (create table if not exists),
    // а две колонки филиала надо было досоздать
    expect(
      'таблица orders появилась',
      db
              .select(
                "select count(*) n from sqlite_master where name = 'orders'",
              )
              .first['n'] ==
          1,
    );
    final orderCols = db
        .select('pragma table_info(branches)')
        .map((r) => r['name'])
        .toSet();
    expect(
      'у филиала появились order_whatsapp и delivery_price',
      orderCols.contains('order_whatsapp') &&
          orderCols.contains('delivery_price'),
      orderCols,
    );
    final branchRow = db.select('select * from branches limit 1').first;
    expect(
      'у старых филиалов заказы выключены, доставка 0',
      branchRow['order_whatsapp'] == '' && branchRow['delivery_price'] == 0,
      branchRow,
    );
    // Право на заказы — услуга от владельца платформы, а не настройка
    // кафе: задним числом оно не включается никому. И оно у каждого
    // филиала своё, в кафе такой колонки быть не должно
    expect(
      'право orders_enabled появилось у филиала',
      orderCols.contains('orders_enabled'),
      orderCols,
    );
    expect(
      'и у старых филиалов оно выключено',
      db
              .select('select count(*) n from branches where orders_enabled = 0')
              .first['n'] ==
          db.select('select count(*) n from branches').first['n'],
      db
          .select('select id, orders_enabled from branches')
          .map((r) => r)
          .toList(),
    );
    expect(
      'у кафе этой колонки нет — право хранится в одном месте',
      !db
          .select('pragma table_info(cafes)')
          .map((r) => r['name'])
          .contains('orders_enabled'),
    );
    // Отзывы гостей: таблица создаётся сама, две колонки филиала надо было
    // досоздать. Право задним числом не выдаётся никому
    expect(
      'таблица reviews появилась',
      db
              .select("select count(*) n from sqlite_master where name = 'reviews'")
              .first['n'] ==
          1,
    );
    final reviewCols = db
        .select('pragma table_info(branches)')
        .map((r) => r['name'])
        .toSet();
    expect(
      'у филиала появилось право reviews_enabled',
      reviewCols.contains('reviews_enabled'),
      reviewCols,
    );
    expect(
      'и у старых филиалов отзывы выключены',
      db
              .select('select count(*) n from branches where reviews_enabled = 0')
              .first['n'] ==
          db.select('select count(*) n from branches').first['n'],
      db
          .select('select id, reviews_enabled from branches')
          .map((r) => r)
          .toList(),
    );
    expect(
      'номера для пересылки отзывов нет — отзыв никуда не пересылается',
      !reviewCols.contains('review_whatsapp'),
      reviewCols,
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

    // Промежуточная версия держала право на заказы у кафе. Его значение
    // должно достаться всем филиалам этого кафе, а колонка — уйти
    final moved = '${dir.path}/moved.db';
    final old2 = sqlite3.open(moved);
    old2.execute(_oldSchema);
    old2.execute(
      "insert into cafes (id, name) values ('yes', 'С заказами'), "
      "('no', 'Без заказов')",
    );
    old2.execute(
      'alter table cafes add column orders_enabled integer not null default 0',
    );
    old2.execute("update cafes set orders_enabled = 1 where id = 'yes'");
    old2.execute(
      "insert into branches (id, cafe_id, slug, name) values "
      "('b-yes', 'yes', 's1', 'Центр'), ('b-yes2', 'yes', 's2', 'Второй'), "
      "('b-no', 'no', 's3', 'Чужой')",
    );
    old2.close();
    final db3 = openDb(moved);
    expect(
      'право кафе досталось всем его филиалам и только им',
      db3
              .select(
                'select id from branches where orders_enabled = 1 order by id',
              )
              .map((r) => r['id'])
              .join(',') ==
          'b-yes,b-yes2',
      db3.select('select id, orders_enabled from branches').map((r) => r).toList(),
    );
    expect(
      'а колонка у кафе убрана',
      !db3
          .select('pragma table_info(cafes)')
          .map((r) => r['name'])
          .contains('orders_enabled'),
    );
    db3.close();
  } finally {
    dir.deleteSync(recursive: true);
  }

  stdout.writeln(
    failures == 0 ? '\nВсе проверки прошли' : '\nОшибок: $failures',
  );
  exit(failures == 0 ? 0 : 1);
}
