import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/branch.dart';

/// Текущий филиал. Пока null — меню грузить не из чего, и приложение
/// показывает экран выбора филиала.
///
/// Филиал намеренно не зашит в сборку: иначе на каждый зал нужен был бы
/// свой APK, и обновлять их пришлось бы по отдельности.
final ValueNotifier<Branch?> currentBranch = ValueNotifier(null);

const _prefsKey = 'branch_slug';

/// Филиал из ссылки: `?branch=center`. Так работает веб по QR-коду.
/// На планшете параметра в адресе нет, и возвращается null.
String? branchSlugFromUrl() {
  final slug = Uri.base.queryParameters['branch'];
  return (slug == null || slug.isEmpty) ? null : slug;
}

/// Филиал, выбранный на этом устройстве ранее.
Future<String?> savedBranchSlug() async {
  final prefs = await SharedPreferences.getInstance();
  final slug = prefs.getString(_prefsKey);
  return (slug == null || slug.isEmpty) ? null : slug;
}

Future<void> saveBranchSlug(String slug) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefsKey, slug);
}

/// Ссылка приоритетнее сохранённой настройки: гость, отсканировавший
/// QR-код второго филиала, должен попасть именно туда, даже если на его
/// телефоне когда-то открывался первый.
Future<String?> resolveBranchSlug() async {
  return branchSlugFromUrl() ?? await savedBranchSlug();
}
