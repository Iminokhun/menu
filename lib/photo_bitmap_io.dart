import 'package:flutter/widgets.dart';

/// На телефоне и компьютере фото разжимает сам движок, и делает это верно —
/// обход не нужен. Всё, что ниже, живёт только в браузере: см.
/// `photo_bitmap_web.dart`.
const bool photoBitmapNeeded = false;

/// Никогда не вызывается: [photoBitmapNeeded] здесь всегда `false`.
ImageProvider photoBitmapImage(String url, int? targetWidth) =>
    throw UnsupportedError('photoBitmapImage бывает только в браузере');
