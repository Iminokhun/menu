import 'package:flutter/foundation.dart';

class Portion {
  final String name;
  final double price;
  Portion({required this.name, required this.price});

  factory Portion.fromJson(Map<String, dynamic> json) =>
      Portion(name: json['name'] ?? '', price: (json['price'] ?? 0).toDouble());
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
    this.isGroup = false,
    this.portions = const [],
    this.sortOrder = 0,
  });

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

  factory Product.fromSupabase(Map<String, dynamic> json) {
    var pList = <Portion>[];
    final portionsJson = json['portions'];
    if (portionsJson != null && portionsJson is List) {
      for (var v in portionsJson) {
        pList.add(Portion.fromJson(v as Map<String, dynamic>));
      }
    }
    return Product(
      id: json['id'] ?? '',
      parentId: json['parent_id'] ?? '',
      name: json['name'] ?? 'Без названия',
      nameEn: json['name_en'] ?? '',
      nameTr: json['name_tr'] ?? '',
      description: json['description'] ?? '',
      descEn: json['desc_en'] ?? '',
      descTr: json['desc_tr'] ?? '',
      price: (json['price'] ?? 0).toDouble(),
      imageUrl: json['image_url'] ?? '',
      isGroup: json['is_group'] ?? false,
      portions: pList,
      sortOrder: json['sort_order'] ?? 0,
    );
  }
}

class CartItem {
  final Product product;
  final Portion? portion;
  int quantity;
  CartItem({required this.product, this.portion, this.quantity = 1});
  double get price => portion?.price ?? product.price;
  String get name =>
      portion != null ? "${product.name} [${portion!.name}]" : product.name;
}

// Глобальная корзина
final ValueNotifier<List<CartItem>> globalCart = ValueNotifier([]);

/// Единый порядок для категорий и товаров: сначала поле «Порядок» из админки,
/// при равных значениях — по алфавиту (у новых записей sort_order = 0).
int compareByOrder(Product a, Product b) {
  final byOrder = a.sortOrder.compareTo(b.sortOrder);
  return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
}
