import 'dart:convert';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';

import 'billing.dart';
import 'languages.dart';

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
  -- Карточка в общем каталоге на главной сайта: показывать ли кафе,
  -- описание, логотип и обложка. Включает только superadmin.
  show_in_catalog integer not null default 0,
  description  text    not null default '',
  logo_url     text    not null default '',
  cover_url    text    not null default '',
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

-- Внимание: /api/public/branch/<slug> отдаёт гостю строку целиком
-- (`select b.*`). Любая колонка отсюда видна всем — секретов не класть.
-- Ключи внешних сервисов живут в переменных окружения.
create table if not exists branches (
  id         text primary key,
  cafe_id    text not null references cafes(id) on delete cascade,
  slug       text not null unique collate nocase,
  name       text    not null default '',
  slogan     text    not null default '',
  phone      text    not null default '',
  logo_url   text    not null default '',
  qr_url     text    not null default '',
  -- Где филиал: адрес, ссылка на 2GIS / Google Maps, часы работы.
  -- Заполняет кафе, гость видит их в каталоге на главной
  address    text    not null default '',
  map_url    text    not null default '',
  hours      text    not null default '',
  -- Оформление меню филиала; пусто — как по умолчанию
  theme      text    not null default '',
  accent     text    not null default '',
  bg_url     text    not null default '',
  card_size  text    not null default '',
  corners    text    not null default '',
  title_font text    not null default '',
  -- Языки меню (languages.dart), JSON-массив: первый — основной
  languages  text    not null default '["ru"]',
  -- Куда уходят заказы гостей. Только цифры с кодом страны: 996555112233 —
  -- значение подставляется в ссылку wa.me как есть. Пусто — кнопки заказа нет
  order_whatsapp text not null default '',
  -- Стоимость доставки, в тех же единицах, что цены блюд. 0 — бесплатно
  delivery_price real not null default 0,
  -- Право принимать заказы с сайта. Выдаёт только superadmin, и каждому
  -- филиалу отдельно: у кафе бывает точка с доставкой и точка, где заказы
  -- принимать некому. Пока право не выдано, номер WhatsApp гостю не
  -- показывается и заказы не принимаются, даже если номер заполнен.
  orders_enabled integer not null default 0,
  -- Право принимать отзывы. Выдаёт только superadmin, каждому филиалу
  -- своё — как orders_enabled. Отзыв никуда не пересылается: он просто
  -- ложится сюда, и кафе читает его в своей админке
  reviews_enabled integer not null default 0,
  is_active  integer not null default 1,
  sort_order integer not null default 0
);

create table if not exists categories (
  id         text primary key,
  branch_id  text not null references branches(id) on delete cascade,
  parent_id  text references categories(id) on delete set null,
  -- name — на основном языке филиала, переводы — в i18n:
  -- {"en": {"name": "..."}, ...}
  name       text    not null default '',
  i18n       text    not null default '{}',
  image_url  text    not null default '',
  is_visible integer not null default 1,
  sort_order integer not null default 0
);

create table if not exists products (
  id          text primary key,
  branch_id   text not null references branches(id) on delete cascade,
  category_id text references categories(id) on delete cascade,
  -- name и description — на основном языке филиала, переводы — в i18n:
  -- {"en": {"name": "...", "description": "..."}, ...}
  name        text    not null default '',
  description text    not null default '',
  i18n        text    not null default '{}',
  price       real    not null default 0,
  image_url   text    not null default '',
  model_url   text    not null default '',
  is_visible  integer not null default 1,
  sort_order  integer not null default 0,
  portions    text    not null default '[]'
);

-- Заказы гостей с сайта. Здесь лежат личные данные — имя, телефон, адрес, —
-- поэтому читает их только кафе через /api/admin/orders. Публичного чтения
-- нет и быть не должно, в SEO-страницы они не попадают.
create table if not exists orders (
  id             text primary key,
  branch_id      text not null references branches(id) on delete cascade,
  -- Короткий код заказа. Его придумывает клиент до открытия WhatsApp, потому
  -- что текст сообщения собирается раньше, чем ответит сервер. По нему же
  -- отбрасываются повторы при двойном нажатии
  code           text not null default '',
  order_type     text not null check (order_type in ('delivery', 'pickup')),
  guest_name     text not null,
  guest_phone    text not null,
  -- Заполнен только у доставки; у самовывоза сервер принудительно пишет ''
  address        text not null default '',
  comment        text not null default '',
  -- На каком языке гость читал меню
  lang           text not null default '',
  -- Снимок позиций, JSON. Заказ — это чек: имя и цена должны застыть на
  -- момент заказа, поэтому не ссылка на products, а копия
  items          text not null default '[]',
  -- Все три суммы считает сервер, клиент денег не присылает вовсе
  items_total    real not null default 0,
  delivery_total real not null default 0,
  total          real not null default 0,
  status         text not null default 'new' check (status in ('new', 'done')),
  -- Как заказ ушёл сотруднику; 'server' — на будущее, когда отправлять
  -- будет сам сервер
  delivery       text not null default 'wa_link',
  sent_at        text,
  created_at     text not null default (datetime('now'))
);

