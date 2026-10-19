import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'db.dart';
import 'media.dart';

/// Меню филиала из выгрузки номенклатуры 1С (`nomenclature.json`).
///
/// Выгрузка — плоский список: группы и товары вперемешку, у каждого `Код`
/// и `КодРодителя`. Группа — то, на что ссылается чей-то `КодРодителя`.
/// Группы верхнего уровня становятся категориями, вложенные — их
/// подкатегориями, товары — блюдами; фото приходят base64 внутри файла.
///
/// Меню филиала заменяется целиком. У блюд и категорий, совпавших по
/// названию со старыми, сохраняется то, чего в 1С нет: переводы, 3D-модель,
/// скрытость, фото (если в 1С его нет). Порядок — как в выгрузке.
class Import1cReport {
  int categories = 0;
  int dishes = 0;
  int photos = 0;

  /// Блюда, у которых сохранились переводы или 3D-модель старого меню
  int carriedOver = 0;

  /// Блюда без цены — загружены скрытыми, чтобы гость не видел «0 сом»
  final hiddenNoPrice = <String>[];
  final warnings = <String>[];
}

class Import1cException implements Exception {
  final String message;
  Import1cException(this.message);
  @override
  String toString() => message;
}

typedef _Item = ({
  String code,
  String name,
  String parent,
  String description,
  double price,
  String photo,
  List<Map<String, Object>> portions,
});

Future<Import1cReport> import1c(
  Database db, {
  required String dataDir,
  required String branchSlug,
  required Object? json,
}) async {
  final report = Import1cReport();
  final items = _parse(json);
  final byCode = {for (final i in items) i.code: i};
  final groupCodes = {
    for (final i in items)
      if (i.parent.isNotEmpty) i.parent,
  };
  for (final code in groupCodes) {
    if (!byCode.containsKey(code)) {
      throw Import1cException(
        'Нет группы с кодом $code, на неё ссылаются товары',
      );
    }
  }

  // Категории — два уровня, как их показывает меню гостя
  bool isGroup(_Item i) => groupCodes.contains(i.code);
  final roots = [
    for (final i in items)
      if (isGroup(i) && i.parent.isEmpty) i,
  ];
  final subs = [
    for (final i in items)
      if (isGroup(i) && i.parent.isNotEmpty) i,
  ];
  for (final s in subs) {
    if (byCode[s.parent]!.parent.isNotEmpty) {
      throw Import1cException(
        'Группа «${s.name}» вложена глубже двух уровней — меню так не покажет',
      );
    }
  }
  final dishes = [
    for (final i in items)
      if (!isGroup(i)) i,
  ];
  for (final d in dishes.where((d) => d.parent.isEmpty)) {
    report.warnings.add('«${d.name}» не в группе — пропущено');
  }

  final branch = db.select('select id, cafe_id from branches where slug = ?', [
    branchSlug,
  ]);
  if (branch.isEmpty) throw Import1cException('Нет филиала «$branchSlug»');
  final branchId = branch.first['id'] as String;
  final cafeId = branch.first['cafe_id'] as String;

  // Фото — до транзакции: сжатие долгое, а база всё это время была бы
  // заперта. Если загрузка сорвётся, записанные файлы удаляются.
  final uploads = Directory('$dataDir/uploads/$cafeId');
  await uploads.create(recursive: true);
  final written = <File>[];
  final photoUrl = <String, String>{};
  try {
    for (final i in items.where((i) => i.photo.isNotEmpty)) {
      final Uint8List raw;
      try {
        raw = base64Decode(i.photo);
      } on FormatException {
        report.warnings.add('«${i.name}»: фото повреждено — без фото');
        continue;
      }
      final photo = await compressPhoto(raw, 'jpg');
      if (photo == null) {
        report.warnings.add('«${i.name}»: фото не читается — без фото');
        continue;
      }
      final name = '1c_${_safe(i.code)}.${photo.ext}';
      final file = File('${uploads.path}/$name');
      await file.writeAsBytes(photo.bytes);
      written.add(file);
      photoUrl[i.code] = '/uploads/$cafeId/$name';
    }
    report.photos = photoUrl.length;

    final oldFiles = _replaceMenu(
      db,
      branchId,
      roots,
      subs,
      dishes.where((d) => d.parent.isNotEmpty).toList(),
      photoUrl,
      report,
    );
    _deleteUnused(
      db,
      dataDir,
      cafeId,
      oldFiles.difference(photoUrl.values.toSet()),
    );
  } catch (_) {
    for (final f in written) {
      if (f.existsSync()) f.deleteSync();
    }
    rethrow;
  }
  return report;
}

