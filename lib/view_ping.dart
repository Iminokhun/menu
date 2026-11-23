/// Отметка о том, что гость открыл меню филиала.
///
/// Нужна она одному человеку — владельцу платформы: в админке `/menu-kg/`
/// по ней видно, сколько людей за день заходило в меню каждого кафе и
/// каждого филиала. Кафе этих цифр не видит.
///
/// **Почему метка устройства, а не адрес в сети.** В кафе весь зал сидит в
/// одном Wi-Fi и приходит с одного адреса — по адресу «люди» не считаются
/// (тот же довод, что у [reviewsPerWindow] в `review/review_once.dart`). А
/// на рабочем сервере адрес и вовсе не гостя: запрос идёт через Cloudflare,
/// и сервер видит адрес её края. Поэтому приложение один раз придумывает
/// себе случайную строку и присылает её с каждой отметкой: сервер по ней
/// только отличает одного гостя от другого за один день, и всё.
///
/// Метка не связана ни с заказом, ни с отзывом, ни с номером телефона, и
/// по ней нельзя узнать о госте ничего. Цена честная: сменил устройство или
/// очистил браузер — считаешься новым человеком.
library;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';

const _key = 'view_device';

final _rnd = Random.secure();

/// Метка этого устройства, пока приложение не закрыли
String? _device;

/// Такой же вид, как у id на сервере (`newId`), — чтобы в журнале и в базе
/// метка не выглядела чужеродной
String _newDevice() {
  final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
  return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}

Future<String> _deviceId() async {
  final known = _device;
  if (known != null) return known;
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null && saved.isNotEmpty) return _device = saved;
    final fresh = _newDevice();
    await prefs.setString(_key, fresh);
    return _device = fresh;
  } catch (_) {
    // Хранилище недоступно (приватное окно, запрет на куки) — метка живёт
    // до перезагрузки страницы. Такой гость посчитается ещё раз; это лучше,
    // чем не посчитать его вовсе
    return _device = _newDevice();
  }
}

/// Засчитать открытие меню филиала [slug].
///
/// Ничего не ждёт и ничего не показывает: нет сети или сервер ответил
/// ошибкой — просмотр просто не засчитан. Гостю об этом знать нечего, а
/// меню он читает из сохранённой копии.
Future<void> pingView(String slug) async {
  // Вошедший в админку — это кафе, а не гость. Хозяин, переключающий
  // филиалы у себя в админке, иначе добавлял бы себе «посетителей»
  if (api.isSignedIn) return;
  try {
    await api.post('/api/public/view', {
      'slug': slug,
      'device': await _deviceId(),
    });
  } catch (_) {
    // Отметка — побочное дело, падать из-за неё нельзя нигде
  }
}

/// Забыть метку (между проверками)
@visibleForTesting
void forgetViewDevice() => _device = null;
