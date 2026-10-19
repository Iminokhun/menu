// Проверка защиты: CORS, защитные заголовки, лимит загрузок, место на диске.
// Запуск: dart run tool/security_test.dart
import 'dart:io';

import 'package:menu_server/security.dart';
import 'package:shelf/shelf.dart';

var failures = 0;

void expect(String what, bool ok, [Object? info]) {
  stdout.writeln('${ok ? 'OK  ' : 'FAIL'} $what${ok ? '' : '  → $info'}');
  if (!ok) failures++;
}

Future<Response> send(
  Handler h,
  String method,
  String path, {
  String? origin,
}) async => await h(
  Request(
    method,
    Uri.parse('http://localhost:8090$path'),
    headers: {if (origin != null) 'origin': origin},
  ),
);

Future<void> main() async {
  final app = const Pipeline()
      .addMiddleware(securityHeaders())
      .addMiddleware(cors(const CorsPolicy({'https://menu.kg'})))
      .addHandler((_) => Response.ok('ok'));

  var r = await send(
    app,
    'GET',
    '/api/admin/branches',
    origin: 'https://menu.kg',
  );
  expect(
    'свой сайт допущен в админку',
    r.headers['access-control-allow-origin'] == 'https://menu.kg' &&
        r.headers['vary'] == 'origin',
    r.headers,
  );
  r = await send(
    app,
    'GET',
    '/api/admin/branches',
    origin: 'https://evil.example',
  );
  expect(
    'чужому сайту разрешения нет',
    !r.headers.containsKey('access-control-allow-origin'),
    r.headers,
  );
  r = await send(
    app,
    'OPTIONS',
    '/api/auth/login',
    origin: 'https://evil.example',
  );
  expect('предзапрос чужого сайта → 403', r.statusCode == 403, r.statusCode);
  r = await send(app, 'OPTIONS', '/api/auth/login', origin: 'https://menu.kg');
  expect('предзапрос своего сайта → 204', r.statusCode == 204, r.statusCode);

  for (final path in [
    '/api/public/menu/x',
    '/uploads/c/a.jpg',
    '/api/health',
  ]) {
    r = await send(app, 'GET', path, origin: 'null');
    expect(
      'публичное ($path) открыто всем, даже «живому фото» из файла приложения',
      r.headers['access-control-allow-origin'] == '*',
      r.headers,
    );
  }

  final open = const Pipeline()
      .addMiddleware(cors(const CorsPolicy({})))
      .addHandler((_) => Response.ok('ok'));
  r = await send(
    open,
    'GET',
    '/api/admin/branches',
    origin: 'http://localhost:8080',
  );
  expect(
    'без настроенных сайтов (разработка) — открыто всем',
    r.headers['access-control-allow-origin'] == '*',
    r.headers,
  );

  r = await send(app, 'GET', '/api/health');
  expect(
    'защитные заголовки на месте',
    r.headers['x-content-type-options'] == 'nosniff' &&
        r.headers['x-frame-options'] == 'SAMEORIGIN' &&
        r.headers['referrer-policy'] == 'strict-origin-when-cross-origin',
    r.headers,
  );
  final own = await const Pipeline()
      .addMiddleware(securityHeaders())
      .addHandler(
        (_) => Response.ok('ok', headers: {'x-frame-options': 'DENY'}),
      )(Request('GET', Uri.parse('http://localhost/x')));
  expect(
    'свой заголовок ответа не перетирается',
    own.headers['x-frame-options'] == 'DENY',
    own.headers,
  );

  expect(
    'адрес сайта: со слэшем',
    CorsPolicy.originOf('https://menu.kg/') == 'https://menu.kg',
  );
  expect(
    'адрес сайта: с портом',
    CorsPolicy.originOf('http://localhost:8080') == 'http://localhost:8080',
  );
  expect('не адрес сайта', CorsPolicy.originOf('menu.kg') == null);

  final limiter = UploadLimiter(
    maxUploads: 3,
    window: const Duration(minutes: 10),
  );
  final t0 = DateTime(2026, 10, 18, 12);
  final first3 = [for (var i = 0; i < 3; i++) limiter.tryAcquire('c', t0)];
  expect('3 загрузки подряд проходят', first3.every((x) => x));
  expect(
    '4-я в те же 10 минут — нет',
    !limiter.tryAcquire('c', t0.add(const Duration(minutes: 5))),
  );
  expect('у другого кафе свой счёт', limiter.tryAcquire('other', t0));
  expect(
    'через 10 минут снова можно',
    limiter.tryAcquire('c', t0.add(const Duration(minutes: 10))),
  );

  final dir = Directory.systemTemp.createTempSync('menu_quota_');
  try {
    File('${dir.path}/a.jpg').writeAsBytesSync(List.filled(1000, 1));
    Directory('${dir.path}/sub').createSync();
    File('${dir.path}/sub/b.glb.gz').writeAsBytesSync(List.filled(500, 2));
    expect(
      'место считается по всем файлам кафе',
      usedBytes(dir) == 1500,
      usedBytes(dir),
    );
    expect('нет папки — 0', usedBytes(Directory('${dir.path}/none')) == 0);
  } finally {
    dir.deleteSync(recursive: true);
  }

  stdout.writeln(
    failures == 0 ? '\nВсе проверки прошли' : '\nОшибок: $failures',
  );
  exit(failures == 0 ? 0 : 1);
}