/// Меню филиала заменяется в одной транзакции. Возвращает файлы старого
/// меню — после замены ненужные из них удаляются.
Set<String> _replaceMenu(
  Database db,
  String branchId,
  List<_Item> roots,
  List<_Item> subs,
  List<_Item> dishes,
  Map<String, String> photoUrl,
  Import1cReport report,
) {
  final oldCats = db.select('select * from categories where branch_id = ?', [
    branchId,
  ]);
  final oldDishes = db.select('select * from products where branch_id = ?', [
    branchId,
  ]);
  Map<String, Row> byName(ResultSet rows) {
    final m = <String, Row>{};
    for (final r in rows) {
      m.putIfAbsent(_key(r['name'] as String), () => r);
    }
    return m;
  }

  final oldCat = byName(oldCats);
  final oldDish = byName(oldDishes);
  final oldFiles = {
    for (final r in [...oldCats, ...oldDishes])
      for (final f in [
        'image_url',
        if (r.containsKey('model_url')) 'model_url',
      ])
        if ((r[f] as String).startsWith('/uploads/')) r[f] as String,
  };

  final catId = <String, String>{};
  inTransaction(db, () {
    db.execute('delete from products where branch_id = ?', [branchId]);
    db.execute('delete from categories where branch_id = ?', [branchId]);

    for (final (i, g) in [...roots, ...subs].indexed) {
      final old = oldCat[_key(g.name)];
      final id = newId();
      catId[g.code] = id;
      db.execute(
        '''insert into categories (id, branch_id, parent_id, name, i18n,
                                   image_url, is_visible, sort_order)
           values (?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          id,
          branchId,
          g.parent.isEmpty ? null : catId[g.parent],
          g.name,
          old?['i18n'] ?? '{}',
          photoUrl[g.code] ?? old?['image_url'] ?? '',
          old?['is_visible'] ?? 1,
          // Порядок — как в выгрузке; поменять его можно в админке
          i,
        ],
      );
      report.categories++;
    }

    final order = <String, int>{};
    for (final d in dishes) {
      final old = oldDish[_key(d.name)];
      final i18n = old?['i18n'] as String? ?? '{}';
      final model = old?['model_url'] as String? ?? '';
      if (i18n != '{}' || model.isNotEmpty) report.carriedOver++;
      final noPrice = d.price <= 0 && d.portions.isEmpty;
      if (noPrice) report.hiddenNoPrice.add(d.name);
      db.execute(
        '''insert into products (id, branch_id, category_id, name, description,
                                 i18n, price, image_url, model_url, is_visible,
                                 sort_order, portions)
           values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          newId(),
          branchId,
          catId[d.parent],
          d.name,
          d.description,
          i18n,
          d.price,
          photoUrl[d.code] ?? old?['image_url'] ?? '',
          model,
          noPrice ? 0 : (old?['is_visible'] ?? 1),
          order[d.parent] = (order[d.parent] ?? -1) + 1,
          jsonEncode(d.portions),
        ],
      );
      report.dishes++;
    }
  });
  return oldFiles;
}

/// Файлы старого меню, на которые больше никто не ссылается (их могли
/// делить с другим филиалом — те остаются).
void _deleteUnused(
  Database db,
  String dataDir,
  String cafeId,
  Set<String> paths,
) {
  for (final path in paths) {
    if (!path.startsWith('/uploads/$cafeId/')) continue;
    final used = db.select(
      '''select 1 from products where image_url = ?1 or model_url = ?1
         union all select 1 from categories where image_url = ?1
         union all select 1 from branches where logo_url = ?1 or bg_url = ?1
         limit 1''',
      [path],
    );
    if (used.isNotEmpty) continue;
    for (final f in [File('$dataDir$path'), File('$dataDir$path.gz')]) {
      if (f.existsSync()) f.deleteSync();
    }
  }
}

List<_Item> _parse(Object? json) {
  if (json is! List) throw Import1cException('Ожидался список номенклатуры');
  final out = <_Item>[];
  final seen = <String>{};
  for (final (n, r) in json.indexed) {
    if (r is! Map) throw Import1cException('Запись №${n + 1}: не объект');
    final code = r['Код'];
    final name = r['Наименование'];
    if (code is! String || code.trim().isEmpty || name is! String) {
      throw Import1cException('Запись №${n + 1}: нет кода или наименования');
    }
    if (!seen.add(code)) throw Import1cException('Код $code повторяется');
    final price = r['Цена'];
    final rawPortions = r['Порции'];
    out.add((
      code: code,
      name: name.trim(),
      parent: (r['КодРодителя'] as String? ?? '').trim(),
      description: (r['Описание'] as String? ?? '').trim(),
      price: price is num && price.isFinite && price > 0 ? price.toDouble() : 0,
      photo: r['Фото'] as String? ?? '',
      portions: [
        if (rawPortions is List)
          for (final p in rawPortions)
            if (p is Map &&
                p['Наименование'] is String &&
                p['Цена'] is num &&
                (p['Цена'] as num) >= 0)
              {
                'name': (p['Наименование'] as String).trim(),
                'price': (p['Цена'] as num).toDouble(),
              },
      ],
    ));
  }
  return out;
}

/// Название для сравнения со старым меню: «Фаст-фуд» = «фаст фуд».
String _key(String name) => name
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

String _safe(String code) => code.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
