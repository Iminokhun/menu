import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';
import 'package:shelf/shelf.dart';

/// Фото крупнее этого по длинной стороне уменьшаются: на экране меню
/// больше не нужно, а снимок с телефона весит в 10–20 раз больше.
const maxPhotoSide = 1600;
const _jpegQuality = 82;

/// Длинная сторона уменьшенной копии фото (`/uploads/...jpg?w=800`).
/// Карточке меню больше не нужно даже на плотном экране телефона (плитка
/// около 760 px), а весит копия вдвое с лишним меньше фото из 1С (1080 px).
const thumbWidth = 800;

/// Копию на карточке не разглядывают вблизи: при 75 она легче ещё на
/// пятую часть, а разницы не видно
const _thumbQuality = 75;

final _photoName = RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false);

/// Файлы, сделанные из фото `/uploads/<кафе>/<файл>`: карта глубины для
/// «живого фото» и уменьшенная копия. Удаляются вместе с фото.
List<File> photoCopies(String dataDir, String uploadPath) => [
  File('$dataDir$uploadPath.depth.png'),
  _thumbFile(dataDir, uploadPath.substring('/uploads/'.length)),
];

/// Копия лежит не в uploads: не входит в место кафе и в ночные копии —
/// её всегда можно сделать заново из фото.
File _thumbFile(String dataDir, String relative) =>
    File('$dataDir/thumbs/$thumbWidth/$relative');

/// Сжатое фото и расширение, под которым его сохранять.
typedef Photo = ({Uint8List bytes, String ext});

/// Уменьшает и пережимает фото. Null — файл не открылся как изображение.
///
/// Работает в отдельном изоляте: разбор снимка в 12 Мп занимает секунду-две,
/// и всё это время сервер не отвечал бы остальным кафе.
Future<Photo?> compressPhoto(
  Uint8List input,
  String ext, {
  int maxSide = maxPhotoSide,
  int quality = _jpegQuality,
}) => Isolate.run(() => _compress(input, ext, maxSide, quality));

Photo? _compress(Uint8List input, String ext, int maxSide, int quality) {
  final decoded = img.decodeImage(input);
  if (decoded == null) return null;

  // Анимацию пересжатие превратило бы в один кадр — оставляем как есть
  if (decoded.numFrames > 1) return (bytes: input, ext: ext);

  // Снимок с телефона часто лежит «боком», а поворот записан в EXIF
  var image = img.bakeOrientation(decoded);
  final longest = image.width > image.height ? image.width : image.height;
  final resized = longest > maxSide;
  if (resized) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: maxSide,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: maxSide,
            interpolation: img.Interpolation.average,
          );
  }

  // Логотипы с прозрачным фоном остаются PNG: в JPEG фон стал бы чёрным.
  // Цвет в JPEG — вполовину чётче яркости (4:2:0), как пишут камеры
  // телефонов: глазу не заметно, а файл легче на треть
  final keepAlpha = image.numChannels == 4;
  final out = keepAlpha
      ? (bytes: img.encodePng(image, level: 6), ext: 'png')
      : (
          bytes: img.encodeJpg(
            image,
            quality: quality,
            chroma: img.JpegChroma.yuv420,
          ),
          ext: 'jpg',
        );

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

/// Файл по этому адресу не меняется: у каждого загруженного файла своё
/// имя, новое фото — новое имя. Браузер и приложение хранят его у себя.
const _immutable = 'public, max-age=31536000, immutable';

/// Раздача загруженных файлов:
/// - 3D-модель, сохранённая как `x.glb.gz`, отдаётся по адресу `x.glb`
///   сжатой (`Content-Encoding: gzip`) — браузер распакует сам;
/// - фото с `?w=800` — уменьшенной копией (см. [thumbWidth]); другой `w`
///   не поддерживается, отдаётся само фото.
///
/// Остальное отдаёт [fallback].
Handler uploadsHandler(String dataDir, Handler fallback) {
  final thumbs = _Thumbnails(dataDir);
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
          'cache-control': _immutable,
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
    final photo = safe && _photoName.hasMatch(segments.last);
    if (photo && req.url.queryParameters['w'] == '$thumbWidth') {
      final bytes = await thumbs.get(segments.skip(1).join('/'));
      if (bytes != null) {
        return Response.ok(
          bytes,
          headers: {
            'content-type':
                lookupMimeType(segments.last, headerBytes: bytes) ??
                'application/octet-stream',
            'cache-control': _immutable,
          },
        );
      }
      // Фото нет — 404 ниже; не открылось как картинка — отдаём как есть
    }
    final res = await fallback(req);
    return photo && res.statusCode == 200
        ? res.change(headers: {'cache-control': _immutable})
        : res;
  };
}

/// Уменьшенные копии фото. Делаются при первом запросе и лежат на диске;
/// фото новее копии — копия делается заново.
class _Thumbnails {
  final String dataDir;

  _Thumbnails(this.dataDir);

  /// Сжатие — секунды процессора на сервере, который делят все кафе:
  /// одновременно делается не больше двух копий, остальные ждут очереди.
  static const _parallel = 2;
  var _busy = 0;
  final _queue = <Completer<void>>[];

  /// Копия, которая уже делается: второй запрос того же фото ждёт её
  final _making = <String, Future<Uint8List?>>{};

  /// Копия фото `uploads/<relative>`. Null — фото нет или оно не открылось.
  Future<Uint8List?> get(String relative) async {
    final original = File('$dataDir/uploads/$relative');
    final thumb = _thumbFile(dataDir, relative);
    final made = await original.stat();
    if (made.type == FileSystemEntityType.notFound) return null;
    final copy = await thumb.stat();
    if (copy.type != FileSystemEntityType.notFound &&
        !copy.modified.isBefore(made.modified)) {
      return thumb.readAsBytes();
    }
    // Тело в фигурных скобках: `=> _making.remove(...)` вернуло бы саму эту
    // копию, и whenComplete ждал бы её же — вечно
    return _making[relative] ??= _make(original, thumb).whenComplete(() {
      _making.remove(relative);
    });
  }

  Future<Uint8List?> _make(File original, File thumb) async {
    await _slot();
    try {
      final ext = original.path.split('.').last.toLowerCase();
      final photo = await compressPhoto(
        await original.readAsBytes(),
        ext,
        maxSide: thumbWidth,
        quality: _thumbQuality,
      );
      if (photo == null) return null;
      // Через временный файл: прерванная запись не оставит битую копию
      await thumb.parent.create(recursive: true);
      final tmp = File('${thumb.path}.tmp');
      await tmp.writeAsBytes(photo.bytes);
      await tmp.rename(thumb.path);
      return photo.bytes;
    } finally {
      _release();
    }
  }

  Future<void> _slot() async {
    if (_busy < _parallel) {
      _busy++;
      return;
    }
    final turn = Completer<void>();
    _queue.add(turn);
    await turn.future;
  }

  /// Место переходит следующему в очереди, а не освобождается
  void _release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _busy--;
    }
  }
}
