import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/product.dart';
import '../../theme/theme_config.dart';
import 'live_photo_frame_io.dart'
    if (dart.library.js_interop) 'live_photo_frame_web.dart';

/// «Живое фото» блюда на весь экран: обычное фото объёмно наклоняется
/// за пальцем или за наклоном телефона. Настоящей 3D-модели не нужно —
/// работает для любого блюда с фото. Тестовая версия.
class LivePhotoView extends StatelessWidget {
  final Product product;
  final String title;
  final ThemeConfig config;

  const LivePhotoView({
    super.key,
    required this.product,
    required this.title,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    final bg = '#${(config.bg.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    return Scaffold(
      backgroundColor: config.bg,
      appBar: AppBar(
        backgroundColor: config.surface,
        foregroundColor: config.text,
        title: Text(
          title,
          style: config.titleStyle(fontWeight: FontWeight.w700, color: config.text),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: LivePhotoFrame(imageUrl: product.imageUrl, background: bg)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Text(
              'Ведите пальцем или наклоните телефон',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: config.text.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
