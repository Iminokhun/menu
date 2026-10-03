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
}
