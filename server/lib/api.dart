import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

import 'auth.dart';
import 'billing.dart';
import 'db.dart';
import 'glb.dart';
import 'languages.dart';
import 'media.dart';
import 'order.dart';
import 'security.dart';
import 'seo.dart' as seo;
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
/// `orders_enabled` здесь намеренно нет: право принимать заказы выдаёт
/// владелец платформы (`PATCH /api/super/branches/<id>`), и кафе не может
/// включить его себе само.
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
  'order_whatsapp',
  'delivery_price',
  ...styleColumns,
  ...locationColumns,
};

/// У заказа кафе меняет только отметку «готово». Состав, суммы и контакты
/// гостя — запись о том, что было, её не правят
const _orderFields = {'status'};
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
const _jsonFields = {'portions', 'languages', 'i18n', 'items'};

/// Поля с адресами файлов: в базе хранится путь `/uploads/...`,
/// наружу отдаётся полный адрес. Так база не привязана к домену сервера.
const _urlFields = {'image_url', 'logo_url', 'model_url', 'bg_url', 'cover_url'};

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

/// Формат снимков айфона. Пакет `image` его не открывает, поэтому админка
/// переводит такое фото в JPEG ещё до отправки (`lib/photo_shrink.dart`).
/// Сюда HEIC доходит только со старой, не обновлённой вкладки — ответ
/// должен подсказать, что делать, а не просто перечислить форматы.
const _appleExts = {'heic', 'heif'};
const _heicHint =
    'Это фото в формате HEIC с айфона. Обновите страницу админки и '
    'попробуйте снова. Если не поможет — на айфоне: Настройки → Камера → '
    'Форматы → «Наиболее совместимые»';

/// Сколько символов в адресе и часах работы филиала
const _maxLocationText = 200;

/// Сколько символов в описании кафе для каталога
const _maxCafeDescription = 300;
const _maxUploadBytes = 10 * 1024 * 1024;

/// Тело JSON-запроса: всё меню филиала — десятки КБ. Без предела любой,
/// даже не вошедший (вход), мог бы прислать гигабайт и занять память
const _maxBodyBytes = 1024 * 1024;

/// Предел длины опознавателя. Все id в базе — UUID из 36 знаков (`newId`),
/// так что запас тут огромный.
///
/// Нужен не для красоты: без него присланный id попадает и в ключ
/// ограничителя частоты, и в сохранённый заказ. Мегабайтная строка в теле
/// запроса оседала бы в памяти на целое окно или ложилась бы в базу —
/// и то, и другое валит сервер у всех кафе разом.
const _maxIdLength = 64;

/// Длина текстовых полей. Без предела в название можно положить мегабайты —
/// меню у гостей грузилось бы минутами
const _maxText = {
  'name': 200,
  'slogan': 200,
  'phone': 50,
  'description': 2000,
  'guest_name': 60,
  'guest_phone': 30,
  'comment': 300,
  'address': _maxLocationText,
};
const _maxTextDefault = 500;

/// Сколько позиций и сколько одинаковых блюд допустимо в одном заказе.
/// Выше — это не обед, а попытка раздуть запись и сообщение в WhatsApp
const _maxOrderItems = 100;
const _maxOrderQty = 99;

/// Код заказа: его придумывает клиент, сервер только проверяет вид
final _orderCode = RegExp(r'^[A-Z0-9]{0,8}$');

/// Управляющие символы и «невидимые» знаки направления текста: ими можно
/// спрятать или перевернуть часть названия (подмена текста). Перевод
/// строки и табуляция остаются
final _hiddenChars = RegExp(
  '[${[
    (0x00, 0x08), (0x0B, 0x0C), (0x0E, 0x1F), (0x7F, 0x7F),
    (0x202A, 0x202E), (0x2066, 0x2069),
    // Пробелы нулевой ширины: ими разрывают слово так, что глазом не
    // отличишь. Соединитель 0x200D не трогаем — на нём держатся эмодзи
    (0x200B, 0x200B), (0xFEFF, 0xFEFF),
  ].map((r) => '${String.fromCharCode(r.$1)}-${String.fromCharCode(r.$2)}').join()}]',
);

