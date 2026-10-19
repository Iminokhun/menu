import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// Резервные копии: база и загруженные файлы.
///
/// Папка копий устроена так:
/// - `<dest>/db/menu-2026-10-18_03-00-00.db` — снимки базы, последние `keep`;
/// - `<dest>/uploads/<cafe>/<file>` — общее зеркало фото и моделей.
///
/// Файлы в uploads не меняются после загрузки (у каждого своё имя), поэтому
/// их достаточно докопировать, а не хранить заново в каждом снимке.
class BackupResult {
  final String dbFile;
  final int copiedFiles;
  final int removedSnapshots;

  const BackupResult(this.dbFile, this.copiedFiles, this.removedSnapshots);
}

class BackupException implements Exception {
  final String message;
  BackupException(this.message);

  @override
  String toString() => message;
}

final _snapshotName = RegExp(r'^menu-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.db$');

/// Делает снимок базы и докопирует новые файлы. Сервер при этом может
/// работать: `VACUUM INTO` пишет целостную копию на момент начала команды,
/// а простое копирование файла базы в режиме WAL дало бы битую копию.
Future<BackupResult> runBackup({
  required String dataDir,
  required String destDir,
  int keep = 14,
  DateTime? now,
}) async {
  if (keep < 1) throw BackupException('Хранить нужно хотя бы одну копию');
  final source = File('$dataDir/menu.db');
  if (!source.existsSync()) throw BackupException('Нет базы: ${source.path}');

  final dbDir = Directory('$destDir/db')..createSync(recursive: true);
  final t = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final name =
      'menu-${t.year}-${two(t.month)}-${two(t.day)}_'
      '${two(t.hour)}-${two(t.minute)}-${two(t.second)}.db';
  final target = File('${dbDir.path}/$name');
  // Пишем во временный файл и переименовываем только после проверки:
  // недописанная копия не должна выглядеть как готовая
  final part = File('${target.path}.part');
  if (part.existsSync()) part.deleteSync();

  final db = sqlite3.open(source.path, mode: OpenMode.readOnly);
  try {
    db.execute('pragma busy_timeout = 10000');
    db.execute('vacuum into ?', [part.path]);
  } finally {
    db.close();
  }

  try {
    checkDatabase(part.path);
  } catch (_) {
    part.deleteSync();
    rethrow;
  }
  part.renameSync(target.path);

  final copied = await _mirror(
    Directory('$dataDir/uploads'),
    Directory('$destDir/uploads'),
  );
  final removed = _rotate(dbDir, keep);
  return BackupResult(target.path, copied, removed);
}

/// Проверяет файл базы: SQLite не нашёл повреждений, и это база меню,
/// а не какая-то другая. Бросает [BackupException], если что-то не так.
void checkDatabase(String path) {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    final result = db.select('pragma integrity_check').first.values.first;
    if (result != 'ok') throw BackupException('Копия повреждена: $result');
    final tables = db
        .select("select name from sqlite_master where type = 'table'")
        .map((r) => r['name'])
        .toSet();
    for (final t in ['cafes', 'users', 'branches', 'categories', 'products']) {
      if (!tables.contains(t)) throw BackupException('В копии нет таблицы $t');
    }
  } finally {
    db.close();
  }
}

/// Восстанавливает базу и файлы из копии. Сервер должен быть остановлен:
/// иначе он продолжит писать в старую базу поверх восстановленной.
///
/// Текущая база не удаляется, а переименовывается в
/// `menu.db.before-restore-<время>` — ошибочное восстановление можно отменить.
Future<String?> restoreBackup({
  required String backupDb,
  required String dataDir,
  DateTime? now,
}) async {
  if (!File(backupDb).existsSync()) {
    throw BackupException('Нет файла копии: $backupDb');
  }
  checkDatabase(backupDb);

  Directory(dataDir).createSync(recursive: true);
  final current = File('$dataDir/menu.db');
  String? saved;
  if (current.existsSync()) {
    final t = (now ?? DateTime.now())
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    saved = '${current.path}.before-restore-$t';
    current.renameSync(saved);
    // Журнал WAL относится к старой базе: рядом с новой его быть не должно
    for (final suffix in ['-wal', '-shm']) {
      final f = File('${current.path}$suffix');
      if (f.existsSync()) f.renameSync('$saved$suffix');
    }
  }
  File(backupDb).copySync(current.path);

  // Файлы — из общего зеркала рядом с папкой снимков: <dest>/db/x.db → <dest>/uploads
  final uploads = Directory('${File(backupDb).parent.parent.path}/uploads');
  if (uploads.existsSync()) {
    await _mirror(uploads, Directory('$dataDir/uploads'));
  }
  return saved;
}

/// Копирует файлы, которых в [to] ещё нет или которые отличаются размером.
/// Ничего не удаляет: в копии остаются и файлы, которые на сервере уже убрали.
Future<int> _mirror(Directory from, Directory to) async {
  if (!from.existsSync()) return 0;
  var copied = 0;
  await for (final entity in from.list(recursive: true, followLinks: false)) {
    // .part — недописанная копия от прерванного запуска, не файл сервера
    if (entity is! File || entity.path.endsWith('.part')) continue;
    final rel = entity.path.substring(from.path.length + 1);
    final dest = File('${to.path}/$rel');
    if (dest.existsSync() && dest.lengthSync() == entity.lengthSync()) continue;
    dest.parent.createSync(recursive: true);
    final part = File('${dest.path}.part');
    await entity.copy(part.path);
    part.renameSync(dest.path);
    copied++;
  }
  return copied;
}

/// Оставляет [keep] самых свежих снимков. Имя содержит дату, поэтому
/// порядок по имени — это порядок по времени.
int _rotate(Directory dbDir, int keep) {
  final snapshots =
      dbDir
          .listSync()
          .whereType<File>()
          .where((f) => _snapshotName.hasMatch(f.uri.pathSegments.last))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
  var removed = 0;
  for (final old in snapshots.skip(keep)) {
    old.deleteSync();
    removed++;
  }
  return removed;
}
