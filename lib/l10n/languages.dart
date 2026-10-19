/// Язык меню, который филиал может включить в админке.
class MenuLanguage {
  /// Код языка: `ru`, `ky`, `en`…
  final String code;

  /// Название на самом языке — так его ищет гость: «Кыргызча», «English».
  final String nativeName;

  /// Название по-русски — для админки кафе.
  final String ruName;

  const MenuLanguage(this.code, this.nativeName, this.ruName);
}

/// Все языки меню. Тот же список — на сервере (server/lib/languages.dart),
/// кнопки меню переведены на каждый (app_localizations.dart).
const menuLanguages = [
  MenuLanguage('ru', 'Русский', 'Русский'),
  MenuLanguage('ky', 'Кыргызча', 'Кыргызский'),
  MenuLanguage('kk', 'Қазақша', 'Казахский'),
  MenuLanguage('uz', 'Oʻzbekcha', 'Узбекский'),
  MenuLanguage('en', 'English', 'Английский'),
  MenuLanguage('tr', 'Türkçe', 'Турецкий'),
  MenuLanguage('zh', '中文', 'Китайский'),
  MenuLanguage('ko', '한국어', 'Корейский'),
  MenuLanguage('ja', '日本語', 'Японский'),
  MenuLanguage('de', 'Deutsch', 'Немецкий'),
  MenuLanguage('fr', 'Français', 'Французский'),
  MenuLanguage('es', 'Español', 'Испанский'),
];

/// Язык по коду; неизвестный код (из будущей версии сервера) — null.
MenuLanguage? menuLanguage(String code) {
  for (final l in menuLanguages) {
    if (l.code == code) return l;
  }
  return null;
}
