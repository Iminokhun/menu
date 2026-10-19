import 'package:cafe_andalus_menu/models/product.dart';
import 'package:cafe_andalus_menu/search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final menu = [
    Product(id: 'soups', parentId: '', name: 'Супы', nameEn: 'Soups', isGroup: true),
    Product(id: 'hot', parentId: '', name: 'Горячее', isGroup: true),
    Product(id: 'kebab', parentId: 'hot', name: 'Шашлык', isGroup: true),
    Product(id: 'd1', parentId: 'soups', name: 'Суп грибной', description: 'С белыми грибами'),
    Product(id: 'd2', parentId: 'soups', name: 'Борщ', nameEn: 'Borscht'),
    Product(id: 'd3', parentId: 'hot', name: 'Плов', description: 'Рис, морковь, баранина'),
    Product(id: 'd4', parentId: 'kebab', name: 'Из баранины'),
    Product(id: 'd5', parentId: 'hot', name: 'Жаркое с грибами'),
    Product(id: 'd6', parentId: 'hot', name: 'Ёжики'),
  ];

  List<String> find(String q) => searchDishes(menu, q).map((p) => p.id).toList();

  test('по названию, без учёта регистра', () {
    expect(find('ПЛОВ'), ['d3']);
  });

  test('латиницей находит русское название', () {
    expect(find('plov'), ['d3']);
    expect(find('borsch'), ['d2']);
  });

  test('по английскому названию', () {
    expect(find('borscht'), ['d2']);
  });

  test('по описанию', () {
    expect(find('морковь'), ['d3']);
  });

  test('по категории — все её блюда, включая подкатегории', () {
    expect(find('супы'), unorderedEquals(['d1', 'd2']));
    expect(find('горячее'), unorderedEquals(['d3', 'd4', 'd5', 'd6']));
    expect(find('шашлык'), ['d4']);
  });

  test('несколько слов — нужны все', () {
    expect(find('суп грибной'), ['d1']);
  });

  test('часть слова находит все блюда, где оно есть', () {
    // «гриб» есть в названии у двух блюд, а у супа ещё и в описании
    expect(find('гриб').toSet(), {'d1', 'd5'});
  });

  test('совпадение в начале названия — первым', () {
    // По алфавиту «Азу…» шло бы первым, но «Курица…» начинается с запроса
    final r = searchDishes([
      Product(id: 'a', parentId: '', name: 'Азу из курицы'),
      Product(id: 'b', parentId: '', name: 'Курица гриль'),
      Product(id: 'c', parentId: '', name: 'Бургер', description: 'Котлета из курицы'),
    ], 'куриц');
    expect(r.map((p) => p.id), ['b', 'a', 'c']);
  });

  test('ё и е не различаются', () {
    expect(find('ежики'), ['d6']);
  });

  test('категории сами в результаты не попадают, пустой запрос — пусто', () {
    expect(find('супы').any((id) => id == 'soups'), isFalse);
    expect(find('   '), isEmpty);
  });

  test('ничего не найдено', () {
    expect(find('пицца'), isEmpty);
  });
}
