import 'dart:io';

import 'package:menu_server/api.dart';
import 'package:menu_server/auth.dart';
import 'package:menu_server/backup.dart';
import 'package:menu_server/db.dart';
import 'package:menu_server/media.dart';
import 'package:menu_server/security.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';

/// Запуск:
/// ```
/// server                                  — API на порту PORT (8090)
/// server create-superadmin <login> [pwd]  — завести главного админа
/// server backup <папка> [--keep=14]       — копия базы и файлов, сервер
///                                           может работать
/// server restore <папка>/db/menu-….db     — восстановить из копии,
///                                           сервер должен быть остановлен
/// ```
///
/// Настройки через переменные окружения:
///   PORT        порт (по умолчанию 8090)
///   DATA_DIR    папка для menu.db и uploads/ (по умолчанию ./data)
///   PUBLIC_URL  внешний адрес, например https://menu.example.com
///   MENU_URL    адрес сайта с меню для гостей, из него собираются ссылки
///               QR-кодов (по умолчанию — адрес самого сервера)
///   MENU_WEB_DIR  папка собранного меню (build/web), открывается по адресу /
///   CORS_ORIGINS  ещё сайты через запятую, которым можно в админку
///               (свой MENU_URL и PUBLIC_URL разрешены и так)
///   UPLOAD_QUOTA_MB  место на диске для файлов одного кафе (2048)
///   BILLING_CONTACT  кому и как платить за меню: телефон, WhatsApp —
///               кафе видит это в админке, когда срок подходит к концу
///   SUPER_WEB_DIR  папка собранной главной админки (super_admin/build/web),
///               она открывается по адресу /menu-kg/
Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final dataDir = env['DATA_DIR'] ?? 'data';
  final port = int.tryParse(env['PORT'] ?? '') ?? 8090;

  // Копии делаются до открытия базы на запись: им не нужна схема и
  // обновление колонок, только чтение
  if (args.isNotEmpty && args.first == 'backup') {
    exit(await _backup(dataDir, args));
  }
  if (args.isNotEmpty && args.first == 'restore') {
    exit(await _restore(dataDir, port, args));
  }

  final uploadsDir = '$dataDir/uploads';
  await Directory(uploadsDir).create(recursive: true);
  final db = openDb('$dataDir/menu.db');

  if (args.isNotEmpty && args.first == 'create-superadmin') {
    if (args.length < 2) {
      stderr.writeln(
        'Использование: server create-superadmin <login> [password]',
      );
      exit(64);
    }
    var password = args.length > 2 ? args[2] : null;
    if (password == null) {
      stdout.write('Пароль: ');
      stdin.echoMode = false;
      password = stdin.readLineSync() ?? '';
      stdin.echoMode = true;
      stdout.writeln();
    }
    createUser(db, login: args[1], password: password, role: 'superadmin');
    stdout.writeln('Главный администратор «${args[1]}» создан');
    exit(0);
  }

  final publicUrl = _checkUrl('PUBLIC_URL', env['PUBLIC_URL']);
  final menuUrl = _checkUrl('MENU_URL', env['MENU_URL']);
  if (menuUrl == null && publicUrl == null) {
    // Без адреса ссылка QR собирается из заголовков запроса и может выйти
    // с localhost или внутренним адресом — такую наклейку гость не откроет
    stderr.writeln(
      'Внимание: не задан MENU_URL. Ссылки QR-кодов будут угадываться по '
      'запросу. На рабочем сервере задайте MENU_URL=https://ваш-домен',
    );
  }

  final api = Api(
    db,
    uploadsDir: uploadsDir,
    publicUrl: publicUrl,
    menuUrl: menuUrl,
    billingContact: (env['BILLING_CONTACT'] ?? '').trim(),
    uploadQuotaBytes: _quota(env['UPLOAD_QUOTA_MB']) * 1024 * 1024,
  );

  // Закрытая часть API доступна из браузера только со своих сайтов
  final origins = <String>{
    for (final url in [menuUrl, publicUrl]) ?CorsPolicy.originOf(url),
    for (final raw in (env['CORS_ORIGINS'] ?? '').split(','))
      if (raw.trim().isNotEmpty) _origin('CORS_ORIGINS', raw),
  };
  if (origins.isEmpty) {
    stderr.writeln(
      'Внимание: CORS открыт для всех сайтов — задайте MENU_URL (рабочий сервер)',
    );
  }
  final uploads = uploadsHandler(
    dataDir,
    createStaticHandler(dataDir, serveFilesOutsidePath: false),
  );

  // Главная админка — собранный super_admin (flutter build web
  // --base-href /menu-kg/). Отдельный сайт, в приложении меню её нет.
  final superAdmin = _siteHandler('SUPER_WEB_DIR', env['SUPER_WEB_DIR']);

  // Меню для гостей — собранное приложение (flutter build web). Тогда
  // QR-код https://домен/?branch=... открывается прямо с этого сервера.
  final menuWeb = _siteHandler('MENU_WEB_DIR', env['MENU_WEB_DIR']);

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(securityHeaders())
      .addMiddleware(cors(CorsPolicy(origins)))
      .addMiddleware(errorHandler())
      .addHandler((req) {
        final path = req.url.path;
        // Картинки: /uploads/<cafe>/<file> из DATA_DIR
        if (path.startsWith('uploads/')) return uploads(req);
        if (superAdmin != null) {
          // Без слэша относительные пути в index.html разъедутся
          if (path == 'menu-kg') return Response.found('/menu-kg/');
          if (path.startsWith('menu-kg/')) {
            return superAdmin(req.change(path: 'menu-kg/'));
          }
        }
        if (menuWeb != null && !path.startsWith('api/')) return menuWeb(req);
        return api.router.call(req);
      });

  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('Menu API: http://${server.address.address}:${server.port}');
  // Сразу видно, что именно раздаёт сервер, — без похода в браузер
  stdout.writeln(
    'Меню для гостей (/): ${env['MENU_WEB_DIR'] ?? 'не задано (MENU_WEB_DIR)'}',
  );
  stdout.writeln(
    'Главная админка (/menu-kg/): ${env['SUPER_WEB_DIR'] ?? 'не задано (SUPER_WEB_DIR)'}',
  );
}

