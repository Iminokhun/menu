import 'package:web/web.dart' as web;

/// Новая вкладка без доступа к нашей странице (`noopener`): сайт карты
/// не сможет ни подменить меню, ни узнать, откуда пришёл гость.
void openLink(String url) {
  web.window.open(url, '_blank', 'noopener,noreferrer');
}
