/// Как заказ попадает к сотруднику кафе.
///
/// Сегодня — ссылкой `wa.me`: гость сам нажимает «Отправить» у себя в
/// WhatsApp. Когда отправку возьмёт на себя сервер, здесь появится второй
/// способ, и корзина с экраном оформления об этом даже не узнают — они
/// знают только [OrderDelivery.canOrder] и [OrderDelivery.submit].
library;

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../models/branch.dart';
import '../models/json_read.dart';
import '../open_link.dart';
import 'order_message.dart';

/// Что ответил сервер на сохранённый заказ.
class OrderReceipt {
  final String id;
  final String code;
  final double itemsTotal;
  final double deliveryTotal;
  final double total;

  /// Сколько блюд успели убрать из меню, пока гость собирал заказ.
  /// Больше нуля — кафе перезвонит, а гостю стоит сказать об этом
  final int missing;

  const OrderReceipt({
    required this.id,
    required this.code,
    required this.itemsTotal,
    required this.deliveryTotal,
    required this.total,
    required this.missing,
  });

  factory OrderReceipt.fromJson(Map<String, dynamic> json) => OrderReceipt(
    id: (json['id'] as String?) ?? '',
    code: (json['code'] as String?) ?? '',
    itemsTotal: jsonDouble(json['items_total']),
    deliveryTotal: jsonDouble(json['delivery_total']),
    total: jsonDouble(json['total']),
    missing: jsonInt(json['missing']),
  );
}

abstract class OrderDelivery {
  const OrderDelivery();

  /// Показывать ли кнопку заказа вообще
  bool get canOrder;

  /// Откроется ли у гостя WhatsApp. От этого зависят надписи на кнопке и
  /// на экране «отправлено»
  bool get opensWhatsapp;

  /// Отправить заказ.
  ///
  /// **Важно:** первое, что делает этот метод, — открывает ссылку, и делает
  /// это синхронно. Вызывать его можно только прямо из обработчика нажатия,
  /// **без единого `await` до него**: Safari открывает окно лишь внутри
  /// жеста пользователя, а после паузы считает его непрошеным и закрывает.
  /// Поэтому возвращённый `Future` ждут уже после — он только про запись на
  /// сервере.
  Future<OrderReceipt?> submit(
    OrderDraft draft, {
    required Branch branch,
    required String lang,
  });

  /// Какой способ подходит филиалу.
  ///
  /// Вне браузера — никакой: `openLink` там заглушка (`open_link_io.dart`),
  /// ссылка не откроется, а кнопка, которая ничего не делает, хуже, чем её
  /// отсутствие.
  static OrderDelivery forBranch(Branch? branch) {
    if (branch == null || !kIsWeb || !branch.canOrderByWhatsapp) {
      return const NoDelivery();
    }
    return WaLinkDelivery(branch.orderWhatsapp);
  }
}

/// Заказы недоступны: не браузер или у филиала не задан номер.
class NoDelivery extends OrderDelivery {
  const NoDelivery();

  @override
  bool get canOrder => false;

  @override
  bool get opensWhatsapp => false;

  @override
  Future<OrderReceipt?> submit(
    OrderDraft draft, {
    required Branch branch,
    required String lang,
  }) async => throw StateError('Заказы в этом филиале не принимаются');
}

/// Открывает у гостя WhatsApp с готовым текстом и параллельно сохраняет
/// заказ на сервере.
class WaLinkDelivery extends OrderDelivery {
  /// Номер кафе, только цифры
  final String phone;

  const WaLinkDelivery(this.phone);

  @override
  bool get canOrder => true;

  @override
  bool get opensWhatsapp => true;

  /// Ссылка на переписку с уже набранным заказом — её же можно открыть
  /// повторно, если окно у гостя заблокировалось.
  String linkFor(OrderDraft draft, Branch branch) =>
      waLink(phone, buildOrderText(draft, branch: branch));

  @override
  Future<OrderReceipt?> submit(
    OrderDraft draft, {
    required Branch branch,
    required String lang,
  }) async {
    // Синхронно и первым делом — см. предупреждение у OrderDelivery.submit
    openLink(linkFor(draft, branch));

    // Запись на сервере — следом и без спешки. Если она не удастся, гость
    // сообщение всё равно отправил, поэтому пугать его нечем: показываем
    // тихое уведомление, а кафе видит заказ в переписке
    try {
      return await _post(draft, branch, lang);
    } on ApiException {
      // Одна попытка повтора: чаще всего это моргнувшая сеть
      try {
        await Future<void>.delayed(const Duration(seconds: 2));
        return await _post(draft, branch, lang);
      } on ApiException {
        return null;
      }
    }
  }

  Future<OrderReceipt> _post(OrderDraft draft, Branch branch, String lang) async {
    final res = await api.post(
      '/api/public/orders',
      draft.toJson(branch.id, lang),
    );
    return OrderReceipt.fromJson(res as Map<String, dynamic>);
  }
}
