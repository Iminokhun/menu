/// Настройки выбора файла, зависящие от платформы: в браузере — свои,
/// на телефоне и компьютере — пустые.
library;

export 'picker_options_io.dart'
    if (dart.library.js_interop) 'picker_options_web.dart';
