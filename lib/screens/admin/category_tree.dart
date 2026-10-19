/// Категории филиала из админского API в порядке меню: основная, сразу за
/// ней её подкатегории. Подкатегория, чей родитель пропал, считается
/// основной — так её видит и меню гостя.
List<Map<String, dynamic>> categoryTree(List<Map<String, dynamic>> cats) {
  final ids = {for (final c in cats) c['id']};
  bool isRoot(Map<String, dynamic> c) => !ids.contains(c['parent_id']);
  int order(Map<String, dynamic> c) => (c['sort_order'] as num?)?.toInt() ?? 0;
  int byOrder(Map<String, dynamic> a, Map<String, dynamic> b) =>
      order(a).compareTo(order(b));

  final roots = cats.where(isRoot).toList()..sort(byOrder);
  return [
    for (final root in roots) ...[
      root,
      ...cats.where((c) => c['parent_id'] == root['id']).toList()..sort(byOrder),
    ],
  ];
}

/// Подкатегория ли это (родитель есть среди [cats]).
bool isSubcategory(Map<String, dynamic> cat, List<Map<String, dynamic>> cats) =>
    cat['parent_id'] != null && cats.any((c) => c['id'] == cat['parent_id']);

/// Название с родителем: «Супы › Холодные».
String categoryPath(Map<String, dynamic> cat, List<Map<String, dynamic>> cats) {
  final name = cat['name'] as String? ?? '';
  if (!isSubcategory(cat, cats)) return name;
  final parent = cats.firstWhere((c) => c['id'] == cat['parent_id']);
  return '${parent['name'] ?? ''} › $name';
}
