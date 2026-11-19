/// Сообщение о заказе, которое гость отправляет сотруднику в WhatsApp.
///
/// Тексты здесь **не** переводятся через `AppLocalizations`: та привязана к
/// языку гостя, а читает сообщение сотрудник кафе. Поэтому подписи берутся
/// по основному языку филиала, а названия блюд — из `product.name`, то есть
/// тоже на языке кафе. Иначе в Бишкек пришёл бы заказ по-корейски.
///
/// Вид сообщения закреплён золотым тестом (`test/order_message_test.dart`):
/// когда отправку возьмёт на себя сервер, его текст должен совпасть с этим
/// слово в слово.
library;

import 'dart:math';

import '../models/branch.dart';
import '../models/product.dart';

/// Как гость забирает заказ.
enum OrderType {
  delivery,
  pickup;

  /// Как это называется в запросе к серверу
  String get wire => name;
}

/// Заказ, собранный на экране оформления.
class OrderDraft {
  /// Короткий код: он попадает и в сообщение, и в запись на сервере —
  /// по нему кафе находит заказ, а сервер отбрасывает повторы
  final String code;
  final OrderType type;
  final String name;
  final String phone;

  /// Пусто при самовывозе
  final String address;
  final String comment;
  final List<CartItem> cart;

  /// Стоимость доставки на момент оформления. Сервер посчитает её заново
  final double deliveryPrice;

  const OrderDraft({
    required this.code,
    required this.type,
    required this.name,
    required this.phone,
    required this.cart,
    this.address = '',
    this.comment = '',
    this.deliveryPrice = 0,
  });

  bool get isDelivery => type == OrderType.delivery;

  double get itemsTotal => cartTotal(cart);

  /// Доставка считается только при доставке и только если она не бесплатна
  double get deliveryTotal => isDelivery ? deliveryPrice : 0;

  double get total => itemsTotal + deliveryTotal;

  /// Тело запроса `POST /api/public/orders`. Денег здесь нет намеренно —
  /// все суммы считает сервер по своей базе.
  Map<String, Object?> toJson(String branchId, String lang) => {
    'branch_id': branchId,
    'code': code,
    'order_type': type.wire,
    'name': name,
    'phone': phone,
    'address': address,
    'comment': comment,
    'lang': lang,
    'items': orderItemsJson(cart),
  };
}

/// Позиции заказа для сервера: что заказали и сколько, без цен.
List<Map<String, Object?>> orderItemsJson(List<CartItem> cart) => [
  for (final i in cart)
    {
      'product_id': i.product.id,
      'portion': i.portion?.name ?? '',
      'qty': i.quantity,
      // Пригодится, только если блюдо успели убрать из меню: тогда сотрудник
      // всё равно увидит, что просили
      'name': i.product.name,
    },
];

final _digits = RegExp(r'\D');

/// Номер кафе, куда уходят заказы, в международном виде: `996555112233`.
///
/// Строго: `null` — номер не распознан. Неверно угаданный код страны увёл бы
/// **все** заказы кафе на чужой телефон, и этого никто бы не заметил.
/// Ведущий ноль дополняется только когда код страны задан явно.
///
/// Повторяет `server/lib/order.dart`: приложение не может импортировать код
/// сервера, поэтому обе стороны проверяются одной таблицей примеров.
String? normalizeWaPhone(String raw, {String defaultCountryCode = ''}) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  if (s.startsWith('+')) s = s.substring(1);
  var d = s.replaceAll(_digits, '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.startsWith('0') && defaultCountryCode.isNotEmpty) {
    d = defaultCountryCode + d.substring(1);
  }
  if (d.length < 10 || d.length > 15 || d.startsWith('0')) return null;
  return d;
}

/// Номер гостя — по нему кафе перезвонит. Мягко: местная запись
/// `0555112233` тоже принимается.
///
/// Нестрогость намеренная: этот номер набирает человек, который сам
/// разберётся с кодом страны, а отказ на оформлении — потерянный заказ.
String? cleanGuestPhone(String raw) {
  final d = raw.replaceAll(_digits, '');
  if (d.length < 9 || d.length > 15) return null;
  return d;
}

/// Код заказа из четырёх знаков, без похожих друг на друга (`0` и `O`,
/// `1` и `I`): его диктуют по телефону.
const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
final _random = Random();

String newOrderCode() =>
    List.generate(4, (_) => _codeAlphabet[_random.nextInt(_codeAlphabet.length)])
        .join();

/// Ссылка, которая открывает WhatsApp с уже набранным сообщением.
///
/// Только `https://wa.me/...`: `whatsapp://` не открывается в браузере на
/// компьютере, а `api.whatsapp.com/send` — лишний переход без пользы.
String waLink(String phoneDigits, String text) =>
    'https://wa.me/$phoneDigits?text=${Uri.encodeComponent(text)}';

/// Длиннее этого ссылки начинают теряться по дороге, особенно на айфоне.
/// Полный состав заказа всё равно сохранён на сервере
const _maxTextLength = 1500;

