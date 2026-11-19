import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../l10n/translation_service.dart';
import '../menu_store.dart';
import '../models/branch.dart';
import '../models/product.dart';
import '../open_link.dart';
import '../order/order_delivery.dart';
import '../order/order_message.dart';
import '../theme/current_theme.dart';
import '../theme/theme_config.dart';

/// Оформление заказа: доставка или самовывоз, контакты гостя и отправка.
///
/// Отдельной шторкой, а не полями в корзине: корзина занимает 85% высоты и
/// держит внутри список — клавиатура закрыла бы кнопку, а пять полей сверху
/// вытолкнули бы блюда с экрана телефона.
class CheckoutSheet extends StatefulWidget {
  final Branch branch;
  final OrderDelivery delivery;

  const CheckoutSheet({
    super.key,
    required this.branch,
    required this.delivery,
  });

  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _comment = TextEditingController();

  OrderType _type = OrderType.delivery;
  String? _nameError;
  String? _phoneError;
  String? _addressError;

  /// Заказ отправлен — показываем подтверждение вместо формы
  bool _sent = false;

  /// Что сказать гостю после ответа сервера: ничего, или что часть блюд
  /// пропала, или что доставка подорожала
  String? _notice;

  /// Ссылка на переписку: её можно открыть ещё раз, если окно заблокировали
  String? _lastLink;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _comment.dispose();
    super.dispose();
  }

  bool get _isDelivery => _type == OrderType.delivery;

  double get _deliveryTotal =>
      _isDelivery ? widget.branch.deliveryPrice : 0;

  /// Отправка заказа.
  ///
  /// **Не `async` и без единого `await`**: ссылку в WhatsApp надо открыть
  /// внутри самого нажатия, иначе Safari сочтёт окно непрошеным и не
  /// откроет его. Всё, что требует ожидания, живёт в `then` ниже.
  void _submit() {
    final cart = globalCart.value;
    if (cart.isEmpty) return;
    final l = AppLocalizations.of(context);

    final name = _name.text.trim();
    final phone = cleanGuestPhone(_phone.text);
    final address = _address.text.trim();
    setState(() {
      _nameError = name.isEmpty ? l.guestNameRequired : null;
      _phoneError = phone == null ? l.guestPhoneRequired : null;
      _addressError = _isDelivery && address.isEmpty
          ? l.deliveryAddressRequired
          : null;
    });
    if (_nameError != null || _phoneError != null || _addressError != null) {
      return;
    }

    final draft = OrderDraft(
      code: newOrderCode(),
      type: _type,
      name: name,
      phone: phone!,
      address: _isDelivery ? address : '',
      comment: _comment.text.trim(),
      cart: List.of(cart),
      deliveryPrice: widget.branch.deliveryPrice,
    );
    final delivery = widget.delivery;
    if (delivery is WaLinkDelivery) {
      _lastLink = delivery.linkFor(draft, widget.branch);
    }

    HapticFeedback.lightImpact();
    // Здесь ссылка и открывается — внутри submit, первой же строкой
    final saving = delivery.submit(
      draft,
      branch: widget.branch,
      lang: currentLocale.value.languageCode,
    );

    globalCart.value = [];
    setState(() => _sent = true);

    unawaited(
      saving.then(
        (receipt) => _onSaved(receipt, draft),
        onError: (_) => _onSaved(null, draft),
      ),
    );
  }

  /// Ответ сервера приходит уже после того, как гость ушёл в WhatsApp, и
  /// ничего отменить не может — только дополнить подсказкой.
  void _onSaved(OrderReceipt? receipt, OrderDraft draft) {
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    String? notice;
    if (receipt == null) {
      notice = l.orderFailed;
    } else if (receipt.missing > 0) {
      // Меню у гостя отстало от кафе — подтянем его на будущее
      unawaited(menuStore.refresh());
      notice = l.orderSomeGone;
    } else if ((receipt.total - draft.total).abs() > 0.01) {
      // Сверяем именно итог, а не одну доставку: цена блюда или порции
      // могла измениться, пока гость заполнял форму, и тогда в сообщении
      // у него одна сумма, а в кафе другая. Меню на устройстве к тому же
      // могло быть из кэша и вовсе устареть
      unawaited(menuStore.refresh());
      notice = l.orderTotalChanged.replaceAll(
        '%s',
        '${money(receipt.total)} ${l.som}',
      );
    }
    if (notice != null) setState(() => _notice = notice);
  }

  void _openAgain() {
    final link = _lastLink;
    if (link != null) openLink(link);
  }

  @override
  Widget build(BuildContext context) {
    final config = appTheme.value;
    final l = AppLocalizations.of(context);
    return Padding(
      // Чтобы клавиатура не закрывала поля и кнопку
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: config.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border.all(color: config.accent.withValues(alpha: 0.3)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(25, 20, 25, 25),
            child: _sent
                ? _done(config, l)
                : _form(config, l),
          ),
        ),
      ),
    );
  }

  Widget _title(ThemeConfig config, String text) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Expanded(
        child: Text(
          text,
          style: GoogleFonts.cormorantGaramond(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: config.accent,
          ),
        ),
      ),
      IconButton(
        onPressed: () => Navigator.pop(context),
        icon: Icon(Icons.keyboard_arrow_down, size: 32, color: config.text),
      ),
    ],
  );

  // ---------- Форма ----------

  Widget _form(ThemeConfig config, AppLocalizations l) {
    return ValueListenableBuilder<List<CartItem>>(
      valueListenable: globalCart,
      builder: (context, cart, child) {
        final items = cartTotal(cart);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _title(config, l.checkout),
            const SizedBox(height: 10),
            _typeSwitch(config, l),
            const SizedBox(height: 18),
            _field(
              config,
              _name,
              l.guestName,
              icon: Icons.person_outline,
              error: _nameError,
              clearError: () => _nameError = null,
              maxLength: 60,
              capitalization: TextCapitalization.words,
            ),
            _field(
              config,
              _phone,
              l.guestPhone,
              icon: Icons.phone_outlined,
              error: _phoneError,
              clearError: () => _phoneError = null,
              maxLength: 30,
              keyboard: TextInputType.phone,
            ),
            if (_isDelivery)
              _field(
                config,
                _address,
                l.deliveryAddress,
                icon: Icons.location_on_outlined,
                error: _addressError,
                clearError: () => _addressError = null,
                maxLength: 200,
                lines: 2,
              )
            else
              _pickupNote(config, l),
            _field(
              config,
              _comment,
              l.orderComment,
              icon: Icons.chat_bubble_outline,
              maxLength: 300,
              lines: 2,
            ),
            const SizedBox(height: 6),
            if (_deliveryTotal > 0) ...[
              _sum(config, l.itemsTotal, items, bold: false),
              _sum(config, l.deliveryCost, _deliveryTotal, bold: false),
            ],
            _sum(config, l.total, items + _deliveryTotal, bold: true),
            const SizedBox(height: 16),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: cart.isEmpty ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: config.accent,
                  foregroundColor: config.onAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: Text(
                  widget.delivery.opensWhatsapp ? l.sendToWhatsapp : l.placeOrder,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Доставка или самовывоз. Две кнопки, а не список: выбор всего из двух,
  /// и он должен быть виден сразу
  Widget _typeSwitch(ThemeConfig config, AppLocalizations l) => Row(
    children: [
      Expanded(child: _typeButton(config, OrderType.delivery, l.delivery)),
      const SizedBox(width: 10),
      Expanded(child: _typeButton(config, OrderType.pickup, l.pickup)),
    ],
  );

  Widget _typeButton(ThemeConfig config, OrderType type, String label) {
    final selected = _type == type;
    return SizedBox(
      height: 48,
      child: selected
          ? ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: config.accent,
                foregroundColor: config.onAccent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(label),
            )
          : OutlinedButton(
              onPressed: () => setState(() {
                _type = type;
                // Адрес не стираем: гость мог переключиться по ошибке
                _addressError = null;
              }),
              style: OutlinedButton.styleFrom(
                foregroundColor: config.text,
                side: BorderSide(color: config.text.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(label),
            ),
    );
  }

  /// Откуда забирать при самовывозе — гость должен это увидеть до отправки
  Widget _pickupNote(ThemeConfig config, AppLocalizations l) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.storefront_outlined,
          size: 20,
          color: config.text.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${l.pickupFrom} ${widget.branch.name}'
            '${widget.branch.address.isEmpty ? '' : ', ${widget.branch.address}'}',
            style: TextStyle(color: config.text.withValues(alpha: 0.8)),
          ),
        ),
      ],
    ),
  );

  Widget _field(
    ThemeConfig config,
    TextEditingController controller,
    String label, {
    required IconData icon,
    String? error,
    VoidCallback? clearError,
    int? maxLength,
    int lines = 1,
    TextInputType? keyboard,
    TextCapitalization capitalization = TextCapitalization.sentences,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: controller,
      keyboardType: lines > 1 ? TextInputType.multiline : keyboard,
      textCapitalization: capitalization,
      minLines: lines,
      // Растёт, а не прокручивается внутри себя: иначе в настольном
      // браузере поверх последних букв ложится полоса прокрутки, и
      // отступом её не отодвинуть — он двигает и текст, и полосу.
      // Прокручивается сама шторка, у неё по краям есть отбивка
      maxLines: lines > 1 ? null : 1,
      maxLength: maxLength,
      // Счётчик под каждым полем только мешает — предел всё равно сработает
      buildCounter:
          (_, {required currentLength, required isFocused, maxLength}) => null,
      style: TextStyle(color: config.text),
      // Ошибка исчезает, как только гость начал исправлять поле
      onChanged: error == null ? null : (_) => setState(clearError!),
      decoration: InputDecoration(
        labelText: label,
        errorText: error,
        prefixIcon: Icon(icon, color: config.text.withValues(alpha: 0.6)),
        labelStyle: TextStyle(color: config.text.withValues(alpha: 0.7)),
        filled: true,
        fillColor: config.bg.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );

  Widget _sum(ThemeConfig config, String label, double value, {required bool bold}) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: config.text.withValues(alpha: bold ? 0.8 : 0.6),
              fontSize: bold ? 16 : 14,
            ),
          ),
          Text(
            '${money(value)} ${l.som}',
            style: GoogleFonts.manrope(
              fontSize: bold ? 26 : 16,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
              color: bold ? config.accent : config.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Отправлено ----------

  Widget _done(ThemeConfig config, AppLocalizations l) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      _title(config, l.checkout),
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, color: config.accent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l.orderSentHint,
              style: TextStyle(color: config.text, fontSize: 16),
            ),
          ),
        ],
      ),
      if (_notice != null) ...[
        const SizedBox(height: 14),
        Text(
          _notice!,
          style: TextStyle(
            color: config.text.withValues(alpha: 0.7),
            fontSize: 14,
          ),
        ),
      ],
      const SizedBox(height: 20),
      if (_lastLink != null)
        OutlinedButton.icon(
          onPressed: _openAgain,
          icon: const Icon(Icons.open_in_new, size: 18),
          style: OutlinedButton.styleFrom(
            foregroundColor: config.text,
            side: BorderSide(color: config.text.withValues(alpha: 0.3)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          label: Text(l.openWhatsappAgain),
        ),
      const SizedBox(height: 10),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(
          l.close,
          style: TextStyle(color: config.text.withValues(alpha: 0.6)),
        ),
      ),
    ],
  );
}
