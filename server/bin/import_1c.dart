import 'dart:convert';
import 'dart:io';

import 'package:menu_server/db.dart';
import 'package:menu_server/import_1c.dart';

/// Меню филиала из выгрузки номенклатуры 1С.
///
/// ```
/// import_1c <nomenclature.json> <адрес филиала>
/// ```
///
/// Меню филиала заменяется целиком (см. lib/import_1c.dart). Перед запуском
/// на рабочей базе — резервная копия: `server backup <папка>`.
const _bom = '\u{FEFF}';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'Использование: import_1c <nomenclature.json> <адрес филиала>',
    );
    exit(64);
  }
  final [path, slug] = args;
  final dataDir = Platform.environment['DATA_DIR'] ?? 'data';

  final Object? json;
  try {
    // 1С пишет файл с меткой BOM в начале
    final text = await File(path).readAsString();
    json = jsonDecode(text.startsWith(_bom) ? text.substring(1) : text);
  } on Object catch (e) {
    stderr.writeln('Не удалось прочитать $path: $e');
    exit(1);
  }

  final db = openDb('$dataDir/menu.db');
  try {
    stdout.writeln(
      'Загрузка в филиал «$slug», фото сжимаются — это займёт минуту-две…',
    );
    final r = await import1c(
      db,
      dataDir: dataDir,
      branchSlug: slug,
      json: json,
    );
    stdout.writeln(
      'Готово: категорий ${r.categories}, блюд ${r.dishes}, фото ${r.photos}; '
      'переводы и 3D сохранены у ${r.carriedOver} блюд',
    );
    if (r.hiddenNoPrice.isNotEmpty) {
      stdout.writeln(
        'Без цены — скрыты, проверьте в админке: ${r.hiddenNoPrice.join(', ')}',
      );
    }
    for (final w in r.warnings) {
      stdout.writeln('Внимание: $w');
    }
  } on Import1cException catch (e) {
    stderr.writeln('Ошибка, меню не изменено: $e');
    exit(1);
  } finally {
    db.close();
  }
}
