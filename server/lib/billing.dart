/// Оплата меню: тариф кафе и срок, до которого оно оплачено.
///
/// Здесь только расчёты без базы и сети — их удобно проверять тестами
/// (tool/billing_test.dart), а сервер лишь применяет результат.
library;

/// Тарифы. `trial` — пробный период, `paid` — оплачено помесячно или на год,
/// `lifetime` — куплено навсегда, срока нет.
const plans = {'trial', 'paid', 'lifetime'};

/// За сколько дней до конца срока кафе видит предупреждение
const warnDays = 7;

/// Сколько дней после конца срока меню ещё работает
const graceDays = 7;

/// Пробный период нового кафе по умолчанию
const defaultTrialDays = 14;

enum Access {
  /// Оплачено, до конца больше [warnDays] дней, или навсегда
  ok,

  /// До конца срока [warnDays] дней или меньше
  ending,

  /// Срок кончился, но ещё идут льготные дни — меню работает
  grace,

  /// Льготные дни прошли: меню у гостей выключено, админка только для чтения
  expired,
}

class AccessInfo {
  final Access access;

  /// Сколько дней осталось (0 — последний день, меньше 0 — сколько просрочено).
  /// null — срока нет (навсегда).
  final int? daysLeft;

  const AccessInfo(this.access, this.daysLeft);
}

/// Дата без времени: `2026-10-18`.
String formatDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// `2026-10-18` → дата; что угодно другое → null.
DateTime? parseDate(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) return null;
  final d = DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  // 2026-02-31 Dart превратил бы в 3 марта — такую дату не принимаем
  return formatDate(d) == s ? d : null;
}

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Статус оплаты на день [today]. Кафе оплачено по [paidUntil] включительно.
AccessInfo cafeAccess(String plan, String paidUntil, DateTime today) {
  if (plan == 'lifetime') return const AccessInfo(Access.ok, null);
  final until = parseDate(paidUntil);
  // Без срока бывает только «навсегда»; иначе это ошибка данных, и меню
  // лучше выключить, чем раздавать бесплатно незаметно для владельца
  if (until == null) return const AccessInfo(Access.expired, null);

  final left = until.difference(_day(today)).inDays;
  final access = left > warnDays
      ? Access.ok
      : left >= 0
      ? Access.ending
      : left >= -graceDays
      ? Access.grace
      : Access.expired;
  return AccessInfo(access, left);
}

/// Новый срок после оплаты на [months] месяцев. Считается от конца текущего
/// срока, если он ещё не наступил (заплатили заранее — дни не пропадают),
/// иначе от сегодня. 31 января + 1 месяц = 28 (29) февраля.
String extend(String paidUntil, int months, DateTime today) {
  if (months < 1) throw ArgumentError('Месяцев должно быть хотя бы 1');
  final now = _day(today);
  final current = parseDate(paidUntil);
  final from = current != null && current.isAfter(now) ? current : now;

  final y = from.year + (from.month - 1 + months) ~/ 12;
  final m = (from.month - 1 + months) % 12 + 1;
  final lastDay = DateTime.utc(y, m + 1, 0).day;
  final d = from.day > lastDay ? lastDay : from.day;
  return formatDate(DateTime.utc(y, m, d));
}
