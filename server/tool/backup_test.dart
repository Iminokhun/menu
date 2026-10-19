// Проверка резервных копий и восстановления на временной папке.
// Запуск: dart run tool/backup_test.dart
import 'dart:io';

import 'package:menu_server/backup.dart';
import 'package:menu_server/db.dart';
import 'package:sqlite3/sqlite3.dart';

var failures = 0;

void expect(String what, bool ok, [Object? info]) {
  stdout.writeln('${ok ? 'OK  ' : 'FAIL'} $what${ok ? '' : '  → $info'}');
  if (!ok) failures++;
}

int count(Database db, String table) =>
    db.select('select count(*) n from $table').first['n'] as int;

Future<void> main() async {
  final root = Directory.systemTemp.createTempSync('menu_backup_');
  final data = '${root.path}/data';
  final dest = '${root.path}/backups';
  try {
    // Рабочая база с кафе и двумя файлами; папку, как и сервер, создаём заранее
    Directory('$data/uploads/c').createSync(recursive: true);
    final db = openDb('$data/menu.db');
    db.execute(
      "insert into cafes (id, name, max_branches) values ('c', 'Андалус', 2)",
    );
    db.execute(
      "insert into branches (id, cafe_id, slug, name) values ('b', 'c', 'center', 'Центр')",
    );
    Directory('$data/uploads/c').createSync(recursive: true);
    File('$data/uploads/c/a.jpg').writeAsBytesSync(List.filled(1000, 1));
    File('$data/uploads/c/b.glb.gz').writeAsBytesSync(List.filled(500, 2));

    // Копия, пока у сервера открыта незавершённая запись: в копию она
    // попасть не должна, а сама копия — получиться целой
    db.execute('begin');
    db.execute("insert into cafes (id, name) values ('draft', 'Не сохранено')");
    final first = await runBackup(
      dataDir: data,
      destDir: dest,
      now: DateTime(2026, 10, 18, 3),
    );
    db.execute('rollback');
    expect('копия создана', File(first.dbFile).existsSync(), first.dbFile);
    expect('скопированы оба файла', first.copiedFiles == 2, first.copiedFiles);
    Object? checkError;
    try {
      checkDatabase(first.dbFile);
    } catch (e) {
      checkError = e;
    }
    expect('копия целая (integrity_check)', checkError == null, checkError);
    final snap = sqlite3.open(first.dbFile, mode: OpenMode.readOnly);
    expect(
      'в копии сохранённые данные, без незавершённой записи',
      count(snap, 'cafes') == 1 && count(snap, 'branches') == 1,
      count(snap, 'cafes'),
    );
    snap.close();
    expect(
      'временных .part не осталось',
      !Directory(
        dest,
      ).listSync(recursive: true).any((f) => f.path.endsWith('.part')),
    );

    // Следующей ночью: новый файл и одно новое кафе
    File('$data/uploads/c/c.png').writeAsBytesSync(List.filled(300, 3));
    db.execute("insert into cafes (id, name) values ('c2', 'Бишкек Кофе')");
    final second = await runBackup(
      dataDir: data,
      destDir: dest,
      now: DateTime(2026, 10, 19, 3),
    );
    expect(
      'докопирован только новый файл',
      second.copiedFiles == 1,
      second.copiedFiles,
    );
    expect(
      'хранятся обе копии',
      Directory('$dest/db').listSync().length == 2,
      Directory('$dest/db').listSync(),
    );

    // Хранить только одну — старая удаляется
    final third = await runBackup(
      dataDir: data,
      destDir: dest,
      keep: 1,
      now: DateTime(2026, 10, 20, 3),
    );
    final left = Directory('$dest/db').listSync();
    expect(
      'при keep=1 осталась одна, самая свежая',
      third.removedSnapshots == 2 &&
          left.length == 1 &&
          left.single.uri.pathSegments.last ==
              File(third.dbFile).uri.pathSegments.last,
      left,
    );
    db.close();

    // Восстановление на «новый сервер» — пустую папку
    final fresh = '${root.path}/fresh';
    final saved = await restoreBackup(backupDb: third.dbFile, dataDir: fresh);
    final restored = sqlite3.open('$fresh/menu.db', mode: OpenMode.readOnly);
    expect(
      'восстановлены оба кафе и филиал',
      count(restored, 'cafes') == 2 && count(restored, 'branches') == 1,
      count(restored, 'cafes'),
    );
    restored.close();
    expect('прежней базы не было — сохранять нечего', saved == null, saved);
    expect(
      'восстановлены все файлы',
      [
        'a.jpg',
        'b.glb.gz',
        'c.png',
      ].every((f) => File('$fresh/uploads/c/$f').existsSync()),
    );

    // Восстановление поверх существующей базы: старая не теряется
    final saved2 = await restoreBackup(backupDb: third.dbFile, dataDir: data);
    expect(
      'прежняя база сохранена рядом',
      saved2 != null && File(saved2).existsSync(),
      saved2,
    );
    final reopened = openDb('$data/menu.db');
    expect(
      'сервер открывает восстановленную базу',
      count(reopened, 'cafes') == 2,
    );
    reopened.close();

    // Битый файл вместо копии не восстанавливается
    final broken = File('${root.path}/broken.db')
      ..writeAsStringSync('это не база');
    Object? restoreError;
    try {
      await restoreBackup(backupDb: broken.path, dataDir: '${root.path}/other');
    } catch (e) {
      restoreError = e;
    }
    expect('битая копия отклонена', restoreError != null);
    expect(
      'при отказе база не тронута',
      !File('${root.path}/other/menu.db').existsSync(),
    );
  } finally {
    root.deleteSync(recursive: true);
  }

  stdout.writeln(
    failures == 0 ? '\nВсе проверки прошли' : '\nОшибок: $failures',
  );
  exit(failures == 0 ? 0 : 1);
}