-- Отзывы гостей с сайта. Здесь личные данные сразу двух людей: имя
-- официанта, на которого жалуются, и свободный текст гостя, куда он может
-- вписать что угодно, вплоть до своего телефона. Поэтому читает их только
-- кафе через /api/admin/reviews: публичного чтения нет, гостям чужие отзывы
-- не показываются, в SEO-страницы они не попадают.
-- Строки старше 40 дней сервер удаляет сам (purgeOldReviews).
create table if not exists reviews (
  id         text primary key,
  branch_id  text    not null references branches(id) on delete cascade,
  -- Единственное обязательное поле: без оценки отправлять нечего
  rating     integer not null check (rating between 1 and 5),
  waiter     text    not null default '',
  -- Текст, а не число: гости пишут «12», «VIP-2», «терраса».
  -- И table — зарезервированное слово SQL, отсюда _no
  table_no   text    not null default '',
  comment    text    not null default '',
  -- На каком языке гость читал меню
  lang       text    not null default '',
  created_at text    not null default (datetime('now'))
);

-- Сколько разных людей открывали меню филиала в какой день. Считает
-- POST /api/public/view; смотрит это только владелец платформы в /menu-kg/.
--
-- Итог, а не журнал посещений: одна строка на филиал в день, и в ней
-- только два числа. Кто именно заходил, здесь не хранится и храниться не
-- может — ни адреса, ни метки устройства, ни времени с точностью до часа.
-- Строки не удаляются: это и есть «всего за всё время», а растёт таблица
-- на 365 строк в год на филиал.
--
-- day — местный день (TZ_OFFSET_H), а не UTC: иначе день кафе начинался бы
-- в 6 утра и вечерние гости попадали бы в завтрашнюю цифру.
create table if not exists branch_views (
  branch_id text    not null references branches(id) on delete cascade,
  day       text    not null,
  -- Разных устройств за день
  people    integer not null default 0,
  -- Сколько раз меню открывали всего. Сейчас не показывается нигде, но
  -- считается: «часто ли возвращаются» иначе придётся собирать с нуля
  opens     integer not null default 0,
  primary key (branch_id, day)
);

-- Чтобы один человек за день считался один раз. device — случайная строка,
-- которую приложение само себе придумало и держит в памяти браузера; она
-- не связана ни с гостем, ни с заказом, ни с отзывом, и очистка браузера
-- делает её новой. Живёт пару дней (purgeOldViewDevices): для «сегодня»
-- больше не нужно, а итог уже сложен в branch_views.
create table if not exists branch_view_devices (
  branch_id text not null references branches(id) on delete cascade,
  day       text not null,
  device    text not null,
  primary key (branch_id, day, device)
);

