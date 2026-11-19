// Демо-данные для ручной проверки: кафе, филиал с заказами в WhatsApp,
// пара блюд и администратор. Только для разработки.
// Запуск: DATA_DIR=... dart run tool/seed_demo.dart
import 'dart:io';

import 'package:menu_server/auth.dart';
import 'package:menu_server/db.dart';

void main(List<String> args) {
  final dir = Platform.environment['DATA_DIR'] ?? 'data';
  Directory(dir).createSync(recursive: true);
  final db = openDb('$dir/menu.db');

  // Скрипт стирает все кафе, поэтому на непустой базе молча не работает:
  // перепутанный DATA_DIR не должен стоить кому-то его меню
  final existing = db.select('select count(*) n from cafes').first['n'] as int;
  if (existing > 0 && !args.contains('--yes')) {
    stderr.writeln(
      'В базе $dir уже $existing кафе. Это удалит их все.\n'
      'Если база действительно демонстрационная — повторите с --yes.',
    );
    db.close();
    exit(1);
  }

  db.execute('delete from cafes');
  db.execute(
    "insert into cafes (id, name, is_active, max_branches, plan, paid_until, "
    "show_in_catalog) values "
    "('c1', 'Демо', 1, 5, 'lifetime', '', 1)",
  );
  db.execute(
    "insert into branches (id, cafe_id, slug, name, slogan, address, "
    "order_whatsapp, delivery_price, orders_enabled, review_whatsapp, "
    "reviews_enabled, languages) values "
    "('b1', 'c1', 'demo', 'Демо-кафе', 'Проверка заказов', "
    "'ул. Киевская 95, 2 этаж', '996555112233', 150, 1, '996555112233', 1, "
    "'[\"ru\",\"en\"]')",
  );
  db.execute(
    "insert into categories (id, branch_id, name, sort_order) values "
    "('cat1', 'b1', 'Горячее', 1)",
  );
  db.execute(
    "insert into products (id, branch_id, category_id, name, price, portions) "
    "values ('p1', 'b1', 'cat1', 'Лагман', 280, "
    "'[{\"name\":\"обычная\",\"price\":280},{\"name\":\"большая\",\"price\":320}]')",
  );
  db.execute(
    "insert into products (id, branch_id, category_id, name, price) values "
    "('p2', 'b1', 'cat1', 'Чай', 120)",
  );
  db.execute(
    "insert into users (id, cafe_id, login, password_hash, role) values "
    "('u1', 'c1', 'demo', ?, 'cafe_admin')",
    [hashPassword('demo12345')],
  );
  db.close();
  stdout.writeln('Готово: кафе «Демо», филиал /?branch=demo, вход demo/demo12345');
}
