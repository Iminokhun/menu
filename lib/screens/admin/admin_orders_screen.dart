import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../api/api_client.dart';
import '../../config/current_branch.dart';
import '../../models/json_read.dart';
import '../../open_link.dart';
import '../../order/order_message.dart';

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
  bool _onlyNew = true;
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

  Future<void> _load() async {
    final branch = currentBranch.value;
    if (branch == null || _busy) return;
    _busy = true;
    try {
      final rows = await api.list('/api/admin/orders', {
        'branch_id': branch.id,
        if (_onlyNew) 'status': 'new',
        'limit': '100',
      });
      if (!mounted) return;
      setState(() {
        _orders = rows;
        _loading = false;
        _loadError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.message;
      });
    } finally {
      _busy = false;
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

  Widget _toolbar() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
    child: Row(
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
        const SizedBox(width: 20),
        ChoiceChip(
          label: const Text('Новые'),
          selected: _onlyNew,
          onSelected: (v) {
            setState(() => _onlyNew = true);
            _load();
          },
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Все'),
          selected: !_onlyNew,
          onSelected: (v) {
            setState(() => _onlyNew = false);
            _load();
          },
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Обновить',
          onPressed: _load,
          icon: const Icon(Icons.refresh, color: Colors.white54),
        ),
      ],
    ),
  );

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
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Text(
            'Заказов пока нет.\nКнопка заказа появляется у гостя, когда в '
            'настройках филиала указан WhatsApp.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 15),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 40),
      itemCount: _orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _card(_orders[i]),
    );
  }

  Widget _card(Map<String, dynamic> order) {
    final done = order['status'] == 'done';
    final isDelivery = order['order_type'] == 'delivery';
    final items = (order['items'] as List?) ?? const [];
    final deliveryTotal = jsonDouble(order['delivery_total']);
    final phone = (order['guest_phone'] as String?) ?? '';
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
            Row(
              children: [
                _badge(
                  isDelivery ? 'ДОСТАВКА' : 'САМОВЫВОЗ',
                  isDelivery ? Colors.lightBlueAccent : Colors.greenAccent,
                ),
                const SizedBox(width: 10),
                Text(
                  '№${order['code']}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  _time(order['created_at'] as String?),
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              (order['guest_name'] as String?) ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            _contact(phone),
            if (isDelivery && ((order['address'] as String?) ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                order['address'] as String,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ],
            const Divider(color: Colors.white12, height: 24),
            for (final raw in items) _line(raw),
            const SizedBox(height: 8),
            if (deliveryTotal > 0)
              _sum('Доставка', deliveryTotal, bold: false),
            _sum('Итого', jsonDouble(order['total']), bold: true),
            if ((order['comment'] as String?)?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Text(
                order['comment'] as String,
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
  Widget _contact(String phone) {
    if (phone.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        const Icon(Icons.phone_outlined, size: 16, color: Colors.white38),
        const SizedBox(width: 6),
        Text(phone, style: const TextStyle(color: Colors.white70)),
        const SizedBox(width: 10),
        if (kIsWeb)
          TextButton(
            onPressed: () => openLink(waLink(phone, '')),
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
              style: TextStyle(
                color: gone ? Colors.redAccent : Colors.white,
                fontSize: 15,
              ),
            ),
          ),
          Text(
            gone ? '—' : '${jsonDouble(raw['sum']).toInt()} с.',
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
          '${value.toInt()} с.',
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
