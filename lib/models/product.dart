import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'json_read.dart';

class Portion {
  final String name;
  final double price;
  Portion({required this.name, required this.price});

  factory Portion.fromJson(Map<String, dynamic> json) =>
      Portion(name: jsonStr(json['name']), price: jsonDouble(json['price']));
  Map<String, dynamic> toJson() => {'name': name, 'price': price};
}

class Product {
  final String id;
  final String parentId;
  /// Название и описание на основном языке филиала.
  final String name;
  final String description;

  /// Переводы на другие языки филиала: `{"en": {"name": …, "description": …}}`.
  final Map<String, Map<String, String>> i18n;
  final double price;
  final String imageUrl;

  /// 3D-модель блюда (.glb). Пустая — у блюда только фото.
  final String modelUrl;
  final bool isGroup;
  final List<Portion> portions;
  final int sortOrder;

  Product({
    required this.id,
    required this.parentId,
    required this.name,
    this.description = '',
    this.i18n = const {},
    this.price = 0,
    this.imageUrl = '',
    this.modelUrl = '',
    this.isGroup = false,
    this.portions = const [],
    this.sortOrder = 0,
  });

  /// Категория из ответа сервера: `parentId` — родительская категория.
  factory Product.categoryFromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        parentId: jsonStr(json['parent_id']),
        name: jsonStr(json['name']),
        i18n: i18nFromJson(json['i18n']),
        imageUrl: jsonStr(json['image_url']),
        isGroup: true,
        sortOrder: jsonInt(json['sort_order']),
      );

  /// Блюдо из ответа сервера: `parentId` — его категория. Порция
  /// неожиданного вида пропускается, остальные остаются.
  factory Product.dishFromJson(Map<String, dynamic> json) {
    final raw = json['portions'];
    return Product(
      id: json['id'] as String,
      parentId: jsonStr(json['category_id']),
      name: jsonStr(json['name']),
      description: jsonStr(json['description']),
      i18n: i18nFromJson(json['i18n']),
      price: jsonDouble(json['price']),
      imageUrl: jsonStr(json['image_url']),
      modelUrl: jsonStr(json['model_url']),
      isGroup: false,
      portions: [
        if (raw is List)
          for (final p in raw)
            if (p is Map<String, dynamic>) Portion.fromJson(p),
      ],
      sortOrder: jsonInt(json['sort_order']),
    );
  }

  /// Название на языке [langCode]; нет перевода — на основном языке.
  String localizedName(String langCode) => i18n[langCode]?['name'] ?? name;

  /// Описание на языке [langCode]; нет перевода — на основном языке.
  String localizedDesc(String langCode) =>
      i18n[langCode]?['description'] ?? description;

  /// Все тексты на всех языках — для поиска.
  Iterable<String> get allNames => [name, for (final t in i18n.values) ?t['name']];
  Iterable<String> get allDescriptions =>
      [description, for (final t in i18n.values) ?t['description']];
}

class CartItem {
  final Product product;
  final Portion? portion;
  int quantity;
  CartItem({required this.product, this.portion, this.quantity = 1});
  double get price => portion?.price ?? product.price;
}

// Глобальная корзина
final ValueNotifier<List<CartItem>> globalCart = ValueNotifier([]);

/// Добавить блюдо в корзину — из меню и из поиска одинаково.
/// Та же порция того же блюда не дублируется, а прибавляется к количеству.
void addToCart(Product p, Portion? portion, int quantity) {
  final current = globalCart.value;
  final index = current.indexWhere(
    (i) => i.product.id == p.id && i.portion?.name == portion?.name,
  );
  if (index >= 0) {
    current[index].quantity += quantity;
    globalCart.value = List.from(current);
  } else {
    globalCart.value = [
      ...current,
      CartItem(product: p, portion: portion, quantity: quantity),
    ];
  }
  HapticFeedback.lightImpact();
}

/// Единый порядок для категорий и товаров: сначала поле «Порядок» из админки,
/// при равных значениях — по алфавиту (у новых записей sort_order = 0).
int compareByOrder(Product a, Product b) {
  final byOrder = a.sortOrder.compareTo(b.sortOrder);
  return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
}
