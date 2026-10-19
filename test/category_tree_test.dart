import 'package:cafe_andalus_menu/screens/admin/category_tree.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> cat(String id, int order, [String? parent]) =>
    {'id': id, 'name': id, 'sort_order': order, 'parent_id': parent};

void main() {
  final cats = [
    cat('Напитки', 2),
    cat('Холодные', 1, 'Супы'),
    cat('Супы', 1),
    cat('Горячие', 0, 'Супы'),
    cat('Сироты', 3, 'удалённая'),
  ];

  test('основная, за ней её подкатегории, всё по порядку', () {
    expect(categoryTree(cats).map((c) => c['id']), [
      'Супы',
      'Горячие',
      'Холодные',
      'Напитки',
      'Сироты',
    ]);
  });

  test('подкатегория без родителя считается основной', () {
    expect(isSubcategory(cats[1], cats), isTrue);
    expect(isSubcategory(cats[4], cats), isFalse);
  });

  test('название с родителем', () {
    expect(categoryPath(cats[1], cats), 'Супы › Холодные');
    expect(categoryPath(cats[0], cats), 'Напитки');
    expect(categoryPath(cats[4], cats), 'Сироты');
  });
}
