import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Длинная сторона фото после уменьшения — как `maxPhotoSide` на сервере
/// (server/lib/media.dart): больше сервер всё равно не хранит.
const _maxSide = 1600;

/// Фото легче этого уходят как есть: их ужмёт сервер. Тяжёлые — снимки
/// 48–200 Мп по 12–30 МБ — сервер не примет (лимит 10 МБ), да и грузить
/// их по мобильному интернету долго.
const _shrinkFromBytes = 3 * 1024 * 1024;

const _jpegQuality = 85;

/// Что принимает сервер (`_imageExts` в server/lib/api.dart). Остальное —
/// прежде всего HEIC с айфона — переснимаем в JPEG здесь: пакет `image` на
/// сервере HEIC не открывает, а у браузера декодер свой, системный.
const _serverExts = {'jpg', 'jpeg', 'png', 'webp', 'gif'};

/// Марки HEIC/HEIF внутри контейнера ISO-BMFF.
const _heicBrands = {
  'heic', 'heix', 'heim', 'heis',
  'hevc', 'hevx', 'hevm', 'hevs',
  'mif1', 'msf1',
};

/// Правда ли внутри HEIC — по самим байтам, а не по имени файла.
///
/// Safari на айфоне отдаёт снимок под именем вроде `image.jpg`, хотя внутри
/// HEIC. По расширению такой файл не отличить, а сервер его не откроет.
bool _looksHeic(Uint8List b) =>
    b.length >= 12 &&
    b[4] == 0x66 && // f
    b[5] == 0x74 && // t
    b[6] == 0x79 && // y
    b[7] == 0x70 && // p
    _heicBrands.contains(String.fromCharCodes(b, 8, 12));

/// Уменьшает тяжёлое фото до [_maxSide] по длинной стороне перед загрузкой
/// и переводит в JPEG формат, которого сервер не знает.
///
/// Разбирает картинку встроенный декодер (браузер или движок): сразу в
/// уменьшенном виде, быстро и с поворотом по EXIF. Кодирует пакет `image`.
/// Если что-то не вышло — возвращает исходный файл, а сервер скажет, что с
/// ним не так.
Future<({Uint8List bytes, String ext})> shrinkPhoto(
  Uint8List bytes,
  String ext,
) async {
  final original = (bytes: bytes, ext: ext);
  // HEIC переснимаем любого размера: он вдвое экономнее JPEG, и снимок
  // айфона обычно весит меньше порога — иначе так и ушёл бы на сервер
  final heic = _looksHeic(bytes);
  final supported = !heic && _serverExts.contains(ext);
  // Не вышло переснять HEIC — отправляем с честным расширением, чтобы
  // сервер ответил понятным «это фото с айфона», а не «файл повреждён»
  final fallback = heic ? (bytes: bytes, ext: 'heic') : original;
  if (supported && bytes.length <= _shrinkFromBytes) return original;
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (w, h) {
        final longest = w > h ? w : h;
        if (longest <= _maxSide) return ui.TargetImageSize(width: w, height: h);
        return w >= h
            ? const ui.TargetImageSize(width: _maxSide)
            : const ui.TargetImageSize(height: _maxSide);
      },
    );
    // Анимацию пересжатие превратило бы в один кадр
    if (codec.frameCount > 1) {
      codec.dispose();
      return fallback;
    }
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    final rgba = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final width = image.width, height = image.height;
    image.dispose();
    if (rgba == null) return fallback;

    final out = await compute(
      _encode,
      (rgba: rgba.buffer.asUint8List(), width: width, height: height),
    );
    // JPEG из HEIC почти всегда тяжелее исходника, и это нормально:
    // исходник сервер просто не примет. Сравниваем вес только у форматов,
    // которые и так прошли бы
    if (!supported) return out;
    return out.bytes.length < bytes.length ? out : original;
  } catch (e) {
    debugPrint('shrinkPhoto: $e');
    return fallback;
  }
}

({Uint8List bytes, String ext}) _encode(
  ({Uint8List rgba, int width, int height}) p,
) {
  final image = img.Image.fromBytes(
    width: p.width,
    height: p.height,
    bytes: p.rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  // Логотип с прозрачным фоном остаётся PNG: в JPEG фон стал бы чёрным
  var transparent = false;
  for (var i = 3; i < p.rgba.length; i += 4) {
    if (p.rgba[i] != 255) {
      transparent = true;
      break;
    }
  }
  return transparent
      ? (bytes: img.encodePng(image, level: 6), ext: 'png')
      : (
          bytes: img.encodeJpg(
            image.convert(numChannels: 3),
            quality: _jpegQuality,
            chroma: img.JpegChroma.yuv420,
          ),
          ext: 'jpg',
        );
}
