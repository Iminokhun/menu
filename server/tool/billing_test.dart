// Проверка правил оплаты: статусы на границах и продление срока.
// Запуск: dart run tool/billing_test.dart
import 'dart:io';

import 'package:menu_server/billing.dart';

var failures = 0;

void expect(String what, Object? actual, Object? expected) {
  final ok = actual == expected;
  stdout.writeln(
    '${ok ? 'OK  ' : 'FAIL'} $what${ok ? '' : '  → $actual, ждали $expected'}',
  );
  if (!ok) failures++;
}

void main() {
  final today = DateTime(2026, 10, 18, 15, 30); // время дня не влияет

  Access at(int daysFromToday) => cafeAccess(
    'paid',
    formatDate(DateTime.utc(2026, 10, 18).add(Duration(days: daysFromToday))),
    today,
  ).access;

  expect('8 дней до конца — всё в порядке', at(8), Access.ok);
  expect('7 дней — предупреждение', at(7), Access.ending);
  expect('последний день — ещё оплачено', at(0), Access.ending);
  expect('просрочено на день — льготные дни', at(-1), Access.grace);
  expect('просрочено на 7 дней — ещё льготные', at(-7), Access.grace);
  expect('просрочено на 8 дней — меню выключено', at(-8), Access.expired);
  expect(
    'daysLeft считает дни',
    cafeAccess('paid', '2026-10-21', today).daysLeft,
    3,
  );

  expect(
    'навсегда — без срока',
    cafeAccess('lifetime', '', today).access,
    Access.ok,
  );
  expect(
    'навсегда — даже со старой датой',
    cafeAccess('lifetime', '2020-01-01', today).access,
    Access.ok,
  );
  expect(
    'без срока и не навсегда — выключено',
    cafeAccess('paid', '', today).access,
    Access.expired,
  );
  expect(
    'битая дата — выключено',
    cafeAccess('trial', '2026-02-31', today).access,
    Access.expired,
  );

  expect(
    'месяц от сегодня, если срок прошёл',
    extend('2026-10-01', 1, today),
    '2026-11-18',
  );
  expect(
    'месяц от конца срока, если заплатили заранее',
    extend('2026-10-25', 1, today),
    '2026-11-25',
  );
  expect('год', extend('2026-10-25', 12, today), '2027-10-25');
  expect(
    '31 января + месяц = 28 февраля',
    extend('2027-01-31', 1, today),
    '2027-02-28',
  );
  expect(
    '31 января + месяц в високосный год = 29 февраля',
    extend('2028-01-31', 1, today),
    '2028-02-29',
  );
  expect('через новый год', extend('2026-12-15', 3, today), '2027-03-15');
  expect('без прежнего срока — от сегодня', extend('', 1, today), '2026-11-18');

  expect('дата читается', parseDate('2026-10-18'), DateTime.utc(2026, 10, 18));
  expect('несуществующая дата отклоняется', parseDate('2026-13-01'), null);
  expect('не дата отклоняется', parseDate('завтра'), null);

  stdout.writeln(
    failures == 0 ? '\nВсе проверки прошли' : '\nОшибок: $failures',
  );
  exit(failures == 0 ? 0 : 1);
}
