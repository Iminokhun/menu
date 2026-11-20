/// Общий отбор по времени для админских списков — заказов и отзывов.
///
/// Лежит отдельно, потому что расчёт границы одинаков для обоих экранов и
/// в нём две ловушки, на которых легко разойтись: часовой пояс и «сегодня
/// и шесть предыдущих».
library;

/// Период отбора. Границу считает экран и присылает серверу готовой:
/// «сегодня» — это сегодня по часам того, кто смотрит, а `created_at`
/// в базе лежит в UTC, и часового пояса кафе сервер не знает.
enum AdminPeriod {
  today('Сегодня', 1),
  week('7 дней', 7),
  month('30 дней', 30),
  all('За всё время', 0);

  const AdminPeriod(this.label, this.days);

  final String label;

  /// Сколько дней захватывает период, считая сегодняшний. 0 — без границы
  final int days;
}

/// Нижняя граница периода в том виде, в каком SQLite пишет `created_at`, —
/// в UTC. `null` — границы нет.
String? sinceFor(AdminPeriod period) {
  if (period.days == 0) return null;
  final now = DateTime.now();
  // Нормализация через конструктор, а не вычитание Duration: второе
  // сдвигает на час на переходе времени. «7 дней» — это сегодня и шесть
  // предыдущих, иначе выборка на сутки шире подписи
  final start = DateTime(
    now.year,
    now.month,
    now.day - (period.days - 1),
  ).toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${start.year}-${two(start.month)}-${two(start.day)} '
      '${two(start.hour)}:${two(start.minute)}:${two(start.second)}';
}
