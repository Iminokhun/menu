import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Пять звёзд: оценка гостя в форме отзыва и она же, только для чтения,
/// в карточке отзыва у кафе.
///
/// `onChanged == null` — режим показа: нажатия ничего не меняют.
class StarRating extends StatelessWidget {
  /// Сколько звёзд закрашено. 0 — гость ещё не выбрал.
  final int value;

  /// Нажатие по N-й звезде отдаёт N. Null — только показ.
  final ValueChanged<int>? onChanged;

  final Color color;

  /// Размер самой звезды. Поле нажатия всегда не меньше 44×44 — пальцем
  /// по звезде в 20 пикселей иначе не попасть
  final double size;

  const StarRating({
    super.key,
    required this.value,
    this.onChanged,
    required this.color,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    final tap = onChanged;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Semantics(
            button: tap != null,
            label: 'Оценка $i из 5',
            selected: value == i,
            child: InkResponse(
              onTap: tap == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      tap(i);
                    },
              radius: size * 0.7,
              child: Padding(
                padding: EdgeInsets.all(tap == null ? 1 : (44 - size) / 2),
                child: Icon(
                  i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: size,
                  // Непоставленные звёзды бледнее, но видны: иначе непонятно,
                  // что их можно нажать
                  color: i <= value ? color : color.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
