import 'package:flutter/material.dart';

import '../api_client.dart';

/// Просмотры меню одного кафе: сколько людей заходило по дням и сколько у
/// каждого филиала. Только смотрим — ничего не меняем, поэтому ничего и не
/// возвращаем.
Future<void> showViewsDialog(
  BuildContext context,
  Map<String, dynamic> cafe,
) => showDialog<void>(
  context: context,
  builder: (_) => _ViewsDialog(cafe: cafe),
);

class _ViewsDialog extends StatefulWidget {
  final Map<String, dynamic> cafe;
  const _ViewsDialog({required this.cafe});

  @override
  State<_ViewsDialog> createState() => _ViewsDialogState();
}

class _ViewsDialogState extends State<_ViewsDialog> {
  static const _accent = Color(0xFFD4AF37);
  static const _surface = Color(0xFF1A1A1A);

  static const _periods = {7: '7 дней', 30: '30 дней', 90: '90 дней'};

  int _days = 30;

  /// null — ещё грузим
  Map<String, dynamic>? _data;
  String? _error;

  String get _cafeId => widget.cafe['id'] as String;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _data = null;
      _error = null;
    });
    try {
      final r = await api.get('/api/super/cafes/$_cafeId/views', {
        'days': '$_days',
      });
      if (mounted) setState(() => _data = Map<String, dynamic>.from(r as Map));
    } catch (e) {
      if (mounted) setState(() => _error = 'Не загрузилось: $e');
    }
  }

  List<Map<String, dynamic>> get _branches => _data == null
      ? const []
      : List<Map<String, dynamic>>.from(_data!['branches'] as List);

  /// Дни ряда — от сегодняшнего назад, включая пустые: сервер присылает
  /// только те, в которые кто-то заходил, а в ряду провалы должны быть
  /// видны наравне с всплесками
  List<({String day, int people})> get _row {
    final data = _data;
    if (data == null) return const [];
    final people = <String, int>{
      for (final d in data['days'] as List)
        (d as Map)['day'] as String: (d['people'] as num).toInt(),
    };
    final today = DateTime.parse(data['today'] as String);
    return [
      for (var i = _days - 1; i >= 0; i--)
        () {
          final d = DateTime(today.year, today.month, today.day - i);
          final key =
              '${d.year}-${d.month.toString().padLeft(2, '0')}'
              '-${d.day.toString().padLeft(2, '0')}';
          return (day: key, people: people[key] ?? 0);
        }(),
    ];
  }

  int get _todayPeople {
    var n = 0;
    for (final b in _branches) {
      n += (b['views_today'] as num).toInt();
    }
    return n;
  }

  int get _allTime {
    var n = 0;
    for (final b in _branches) {
      n += (b['views_total'] as num).toInt();
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final row = _row;
    final period = row.fold(0, (s, d) => s + d.people);
    return AlertDialog(
      backgroundColor: _surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Просмотры · ${widget.cafe['name']}',
        style: const TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in _periods.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: _days == e.key,
                      onSelected: (_) {
                        setState(() => _days = e.key);
                        _load();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 13,
                  ),
                )
              else if (_data == null)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: LinearProgressIndicator(color: _accent),
                )
              else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _big('$_todayPeople', 'сегодня'),
                    const SizedBox(width: 24),
                    _big('$period', 'за ${_periods[_days]}'),
                    const SizedBox(width: 24),
                    _big('$_allTime', 'всего'),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Людей — это разные устройства за день. Постоянный гость '
                  'считается заново каждый день, поэтому «всего» — это '
                  'посещения, а не разные люди.',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 18),
                _chart(row),
                const SizedBox(height: 20),
                _label('ФИЛИАЛЫ'),
                const SizedBox(height: 6),
                if (_branches.isEmpty)
                  const Text(
                    'У кафе нет филиалов',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  )
                else
                  for (final b in _branches) _branchRow(b),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть', style: TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }

  Widget _big(String n, String what) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        n,
        style: const TextStyle(
          color: _accent,
          fontSize: 26,
          fontWeight: FontWeight.w800,
        ),
      ),
      Text(what, style: const TextStyle(color: Colors.white54, fontSize: 12)),
    ],
  );

  static Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      color: Colors.white38,
      fontSize: 11,
      letterSpacing: 2,
      fontWeight: FontWeight.w700,
    ),
  );

  /// Столбики по дням. Рисуем сами: библиотеки графиков в проекте нет, а
  /// тридцать прямоугольников её и не стоят.
  Widget _chart(List<({String day, int people})> row) {
    final top = row.fold(0, (m, d) => d.people > m ? d.people : m);
    return SizedBox(
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in row)
            Expanded(
              child: Tooltip(
                message: '${_ruDay(d.day)} · ${d.people}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Пустой день — тонкая серая полоска у самого низа:
                      // так видно, что день был, а гостей не было
                      Container(
                        height: top == 0
                            ? 2.0
                            : 2 + 86 * (d.people / top).clamp(0.0, 1.0),
                        decoration: BoxDecoration(
                          color: d.people == 0 ? Colors.white12 : _accent,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _branchRow(Map<String, dynamic> b) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        const Icon(Icons.visibility_outlined, size: 14, color: Colors.white38),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${b['name']}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          'сегодня ${b['views_today']} · всего ${b['views_total']}',
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    ),
  );

  /// `2026-11-21` → `21.11`
  static String _ruDay(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}.${p[1]}' : iso;
  }
}
