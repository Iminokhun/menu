import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/branch.dart';

enum AppThemeType { midnight, porcelain, royal, sea, sakura, highContrast }

class ThemeConfig {
  final String name;
  final Color bg;
  final Color bgOverlay;
  final String bgImage;
  final Color surface;
  final Color glass;
  final Color accent;
  final Color text;
  final Brightness brightness;
  final bool isHighContrast;

  /// Множитель скругления углов карточек (острые / мягкие / круглые)
  final double cornerScale;

  /// Множитель размера карточек в сетке (мелкие / обычные / крупные)
  final double gridScale;

  /// Шрифт названий: classic, montserrat, playfair, oswald, lora
  final String titleFont;

  ThemeConfig({
    required this.name,
    required this.bg,
    required this.bgOverlay,
    required this.bgImage,
    required this.surface,
    required this.glass,
    required this.accent,
    required this.text,
    required this.brightness,
    this.isHighContrast = false,
    this.cornerScale = 1,
    this.gridScale = 1,
    this.titleFont = 'classic',
  });

  /// Цвет текста и значков на фирменном цвете: на тёмно-синей кнопке
  /// чёрная надпись не читается, на жёлтой — белая
  Color get onAccent => accent.computeLuminance() > 0.45 ? Colors.black : Colors.white;

  /// Скругление с учётом выбора кафе: [base] — как было задумано в макете
  double radius(double base) => base * cornerScale;

