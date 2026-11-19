/// Телефоны заказа: номер кафе и номер гостя.
///
/// Те же правила повторены на клиенте, в `lib/order/order_message.dart` —
/// приложение не может импортировать код сервера. Обе стороны проверяются
/// одной таблицей примеров (`server/tool/order_test.dart` и
/// `test/order_message_test.dart`), чтобы они не разошлись молча.
library;

final _digits = RegExp(r'\D');

/// Номер кафе, куда уходят заказы, в международном виде: `996555112233`.
/// Ровно это значение подставляется в ссылку `wa.me`.
///
/// Строго: `null` — номер не распознан, сохранять нельзя. Неверно угаданный
/// код страны увёл бы **все** заказы кафе на чужой телефон, и этого никто бы
/// не заметил, поэтому домысливать здесь нечего — кроме ведущего нуля, и то
/// лишь когда код страны задан явно, через `DEFAULT_COUNTRY_CODE`.
///
/// Пустая строка на входе даёт пустую на выходе: так кафе выключает заказы.
String? normalizeWaPhone(String raw, {String defaultCountryCode = ''}) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  // Международная запись: +996…, 00996… — и то и другое значит одно
  if (s.startsWith('+')) s = s.substring(1);
  var d = s.replaceAll(_digits, '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.startsWith('0') && defaultCountryCode.isNotEmpty) {
    d = defaultCountryCode + d.substring(1);
  }
  if (d.length < 10 || d.length > 15 || d.startsWith('0')) return null;
  return d;
}

/// Номер гостя — по нему кафе перезвонит. Мягко: принимается и местная
/// запись `0555112233`.
///
/// Нестрогость намеренная. Этот номер набирает человек, который сам
/// разберётся с кодом страны, а отказ на оформлении заказа из-за привычной
/// записи — это потерянный заказ.
String? cleanGuestPhone(String raw) {
  final d = raw.replaceAll(_digits, '');
  if (d.length < 9 || d.length > 15) return null;
  return d;
}
