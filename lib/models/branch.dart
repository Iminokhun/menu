import '../l10n/languages.dart';
import 'json_read.dart';

/// Филиал — отдельное заведение со своим меню.
///
/// Заменяет таблицу `shop`, в которой была ровно одна строка: приложение
/// читало её через `.single()`, и со вторым филиалом это падало бы.
class Branch {
  final String id;

  /// Короткое имя для ссылки QR-кода: `?branch=center`.
  final String slug;

  final String name;
  final String slogan;
  final String phone;
  final String logoUrl;

  /// Ссылка, из которой рисуется QR-код. У каждого филиала своя,
  /// со своим `?branch=`, иначе оба кода ведут в одно меню.
  final String qrUrl;

  final int sortOrder;

  /// Оформление меню, которое задало кафе в админке
  final BranchStyle style;

  /// Языки меню, первый — основной: на нём названия блюд в `name`.
  final List<String> languages;

  String get mainLanguage => languages.first;

  const Branch({
    required this.id,
    required this.slug,
    required this.name,
    this.slogan = '',
    this.phone = '',
    this.logoUrl = '',
    this.qrUrl = '',
    this.sortOrder = 0,
    this.style = const BranchStyle(),
    this.languages = const ['ru'],
  });

  /// Подстановки на случай пустых полей живут здесь, а не на экране:
  /// филиал читают и экран гостя, и админка.
  factory Branch.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] as String?) ?? '';
    final slogan = (json['slogan'] as String?) ?? '';
    return Branch(
      id: json['id'] as String,
      slug: (json['slug'] as String?) ?? '',
      name: name.isEmpty ? 'MENU' : name,
      slogan: slogan.isEmpty ? 'Добро пожаловать' : slogan,
      phone: (json['phone'] as String?) ?? '',
      logoUrl: (json['logo_url'] as String?) ?? '',
      qrUrl: (json['qr_url'] as String?) ?? '',
      sortOrder: jsonInt(json['sort_order']),
      style: BranchStyle.fromJson(json),
      languages: _languages(json['languages']),
    );
  }

  /// Языки, которые это приложение знает. Пустой список (старый сервер,
  /// старая копия меню) — русский: на нём меню было всегда.
  static List<String> _languages(Object? v) {
    final known = jsonStrings(v).where((c) => menuLanguage(c) != null).toList();
    return known.isEmpty ? const ['ru'] : known;
  }
}

/// Оформление меню филиала. Пустая строка в любом поле — «как по умолчанию».
/// Варианты совпадают со списком на сервере (server/lib/api.dart, _styleChoices).
class BranchStyle {
  /// Тема: midnight, porcelain, royal, sea, sakura, highContrast
  final String theme;

  /// Фирменный цвет `#RRGGBB` вместо цвета темы
  final String accent;

  /// Своя картинка фона
  final String bgUrl;

  /// small, normal, large
  final String cardSize;

  /// sharp, soft, round
  final String corners;

  /// classic, montserrat, playfair, oswald, lora
  final String titleFont;

  const BranchStyle({
    this.theme = '',
    this.accent = '',
    this.bgUrl = '',
    this.cardSize = '',
    this.corners = '',
    this.titleFont = '',
  });

  factory BranchStyle.fromJson(Map<String, dynamic> j) => BranchStyle(
        theme: jsonStr(j['theme']),
        accent: jsonStr(j['accent']),
        bgUrl: jsonStr(j['bg_url']),
        cardSize: jsonStr(j['card_size']),
        corners: jsonStr(j['corners']),
        titleFont: jsonStr(j['title_font']),
      );

  Map<String, String> toJson() => {
        'theme': theme,
        'accent': accent,
        'bg_url': bgUrl,
        'card_size': cardSize,
        'corners': corners,
        'title_font': titleFont,
      };

  BranchStyle copyWith({
    String? theme,
    String? accent,
    String? bgUrl,
    String? cardSize,
    String? corners,
    String? titleFont,
  }) =>
      BranchStyle(
        theme: theme ?? this.theme,
        accent: accent ?? this.accent,
        bgUrl: bgUrl ?? this.bgUrl,
        cardSize: cardSize ?? this.cardSize,
        corners: corners ?? this.corners,
        titleFont: titleFont ?? this.titleFont,
      );

  @override
  bool operator ==(Object other) =>
      other is BranchStyle &&
      other.theme == theme &&
      other.accent == accent &&
      other.bgUrl == bgUrl &&
      other.cardSize == cardSize &&
      other.corners == corners &&
      other.titleFont == titleFont;

  @override
  int get hashCode => Object.hash(theme, accent, bgUrl, cardSize, corners, titleFont);
}
