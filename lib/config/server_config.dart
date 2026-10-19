import 'package:flutter/foundation.dart';

const _apiUrl = String.fromEnvironment('API_URL');

/// Адрес API-сервера меню.
///
/// - Задан при сборке (`--dart-define=API_URL=https://menu.kg`) — он.
///   Так собирается APK: у приложения на планшете нет «своего» адреса.
/// - Сайт меню в рабочей сборке — адрес открытой страницы: сайт раздаёт
///   тот же сервер, поэтому при смене домена пересобирать не нужно.
/// - Разработка (`flutter run`) — локальный сервер.
final String serverUrl = _apiUrl.isNotEmpty
    ? _apiUrl
    : kIsWeb && kReleaseMode
        ? Uri.base.origin
        : 'http://localhost:8090';
