import 'package:flutter/material.dart';

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
  });

  static Map<AppThemeType, ThemeConfig> palettes = {
    AppThemeType.midnight: ThemeConfig(
      name: "MIDNIGHT",
      bg: const Color(0xFF000000),
      bgImage:
          "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?q=80&w=2564&auto=format&fit=crop",
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
      bgImage:
          "https://images.unsplash.com/photo-1590664216212-65e7004a7c0f?q=80&w=2574&auto=format&fit=crop",
      bgOverlay: Colors.white.withValues(alpha: 0.9),
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
