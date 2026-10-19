import 'dart:convert';

import 'package:http/http.dart' as http;

/// Адрес API. Админка раздаётся тем же сервером, что и API, поэтому по
/// умолчанию это адрес открытой страницы — при смене домена пересобирать
/// не нужно. Для разработки: `--dart-define=API_URL=http://localhost:8090`.
final serverUrl = const String.fromEnvironment('API_URL').isNotEmpty
    ? const String.fromEnvironment('API_URL')
    : Uri.base.origin;

/// Ошибка от сервера. [message] уже написан для человека — его можно
/// показывать в SnackBar как есть.
class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);

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

  Me({
    required this.id,
    required this.login,
    required this.role,
    this.cafeId,
    this.cafeName = '',
    this.maxBranches = 0,
    this.branchCount = 0,
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
      maxBranches: (cafe?['max_branches'] as int?) ?? 0,
      branchCount: (cafe?['branch_count'] as int?) ?? 0,
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

  bool get isSignedIn => _token != null;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$serverUrl$path').replace(queryParameters: query);

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (_token != null) 'authorization': 'Bearer $_token',
      };

  dynamic _decode(http.Response res) {
    final text = utf8.decode(res.bodyBytes);
    final body = text.isEmpty ? null : jsonDecode(text);
    if (res.statusCode >= 400) {
      final msg = body is Map && body['error'] is String
          ? body['error'] as String
          : 'Ошибка сервера (${res.statusCode})';
      throw ApiException(res.statusCode, msg);
    }
    return body;
  }

  Future<dynamic> get(String path, [Map<String, String>? query]) async =>
      _decode(await http.get(_uri(path, query), headers: _headers));

  Future<dynamic> post(String path, [Object? body]) async =>
      _decode(await http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? {})));

  Future<dynamic> patch(String path, Object body) async =>
      _decode(await http.patch(_uri(path), headers: _headers, body: jsonEncode(body)));

  Future<dynamic> delete(String path) async =>
      _decode(await http.delete(_uri(path), headers: _headers));

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
}

final api = ApiClient.instance;