  /// Заголовки: название кафе, категории
  TextStyle titleStyle({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      _font(titleFont == 'classic' ? 'Outfit' : null, fontSize, fontWeight, color, letterSpacing, height);

  /// Названия блюд — в классическом варианте антиквой, как было
  TextStyle dishTitleStyle({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
  }) =>
      _font(titleFont == 'classic' ? 'Cormorant Garamond' : null, fontSize, fontWeight, color, null, height);

  static const fontFamilies = {
    'montserrat': 'Montserrat',
    'playfair': 'Playfair Display',
    'oswald': 'Oswald',
    'lora': 'Lora',
  };

  TextStyle _font(String? classic, double? size, FontWeight? weight, Color? color,
      double? spacing, double? height) {
    final family = classic ?? fontFamilies[titleFont] ?? 'Outfit';
    return GoogleFonts.getFont(
      family,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
      height: height,
    );
  }

  ThemeConfig copyWith({
    Color? bgOverlay,
    String? bgImage,
    Color? accent,
    double? cornerScale,
    double? gridScale,
    String? titleFont,
  }) =>
      ThemeConfig(
        name: name,
        bg: bg,
        bgOverlay: bgOverlay ?? this.bgOverlay,
        bgImage: bgImage ?? this.bgImage,
        surface: surface,
        glass: glass,
        accent: accent ?? this.accent,
        text: text,
        brightness: brightness,
        isHighContrast: isHighContrast,
        cornerScale: cornerScale ?? this.cornerScale,
        gridScale: gridScale ?? this.gridScale,
        titleFont: titleFont ?? this.titleFont,
      );

  /// Тема меню по настройкам кафе: палитра выбранной темы, поверх — свой
  /// цвет, фон, углы, размер карточек и шрифт. Пустые поля — как в теме.
  static ThemeConfig forStyle(BranchStyle s) {
    final type = AppThemeType.values.firstWhere(
      (t) => t.name == s.theme,
      orElse: () => AppThemeType.midnight,
    );
    final base = palettes[type]!;

    // В контрастной теме жёлтый оставляем: она для тех, кто плохо видит
    final accent = base.isHighContrast ? null : parseHexColor(s.accent);

    String? bgImage;
    Color? overlay;
    if (s.bgUrl == 'none') {
      bgImage = ''; // однотонный фон
    } else if (s.bgUrl.isNotEmpty && !base.isHighContrast) {
      bgImage = s.bgUrl;
      // своё фото приглушаем, чтобы на нём читались карточки
      overlay = base.bg.withValues(alpha: 0.78);
    }

    return base.copyWith(
      accent: accent,
      bgImage: bgImage,
      bgOverlay: overlay,
      cornerScale: const {'sharp': 0.35, 'round': 1.4}[s.corners] ?? 1,
      gridScale: const {'small': 0.8, 'large': 1.25}[s.cardSize] ?? 1,
      titleFont: fontFamilies.containsKey(s.titleFont) ? s.titleFont : 'classic',
    );
  }

  /// `#RRGGBB` → цвет; что угодно другое → null
  static Color? parseHexColor(String hex) {
    final m = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(hex);
    return m == null ? null : Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
  }

  static Map<AppThemeType, ThemeConfig> palettes = {
    AppThemeType.midnight: ThemeConfig(
      name: "MIDNIGHT",
      bg: const Color(0xFF000000),
      // Фон лежит в самом приложении: виден без интернета и не зависит
      // от чужого сайта (раньше грузился с Unsplash)
      bgImage: "assets/backgrounds/midnight.jpg",
      bgOverlay: Colors.black.withValues(alpha: 0.8),
      surface: const Color(0xFF1E1E1E),
      glass: const Color(0xFF121212).withValues(alpha: 0.85),
      accent: const Color(0xFFD4AF37),
      text: const Color(0xFFE0E0E0),
      brightness: Brightness.dark,
    ),
    AppThemeType.porcelain: ThemeConfig(
      name: "PORCELAIN",
      bg: const Color(0xFFF2F2F7),
      // Свой мягкий светлый фон: картинку с Unsplash, которая была здесь,
      // там уже удалили. Она и так светлая, поэтому дымка слабее
      bgImage: "assets/backgrounds/porcelain.jpg",
      bgOverlay: Colors.white.withValues(alpha: 0.35),
      surface: const Color(0xFFFFFFFF),
      glass: const Color(0xFFFFFFFF).withValues(alpha: 0.9),
      accent: const Color(0xFF8B5A2B),
      text: const Color(0xFF1C1C1E),
      brightness: Brightness.light,
    ),
    AppThemeType.royal: ThemeConfig(
      name: "ROYAL",
      bg: const Color(0xFF0F0518),
      bgImage: "",
      bgOverlay: const Color(0xFF0F0518),
      surface: const Color(0xFF1F102E),
      glass: const Color(0xFF1F102E).withValues(alpha: 0.9),
      accent: const Color(0xFFFFD700),
      text: const Color(0xFFF3E5F5),
      brightness: Brightness.dark,
    ),
    AppThemeType.sea: ThemeConfig(
      name: "SEA",
      bg: const Color(0xFF001F24),
      bgImage: "",
      bgOverlay: const Color(0xFF001F24),
      surface: const Color(0xFF00363D),
      glass: const Color(0xFF00363D).withValues(alpha: 0.9),
      accent: const Color(0xFF64D2FF),
      text: const Color(0xFFE0F7FA),
      brightness: Brightness.dark,
    ),
    AppThemeType.sakura: ThemeConfig(
      name: "SAKURA",
      bg: const Color(0xFFFFF0F3),
      bgImage: "",
      bgOverlay: const Color(0xFFFFF0F3),
      surface: const Color(0xFFFFFFFF),
      glass: const Color(0xFFFFFFFF).withValues(alpha: 0.9),
      accent: const Color(0xFFFF4081),
      text: const Color(0xFF2D2D2D),
      brightness: Brightness.light,
    ),
    AppThemeType.highContrast: ThemeConfig(
      name: "ACCESSIBLE",
      bg: Colors.black,
      bgImage: "",
      bgOverlay: Colors.black,
      surface: const Color(0xFF000000),
      glass: const Color(0xFF000000),
      accent: const Color(0xFFFFFF00),
      text: const Color(0xFFFFFFFF),
      brightness: Brightness.dark,
      isHighContrast: true,
    ),
  };
}
