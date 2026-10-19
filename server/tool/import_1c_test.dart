// Загрузка меню из выгрузки 1С на временной базе:
//   dart run tool/import_1c_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:menu_server/db.dart';
import 'package:menu_server/import_1c.dart';
import 'package:sqlite3/sqlite3.dart';

var failures = 0;

void expect(String what, bool ok, [Object? info]) {
  stdout.writeln('${ok ? 'OK  ' : 'FAIL'} $what${ok ? '' : '  → $info'}');
  if (!ok) failures++;
}

Map<String, Object?> item(
  String code,
  String name, {
  String parent = '',
  num price = 0,
  String photo = '',
  String description = '',
  List<Map<String, Object>> portions = const [],
}) => {
  'Код': code,
  'Наименование': name,
  'Родитель': '',
  'КодРодителя': parent,
  'Описание': description,
  'Цена': price,
  'ИдентификаторСервера': '',
  'Фото': photo,
  'Порции': portions,
};

Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('menu_1c_');
  try {
    final dataDir = dir.path;
    final db = openDb('$dataDir/menu.db');
    final files = Directory('$dataDir/uploads/c')..createSync(recursive: true);
    for (final f in ['old.jpg', 'borsch.jpg', 'shared.jpg', 'model.glb']) {
      File('${files.path}/$f').writeAsStringSync('x');
    }

    // Старое меню: две категории, три блюда; одно фото общее с ntcn
    db.execute(
      "insert into cafes (id, name, max_branches) values ('c', 'Андалус', 5)",
    );
    db.execute(
      "insert into branches (id, cafe_id, slug, name) values ('b', 'c', 'center', 'Центр'), ('b2', 'c', 'ntcn', 'ЦУМ')",
    );
    db.execute(
      '''insert into categories (id, branch_id, name, i18n, sort_order) values
      ('k1', 'b', 'Фаст-Фуд', '{"en":{"name":"Fast food"}}', 3),
      ('k2', 'b', 'Убранная', '{}', 0),
      ('k9', 'b2', 'Фаст-Фуд', '{}', 0)''',
    );
    db.execute(
      '''insert into products (id, branch_id, category_id, name, i18n, image_url, model_url, is_visible) values
      ('p1', 'b', 'k1', 'Борщ', '{"en":{"name":"Borscht"}}', '/uploads/c/borsch.jpg', '/uploads/c/model.glb', 1),
      ('p2', 'b', 'k2', 'Старое', '{}', '/uploads/c/old.jpg', '', 1),
      ('p3', 'b', 'k2', 'Общее', '{}', '/uploads/c/shared.jpg', '', 1),
      ('p9', 'b2', 'k9', 'Общее', '{}', '/uploads/c/shared.jpg', '', 1)''',
    );

    final jpeg = base64Encode(img.encodeJpg(img.Image(width: 40, height: 30)));
    final export = [
      item('g1', 'Фаст фуд', photo: jpeg),
      item('g2', 'Напитки'),
      item('g3', 'Кофе', parent: 'g2'),
      item(
        'd1',
        'Борщ',
        parent: 'g1',
        price: 300,
        description: 'Со сметаной',
        portions: [
          {'Наименование': '0.5', 'Цена': 200},
        ],
      ),
      item('d2', 'Латте', parent: 'g3', photo: jpeg),
      item('d3', 'Капучино', parent: 'g3', price: 180, photo: 'не base64!'),
    ];

    // Ошибка в выгрузке — меню не трогается
    Object? error;
    try {
      await import1c(
        db,
        dataDir: dataDir,
        branchSlug: 'center',
        json: [
          ...export,
          item('d4', 'Сирота', parent: 'нет-такой'),
        ],
      );
    } on Import1cException catch (e) {
      error = e;
    }
    expect(
      'ссылка на несуществующую группу — ошибка, меню прежнее',
      error != null &&
          db
                  .select(
                    "select count(*) n from products where branch_id = 'b'",
                  )
                  .first['n'] ==
              3,
      error,
    );

    final r = await import1c(
      db,
      dataDir: dataDir,
      branchSlug: 'center',
      json: export,
    );
    expect(
      'отчёт: 3 категории, 3 блюда, 2 фото',
      r.categories == 3 && r.dishes == 3 && r.photos == 2,
      '${r.categories} ${r.dishes} ${r.photos}',
    );
    expect(
      'повреждённое фото — предупреждение, блюдо без фото',
      r.warnings.length == 1 && r.warnings.first.contains('Капучино'),
      r.warnings,
    );

    Row cat(String name) => db.select(
      "select * from categories where branch_id = 'b' and name = ?",
      [name],
    ).first;
    Row dish(String name) => db.select(
      "select * from products where branch_id = 'b' and name = ?",
      [name],
    ).first;

    final fast = cat('Фаст фуд');
    expect(
      'категория совпала со старой («Фаст-Фуд»): перевод сохранён, фото из 1С, порядок как в 1С',
      fast['i18n'] == '{"en":{"name":"Fast food"}}' &&
          fast['sort_order'] == 0 &&
          (fast['image_url'] as String).endsWith('/1c_b_g1.jpg'),
      fast,
    );
    expect(
      'подкатегория «Кофе» внутри «Напитков»',
      cat('Кофе')['parent_id'] == cat('Напитки')['id'],
    );

    final borsch = dish('Борщ');
    expect(
      'блюдо совпало: перевод, 3D и старое фото сохранены, цена и порции из 1С',
      borsch['i18n'] == '{"en":{"name":"Borscht"}}' &&
          borsch['model_url'] == '/uploads/c/model.glb' &&
          borsch['image_url'] == '/uploads/c/borsch.jpg' &&
          borsch['price'] == 300 &&
          borsch['description'] == 'Со сметаной' &&
          borsch['portions'] == '[{"name":"0.5","price":200.0}]' &&
          borsch['category_id'] == fast['id'],
      borsch,
    );
    expect(
      'блюдо без цены — скрыто и названо в отчёте',
      dish('Латте')['is_visible'] == 0 && r.hiddenNoPrice.join() == 'Латте',
      r.hiddenNoPrice,
    );
    expect('с ценой — видно', dish('Капучино')['is_visible'] == 1);
    expect(
      'старых блюд и категорий филиала нет',
      db
              .select("select 1 from products where id in ('p1', 'p2', 'p3')")
              .isEmpty &&
          db
              .select("select 1 from categories where id in ('k1', 'k2')")
              .isEmpty,
    );
    expect(
      'другой филиал не тронут',
      db
              .select("select count(*) n from products where branch_id = 'b2'")
              .first['n'] ==
          1,
    );
    bool exists(String f) => File('${files.path}/$f').existsSync();
    expect(
      'файлы: ненужное старое фото удалено, нужные и общие с другим филиалом остались',
      !exists('old.jpg') &&
          exists('shared.jpg') &&
          exists('borsch.jpg') &&
          exists('model.glb') &&
          exists('1c_b_d2.jpg'),
    );

    // Та же выгрузка (те же коды 1С) во второй филиал — фото первого целы
    await import1c(db, dataDir: dataDir, branchSlug: 'ntcn', json: export);
    expect(
      'коды 1С совпали в двух филиалах: у каждого свои файлы фото',
      exists('1c_b_d2.jpg') &&
          exists('1c_b2_d2.jpg') &&
          dish('Латте')['image_url'] == '/uploads/c/1c_b_d2.jpg',
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