/// Раздача собранного сайта из папки [dir]. Не задана — сайта нет, это
/// нормально. Задана, но там нет index.html — опечатка в пути: сервер
/// не запускается, иначе он молча отвечал бы «не найдено» вместо меню
/// и главной админки, а все напечатанные QR-коды вели бы в пустоту.
Handler? _siteHandler(String name, String? dir) {
  if (dir == null || dir.isEmpty) return null;
  if (!File('$dir/index.html').existsSync()) {
    stderr.writeln(
      'Ошибка: $name=$dir — в этой папке нет index.html. '
      'Проверьте путь или соберите сайт (flutter build web).',
    );
    exit(78); // EX_CONFIG: ошибка в настройках
  }
  return createStaticHandler(dir, defaultDocument: 'index.html');
}

/// Адрес сайта из настроек: `https://домен` без пути. Ошибка в нём
/// попала бы во все QR-коды, поэтому неправильный адрес останавливает
/// запуск. http (кроме localhost) — только предупреждение: камера и AR
/// в браузере работают лишь на https.
String? _checkUrl(String name, String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final url = value.trim().replaceFirst(RegExp(r'/+$'), '');
  final uri = Uri.tryParse(url);
  final ok =
      uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty &&
      uri.path.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment;
  if (!ok) {
    stderr.writeln(
      'Ошибка: $name=$value — нужен адрес сайта без пути, '
      'например https://menu.kg',
    );
    exit(78); // EX_CONFIG: ошибка в настройках
  }
  final local = uri.host == 'localhost' || uri.host == '127.0.0.1';
  if (uri.scheme == 'http' && !local) {
    stderr.writeln(
      'Внимание: $name=$url без https — в браузере не будет работать AR, '
      'а часть телефонов покажет предупреждение о небезопасном сайте',
    );
  }
  return url;
}

Future<int> _backup(String dataDir, List<String> args) async {
  final dest = args.length > 1 && !args[1].startsWith('--') ? args[1] : null;
  final keepArg = args.where((a) => a.startsWith('--keep=')).firstOrNull;
  final keep = keepArg == null ? 14 : int.tryParse(keepArg.substring(7));
  if (dest == null || keep == null) {
    stderr.writeln('Использование: server backup <папка> [--keep=14]');
    return 64;
  }
  try {
    final r = await runBackup(dataDir: dataDir, destDir: dest, keep: keep);
    stdout.writeln('Копия базы: ${r.dbFile}');
    stdout.writeln('Новых файлов скопировано: ${r.copiedFiles}');
    if (r.removedSnapshots > 0) {
      stdout.writeln('Старых копий удалено: ${r.removedSnapshots}');
    }
    return 0;
  } on BackupException catch (e) {
    stderr.writeln('Ошибка копии: $e');
    return 1;
  }
}

Future<int> _restore(String dataDir, int port, List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('Использование: server restore <папка>/db/menu-….db');
    return 64;
  }
  // Работающий сервер держит свой порт. Восстанавливать под ним нельзя:
  // он продолжит писать в старую базу поверх восстановленной
  try {
    final probe = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    await probe.close();
  } on SocketException {
    stderr.writeln('Порт $port занят — сначала остановите сервер');
    return 1;
  }
  try {
    final saved = await restoreBackup(backupDb: args[1], dataDir: dataDir);
    stdout.writeln('База восстановлена из ${args[1]}');
    if (saved != null) stdout.writeln('Прежняя база сохранена: $saved');
    return 0;
  } on BackupException catch (e) {
    stderr.writeln('Ошибка восстановления: $e');
    return 1;
  }
}

/// Адрес сайта из CORS_ORIGINS; неправильный останавливает запуск — так же,
/// как ошибка в MENU_URL.
String _origin(String name, String raw) {
  final origin = CorsPolicy.originOf(_checkUrl(name, raw.trim()));
  if (origin == null) {
    stderr.writeln(
      'Ошибка: $name=$raw — нужен адрес сайта, например https://menu.kg',
    );
    exit(78);
  }
  return origin;
}

int _quota(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 2048;
  final mb = int.tryParse(raw.trim());
  if (mb == null || mb < 1) {
    stderr.writeln('Ошибка: UPLOAD_QUOTA_MB=$raw — нужно целое число мегабайт');
    exit(78);
  }
  return mb;
}
