/// Разжатие фото: в Safari и Firefox — своё, в остальных браузерах и на
/// телефоне — штатное, движком.
library;

export 'photo_bitmap_io.dart'
    if (dart.library.js_interop) 'photo_bitmap_web.dart';
