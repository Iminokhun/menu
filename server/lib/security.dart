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

/// Сколько загрузок кафе может сделать за [window]. Обычная работа — это
/// десяток фото за раз; поток в сотни файлов — ошибка или злоумышленник.
class UploadLimiter {
  final int maxUploads;
  final Duration window;
  final _recent = <String, List<DateTime>>{};

  UploadLimiter({
    this.maxUploads = 60,
    this.window = const Duration(minutes: 10),
  });

  /// Записывает загрузку; false — лимит исчерпан, загрузку не принимать.
  bool tryAcquire(String cafeId, [DateTime? now]) {
    final t = now ?? DateTime.now();
    final list = (_recent[cafeId] ??= [])
      ..removeWhere((x) => t.difference(x) >= window);
    if (list.length >= maxUploads) return false;
    list.add(t);
    return true;
  }
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
