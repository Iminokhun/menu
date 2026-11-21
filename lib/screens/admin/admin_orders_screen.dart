import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../api/api_client.dart';
import '../../config/current_branch.dart';
import 'admin_filters.dart';
import '../../models/json_read.dart';
import '../../models/product.dart' show money;
import '../../open_link.dart';
import '../../order/order_message.dart';

/// Отметка заказа. «Новые» — рабочее состояние экрана, с него и
/// открывается: готовые уже никого не ждут.
enum _Status {
  fresh('Новые', 'new'),
  done('Готовые', 'done'),
  any('Все заказы', null);

  const _Status(this.label, this.value);
  final String label;
  final String? value;
}

/// Способ получения. Подписи не повторяют слово «все» из отметок: два
/// одинаковых слова в соседних группах неразличимы.
enum _Type {
  any('Любой способ', null),
  delivery('Доставка', 'delivery'),
  pickup('Самовывоз', 'pickup');

  const _Type(this.label, this.value);
  final String label;
  final String? value;
}

/// Заказы, оформленные гостями на сайте.
///
/// Это **единственная полная запись** о заказе: сообщение в WhatsApp гость
/// набирает у себя и может его поправить или вовсе не отправить. Поэтому
/// список обновляется сам, а не только по кнопке.
class AdminOrdersScreen extends StatefulWidget {
  /// Открыт ли этот раздел сейчас. `IndexedStack` в `admin_shell` держит все
  /// экраны живыми, поэтому без этого флага опрос сервера шёл бы и с других
  /// вкладок.
  final bool active;

  const AdminOrdersScreen({super.key, required this.active});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  static const _accent = Color(0xFFD4AF37);
  static const _bg = Color(0xFF0A0A0A);
  static const _surface = Color(0xFF1A1A1A);

  /// Как часто перечитывать список, пока раздел открыт
  static const _poll = Duration(seconds: 20);

  List<Map<String, dynamic>> _orders = const [];
  bool _loading = true;
  bool _busy = false;
  String? _loadError;

  /// Отбор. Считает его сервер, а не экран: выборка ограничена сотней
  /// строк, и заказы за сегодня или только самовывоз иначе могли бы в неё
  /// не попасть
  AdminPeriod _period = AdminPeriod.all;
  _Status _status = _Status.fresh;
  _Type _type = _Type.any;

  /// Отличается ли отбор от рабочего вида, с которого экран открывается
  bool get _filtered =>
      _period != AdminPeriod.all ||
      _status != _Status.fresh ||
      _type != _Type.any;

  static const _limit = 100;

  /// Нажали, пока предыдущий запрос был в пути: повторим его в конце,
  /// иначе отбор молча расходится с тем, что на экране
  bool _again = false;

