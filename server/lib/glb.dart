import 'dart:convert';
import 'dart:typed_data';

/// Что не так с 3D-моделью .glb, или null — модель правильная.
///
/// Проверяется вся структура glTF 2.0 Binary, а не только первые байты:
/// иначе к модели можно приклеить что угодно (архив, скрипт) и хранить это
/// на нашем сервере. Ссылки модели на внешние адреса тоже запрещены —
/// браузер гостя ходил бы по ним.
String? glbProblem(Uint8List bytes) {
  const notGlb = 'Это не 3D-модель .glb';
  if (bytes.length < 12) return notGlb;
  final data = ByteData.sublistView(bytes);
  if (ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'glTF') {
    return notGlb;
  }
  if (data.getUint32(4, Endian.little) != 2) {
    return 'Нужна модель glTF 2.0 (.glb)';
  }
  // Длина в заголовке — ровно длина файла: лишнее в конце не пройдёт
  if (data.getUint32(8, Endian.little) != bytes.length) {
    return 'Файл модели повреждён или в нём есть лишние данные';
  }

  Object? json;
  var offset = 12;
  while (offset < bytes.length) {
    if (offset + 8 > bytes.length) return 'Файл модели повреждён';
    final length = data.getUint32(offset, Endian.little);
    final type = data.getUint32(offset + 4, Endian.little);
    final start = offset + 8;
    if (length % 4 != 0 || start + length > bytes.length) {
      return 'Файл модели повреждён';
    }
    if (offset == 12) {
      // Первый кусок — описание модели в JSON
      if (type != _jsonChunk) return 'Файл модели повреждён';
      try {
        json = jsonDecode(utf8.decode(bytes.sublist(start, start + length)));
      } on FormatException {
        return 'Файл модели повреждён';
      }
    } else if (type != _binChunk) {
      return 'В модели есть посторонние данные';
    }
    offset = start + length;
  }

  if (json is! Map || json['asset'] is! Map) return 'Файл модели повреждён';
  if ((json['asset'] as Map)['version'] != '2.0') {
    return 'Нужна модель glTF 2.0 (.glb)';
  }
  for (final key in ['buffers', 'images']) {
    final list = json[key];
    if (list == null) continue;
    if (list is! List) return 'Файл модели повреждён';
    for (final item in list) {
      if (item is! Map) return 'Файл модели повреждён';
      final uri = item['uri'];
      if (uri != null && (uri is! String || !uri.startsWith('data:'))) {
        return 'Модель ссылается на внешние файлы — нужен .glb, где всё '
            'внутри одного файла';
      }
    }
  }
  return null;
}

/// Типы кусков .glb: «JSON» и «BIN\0» в порядке little-endian
const _jsonChunk = 0x4E4F534A;
const _binChunk = 0x004E4942;
