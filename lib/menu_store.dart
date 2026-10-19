import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'models/branch.dart';
import 'models/product.dart';

/// Меню филиала вместе с тем, откуда оно взято.
class MenuData {
  final Branch branch;

  /// Категории (isGroup) и блюда одним плоским списком
  final List<Product> items;

  /// Когда меню получено с сервера
  final DateTime savedAt;

  /// Показана сохранённая копия: свежее меню получить не удалось
  final bool fromCache;

  const MenuData({
    required this.branch,
    required this.items,
    required this.savedAt,
    required this.fromCache,
  });
}

enum MenuResult {
  /// Свежее меню с сервера
  fresh,

  /// Нет связи, показана сохранённая копия
  offline,

  /// Нет связи и копии на устройстве нет — показывать нечего
  offlineNoCache,

  /// Филиала больше нет или кафе заблокировано
  notFound,

  /// Меню кафе не оплачено — гостю показывается «Меню временно недоступно»
  unpaid,
}

/// Единственное место, откуда экраны гостя берут меню.
///
/// Каждое удачное обновление сохраняется на устройстве, поэтому без
/// интернета показывается последнее меню, а не пустой экран. Свежее меню
/// берётся при запуске и по кнопке «Обновить» — сам по себе экран сеть
/// не дёргает.
class MenuStore {
  final data = ValueNotifier<MenuData?>(null);
  final refreshing = ValueNotifier<bool>(false);

  /// Чем закончилось последнее обновление; null — ещё не обновлялись
  final status = ValueNotifier<MenuResult?>(null);

  String? _slug;
  String? get slug => _slug;

  static String _key(String slug) => 'menu_cache_${slug.toLowerCase()}';

  /// Открыть филиал: сохранённая копия показывается сразу, свежее меню
  /// догружается следом. Без копии — ждём сервер.
  Future<void> open(String slug) async {
    _slug = slug;
    data.value = await _readCache(slug);
    if (data.value != null) {
      unawaited(refresh());
    } else {
      await refresh();
    }
  }

  Future<MenuResult>? _inFlight;

  /// Повторное нажатие «Обновить», пока идёт обновление, ждёт то же самое,
  /// а не запускает второе.
  Future<MenuResult> refresh() => _inFlight ??= _refresh().whenComplete(() => _inFlight = null);

  Future<MenuResult> _refresh() async {
    final slug = _slug;
    if (slug == null) return MenuResult.notFound;
    refreshing.value = true;
    final result = await _fetch(slug);
    if (slug == _slug) status.value = result;
    refreshing.value = false;
    return result;
  }

  Future<MenuResult> _fetch(String slug) async {
    try {
      final branchJson = await api.get('/api/public/branch/${Uri.encodeComponent(slug)}')
          as Map<String, dynamic>;
      final menuJson = await api.get('/api/public/menu/${branchJson['id']}')
          as Map<String, dynamic>;
      final now = DateTime.now();
      // Пока ждали ответ, могли переключить филиал — чужое меню не показываем
      if (slug != _slug) return MenuResult.fresh;
      final fresh = _parse(branchJson, menuJson, now, fromCache: false);
      data.value = fresh;
      await _writeCache(slug, branchJson, menuJson, now);
      _precacheImages(fresh);
      return MenuResult.fresh;
    } on ApiException catch (e) {
      if (e.code == 'unpaid') {
        // Неоплаченное меню не должно жить и в сохранённой копии
        if (slug == _slug) data.value = null;
        await _removeCache(slug);
        return MenuResult.unpaid;
      }
      if (!e.isOffline) {
        // 404: филиал удалён или кафе заблокировано — копию не держим,
        // иначе заблокированное меню показывалось бы вечно
        if (slug == _slug) data.value = null;
        await _removeCache(slug);
        return MenuResult.notFound;
      }
      return _fallBack(slug);
    } catch (e) {
      // Сервер ответил чем-то неожиданным — для гостя это то же, что нет связи
      debugPrint('Меню не обновлено: $e');
      return _fallBack(slug);
    }
  }

  Future<MenuResult> _fallBack(String slug) async {
    if (slug != _slug) return MenuResult.offline;
    final current = data.value;
    final cached = current ?? await _readCache(slug);
    if (cached == null) return MenuResult.offlineNoCache;
    data.value = MenuData(
      branch: cached.branch,
      items: cached.items,
      savedAt: cached.savedAt,
      fromCache: true,
    );
    return MenuResult.offline;
  }

  // ---------------------------------------------------------------- копия

  Future<MenuData?> _readCache(String slug) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(slug));
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return _parse(
        j['branch'] as Map<String, dynamic>,
        j['menu'] as Map<String, dynamic>,
        DateTime.parse(j['saved_at'] as String),
        fromCache: true,
      );
    } catch (e) {
      // Испорченная копия хуже, чем никакой: читаем заново с сервера
      debugPrint('Копия меню не прочитана: $e');
      return null;
    }
  }

  Future<void> _writeCache(
    String slug,
    Map<String, dynamic> branch,
    Map<String, dynamic> menu,
    DateTime at,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key(slug),
        jsonEncode({'branch': branch, 'menu': menu, 'saved_at': at.toIso8601String()}),
      );
    } catch (e) {
      // Не сохранилось (например, переполнено хранилище браузера) — меню
      // всё равно показано, просто без интернета его не будет
      debugPrint('Копия меню не сохранена: $e');
    }
  }

  Future<void> _removeCache(String slug) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(slug));
    } catch (_) {}
  }

  static MenuData _parse(
    Map<String, dynamic> branch,
    Map<String, dynamic> menu,
    DateTime at, {
    required bool fromCache,
  }) =>
      MenuData(
        branch: Branch.fromJson(branch),
        items: [
          ...parseEach(menu['categories'], Product.categoryFromJson),
          ...parseEach(menu['products'], Product.dishFromJson),
        ],
        savedAt: at,
        fromCache: fromCache,
      );

  /// Разбирает каждую строку отдельно: строка, которую не удалось прочитать,
  /// пропускается, а не обнуляет всё меню.
  @visibleForTesting
  static List<Product> parseEach(
    Object? rows,
    Product Function(Map<String, dynamic>) parse,
  ) {
    if (rows is! List) return const [];
    final out = <Product>[];
    for (final row in rows) {
      try {
        out.add(parse(row as Map<String, dynamic>));
      } catch (e) {
        debugPrint('Пропущена строка меню: $e — $row');
      }
    }
    return out;
  }

  /// Фото скачиваются заранее, пока есть сеть: без интернета на планшете
  /// показываются и блюда, которые ещё ни разу не открывали. В браузере
  /// фото и так кэширует сам браузер.
  void _precacheImages(MenuData menu) {
    if (kIsWeb) return;
    final bg = menu.branch.style.bgUrl;
    final urls = {
      menu.branch.logoUrl,
      if (bg != 'none') bg, // фон кафе, 'none' — однотонный
      for (final p in menu.items) p.imageUrl,
    }..remove('');
    for (final url in urls) {
      final stream = CachedNetworkImageProvider(url).resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (_, __) => stream.removeListener(listener),
        onError: (_, __) => stream.removeListener(listener),
      );
      stream.addListener(listener);
    }
  }
}

final menuStore = MenuStore();
