/// Длинная сторона уменьшенной копии фото на сервере меню (thumbWidth в
/// server/lib/media.dart)
const thumbPx = 800;

final _photoName = RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false);

/// Адрес фото под место на экране: если хватает [thumbPx] пикселей —
/// уменьшенная копия с сервера меню (`?w=800`, вдвое легче фото из 1С),
/// иначе само фото. Чужие адреса не меняются: копии делает только наш сервер.
///
/// Копия годится и для места чуть больше неё — до [thumbPx] / 0.8: на
/// плотном экране телефона растяжение на четверть не видно.
String sizedPhotoUrl(String url, int? px) {
  if (px == null || px * 0.8 > thumbPx) return url;
  final uri = Uri.tryParse(url);
  if (uri == null || uri.hasQuery || !uri.path.startsWith('/uploads/')) return url;
  if (!_photoName.hasMatch(uri.path)) return url;
  return '$url?w=$thumbPx';
}
