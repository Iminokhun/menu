import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

import 'auth.dart';
import 'billing.dart';
import 'db.dart';
import 'languages.dart';
import 'media.dart';
import 'security.dart';
import 'slug.dart';

/// Ошибка, которую клиент увидит как `{"error": message}` с кодом [status].
/// [code] — машинная метка для приложения, например `unpaid`.
class ApiError implements Exception {
  final int status;
  final String message;
  final String? code;
  ApiError(this.status, this.message, {this.code});
}

/// Поля, которые клиенту разрешено писать. Всё остальное (id, cafe_id,
/// branch_id у существующих строк) из запроса молча отбрасывается —
/// так кафе не переложит свой товар в чужой филиал подменой поля.
const _branchFields = {
  'slug',
  'name',
  'slogan',
  'phone',
  'logo_url',
  'qr_url',
  'is_active',
  'sort_order',
  'languages',
  ...styleColumns,
};
const _categoryFields = {
  'parent_id',
  'name',
  'i18n',
  'image_url',
  'is_visible',
  'sort_order',
};
const _productFields = {
  'category_id',
  'name',
  'description',
  'i18n',
  'price',
  'image_url',
  'model_url',
  'is_visible',
  'sort_order',
  'portions',
};

/// Поля, которые в базе лежат JSON-текстом, а наружу отдаются как есть.
const _jsonFields = {'portions', 'languages', 'i18n'};

/// Поля с адресами файлов: в базе хранится путь `/uploads/...`,
/// наружу отдаётся полный адрес. Так база не привязана к домену сервера.
const _urlFields = {'image_url', 'logo_url', 'model_url', 'bg_url'};

/// Допустимые значения оформления. Пустая строка — «как по умолчанию».
/// Список совпадает с вариантами в приложении (lib/models/branch.dart).
const _styleChoices = {
  'theme': {
    '',
    'midnight',
    'porcelain',
    'royal',
    'sea',
    'sakura',
    'highContrast',
  },
  'card_size': {'', 'small', 'normal', 'large'},
  'corners': {'', 'sharp', 'soft', 'round'},
  'title_font': {'', 'classic', 'montserrat', 'playfair', 'oswald', 'lora'},
};
final _hexColor = RegExp(r'^#[0-9a-fA-F]{6}$');

const _imageExts = {'jpg', 'jpeg', 'png', 'webp', 'gif'};
const _maxUploadBytes = 10 * 1024 * 1024;

/// 3D-модели блюд (.glb) тяжелее фото — им свой лимит
const _modelExts = {'glb'};
const _maxModelBytes = 25 * 1024 * 1024;

class Api {
  final Database db;
  final String uploadsDir;

  /// Внешний адрес сервера, например `https://menu.example.com`.
  /// Если не задан — берётся из заголовков запроса.
  final String? publicUrl;

  /// Адрес сайта с меню для гостей — из него собираются ссылки QR-кодов.
  /// Если не задан — меню считается на том же адресе, что и сервер.
  final String? menuUrl;

  /// Кому и как платить — показывается кафе в админке, когда срок
  /// подходит к концу (`BILLING_CONTACT`, например телефон или WhatsApp)
  final String billingContact;

  Api(
    this.db, {
    required this.uploadsDir,
    this.publicUrl,
    this.menuUrl,
    this.billingContact = '',
    this.uploadQuotaBytes = 2 * 1024 * 1024 * 1024,
    UploadLimiter? uploadLimiter,
  }) : _uploads = uploadLimiter ?? UploadLimiter();

  /// Сколько места на диске может занять одно кафе (фото и 3D-модели)
  final int uploadQuotaBytes;

  /// Сколько загрузок подряд разрешено одному кафе
  final UploadLimiter _uploads;

  /// Сегодня — отдельным методом, чтобы все проверки оплаты брали одну дату
  DateTime _today() => DateTime.now();

  AccessInfo _access(String cafeId) {
    final rows = db.select('select plan, paid_until from cafes where id = ?', [
      cafeId,
    ]);
    if (rows.isEmpty) return const AccessInfo(Access.expired, null);
    final r = rows.first;
    return cafeAccess(r['plan'] as String, r['paid_until'] as String, _today());
  }

  static const _unpaidGuest = 'Меню временно недоступно';

  /// Неудачные входы по логину: защита от подбора пароля.
  final _failedLogins = <String, List<DateTime>>{};

  final _startedAt = DateTime.now();

  late final Router router = _buildRouter();

  Router _buildRouter() {
    final r = Router();

    // ---------- Проверка, что сервер жив ----------
    r.get('/api/health', _health);

    // ---------- Гость ----------
    r.get('/api/public/branch/<slug>', _publicBranch);
    r.get('/api/public/menu/<branchId>', _publicMenu);

    // ---------- Вход ----------
    r.post('/api/auth/login', _login);
    r.post('/api/auth/logout', _logout);
    r.get('/api/me', _me);

    // ---------- Админ кафе ----------
    r.get('/api/admin/branches', _listBranches);
    r.post('/api/admin/branches', _createBranch);
    r.patch('/api/admin/branches/<id>', _updateBranch);
    r.delete('/api/admin/branches/<id>', _deleteBranch);
    r.patch('/api/admin/style', _updateStyleAll);

    r.get('/api/admin/categories', _listCategories);
    r.post('/api/admin/categories', _createCategory);
    r.patch('/api/admin/categories/<id>', _updateCategory);
    r.delete('/api/admin/categories/<id>', _deleteCategory);

    r.get('/api/admin/products', _listProducts);
    r.post('/api/admin/products', _createProduct);
    r.patch('/api/admin/products/<id>', _updateProduct);
    r.delete('/api/admin/products/<id>', _deleteProduct);

    r.post('/api/admin/upload', _upload);

    // ---------- Superadmin ----------
    r.get('/api/super/cafes', _listCafes);
    r.post('/api/super/cafes', _createCafe);
    r.patch('/api/super/cafes/<id>', _updateCafe);
    r.delete('/api/super/cafes/<id>', _deleteCafe);
    r.post('/api/super/cafes/<id>/users', _createCafeUser);
    r.get('/api/super/cafes/<id>/payments', _listPayments);
    r.post('/api/super/cafes/<id>/payments', _addPayment);
    r.patch('/api/super/users/<id>', _updateUser);
    r.delete('/api/super/users/<id>', _deleteUser);

    return r;
  }

