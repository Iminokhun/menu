import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:menu_server/billing.dart';
import 'package:menu_server/db.dart';
import 'package:menu_server/media.dart';

/// Переносит меню из Supabase в SQLite как одно кафе.
///
/// ```
/// import_supabase <supabaseUrl> <anonKey> "<Название кафе>" <лимит филиалов>
/// ```
///
/// Читает только публичные данные (то же, что видит гость), Supabase не
/// меняет. id филиалов, категорий и товаров сохраняются. Картинки из
/// Supabase Storage скачиваются в `DATA_DIR/uploads/<cafe_id>/`.
/// Логин для кафе потом выдаётся в главной админке.
Future<void> main(List<String> args) async {
  if (args.length < 4) {
    stderr.writeln(
      'Использование: import_supabase <url> <anonKey> "<название>" <лимит>',
    );
    exit(64);
  }
  final [sbUrl, key, cafeName, maxStr, ...] = args;
  final maxBranches = int.parse(maxStr);

  final dataDir = Platform.environment['DATA_DIR'] ?? 'data';
  await Directory(dataDir).create(recursive: true);
  final db = openDb('$dataDir/menu.db');
  final headers = {'apikey': key, 'authorization': 'Bearer $key'};

  Future<List<Map<String, dynamic>>> fetch(String table) async {
    final res = await http.get(
      Uri.parse('$sbUrl/rest/v1/$table?select=*'),
      headers: headers,
    );
    if (res.statusCode != 200) {
      throw 'Не удалось прочитать $table: ${res.statusCode} ${res.body}';
    }
    return (jsonDecode(utf8.decode(res.bodyBytes)) as List)
        .cast<Map<String, dynamic>>();
  }

  final branches = await fetch('branches');
  final categories = await fetch('categories');
  final products = await fetch('products');
  stdout.writeln(
    'Supabase: филиалов ${branches.length}, категорий ${categories.length}, '
    'товаров ${products.length}',
  );

  final cafeId = newId();
  final uploadDir = Directory('$dataDir/uploads/$cafeId');
  await uploadDir.create(recursive: true);

  // Картинка из Storage → локальный файл. Чужие ссылки оставляем как есть.
  final storagePrefix = '$sbUrl/storage/v1/object/public/';
  final copied = <String, String>{};
  Future<String> image(Object? url) async {
    final u = (url as String?) ?? '';
    if (!u.startsWith(storagePrefix)) return u;
    if (copied.containsKey(u)) return copied[u]!;
    final name = Uri.decodeComponent(
      u.split('/').last.split('?').first,
    ).replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final res = await http.get(Uri.parse(u));
    if (res.statusCode != 200) {
      stderr.writeln('  картинка не скачалась (${res.statusCode}): $u');
      return u;
    }
    // Фото сжимаются так же, как при загрузке через админку
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : 'jpg';
    final photo = await compressPhoto(res.bodyBytes, ext);
    final saved = photo == null ? name : '$base.${photo.ext}';
    await File(
      '${uploadDir.path}/$saved',
    ).writeAsBytes(photo?.bytes ?? res.bodyBytes);
    return copied[u] = '/uploads/$cafeId/$saved';
  }

  // Лимит в базе проверяется триггером, поэтому кафе создаём с лимитом не
  // меньше числа переносимых филиалов, а нужный ставим в конце.
  final insertLimit = branches.length > maxBranches
      ? branches.length
      : maxBranches;

  int b(Object? v) => v == false ? 0 : 1;

  // Переводы Supabase (name_en, desc_tr…) — в i18n: {"en": {"name": …}}.
  // [fields]: префикс колонки в Supabase → поле перевода
  String translations(Map<String, dynamic> row, Map<String, String> fields) {
    final i18n = <String, Map<String, String>>{};
    for (final lang in ['en', 'tr']) {
      fields.forEach((prefix, field) {
        final text = ((row['${prefix}_$lang'] as String?) ?? '').trim();
        if (text.isNotEmpty) (i18n[lang] ??= {})[field] = text;
      });
    }
    return jsonEncode(i18n);
  }

  db.execute('begin');
  try {
    // Пробный срок, как у нового кафе из главной админки: без даты меню
    // было бы выключено сразу после переноса. Оплату ставят потом там же
    db.execute(
      "insert into cafes (id, name, max_branches, plan, paid_until) "
      "values (?, ?, ?, 'trial', ?)",
      [
        cafeId,
        cafeName,
        insertLimit,
        formatDate(DateTime.now().add(const Duration(days: defaultTrialDays))),
      ],
    );

    for (final r in branches) {
      db.execute(
        '''
        insert into branches (id, cafe_id, slug, name, slogan, phone, logo_url, qr_url,
                              is_active, sort_order, languages)
        values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          r['id'],
          cafeId,
          r['slug'],
          r['name'] ?? '',
          r['slogan'] ?? '',
          r['phone'] ?? '',
          await image(r['logo_url']),
          r['qr_url'] ?? '',
          b(r['is_active']),
          r['sort_order'] ?? 0,
          // В Supabase у меню было три постоянных языка
          jsonEncode(['ru', 'en', 'tr']),
        ],
      );
    }

    // Родителей вставляем раньше детей: внешний ключ parent_id это требует
    final pending = [...categories];
    final done = <String>{};
    while (pending.isNotEmpty) {
      final ready = pending
          .where((c) => c['parent_id'] == null || done.contains(c['parent_id']))
          .toList();
      if (ready.isEmpty) {
        // Ссылка на несуществующего родителя — переносим как корневую
        for (final c in pending) {
          c['parent_id'] = null;
        }
        continue;
      }
      for (final c in ready) {
        db.execute(
          '''
          insert into categories (id, branch_id, parent_id, name, i18n,
                                  image_url, is_visible, sort_order)
          values (?, ?, ?, ?, ?, ?, ?, ?)''',
          [
            c['id'],
            c['branch_id'],
            c['parent_id'],
            c['name'] ?? '',
            translations(c, {'name': 'name'}),
            await image(c['image_url']),
            b(c['is_visible']),
            c['sort_order'] ?? 0,
          ],
        );
        done.add(c['id'] as String);
        pending.remove(c);
      }
    }

    for (final p in products) {
      db.execute(
        '''
        insert into products (id, branch_id, category_id, name, description, i18n,
                              price, image_url, is_visible, sort_order, portions)
        values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          p['id'],
          p['branch_id'],
          p['category_id'],
          p['name'] ?? '',
          p['description'] ?? '',
          translations(p, {'name': 'name', 'desc': 'description'}),
          (p['price'] as num?)?.toDouble() ?? 0,
          await image(p['image_url']),
          b(p['is_visible']),
          p['sort_order'] ?? 0,
          jsonEncode(p['portions'] ?? []),
        ],
      );
    }

    db.execute('update cafes set max_branches = ? where id = ?', [
      maxBranches,
      cafeId,
    ]);
    db.execute('commit');
  } catch (e) {
    db.execute('rollback');
    stderr.writeln('Ошибка, ничего не перенесено: $e');
    exit(1);
  }

  stdout.writeln(
    'Готово: кафе «$cafeName» (id $cafeId), картинок скачано ${copied.length}',
  );
  stdout.writeln('Выдайте ему логин в главной админке.');
}
