import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';

import '../photo_url.dart';
import '../theme/current_theme.dart';

/// Виджет для отображения изображений с сервера меню.
/// Автоматически кэширует на диске, показывает плейсхолдер при загрузке.
class AuthImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;

  const AuthImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    // У блюда нет фото или оно не загрузилось — спокойная заглушка, а не
    // значок «картинка сломана»: гость видит оформленную карточку
    if (url.isEmpty) return _NoPhoto(width: width, height: height);
    return LayoutBuilder(builder: (context, c) => _image(context, c));
  }

  Widget _image(BuildContext context, BoxConstraints c) {
    // Фото разжимается в размер места на экране, а не в полный (1080×1080
    // из 1С — почти 5 МБ памяти на каждое): иначе память кончается
    final w = width ?? c.maxWidth, h = height ?? c.maxHeight;
    final side = [w, h].where((v) => v.isFinite).fold<double>(0, (a, b) => a > b ? a : b);
    final decode = side > 0 ? (side * MediaQuery.devicePixelRatioOf(context)).round() : null;
    return CachedNetworkImage(
      imageUrl: sizedPhotoUrl(url, decode),
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: decode,
      // В браузере фото скачивается и разжимается самим Flutter, как в
      // приложении. По умолчанию (HtmlImage) его разжимает браузер, и фото,
      // которое пролежало под другим экраном, после возврата рисуется чёрным
      imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
      fadeInDuration: const Duration(milliseconds: 220),
      fadeOutDuration: const Duration(milliseconds: 120),
      // Пока грузится — ровный фон без индикатора: в сетке из десятков
      // карточек крутящиеся кружки рябят сильнее, чем помогают
      placeholder: (context, url) => SizedBox(
        width: width,
        height: height,
        child: const ColoredBox(color: Color(0x14FFFFFF)),
      ),
      errorWidget: (context, url, error) => _NoPhoto(width: width, height: height),
    );
  }
}

class _NoPhoto extends StatelessWidget {
  final double? width;
  final double? height;

  const _NoPhoto({this.width, this.height});

  @override
  Widget build(BuildContext context) {
    // На светлой теме — тёмная дымка, на тёмной — светлая: иначе заглушка
    // сливается с фоном
    final ink = appTheme.value.brightness == Brightness.light ? Colors.black : Colors.white;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ink.withValues(alpha: 0.12), ink.withValues(alpha: 0.03)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final side = c.biggest.shortestSide;
          final size = side.isFinite ? (side * 0.32).clamp(16.0, 64.0) : 40.0;
          return Center(
            child: Icon(Icons.restaurant_rounded, size: size, color: ink.withValues(alpha: 0.25)),
          );
        },
      ),
    );
  }
}
