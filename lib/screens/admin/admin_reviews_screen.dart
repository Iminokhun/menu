import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../api/api_client.dart';
import '../../config/current_branch.dart';
import '../../responsive.dart';
import 'admin_filters.dart';
import '../../widgets/star_rating.dart';

/// Отзывы, оставленные гостями на сайте.
///
/// Здесь имя официанта и жалоба на него: это видит только своё кафе.
/// Править и удалять отзыв нельзя — в нём нечего менять, а кафе, которое
/// стирает плохие отзывы, обманывает само себя. Старые уходят сами через
/// 40 дней, и об этом сказано прямо под списком.
/// Корзина оценок. «Плохие» в прежнем виде — это ровно `max_rating=2`,
/// поэтому старый клиент продолжает работать без правок.
enum _Bucket {
  any('Любая оценка', null, null),
  good('5 и 4', 4, null),
  mid('3', 3, 3),
  bad('2 и 1', null, 2);

  const _Bucket(this.label, this.min, this.max);
  final String label;
  final int? min;
  final int? max;
}

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

  /// Отбор. Сервер считает все три: выборка ограничена сотней строк, и
  /// отзывы за сегодня, плохие или про одного официанта иначе могли бы в
  /// неё не попасть — а ради них этот экран и открывают
  AdminPeriod _period = AdminPeriod.all;
  _Bucket _bucket = _Bucket.any;
  String? _waiter;

  /// Кто упоминался в отзывах — для выбора официанта. Приходит отдельной
  /// ручкой: список, собранный из загруженных отзывов, сам себя уничтожал
  /// бы — выбрали официанта, и переключиться стало бы не на кого
  List<Map<String, dynamic>> _waiters = const [];

  bool get _filtered =>
      _period != AdminPeriod.all || _bucket != _Bucket.any || _waiter != null;

  /// Сколько строк просим. Больше двух сотен карточек никто не читает, а
  /// ждать дольше — читают ещё меньше
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
    _loadWaiters();
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

  void _reload() {
    // Имена официантов принадлежат филиалу: при смене филиала выбор
    // сбрасываем, а период и оценку оставляем — их смысл не меняется
    _waiter = null;
    _loadWaiters();
    _load();
  }

  /// Смена отбора: перерисовать, отодвинуть опрос и перечитать список.
  /// Опрос отодвигается, чтобы список не дёргался под руками
  void _apply(VoidCallback change) {
    setState(change);
    _syncTimer();
    _load();
  }

  void _reset() => _apply(() {
    _period = AdminPeriod.all;
    _bucket = _Bucket.any;
    _waiter = null;
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
      final rows = await api.list('/api/admin/reviews', {
        'branch_id': branch.id,
        if (since != null) 'since': since,
        if (_bucket.min != null) 'min_rating': '${_bucket.min}',
        if (_bucket.max != null) 'max_rating': '${_bucket.max}',
        if (_waiter != null) 'waiter': _waiter!,
        'limit': '$_limit',
      });
      if (!mounted || gen != _gen) return;
      setState(() {
        _reviews = rows;
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

  /// Список имён для выбора официанта. Из опроса не зовётся: новое имя —
  /// событие редкое, а лишний запрос раз в две минуты с каждого открытого
  /// планшета не нужен
  Future<void> _loadWaiters() async {
    final branch = currentBranch.value;
    if (branch == null) return;
    try {
      final since = sinceFor(_period);
      final rows = await api.list('/api/admin/reviews/waiters', {
        'branch_id': branch.id,
        if (since != null) 'since': since,
      });
      if (!mounted) return;
      setState(() => _waiters = rows);
    } on ApiException {
      // Не вышло — меню останется прежним. Списку отзывов это не мешает
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
    // Порог от экрана, а не от своих ограничений: в широкой вёрстке часть
    // ширины забирает боковая колонка оболочки
    final wide = Responsive.isWide(MediaQuery.sizeOf(context));
    return Container(
      color: _bg,
      child: Column(
        children: [
          _toolbar(wide),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _toolbar(bool wide) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Wrap, а не Row со Spacer: «Средняя по показанным: 4,5 (12)» вдвое
      // длиннее заголовка и на телефоне уходит строкой ниже
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
                'ОТЗЫВЫ',
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
                  if (_reviews.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        wide ? _countLine : _countShort,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Обновить',
                    onPressed: () {
                      _loadWaiters();
                      _apply(() {});
                    },
                    icon: const Icon(Icons.refresh, color: Colors.white54),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      // Один Wrap на все кнопки: на узком окне он переносит ряд, а Row
      // упёрся бы в переполнение. Подписи групп не нужны — ни одно слово
      // не повторяется: у периода «За всё время», у оценки «Любая оценка»
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final p in AdminPeriod.values)
              _chip(
                p.label,
                _period == p,
                () => _apply(() {
                  _period = p;
                  // Период меняет и набор имён: уволившийся месяц назад не
                  // должен мешаться в выборе
                  _loadWaiters();
                }),
              ),
            _divider(),
            for (final b in _Bucket.values)
              _chip(b.label, _bucket == b, () => _apply(() => _bucket = b)),
            _waiterMenu(),
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
  /// период и начинается оценка
  Widget _divider() => Container(width: 1, height: 24, color: Colors.white24);

  /// Официант — одна кнопка с меню, а не ряд чипсов: имён неизвестно
  /// сколько, их пишет гость руками
  Widget _waiterMenu() => PopupMenuButton<String?>(
    tooltip: 'Официант',
    color: _surface,
    initialValue: _waiter,
    onSelected: (v) => _apply(() => _waiter = v),
    itemBuilder: (_) => [
      const PopupMenuItem<String?>(
        value: null,
        child: Text(
          'Все официанты',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ),
      for (final w in _waiters)
        PopupMenuItem<String?>(
          value: w['waiter'] as String?,
          child: Text(
            '${w['waiter']} · ${w['count']}',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
    ],
    child: Chip(
      backgroundColor: _waiter == null ? null : _accent.withValues(alpha: 0.2),
      label: Text(
        'Официант: ${_waiter ?? 'все'}',
        style: const TextStyle(fontSize: 13),
      ),
      avatar: const Icon(Icons.arrow_drop_down, size: 18),
    ),
  );

  /// Что написано справа в заголовке.
  ///
  /// Средняя показывается только без отбора по оценке: средняя внутри
  /// корзины — тавтология (у «2 и 1» она всегда около полутора), но стоит
  /// рядом с кнопкой и читается как оценка кафе
  String get _countLine => _bucket == _Bucket.any
      ? 'Средняя по показанным: $_average (${_reviews.length})'
      : 'Показано: ${_reviews.length}';

  /// То же для телефона: там на подпись остаётся полстроки, а цифры важнее
  /// слов — «4,5 · 12» читается так же, как «Средняя по показанным».
  String get _countShort => _bucket == _Bucket.any
      ? '$_average · ${_reviews.length}'
      : '${_reviews.length}';

  /// Чем сейчас сужен список — строкой, чтобы объяснить пустой экран
  String get _filterLine => [
    if (_period != AdminPeriod.all) _period.label,
    if (_bucket != _Bucket.any) 'оценка ${_bucket.label}',
    if (_waiter != null) _waiter!,
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
    final allowed = currentBranch.value?.reviewsEnabled == true;
    if (_reviews.isEmpty) {
      // Порядок важен: про невыданное право сказать нужнее, чем про отбор
      if (!allowed) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: Text(
              'Отзывы этому филиалу не подключены — кнопки у гостя нет.\n'
              'Подключение включают там же, где заводили кафе.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.orangeAccent, fontSize: 15),
            ),
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _filtered ? 'Под этот отбор отзывов нет.' : 'Отзывов пока нет.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 15),
              ),
              // Здесь владелец и застревает, поэтому сброс — прямо тут, а
              // не только наверху
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
                  child: const Text('Показать все отзывы'),
                ),
              ],
            ],
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
          : Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _reviews.length < _limit
                    ? 'Отзывы хранятся 40 дней, потом удаляются.'
                    : 'Показаны последние $_limit — уточните период или '
                          'оценку.\nОтзывы хранятся 40 дней, потом удаляются.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white24, fontSize: 13),
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
