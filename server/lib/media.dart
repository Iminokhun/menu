import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:shelf/shelf.dart';

/// Фото крупнее этого по длинной стороне уменьшаются: на экране меню
/// больше не нужно, а снимок с телефона весит в 10–20 раз больше.
const maxPhotoSide = 1600;
const _jpegQuality = 82;

/// Сжатое фото и расширение, под которым его сохранять.
typedef Photo = ({Uint8List bytes, String ext});

/// Уменьшает и пережимает фото. Null — файл не открылся как изображение.
///
/// Работает в отдельном изоляте: разбор снимка в 12 Мп занимает секунду-две,
/// и всё это время сервер не отвечал бы остальным кафе.
Future<Photo?> compressPhoto(Uint8List input, String ext) =>
    Isolate.run(() => _compress(input, ext));

Photo? _compress(Uint8List input, String ext) {
  final decoded = img.decodeImage(input);
  if (decoded == null) return null;

  // Анимацию пересжатие превратило бы в один кадр — оставляем как есть
  if (decoded.numFrames > 1) return (bytes: input, ext: ext);

  // Снимок с телефона часто лежит «боком», а поворот записан в EXIF
  var image = img.bakeOrientation(decoded);
  final longest = image.width > image.height ? image.width : image.height;
  final resized = longest > maxPhotoSide;
  if (resized) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: maxPhotoSide,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: maxPhotoSide,
            interpolation: img.Interpolation.average,
          );
  }

  // Логотипы с прозрачным фоном остаются PNG: в JPEG фон стал бы чёрным
  final keepAlpha = image.numChannels == 4;
  final out = keepAlpha
      ? (bytes: img.encodePng(image, level: 6), ext: 'png')
      : (bytes: img.encodeJpg(image, quality: _jpegQuality), ext: 'jpg');

  // Уже маленькое фото пересжатие могло только раздуть
  final sameKind = ext == out.ext || (ext == 'jpeg' && out.ext == 'jpg');
  if (!resized && sameKind && out.bytes.length >= input.length) {
    return (bytes: input, ext: ext);
  }
  return out;
}

/// gzip-версия файла, если она заметно меньше; иначе null.
/// В .glb геометрия сжимается хорошо, а уже сжатые текстуры — почти нет.
Uint8List? gzipIfWorthIt(Uint8List bytes) {
  final packed = Uint8List.fromList(gzip.encode(bytes));
  return packed.length < bytes.length * 0.9 ? packed : null;
}

/// Раздача загруженных файлов: 3D-модель, сохранённая как `x.glb.gz`,
/// отдаётся по адресу `x.glb` сжатой (`Content-Encoding: gzip`) — браузер
/// распакует сам. Остальное отдаёт [fallback].
Handler uploadsHandler(String dataDir, Handler fallback) {
  return (Request req) async {
    final segments = req.url.pathSegments;
    final safe =
        segments.isNotEmpty &&
        segments.every(
          (s) => s.isNotEmpty && s != '..' && s != '.' && !s.contains('\\'),
        );
    if (safe && segments.last.endsWith('.glb')) {
      final gz = File('$dataDir/${segments.join('/')}.gz');
      if (await gz.exists()) {
        final headers = {
          'content-type': 'model/gltf-binary',
          'vary': 'accept-encoding',
          // Имя файла уникально, содержимое по этому адресу не меняется
          'cache-control': 'public, max-age=31536000, immutable',
        };
        final acceptsGzip = (req.headers['accept-encoding'] ?? '').contains(
          'gzip',
        );
        if (acceptsGzip) {
          return Response.ok(
            gz.openRead(),
            headers: {
              ...headers,
              'content-encoding': 'gzip',
              'content-length': '${await gz.length()}',
            },
          );
        }
        return Response.ok(
          gz.openRead().transform(gzip.decoder),
          headers: headers,
        );
      }
    }
    return fallback(req);
  };
}
