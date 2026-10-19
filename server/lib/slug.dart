/// Адрес, который безопасно класть в ссылку QR-кода: латиница в нижнем
/// регистре, цифры и одиночные дефисы между ними. Пробел, `&`, `#` или `/`
/// ломают ссылку, а QR-коды к этому времени уже бывают напечатаны.
final _slugPattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

bool isValidSlug(String s) => s.length <= 60 && _slugPattern.hasMatch(s);

/// Превращает название в адрес для ссылки: «Центр» → `centr`,
/// «Бишкек Кофе» → `bishkek-kofe`. Тот же алгоритм, что в админке кафе.
String slugify(String input) {
  const translit = {
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'e',
    'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'i', 'к': 'k', 'л': 'l', 'м': 'm',
    'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
    'ф': 'f', 'х': 'h', 'ц': 'c', 'ч': 'ch', 'ш': 'sh', 'щ': 'sch',
    'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
    // кыргызские буквы
    'ң': 'n', 'ө': 'o', 'ү': 'u',
  };

  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    if (translit.containsKey(ch)) {
      buffer.write(translit[ch]);
    } else if (RegExp(r'[a-z0-9]').hasMatch(ch)) {
      buffer.write(ch);
    } else {
      buffer.write('-');
    }
  }

  return buffer
      .toString()
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}
