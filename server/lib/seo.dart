import 'dart:convert';

/// Страницы для поисковиков: каталог кафе и меню филиала обычным HTML.
///
/// Сайт меню — Flutter: он рисует всё на холсте, и Google видит пустую
/// страницу. Здесь те же данные отдаются простым текстом — названия кафе,
/// адреса, блюда с ценами, — чтобы кафе находили по запросам вроде
/// «меню Андалус Бишкек». Гость с такой страницы одной кнопкой попадает
/// в настоящее меню (`/?branch=...`).
///
/// Показываются только кафе из каталога на главной: в поиск попадает
/// лишь то, что кафе и так показывает всем.

/// Пути, которые отдаёт сервер, а не сайт Flutter (см. bin/server.dart)
bool isSeoPath(String path) =>
    path == 'kafe' ||
    path.startsWith('kafe/') ||
    path == 'sitemap.xml' ||
    path == 'robots.txt';

const _siteName = 'menu.kg';

// Как стандартный, но без «/» → «&#47;»: адреса в ссылках остаются чистыми
const _html = HtmlEscape(
  HtmlEscapeMode(escapeLtGt: true, escapeQuot: true, escapeApos: true),
);

String _e(Object? v) => _html.convert('${v ?? ''}');

String _str(Map m, String key) => (m[key] as String?) ?? '';

/// Адрес страницы филиала
String branchPagePath(String slug) => '/kafe/${Uri.encodeComponent(slug)}';

/// Цена без лишних нулей: 350.0 → «350»
String _price(Object? v) {
  final n = (v as num?) ?? 0;
  return n == n.truncateToDouble() ? '${n.toInt()}' : n.toStringAsFixed(2);
}

String catalogPage({
  required String base,
  required List<Map<String, Object?>> cafes,
}) {
  final items = StringBuffer();
  for (final cafe in cafes) {
    final branches = (cafe['branches'] as List).cast<Map<String, Object?>>();
    items.write('<li class="cafe">');
    items.write('<h2>${_e(cafe['name'])}</h2>');
    final desc = _str(cafe, 'description');
    if (desc.isNotEmpty) items.write('<p>${_e(desc)}</p>');
    items.write('<ul>');
    for (final b in branches) {
      final place = [
        _str(b, 'address'),
        _str(b, 'hours'),
      ].where((s) => s.isNotEmpty).join(' · ');
      items.write(
        '<li><a href="${_e(branchPagePath(_str(b, 'slug')))}">'
        '${_e(_branchTitle(cafe, b))}</a>'
        '${place.isEmpty ? '' : ' — ${_e(place)}'}</li>',
      );
    }
    items.write('</ul></li>');
  }
  return _page(
    base: base,
    path: '/kafe',
    title: 'Меню кафе и ресторанов — $_siteName',
    description:
        'Меню кафе и ресторанов: блюда, цены, адреса и часы работы. '
        '${cafes.map((c) => c['name']).take(8).join(', ')}',
    body:
        '<h1>Меню кафе и ресторанов</h1>'
        '<p><a class="btn" href="/">Открыть $_siteName</a></p>'
        '${cafes.isEmpty ? '<p>Здесь пока нет кафе.</p>' : '<ul class="cafes">$items</ul>'}',
  );
}

/// «Андалус — Монте»; если филиал назван как кафе — просто «Андалус»
String _branchTitle(Map cafe, Map branch) {
  final c = _str(cafe, 'name');
  final b = _str(branch, 'name');
  return b.isEmpty || b == c ? c : '$c — $b';
}

