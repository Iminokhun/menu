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
    'ky': {
      'catalog': 'КАТАЛОГ',
      'open': 'АЧУУ',
      'menuInPhone': 'Телефондогу меню',
      'all': 'БААРЫ',
      'emptyCategory': 'Бул категория бош',
      'menuLoading': 'ЖҮКТӨЛҮҮДӨ...',
      'yourOrder': 'СИЗДИН БУЙРУТМА',
      'total': 'ЖАЛПЫ:',
      'placeOrder': 'БУЙРУТМА БЕРҮҮ (ЖАКЫНДА)',
      'clearCart': 'Себетти тазалоо',
      'cartEmpty': 'Себет бош',
      'add': 'КОШУУ',
      'som': 'сом',
      'pcs': 'даана',
      'noDescription': 'Сүрөттөмө жок.',
      'size': 'Өлчөмү:',
      'applyingTheme': 'Тема колдонулууда...',
      'search': 'Тамак издөө',
      'searchHint': 'Аталышы же курамы',
      'searchStart': 'Тамактын атын жазыңыз',
      'nothingFound': 'Эч нерсе табылган жок',
      'found': 'Табылды',
    },
    'kk': {
      'catalog': 'КАТАЛОГ',
      'open': 'АШУ',
      'menuInPhone': 'Телефондағы мәзір',
      'all': 'БАРЛЫҒЫ',
      'emptyCategory': 'Бұл санат бос',
      'menuLoading': 'ЖҮКТЕЛУДЕ...',
      'yourOrder': 'СІЗДІҢ ТАПСЫРЫСЫҢЫЗ',
      'total': 'ЖИЫНЫ:',
      'placeOrder': 'ТАПСЫРЫС БЕРУ (ЖАҚЫНДА)',
      'clearCart': 'Себетті тазарту',
      'cartEmpty': 'Себет бос',
      'add': 'ҚОСУ',
      'som': 'сом',
      'pcs': 'дана',
      'noDescription': 'Сипаттама жоқ.',
      'size': 'Өлшемі:',
      'applyingTheme': 'Тақырып қолданылуда...',
      'search': 'Тағам іздеу',
      'searchHint': 'Атауы немесе құрамы',
      'searchStart': 'Тағам атауын жазыңыз',
      'nothingFound': 'Ештеңе табылмады',
      'found': 'Табылды',
    },
    'uz': {
      'catalog': 'KATALOG',
      'open': 'OCHISH',
      'menuInPhone': 'Telefondagi menyu',
      'all': 'HAMMASI',
      'emptyCategory': 'Bu toifa boʻsh',
      'menuLoading': 'YUKLANMOQDA...',
      'yourOrder': 'BUYURTMANGIZ',
      'total': 'JAMI:',
      'placeOrder': 'BUYURTMA BERISH (TEZ ORADA)',
      'clearCart': 'Savatni tozalash',
      'cartEmpty': 'Savat boʻsh',
      'add': 'QOʻSHISH',
      'som': 'som',
      'pcs': 'dona',
      'noDescription': 'Tavsif yoʻq.',
      'size': 'Hajmi:',
      'applyingTheme': 'Mavzu qoʻllanmoqda...',
      'search': 'Taom qidirish',
      'searchHint': 'Nomi yoki tarkibi',
      'searchStart': 'Taom nomini yozing',
      'nothingFound': 'Hech narsa topilmadi',
      'found': 'Topildi',
    },
    'zh': {
      'catalog': '菜单',
      'open': '打开',
      'menuInPhone': '手机菜单',
      'all': '全部',
      'emptyCategory': '此分类暂无菜品',
      'menuLoading': '加载中...',
      'yourOrder': '您的订单',
      'total': '合计：',
      'placeOrder': '下单（即将推出）',
      'clearCart': '清空购物车',
      'cartEmpty': '购物车是空的',
      'add': '添加',
      'som': '索姆',
      'pcs': '份',
      'noDescription': '暂无描述。',
      'size': '规格：',
      'applyingTheme': '正在应用主题...',
      'search': '搜索菜品',
      'searchHint': '菜名或配料',
      'searchStart': '请输入菜名',
      'nothingFound': '未找到结果',
      'found': '找到',
    },
    'ko': {
      'catalog': '메뉴',
      'open': '열기',
      'menuInPhone': '휴대폰 메뉴',
      'all': '전체',
      'emptyCategory': '이 카테고리는 비어 있습니다',
      'menuLoading': '불러오는 중...',
      'yourOrder': '주문 내역',
      'total': '합계:',
      'placeOrder': '주문하기 (준비 중)',
      'clearCart': '장바구니 비우기',
      'cartEmpty': '장바구니가 비어 있습니다',
      'add': '담기',
      'som': '솜',
      'pcs': '개',
      'noDescription': '설명이 없습니다.',
      'size': '사이즈:',
      'applyingTheme': '테마 적용 중...',
      'search': '메뉴 검색',
      'searchHint': '메뉴 이름 또는 재료',
      'searchStart': '메뉴 이름을 입력하세요',
      'nothingFound': '검색 결과가 없습니다',
      'found': '검색 결과',
    },
    'ja': {
      'catalog': 'メニュー',
      'open': '開く',
      'menuInPhone': 'スマホでメニュー',
      'all': 'すべて',
      'emptyCategory': 'このカテゴリーは空です',
      'menuLoading': '読み込み中...',
      'yourOrder': 'ご注文',
      'total': '合計：',
      'placeOrder': '注文する（近日公開）',
      'clearCart': 'カートを空にする',
      'cartEmpty': 'カートは空です',
      'add': '追加',
      'som': 'ソム',
      'pcs': '個',
      'noDescription': '説明はありません。',
      'size': 'サイズ：',
      'applyingTheme': 'テーマを適用中...',
      'search': '料理を検索',
      'searchHint': '料理名または材料',
      'searchStart': '料理名を入力してください',
      'nothingFound': '見つかりませんでした',
      'found': '件数',
    },
    'de': {
      'catalog': 'KATALOG',
      'open': 'ÖFFNEN',
      'menuInPhone': 'Menü auf dem Handy',
      'all': 'ALLE',
      'emptyCategory': 'Diese Kategorie ist leer',
      'menuLoading': 'LÄDT...',
      'yourOrder': 'IHRE BESTELLUNG',
      'total': 'GESAMT:',
      'placeOrder': 'BESTELLEN (BALD)',
      'clearCart': 'Warenkorb leeren',
      'cartEmpty': 'Der Warenkorb ist leer',
      'add': 'HINZUFÜGEN',
      'som': 'Som',
      'pcs': 'Stk.',
      'noDescription': 'Keine Beschreibung.',
      'size': 'Größe:',
      'applyingTheme': 'Design wird angewendet...',
      'search': 'Gerichte suchen',
      'searchHint': 'Name oder Zutat',
      'searchStart': 'Namen eines Gerichts eingeben',
      'nothingFound': 'Nichts gefunden',
      'found': 'Gefunden',
    },
    'fr': {
      'catalog': 'CATALOGUE',
      'open': 'OUVRIR',
      'menuInPhone': 'Menu sur le téléphone',
      'all': 'TOUT',
      'emptyCategory': 'Cette catégorie est vide',
      'menuLoading': 'CHARGEMENT...',
      'yourOrder': 'VOTRE COMMANDE',
      'total': 'TOTAL :',
      'placeOrder': 'COMMANDER (BIENTÔT)',
      'clearCart': 'Vider le panier',
      'cartEmpty': 'Le panier est vide',
      'add': 'AJOUTER',
      'som': 'som',
      'pcs': 'pcs',
      'noDescription': 'Pas de description.',
      'size': 'Taille :',
      'applyingTheme': 'Application du thème...',
      'search': 'Rechercher un plat',
      'searchHint': 'Nom ou ingrédient',
      'searchStart': 'Saisissez le nom d’un plat',
      'nothingFound': 'Aucun résultat',
      'found': 'Trouvé',
    },
    'es': {
      'catalog': 'CATÁLOGO',
      'open': 'ABRIR',
      'menuInPhone': 'Menú en el móvil',
      'all': 'TODO',
      'emptyCategory': 'Esta categoría está vacía',
      'menuLoading': 'CARGANDO...',
      'yourOrder': 'SU PEDIDO',
      'total': 'TOTAL:',
      'placeOrder': 'HACER PEDIDO (PRONTO)',
      'clearCart': 'Vaciar carrito',
      'cartEmpty': 'El carrito está vacío',
      'add': 'AÑADIR',
      'som': 'som',
      'pcs': 'ud.',
      'noDescription': 'Sin descripción.',
      'size': 'Tamaño:',
      'applyingTheme': 'Aplicando tema...',
      'search': 'Buscar platos',
      'searchHint': 'Nombre o ingrediente',
      'searchStart': 'Escriba el nombre de un plato',
      'nothingFound': 'No se encontró nada',
      'found': 'Encontrado',
    },
  };

  /// Языки, на которые переведены кнопки меню (см. languages.dart).
  static Iterable<String> get supportedCodes => _strings.keys;

  /// Ключи, которые есть у каждого языка (для теста полноты перевода).
  static Map<String, Set<String>> get keysByLanguage =>
      {for (final e in _strings.entries) e.key: e.value.keys.toSet()};

  String get(String key) {
    final lang = locale.languageCode;
    return _strings[lang]?[key] ?? _strings['en']![key] ?? key;
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
      AppLocalizations.supportedCodes.contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
