import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import 'db.dart';

/// Сессия живёт сутки: админка открывается ненадолго, а планшет в зале
/// не должен держать вход бесконечно.
const sessionLifetime = Duration(hours: 24);

const _iterations = 120000;
final _rnd = Random.secure();

/// PBKDF2-HMAC-SHA256. Формат строки: `pbkdf2$<итерации>$<соль>$<хэш>`,
/// число итераций хранится рядом, чтобы его можно было поднять позже,
/// не ломая уже выданные пароли.
String hashPassword(String password) {
  final salt = Uint8List.fromList(List.generate(16, (_) => _rnd.nextInt(256)));
  final dk = _pbkdf2(utf8.encode(password), salt, _iterations);
  return 'pbkdf2\$$_iterations\$${base64Url.encode(salt)}\$${base64Url.encode(dk)}';
}

bool verifyPassword(String password, String stored) {
  final parts = stored.split('\$');
  if (parts.length != 4 || parts[0] != 'pbkdf2') return false;
  final iterations = int.tryParse(parts[1]);
  if (iterations == null) return false;
  final salt = base64Url.decode(parts[2]);
  final expected = base64Url.decode(parts[3]);
  final actual = _pbkdf2(utf8.encode(password), salt, iterations);
  // Сравнение за постоянное время: по скорости ответа хэш не подобрать
  var diff = expected.length ^ actual.length;
  for (var i = 0; i < min(expected.length, actual.length); i++) {
    diff |= expected[i] ^ actual[i];
  }
  return diff == 0;
}

Uint8List _pbkdf2(List<int> password, List<int> salt, int iterations) {
  final hmac = Hmac(sha256, password);
  final block = Uint8List.fromList([...salt, 0, 0, 0, 1]);
  var u = hmac.convert(block).bytes;
  final out = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }
  }
  return out;
}

String _newToken() {
  final b = List<int>.generate(32, (_) => _rnd.nextInt(256));
  return base64Url.encode(b).replaceAll('=', '');
}

/// Вошедший пользователь, как его видят обработчики API.
class AuthUser {
  final String id;
  final String login;
  final String role;
  final String? cafeId;

  AuthUser(this.id, this.login, this.role, this.cafeId);

  bool get isSuper => role == 'superadmin';
}

String createSession(Database db, String userId) {
  final token = _newToken();
  final expires = DateTime.now().toUtc().add(sessionLifetime).toIso8601String();
  db.execute(
    'insert into sessions (token, user_id, expires_at) values (?, ?, ?)',
    [token, userId, expires],
  );
  // Заодно чистим просроченные, чтобы таблица не росла
  db.execute('delete from sessions where expires_at < ?', [
    DateTime.now().toUtc().toIso8601String(),
  ]);
  return token;
}

/// Пользователь по токену. null — если токена нет, он просрочен,
/// пользователь заблокирован или заблокировано его кафе.
AuthUser? userByToken(Database db, String token) {
  final rows = db.select(
    '''
    select u.id, u.login, u.role, u.cafe_id
      from sessions s
      join users u on u.id = s.user_id
      left join cafes c on c.id = u.cafe_id
     where s.token = ?
       and s.expires_at > ?
       and u.is_active = 1
       and (u.cafe_id is null or c.is_active = 1)
  ''',
    [token, DateTime.now().toUtc().toIso8601String()],
  );
  if (rows.isEmpty) return null;
  final r = rows.first;
  return AuthUser(
    r['id'] as String,
    r['login'] as String,
    r['role'] as String,
    r['cafe_id'] as String?,
  );
}

/// Создаёт пользователя. Пароль короче 6 символов не принимаем.
String createUser(
  Database db, {
  required String login,
  required String password,
  required String role,
  String? cafeId,
}) {
  if (password.length < 6) {
    throw ArgumentError('Пароль должен быть не короче 6 символов');
  }
  final id = newId();
  db.execute(
    'insert into users (id, cafe_id, login, password_hash, role) values (?, ?, ?, ?, ?)',
    [id, cafeId, login.trim(), hashPassword(password), role],
  );
  return id;
}