String branchPage({
  required String base,
  required Map<String, Object?> cafe,
  required Map<String, Object?> branch,
  required List<Map<String, Object?>> categories,
  required List<Map<String, Object?>> products,
}) {
  final title = _branchTitle(cafe, branch);
  final slug = _str(branch, 'slug');
  final menuLink = '/?branch=${Uri.encodeQueryComponent(slug)}';
  final address = _str(branch, 'address');
  final hours = _str(branch, 'hours');
  final phone = _str(branch, 'phone');
  final mapUrl = _str(branch, 'map_url');

  // Подкатегории идут сразу за своим разделом — как в меню у гостя
  final ordered = <Map<String, Object?>>[];
  final roots = categories.where((c) => c['parent_id'] == null).toList();
  for (final root in roots) {
    ordered.add(root);
    ordered.addAll(categories.where((c) => c['parent_id'] == root['id']));
  }
  final known = ordered.map((c) => c['id']).toSet();
  ordered.addAll(categories.where((c) => !known.contains(c['id'])));

  final menu = StringBuffer();
  final sections = <Map<String, Object?>>[];
  for (final cat in ordered) {
    final dishes = products.where((p) => p['category_id'] == cat['id']).toList();
    if (dishes.isEmpty) continue;
    menu.write('<section><h2>${_e(cat['name'])}</h2><ul class="dishes">');
    for (final p in dishes) {
      final portions = (p['portions'] as List?) ?? const [];
      final prices = portions.isEmpty
          ? '${_price(p['price'])} сом'
          : [
              '${_price(p['price'])} сом',
              for (final x in portions)
                '${(x as Map)['name']} — ${_price(x['price'])} сом',
            ].join(', ');
      final desc = _str(p, 'description');
      menu.write(
        '<li><span class="dish">${_e(p['name'])}</span>'
        '<span class="price">${_e(prices)}</span>'
        '${desc.isEmpty ? '' : '<p>${_e(desc)}</p>'}</li>',
      );
    }
    menu.write('</ul></section>');
    sections.add({
      '@type': 'MenuSection',
      'name': cat['name'],
      'hasMenuItem': [
        for (final p in dishes)
          {
            '@type': 'MenuItem',
            'name': p['name'],
            if (_str(p, 'description').isNotEmpty)
              'description': p['description'],
            'offers': {
              '@type': 'Offer',
              'price': _price(p['price']),
              'priceCurrency': 'KGS',
            },
          },
      ],
    });
  }

  // Разметка schema.org: поисковик понимает, что это ресторан с меню
  final ld = {
    '@context': 'https://schema.org',
    '@type': 'Restaurant',
    'name': title,
    'url': '$base${branchPagePath(slug)}',
    if (_str(branch, 'logo_url').isNotEmpty) 'image': branch['logo_url'],
    if (phone.isNotEmpty) 'telephone': phone,
    if (address.isNotEmpty)
      'address': {
        '@type': 'PostalAddress',
        'streetAddress': address,
        'addressCountry': 'KG',
      },
    if (mapUrl.isNotEmpty) 'hasMap': mapUrl,
    'hasMenu': {'@type': 'Menu', 'hasMenuSection': sections},
  };

  final info = StringBuffer();
  if (address.isNotEmpty) info.write('<li>Адрес: ${_e(address)}</li>');
  if (hours.isNotEmpty) info.write('<li>Часы работы: ${_e(hours)}</li>');
  if (phone.isNotEmpty) {
    info.write(
      '<li>Телефон: <a href="tel:${_e(phone.replaceAll(RegExp(r'[^\d+]'), ''))}">'
      '${_e(phone)}</a></li>',
    );
  }
  if (mapUrl.isNotEmpty) {
    info.write(
      '<li><a href="${_e(mapUrl)}" rel="noopener nofollow" target="_blank">'
      'Как добраться</a></li>',
    );
  }

  final desc = _str(cafe, 'description');
  return _page(
    base: base,
    path: branchPagePath(slug),
    title: 'Меню $title${address.isEmpty ? '' : ', $address'} — цены | $_siteName',
    description: [
      'Меню и цены $title.',
      if (desc.isNotEmpty) desc,
      if (address.isNotEmpty) 'Адрес: $address.',
      if (hours.isNotEmpty) 'Часы работы: $hours.',
    ].join(' '),
    image: _str(cafe, 'cover_url').isNotEmpty
        ? _str(cafe, 'cover_url')
        : _str(branch, 'logo_url'),
    jsonLd: jsonEncode(ld),
    body:
        '<p class="crumbs"><a href="/kafe">Все кафе</a></p>'
        '<h1>Меню ${_e(title)}</h1>'
        '${desc.isEmpty ? '' : '<p>${_e(desc)}</p>'}'
        '${info.isEmpty ? '' : '<ul class="info">$info</ul>'}'
        '<p><a class="btn" href="${_e(menuLink)}">Открыть меню с фото</a></p>'
        '${menu.isEmpty ? '<p>Меню скоро появится.</p>' : '$menu'}',
  );
}