create index if not exists branches_cafe_idx    on branches (cafe_id, sort_order);
create index if not exists orders_branch_idx     on orders (branch_id, created_at);
create index if not exists reviews_branch_idx    on reviews (branch_id, created_at);
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
  for (final col in [...styleColumns, ...locationColumns]) {
    if (!branchCols.contains(col)) {
      db.execute(
        "alter table branches add column $col text not null default ''",
      );
    }
  }

  // Заказы гостей: WhatsApp филиала и стоимость доставки. Обе колонки
  // появились разом, поэтому и проверка по одной
  if (!branchCols.contains('order_whatsapp')) {
    inTransaction(db, () {
      db.execute(
        "alter table branches add column order_whatsapp text not null default ''",
      );
      db.execute(
        'alter table branches add column delivery_price real not null default 0',
      );
    });
  }

  // Оплата. Кафе, заведённые до неё, получают пробный месяц: иначе в день
  // обновления сервера меню у всех выключилось бы
  final cafeCols = db
      .select('pragma table_info(cafes)')
      .map((r) => r['name'])
      .toSet();
  if (!cafeCols.contains('plan')) {
    final until = formatDate(DateTime.now().add(const Duration(days: 30)));
    inTransaction(db, () {
      db.execute(
        "alter table cafes add column plan text not null default 'trial'",
      );
      db.execute(
        "alter table cafes add column paid_until text not null default ''",
      );
      db.execute('update cafes set paid_until = ?', [until]);
    });
  }

  // Каталог кафе на главной. Старые кафе в него не попадают, пока
  // superadmin сам не включит
  if (!cafeCols.contains('show_in_catalog')) {
    inTransaction(db, () {
      db.execute(
        'alter table cafes add column show_in_catalog integer not null default 0',
      );
      for (final col in ['description', 'logo_url', 'cover_url']) {
        db.execute("alter table cafes add column $col text not null default ''");
      }
    });
  }

  // Право принимать заказы с сайта. Ноль всем, включая уже заведённые
  // филиалы: это услуга, которую владелец платформы выдаёт сам. Включать
  // задним числом нельзя — кафе, не знающее про заказы, их и не увидит.
  // Сначала право было одно на всё кафе; если такая колонка ещё есть, её
  // значение достаётся всем филиалам этого кафе, а сама она уходит: два
  // места для одного права — это вопрос «какое из них главнее»
  if (!branchCols.contains('orders_enabled')) {
    inTransaction(db, () {
      db.execute(
        'alter table branches add column orders_enabled integer not null '
        'default 0',
      );
      if (cafeCols.contains('orders_enabled')) {
        db.execute('''
          update branches set orders_enabled = 1 where cafe_id in
            (select id from cafes where orders_enabled = 1)''');
      }
    });
  }
  if (cafeCols.contains('orders_enabled')) {
    db.execute('alter table cafes drop column orders_enabled');
  }

  // Право принимать отзывы. Не включается задним числом никому: это
  // отдельная услуга, которую владелец платформы выдаёт сам
  if (!branchCols.contains('reviews_enabled')) {
    db.execute(
      'alter table branches add column reviews_enabled integer not null '
      'default 0',
    );
  }
  // Отзыв больше никуда не пересылается, только сохраняется. Номер для
  // пересылки убираем: колонка, которую никто не читает, через полгода
  // выглядит как настройка, которая «почему-то не работает»
  if (branchCols.contains('review_whatsapp')) {
    db.execute('alter table branches drop column review_whatsapp');
  }

  // Языки меню. Раньше их было три постоянных — филиалы, заведённые тогда,
  // их и сохраняют
  if (!branchCols.contains('languages')) {
    inTransaction(db, () {
      db.execute(
        "alter table branches add column languages text not null "
        "default '${jsonEncode(defaultLanguages)}'",
      );
      db.execute('update branches set languages = ?', [
        jsonEncode(['ru', 'en', 'tr']),
      ]);
    });
  }
  _moveTranslations(db, 'categories', {
    'name_en': ('en', 'name'),
    'name_tr': ('tr', 'name'),
  });
  _moveTranslations(db, 'products', {
    'name_en': ('en', 'name'),
    'name_tr': ('tr', 'name'),
    'desc_en': ('en', 'description'),
    'desc_tr': ('tr', 'description'),
  });
}

/// Переводы из постоянных колонок (`name_en`, `desc_tr`…) — в `i18n`,
/// а сами колонки убираются. [columns]: колонка → (язык, поле).
void _moveTranslations(
  Database db,
  String table,
  Map<String, (String, String)> columns,
) {
  final cols = db
      .select('pragma table_info($table)')
      .map((r) => r['name'])
      .toSet();
  if (!cols.contains(columns.keys.first)) return;
  inTransaction(db, () {
    if (!cols.contains('i18n')) {
      db.execute(
        "alter table $table add column i18n text not null default '{}'",
      );
    }
    final rows = db.select('select id, ${columns.keys.join(', ')} from $table');
    final update = db.prepare('update $table set i18n = ? where id = ?');
    try {
      for (final row in rows) {
        final i18n = <String, Map<String, String>>{};
        columns.forEach((col, target) {
          final text = (row[col] as String? ?? '').trim();
          if (text.isNotEmpty) (i18n[target.$1] ??= {})[target.$2] = text;
        });
        if (i18n.isNotEmpty) update.execute([jsonEncode(i18n), row['id']]);
      }
    } finally {
      update.close();
    }
    for (final col in columns.keys) {
      db.execute('alter table $table drop column $col');
    }
  });
}

