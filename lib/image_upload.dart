import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Бакет Supabase Storage, куда складываются картинки категорий и товаров.
const _bucket = 'Andalus';

/// Просит выбрать изображение и заливает его в Storage.
/// Возвращает публичный URL или null, если выбор отменили.
///
/// Вынесено из трёх админ-экранов: у file_picker 12 нет ни `PlatformFile.bytes`,
/// ни `PlatformFile.extension` — байты читаются методом, а расширение
/// приходится доставать из имени файла.
Future<String?> pickAndUploadImage(String prefix) async {
  final file = await FilePicker.pickFile(type: FileType.image);
  if (file == null) return null;

  final bytes = await file.readAsBytes();

  final dot = file.name.lastIndexOf('.');
  final ext = dot > 0 ? file.name.substring(dot + 1).toLowerCase() : 'jpg';

  final name = '$prefix${DateTime.now().millisecondsSinceEpoch}.$ext';
  final storage = Supabase.instance.client.storage.from(_bucket);
  await storage.uploadBinary(name, bytes);
  return storage.getPublicUrl(name);
}
