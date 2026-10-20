import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// На планшете и телефоне страница «живого фото» открывается во встроенном
/// браузере из файлов приложения — интернет нужен только для самого фото,
/// а оно уже лежит в кэше, если меню открывали.
class LivePhotoFrame extends StatefulWidget {
  final String imageUrl;
  final String background;

  const LivePhotoFrame({super.key, required this.imageUrl, required this.background});

  @override
  State<LivePhotoFrame> createState() => _LivePhotoFrameState();
}

class _LivePhotoFrameState extends State<LivePhotoFrame> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        // Адрес фото передаётся после загрузки страницы: у файла из
        // приложения нет строки запроса, как у iframe в браузере
        onPageFinished: (_) => _controller.runJavaScript(
          'startLivePhoto(${jsonEncode(widget.imageUrl)}, ${jsonEncode(widget.background)})',
        ),
      ))
      ..loadFlutterAsset('assets/live_photo/live_photo.html');
  }

  @override
  void dispose() {
    // Встроенный браузер живёт, пока Dart не соберёт контроллер, и всё это
    // время крутит WebGL и держит фото в памяти. Останавливаем сами и
    // открываем пустую страницу. Страница могла не успеть загрузиться —
    // тогда останавливать нечего, ошибку не показываем
    _controller
        .runJavaScript('window.stopLivePhoto && stopLivePhoto()')
        .whenComplete(() => _controller.loadRequest(Uri.parse('about:blank')))
        .ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
