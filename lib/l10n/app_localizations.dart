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
      'loading': 'Загрузка...',
      'updating': 'Обновление...',
      'menuLoaded': 'Меню загружено!',
      'error': 'Ошибка',
      'sync': 'Загрузить',
      'settings': 'НАСТРОЙКИ',
      'menuInPhone': 'Меню в телефоне',
      // Меню
      'all': 'ВСЕ',
      'emptyCategory': 'В этой категории пусто',
      'backToMain': 'На главную',
      'menuLoading': 'ЗАГРУЗКА...',
      // Корзина
      'yourOrder': 'ВАШ ЗАКАЗ',
      'total': 'ИТОГО:',
      'placeOrder': 'ОФОРМИТЬ ЗАКАЗ (СКОРО)',
      'clearCart': 'Очистить корзину',
      'cartEmpty': 'Корзина пуста',
      // Карточка товара
      'addToCart': 'В КОРЗИНУ',
      'choosePortion': 'Выберите порцию',
      'quantity': 'Количество',
      'add': 'ДОБАВИТЬ',
      'som': 'с.',
      // Настройки сервера
      'serverSettings': 'Настройки Сервера (Админ)',
      'serverAddress': 'Адрес сервера',
      'dbName': 'Имя базы (Publication)',
      'authorization': 'Авторизация',
      'user': 'Пользователь',
      'password': 'Пароль',
      'cancel': 'Отмена',
      'save': 'Сохранить',
      'settingsSaved': 'Настройки сохранены',
      'applyingTheme': 'Применение темы...',
      'pcs': 'шт.',
      'noDescription': 'Описание отсутствует.',
      'size': 'Размер:',
    },
    'en': {
      'catalog': 'CATALOG',
      'open': 'OPEN',
      'loading': 'Loading...',
      'updating': 'Updating...',
      'menuLoaded': 'Menu loaded!',
      'error': 'Error',
      'sync': 'Update',
      'settings': 'SETTINGS',
      'menuInPhone': 'Menu on phone',
      'all': 'ALL',
      'emptyCategory': 'This category is empty',
      'backToMain': 'Home',
      'menuLoading': 'LOADING...',
      'yourOrder': 'YOUR ORDER',
      'total': 'TOTAL:',
      'placeOrder': 'PLACE ORDER (SOON)',
      'clearCart': 'Clear cart',
      'cartEmpty': 'Cart is empty',
      'addToCart': 'ADD TO CART',
      'choosePortion': 'Choose portion',
      'quantity': 'Quantity',
      'add': 'ADD',
      'som': 'som',
      'serverSettings': 'Server Settings (Admin)',
      'serverAddress': 'Server address',
      'dbName': 'Database name (Publication)',
      'authorization': 'Authorization',
      'user': 'Username',
      'password': 'Password',
      'cancel': 'Cancel',
      'save': 'Save',
      'settingsSaved': 'Settings saved',
      'applyingTheme': 'Applying theme...',
      'pcs': 'pcs.',
      'noDescription': 'No description.',
      'size': 'Size:',
    },
    'tr': {
      'catalog': 'KATALOG',
      'open': 'AÇ',
      'loading': 'Yükleniyor...',
      'updating': 'Güncelleniyor...',
      'menuLoaded': 'Menü yüklendi!',
      'error': 'Hata',
      'sync': 'Güncelle',
      'settings': 'AYARLAR',
      'menuInPhone': 'Telefonda menü',
      'all': 'HEPSİ',
      'emptyCategory': 'Bu kategori boş',
      'backToMain': 'Ana sayfa',
      'menuLoading': 'YÜKLENİYOR...',
      'yourOrder': 'SİPARİŞİNİZ',
      'total': 'TOPLAM:',
      'placeOrder': 'SİPARİŞ VER (YAKINDA)',
      'clearCart': 'Sepeti temizle',
      'cartEmpty': 'Sepet boş',
      'addToCart': 'SEPETE EKLE',
      'choosePortion': 'Porsiyon seçin',
      'quantity': 'Miktar',
      'add': 'EKLE',
      'som': 'som',
      'serverSettings': 'Sunucu Ayarları (Admin)',
      'serverAddress': 'Sunucu adresi',
      'dbName': 'Veritabanı adı (Publication)',
      'authorization': 'Yetkilendirme',
      'user': 'Kullanıcı adı',
      'password': 'Şifre',
      'cancel': 'İptal',
      'save': 'Kaydet',
      'settingsSaved': 'Ayarlar kaydedildi',
      'applyingTheme': 'Tema uygulanıyor...',
      'pcs': 'adet',
      'noDescription': 'Açıklama yok.',
      'size': 'Boyut:',
    },
  };

  String get(String key) {
    final lang = locale.languageCode;
    return _strings[lang]?[key] ?? _strings['ru']![key] ?? key;
  }

  // Удобные геттеры
  String get catalog => get('catalog');
  String get open => get('open');
  String get loading => get('loading');
  String get updating => get('updating');
  String get menuLoaded => get('menuLoaded');
  String get error => get('error');
  String get sync => get('sync');
  String get settings => get('settings');
  String get menuInPhone => get('menuInPhone');
  String get all => get('all');
  String get emptyCategory => get('emptyCategory');
  String get backToMain => get('backToMain');
  String get menuLoading => get('menuLoading');
  String get yourOrder => get('yourOrder');
  String get total => get('total');
  String get placeOrder => get('placeOrder');
  String get clearCart => get('clearCart');
  String get cartEmpty => get('cartEmpty');
  String get addToCart => get('addToCart');
  String get choosePortion => get('choosePortion');
  String get quantity => get('quantity');
  String get add => get('add');
  String get som => get('som');
  String get serverSettings => get('serverSettings');
  String get serverAddress => get('serverAddress');
  String get dbName => get('dbName');
  String get authorization => get('authorization');
  String get user => get('user');
  String get password => get('password');
  String get cancel => get('cancel');
  String get save => get('save');
  String get settingsSaved => get('settingsSaved');
  String get applyingTheme => get('applyingTheme');
  String get pcs => get('pcs');
  String get noDescription => get('noDescription');
  String get size => get('size');
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
