import 'models/product.dart';

/// Поиск блюд по меню, которое уже есть на устройстве, — работает и без
/// интернета.
///
/// Блюдо находится по названию и описанию на любом из языков меню и по
/// названию своей категории («супы» → все супы). Латиницей тоже можно:
/// «plov» найдёт «Плов» — туристу не нужна русская раскладка. Несколько
/// слов ищутся вместе: «суп грибной» — блюда, где есть оба слова.
List<Product> searchDishes(List<Product> items, String query) {
  final words = _normalize(query).split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];

  final groups = {for (final p in items) if (p.isGroup) p.id: p};

  /// Названия категории блюда и всех её родителей
  String categoryText(Product dish) {
    final parts = <String>[];
    var id = dish.parentId;
    for (var depth = 0; depth < 5 && groups.containsKey(id); depth++) {
      final g = groups[id]!;
      parts.addAll([g.name, g.nameEn, g.nameTr]);
      id = g.parentId;
    }
    return parts.join(' ');
  }

  final scored = <(Product, int)>[];
  for (final dish in items) {
    if (dish.isGroup) continue;
    final names = _searchable('${dish.name} ${dish.nameEn} ${dish.nameTr}');
    final rest = _searchable(
      '${dish.description} ${dish.descEn} ${dish.descTr} ${categoryText(dish)}',
    );
    if (!words.every((w) => names.contains(w) || rest.contains(w))) continue;

    // Выше — название, которое начинается с запроса, потом — где запрос
    // в начале другого слова названия, потом — где-то в названии, ниже всех —
    // только в описании или категории
    final first = words.first;
    final score = names.startsWith(first)
        ? 0
        : names.contains(' $first')
            ? 1
            : words.every(names.contains)
                ? 2
                : 3;
    scored.add((dish, score));
  }
  scored.sort((a, b) {
    final byScore = a.$2.compareTo(b.$2);
    return byScore != 0 ? byScore : compareByOrder(a.$1, b.$1);
  });
  return [for (final s in scored) s.$1];
}

/// Текст для поиска: как написан и он же латиницей, через пробел.
String _searchable(String text) {
  final n = _normalize(text);
  return '$n ${_toLatin(n)}';
}

String _normalize(String s) => s
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

const _latin = {
  'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ж': 'zh',
  'з': 'z', 'и': 'i', 'й': 'i', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n',
  'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ф': 'f',
  'х': 'h', 'ц': 'c', 'ч': 'ch', 'ш': 'sh', 'щ': 'sch', 'ъ': '', 'ы': 'y',
  'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
  // кыргызские буквы
  'ң': 'n', 'ө': 'o', 'ү': 'u',
};

String _toLatin(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    b.write(_latin[ch] ?? ch);
  }
  return b.toString();
}
