import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const _strings = {
    'ru': {
      // Главный экран
      'catalog': 'КАТАЛОГ',
      'open': 'ОТКРЫТЬ',
      'menuInPhone': 'Меню в телефоне',
      // Меню
      'all': 'ВСЕ',
      'emptyCategory': 'В этой категории пусто',
      'menuLoading': 'ЗАГРУЗКА...',
      // Корзина
      'yourOrder': 'ВАШ ЗАКАЗ',
      'total': 'ИТОГО:',
      'placeOrder': 'ОФОРМИТЬ ЗАКАЗ (СКОРО)',
      'clearCart': 'Очистить корзину',
      'cartEmpty': 'Корзина пуста',
      // Карточка товара
      'add': 'ДОБАВИТЬ',
      'som': 'с.',
      'pcs': 'шт.',
      'noDescription': 'Описание отсутствует.',
      'size': 'Размер:',
      // Темы
      'applyingTheme': 'Применение темы...',
      // Поиск
      'search': 'Поиск блюд',
      'searchHint': 'Название или ингредиент',
      'searchStart': 'Введите название блюда',
      'nothingFound': 'Ничего не найдено',
      'found': 'Найдено',
    },
    'en': {
      'catalog': 'CATALOG',
      'open': 'OPEN',
      'menuInPhone': 'Menu on phone',
      'all': 'ALL',
      'emptyCategory': 'This category is empty',
      'menuLoading': 'LOADING...',
      'yourOrder': 'YOUR ORDER',
      'total': 'TOTAL:',
      'placeOrder': 'PLACE ORDER (SOON)',
      'clearCart': 'Clear cart',
      'cartEmpty': 'Cart is empty',
      'add': 'ADD',
      'som': 'som',
      'pcs': 'pcs.',
      'noDescription': 'No description.',
      'size': 'Size:',
      'applyingTheme': 'Applying theme...',
      'search': 'Search dishes',
      'searchHint': 'Dish name or ingredient',
      'searchStart': 'Type a dish name',
      'nothingFound': 'Nothing found',
      'found': 'Found',
    },
    'tr': {
      'catalog': 'KATALOG',
      'open': 'AÇ',
      'menuInPhone': 'Telefonda menü',
      'all': 'HEPSİ',
      'emptyCategory': 'Bu kategori boş',
      'menuLoading': 'YÜKLENİYOR...',
      'yourOrder': 'SİPARİŞİNİZ',
      'total': 'TOPLAM:',
      'placeOrder': 'SİPARİŞ VER (YAKINDA)',
      'clearCart': 'Sepeti temizle',
      'cartEmpty': 'Sepet boş',
      'add': 'EKLE',
      'som': 'som',
      'pcs': 'adet',
      'noDescription': 'Açıklama yok.',
      'size': 'Boyut:',
      'applyingTheme': 'Tema uygulanıyor...',
      'search': 'Yemek ara',
      'searchHint': 'Yemek adı veya malzeme',
      'searchStart': 'Yemek adını yazın',
      'nothingFound': 'Sonuç bulunamadı',
      'found': 'Bulunan',
    },
  };

  String get(String key) {
    final lang = locale.languageCode;
    return _strings[lang]?[key] ?? _strings['ru']![key] ?? key;
  }

  // Удобные геттеры
  String get catalog => get('catalog');
  String get search => get('search');
  String get searchHint => get('searchHint');
  String get searchStart => get('searchStart');
  String get nothingFound => get('nothingFound');
  String get found => get('found');
  String get open => get('open');
  String get menuInPhone => get('menuInPhone');
  String get all => get('all');
  String get emptyCategory => get('emptyCategory');
  String get menuLoading => get('menuLoading');
  String get yourOrder => get('yourOrder');
  String get total => get('total');
  String get placeOrder => get('placeOrder');
  String get clearCart => get('clearCart');
  String get cartEmpty => get('cartEmpty');
  String get add => get('add');
  String get som => get('som');
  String get pcs => get('pcs');
  String get noDescription => get('noDescription');
  String get size => get('size');
  String get applyingTheme => get('applyingTheme');
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['ru', 'en', 'tr'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
