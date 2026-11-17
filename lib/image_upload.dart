import 'package:file_picker/file_picker.dart';
import 'api/api_client.dart';
import 'photo_shrink.dart';
import 'picker_options.dart';

/// Просит выбрать изображение и заливает его на сервер.
/// Возвращает адрес картинки или null, если выбор отменили.
///
/// Вынесено из трёх админ-экранов: у file_picker 12 нет ни `PlatformFile.bytes`,
/// ни `PlatformFile.extension` — байты читаются методом, а расширение
/// приходится доставать из имени файла.
Future<String?> pickAndUploadImage(String prefix) async {
  final file = await FilePicker.pickFile(
    type: FileType.image,
    webOptions: pickerWebOptions,
  );
  if (file == null) return null;

  final dot = file.name.lastIndexOf('.');
  final ext = dot > 0 ? file.name.substring(dot + 1).toLowerCase() : 'jpg';

  // Тяжёлый снимок уменьшается здесь (а HEIC с айфона ещё и переводится
  // в JPEG): сервер больше 10 МБ не примет и HEIC не откроет
  final photo = await shrinkPhoto(await file.readAsBytes(), ext);
  return api.upload(photo.bytes, ext: photo.ext, prefix: prefix);
}

/// Просит выбрать 3D-модель блюда (.glb) и заливает её на сервер.
/// Возвращает адрес модели или null, если выбор отменили.
Future<String?> pickAndUploadModel(String prefix) async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['glb'],
    webOptions: pickerWebOptions,
  );
  if (file == null) return null;

  final bytes = await file.readAsBytes();
  return api.upload(bytes, ext: 'glb', prefix: prefix);
}