String notFoundPage(String base) => _page(
  base: base,
  path: '/kafe',
  title: 'Кафе не найдено — $_siteName',
  description: 'Такого кафе нет в каталоге $_siteName.',
  noindex: true,
  body:
      '<h1>Кафе не найдено</h1>'
      '<p><a class="btn" href="/kafe">Все кафе</a></p>',
);

String sitemap(String base, Iterable<String> slugs) {
  final urls = ['/', '/kafe', for (final s in slugs) branchPagePath(s)];
  return '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
      '${urls.map((u) => '  <url><loc>${_e('$base$u')}</loc></url>\n').join()}'
      '</urlset>\n';
}

String robots(String base) =>
    'User-agent: *\n'
    'Allow: /\n'
    'Disallow: /api/\n'
    'Disallow: /menu-kg/\n'
    '\n'
    'Sitemap: $base/sitemap.xml\n';

/// JSON внутри <script>: каждый «<» записывается юникод-кодом — тогда
/// название блюда вроде «</script>» не закроет тег раньше времени
String _safeJson(String json) => json.replaceAll('<', _ltEscape);

/// Юникод-код «<» для JSON. Собран из двух частей: целиком такую запись
/// некоторые инструменты при правке превращают обратно в «<»
const _ltEscape = r'\u' '003c';

String _page({
  required String base,
  required String path,
  required String title,
  required String description,
  required String body,
  String image = '',
  String? jsonLd,
  bool noindex = false,
}) {
  final canonical = '$base$path';
  return '''<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_e(title)}</title>
<meta name="description" content="${_e(description)}">
${noindex ? '<meta name="robots" content="noindex">' : '<link rel="canonical" href="${_e(canonical)}">'}
<meta property="og:type" content="website">
<meta property="og:site_name" content="$_siteName">
<meta property="og:title" content="${_e(title)}">
<meta property="og:description" content="${_e(description)}">
<meta property="og:url" content="${_e(canonical)}">
${image.isEmpty ? '' : '<meta property="og:image" content="${_e(image)}">'}
<link rel="icon" type="image/png" href="/favicon.png">
${jsonLd == null ? '' : '<script type="application/ld+json">${_safeJson(jsonLd)}</script>'}
<style>
:root{--bg:#141414;--surface:#1f1f1f;--text:#f4efe6;--muted:#a59f95;--accent:#d9573a}
@media (prefers-color-scheme: light){:root{--bg:#faf7f2;--surface:#fff;--text:#1c1c1c;--muted:#6b665e}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:16px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;-webkit-font-smoothing:antialiased}
main{max-width:720px;margin:0 auto;padding:24px 16px 48px}
a{color:var(--accent)}
h1{font-size:28px;line-height:1.2;margin:8px 0 12px;text-wrap:balance}
h2{font-size:20px;margin:28px 0 8px}
p{text-wrap:pretty}
.btn{display:inline-block;background:var(--accent);color:#fff;text-decoration:none;font-weight:700;padding:12px 20px;border-radius:12px}
.crumbs{margin:0;font-size:14px}
ul{padding:0;list-style:none}
.info li{margin:4px 0;color:var(--muted)}
.cafe{background:var(--surface);border-radius:16px;padding:4px 16px 8px;margin:12px 0}
.cafe li{margin:6px 0}
.dishes li{display:grid;grid-template-columns:1fr auto;gap:2px 12px;padding:10px 0;border-bottom:1px solid color-mix(in srgb,var(--text) 10%,transparent)}
.dishes p{grid-column:1/-1;margin:0;color:var(--muted);font-size:14px}
.price{font-weight:700;font-variant-numeric:tabular-nums;white-space:nowrap}
footer{color:var(--muted);font-size:13px;margin-top:40px}
</style>
</head>
<body>
<main>
$body
<footer><a href="/">$_siteName</a> — меню кафе и ресторанов</footer>
</main>
</body>
</html>
''';
}
