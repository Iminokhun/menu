import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/server_config.dart';
import '../models/json_read.dart';

/// Ошибка от сервера. [message] уже написан для человека — его можно
/// показывать в SnackBar как есть.
class ApiException implements Exception {
  /// HTTP-код ответа; [noConnection] — сервер не ответил вовсе.
  final int status;
  final String message;

  /// Машинная метка от сервера, например `unpaid`
  final String? code;
  ApiException(this.status, this.message, {this.code});

  static const noConnection = 0;

  /// Сервер недоступен: нет сети, не ответил вовремя или сам сломан.
  /// В отличие от 4xx, это не повод забывать сохранённое меню.
  bool get isOffline => status == noConnection || status >= 500;

  @override
  String toString() => message;
}

/// Кто вошёл: главный администратор платформы или администратор кафе.
class Me {
  final String id;
  final String login;
  final String role;
  final String? cafeId;
  final String cafeName;
  final int maxBranches;
  final int branchCount;

  /// Адрес сайта с меню для гостей, например `https://menu.kg`.
  /// Из него собирается ссылка QR-кода филиала.
  final String menuUrl;

  /// Оплата: тариф (trial / paid / lifetime), «оплачено до» (ГГГГ-ММ-ДД),
  /// статус (ok / ending / grace / expired) и сколько дней осталось
  final String plan;
  final String paidUntil;
  final String access;
  final int? daysLeft;

  /// Через сколько дней меню у гостей выключится, если не оплатить
  final int? menuOffIn;

  /// Кому платить за меню — задаёт владелец платформы
  final String billingContact;

  Me({
    required this.id,
    required this.login,
    required this.role,
    this.cafeId,
    this.cafeName = '',
    this.maxBranches = 0,
    this.branchCount = 0,
    this.menuUrl = '',
    this.plan = '',
    this.paidUntil = '',
    this.access = 'ok',
    this.daysLeft,
    this.menuOffIn,
    this.billingContact = '',
  });

  bool get isSuper => role == 'superadmin';

  factory Me.fromJson(Map<String, dynamic> j) {
    final cafe = j['cafe'] as Map<String, dynamic>?;
    return Me(
      id: j['id'] as String,
      login: j['login'] as String,
      role: j['role'] as String,
      cafeId: cafe?['id'] as String?,
      cafeName: (cafe?['name'] as String?) ?? '',
      maxBranches: jsonInt(cafe?['max_branches']),
      branchCount: jsonInt(cafe?['branch_count']),
      menuUrl: (j['menu_url'] as String?) ?? '',
      plan: jsonStr(cafe?['plan']),
      paidUntil: jsonStr(cafe?['paid_until']),
      access: jsonStr(cafe?['access'], 'ok'),
      daysLeft: cafe?['days_left'] is num ? jsonInt(cafe?['days_left']) : null,
      menuOffIn: cafe?['menu_off_in'] is num ? jsonInt(cafe?['menu_off_in']) : null,
      billingContact: jsonStr(cafe?['billing_contact']),
    );
  }
}

/// Единственная точка общения с сервером.
///
/// Токен держится только в памяти: пароль спрашивается при каждом входе
/// в админку, и после перезапуска приложения сессии не остаётся.
class ApiClient {
  ApiClient._();
  static final instance = ApiClient._();

  String? _token;
  Me? me;

  /// Подменяется в тестах заглушкой без сети.
  http.Client httpClient = http.Client();

  static const _timeout = Duration(seconds: 15);

  /// 25 МБ модели по медленному Wi-Fi грузятся дольше обычного запроса
  static const _uploadTimeout = Duration(minutes: 3);

  bool get isSignedIn => _token != null;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$serverUrl$path').replace(queryParameters: query);

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (_token != null) 'authorization': 'Bearer $_token',
      };

  /// Запрос с ограничением по времени. Обрыв сети и молчащий сервер
  /// превращаются в [ApiException] с кодом [ApiException.noConnection]:
  /// иначе зависший запрос крутил бы индикатор загрузки бесконечно.
  Future<dynamic> _send(Future<http.Response> request, [Duration timeout = _timeout]) async {
    final http.Response res;
    try {
      res = await request.timeout(timeout);
    } on TimeoutException {
      throw ApiException(ApiException.noConnection, 'Сервер не отвечает');
    } on http.ClientException {
      throw ApiException(ApiException.noConnection, 'Нет связи с сервером');
    }
    return _decode(res);
  }

  dynamic _decode(http.Response res) {
    Object? body;
    try {
      final text = utf8.decode(res.bodyBytes);
      body = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      // HTML от прокси (413, 502) вместо JSON нашего сервера
      body = null;
      if (res.statusCode < 400) {
        throw ApiException(res.statusCode, 'Сервер прислал непонятный ответ');
      }
    }
    if (res.statusCode >= 400) {
      final msg = body is Map && body['error'] is String
          ? body['error'] as String
          : 'Ошибка сервера (${res.statusCode})';
      throw ApiException(
        res.statusCode,
        msg,
        code: body is Map && body['code'] is String ? body['code'] as String : null,
      );
    }
    return body;
  }

  Future<dynamic> get(String path, [Map<String, String>? query]) =>
      _send(httpClient.get(_uri(path, query), headers: _headers));

  Future<dynamic> post(String path, [Object? body]) =>
      _send(httpClient.post(_uri(path), headers: _headers, body: jsonEncode(body ?? {})));

  Future<dynamic> patch(String path, Object body) =>
      _send(httpClient.patch(_uri(path), headers: _headers, body: jsonEncode(body)));

  Future<dynamic> delete(String path) =>
      _send(httpClient.delete(_uri(path), headers: _headers));

  /// Список строк из ответа — для экранов, которые работают с Map.
  Future<List<Map<String, dynamic>>> list(String path, [Map<String, String>? query]) async =>
      List<Map<String, dynamic>>.from(await get(path, query) as List);

  Future<Me> login(String login, String password) async {
    final r = await post('/api/auth/login', {'login': login, 'password': password});
    _token = r['token'] as String;
    return me = Me.fromJson(r['user'] as Map<String, dynamic>);
  }

  /// Перечитать лимит и число филиалов — после создания или удаления.
  Future<Me> refreshMe() async =>
      me = Me.fromJson(await get('/api/me') as Map<String, dynamic>);

  Future<void> logout() async {
    if (_token == null) return;
    try {
      await post('/api/auth/logout');
    } catch (_) {
      // Нет сети — не страшно: токен живёт только в памяти и сейчас пропадёт
    }
    _token = null;
    me = null;
  }

  /// Загрузка картинки или 3D-модели (.glb). Возвращает полный адрес
  /// файла на сервере.
  Future<String> upload(List<int> bytes, {required String ext, String prefix = ''}) async {
    final res = await _send(
      httpClient.post(
        _uri('/api/admin/upload', {'ext': ext, 'prefix': prefix}),
        headers: {if (_token != null) 'authorization': 'Bearer $_token'},
        body: bytes,
      ),
      _uploadTimeout,
    );
    return (res as Map)['url'] as String;
  }
}

final api = ApiClient.instance;
