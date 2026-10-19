import 'package:flutter/material.dart';

import '../api_client.dart';

/// `2026-10-18` → `18.10.2026`; пустая строка остаётся пустой.
String ruDate(String iso) {
  final p = iso.split('-');
  return p.length == 3 ? '${p[2]}.${p[1]}.${p[0]}' : iso;
}

/// Статус оплаты кафе для карточки: текст и цвет.
({String text, Color color}) accessLabel(Map<String, dynamic> cafe) {
  final until = ruDate((cafe['paid_until'] as String?) ?? '');
  final left = cafe['days_left'] as int?;
  final isTrial = cafe['plan'] == 'trial';
  return switch (cafe['access']) {
    _ when cafe['plan'] == 'lifetime' => (text: 'Навсегда', color: const Color(0xFFD4AF37)),
    'ok' => (text: '${isTrial ? 'Пробный' : 'Оплачено'} до $until', color: Colors.green),
    'ending' => (
        text: '${isTrial ? 'Пробный: о' : 'О'}сталось ${left ?? 0} дн. (до $until)',
        color: Colors.orangeAccent,
      ),
    'grace' => (
        text: 'Просрочено ${-(left ?? 0)} дн. — меню ещё работает',
        color: Colors.deepOrangeAccent,
      ),
    _ => (text: 'Просрочено — меню выключено', color: Colors.redAccent),
  };
}

/// Оплата кафе: продление на 1–12 месяцев или «навсегда», история оплат
/// и ручная правка срока. Возвращает true, если что-то изменилось.
Future<bool> showPaymentDialog(BuildContext context, Map<String, dynamic> cafe) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => _PaymentDialog(cafe: cafe),
  );
  return changed == true;
}

class _PaymentDialog extends StatefulWidget {
  final Map<String, dynamic> cafe;
  const _PaymentDialog({required this.cafe});

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  static const _accent = Color(0xFFD4AF37);
  static const _surface = Color(0xFF1A1A1A);

  /// Месяцы; 0 — навсегда
  static const _periods = {1: '1 мес', 3: '3 мес', 6: '6 мес', 12: '1 год', 0: 'Навсегда'};

  int _months = 1;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  List<Map<String, dynamic>>? _history;
  String? _error;
  bool _saving = false;

  String get _cafeId => widget.cafe['id'] as String;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final rows = await api.list('/api/super/cafes/$_cafeId/payments');
      if (mounted) setState(() => _history = rows);
    } catch (e) {
      if (mounted) setState(() => _error = 'История не загрузилась: $e');
    }
  }

  /// От какой даты считается продление — так же, как на сервере: от конца
  /// текущего срока, если он ещё не наступил, иначе от сегодня
  String get _fromText {
    final until = (widget.cafe['paid_until'] as String?) ?? '';
    final left = widget.cafe['days_left'] as int?;
    final fromEnd = until.isNotEmpty && left != null && left >= 0;
    return fromEnd ? 'от ${ruDate(until)} (конец текущего срока)' : 'от сегодня';
  }

  Future<void> _pay() async {
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
    if (amount == null || amount < 0) {
      setState(() => _error = 'Введите сумму, например 1500');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final cafe = await api.post('/api/super/cafes/$_cafeId/payments', {
        'period': _months == 0 ? 'lifetime' : 'month',
        if (_months > 0) 'months': _months,
        'amount': amount,
        'note': _note.text.trim(),
      }) as Map<String, dynamic>;
      if (!mounted) return;
      final label = accessLabel(cafe).text;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Оплата сохранена. ${widget.cafe['name']}: $label'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  /// Ручная правка срока — если ошиблись при оплате или договорились иначе
  Future<void> _setDate() async {
    final current = DateTime.tryParse((widget.cafe['paid_until'] as String?) ?? '');
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
      helpText: 'Оплачено до (включительно)',
    );
    if (picked == null || !mounted) return;
    final iso = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    try {
      await api.patch('/api/super/cafes/$_cafeId', {
        'paid_until': iso,
        // У «навсегда» срока нет — заданная дата переводит на обычный тариф
        if (widget.cafe['plan'] == 'lifetime') 'plan': 'paid',
      });
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Срок изменён: до ${ruDate(iso)}'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = accessLabel(widget.cafe);
    return AlertDialog(
      backgroundColor: _surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Оплата · ${widget.cafe['name']}', style: const TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.circle, size: 10, color: status.color),
                const SizedBox(width: 8),
                Expanded(child: Text(status.text, style: TextStyle(color: status.color))),
                TextButton(
                  onPressed: _saving ? null : _setDate,
                  child: const Text('Изменить срок', style: TextStyle(color: Colors.white54)),
                ),
              ]),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in _periods.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: _months == e.key,
                      onSelected: _saving ? null : (_) => setState(() => _months = e.key),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _months == 0
                    ? 'Срок больше не нужен: меню работает без ограничений'
                    : 'Продлится на ${_periods[_months]} $_fromText',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _amount,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Сумма, сом',
                  labelStyle: TextStyle(color: Colors.grey),
                ),
              ),
              TextField(
                controller: _note,
                enabled: !_saving,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Комментарий',
                  hintText: 'Например: Mbank, перевод от 18.10',
                  hintStyle: TextStyle(color: Colors.white24),
                  labelStyle: TextStyle(color: Colors.grey),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              const Text('ИСТОРИЯ ОПЛАТ',
                  style: TextStyle(
                      color: Colors.white38, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (_history == null && _error == null)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: LinearProgressIndicator(color: _accent),
                )
              else if (_history != null && _history!.isEmpty)
                const Text('Оплат ещё не было', style: TextStyle(color: Colors.white38, fontSize: 13))
              else
                for (final p in _history ?? const <Map<String, dynamic>>[]) _historyRow(p),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Закрыть', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.black),
          onPressed: _saving ? null : _pay,
          child: _saving
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Text('Сохранить оплату'),
        ),
      ],
    );
  }

  Widget _historyRow(Map<String, dynamic> p) {
    final date = ruDate(((p['paid_at'] as String?) ?? '').split(' ').first);
    final period = p['period'] == 'lifetime' ? 'навсегда' : '${p['months']} мес';
    final amount = (p['amount'] as num).toStringAsFixed(0);
    final until = (p['paid_until'] as String?) ?? '';
    final note = (p['note'] as String?) ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(date, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              '$period · $amount сом${until.isEmpty ? '' : ' → до ${ruDate(until)}'}'
              '${note.isEmpty ? '' : '\n$note'}',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
