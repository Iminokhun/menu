import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Карточка слегка «проседает» под пальцем — понятно, что нажатие
/// засчитано, ещё до перехода на следующий экран.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  /// Насколько уменьшается под пальцем. Для больших карточек хватает 0.97:
  /// сильнее — и сетка заметно «дёргается».
  final double pressedScale;

  const Pressable({super.key, required this.child, this.onTap, this.pressedScale = 0.97});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    // «Уменьшить движение» в настройках телефона — без анимации
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _down && !still ? widget.pressedScale : 1,
        duration: Duration(milliseconds: _down ? 90 : 160),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Мягкое появление элемента сетки: из прозрачности и чуть снизу. Соседние
/// карточки появляются с небольшой задержкой друг за другом — сетка
/// «складывается», а не возникает рывком.
class FadeSlideIn extends StatelessWidget {
  final Widget child;
  final int index;

  const FadeSlideIn({super.key, required this.child, this.index = 0});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    // Задержка растёт только для первых карточек: дальние появляются сразу,
    // иначе длинное меню «проявлялось» бы секунду
    final delay = math.min(index, 8) * 35;
    final total = 260 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 12), child: child),
      ),
      child: child,
    );
  }
}
