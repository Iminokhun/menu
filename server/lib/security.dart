import 'dart:io';

import 'package:shelf/shelf.dart';

/// С каких сайтов браузеру разрешено обращаться к закрытой части API
/// (вход, админки). Публичное — меню гостя, файлы, `/api/health` — открыто
/// всем: там нет ничего секретного, а «живое фото» на телефоне грузит фото
/// из файла приложения, у которого вообще нет адреса сайта.
class CorsPolicy {
  /// Адреса вида `https://menu.kg`. Пусто — разрешено всем: так удобно
  /// разрабатывать, а на рабочем сервере адрес задан через MENU_URL.
  final Set<String> origins;

  const CorsPolicy(this.origins);

  bool get allowsAll => origins.isEmpty;

  /// `https://menu.kg/` → `https://menu.kg`; не адрес сайта → null.
  static String? originOf(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri.origin;
  }
}

bool _isPublic(String path) =>
    path == 'api/health' ||
    path.startsWith('api/public/') ||
    path.startsWith('uploads/');

Middleware cors(CorsPolicy policy) =>
    (inner) => (req) async {
      final origin = req.headers['origin'];
      final String? allow;
      if (policy.allowsAll || _isPublic(req.url.path)) {
        allow = '*';
      } else if (origin != null && policy.origins.contains(origin)) {
        allow = origin;
      } else {
        allow = null; // чужой сайт: браузер сам не отдаст ему ответ
      }
      final headers = <String, String>{
        if (allow != null) ...{
          'access-control-allow-origin': allow,
          'access-control-allow-methods': 'GET, POST, PATCH, DELETE, OPTIONS',
          'access-control-allow-headers': 'authorization, content-type',
          'access-control-max-age': '600',
        },
        // Ответ зависит от того, кто спрашивает, — кэши не должны его путать
        if (allow != null && allow != '*') 'vary': 'origin',
      };
      if (req.method == 'OPTIONS') {
        return Response(allow == null ? 403 : 204, headers: headers);
      }
      final res = await inner(req);
      return headers.isEmpty ? res : res.change(headers: headers);
    };

/// Заголовки, которые просят браузер вести себя безопаснее. HSTS («только
/// HTTPS») ставит Caddy: сервер меню за ним видит обычный HTTP.
///
/// Content-Security-Policy сознательно не задана: веб-версии Flutter,
/// шрифтам Google и 3D-просмотру нужны разные источники, и ошибка в
/// политике молча сломала бы меню у гостей.
Middleware securityHeaders() =>
    (inner) => (req) async {
      final res = await inner(req);
      const add = {
        // Не угадывать тип файла: загруженная «картинка» не исполнится как скрипт
        'x-content-type-options': 'nosniff',
        // Меню и админку нельзя встроить в чужой сайт (подмена кнопок)
        'x-frame-options': 'SAMEORIGIN',
        'referrer-policy': 'strict-origin-when-cross-origin',
        // Микрофон и геолокация меню не нужны. Камеру не запрещаем — она
        // нужна AR («блюдо на столе»)
        'permissions-policy': 'microphone=(), geolocation=()',
      };
      final missing = {
        for (final e in add.entries)
          if (!res.headers.containsKey(e.key)) e.key: e.value,
      };
      return res.change(headers: missing);
    };

/// Сколько действий с одним ключом допустимо за [window].
///
/// Ключ — это кафе (загрузки), IP гостя или филиал (заказы). Пустые ключи
/// выбрасываются сразу, а когда их накапливается слишком много — чистятся
/// целиком: по IP ключей столько, сколько их захочет завести чужой, и без
/// уборки список рос бы без предела.
class SlidingWindowLimiter {
  final int max;
  final Duration window;
  final _recent = <String, List<DateTime>>{};

  /// Больше скольких ключей начинать уборку. Обычной работе столько не
  /// нужно; задаётся отдельно, чтобы это можно было проверить тестом
  final int sweepAt;

  SlidingWindowLimiter({
    required this.max,
    required this.window,
    this.sweepAt = 10000,
  });

  DateTime? _lastSweep;

  /// Записывает действие; false — предел исчерпан, действие не принимать.
  bool tryAcquire(String key, [DateTime? now]) {
    final t = now ?? DateTime.now();
    // Уборка — не чаще раза за окно: иначе на десяти тысячах живых ключей
    // полный проход делался бы на каждый запрос
    if (_recent.length >= sweepAt &&
        (_lastSweep == null || t.difference(_lastSweep!) >= window)) {
      _lastSweep = t;
      _sweep(t);
    }
    final list = (_recent[key] ??= [])
      ..removeWhere((x) => t.difference(x) >= window);
    if (list.length >= max) {
      if (list.isEmpty) _recent.remove(key);
      return false;
    }
    list.add(t);
    return true;
  }

  void _sweep(DateTime t) {
    _recent.removeWhere((_, list) {
      list.removeWhere((x) => t.difference(x) >= window);
      return list.isEmpty;
    });
  }

  /// Сколько ключей сейчас помнится. Нужно тестам про уборку
  int get keyCount => _recent.length;
}

/// Сколько загрузок кафе может сделать за `window`. Обычная работа — это
/// десяток фото за раз; поток в сотни файлов — ошибка или злоумышленник.
class UploadLimiter extends SlidingWindowLimiter {
  UploadLimiter({
    int maxUploads = 60,
    super.window = const Duration(minutes: 10),
  }) : super(max: maxUploads);

  int get maxUploads => max;
}

/// Откуда пришёл запрос. Нужен, чтобы считать заказы по гостю, а не по всему
/// интернету сразу.
///
/// Берётся **последний** адрес из `x-forwarded-for`, а не первый: и nginx
/// (`$proxy_add_x_forwarded_for`), и Caddy **дописывают** адрес соединения к
/// тому, что прислал клиент. Гость, пославший свой `x-forwarded-for`, даёт
/// `чужое, настоящее` — доверие к первому значению позволило бы менять ключ
/// ограничителя как угодно и обнулило бы всю защиту.
///
/// Подделать последнее значение нельзя, пока до сервера нельзя достучаться
/// мимо прокси: в `deploy/docker-compose.yml` у меню не опубликовано ни
/// одного порта. Появится строка `ports:` — эта гарантия исчезнет.
String clientIp(Request req) {
  final forwarded = req.headers['x-forwarded-for'];
  if (forwarded != null && forwarded.trim().isNotEmpty) {
    final parts = forwarded.split(',');
    final last = parts.last.trim();
    if (last.isNotEmpty) return last;
  }
  final conn = req.context['shelf.io.connection_info'];
  if (conn is HttpConnectionInfo) return conn.remoteAddress.address;
  // Запрос без сокета — так бывает только в тестах
  return 'local';
}

/// Сколько байт занимают файлы кафе на диске.
int usedBytes(Directory dir) {
  if (!dir.existsSync()) return 0;
  var total = 0;
  for (final f in dir.listSync(recursive: true, followLinks: false)) {
    if (f is File) total += f.lengthSync();
  }
  return total;
}
