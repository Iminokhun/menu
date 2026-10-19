import 'package:cafe_andalus_menu/models/branch.dart';
import 'package:cafe_andalus_menu/models/product.dart';
import 'package:cafe_andalus_menu/menu_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('блюдо с полями неожиданного типа читается со значениями по умолчанию', () {
    final p = Product.dishFromJson({
      'id': 'd1',
      'category_id': null,
      'name': 5,
      'price': 'abc',
      'sort_order': 1.5,
      'model_url': null,
      'portions': [
        1,
        {'name': 'Большая', 'price': 450},
        {'name': null, 'price': '300'},
      ],
    });
    expect(p.parentId, '');
    expect(p.name, '');
    expect(p.price, 0);
    expect(p.sortOrder, 1);
    expect(p.modelUrl, '');
    expect(p.portions.map((x) => (x.name, x.price)), [('Большая', 450.0), ('', 300.0)]);
  });

  test('обычное блюдо читается как есть', () {
    final p = Product.dishFromJson({
      'id': 'd2',
      'category_id': 'c1',
      'name': 'Плов',
      'price': 350,
      'sort_order': 2,
      'model_url': 'http://x/uploads/a/m.glb',
      'portions': [],
    });
    expect((p.parentId, p.name, p.price, p.sortOrder, p.modelUrl),
        ('c1', 'Плов', 350.0, 2, 'http://x/uploads/a/m.glb'));
    expect(p.isGroup, isFalse);
  });

  test('строка, которую нельзя прочитать, пропускается, остальные остаются', () {
    final items = MenuStore.parseEach(
      [
        {'id': 'ok', 'name': 'Плов'},
        {'name': 'без id'},
        'не объект',
      ],
      Product.dishFromJson,
    );
    expect(items.map((p) => p.id), ['ok']);
  });

  test('категория и филиал не падают на дробном порядке', () {
    expect(Product.categoryFromJson({'id': 'c', 'sort_order': 3.0}).sortOrder, 3);
    expect(Branch.fromJson({'id': 'b', 'sort_order': 2.0}).sortOrder, 2);
  });
}
