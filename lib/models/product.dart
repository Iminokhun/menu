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
  final String name;
  final String nameEn;
  final String nameTr;
  final String description;
  final String descEn;
  final String descTr;
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
    this.nameEn = '',
    this.nameTr = '',
    this.description = '',
    this.descEn = '',
    this.descTr = '',
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
        nameEn: jsonStr(json['name_en']),
        nameTr: jsonStr(json['name_tr']),
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
      nameEn: jsonStr(json['name_en']),
      nameTr: jsonStr(json['name_tr']),
      description: jsonStr(json['description']),
      descEn: jsonStr(json['desc_en']),
      descTr: jsonStr(json['desc_tr']),
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

  /// Локализованное название товара/категории
  String localizedName(String langCode) {
    if (langCode == 'en' && nameEn.isNotEmpty) return nameEn;
    if (langCode == 'tr' && nameTr.isNotEmpty) return nameTr;
    return name;
  }

  /// Локализованное описание
  String localizedDesc(String langCode) {
    if (langCode == 'en' && descEn.isNotEmpty) return descEn;
    if (langCode == 'tr' && descTr.isNotEmpty) return descTr;
    return description;
  }
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
