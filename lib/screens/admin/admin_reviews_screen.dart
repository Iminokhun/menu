import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../api/api_client.dart';
import '../../config/current_branch.dart';
import '../../widgets/star_rating.dart';

/// Отзывы, оставленные гостями на сайте.
///
/// Здесь имя официанта и жалоба на него: это видит только своё кафе.
/// Править и удалять отзыв нельзя — в нём нечего менять, а кафе, которое
/// стирает плохие отзывы, обманывает само себя. Старые уходят сами через
/// 40 дней, и об этом сказано прямо под списком.
class AdminReviewsScreen extends StatefulWidget {
  /// Открыт ли этот раздел сейчас. `IndexedStack` в `admin_shell` держит все
  /// экраны живыми, поэтому без этого флага опрос сервера шёл бы и с других
  /// вкладок.
  final bool active;

  const AdminReviewsScreen({super.key, required this.active});

  @override
  State<AdminReviewsScreen> createState() => _AdminReviewsScreenState();
}

class _AdminReviewsScreenState extends State<AdminReviewsScreen> {
  static const _accent = Color(0xFFD4AF37);
  static const _bg = Color(0xFF0A0A0A);
  static const _surface = Color(0xFF1A1A1A);

  /// Реже, чем заказы: отзыв не требует реакции в минуты. Но совсем без
  /// опроса экран, открытый с утра, к вечеру показывал бы утренний список
  static const _poll = Duration(minutes: 2);

  List<Map<String, dynamic>> _reviews = const [];
  bool _loading = true;
  bool _busy = false;
  String? _loadError;

  /// Показывать только плохие (1–2 звезды): ради них этот экран и открывают
  bool _onlyBad = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    currentBranch.addListener(_reload);
    _load();
    _syncTimer();
  }

  @override
  void didUpdateWidget(AdminReviewsScreen old) {
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
      // Фильтр считает сервер: при сотне строк в выборке плохие отзывы
      // иначе могли бы в неё и не попасть
      final rows = await api.list('/api/admin/reviews', {
        'branch_id': branch.id,
        if (_onlyBad) 'max_rating': '2',
        'limit': '100',
      });
      if (!mounted) return;
      setState(() {
        _reviews = rows;
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

  /// Средняя оценка по тому, что сейчас на экране. Так и подписано: при
  /// фильтре «плохие» среднее по ним, а не по всем отзывам
  String get _average {
    if (_reviews.isEmpty) return '';
    final sum = _reviews.fold<int>(0, (s, r) => s + (r['rating'] as int? ?? 0));
    return (sum / _reviews.length).toStringAsFixed(1).replaceAll('.', ',');
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
          'ОТЗЫВЫ',
          style: GoogleFonts.manrope(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(width: 20),
        ChoiceChip(
          label: const Text('Все'),
          selected: !_onlyBad,
          onSelected: (_) {
            setState(() => _onlyBad = false);
            _load();
          },
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Плохие'),
          selected: _onlyBad,
          onSelected: (_) {
            setState(() => _onlyBad = true);
            _load();
          },
        ),
        const Spacer(),
        if (_reviews.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              'Средняя по показанным: $_average (${_reviews.length})',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
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
    final allowed = currentBranch.value?.reviewsEnabled == true;
    if (_reviews.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            allowed
                ? 'Отзывов пока нет.'
                : 'Отзывы этому филиалу не подключены — кнопки у гостя нет.\n'
                      'Подключение включают там же, где заводили кафе.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: allowed ? Colors.white38 : Colors.orangeAccent,
              fontSize: 15,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 40),
      // Последняя строка — не отзыв, а срок хранения: кафе должно знать
      // заранее, а не обнаружить пропажу
      itemCount: _reviews.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) => i < _reviews.length
          ? _card(_reviews[i])
          : const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Отзывы хранятся 40 дней, потом удаляются.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white24, fontSize: 13),
              ),
            ),
    );
  }

  Widget _card(Map<String, dynamic> review) {
    final rating = review['rating'] as int? ?? 0;
    final bad = rating <= 2;
    final waiter = (review['waiter'] as String?) ?? '';
    final table = (review['table_no'] as String?) ?? '';
    final comment = (review['comment'] as String?) ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: bad
              ? Colors.redAccent.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StarRating(
                value: rating,
                color: bad ? Colors.redAccent : _accent,
                size: 20,
              ),
              const Spacer(),
              Text(
                _time(review['created_at'] as String?),
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
          ),
          if (waiter.isNotEmpty || table.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              [
                if (waiter.isNotEmpty) 'Официант: $waiter',
                if (table.isNotEmpty) 'Стол: $table',
              ].join('   ·   '),
              // Пришло из интернета: длину ограничиваем, как и в заказах
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              comment,
              maxLines: 10,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// `2026-11-18 12:34:56` из SQLite — в «18.11 12:34».
  String _time(String? raw) {
    final t = DateTime.tryParse('${raw ?? ''}Z')?.toLocal();
    if (t == null) return raw ?? '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
  }
}
