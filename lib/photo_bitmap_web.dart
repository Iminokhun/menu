import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Разжимает ли фото сам браузер, через `ImageDecoder`.
///
/// Это в точности условие движка (`_defaultBrowserSupportsImageDecoder` в
/// engine/safe_browser_api.dart): мало того, что `ImageDecoder` есть — движок
/// намеренно берёт его только в Chrome, даже если другой браузер его завёл.
bool get _engineDecodesItself =>
    ui_web.browser.browserEngine == ui_web.BrowserEngine.blink &&
    globalContext.has('ImageDecoder');

/// Нужно ли разжимать фото в обход движка.
///
/// Это **любой браузер на айфоне и айпаде** — Chrome и прочие там только
/// оболочка, внутри Safari, — Safari на маке и Firefox. Там движок с версии
/// 3.47 наводит на скачанные байты скрытый `<img>` и делает «ленивую»
/// картинку: пиксели уходят в видеопамять только в момент отрисовки. К этому
/// моменту их может не быть, и на месте фото остаётся пустота — без ошибки,
/// так что заглушка «нет фото» тоже не появляется.
final bool photoBitmapNeeded = !_engineDecodesItself;

/// Фото для [Image.new] в обход движка.
ImageProvider photoBitmapImage(String url, int? targetWidth) =>
    PhotoBitmapImage(url, targetWidth);

/// Фото, разжатое в `ImageBitmap`.
///
/// `ImageBitmap` держит пиксели у себя, поэтому отложенная отправка в
/// видеопамять всегда находит данные — в отличие от скрытого `<img>`,
/// которым пользуется движок.
@immutable
class PhotoBitmapImage extends ImageProvider<PhotoBitmapImage> {
  const PhotoBitmapImage(this.url, this.targetWidth);

  final String url;

  /// Ширина, под которую уменьшить фото, или `null` — оставить как есть
  final int? targetWidth;

  @override
  Future<PhotoBitmapImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<PhotoBitmapImage>(this);

  @override
  ImageStreamCompleter loadImage(
    PhotoBitmapImage key,
    ImageDecoderCallback decode,
  ) =>
      // Ошибка дойдёт до `errorBuilder`, и гость увидит заглушку, а не
      // вечный пустой прямоугольник
      OneFrameImageStreamCompleter(
        _load(key),
        informationCollector: () => <DiagnosticsNode>[
          ErrorDescription('Фото: ${key.url}'),
        ],
      );

  static Future<ImageInfo> _load(PhotoBitmapImage key) async =>
      ImageInfo(image: await _decode(key.url, key.targetWidth));

  @override
  bool operator ==(Object other) =>
      other is PhotoBitmapImage &&
      other.url == url &&
      other.targetWidth == targetWidth;

  @override
  int get hashCode => Object.hash(url, targetWidth);

  @override
  String toString() => 'PhotoBitmapImage("$url", $targetWidth)';
}

/// Качает фото и разжимает его в `ImageBitmap`.
///
/// Повторные показы берёт кэш самого браузера: фото отдаются как неизменные
/// (`immutable`, год), и их заранее качает `menu_store.dart`.
Future<ui.Image> _decode(String url, int? targetWidth) async {
  final web.Response response = await web.window.fetch(url.toJS).toDart;
  if (!response.ok) {
    throw Exception('Фото не отдалось: HTTP ${response.status} — $url');
  }
  final web.Blob blob = await response.blob().toDart;
  web.ImageBitmap bitmap = await web.window.createImageBitmap(blob).toDart;
  // Уменьшаем уже разжатое: до разжатия настоящий размер фото неизвестен, а
  // растягивать маленькое фото под большое место незачем
  if (targetWidth != null && targetWidth < bitmap.width) {
    final web.ImageBitmap smaller = await web.window
        .createImageBitmap(
          bitmap,
          web.ImageBitmapOptions(
            resizeWidth: targetWidth,
            resizeQuality: 'high',
          ),
        )
        .toDart;
    bitmap.close();
    bitmap = smaller;
  }
  // Картинку забирает себе движок — закрывать её здесь нельзя
  return ui_web.createImageFromImageBitmap(bitmap);
}
