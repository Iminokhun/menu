import 'package:flutter/widgets.dart';

/// Текст, в котором слово никогда не рвётся посередине.
///
/// Обычный [Text] переносит слово, которое не влезает в строку, по
/// буквам: в узкой карточке «ЗАВТРАКИ» становится «ЗАВТРАК» + «И». Здесь
/// шрифт уменьшается ровно настолько, чтобы самое длинное слово
/// поместилось в строку, — переносы остаются только между словами.
/// Короткие названия показываются в полный размер.
class FitWordsText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final int maxLines;

  /// Мельче не уменьшаем: такое слово всё-таки перенесётся, но останется
  /// читаемым
  final double minFontSize;

  const FitWordsText(
    this.text, {
    super.key,
    required this.style,
    this.textAlign = TextAlign.center,
    this.maxLines = 2,
    this.minFontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final base = style.fontSize ?? 14;
        var size = base;
        final width = constraints.maxWidth;
        if (width.isFinite) {
          // Разрядка между буквами с размером шрифта не уменьшается, поэтому
          // одного пропорционального пересчёта мало — уточняем, пока слово
          // не влезет. Обычно хватает двух шагов
          for (var i = 0; i < 6; i++) {
            final widest = _widestWord(context, size);
            if (widest <= width || size <= minFontSize) break;
            // Чуть меньше расчётного: дробные пиксели при отрисовке иначе
            // иногда всё же сбрасывают последнюю букву на новую строку
            size = (size * width / widest * 0.98).clamp(minFontSize, base);
          }
        }
        return Text(
          text,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(fontSize: size),
        );
      },
    );
  }

  /// Ширина самого длинного слова при размере шрифта [size]
  double _widestWord(BuildContext context, double size) {
    final scaler = MediaQuery.textScalerOf(context);
    final sized = style.copyWith(fontSize: size);
    var widest = 0.0;
    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(text: word, style: sized),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    return widest;
  }
}
