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

/// Филиал, чья корзина сейчас собрана (его slug).
String? _cartBranch;

/// Корзину обнулил переход в другое кафе. Экран гостя говорит об этом один
/// раз и опускает флаг: молча исчезнувшая корзина выглядит поломкой.
final ValueNotifier<bool> cartDropped = ValueNotifier(false);

/// Привязать корзину к филиалу, чьё меню открывают.
///
/// Корзина одна на всё приложение, а блюда, цены и номер WhatsApp у каждого
/// филиала свои. Собранное в одном кафе в другом не продадут: сервер считает
/// заказ по меню того филиала, которому он адресован, и чужие блюда попали бы
/// в него строками с нулевой ценой и пометкой «перезвонить». Поэтому при
/// переходе в другой филиал корзина обнуляется.
///
/// Тот же филиал корзину сохраняет: гость мог выйти в каталог и вернуться,
/// нажать «Обновить» или остаться без связи.
void bindCartToBranch(String slug) {
  if (slug == _cartBranch) return;
  _cartBranch = slug;
  if (globalCart.value.isEmpty) return;
  globalCart.value = [];
  cartDropped.value = true;
}

/// Корзина снова ничья: нужно тестам, чтобы один не тянул состояние в другой.
@visibleForTesting
void forgetCartBranch() {
  _cartBranch = null;
  cartDropped.value = false;
}

/// Сумма корзины и число блюд в ней.
///
/// Считаются в одном месте нарочно: эти два числа показывает кнопка корзины,
/// сама корзина, экран оформления и сообщение в WhatsApp. Четыре копии
/// одной денежной арифметики — это ровно то, как они однажды разойдутся.
double cartTotal(List<CartItem> cart) =>
    cart.fold(0, (sum, i) => sum + i.price * i.quantity);

int cartCount(List<CartItem> cart) => cart.fold(0, (sum, i) => sum + i.quantity);

/// Сумма для показа: «280», «280.50».
///
/// Одна функция на всё приложение — кнопку корзины, корзину, оформление,
/// сообщение в WhatsApp и админку. Раньше экран отрезал дробную часть
/// (`toInt`), а сообщение округляло: на экране «649 с.», в WhatsApp
/// «649.90 с.», и слагаемые не сходились с итогом.
///
/// Округляем, а не отрезаем: 100.6 + 100.6 — это 201.2, а не 201.
String money(double v) {
  final rounded = (v * 100).round() / 100;
  return rounded == rounded.roundToDouble()
      ? rounded.round().toString()
      : rounded.toStringAsFixed(2);
}

/// Сколько порций одного блюда помещается в одну строку заказа и сколько
/// строк бывает в заказе. Те же числа стоят на сервере (`_maxOrderQty`,
/// `_maxOrderItems`): перешагнув их, гость получил бы отказ уже после того,
/// как сообщение ушло в WhatsApp, — заказ не попал бы никуда.
const maxCartQuantity = 99;
const maxCartLines = 100;

/// Чем кончилась попытка положить блюдо в корзину.
enum AddToCart {
  added,

  /// Упёрлись в [maxCartQuantity] по этому блюду
  tooManyOfOne,

  /// Упёрлись в [maxCartLines] разных строк
  tooManyLines,
}

/// Добавить блюдо в корзину — из меню и из поиска одинаково.
/// Та же порция того же блюда не дублируется, а прибавляется к количеству.
AddToCart addToCart(Product p, Portion? portion, int quantity) {
  final current = globalCart.value;
  final index = current.indexWhere(
    (i) => i.product.id == p.id && i.portion?.name == portion?.name,
  );
  if (index >= 0) {
    if (current[index].quantity >= maxCartQuantity) {
      return AddToCart.tooManyOfOne;
    }
    current[index].quantity = (current[index].quantity + quantity)
        .clamp(1, maxCartQuantity);
    globalCart.value = List.from(current);
  } else {
    if (current.length >= maxCartLines) return AddToCart.tooManyLines;
    globalCart.value = [
      ...current,
      CartItem(
        product: p,
        portion: portion,
        quantity: quantity.clamp(1, maxCartQuantity),
      ),
    ];
  }
  HapticFeedback.lightImpact();
  return AddToCart.added;
}

/// Единый порядок для категорий и товаров: сначала поле «Порядок» из админки,
/// при равных значениях — по алфавиту (у новых записей sort_order = 0).
int compareByOrder(Product a, Product b) {
  final byOrder = a.sortOrder.compareTo(b.sortOrder);
  return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
}