/// Сколько дней живут отзывы. Старше — удаляются: это личные данные сразу
/// двух людей (гостя и официанта), и держать их дольше, чем нужно кафе,
/// незачем. Кафе предупреждено об этом прямо в списке отзывов.
const reviewMaxAgeDays = 40;

/// Удалить отзывы старше [days] дней. Возвращает, сколько удалилось.
///
/// Отдельного индекса по created_at нет намеренно: таблица по построению
/// крошечная — это 40 дней потока, зажатого ограничителем частоты, — а
/// второй индекс удорожал бы каждую вставку. Полный проход раз в сутки
/// здесь дешевле.
///
/// created_at пишется `datetime('now')`, то есть в UTC, и сравнивается с
/// UTC же. Локальное время из Dart сюда подставлять нельзя.
int purgeOldReviews(Database db, {int days = reviewMaxAgeDays}) {
  db.execute("delete from reviews where created_at < datetime('now', ?)", [
    '-$days days',
  ]);
  return db.updatedRows;
}

/// Засчитать открытие меню филиала.
///
/// `people` растёт только с нового устройства за этот день, `opens` — с
/// каждого открытия. Одной транзакцией: иначе при двух одновременных
/// гостях метка легла бы, а число не выросло.
void countView(
  Database db, {
  required String branchId,
  required String device,
  required String day,
}) {
  inTransaction(db, () {
    // `insert or ignore` + updatedRows вместо «сначала посмотреть, потом
    // вставить»: проверка и вставка — одно действие, и второго такого же
    // гостя отсекает сама база, а не наша догадка о том, кто успел раньше
    db.execute(
      'insert or ignore into branch_view_devices (branch_id, day, device) '
      'values (?, ?, ?)',
      [branchId, day, device],
    );
    final fresh = db.updatedRows;
    db.execute(
      'insert or ignore into branch_views (branch_id, day) values (?, ?)',
      [branchId, day],
    );
    db.execute(
      'update branch_views set people = people + ?, opens = opens + 1 '
      'where branch_id = ? and day = ?',
      [fresh, branchId, day],
    );
  });
}

/// Сколько дней держатся метки устройств. Нужны они только для «сегодня»,
/// но день кончается не одновременно во всех часовых поясах, поэтому два,
/// а не один.
const viewDeviceMaxAgeDays = 2;

/// Удалить метки устройств старше [days] дней. Возвращает, сколько удалилось.
/// Итоги в `branch_views` не трогает — они постоянные.
///
/// `day` — местный день сервера, поэтому границу считаем так же, через
/// [localDay], а не `date('now')` (это UTC).
int purgeOldViewDevices(
  Database db, {
  int days = viewDeviceMaxAgeDays,
  int tzOffsetHours = 0,
  DateTime? now,
}) {
  final edge = localDay(
    (now ?? DateTime.now()).subtract(Duration(days: days)),
    tzOffsetHours,
  );
  db.execute('delete from branch_view_devices where day < ?', [edge]);
  return db.updatedRows;
}

/// Местный день (`ГГГГ-ММ-ДД`) по часам кафе: UTC плюс [tzOffsetHours].
///
/// Сервер в контейнере живёт по UTC, а кафе — по своему времени, и «сегодня»
/// у счётчика просмотров должно совпадать с тем, что считает кафе днём.
String localDay(DateTime t, int tzOffsetHours) {
  final d = t.toUtc().add(Duration(hours: tzOffsetHours));
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

/// [body] целиком или ничего: схема не остаётся наполовину обновлённой.
void inTransaction(Database db, void Function() body) {
  db.execute('begin');
  try {
    body();
    db.execute('commit');
  } catch (_) {
    db.execute('rollback');
    rethrow;
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
const boolColumns = {
  'is_active',
  'is_visible',
  'show_in_catalog',
  'orders_enabled',
  'reviews_enabled',
};

Map<String, Object?> rowToJson(Row row) {
  final m = <String, Object?>{};
  for (final k in row.keys) {
    final v = row[k];
    m[k] = boolColumns.contains(k) && v is int ? v != 0 : v;
  }
  return m;
}

/// Где находится филиал (см. схему branches)
const locationColumns = ['address', 'map_url', 'hours'];

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
