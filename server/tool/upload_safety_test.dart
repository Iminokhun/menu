// Защита загрузки: приклеенные к фото «хвосты», фото-бомбы, проверка .glb.
//   dart run tool/upload_safety_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:menu_server/glb.dart';
import 'package:menu_server/media.dart';

var failures = 0;

/// Пересчитывает контрольную сумму заголовка PNG после подмены размеров:
/// настоящая фото-бомба — правильный файл, просто огромный по размеру
void pngBombFix(Uint8List png) {
  var crc = 0xFFFFFFFF;
  for (final b in png.sublist(12, 29)) {
    crc ^= b;
    for (var k = 0; k < 8; k++) {
      crc = crc & 1 != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  ByteData.sublistView(png).setUint32(29, crc ^ 0xFFFFFFFF);
}

void expect(String what, bool ok, [Object? info]) {
  stdout.writeln('${ok ? 'OK  ' : 'FAIL'} $what${ok ? '' : '  → $info'}');
  if (!ok) failures++;
}

/// Есть ли в [bytes] подряд байты [part]
bool contains(List<int> bytes, List<int> part) {
  outer:
  for (var i = 0; i + part.length <= bytes.length; i++) {
    for (var j = 0; j < part.length; j++) {
      if (bytes[i + j] != part[j]) continue outer;
    }
    return true;
  }
  return false;
}

Uint8List glb({
  String json = '{"asset":{"version":"2.0"}}',
  int bin = 0,
  List<int> tail = const [],
  int? declared,
}) {
  final j = utf8.encode(json.padRight((json.length + 3) ~/ 4 * 4));
  final length = 12 + 8 + j.length + (bin > 0 ? 8 + bin : 0);
  List<int> u32(int v) =>
      (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();
  return Uint8List.fromList([
    ...ascii.encode('glTF'), ...u32(2), ...u32(declared ?? length + tail.length),
    ...u32(j.length), ...ascii.encode('JSON'), ...j,
    if (bin > 0) ...[...u32(bin), ...ascii.encode('BIN'), 0, ...List.filled(bin, 1)],
    ...tail,
  ]);
}

Future<void> main() async {
  final payload = utf8.encode('<script>alert(1)</script>PK\x03\x04virus');

  // Маленькое фото с хвостом: раньше уходило на сервер как есть
  final small = img.encodeJpg(img.Image(width: 200, height: 150), quality: 50);
  final out = (await compressPhoto(
    Uint8List.fromList([...small, ...payload]),
    'jpg',
  ))!;
  expect(
    'хвост маленького JPEG не сохраняется',
    !contains(out.bytes, payload) && img.decodeJpg(out.bytes) != null,
  );

  final png = img.encodePng(img.Image(width: 100, height: 100, numChannels: 4));
  final outPng = (await compressPhoto(
    Uint8List.fromList([...png, ...payload]),
    'png',
  ))!;
  expect(
    'хвост PNG не сохраняется, прозрачность на месте',
    outPng.ext == 'png' && !contains(outPng.bytes, payload),
  );

  // Анимация: раньше сохранялась как есть
  final anim = img.Image(width: 40, height: 40);
  for (var i = 0; i < 3; i++) {
    anim.addFrame(img.Image(width: 40, height: 40)..clear(img.ColorRgb8(i * 80, 0, 0)));
  }
  final gif = img.encodeGif(anim);
  final outGif = (await compressPhoto(
    Uint8List.fromList([...gif, ...payload]),
    'gif',
  ))!;
  final redecoded = img.decodeGif(outGif.bytes);
  expect(
    'анимация остаётся анимацией, хвоста нет',
    outGif.ext == 'gif' &&
        !contains(outGif.bytes, payload) &&
        redecoded != null &&
        redecoded.numFrames == anim.numFrames,
    '${outGif.ext} ${redecoded?.numFrames}/${anim.numFrames}',
  );

  // Фото-бомба: заголовок на огромный размер при файле в сотню байт
  for (final side in [10000, 60000]) {
    final bomb = img.encodePng(img.Image(width: 1, height: 1));
    ByteData.sublistView(bomb)
      ..setUint32(16, side)
      ..setUint32(20, side);
    pngBombFix(bomb);
    final started = DateTime.now();
    Object? error;
    try {
      await compressPhoto(bomb, 'png');
    } catch (e) {
      error = e;
    }
    expect(
      'фото-бомба $side×$side отклоняется сразу, без разбора',
      error is PhotoTooLarge &&
          DateTime.now().difference(started) < const Duration(seconds: 5),
      error,
    );
  }
  // Анимация: каждый кадр в норме, а вместе — слишком много
  final long = img.Image(width: 1000, height: 1000);
  for (var i = 0; i < 60; i++) {
    long.addFrame(img.Image(width: 1000, height: 1000));
  }
  Object? longError;
  try {
    await compressPhoto(img.encodeGif(long), 'gif');
  } catch (e) {
    longError = e;
  }
  expect('анимация на 61 Мп всех кадров отклоняется', longError is PhotoTooLarge, longError);
  expect(
    'не картинка → null',
    await compressPhoto(Uint8List.fromList(payload), 'jpg') == null,
  );

  // .glb
  expect('правильная модель', glbProblem(glb(bin: 64)) == null, glbProblem(glb(bin: 64)));
  expect(
    'модель с хвостом',
    glbProblem(glb(tail: payload, declared: glb().length)) != null,
  );
  expect('хвост, учтённый в длине, — посторонние данные', glbProblem(glb(tail: [...payload, 0, 0, 0])) != null);
  expect('неверная длина в заголовке', glbProblem(glb(declared: 999)) != null);
  expect(
    'ссылка на внешний файл',
    glbProblem(glb(json: '{"asset":{"version":"2.0"},"images":[{"uri":"http://x.io/a.png"}]}')) != null,
  );
  expect(
    'данные внутри модели (data:) разрешены',
    glbProblem(glb(json: '{"asset":{"version":"2.0"},"buffers":[{"uri":"data:application/octet-stream;base64,AAAA"}]}')) == null,
  );
  expect('JSON не разбирается', glbProblem(glb(json: 'not json')) != null);
  expect('без asset', glbProblem(glb(json: '{"a":1}')) != null);
  expect('просто текст', glbProblem(Uint8List.fromList(payload)) != null);

  stdout.writeln(failures == 0 ? '\nВсе проверки прошли' : '\nОшибок: $failures');
  exit(failures == 0 ? 0 : 1);
}
