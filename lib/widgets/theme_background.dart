import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter/material.dart';

import '../theme/theme_config.dart';

/// Фон меню с дымкой поверх. Фон темы лежит в приложении (`assets/...`),
/// своё фото кафе — на сервере и кэшируется; оба видны без интернета.
class ThemeBackground extends StatelessWidget {
  final ThemeConfig config;

  const ThemeBackground({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final src = config.bgImage;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (src.startsWith('assets/'))
          Image.asset(src, fit: BoxFit.cover)
        else if (src.isNotEmpty)
          CachedNetworkImage(
            imageUrl: src,
            fit: BoxFit.cover,
            // Как у фото блюд (см. AuthImage): иначе фон после возврата
            // с другого экрана в браузере становится чёрным
            imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
            errorWidget: (_, __, ___) => const SizedBox(),
          ),
        ColoredBox(color: config.bgOverlay),
      ],
    );
  }
}
