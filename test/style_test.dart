import 'package:cafe_andalus_menu/models/branch.dart';
import 'package:cafe_andalus_menu/theme/theme_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('оформление из ответа сервера, мусор — «по умолчанию»', () {
    final s = BranchStyle.fromJson({
      'theme': 'porcelain',
      'accent': '#C0392B',
      'bg_url': 5,
      'card_size': null,
    });
    expect(s.theme, 'porcelain');
    expect(s.accent, '#C0392B');
    expect(s.bgUrl, '');
    expect(s.cardSize, '');
    expect(Branch.fromJson({'id': 'b', 'theme': 'sea'}).style.theme, 'sea');
  });

  test('без настроек — тёмная тема с золотом, как было', () {
    final t = ThemeConfig.forStyle(const BranchStyle());
    final midnight = ThemeConfig.palettes[AppThemeType.midnight]!;
    expect(t.bg, midnight.bg);
    expect(t.accent, midnight.accent);
    expect(t.cornerScale, 1);
    expect(t.gridScale, 1);
    expect(t.titleFont, 'classic');
  });

  test('тема, свой цвет, углы, размер и шрифт применяются', () {
    final t = ThemeConfig.forStyle(const BranchStyle(
      theme: 'porcelain',
      accent: '#C0392B',
      cardSize: 'large',
      corners: 'round',
      titleFont: 'playfair',
    ));
    expect(t.brightness, Brightness.light);
    expect(t.accent, const Color(0xFFC0392B));
    expect(t.radius(10), closeTo(14, 0.001));
    expect(t.gridScale, 1.25);
    expect(t.titleFont, 'playfair');
  });

  test('неизвестные значения не ломают тему', () {
    final t = ThemeConfig.forStyle(const BranchStyle(
      theme: 'neon',
      accent: 'red',
      titleFont: 'comic',
      corners: 'zigzag',
    ));
    expect(t.accent, ThemeConfig.palettes[AppThemeType.midnight]!.accent);
    expect(t.titleFont, 'classic');
    expect(t.cornerScale, 1);
  });

  test('контрастная тема оставляет жёлтый и не берёт своё фото фона', () {
    final t = ThemeConfig.forStyle(const BranchStyle(
      theme: 'highContrast',
      accent: '#2980B9',
      bgUrl: 'http://x/bg.jpg',
    ));
    expect(t.accent, const Color(0xFFFFFF00));
    expect(t.bgImage, '');
  });

  test('фон тем лежит в приложении, а не на чужом сайте', () {
    for (final t in ThemeConfig.palettes.values) {
      expect(t.bgImage.isEmpty || t.bgImage.startsWith('assets/'), isTrue, reason: t.name);
    }
  });

  test('фон: своё фото и однотонный', () {
    expect(ThemeConfig.forStyle(const BranchStyle(bgUrl: 'http://x/bg.jpg')).bgImage,
        'http://x/bg.jpg');
    expect(ThemeConfig.forStyle(const BranchStyle(bgUrl: 'none')).bgImage, '');
  });

  test('надпись на фирменном цвете читается: белая на тёмном, чёрная на светлом', () {
    expect(ThemeConfig.forStyle(const BranchStyle(accent: '#1A237E')).onAccent, Colors.white);
    expect(ThemeConfig.forStyle(const BranchStyle(accent: '#F1C40F')).onAccent, Colors.black);
  });
}
