import 'package:flutter/material.dart';

/// Крупная цифра с подписью. Статистику смотрят не построчно, а одним
/// взглядом: «сколько сегодня» должно быть видно сразу, а не вычитываться
/// из серой строчки наравне с настройками. Виджет один на всю админку —
/// иначе «сегодня» в карточке кафе и «сегодня» в окне разъедутся.
class BigStat extends StatelessWidget {
  /// Само число
  final int value;

  /// Что это за число: «сегодня», «всего», «заведений»
  final String label;

  final Color color;

  /// Высота цифры. Подпись подбирается под неё сама
  final double size;

  const BigStat(
    this.value,
    this.label, {
    this.color = const Color(0xFFD4AF37),
    this.size = 30,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        bigNumber(value),
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w800,
          // Цифра и подпись — одна пара, между ними не должно быть щели
          height: 1.05,
        ),
      ),
      Text(
        label,
        style: TextStyle(
          color: Colors.white54,
          fontSize: size < 24 ? 11 : 12,
        ),
      ),
    ],
  );
}

/// Число тройками: `9412` глазом не отличить от `94120`, а `9 412` —
/// сразу. Разделитель неразрывный: обычным пробелом перенос строки
/// разорвал бы число пополам.
String bigNumber(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(' ');
    out.write(digits[i]);
  }
  return out.toString();
}
