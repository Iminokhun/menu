import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/product.dart';

class DatabaseService {
  SupabaseClient get _client => Supabase.instance.client;

  /// Информация о заведении
  Future<Map<String, String>> getShopInfo() async {
    try {
      final data = await _client.from('shop').select().single();
      return {
        'name': data['name'] ?? 'CAFE ANDALUS',
        'slogan': data['slogan'] ?? 'Добро пожаловать',
        'phone': data['phone'] ?? '',
        'logo_url': data['logo_url'] ?? '',
        'qr_url': data['qr_url'] ?? '',
      };
    } catch (e) {
      debugPrint('getShopInfo error: $e');
      return {
        'name': 'CAFE ANDALUS',
        'slogan': 'Добро пожаловать',
        'phone': '',
        'logo_url': '',
        'qr_url': '',
      };
    }
  }

  /// Загружает категории и товары параллельно,
  /// возвращает плоский список Product (как раньше из 1С).
  /// Категории → isGroup: true, parentId = parent_id
  /// Товары    → isGroup: false, parentId = category_id
  Future<List<Product>> getAllProducts() async {
    try {
      final results = await Future.wait([
        _client
            .from('categories')
            .select()
            .eq('is_visible', true)
            .order('sort_order'),
        _client
            .from('products')
            .select()
            .eq('is_visible', true)
            .order('sort_order'),
      ]);

      final categoriesList = results[0] as List;
      final productsList = results[1] as List;

      final List<Product> all = [];

      // Категории → Product(isGroup: true)
      for (final json in categoriesList) {
        all.add(Product(
          id: json['id'] as String,
          parentId: json['parent_id'] as String? ?? '',
          name: json['name'] ?? '',
          nameEn: json['name_en'] ?? '',
          nameTr: json['name_tr'] ?? '',
          imageUrl: json['image_url'] ?? '',
          isGroup: true,
          sortOrder: json['sort_order'] ?? 0,
        ));
      }

      // Товары → Product(isGroup: false)
      for (final json in productsList) {
        var pList = <Portion>[];
        final portionsJson = json['portions'];
        if (portionsJson != null && portionsJson is List) {
          for (var v in portionsJson) {
            pList.add(Portion.fromJson(v as Map<String, dynamic>));
          }
        }
        all.add(Product(
          id: json['id'] as String,
          parentId: json['category_id'] as String? ?? '',
          name: json['name'] ?? '',
          nameEn: json['name_en'] ?? '',
          nameTr: json['name_tr'] ?? '',
          description: json['description'] ?? '',
          descEn: json['desc_en'] ?? '',
          descTr: json['desc_tr'] ?? '',
          price: (json['price'] ?? 0).toDouble(),
          imageUrl: json['image_url'] ?? '',
          isGroup: false,
          portions: pList,
          sortOrder: json['sort_order'] ?? 0,
        ));
      }

      return all;
    } catch (e) {
      debugPrint('getAllProducts error: $e');
      return [];
    }
  }
}
