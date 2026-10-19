import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../models/product.dart';
import '../theme/theme_config.dart';

/// Блюдо в 3D на весь экран: крутится само, гость вращает пальцем и
/// приближает. На телефоне с поддержкой AR появляется кнопка — блюдо
/// ставится на стол через камеру в натуральную величину. Без поддержки
/// AR кнопку `<model-viewer>` просто не показывает.
class Dish3DView extends StatelessWidget {
  final Product product;
  final String title;
  final ThemeConfig config;

  const Dish3DView({
    super.key,
    required this.product,
    required this.title,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
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
      body: Stack(
        children: [
          ModelViewer(
            src: product.modelUrl,
            // Пока модель грузится, видно фото блюда, а не пустой экран
            poster: product.imageUrl.isEmpty ? null : product.imageUrl,
            alt: title,
            backgroundColor: config.bg,
            autoRotate: true,
            cameraControls: true,
            disablePan: true,
            ar: true,
            // Android — Scene Viewer, iPhone — Quick Look (файл для него
            // model-viewer собирает из .glb сам), остальные — WebXR
            arModes: const ['scene-viewer', 'webxr', 'quick-look'],
            arScale: ArScale.fixed,
            shadowIntensity: 1,
            debugLogging: false,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: IgnorePointer(
              child: Text(
                'Вращайте пальцем · приближайте двумя пальцами',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  color: config.text.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