/// Путь к файлу кафе: `/uploads/<кафе>/<файл>` — такие имена даёт сервер
final _uploadPath = RegExp(r'^/uploads/([A-Za-z0-9_-]+)/[A-Za-z0-9._-]+$');

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

  /// Код страны, которым дополняется номер WhatsApp, начатый с нуля
  /// (`0555112233` → `996555112233`). Пусто — такие номера не принимаются:
  /// угаданный неверно код страны увёл бы все заказы кафе на чужой телефон
  final String defaultCountryCode;

  Api(
    this.db, {
    required this.uploadsDir,
    this.publicUrl,
    this.menuUrl,
    this.billingContact = '',
    this.defaultCountryCode = '',
    this.uploadQuotaBytes = 2 * 1024 * 1024 * 1024,
    UploadLimiter? uploadLimiter,
    SlidingWindowLimiter? orderIpLimiter,
    SlidingWindowLimiter? orderBranchLimiter,
  }) : _uploads = uploadLimiter ?? UploadLimiter(),
       _orderIp =
           orderIpLimiter ??
           SlidingWindowLimiter(max: 5, window: const Duration(minutes: 5)),
       _orderBranch =
           orderBranchLimiter ??
           SlidingWindowLimiter(max: 60, window: const Duration(minutes: 10));

  /// Сколько заказов подряд принимается с одного адреса
  final SlidingWindowLimiter _orderIp;

  /// И сколько — одним филиалом: это предел и на наплыв с разных адресов,
  /// и на рост таблицы
  final SlidingWindowLimiter _orderBranch;

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
  static const _tooManyOrders =
      'Слишком много заказов подряд. Подождите немного';

  /// Значение поля запроса как строка; не строка — пусто.
  static String _str(Object? v) => v is String ? v : '';

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
    r.get('/api/public/cafes', _publicCafes);
    r.post('/api/public/orders', _createOrder);

    // ---------- Для поисковиков (seo.dart) ----------
    r.get('/kafe', _seoCatalog);
    r.get('/kafe/', _seoCatalog);
    r.get('/kafe/<slug>', _seoBranch);
    r.get('/sitemap.xml', _sitemap);
    r.get('/robots.txt', _robots);

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
    r.post('/api/admin/products/copy', _copyProducts);

    r.get('/api/admin/orders', _listOrders);
    r.patch('/api/admin/orders/<id>', _updateOrder);

    r.post('/api/admin/upload', _upload);

    // ---------- Superadmin ----------
    r.get('/api/super/cafes', _listCafes);
    r.post('/api/super/cafes', _createCafe);
    r.patch('/api/super/cafes/<id>', _updateCafe);
    r.delete('/api/super/cafes/<id>', _deleteCafe);
    r.post('/api/super/cafes/<id>/users', _createCafeUser);
    r.get('/api/super/cafes/<id>/payments', _listPayments);
    r.post('/api/super/cafes/<id>/payments', _addPayment);
    r.post('/api/super/cafes/<id>/upload', _uploadCafeImage);
    r.patch('/api/super/branches/<id>', _updateBranchOrders);
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
    // Номер гостя хранится так, как он его набрал: «0555112233» — то, что
    // кафе узнаёт и диктует вслух. Для ссылки «написать в WhatsApp» нужен
    // международный вид, а код страны знает только сервер
    // (DEFAULT_COUNTRY_CODE). Не вышло — пусто, и кнопки в админке нет
    if (m.containsKey('guest_phone')) {
      m['guest_phone_wa'] =
          normalizeWaPhone(
            _str(m['guest_phone']),
            defaultCountryCode: defaultCountryCode,
          ) ??
          '';
    }
    // Код страны для номеров, набранных с нуля, знает только сервер.
    // Админка показывает «Сохранится как…» ещё до отправки, и без этого
    // ей пришлось бы угадывать страну самой — ровно то, чего мы избегаем
    if (m.containsKey('order_whatsapp')) {
      m['default_country_code'] = defaultCountryCode;
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
    const tooBig = 'Слишком большой запрос';
    if ((req.contentLength ?? 0) > _maxBodyBytes) throw ApiError(413, tooBig);
    final buf = BytesBuilder(copy: false);
    await for (final chunk in req.read()) {
      buf.add(chunk);
      if (buf.length > _maxBodyBytes) throw ApiError(413, tooBig);
    }
    try {
      final text = utf8.decode(buf.takeBytes());
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
        final v = _in(req, e.key, _valid(e.key, e.value));
        if (_urlFields.contains(e.key)) _checkOwnFile(req, e.key, v);
        m[e.key] = e.key == 'qr_url' ? _checkQr(req, v as String) : v;
      }
    }
    return m;
  }

  /// Картинка или модель — только файл, загруженный этим же кафе. Иначе
  /// в меню можно вписать любую ссылку: на чужой сайт, который увидит
  /// адреса гостей, на непроверенный файл или `javascript:`.
  void _checkOwnFile(Request req, String field, Object? v) {
    if (v == null || v == '') return;
    final m = v is String ? _uploadPath.firstMatch(v) : null;
    if (m == null || m.group(1) != _user(req).cafeId) {
      throw ApiError(
        400,
        'Файл для «$field» нужно загрузить через админку',
      );
    }
  }

  /// Ссылка внутри QR-кода на столе: подмена увела бы гостей на чужой
  /// сайт — только обычный https-адрес. Ссылка на наше же меню (её
  /// подставляет [_out]) хранится пустой: соберётся заново из адреса.
  String _checkQr(Request req, String v) {
    if (v.isEmpty || v.startsWith('${_menuBase(req)}/')) return '';
    final uri = Uri.tryParse(v);
    if (uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        v.length <= 1000) {
      return v;
    }
    throw ApiError(400, 'Ссылка для QR должна начинаться с https://');
  }

  /// Текст из формы: без невидимых символов, с обрезанными пробелами по
  /// краям и не длиннее предела поля
  /// Поле, которое по смыслу занимает одну строку: имя гостя, название
  /// блюда, размер порции. Переносы строк схлопываем в пробел.
  ///
  /// Иначе внутри такого поля рисуется строка, похожая на служебную
  /// («Итого: 0 с.»), и карточка заказа в админке начинает врать.
  /// Адрес и комментарий сюда не входят: там перенос строки осмыслен.
  static String _line(String field, String v) =>
      _text(field, v.replaceAll(RegExp(r'[\r\n]+'), ' '));

  static String _text(String field, String v) {
    final t = v.replaceAll(_hiddenChars, '').trim();
    final max = _maxText[field] ?? _maxTextDefault;
    if (t.length > max) {
      throw ApiError(400, 'Поле «$field»: не длиннее $max символов');
    }
    return t;
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
      case 'address' || 'hours':
        if (v is String) {
          final t = v.trim();
          if (t.length > _maxLocationText) {
            throw ApiError(400, 'Не длиннее $_maxLocationText символов');
          }
          return t;
        }
      case 'qr_url':
        // Адрес проверит _checkQr — ему нужен адрес меню из запроса
        if (v is String) return v.trim();
      case 'image_url' || 'logo_url' || 'model_url' || 'bg_url' || 'cover_url':
        // Чей это файл, проверит _checkOwnFile — здесь только тип
        if (v is String) return v.trim();
      case 'map_url':
        // Ссылка открывается у гостя — только обычный https-адрес, иначе
        // под видом карты можно было бы подсунуть javascript: или файл
        if (v is String) {
          final t = v.trim();
          final uri = Uri.tryParse(t);
          if (t.isEmpty) return t;
          if (uri != null &&
              uri.scheme == 'https' &&
              uri.host.isNotEmpty &&
              t.length <= 1000) {
            return t;
          }
          throw ApiError(
            400,
            'Ссылка на карту должна начинаться с https://',
          );
        }
      case 'order_whatsapp':
        if (v is String) {
          final digits = normalizeWaPhone(
            v,
            defaultCountryCode: defaultCountryCode,
          );
          if (digits != null) return digits;
          throw ApiError(
            400,
            'Номер WhatsApp: цифры с кодом страны, например 996555112233',
          );
        }
      case 'delivery_price':
        // Потолок — чтобы съехавшая запятая не превратилась в счёт на
        // миллион, который гость увидит у себя в WhatsApp
        if (v is num && v.isFinite && v >= 0 && v <= 100000) {
          return v.toDouble();
        }
        throw ApiError(400, 'Стоимость доставки: число от 0');
      case 'status':
        if (v == 'new' || v == 'done') return v;
        throw ApiError(400, 'Неизвестная отметка заказа');
      case 'i18n':
        return _validI18n(v);
      case 'portions':
        if (v == null) return const [];
        if (v is List && v.every(_validPortion)) {
          return [
            for (final p in v)
              {
                'name': _text('name', (p as Map)['name'] as String),
                'price': (p['price'] as num).toDouble(),
              },
          ];
        }
        throw ApiError(
          400,
          'Порции: у каждой нужны название и цена не меньше 0',
        );
      default:
        if (v is String) return _text(field, v);
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
        final clean = _text(field as String, text);
        if (clean.isNotEmpty) texts[field] = clean;
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
    final m = _out(req, rows.first);
    // Право на заказы выдаёт владелец платформы, и каждому филиалу своё.
    // Нет права — для гостя это просто незаполненный номер: кнопки заказа
    // нет, и объяснять ему нечего. Сам номер при этом остаётся в базе
    if (m['orders_enabled'] != true) m['order_whatsapp'] = '';
    return _json(m);
  }

  /// Каталог на главной сайта: кафе, которые superadmin включил в него,
  /// с их филиалами. Заблокированные и неоплаченные (меню у гостей
  /// выключено) не показываются, как и кафе без единого работающего филиала.
  Response _publicCafes(Request req) => _json([
    for (final c in _catalogCafes(req))
      {
        ...c,
        'branches': [
          for (final b in c['branches'] as List<Map<String, Object?>>)
            Map.of(b)..remove('id'),
        ],
      },
  ]);

  /// Кафе каталога с филиалами — для [_publicCafes] и страниц поисковиков.
  /// У филиала есть `id`: по нему страница поисковика берёт меню.
  List<Map<String, Object?>> _catalogCafes(Request req) {
    final cafes = db.select('''
      select id, name, description, logo_url, cover_url, plan, paid_until
        from cafes where is_active = 1 and show_in_catalog = 1
       order by name collate nocase''');
    final branches = db.select('''
      select b.id, b.cafe_id, b.slug, b.name, b.slogan, b.logo_url, b.phone,
             b.address, b.map_url, b.hours from branches b
        join cafes c on c.id = b.cafe_id
       where b.is_active = 1 and c.is_active = 1 and c.show_in_catalog = 1
       order by b.sort_order, b.name''');
    final out = <Map<String, Object?>>[];
    for (final c in cafes) {
      final access = cafeAccess(
        c['plan'] as String,
        c['paid_until'] as String,
        _today(),
      );
      if (access.access == Access.expired) continue;
      final own = branches.where((b) => b['cafe_id'] == c['id']).map((b) {
        final m = _out(req, b)..remove('cafe_id');
        return m;
      }).toList();
      if (own.isEmpty) continue;
      out.add(
        _out(req, c)
          ..remove('plan')
          ..remove('paid_until')
          ..['branches'] = own,
      );
    }
    return out;
  }

  // ======================================================================
  //  Для поисковиков
  // ======================================================================

  Response _seoCatalog(Request req) =>
      _html(seo.catalogPage(base: _menuBase(req), cafes: _catalogCafes(req)));

  Response _seoBranch(Request req, String slug) {
    final base = _menuBase(req);
    for (final cafe in _catalogCafes(req)) {
      for (final b in cafe['branches'] as List<Map<String, Object?>>) {
        if ((b['slug'] as String).toLowerCase() != slug.toLowerCase()) {
          continue;
        }
        final cats = db.select(
          'select * from categories where branch_id = ? and is_visible = 1 order by sort_order',
          [b['id']],
        );
        final prods = db.select(
          'select * from products where branch_id = ? and is_visible = 1 order by sort_order',
          [b['id']],
        );
        return _html(
          seo.branchPage(
            base: base,
            cafe: cafe,
            branch: b,
            categories: _outAll(req, cats),
            products: _outAll(req, prods),
          ),
        );
      }
    }
    return _html(seo.notFoundPage(base), status: 404);
  }

  Response _sitemap(Request req) => Response.ok(
    seo.sitemap(_menuBase(req), [
      for (final c in _catalogCafes(req))
        for (final b in c['branches'] as List<Map<String, Object?>>)
          b['slug'] as String,
    ]),
    headers: {'content-type': 'application/xml; charset=utf-8'},
  );

  Response _robots(Request req) => Response.ok(
    seo.robots(_menuBase(req)),
    headers: {'content-type': 'text/plain; charset=utf-8'},
  );

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

  /// Заказ гостя с сайта. Открыт всем: гость никуда не входит.
  ///
  /// Клиент не присылает **никаких денег** — ни цен блюд, ни стоимости
  /// доставки, ни итога. Всё это сервер считает сам, по своей же базе:
  /// запрос публичный, и доверие к присланной сумме позволило бы любому
  /// записать кафе «шашлык за 1 сом». К тому же меню у гостя бывает из
  /// кэша (menu_store.dart) и несёт прошлонедельные цены.
  ///
  /// Текст сообщения собирает клиент, и гость может его поправить перед
  /// отправкой. Сообщение — уведомление; что было на самом деле, записано
  /// здесь, и кафе смотрит в список заказов.
  Future<Response> _createOrder(Request req) async {
    final body = await _body(req);
    // Пределы — до любой работы с базой
    if (!_orderIp.tryAcquire(clientIp(req))) {
      throw ApiError(429, _tooManyOrders, code: 'too_often');
    }
    final branchId = _str(body['branch_id']);
    if (branchId.isEmpty || branchId.length > _maxIdLength) {
      throw ApiError(400, 'Не указан филиал');
    }

    final rows = db.select(
      '''
      select b.* from branches b join cafes c on c.id = b.cafe_id
       where b.id = ? and b.is_active = 1 and c.is_active = 1''',
      [branchId],
    );
    if (rows.isEmpty) throw ApiError(404, 'Филиал не найден');
    final branch = rows.first;
    // Предел по филиалу — только после того, как филиал нашёлся: ключом
    // обязан быть существующий id. Иначе ключи заводит кто угодно, просто
    // присылая каждый раз новую строку, и память растёт без предела.
    // Запрос до этой точки один и по первичному ключу, а гостя уже
    // придержал предел по адресу выше
    if (!_orderBranch.tryAcquire(branch['id'] as String)) {
      throw ApiError(429, _tooManyOrders, code: 'too_often');
    }
    if (_access(branch['cafe_id'] as String).access == Access.expired) {
      throw ApiError(403, _unpaidGuest, code: 'unpaid');
    }
    // Два условия, и оба обязательны: право на заказы этому филиалу выдал
    // владелец платформы, а кафе вписало номер WhatsApp. Гостю разница не
    // видна — кнопки у него в обоих случаях нет, и ответ одинаковый. Без этой
    // проверки список заказов можно было бы засыпать тому, кто их не
    // принимает и на этот экран не заходит
    if ((branch['orders_enabled'] as int? ?? 0) == 0 ||
        _str(branch['order_whatsapp']).isEmpty) {
      throw ApiError(
        403,
        'Заказы в этом кафе пока не принимаются',
        code: 'orders_off',
      );
    }

    final type = body['order_type'];
    if (type != 'delivery' && type != 'pickup') {
      throw ApiError(400, 'Неизвестный способ получения заказа');
    }
    final isDelivery = type == 'delivery';

    final name = _line('guest_name', _str(body['name']));
    if (name.isEmpty) throw ApiError(400, 'Укажите имя');
    final phone = cleanGuestPhone(_str(body['phone']));
    if (phone == null) throw ApiError(400, 'Укажите телефон');
    // У самовывоза адреса нет, что бы ни прислал клиент
    final address = isDelivery ? _text('address', _str(body['address'])) : '';
    if (isDelivery && address.isEmpty) {
      throw ApiError(400, 'Укажите адрес доставки');
    }
    final comment = _text('comment', _str(body['comment']));
    final lang = _str(body['lang']);
    if (lang.isNotEmpty && !menuLanguages.contains(lang)) {
      throw ApiError(400, 'Неизвестный язык');
    }
    final code = _str(body['code']).toUpperCase();
    if (!_orderCode.hasMatch(code)) {
      throw ApiError(400, 'Неверный код заказа');
    }

    // Повтор: двойное нажатие или переотправка с клиента. Возвращаем тот же
    // заказ, а не заводим второй — иначе на кухню уйдут два одинаковых
    if (code.isNotEmpty) {
      final same = db.select(
        '''
        select * from orders
         where branch_id = ? and code = ?
           and created_at > datetime('now', '-10 minutes')
         order by created_at desc limit 1''',
        [branchId, code],
      );
      if (same.isNotEmpty) return _json(_orderReceipt(same.first));
    }

    final rawItems = body['items'];
    if (rawItems is! List || rawItems.isEmpty) {
      throw ApiError(400, 'Заказ пустой');
    }
    if (rawItems.length > _maxOrderItems) {
      throw ApiError(400, 'В заказе не больше $_maxOrderItems позиций');
    }
    final menu = <String, Row>{
      for (final p in db.select(
        'select id, name, price, portions from products '
        'where branch_id = ? and is_visible = 1',
        [branchId],
      ))
        p['id'] as String: p,
    };

    final items = <Map<String, Object?>>[];
    var itemsTotal = 0.0;
    for (final raw in rawItems) {
      if (raw is! Map) throw ApiError(400, 'Неверная позиция заказа');
      final id = _str(raw['product_id']);
      final qty = raw['qty'];
      if (id.isEmpty ||
          id.length > _maxIdLength ||
          qty is! int ||
          qty < 1 ||
          qty > _maxOrderQty) {
        throw ApiError(400, 'Неверная позиция заказа');
      }
      final portion = _line('name', _str(raw['portion']));
      final product = menu[id];
      if (product == null) {
        // Блюдо исчезло из меню, пока гость собирал заказ. Отказать нельзя:
        // ссылка в WhatsApp к этому моменту уже открыта, и отказ сообщение
        // не отзовёт — кафе получило бы заказ, которого нет в списке. Строка
        // остаётся, но с ценой 0 и пометкой: пусть кафе перезвонит, а не
        // привезёт меньше, чем просили
        items.add({
          'product_id': id,
          'name': _line('name', _str(raw['name'])),
          'portion': portion,
          'price': 0,
          'qty': qty,
          'sum': 0,
          'missing': true,
        });
        continue;
      }
      final price = _portionPrice(product, portion);
      final sum = price * qty;
      itemsTotal += sum;
      items.add({
        'product_id': id,
        'name': product['name'] as String,
        'portion': portion,
        'price': price,
        'qty': qty,
        'sum': sum,
      });
    }

    final deliveryTotal = isDelivery
        ? ((branch['delivery_price'] as num?)?.toDouble() ?? 0)
        : 0.0;
    final id = newId();
    try {
      _insert('orders', {
        'id': id,
        'branch_id': branchId,
        'code': code,
        'order_type': type,
        'guest_name': name,
        'guest_phone': phone,
        'address': address,
        'comment': comment,
        'lang': lang,
        'items': jsonEncode(items),
        'items_total': itemsTotal,
        'delivery_total': deliveryTotal,
        'total': itemsTotal + deliveryTotal,
      });
    } on SqliteException catch (e) {
      _sqlError(e);
    }
    // Ответ собирается из сохранённой строки — тем же кодом, что и ответ на
    // повтор выше, чтобы они не разошлись
    final saved = db.select('select * from orders where id = ?', [id]).first;
    return _json(_orderReceipt(saved), status: 201);
  }

  /// Цена порции по её названию; нет такой — цена блюда целиком.
  double _portionPrice(Row product, String portion) {
    final base = (product['price'] as num?)?.toDouble() ?? 0;
    if (portion.isEmpty) return base;
    try {
      final list = jsonDecode(_str(product['portions']));
      if (list is List) {
        for (final p in list) {
          if (p is Map && p['name'] == portion && p['price'] is num) {
            return (p['price'] as num).toDouble();
          }
        }
      }
    } catch (_) {
      // Испорченный JSON порций не должен ронять заказ
    }
    return base;
  }

  /// Что возвращается гостю после заказа: только суммы и сколько блюд уже
  /// пропало из меню. Личные данные обратно не отдаём — их незачем
  /// пересылать ещё раз
  Map<String, Object?> _orderReceipt(Row row) {
    var missing = 0;
    try {
      final items = jsonDecode(_str(row['items']));
      if (items is List) {
        missing = items.where((i) => i is Map && i['missing'] == true).length;
      }
    } catch (_) {
      // см. _portionPrice
    }
    return {
      'id': row['id'],
      'code': row['code'],
      'items_total': row['items_total'],
      'delivery_total': row['delivery_total'],
      'total': row['total'],
      'missing': missing,
      'created_at': row['created_at'],
    };
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
    // `orders_enabled` в строке филиала — право на заказы, выданное
    // владельцем платформы. Своей админке показываем его честно: иначе
    // кафе вписало бы номер и не понимало, почему кнопка у гостей так и не
    // появилась. Поменять это поле кафе не может — его нет в `_branchFields`
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

  /// Блюда — в другой филиал своего кафе. Категория там ищется по
  /// названию на том же уровне (подкатегория — внутри основной с именем
  /// родителя), нет — создаётся. Блюдо с тем же названием в этой категории
  /// уже есть — пропускается: у филиала могут быть свои цены. Файлы общие:
  /// копия ссылается на те же фото и 3D, удаление блюда файлов не трогает.
  /// id строки с тем же названием без учёта регистра. Сравнение в Dart:
  /// `lower()` в SQLite понимает только латиницу, «Кофе» ≠ «кофе».
  static String? _byName(ResultSet rows, String name) {
    final key = name.trim().toLowerCase();
    for (final r in rows) {
      if ((r['name'] as String).trim().toLowerCase() == key) {
        return r['id'] as String;
      }
    }
    return null;
  }

  Future<Response> _copyProducts(Request req) async {
    final u = _cafeAdmin(req);
    final body = await _body(req);
    final ids = body['product_ids'];
    final to = body['to_branch_id'];
    if (ids is! List ||
        ids.isEmpty ||
        ids.length > 1000 ||
        ids.any((i) => i is! String)) {
      throw ApiError(400, 'Выберите от 1 до 1000 блюд');
    }
    if (to is! String) throw ApiError(400, 'Выберите филиал');
    _ownBranch(u, to);
    final dishes = [
      for (final id in ids.toSet()) _ownRow(u, 'products', id as String),
    ];
    if (dishes.any((d) => d['branch_id'] == to)) {
      throw ApiError(400, 'Блюда уже в этом филиале — выберите другой');
    }

    var copied = 0, skipped = 0, created = 0;
    // Категория источника → категория в целевом филиале
    final mapped = <String, String>{};

    String targetCategory(String sourceId) {
      final cached = mapped[sourceId];
      if (cached != null) return cached;
      final src = db.select('select * from categories where id = ?', [
        sourceId,
      ]).first;
      final parentSrc = src['parent_id'] as String?;
      final parent = parentSrc == null ? null : targetCategory(parentSrc);
      final found = _byName(
        db.select(
          'select id, name from categories where branch_id = ? and parent_id is ?',
          [to, parent],
        ),
        src['name'] as String,
      );
      final String id;
      if (found != null) {
        id = found;
      } else {
        id = newId();
        db.execute(
          '''insert into categories (id, branch_id, parent_id, name, i18n,
                                     image_url, is_visible, sort_order)
             values (?, ?, ?, ?, ?, ?, ?, ?)''',
          [
            id,
            to,
            parent,
            src['name'],
            src['i18n'],
            src['image_url'],
            src['is_visible'],
            src['sort_order'],
          ],
        );
        created++;
      }
      return mapped[sourceId] = id;
    }

    inTransaction(db, () {
      for (final d in dishes) {
        final source = d['category_id'] as String?;
        final category = source == null ? null : targetCategory(source);
        final exists = _byName(
          db.select(
            'select id, name from products where branch_id = ? and category_id is ?',
            [to, category],
          ),
          d['name'] as String,
        );
        if (exists != null) {
          skipped++;
          continue;
        }
        db.execute(
          '''insert into products (id, branch_id, category_id, name, description,
                                   i18n, price, image_url, model_url, is_visible,
                                   sort_order, portions)
             values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
          [
            newId(),
            to,
            category,
            d['name'],
            d['description'],
            d['i18n'],
            d['price'],
            d['image_url'],
            d['model_url'],
            d['is_visible'],
            d['sort_order'],
            d['portions'],
          ],
        );
        copied++;
      }
    });
    return _json({
      'copied': copied,
      'skipped': skipped,
      'categories_created': created,
    });
  }

  // ======================================================================
  //  Заказы (кафе)
  // ======================================================================

  /// Заказы филиала, новые сверху. Личные данные гостя видит только своё
  /// кафе: публичного чтения заказов нет и быть не должно.
  Response _listOrders(Request req) {
    final u = _cafeAdmin(req);
    final q = req.url.queryParameters;
    final branch = _ownBranch(u, q['branch_id']);
    final status = q['status'];
    if (status != null && status != 'new' && status != 'done') {
      throw ApiError(400, 'Неизвестная отметка заказа');
    }
    final before = q['before'];
    final where = StringBuffer('branch_id = ?');
    final args = <Object?>[branch['id']];
    if (status != null) {
      where.write(' and status = ?');
      args.add(status);
    }
    if (before != null && before.isNotEmpty) {
      where.write(' and created_at < ?');
      args.add(before);
    }
    // Предел обязателен: без него экран кафе с годовой историей заказов
    // грузился бы минутами
    args.add((int.tryParse(q['limit'] ?? '') ?? 50).clamp(1, 200));
    return _json(
      _outAll(
        req,
        db.select(
          'select * from orders where $where order by created_at desc limit ?',
          args,
        ),
      ),
    );
  }

  /// Отметка «готово» и обратно. Состав и суммы заказа не меняются: это
  /// запись о том, что было.
  Future<Response> _updateOrder(Request req, String id) async {
    final u = _cafeAdmin(req);
    _ownRow(u, 'orders', id);
    final data = _pick(req, await _body(req), _orderFields);
    _update('orders', id, data);
    return _json(
      _out(req, db.select('select * from orders where id = ?', [id]).first),
    );
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
        _appleExts.contains(ext)
            ? _heicHint
            : 'Можно загружать фото (jpg, png, webp, gif) или 3D-модель (glb)',
      );
    }
    final prefix = (req.url.queryParameters['prefix'] ?? '').replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '',
    );
    final path = await _storeUpload(req, u.cafeId!, ext, prefix);
    return _json({'path': path, 'url': '${_base(req)}$path'}, status: 201);
  }

  /// Логотип или обложка кафе для каталога — ставит superadmin.
  /// `?kind=logo|cover`, `?ext=` — как у [_upload], но только фото.
  Future<Response> _uploadCafeImage(Request req, String id) async {
    _superadmin(req);
    _cafeById(id);
    final kind = req.url.queryParameters['kind'];
    final column = switch (kind) {
      'logo' => 'logo_url',
      'cover' => 'cover_url',
      _ => throw ApiError(400, 'kind: logo или cover'),
    };
    final ext = (req.url.queryParameters['ext'] ?? 'jpg').toLowerCase();
    if (!_imageExts.contains(ext)) {
      throw ApiError(
        400,
        _appleExts.contains(ext)
            ? _heicHint
            : 'Можно загружать фото (jpg, png, webp, gif)',
      );
    }
    final path = await _storeUpload(req, id, ext, 'cafe-$kind-');
    _update('cafes', id, {column: path});
    return _json(_cafeById(id), status: 201);
  }

  /// Принимает тело запроса и кладёт файл в папку кафе [cafeId].
  /// Фото сжимается, 3D-модель проверяется и по возможности сжимается gzip.
  /// Возвращает путь `/uploads/...`.
  Future<String> _storeUpload(
    Request req,
    String cafeId,
    String ext,
    String prefix,
  ) async {
    final isModel = _modelExts.contains(ext);
    if (!_uploads.tryAcquire(cafeId)) {
      throw ApiError(
        429,
        'Слишком много загрузок подряд — подождите несколько минут',
      );
    }
    final maxBytes = isModel ? _maxModelBytes : _maxUploadBytes;
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
      // Проверяется вся структура — иначе под видом модели можно выложить
      // на сервер что угодно
      final problem = glbProblem(bytes);
      if (problem != null) throw ApiError(400, problem);
      final packed = gzipIfWorthIt(bytes);
      stored = packed ?? bytes;
      gzipped = packed != null;
    } else {
      final Photo? photo;
      try {
        photo = await compressPhoto(bytes, ext);
      } on PhotoTooLarge catch (e) {
        throw ApiError(400, '$e');
      }
      if (photo == null) throw ApiError(400, 'Это не фото или файл повреждён');
      stored = photo.bytes;
      storedExt = photo.ext;
    }

    final name = '$prefix${DateTime.now().microsecondsSinceEpoch}.$storedExt';
    final dir = Directory('$uploadsDir/$cafeId');
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
    return '/uploads/$cafeId/$name';
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
    // order_whatsapp — чтобы на экране было видно не только выданное
    // право, но и вписало ли кафе номер: без номера заказы всё равно не
    // идут, а выглядит это как поломка
    final branches = db.select(
      'select id, cafe_id, slug, name, is_active, orders_enabled, '
      'order_whatsapp from branches order by sort_order, name',
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
    if (body.containsKey('show_in_catalog')) {
      data['show_in_catalog'] = toSql(body['show_in_catalog'] == true);
    }
    if (body.containsKey('description')) {
      final text = body['description'];
      if (text is! String) throw ApiError(400, 'Описание — текстом');
      final t = text.trim();
      if (t.length > _maxCafeDescription) {
        throw ApiError(
          400,
          'Описание — не длиннее $_maxCafeDescription символов',
        );
      }
      data['description'] = t;
    }
    // Логотип и обложку можно только убрать: ставятся они загрузкой
    for (final f in ['logo_url', 'cover_url']) {
      if (body.containsKey(f)) {
        if (body[f] != '') throw ApiError(400, 'Картинку — через загрузку');
        data[f] = '';
      }
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

  /// Право принимать заказы с сайта: включает и выключает только владелец
  /// платформы, и каждому филиалу отдельно. Больше этим запросом в филиале
  /// ничего не меняется — остальные поля кафе правит у себя само.
  /// Выключение мгновенно убирает кнопку у гостей и закрывает приём, а
  /// номер WhatsApp остаётся: вернём право — набирать заново не придётся
  Future<Response> _updateBranchOrders(Request req, String id) async {
    _superadmin(req);
    final rows = db.select('select id from branches where id = ?', [id]);
    if (rows.isEmpty) throw ApiError(404, 'Филиал не найден');
    final body = await _body(req);
    if (!body.containsKey('orders_enabled')) {
      throw ApiError(400, 'Нечего менять');
    }
    db.execute('update branches set orders_enabled = ? where id = ?', [
      toSql(body['orders_enabled'] == true),
      id,
    ]);
    return _json(
      _out(req, db.select('select * from branches where id = ?', [id]).first),
    );
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

Response _html(String body, {int status = 200}) => Response(
  status,
  body: body,
  headers: {
    'content-type': 'text/html; charset=utf-8',
    // Меню меняется — поисковик и браузер перечитывают через 10 минут
    'cache-control': 'public, max-age=600',
  },
);

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
