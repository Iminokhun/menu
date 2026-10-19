import 'dart:math';

import 'package:sqlite3/sqlite3.dart';

import 'billing.dart';

/// Схема базы. Применяется при каждом запуске: все `create` идемпотентны.
///
/// Булевы поля хранятся как 0/1 (в SQLite нет отдельного типа) и
/// превращаются в true/false при отдаче наружу — см. [rowToJson].
const _schema = '''
create table if not exists cafes (
  id           text primary key,
  name         text    not null,
  is_active    integer not null default 1,
  -- Сколько филиалов кафе вправе завести. Задаёт только superadmin.
  max_branches integer not null default 1,
  -- Оплата (см. billing.dart): тариф и дата «оплачено до» включительно,
  -- YYYY-MM-DD; пустая — только у тарифа lifetime
  plan         text    not null default 'trial',
  paid_until   text    not null default '',
  created_at   text    not null default (datetime('now'))
);

-- История оплат: кто, сколько и за какой период заплатил
create table if not exists payments (
  id         text primary key,
  cafe_id    text not null references cafes(id) on delete cascade,
  period     text not null check (period in ('month', 'lifetime')),
  months     integer not null default 0,
  amount     real    not null default 0,
  currency   text    not null default 'KGS',
  note       text    not null default '',
  paid_until text    not null default '',
  created_by text,
  paid_at    text    not null default (datetime('now'))
);
create index if not exists payments_cafe_idx on payments (cafe_id, paid_at);

create table if not exists users (
  id            text primary key,
  cafe_id       text references cafes(id) on delete cascade,
  login         text not null unique collate nocase,
  password_hash text not null,
  role          text not null check (role in ('superadmin', 'cafe_admin')),
  is_active     integer not null default 1,
  created_at    text not null default (datetime('now')),
  -- У superadmin кафе нет, у админа кафе оно обязательно
  check ((role = 'superadmin') = (cafe_id is null))
);

create table if not exists sessions (
  token      text primary key,
  user_id    text not null references users(id) on delete cascade,
  expires_at text not null
);

create table if not exists branches (
  id         text primary key,
  cafe_id    text not null references cafes(id) on delete cascade,
  slug       text not null unique collate nocase,
  name       text    not null default '',
  slogan     text    not null default '',
  phone      text    not null default '',
  logo_url   text    not null default '',
  qr_url     text    not null default '',
  -- Оформление меню филиала; пусто — как по умолчанию
  theme      text    not null default '',
  accent     text    not null default '',
  bg_url     text    not null default '',
  card_size  text    not null default '',
  corners    text    not null default '',
  title_font text    not null default '',
  is_active  integer not null default 1,
  sort_order integer not null default 0
);

create table if not exists categories (
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

create table if not exists products (
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
  model_url   text    not null default '',
  is_visible  integer not null default 1,
  sort_order  integer not null default 0,
  portions    text    not null default '[]'
);

create index if not exists branches_cafe_idx    on branches (cafe_id, sort_order);
create index if not exists categories_branch_idx on categories (branch_id, sort_order);
create index if not exists products_branch_idx   on products (branch_id, sort_order);
create index if not exists sessions_user_idx     on sessions (user_id);

-- Лимит филиалов держит сама база, а не только API: так его не обойти
-- ни старой версией приложения, ни ручным запросом.
create trigger if not exists branches_limit
before insert on branches
begin
  select raise(abort, 'BRANCH_LIMIT')
   where (select count(*) from branches where cafe_id = new.cafe_id)
      >= (select max_branches from cafes where id = new.cafe_id);
end;
''';

Database openDb(String path) {
  final db = sqlite3.open(path);
  db.execute('pragma foreign_keys = on;');
  db.execute('pragma journal_mode = wal;');
  db.execute('pragma busy_timeout = 5000;');
  db.execute(_schema);
  _migrate(db);
  return db;
}

/// Колонки, добавленные после первого запуска: `create table if not exists`
/// не трогает уже созданные таблицы, поэтому досоздаём их сами.
void _migrate(Database db) {
  final cols = db
      .select('pragma table_info(products)')
      .map((r) => r['name'])
      .toSet();
  // 3D-модель блюда (.glb), необязательная
  if (!cols.contains('model_url')) {
    db.execute(
      "alter table products add column model_url text not null default ''",
    );
  }

  // Оформление меню филиала: тема, цвет, фон, карточки, шрифт
  final branchCols = db
      .select('pragma table_info(branches)')
      .map((r) => r['name'])
      .toSet();
  for (final col in styleColumns) {
    if (!branchCols.contains(col)) {
      db.execute(
        "alter table branches add column $col text not null default ''",
      );
    }
  }

  // Оплата. Кафе, заведённые до неё, получают пробный месяц: иначе в день
  // обновления сервера меню у всех выключилось бы
  final cafeCols = db
      .select('pragma table_info(cafes)')
      .map((r) => r['name'])
      .toSet();
  if (!cafeCols.contains('plan')) {
    final until = formatDate(DateTime.now().add(const Duration(days: 30)));
    db.execute('begin');
    try {
      db.execute(
        "alter table cafes add column plan text not null default 'trial'",
      );
      db.execute(
        "alter table cafes add column paid_until text not null default ''",
      );
      db.execute('update cafes set paid_until = ?', [until]);
      db.execute('commit');
    } catch (_) {
      db.execute('rollback');
      rethrow;
    }
  }
}

final _rnd = Random.secure();

/// UUID v4 строкой — в том же виде, что выдавал Supabase, поэтому
/// при переносе данных id сохраняются как есть.
String newId() {
  final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// Поля 0/1, которые наружу отдаются как true/false.
const boolColumns = {'is_active', 'is_visible'};

Map<String, Object?> rowToJson(Row row) {
  final m = <String, Object?>{};
  for (final k in row.keys) {
    final v = row[k];
    m[k] = boolColumns.contains(k) && v is int ? v != 0 : v;
  }
  return m;
}

/// Колонки оформления филиала (см. схему branches)
const styleColumns = [
  'theme',
  'accent',
  'bg_url',
  'card_size',
  'corners',
  'title_font',
];

Object? toSql(Object? v) => v is bool ? (v ? 1 : 0) : v;
