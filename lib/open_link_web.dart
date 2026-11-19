import 'package:web/web.dart' as web;

/// Открываем ссылку так же, как её открыл бы сам гость: создаём обычную
/// ссылку с `target="_blank"` и нажимаем её.
///
/// Раньше здесь был `window.open(url, '_blank', 'noopener,noreferrer')`.
/// Третий довод — список параметров окна — переводит браузер в режим
/// «всплывающее окно»: Safari на айфоне открывает пустую вкладку
/// `about:blank`, а саму карту показывает отдельно, и пустая вкладка
/// остаётся висеть у гостя. Нажатие по ссылке такого режима не включает.
///
/// `rel="noopener noreferrer"` сохраняет то, ради чего были эти параметры:
/// сайт карты не получит доступ к нашей странице и не узнает, откуда
/// пришёл гость.
///
/// Открытие обязано быть мгновенным, без единого `await` до него: иначе
/// браузер считает новую вкладку непрошеной и блокирует её. На этом же
/// держится отправка заказа в WhatsApp (см. `order_delivery.dart`).
void openLink(String url) {
  if (url.isEmpty) return;
  final link =
      web.document.createElement('a') as web.HTMLAnchorElement
        ..href = url
        ..target = '_blank'
        ..rel = 'noopener noreferrer';
  // В документе ссылка живёт один миг — ровно на время нажатия: без него
  // часть браузеров нажатие по оторванному элементу не обрабатывает
  link.style.display = 'none';
  web.document.body?.appendChild(link);
  link.click();
  link.remove();
}