  // ======================================================================
  //  Общее
  // ======================================================================

  String _base(Request req) {
    if (publicUrl != null && publicUrl!.isNotEmpty) return publicUrl!;
    final proto = req.headers['x-forwarded-proto'] ?? req.requestedUri.scheme;
    final host =
        req.headers['x-forwarded-host'] ?? req.headers['host'] ?? 'localhost';
    return '$proto://$host';
  }

  String _menuBase(Request req) {
    final m = menuUrl;
    final base = m != null && m.isNotEmpty ? m : _base(req);
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  /// Ссылка, которую зашивают в QR-код филиала.
  String _qrLink(Request req, String slug) =>
      '${_menuBase(req)}/?branch=${Uri.encodeQueryComponent(slug)}';

  /// Адрес филиала, введённый руками: большие буквы приводим к маленьким,
  /// всё остальное недопустимое — отказ, а не молчаливая правка.
  String _checkSlug(String raw) {
    final slug = raw.toLowerCase();
    if (!isValidSlug(slug)) {
      throw ApiError(
        400,
        'Адрес может содержать только латинские буквы, цифры и дефис, '
        'например centr-2',
      );
    }
    return slug;
  }

  /// Свободный адрес филиала: `bishkek-kofe`, а если занят — `bishkek-kofe-2`…
  String _uniqueSlug(String wanted) {
    final base = wanted.isEmpty ? 'menu' : wanted;
    var slug = base;
    for (
      var i = 2;
      db.select('select 1 from branches where slug = ?', [slug]).isNotEmpty;
      i++
    ) {
      slug = '$base-$i';
    }
    return slug;
  }

  Map<String, Object?> _out(Request req, Row row) {
    final m = rowToJson(row);
    for (final f in _urlFields) {
      final v = m[f];
      if (v is String && v.startsWith('/uploads/')) m[f] = '${_base(req)}$v';
    }
    // У филиала без сохранённой ссылки QR она собирается из адреса меню
    if (m.containsKey('qr_url') &&
        m['slug'] is String &&
        (m['qr_url'] ?? '') == '') {
      m['qr_url'] = _qrLink(req, m['slug'] as String);
    }
    for (final f in _jsonFields) {
      if (m[f] is String) m[f] = jsonDecode(m[f] as String);
    }
    return m;
  }

  List<Map<String, Object?>> _outAll(Request req, ResultSet rows) =>
      rows.map((r) => _out(req, r)).toList();

  /// Адрес своей же картинки превращаем обратно в путь `/uploads/...`.
  Object? _in(Request req, String field, Object? v) {
    if (_urlFields.contains(field) && v is String) {
      final i = v.indexOf('/uploads/');
      if (i >= 0 && v.startsWith(_base(req))) return v.substring(i);
      return v;
    }
    if (_jsonFields.contains(field)) return jsonEncode(v);
    return toSql(v);
  }

  Future<Map<String, dynamic>> _body(Request req) async {
    try {
      final text = await req.readAsString(utf8);
      if (text.isEmpty) return {};
      final v = jsonDecode(text);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    throw ApiError(400, 'Некорректный JSON');
  }

  AuthUser _user(Request req) {
    final h = req.headers['authorization'] ?? '';
    if (!h.startsWith('Bearer ')) throw ApiError(401, 'Требуется вход');
    final u = userByToken(db, h.substring(7));
    if (u == null) throw ApiError(401, 'Сессия истекла, войдите заново');
    return u;
  }

  AuthUser _cafeAdmin(Request req) {
    final u = _user(req);
    if (u.cafeId == null) throw ApiError(403, 'Только для администратора кафе');
    // Оплата просрочена: смотреть можно, менять нельзя. Через эту проверку
    // проходит каждый запрос админки кафе, поэтому обойти её нечем
    if (req.method != 'GET' && _access(u.cafeId!).access == Access.expired) {
      final how = billingContact.isEmpty
          ? ''
          : ' Для продления: $billingContact';
      throw ApiError(
        403,
        'Оплата просрочена — меню и изменения выключены.$how',
        code: 'unpaid',
      );
    }
    return u;
  }

  AuthUser _superadmin(Request req) {
    final u = _user(req);
    if (!u.isSuper) throw ApiError(403, 'Только для главного администратора');
    return u;
  }

  /// Филиал, если он принадлежит кафе пользователя. Чужой филиал для
  /// пользователя «не существует» — 404, а не 403, чтобы по ответам
  /// нельзя было перебирать id чужих филиалов.
  Row _ownBranch(AuthUser u, String? branchId) {
    if (branchId == null || branchId.isEmpty) {
      throw ApiError(400, 'Не указан филиал');
    }
    final rows = db.select(
      'select * from branches where id = ? and cafe_id = ?',
      [branchId, u.cafeId],
    );
    if (rows.isEmpty) throw ApiError(404, 'Филиал не найден');
    return rows.first;
  }

  /// Строка categories/products, если её филиал принадлежит кафе пользователя.
  Row _ownRow(AuthUser u, String table, String id) {
    final rows = db.select(
      '''
      select t.* from $table t
        join branches b on b.id = t.branch_id
       where t.id = ? and b.cafe_id = ?''',
      [id, u.cafeId],
    );
    if (rows.isEmpty) throw ApiError(404, 'Запись не найдена');
    return rows.first;
  }

  /// Категория должна быть из того же филиала, что и запись, которая на неё
  /// ссылается. Иначе товар одного кафе можно было бы повесить в чужое меню.
  void _checkCategory(String? categoryId, String branchId, {String? selfId}) {
    if (categoryId == null || categoryId.isEmpty) return;
    if (categoryId == selfId) {
      throw ApiError(400, 'Категория не может быть своим родителем');
    }
    final rows = db.select(
      'select 1 from categories where id = ? and branch_id = ?',
      [categoryId, branchId],
    );
    if (rows.isEmpty) throw ApiError(400, 'Категория не из этого филиала');
  }

  /// Подкатегории — один уровень, как их показывает меню гостя: родитель
  /// должен быть основной категорией, а категория с подкатегориями сама
  /// подкатегорией стать не может.
  void _checkParent(String? parentId, String branchId, {String? selfId}) {
    _checkCategory(parentId, branchId, selfId: selfId);
    if (parentId == null || parentId.isEmpty) return;
    final parent = db.select('select parent_id from categories where id = ?', [
      parentId,
    ]).first;
    if (parent['parent_id'] != null) {
      throw ApiError(
        400,
        'Подкатегорию можно добавить только в основную категорию',
      );
    }
    if (selfId != null &&
        db.select('select 1 from categories where parent_id = ?', [
          selfId,
        ]).isNotEmpty) {
      throw ApiError(
        400,
        'У категории есть подкатегории — сначала перенесите или удалите их',
      );
    }
  }

  Map<String, Object?> _pick(
    Request req,
    Map<String, dynamic> body,
    Set<String> allowed,
  ) {
    final m = <String, Object?>{};
    for (final e in body.entries) {
      if (allowed.contains(e.key)) {
        m[e.key] = _in(req, e.key, _valid(e.key, e.value));
      }
    }
    return m;
  }

  /// Значение поля нужного типа — или 400. SQLite сохранит что угодно
  /// (текст в колонке цены, дробь в порядке), а приложение потом не сможет
  /// прочитать такую строку, и меню гостя сломается целиком.
  Object? _valid(String field, Object? v) {
    switch (field) {
      case 'theme' || 'card_size' || 'corners' || 'title_font':
        if (v is String && _styleChoices[field]!.contains(v)) return v;
      case 'accent':
        if (v is String && (v.isEmpty || _hexColor.hasMatch(v))) {
          return v.toUpperCase();
        }
      case 'parent_id' || 'category_id':
        // Пустая строка из формы — «без категории», а не ссылка на id ''
        if (v == null || v == '') return null;
        if (v is String) return v;
      case 'sort_order':
        if (v is int) return v;
        if (v is double && v.isFinite && v == v.truncateToDouble()) {
          return v.toInt();
        }
        throw ApiError(400, 'Порядок должен быть целым числом');
      case 'price':
        if (v is num && v.isFinite && v >= 0) return v.toDouble();
        throw ApiError(400, 'Цена должна быть числом не меньше 0');
      case 'is_active' || 'is_visible':
        if (v is bool) return v;
      case 'languages':
        if (v is List &&
            v.isNotEmpty &&
            v.every(menuLanguages.contains) &&
            v.toSet().length == v.length) {
          return List<String>.from(v);
        }
        throw ApiError(
          400,
          'Языки: хотя бы один, без повторов, из списка ${menuLanguages.join(', ')}',
        );
      case 'i18n':
        return _validI18n(v);
      case 'portions':
        if (v == null) return const [];
        if (v is List && v.every(_validPortion)) {
          return [
            for (final p in v)
              {
                'name': (p as Map)['name'],
                'price': (p['price'] as num).toDouble(),
              },
          ];
        }
        throw ApiError(
          400,
          'Порции: у каждой нужны название и цена не меньше 0',
        );
      default:
        if (v is String) return v;
    }
    throw ApiError(400, 'Неверное значение поля «$field»');
  }

  /// Переводы `{"en": {"name": "...", "description": "..."}}`: только
  /// известные языки и поля, пустые строки отбрасываются.
  static Map<String, Map<String, String>> _validI18n(Object? v) {
    if (v == null) return const {};
    const error = 'Переводы: {"язык": {"name": "...", "description": "..."}}';
    if (v is! Map) throw ApiError(400, error);
    final out = <String, Map<String, String>>{};
    for (final MapEntry(:key, :value) in v.entries) {
      if (!menuLanguages.contains(key) || value is! Map) {
        throw ApiError(400, error);
      }
      final texts = <String, String>{};
      for (final MapEntry(key: field, value: text) in value.entries) {
        if (!translatableFields.contains(field) || text is! String) {
          throw ApiError(400, error);
        }
        if (text.trim().isNotEmpty) texts[field as String] = text.trim();
      }
      if (texts.isNotEmpty) out[key as String] = texts;
    }
    return out;
  }

  static bool _validPortion(Object? p) {
    if (p is! Map) return false;
    final price = p['price'];
    return p['name'] is String && price is num && price.isFinite && price >= 0;
  }

  void _insert(String table, Map<String, Object?> data) {
    final cols = data.keys.join(', ');
    final qs = List.filled(data.length, '?').join(', ');
    db.execute('insert into $table ($cols) values ($qs)', data.values.toList());
  }

  void _update(String table, String id, Map<String, Object?> data) {
    if (data.isEmpty) return;
    final set = data.keys.map((k) => '$k = ?').join(', ');
    db.execute('update $table set $set where id = ?', [...data.values, id]);
  }

  /// Ошибки уникальности и лимита из SQLite — понятным текстом.
  Never _sqlError(SqliteException e, {String? slug}) {
    final msg = e.message;
    if (msg.contains('BRANCH_LIMIT')) {
      throw ApiError(403, 'Достигнут лимит филиалов по вашему тарифу');
    }
    if (msg.contains('UNIQUE') && msg.contains('branches.slug')) {
      throw ApiError(409, 'Адрес «${slug ?? ''}» уже занят, выберите другой');
    }
    if (msg.contains('UNIQUE') && msg.contains('users.login')) {
      throw ApiError(409, 'Такой логин уже есть');
    }
    throw ApiError(400, msg);
  }

  // ======================================================================
  //  Здоровье сервера
  // ======================================================================

  /// Для мониторинга и проверки после обновления: 200 — всё работает,
  /// 503 — база или папка файлов недоступны. Без входа и без данных кафе.
  Response _health(Request req) {
    var dbOk = true;
    try {
      db.select('select 1 from cafes limit 1');
    } catch (_) {
      dbOk = false;
    }
    final filesOk = Directory(uploadsDir).existsSync();
    final ok = dbOk && filesOk;
    return _json({
      'status': ok ? 'ok' : 'error',
      'db': dbOk ? 'ok' : 'error',
      'files': filesOk ? 'ok' : 'error',
      'uptime_s': DateTime.now().difference(_startedAt).inSeconds,
    }, status: ok ? 200 : 503);
  }

  // ======================================================================
  //  Гость
  // ======================================================================

  Response _publicBranch(Request req, String slug) {
    final rows = db.select(
      '''
      select b.* from branches b join cafes c on c.id = b.cafe_id
       where b.slug = ? and b.is_active = 1 and c.is_active = 1''',
      [slug],
    );
    if (rows.isEmpty) throw ApiError(404, 'Филиал не найден');
    if (_access(rows.first['cafe_id'] as String).access == Access.expired) {
      throw ApiError(403, _unpaidGuest, code: 'unpaid');
    }
    return _json(_out(req, rows.first));
  }

  Response _publicMenu(Request req, String branchId) {
    final ok = db.select(
      '''
      select b.cafe_id from branches b join cafes c on c.id = b.cafe_id
       where b.id = ? and b.is_active = 1 and c.is_active = 1''',
      [branchId],
    );
    if (ok.isEmpty) throw ApiError(404, 'Филиал не найден');
    if (_access(ok.first['cafe_id'] as String).access == Access.expired) {
      throw ApiError(403, _unpaidGuest, code: 'unpaid');
    }
    final cats = db.select(
      'select * from categories where branch_id = ? and is_visible = 1 order by sort_order',
      [branchId],
    );
    final prods = db.select(
      'select * from products where branch_id = ? and is_visible = 1 order by sort_order',
      [branchId],
    );
    return _json({
      'categories': _outAll(req, cats),
      'products': _outAll(req, prods),
    });
  }

  // ======================================================================
  //  Вход
  // ======================================================================

  Future<Response> _login(Request req) async {
    final body = await _body(req);
    final login = (body['login'] as String? ?? '').trim();
    final password = body['password'] as String? ?? '';
    if (login.isEmpty || password.isEmpty) {
      throw ApiError(400, 'Введите логин и пароль');
    }

    final key = login.toLowerCase();
    final now = DateTime.now();
    final fails = (_failedLogins[key] ?? [])
      ..removeWhere((t) => now.difference(t) > const Duration(minutes: 15));
    if (fails.length >= 10) {
      throw ApiError(429, 'Слишком много попыток. Подождите 15 минут');
    }

    final rows = db.select(
      '''
      select u.*, c.is_active as cafe_active from users u
        left join cafes c on c.id = u.cafe_id
       where u.login = ?''',
      [login],
    );
    final row = rows.isEmpty ? null : rows.first;
    if (row == null ||
        !verifyPassword(password, row['password_hash'] as String)) {
      _failedLogins[key] = fails..add(now);
      // Одинаковый ответ на неизвестный логин и неверный пароль
      throw ApiError(401, 'Неверный логин или пароль');
    }
    if (row['is_active'] != 1 ||
        (row['cafe_id'] != null && row['cafe_active'] != 1)) {
      throw ApiError(403, 'Доступ заблокирован. Обратитесь к администратору');
    }
    _failedLogins.remove(key);

    final token = createSession(db, row['id'] as String);
    final user = userByToken(db, token)!;
    return _json({'token': token, 'user': _meJson(req, user)});
  }

  Response _logout(Request req) {
    final h = req.headers['authorization'] ?? '';
    if (h.startsWith('Bearer ')) {
      db.execute('delete from sessions where token = ?', [h.substring(7)]);
    }
    return _json({'ok': true});
  }

  Response _me(Request req) => _json(_meJson(req, _user(req)));

  Map<String, Object?> _meJson(Request req, AuthUser u) {
    Map<String, Object?>? cafe;
    if (u.cafeId != null) {
      final r = db
          .select(
            '''
        select c.id, c.name, c.max_branches, c.plan, c.paid_until,
               (select count(*) from branches b where b.cafe_id = c.id) as branch_count
          from cafes c where c.id = ?''',
            [u.cafeId],
          )
          .first;
      cafe = _withAccess(rowToJson(r));
      cafe['billing_contact'] = billingContact;
    }
    return {
      'id': u.id,
      'login': u.login,
      'role': u.role,
      'cafe': cafe,
      'menu_url': _menuBase(req),
    };
  }

  // ======================================================================
  //  Админ кафе: филиалы
  // ======================================================================

  Response _listBranches(Request req) {
    final u = _cafeAdmin(req);
    final rows = db.select(
      'select * from branches where cafe_id = ? order by sort_order, name',
      [u.cafeId],
    );
    return _json(_outAll(req, rows));
  }

  Future<Response> _createBranch(Request req) async {
    final u = _cafeAdmin(req);
    final data = _pick(req, await _body(req), _branchFields);
    final name = (data['name'] as String? ?? '').trim();
    if (name.isEmpty) throw ApiError(400, 'Введите название филиала');
    // Без адреса — собираем сами из названий кафе и филиала: у двух кафе
    // может быть свой «Центр», а адрес на всю платформу один.
    var slug = (data['slug'] as String? ?? '').trim();
    if (slug.isEmpty) {
      final cafe = db.select('select name from cafes where id = ?', [
        u.cafeId,
      ]).first;
      slug = _uniqueSlug(slugify('${cafe['name']} $name'));
    } else {
      slug = _checkSlug(slug);
    }

    // Понятное сообщение с числом — до того, как сработает триггер в базе
    final lim = db
        .select(
          '''
      select c.max_branches, (select count(*) from branches where cafe_id = c.id) as n
        from cafes c where c.id = ?''',
          [u.cafeId],
        )
        .first;
    if ((lim['n'] as int) >= (lim['max_branches'] as int)) {
      throw ApiError(
        403,
        'По вашему тарифу доступно филиалов: ${lim['max_branches']}. Новый создать нельзя',
      );
    }

    // Языки — как у первого филиала кафе: обычно меню на тех же языках
    if (!data.containsKey('languages')) {
      final first = db.select(
        'select languages from branches where cafe_id = ? order by sort_order limit 1',
        [u.cafeId],
      );
      if (first.isNotEmpty) data['languages'] = first.first['languages'];
    }

    final id = newId();
    try {
      _insert('branches', {
        ...data,
        'slug': slug,
        'id': id,
        'cafe_id': u.cafeId,
      });
    } on SqliteException catch (e) {
      _sqlError(e, slug: slug);
    }
    return _json(
      _out(req, db.select('select * from branches where id = ?', [id]).first),
      status: 201,
    );
  }

  Future<Response> _updateBranch(Request req, String id) async {
    final u = _cafeAdmin(req);
    _ownBranch(u, id);
    final data = _pick(req, await _body(req), _branchFields);
    if (data.containsKey('slug')) {
      final slug = (data['slug'] as String? ?? '').trim();
      if (slug.isEmpty) {
        throw ApiError(400, 'Адрес для ссылки не может быть пустым');
      }
      data['slug'] = _checkSlug(slug);
    }
    final oldMain = _mainLanguage(
      db.select('select languages from branches where id = ?', [id]).first,
    );
    final newMain = data.containsKey('languages')
        ? (jsonDecode(data['languages'] as String) as List).first as String
        : oldMain;
    try {
      inTransaction(db, () {
        _update('branches', id, data);
        if (newMain != oldMain) _switchMainLanguage(id, oldMain, newMain);
      });
    } on SqliteException catch (e) {
      _sqlError(e, slug: data['slug'] as String?);
    }
    return _json(
      _out(req, db.select('select * from branches where id = ?', [id]).first),
    );
  }

  static String _mainLanguage(Row branch) =>
      (jsonDecode(branch['languages'] as String) as List).first as String;

  /// Основной язык филиала сменился: тексты основного языка (name,
  /// description) и перевод на новый основной меняются местами. Если
  /// перевода нет — текст остаётся прежним, чтобы блюдо не стало пустым;
  /// при обратной смене такая копия переводом не считается.
  void _switchMainLanguage(String branchId, String from, String to) {
    for (final (table, fields) in [
      ('categories', ['name']),
      ('products', ['name', 'description']),
    ]) {
      final rows = db.select(
        'select id, ${fields.join(', ')}, i18n from $table where branch_id = ?',
        [branchId],
      );
      for (final row in rows) {
        final i18n = (jsonDecode(row['i18n'] as String) as Map)
            .cast<String, dynamic>();
        final target = (i18n.remove(to) as Map?)?.cast<String, dynamic>() ?? {};
        final previous = <String, String>{};
        final main = <String, String>{};
        for (final f in fields) {
          final current = row[f] as String;
          final translated = (target[f] as String?) ?? '';
          // Текст, равный переводу, — это копия, оставленная при прошлой
          // смене языка (перевода тогда не было), а не текст на [from]
          if (current.isNotEmpty && current != translated) {
            previous[f] = current;
          }
          main[f] = translated.isNotEmpty ? translated : current;
        }
        if (previous.isNotEmpty) i18n[from] = previous;
        _update(table, row['id'] as String, {
          ...main,
          'i18n': jsonEncode(i18n),
        });
      }
    }
  }

  /// Одно оформление на все филиалы кафе — одним запросом: либо у всех,
  /// либо ни у кого. Поля, кроме оформления, отбрасываются.
  Future<Response> _updateStyleAll(Request req) async {
    final u = _cafeAdmin(req);
    final data = _pick(req, await _body(req), styleColumns.toSet());
    if (data.isEmpty) throw ApiError(400, 'Нет полей оформления');
    final set = data.keys.map((k) => '$k = ?').join(', ');
    db.execute('update branches set $set where cafe_id = ?', [
      ...data.values,
      u.cafeId,
    ]);
    final rows = db.select(
      'select * from branches where cafe_id = ? order by sort_order',
      [u.cafeId],
    );
    return _json(_outAll(req, rows));
  }

  Response _deleteBranch(Request req, String id) {
    final u = _cafeAdmin(req);
    _ownBranch(u, id);
    final n =
        db.select('select count(*) as n from branches where cafe_id = ?', [
              u.cafeId,
            ]).first['n']
            as int;
    if (n <= 1) throw ApiError(400, 'Нельзя удалить единственный филиал');
    db.execute('delete from branches where id = ?', [id]);
    return _json({'ok': true});
  }

  // ======================================================================
  //  Админ кафе: категории и товары
  // ======================================================================

  Response _listCategories(Request req) {
    final u = _cafeAdmin(req);
    final branchId = req.url.queryParameters['branch_id'];
    _ownBranch(u, branchId);
    final rows = db.select(
      'select * from categories where branch_id = ? order by sort_order',
      [branchId],
    );
    return _json(_outAll(req, rows));
  }

  Future<Response> _createCategory(Request req) async {
    final u = _cafeAdmin(req);
    final body = await _body(req);
    final branchId = body['branch_id'] is String
        ? body['branch_id'] as String
        : null;
    _ownBranch(u, branchId);
    final data = _pick(req, body, _categoryFields);
    _checkParent(data['parent_id'] as String?, branchId!);
    final id = newId();
    _insert('categories', {...data, 'id': id, 'branch_id': branchId});
    return _json(
      _out(req, db.select('select * from categories where id = ?', [id]).first),
      status: 201,
    );
  }

  Future<Response> _updateCategory(Request req, String id) async {
    final u = _cafeAdmin(req);
    final row = _ownRow(u, 'categories', id);
    final data = _pick(req, await _body(req), _categoryFields);
    if (data.containsKey('parent_id')) {
      _checkParent(
        data['parent_id'] as String?,
        row['branch_id'] as String,
        selfId: id,
      );
    }
    _update('categories', id, data);
    return _json(
      _out(req, db.select('select * from categories where id = ?', [id]).first),
    );
  }

  Response _deleteCategory(Request req, String id) {
    final u = _cafeAdmin(req);
    _ownRow(u, 'categories', id);
    db.execute('delete from categories where id = ?', [id]);
    return _json({'ok': true});
  }

  Response _listProducts(Request req) {
    final u = _cafeAdmin(req);
    final branchId = req.url.queryParameters['branch_id'];
    _ownBranch(u, branchId);
    final rows = db.select(
      'select * from products where branch_id = ? order by sort_order',
      [branchId],
    );
    return _json(_outAll(req, rows));
  }

  Future<Response> _createProduct(Request req) async {
    final u = _cafeAdmin(req);
    final body = await _body(req);
    final branchId = body['branch_id'] is String
        ? body['branch_id'] as String
        : null;
    _ownBranch(u, branchId);
    final data = _pick(req, body, _productFields);
    _checkCategory(data['category_id'] as String?, branchId!);
    final id = newId();
    _insert('products', {...data, 'id': id, 'branch_id': branchId});
    return _json(
      _out(req, db.select('select * from products where id = ?', [id]).first),
      status: 201,
    );
  }

  Future<Response> _updateProduct(Request req, String id) async {
    final u = _cafeAdmin(req);
    final row = _ownRow(u, 'products', id);
    final data = _pick(req, await _body(req), _productFields);
    _checkCategory(data['category_id'] as String?, row['branch_id'] as String);
    _update('products', id, data);
    return _json(
      _out(req, db.select('select * from products where id = ?', [id]).first),
    );
  }

  Response _deleteProduct(Request req, String id) {
    final u = _cafeAdmin(req);
    _ownRow(u, 'products', id);
    db.execute('delete from products where id = ?', [id]);
    return _json({'ok': true});
  }

  /// Загрузка картинки или 3D-модели: тело запроса — сами байты, расширение
  /// в `?ext=`, префикс имени в `?prefix=`. Файлы каждого кафе лежат в своей
  /// папке.
  Future<Response> _upload(Request req) async {
    final u = _cafeAdmin(req);
    final ext = (req.url.queryParameters['ext'] ?? 'jpg').toLowerCase();
    final isModel = _modelExts.contains(ext);
    if (!isModel && !_imageExts.contains(ext)) {
      throw ApiError(
        400,
        'Можно загружать фото (jpg, png, webp, gif) или 3D-модель (glb)',
      );
    }
    if (!_uploads.tryAcquire(u.cafeId!)) {
      throw ApiError(
        429,
        'Слишком много загрузок подряд — подождите несколько минут',
      );
    }
    final maxBytes = isModel ? _maxModelBytes : _maxUploadBytes;
    final prefix = (req.url.queryParameters['prefix'] ?? '').replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '',
    );

    final tooBig = ApiError(413, 'Файл больше ${maxBytes ~/ (1024 * 1024)} МБ');
    // Заявленный размер проверяем до чтения: файл сверх лимита даже не
    // начинаем принимать
    if ((req.contentLength ?? 0) > maxBytes) throw tooBig;

    // BytesBuilder держит байты одним блоком: List<int> занял бы в 8 раз
    // больше памяти, и несколько больших моделей разом уронили бы сервер
    final buf = BytesBuilder(copy: false);
    await for (final chunk in req.read()) {
      buf.add(chunk);
      if (buf.length > maxBytes) throw tooBig;
    }
    final bytes = buf.takeBytes();
    if (bytes.isEmpty) throw ApiError(400, 'Пустой файл');

    late final Uint8List stored;
    var storedExt = ext;
    var gzipped = false;
    if (isModel) {
      // Настоящий .glb начинается с «glTF» — иначе под видом модели можно
      // выложить на сервер что угодно
      if (bytes.length < 12 ||
          ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'glTF') {
        throw ApiError(400, 'Это не 3D-модель .glb');
      }
      final packed = gzipIfWorthIt(bytes);
      stored = packed ?? bytes;
      gzipped = packed != null;
    } else {
      final photo = await compressPhoto(bytes, ext);
      if (photo == null) throw ApiError(400, 'Это не фото или файл повреждён');
      stored = photo.bytes;
      storedExt = photo.ext;
    }

    final name = '$prefix${DateTime.now().microsecondsSinceEpoch}.$storedExt';
    final dir = Directory('$uploadsDir/${u.cafeId}');
    // Место на диске общее для всех кафе — одно не должно занять его целиком
    final used = usedBytes(dir);
    if (used + stored.length > uploadQuotaBytes) {
      const mb = 1024 * 1024;
      throw ApiError(
        413,
        'Место для файлов кафе закончилось: занято ${used ~/ mb} из '
        '${uploadQuotaBytes ~/ mb} МБ. Обратитесь к администратору платформы',
      );
    }
    await dir.create(recursive: true);
    // Сжатая модель лежит как x.glb.gz, а адрес у неё x.glb — см. uploadsHandler
    await File('${dir.path}/$name${gzipped ? '.gz' : ''}').writeAsBytes(stored);
    final path = '/uploads/${u.cafeId}/$name';
    return _json({'path': path, 'url': '${_base(req)}$path'}, status: 201);
  }

  // ======================================================================
  //  Superadmin
  // ======================================================================

  Response _listCafes(Request req) {
    _superadmin(req);
    final cafes = db.select('''
      select c.*, (select count(*) from branches b where b.cafe_id = c.id) as branch_count
        from cafes c order by c.created_at desc''');
    final users = db.select('''
      select id, cafe_id, login, is_active, created_at from users
       where role = 'cafe_admin' order by created_at''');
    final branches = db.select(
      'select id, cafe_id, slug, name, is_active from branches order by sort_order, name',
    );
    return _json(
      cafes.map((c) {
        final m = _withAccess(rowToJson(c));
        m['users'] = users
            .where((x) => x['cafe_id'] == c['id'])
            .map(rowToJson)
            .toList();
        m['branches'] = branches
            .where((x) => x['cafe_id'] == c['id'])
            .map(rowToJson)
            .toList();
        return m;
      }).toList(),
    );
  }

  Map<String, Object?> _cafeById(String id) {
    final rows = db.select(
      '''
      select c.*, (select count(*) from branches b where b.cafe_id = c.id) as branch_count
        from cafes c where c.id = ?''',
      [id],
    );
    if (rows.isEmpty) throw ApiError(404, 'Кафе не найдено');
    return _withAccess(rowToJson(rows.first));
  }

  /// Добавляет к строке кафе статус оплаты и сколько дней осталось
  Map<String, Object?> _withAccess(Map<String, Object?> cafe) {
    final a = cafeAccess(
      cafe['plan'] as String,
      cafe['paid_until'] as String,
      _today(),
    );
    final left = a.daysLeft;
    return cafe
      ..['access'] = a.access.name
      ..['days_left'] = left
      // Через сколько дней меню у гостей выключится (null — не выключится)
      ..['menu_off_in'] = left == null || a.access == Access.expired
          ? null
          : left + graceDays + 1;
  }

  int _maxBranches(Object? v) {
    final n = v is int ? v : int.tryParse('$v');
    if (n == null || n < 1 || n > 1000) {
      throw ApiError(400, 'Лимит филиалов: число от 1');
    }
    return n;
  }

  Future<Response> _createCafe(Request req) async {
    _superadmin(req);
    final body = await _body(req);
    final name = (body['name'] as String? ?? '').trim();
    if (name.isEmpty) throw ApiError(400, 'Введите название кафе');
    final max = _maxBranches(body['max_branches'] ?? 1);
    final trial = body['trial_days'] ?? defaultTrialDays;
    if (trial is! int || trial < 0 || trial > 365) {
      throw ApiError(400, 'Пробный период: от 0 до 365 дней');
    }
    final paidUntil = formatDate(_today().add(Duration(days: trial)));
    final id = newId();
    // Сразу с первым филиалом: иначе админу кафе некуда войти — меню
    // и админка работают внутри филиала, а создать его было бы негде.
    db.execute('begin');
    try {
      db.execute(
        "insert into cafes (id, name, max_branches, plan, paid_until) values (?, ?, ?, 'trial', ?)",
        [id, name, max, paidUntil],
      );
      _insert('branches', {
        'id': newId(),
        'cafe_id': id,
        'slug': _uniqueSlug(slugify(name)),
        'name': name,
      });
      db.execute('commit');
    } catch (_) {
      db.execute('rollback');
      rethrow;
    }
    return _json(_cafeById(id), status: 201);
  }

  Future<Response> _updateCafe(Request req, String id) async {
    _superadmin(req);
    _cafeById(id);
    final body = await _body(req);
    final data = <String, Object?>{};
    if (body.containsKey('name')) {
      final name = (body['name'] as String? ?? '').trim();
      if (name.isEmpty) throw ApiError(400, 'Введите название кафе');
      data['name'] = name;
    }
    if (body.containsKey('max_branches')) {
      // Лимит можно уменьшить ниже текущего числа филиалов: лишние
      // остаются работать, но новые не создаются, пока их не станет меньше.
      data['max_branches'] = _maxBranches(body['max_branches']);
    }
    if (body.containsKey('is_active')) {
      data['is_active'] = toSql(body['is_active'] == true);
    }
    // Ручная правка срока — если ошиблись при оплате
    if (body.containsKey('plan')) {
      final plan = body['plan'];
      if (plan is! String || !plans.contains(plan)) {
        throw ApiError(400, 'Тариф: trial, paid или lifetime');
      }
      data['plan'] = plan;
    }
    if (body.containsKey('paid_until')) {
      final until = body['paid_until'];
      if (until is! String || parseDate(until) == null) {
        throw ApiError(400, 'Дата оплаты в виде ГГГГ-ММ-ДД');
      }
      data['paid_until'] = until;
    }
    _update('cafes', id, data);
    if (data['is_active'] == 0) {
      // Блокировка выкидывает уже вошедших
      db.execute(
        'delete from sessions where user_id in (select id from users where cafe_id = ?)',
        [id],
      );
    }
    return _json(_cafeById(id));
  }

  Response _deleteCafe(Request req, String id) {
    _superadmin(req);
    _cafeById(id);
    db.execute('delete from cafes where id = ?', [id]);
    return _json({'ok': true});
  }

  Response _listPayments(Request req, String cafeId) {
    _superadmin(req);
    _cafeById(cafeId);
    final rows = db.select(
      'select * from payments where cafe_id = ? order by paid_at desc',
      [cafeId],
    );
    return _json(rows.map(rowToJson).toList());
  }

  /// Оплата: продлевает срок на `months` месяцев (или навсегда) и пишет
  /// её в историю. Срок и запись меняются вместе, в одной транзакции.
  Future<Response> _addPayment(Request req, String cafeId) async {
    final admin = _superadmin(req);
    final cafe = _cafeById(cafeId);
    final body = await _body(req);

    final period = body['period'];
    if (period != 'month' && period != 'lifetime') {
      throw ApiError(400, 'Период: month или lifetime');
    }
    final months = period == 'month' ? body['months'] : 0;
    if (months is! int || (period == 'month' && (months < 1 || months > 36))) {
      throw ApiError(400, 'Месяцев: от 1 до 36');
    }
    final amount = body['amount'] ?? 0;
    if (amount is! num || !amount.isFinite || amount < 0) {
      throw ApiError(400, 'Сумма должна быть числом не меньше 0');
    }
    final note = body['note'] ?? '';
    if (note is! String) throw ApiError(400, 'Комментарий должен быть текстом');

    final plan = period == 'lifetime' ? 'lifetime' : 'paid';
    final until = period == 'lifetime'
        ? ''
        : extend(cafe['paid_until'] as String, months, _today());

    db.execute('begin');
    try {
      db.execute('update cafes set plan = ?, paid_until = ? where id = ?', [
        plan,
        until,
        cafeId,
      ]);
      db.execute(
        '''insert into payments (id, cafe_id, period, months, amount, note, paid_until, created_by)
           values (?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          newId(),
          cafeId,
          period,
          months,
          amount.toDouble(),
          note.trim(),
          until,
          admin.id,
        ],
      );
      db.execute('commit');
    } catch (_) {
      db.execute('rollback');
      rethrow;
    }
    return _json(_cafeById(cafeId), status: 201);
  }

  Future<Response> _createCafeUser(Request req, String cafeId) async {
    _superadmin(req);
    _cafeById(cafeId);
    final body = await _body(req);
    final login = (body['login'] as String? ?? '').trim();
    final password = body['password'] as String? ?? '';
    if (login.length < 3) {
      throw ApiError(400, 'Логин должен быть не короче 3 символов');
    }
    try {
      final id = createUser(
        db,
        login: login,
        password: password,
        role: 'cafe_admin',
        cafeId: cafeId,
      );
      return _json({'id': id, 'login': login}, status: 201);
    } on ArgumentError catch (e) {
      throw ApiError(400, '${e.message}');
    } on SqliteException catch (e) {
      _sqlError(e);
    }
  }

  Row _cafeUser(String id) {
    final rows = db.select(
      "select * from users where id = ? and role = 'cafe_admin'",
      [id],
    );
    if (rows.isEmpty) throw ApiError(404, 'Пользователь не найден');
    return rows.first;
  }

  Future<Response> _updateUser(Request req, String id) async {
    _superadmin(req);
    _cafeUser(id);
    final body = await _body(req);
    if (body['password'] is String) {
      final p = body['password'] as String;
      if (p.length < 6) {
        throw ApiError(400, 'Пароль должен быть не короче 6 символов');
      }
      db.execute('update users set password_hash = ? where id = ?', [
        hashPassword(p),
        id,
      ]);
      db.execute('delete from sessions where user_id = ?', [id]);
    }
    if (body.containsKey('is_active')) {
      db.execute('update users set is_active = ? where id = ?', [
        toSql(body['is_active'] == true),
        id,
      ]);
      if (body['is_active'] != true) {
        db.execute('delete from sessions where user_id = ?', [id]);
      }
    }
    return _json({'ok': true});
  }

  Response _deleteUser(Request req, String id) {
    _superadmin(req);
    _cafeUser(id);
    db.execute('delete from users where id = ?', [id]);
    return _json({'ok': true});
  }
}

Response _json(Object? body, {int status = 200}) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Превращает [ApiError] и прочие исключения в JSON-ответ.
Middleware errorHandler() =>
    (inner) => (req) async {
      try {
        return await inner(req);
      } on ApiError catch (e) {
        return _json({
          'error': e.message,
          if (e.code != null) 'code': e.code,
        }, status: e.status);
      } catch (e, st) {
        stderr.writeln('${req.method} ${req.requestedUri}: $e\n$st');
        return _json({'error': 'Внутренняя ошибка сервера'}, status: 500);
      }
    };
