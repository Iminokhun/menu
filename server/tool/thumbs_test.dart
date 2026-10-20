// Уменьшенные копии фото и кэш у /uploads, на временной папке:
//   dart run tool/thumbs_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:menu_server/media.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';

var failures = 0;

void expect(String what, bool ok, [Object? info]) {
  stdout.writeln('${ok ? 'OK  ' : 'FAIL'} $what${ok ? '' : '  → $info'}');
  if (!ok) failures++;
}

bool same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('menu_thumbs_');
  try {
    final dataDir = dir.path;
    final files = Directory('$dataDir/uploads/c')..createSync(recursive: true);

    // Фото как из 1С: 1080×1080, с переходами цвета — чтобы было что сжимать
    final photo = img.Image(width: 1080, height: 1080);
    for (final p in photo) {
      p
        ..r = p.x * 255 ~/ 1080
        ..g = p.y * 255 ~/ 1080
        ..b = (p.x * p.y) % 256;
    }
    final original = File('${files.path}/dish.jpg')
      ..writeAsBytesSync(img.encodeJpg(photo, quality: 90));
    // Логотип с прозрачностью
    final logo = img.Image(width: 900, height: 300, numChannels: 4);
    File('${files.path}/logo.png').writeAsBytesSync(img.encodePng(logo));

    final handler = uploadsHandler(
      dataDir,
      createStaticHandler(dataDir, serveFilesOutsidePath: false),
    );
    Future<(Response, Uint8List)> get(String path) async {
      final res = await handler(
        Request('GET', Uri.parse('http://localhost/$path')),
      );
      final body = await res.read().expand((c) => c).toList();
      return (res, Uint8List.fromList(body));
    }

    var (res, body) = await get('uploads/c/dish.jpg?w=800');
    final small = img.decodeImage(body);
    expect(
      '?w=800: картинка 800 px, легче фото, JPEG, кэшируется надолго',
      res.statusCode == 200 &&
          small?.width == 800 &&
          body.length < original.lengthSync() &&
          res.headers['content-type'] == 'image/jpeg' &&
          res.headers['cache-control']!.contains('immutable'),
      '${res.statusCode} ${small?.width} ${body.length} ${res.headers}',
    );
    final thumb = File('$dataDir/thumbs/800/c/dish.jpg');
    expect('копия лежит в data/thumbs, не в uploads', thumb.existsSync());

    // Готовая копия отдаётся с диска, а не делается заново
    final marker = Uint8List.fromList([1, 2, 3]);
    thumb.writeAsBytesSync(marker);
    (res, body) = await get('uploads/c/dish.jpg?w=800');
    expect('повтор — готовая копия с диска', same(body, marker), body.length);

    // Фото заменили по тому же адресу — копия делается заново
    original.setLastModifiedSync(DateTime.now().add(const Duration(hours: 1)));
    (res, body) = await get('uploads/c/dish.jpg?w=800');
    expect(
      'фото новее копии — копия сделана заново',
      img.decodeImage(body)?.width == 800,
      body.length,
    );

    final results = await Future.wait([
      for (var i = 0; i < 6; i++) get('uploads/c/logo.png?w=800'),
    ]);
    expect(
      '6 запросов одной копии сразу — все получили одно и то же',
      results.every(
        (r) => r.$1.statusCode == 200 && same(r.$2, results.first.$2),
      ),
    );
    expect(
      'логотип с прозрачностью — остаётся PNG',
      results.first.$1.headers['content-type'] == 'image/png' &&
          img.decodePng(results.first.$2)?.width == 800,
      results.first.$1.headers,
    );

    (res, body) = await get('uploads/c/dish.jpg?w=123');
    expect(
      'другой w — само фото',
      res.statusCode == 200 && same(body, original.readAsBytesSync()),
    );
    (res, body) = await get('uploads/c/dish.jpg');
    expect(
      'само фото тоже кэшируется надолго',
      res.statusCode == 200 &&
          res.headers['cache-control']!.contains('immutable'),
      res.headers,
    );
    (res, _) = await get('uploads/c/none.jpg?w=800');
    expect('нет фото — 404', res.statusCode == 404, res.statusCode);
    expect(
      'нет фото — копия не создаётся',
      !File('$dataDir/thumbs/800/c/none.jpg').existsSync(),
    );

    final copies = photoCopies(dataDir, '/uploads/c/dish.jpg');
    expect(
      'к фото относятся карта глубины и копия',
      copies.map((f) => f.path).toSet().containsAll({
        '$dataDir/uploads/c/dish.jpg.depth.png',
        thumb.path,
      }),
      copies,
    );
  } finally {
    dir.deleteSync(recursive: true);
  }

  stdout.writeln(
    failures == 0 ? '\nВсе проверки прошли' : '\nОшибок: $failures',
  );
  exit(failures == 0 ? 0 : 1);
}
