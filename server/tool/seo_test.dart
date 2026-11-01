// Проверка страниц для поисковиков без сервера: экранирование, меню,
// sitemap. Запуск: dart run tool/seo_test.dart
import 'dart:io';

import 'package:menu_server/seo.dart';

var failures = 0;

void expect(String what, bool ok, [Object? info]) {
  stdout.writeln('${ok ? 'OK  ' : 'FAIL'} $what${ok ? '' : '  → $info'}');
  if (!ok) failures++;
}

void main() {
  const base = 'https://menu.example.kg';
  final cafe = <String, Object?>{
    'name': 'Андалус',
    'description': 'Восточная кухня',
    'cover_url': '',
  };
  final branch = <String, Object?>{
    'slug': 'andalus',
    'name': 'Андалус',
    'address': 'ул. Киевская 95',
    'hours': '10:00–23:00',
    'phone': '+996 555 12-34-56',
    'map_url': 'https://2gis.kg/x',
    'logo_url': '',
  };
  final page = branchPage(
    base: base,
    cafe: cafe,
    branch: branch,
    categories: [
      {'id': 'c1', 'name': 'Завтраки', 'parent_id': null},
      {'id': 'c2', 'name': 'Каши', 'parent_id': 'c1'},
      {'id': 'c3', 'name': 'Пустая', 'parent_id': null},
    ],
    products: [
      {
        'name': '<script>alert(1)</script>',
        'description': 'вкусно & сытно',
        'price': 250.0,
        'category_id': 'c1',
        'portions': [],
      },
      {
        'name': 'Овсянка </script><b>',
        'description': '',
        'price': 180.0,
        'category_id': 'c2',
        'portions': [
          {'name': 'Большая', 'price': 240.0},
        ],
      },
    ],
  );

  expect(
    'название блюда экранировано, скрипт не попадает в страницу',
    !page.contains('<script>alert') && page.contains('&lt;script&gt;'),
  );
  expect(
    '</script> в названии не закрывает разметку schema.org',
    !page.contains('Овсянка </script>') &&
        page.contains('Овсянка ${r'\u' '003c'}/script>'),
  );
  expect('цена без нулей и с порцией', page.contains('180 сом, Большая — 240 сом'));
  expect(
    'подкатегория идёт сразу за своим разделом',
    page.indexOf('Завтраки') < page.indexOf('Каши'),
  );
  expect('пустой раздел не показывается', !page.contains('Пустая'));
  expect('кнопка ведёт в настоящее меню', page.contains('href="/?branch=andalus"'));
  expect(
    'адрес, часы и телефон на странице',
    page.contains('ул. Киевская 95') &&
        page.contains('10:00–23:00') &&
        page.contains('href="tel:+996555123456"'),
  );
  expect(
    'канонический адрес страницы',
    page.contains('<link rel="canonical" href="$base/kafe/andalus">'),
  );

  final catalog = catalogPage(
    base: base,
    cafes: [
      {...cafe, 'branches': [branch]},
    ],
  );
  expect('каталог: ссылка на страницу филиала', catalog.contains('href="/kafe/andalus"'));
  expect(
    'каталог: адрес рядом со ссылкой',
    catalog.contains('ул. Киевская 95 · 10:00–23:00'),
  );

  final map = sitemap(base, ['andalus', 'a&b']);
  expect(
    'sitemap: главная, каталог и филиалы, амперсанд экранирован',
    map.contains('<loc>$base/</loc>') &&
        map.contains('<loc>$base/kafe</loc>') &&
        map.contains('<loc>$base/kafe/andalus</loc>') &&
        !map.contains('a&b'),
  );
  expect(
    'robots.txt: sitemap и закрытые API и админка',
    robots(base).contains('Sitemap: $base/sitemap.xml') &&
        robots(base).contains('Disallow: /menu-kg/'),
  );
  expect('страница-заглушка не индексируется', notFoundPage(base).contains('noindex'));
  expect(
    'пути поисковиков отделены от сайта Flutter',
    isSeoPath('kafe') &&
        isSeoPath('kafe/andalus') &&
        isSeoPath('sitemap.xml') &&
        !isSeoPath('') &&
        !isSeoPath('kafeteria'),
  );

  stdout.writeln(failures == 0 ? '\nВсе проверки прошли' : '\nОшибок: $failures');
  exit(failures == 0 ? 0 : 1);
}
