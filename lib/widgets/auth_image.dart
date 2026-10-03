import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Виджет для отображения изображений из Firebase Storage / Supabase Storage.
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
    if (url.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: Colors.black12,
        child: const Icon(Icons.image_not_supported_outlined, color: Colors.white30),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      placeholder: (context, url) => Container(
        width: width,
        height: height,
        color: Colors.black12,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white30),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        width: width,
        height: height,
        color: Colors.black12,
        child: const Icon(Icons.broken_image_outlined, color: Colors.white30),
      ),
    );
  }
}