/// Подписи на языке сотрудника. Чего нет — по-русски: меню кафе может быть
/// хоть на японском, но заказ читает тот, кто стоит на кухне.
const _labels = <String, Map<String, String>>{
  'ru': {
    'order': 'Заказ',
    'delivery': 'ДОСТАВКА',
    'pickup': 'САМОВЫВОЗ',
    'name': 'Имя',
    'phone': 'Телефон',
    'address': 'Адрес',
    'pickupFrom': 'Забрать',
    'items': 'Блюда',
    'deliveryCost': 'Доставка',
    'total': 'Итого',
    'comment': 'Комментарий',
    'more': 'и ещё %d позиций',
    'som': 'с.',
  },
  'en': {
    'order': 'Order',
    'delivery': 'DELIVERY',
    'pickup': 'PICKUP',
    'name': 'Name',
    'phone': 'Phone',
    'address': 'Address',
    'pickupFrom': 'Pick up at',
    'items': 'Items',
    'deliveryCost': 'Delivery',
    'total': 'Total',
    'comment': 'Comment',
    'more': 'and %d more items',
    'som': 'som',
  },
  'ky': {
    'order': 'Заказ',
    'delivery': 'ЖЕТКИРҮҮ',
    'pickup': 'ӨЗҮ АЛЫП КЕТЕТ',
    'name': 'Аты',
    'phone': 'Телефон',
    'address': 'Дарек',
    'pickupFrom': 'Алып кетүү',
    'items': 'Тамактар',
    'deliveryCost': 'Жеткирүү',
    'total': 'Баары',
    'comment': 'Эскертүү',
    'more': 'жана дагы %d позиция',
    'som': 'сом',
  },
  'tr': {
    'order': 'Sipariş',
    'delivery': 'TESLİMAT',
    'pickup': 'GEL AL',
    'name': 'İsim',
    'phone': 'Telefon',
    'address': 'Adres',
    'pickupFrom': 'Teslim yeri',
    'items': 'Yemekler',
    'deliveryCost': 'Teslimat',
    'total': 'Toplam',
    'comment': 'Not',
    'more':'ve %d ürün daha',
    'som': 'som',
  },
};

Map<String, String> _labelsFor(String language) =>
    _labels[language] ?? _labels['ru']!;

/// Сумма без лишнего хвоста: 640, но 640.5 так и останется.
String _money(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

/// Жирный в WhatsApp — звёздочки вокруг текста.
///
/// Выделяем только две вещи: адрес доставки и итог. Выделить больше — значит
/// не выделить ничего. Звёздочки видны как есть, если текст вставить не в
/// WhatsApp (например, в кассовую программу), — цена за то, что курьер не
/// промахивается мимо адреса.
String _bold(String s) => '*$s*';

/// Текст заказа для WhatsApp.
///
/// Сообщение читают с телефона, на ходу, в потоке других переписок, поэтому
/// оно разбито пустыми строками на пять блоков: шапка, гость, состав, суммы,
/// хвост. Главное — чтобы адрес не слипался со списком блюд: курьер ищет
/// глазами одну строку, а не вычитывает абзац.
///
/// Порядок блоков не случайный:
/// - филиал первой строкой: у сотрудника может быть несколько точек, и в
///   списке переписок видно именно начало сообщения;
/// - способ получения заглавными сразу под кодом — это первое, что решает
///   сотрудник: собрать курьеру или отложить на стойку;
/// - контакты гостя выше состава: если что-то не так, звонят сразу;
/// - «Блюда» и «Доставка» отдельными строками появляются, только когда
///   доставка платная, иначе три строки вместо одной — лишний шум;
/// - комментарий последним: длинный комментарий не должен вытолкнуть состав
///   и сумму из уведомления на телефоне.
///
/// Без эмодзи и с латинской `x` вместо `×`: и то, и другое ломается при
/// вставке в кассовую программу. Про звёздочки жирного — см. [_bold].
String buildOrderText(OrderDraft draft, {required Branch branch}) {
  final l = _labelsFor(branch.mainLanguage);
  final som = l['som']!;
  String money(double v) => '${_money(v)} $som';

  final head = <String>[
    branch.name,
    '${l['order']} ${draft.code}',
    draft.isDelivery ? l['delivery']! : l['pickup']!,
  ];

  final guest = <String>[
    '${l['name']}: ${draft.name}',
    '${l['phone']}: ${draft.phone}',
    if (draft.isDelivery)
      '${l['address']}: ${_bold(draft.address)}'
    else
      // Адрес кафе жирным не выделяем: гость едет к сотруднику, а не наоборот
      '${l['pickupFrom']}: ${branch.name}'
          '${branch.address.isEmpty ? '' : ' — ${branch.address}'}',
  ];

  final lines = <String>[
    for (final i in draft.cart)
      '${i.quantity} x ${i.product.name}'
      '${i.portion == null ? '' : ' (${i.portion!.name})'}'
      ' — ${money(i.price * i.quantity)}',
  ];

  final sums = <String>[
    if (draft.deliveryTotal > 0) ...[
      '${l['items']}: ${money(draft.itemsTotal)}',
      '${l['deliveryCost']}: ${money(draft.deliveryTotal)}',
    ],
    _bold('${l['total']}: ${money(draft.total)}'),
  ];

  final tail = <String>[
    if (draft.comment.isNotEmpty) '${l['comment']}: ${draft.comment}',
  ];

  // Длинный заказ обрезаем по списку блюд, а не по концу: суммы и контакты
  // нужнее, чем сорок первая позиция
  var kept = lines.length;
  String join() => [
    head,
    guest,
    [
      ...lines.take(kept),
      if (kept < lines.length)
        l['more']!.replaceAll('%d', '${lines.length - kept}'),
    ],
    sums,
    tail,
  ].where((block) => block.isNotEmpty).map((b) => b.join('\n')).join('\n\n');
  var text = join();
  while (text.length > _maxTextLength && kept > 1) {
    kept--;
    text = join();
  }
  return text;
}
