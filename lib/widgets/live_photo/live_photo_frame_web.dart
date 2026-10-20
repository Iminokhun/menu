import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// В браузере страница «живого фото» встраивается как iframe: это обычный
/// файл приложения (assets/live_photo/live_photo.html) рядом с Three.js.
class LivePhotoFrame extends StatefulWidget {
  final String imageUrl;
  final String background;

  const LivePhotoFrame({super.key, required this.imageUrl, required this.background});

  @override
  State<LivePhotoFrame> createState() => _LivePhotoFrameState();
}

class _LivePhotoFrameState extends State<LivePhotoFrame> {
  late final String _viewType = 'live-photo-${identityHashCode(this)}';
  web.HTMLIFrameElement? _frame;

  @override
  void initState() {
    super.initState();
    final src = 'assets/assets/live_photo/live_photo.html'
        '?img=${Uri.encodeQueryComponent(widget.imageUrl)}'
        '&bg=${widget.background.replaceFirst('#', '')}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      return _frame = web.HTMLIFrameElement()
        ..src = src
        // наклон телефона внутри iframe разрешается явно
        ..allow = 'accelerometer; gyroscope'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
    });
  }

  @override
  void dispose() {
    // Как и в приложении: WebGL страницы отпускается сразу, а не когда
    // браузер соберёт убранный iframe. Страница могла ещё не загрузиться —
    // тогда останавливать нечего
    final page = _frame?.contentWindow as JSObject?;
    if (page != null && page.has('stopLivePhoto')) {
      page.callMethod<JSAny?>('stopLivePhoto'.toJS);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
