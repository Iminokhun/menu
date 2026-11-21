import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Единые правила адаптива.
///
/// Раньше пороги были разные: 800 на экранах и 650 в карточке товара,
/// из-за чего экран шириной 650–800 получал мобильную сетку с «широким»
/// диалогом товара.
class Responsive {
  /// Минимальная ширина для двухколоночной («широкой») вёрстки.
  static const double wideWidth = 800;

  /// Минимальная высота для неё же. Без этой проверки телефон в альбомной
  /// ориентации (например, 844×390) проходил по ширине и получал вёрстку,
  /// рассчитанную на планшет: сайдбару приветственного экрана нужно ~570 px
  /// высоты, а её там 390.
  static const double wideHeight = 600;

  /// Планшет определяем по короткой стороне — она не меняется при повороте.
  /// 600dp — стандартный порог Android (sw600dp).
  static const double tabletShortestSide = 600;

  /// Широкая вёрстка: хватает и ширины, и высоты.
  static bool isWide(Size size) =>
      size.width > wideWidth && size.height >= wideHeight;

  static bool isWideConstraints(BoxConstraints c) =>
      isWide(Size(c.maxWidth, c.maxHeight));

  /// Планшет/десктоп — устройство, которое имеет смысл держать в альбоме.
  static bool isTablet(Size size) => size.shortestSide >= tabletShortestSide;

  /// Отступ диалога от краёв экрана.
  static double dialogInset(Size screen) => isWide(screen) ? 20.0 : 15.0;

  /// Ширина диалога: желаемая, но не больше экрана.
  ///
  /// Одна формула на всё приложение. Раньше каждый диалог носил своё число
  /// (340, 420, 440, 520) и рассчитывал на монитор: на телефоне форма либо
  /// упиралась в край, либо теряла впустую 80 px на пустые поля по бокам.
  ///
  /// [chrome] — то, что диалог тратит на себя сам. У `AlertDialog` это
  /// `contentPadding` 24 + 24; у голого `Dialog` ничего, и тогда 0.
  static double dialogWidth(Size screen, double preferred, {double chrome = 0}) =>
      math.min(preferred, screen.width - dialogInset(screen) * 2 - chrome);

  /// Отступы `AlertDialog` от краёв экрана: на мониторе — как у Material,
  /// на телефоне — почти во всю ширину, иначе форме остаётся 232 px.
  static EdgeInsets dialogPadding(Size screen) =>
      EdgeInsets.symmetric(horizontal: dialogInset(screen), vertical: 24);
}