  /// Поколение запроса: опоздавший ответ не должен перебить новый
  int _gen = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    currentBranch.addListener(_reload);
    _load();
    _syncTimer();
  }

  @override
  void didUpdateWidget(AdminOrdersScreen old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      _syncTimer();
      if (widget.active) _load();
    }
  }

  @override
  void dispose() {
    currentBranch.removeListener(_reload);
    _timer?.cancel();
    super.dispose();
  }

  void _syncTimer() {
    _timer?.cancel();
    _timer = widget.active ? Timer.periodic(_poll, (_) => _load()) : null;
  }

  void _reload() => _load();

  /// Смена отбора: перерисовать, отодвинуть опрос и перечитать список.
  /// Опрос отодвигается, чтобы список не дёргался под руками
  void _apply(VoidCallback change) {
    setState(change);
    _syncTimer();
    _load();
  }

  void _reset() => _apply(() {
    _period = AdminPeriod.all;
    _status = _Status.fresh;
    _type = _Type.any;
  });

  Future<void> _load() async {
    final branch = currentBranch.value;
    if (branch == null) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    final gen = ++_gen;
    try {
      final since = sinceFor(_period);
      final rows = await api.list('/api/admin/orders', {
        'branch_id': branch.id,
        if (since != null) 'since': since,
        if (_status.value != null) 'status': _status.value!,
        if (_type.value != null) 'order_type': _type.value!,
        'limit': '$_limit',
      });
      if (!mounted || gen != _gen) return;
      setState(() {
        _orders = rows;
        _loading = false;
        _loadError = null;
      });
    } on ApiException catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loading = false;
        _loadError = e.message;
      });
    } finally {
      _busy = false;
      if (_again) {
        _again = false;
        _load();
      }
    }
  }

  Future<void> _setStatus(Map<String, dynamic> order, String status) async {
    try {
      await api.patch('/api/admin/orders/${order['id']}', {'status': status});
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: Column(
        children: [
          _toolbar(),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _toolbar() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Wrap, а не Row со Spacer: на мониторе выглядит так же, а на
      // телефоне счётчик с кнопкой уезжают строкой ниже вместо
      // переполнения
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        // Ширина во всю строку: без неё Wrap ужался бы по содержимому, и
        // прижимать счётчик к правому краю было бы нечем
        child: SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                'ЗАКАЗЫ',
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_orders.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        'Показано: ${_orders.length}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Обновить',
                    onPressed: () => _apply(() {}),
                    icon: const Icon(Icons.refresh, color: Colors.white54),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      // Один Wrap на все кнопки: на узком окне он переносит ряд, а Row
      // упёрся бы в переполнение
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final p in AdminPeriod.values)
              _chip(p.label, _period == p, () => _apply(() => _period = p)),
            _divider(),
            for (final s in _Status.values)
              _chip(s.label, _status == s, () => _apply(() => _status = s)),
            _divider(),
            for (final t in _Type.values)
              _chip(t.label, _type == t, () => _apply(() => _type = t)),
            if (_filtered)
              TextButton(
                onPressed: _reset,
                child: const Text(
                  'Сбросить',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _chip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
  );

  /// Полоска между группами: после переноса ряда видно, где кончается
  /// одна группа и начинается другая
  Widget _divider() => Container(width: 1, height: 24, color: Colors.white24);

  /// Чем сейчас сужен список — строкой, чтобы объяснить пустой экран
  String get _filterLine => [
    if (_period != AdminPeriod.all) _period.label,
    if (_status != _Status.fresh) _status.label,
    if (_type != _Type.any) _type.label,
  ].join(' · ');

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (_loadError != null) {
      return Center(
        child: Text(
          _loadError!,
          style: const TextStyle(color: Colors.redAccent),
        ),
      );
    }
    if (_orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _filtered
                    ? 'Под этот отбор заказов нет.'
                    : 'Новых заказов нет.\nКнопка заказа появляется у гостя, '
                          'когда в настройках филиала указан WhatsApp.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 15),
              ),
              // Здесь кафе и застревает, поэтому сброс — прямо тут, а не
              // только наверху
              if (_filtered) ...[
                const SizedBox(height: 8),
                Text(
                  _filterLine,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white24, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _reset,
                  child: const Text('Вернуться к новым'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    // Уперлись в предел — сказать об этом прямо: иначе «Показано: 100»
    // выглядит как итог, а это окно
    final capped = _orders.length == _limit;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 40),
      itemCount: _orders.length + (capped ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) => i < _orders.length
          ? _card(_orders[i])
          : const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Показаны последние $_limit — уточните период или отметку.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white24, fontSize: 13),
              ),
            ),
    );
  }

  Widget _card(Map<String, dynamic> order) {
    final done = order['status'] == 'done';
    final isDelivery = order['order_type'] == 'delivery';
    final items = (order['items'] as List?) ?? const [];
    final deliveryTotal = jsonDouble(order['delivery_total']);
    final phone = (order['guest_phone'] as String?) ?? '';
    final waPhone = (order['guest_phone_wa'] as String?) ?? '';
    return Opacity(
      opacity: done ? 0.5 : 1,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: done ? Colors.white12 : _accent.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Wrap, а не Row: на телефоне время уходит строкой ниже, а
            // не выдавливает номер заказа за край карточки
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 4,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _badge(
                        isDelivery ? 'ДОСТАВКА' : 'САМОВЫВОЗ',
                        isDelivery
                            ? Colors.lightBlueAccent
                            : Colors.greenAccent,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '№${order['code']}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _time(order['created_at'] as String?),
                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              (order['guest_name'] as String?) ?? '',
              // Имя пришло из интернета. Сервер уже убрал оттуда переносы
              // строк, но длину карточки всё равно держим в узде
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            _contact(phone, waPhone),
            if (isDelivery &&
                ((order['address'] as String?) ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                order['address'] as String,
                // В адресе перенос строки осмыслен, поэтому он сохранён.
                // Но заполнить им весь экран гость не должен
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ],
            const Divider(color: Colors.white12, height: 24),
            for (final raw in items) _line(raw),
            const SizedBox(height: 8),
            if (deliveryTotal > 0) _sum('Доставка', deliveryTotal, bold: false),
            _sum('Итого', jsonDouble(order['total']), bold: true),
            if ((order['comment'] as String?)?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Text(
                order['comment'] as String,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: done
                  ? TextButton(
                      onPressed: () => _setStatus(order, 'new'),
                      child: const Text('Вернуть в новые'),
                    )
                  : ElevatedButton.icon(
                      onPressed: () => _setStatus(order, 'done'),
                      icon: const Icon(Icons.check, size: 18),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.black,
                      ),
                      label: const Text('Готово'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Телефон гостя: в браузере — ссылкой в WhatsApp, иначе копируется.
  /// Телефон гостя и что с ним можно сделать.
  ///
  /// Показываем номер так, как его набрал гость, — «0555112233» он и
  /// продиктует по телефону. А в ссылку WhatsApp подставляем [waPhone]:
  /// международный вид, который посчитал сервер по своему коду страны.
  /// Не посчитал — кнопки «Написать» нет, остаётся «Скопировать»: пустая
  /// ссылка открыла бы переписку с несуществующим номером.
  Widget _contact(String phone, String waPhone) {
    if (phone.isEmpty) return const SizedBox.shrink();
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.phone_outlined, size: 16, color: Colors.white38),
            const SizedBox(width: 6),
            Text(phone, style: const TextStyle(color: Colors.white70)),
          ],
        ),
        if (kIsWeb && waPhone.isNotEmpty)
          TextButton(
            onPressed: () => openLink(waLink(waPhone, '')),
            child: const Text('Написать'),
          )
        else
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: phone)),
            child: const Text('Скопировать'),
          ),
      ],
    );
  }

  Widget _line(Object? raw) {
    if (raw is! Map) return const SizedBox.shrink();
    final gone = raw['missing'] == true;
    final portion = (raw['portion'] as String?) ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              '${raw['qty']} x ${raw['name']}'
              '${portion.isEmpty ? '' : ' ($portion)'}'
              '${gone ? '  — нет в меню, со слов гостя' : ''}',
              // У пропавшего блюда название пришло от гостя, а не из меню
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: gone ? Colors.redAccent : Colors.white,
                fontSize: 15,
              ),
            ),
          ),
          Text(
            gone ? '—' : '${money(jsonDouble(raw['sum']))} с.',
            style: TextStyle(
              color: gone ? Colors.redAccent : Colors.white70,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sum(String label, double value, {required bool bold}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: bold ? Colors.white : Colors.white54,
            fontSize: bold ? 16 : 14,
          ),
        ),
        Text(
          '${money(value)} с.',
          style: GoogleFonts.manrope(
            color: bold ? _accent : Colors.white70,
            fontSize: bold ? 20 : 14,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    ),
  );

  /// `2026-11-18 12:34:56` из SQLite — в «18.11 12:34».
  String _time(String? raw) {
    final t = DateTime.tryParse('${raw ?? ''}Z')?.toLocal();
    if (t == null) return raw ?? '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
  }
}
