import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../api_client.dart';
import 'payment_dialog.dart';

/// Главная админка платформы: кафе, их логины и лимит филиалов.
///
/// Сюда попадает только superadmin. Меню кафе отсюда не правится — для
/// этого у кафе свой логин и обычная админка. Здесь решается, кто
/// получает доступ и сколько филиалов ему разрешено открыть.
class SuperAdminShell extends StatefulWidget {
  /// Выход: закрыть сессию и вернуться к экрану входа
  final VoidCallback onLogout;

  const SuperAdminShell({super.key, required this.onLogout});

  @override
  State<SuperAdminShell> createState() => _SuperAdminShellState();
}

class _SuperAdminShellState extends State<SuperAdminShell> {
  List<Map<String, dynamic>> _cafes = [];
  bool _loading = true;
  String _query = '';

  /// Фильтр по оплате: all — все, soon — скоро кончается или просрочено
  /// в льготные дни, expired — меню уже выключено
  String _billing = 'all';

  static const _accent = Color(0xFFD4AF37);
  static const _bg = Color(0xFF0A0A0A);
  static const _surface = Color(0xFF1A1A1A);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await api.list('/api/super/cafes');
      if (!mounted) return;
      setState(() {
        _cafes = data;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // Сессия истекла (живёт сутки) — обратно на вход, а не пустой список
      if (e.status == 401) return widget.onLogout();
      setState(() => _loading = false);
      _toast('Ошибка загрузки: $e', isError: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('Нет связи с сервером: $e', isError: true);
    }
  }

  /// Выполняет действие, показывает итог и перечитывает список.
  Future<bool> _run(Future<void> Function() action, String success) async {
    try {
      await action();
      _toast(success);
      _load();
      return true;
    } catch (e) {
      _toast('$e', isError: true);
      return false;
    }
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
      duration: const Duration(seconds: 3),
    ));
  }

  // ======================================================================
  //  Диалоги
  // ======================================================================

  /// Форма из нескольких полей. Возвращает значения по ключам или null.
  /// [validate] возвращает текст ошибки — тогда окно не закрывается.
  Future<Map<String, String>?> _form({
    required String title,
    required List<_Field> fields,
    required String submit,
    String? Function(Map<String, String>)? validate,
    Future<String?> Function(Map<String, String>)? onSubmit,
  }) {
    final ctrls = {for (final f in fields) f.key: TextEditingController(text: f.initial)};
    String? error;
    bool busy = false;

    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Future<void> go() async {
          final values = {for (final e in ctrls.entries) e.key: e.value.text.trim()};
          final err = validate?.call(values);
          if (err != null) {
            setS(() => error = err);
            return;
          }
          if (onSubmit != null) {
            setS(() {
              busy = true;
              error = null;
            });
            final serverErr = await onSubmit(values);
            if (serverErr != null) {
              setS(() {
                busy = false;
                error = serverErr;
              });
              return;
            }
          }
          if (ctx.mounted) Navigator.pop(ctx, values);
        }

        return AlertDialog(
          backgroundColor: _surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 18)),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final f in fields) ...[
                    TextField(
                      controller: ctrls[f.key],
                      enabled: !busy,
                      autofocus: f == fields.first,
                      obscureText: false,
                      keyboardType: f.number ? TextInputType.number : TextInputType.text,
                      autocorrect: false,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: f.label,
                        helperText: f.hint,
                        helperStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                        helperMaxLines: 2,
                        labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                        enabledBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: _accent)),
                      ),
                      onSubmitted: (_) => go(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(error!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _accent, foregroundColor: Colors.black),
              onPressed: busy ? null : go,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : Text(submit, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      }),
    );
  }

  static String? _checkLogin(String login, String password) {
    if (login.length < 3) return 'Логин — не короче 3 символов';
    if (password.length < 6) return 'Пароль — не короче 6 символов';
    return null;
  }

  static String? _checkLimit(String v) {
    final n = int.tryParse(v);
    if (n == null || n < 1) return 'Лимит филиалов — целое число от 1';
    return null;
  }

  /// Новое кафе сразу с логином: кафе без логина никто не сможет наполнить.
  Future<void> _createCafe() async {
    String? createdId;
    final values = await _form(
      title: 'Новое кафе',
      submit: 'Создать',
      fields: const [
        _Field('name', 'Название кафе',
            hint: 'Первый филиал с этим названием появится сам — с готовым QR-кодом'),
        _Field('max', 'Сколько филиалов разрешено', initial: '1', number: true,
            hint: 'Больше этого числа кафе само создать не сможет'),
        _Field('trial', 'Пробный период, дней', initial: '14', number: true,
            hint: 'После него меню нужно оплатить, иначе оно выключится'),
        _Field('login', 'Логин для кафе'),
        _Field('password', 'Пароль', hint: 'Не короче 6 символов. Передайте его владельцу кафе'),
      ],
      validate: (v) {
        if (v['name']!.isEmpty) return 'Введите название кафе';
        final trial = int.tryParse(v['trial']!);
        if (trial == null || trial < 0 || trial > 365) {
          return 'Пробный период — от 0 до 365 дней';
        }
        return _checkLimit(v['max']!) ?? _checkLogin(v['login']!, v['password']!);
      },
      onSubmit: (v) async {
        try {
          // Если кафе уже создано, а логин не прошёл (занят) — повторно
          // кафе не заводим, только пробуем логин ещё раз
          createdId ??= (await api.post('/api/super/cafes', {
            'name': v['name'],
            'max_branches': int.parse(v['max']!),
            'trial_days': int.parse(v['trial']!),
          }) as Map)['id'] as String;
          await api.post('/api/super/cafes/$createdId/users',
              {'login': v['login'], 'password': v['password']});
          return null;
        } catch (e) {
          return '$e';
        }
      },
    );
    if (createdId != null) _load();
    if (values != null) {
      _toast('Кафе «${values['name']}» создано. Логин: ${values['login']}');
    }
  }

  Future<void> _editCafe(Map<String, dynamic> cafe) async {
    await _form(
      title: 'Кафе «${cafe['name']}»',
      submit: 'Сохранить',
      fields: [
        _Field('name', 'Название', initial: cafe['name'] as String),
        _Field('max', 'Сколько филиалов разрешено',
            initial: '${cafe['max_branches']}',
            number: true,
            hint: 'Сейчас создано: ${cafe['branch_count']}. Если уменьшить ниже, '
                'существующие продолжат работать, но новые создать будет нельзя'),
      ],
      validate: (v) => v['name']!.isEmpty ? 'Введите название' : _checkLimit(v['max']!),
      onSubmit: (v) async {
        try {
          await api.patch('/api/super/cafes/${cafe['id']}',
              {'name': v['name'], 'max_branches': int.parse(v['max']!)});
          return null;
        } catch (e) {
          return '$e';
        }
      },
    ).then((v) {
      if (v != null) {
        _toast('Сохранено');
        _load();
      }
    });
  }

  Future<void> _addUser(Map<String, dynamic> cafe) async {
    final v = await _form(
      title: 'Логин для «${cafe['name']}»',
      submit: 'Создать',
      fields: const [
        _Field('login', 'Логин'),
        _Field('password', 'Пароль', hint: 'Не короче 6 символов'),
      ],
      validate: (v) => _checkLogin(v['login']!, v['password']!),
      onSubmit: (v) async {
        try {
          await api.post('/api/super/cafes/${cafe['id']}/users',
              {'login': v['login'], 'password': v['password']});
          return null;
        } catch (e) {
          return '$e';
        }
      },
    );
    if (v != null) {
      _toast('Логин ${v['login']} создан');
      _load();
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> user) async {
    final v = await _form(
      title: 'Новый пароль для ${user['login']}',
      submit: 'Сменить',
      fields: const [
        _Field('password', 'Новый пароль', hint: 'Текущие входы с этим логином будут закрыты'),
      ],
      validate: (v) => v['password']!.length < 6 ? 'Пароль — не короче 6 символов' : null,
      onSubmit: (v) async {
        try {
          await api.patch('/api/super/users/${user['id']}', {'password': v['password']});
          return null;
        } catch (e) {
          return '$e';
        }
      },
    );
    if (v != null) _toast('Пароль для ${user['login']} изменён');
  }

  /// Подтверждение вводом названия — для необратимых действий.
  Future<bool> _confirmByName(String title, String body, String name) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final matches = ctrl.text.trim() == name;
        return AlertDialog(
          backgroundColor: _surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(body, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 16),
                Text('Введите «$name», чтобы подтвердить:',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (_) => setS(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                disabledBackgroundColor: Colors.white12,
              ),
              onPressed: matches ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Удалить навсегда', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );
    return ok == true;
  }

  Future<void> _deleteCafe(Map<String, dynamic> cafe) async {
    final name = cafe['name'] as String;
    final ok = await _confirmByName(
      'Удалить кафе?',
      'Будут удалены все филиалы (${cafe['branch_count']}), меню и логины «$name». '
          'Восстановить нельзя. Если нужно просто закрыть доступ — заблокируйте кафе.',
      name,
    );
    if (ok) await _run(() => api.delete('/api/super/cafes/${cafe['id']}'), 'Кафе удалено');
  }

  /// Подходит ли кафе под фильтр оплаты (см. [_billing])
  static bool _matchesBilling(Map<String, dynamic> cafe, String filter) => switch (filter) {
        'soon' => cafe['access'] == 'ending' || cafe['access'] == 'grace',
        'expired' => cafe['access'] == 'expired',
        _ => true,
      };

  // ======================================================================
  //  Экран
  // ======================================================================

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final shown = _cafes.where((c) {
      if (!_matchesBilling(c, _billing)) return false;
      if (q.isEmpty) return true;
      final users = (c['users'] as List).map((u) => u['login'] as String);
      return (c['name'] as String).toLowerCase().contains(q) ||
          users.any((l) => l.toLowerCase().contains(q));
    }).toList();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const Icon(Icons.shield_outlined, color: _accent, size: 22),
            const SizedBox(width: 10),
            Text('Платформа · Заведения',
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _createCafe,
            icon: const Icon(Icons.add_business_outlined, color: _accent, size: 18),
            label: const Text('Новое кафе', style: TextStyle(color: _accent)),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.exit_to_app, color: Colors.white38, size: 18),
            label: const Text('Выйти', style: TextStyle(color: Colors.white38)),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : RefreshIndicator(
              onRefresh: _load,
              color: _accent,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Поиск по названию или логину',
                      hintStyle: const TextStyle(color: Colors.white24),
                      prefixIcon: const Icon(Icons.search, color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.04),
                      enabledBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white12)),
                      focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: _accent)),
                    ),
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                  const SizedBox(height: 10),
                  // Кому пора напомнить об оплате — одним нажатием
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (key, label) in [
                        ('all', 'Все'),
                        ('soon', 'Скоро кончается'),
                        ('expired', 'Меню выключено'),
                      ])
                        ChoiceChip(
                          label: Text(key == 'all'
                              ? label
                              : '$label: ${_cafes.where((c) => _matchesBilling(c, key)).length}'),
                          selected: _billing == key,
                          onSelected: (_) => setState(() => _billing = key),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Заведений: ${_cafes.length}',
                      style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 16),
                  if (_cafes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: Center(
                        child: Text('Заведений пока нет — нажмите «Новое кафе»',
                            style: TextStyle(color: Colors.white38)),
                      ),
                    ),
                  for (final c in shown) _cafeCard(c),
                ],
              ),
            ),
    );
  }

  Widget _cafeCard(Map<String, dynamic> cafe) {
    final active = cafe['is_active'] == true;
    final count = cafe['branch_count'] as int;
    final max = cafe['max_branches'] as int;
    final users = List<Map<String, dynamic>>.from(cafe['users'] as List);
    final branches = List<Map<String, dynamic>>.from(cafe['branches'] as List);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: active ? Colors.white.withValues(alpha: 0.08) : Colors.redAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(cafe['name'] as String,
                    style: GoogleFonts.outfit(
                        color: active ? Colors.white : Colors.white54,
                        fontSize: 19,
                        fontWeight: FontWeight.w700)),
              ),
              _chip(active ? 'Активно' : 'Заблокировано',
                  active ? Colors.green : Colors.redAccent),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white54),
                color: _surface,
                onSelected: (a) {
                  switch (a) {
                    case 'edit':
                      _editCafe(cafe);
                    case 'user':
                      _addUser(cafe);
                    case 'block':
                      _run(
                          () => api.patch('/api/super/cafes/${cafe['id']}', {'is_active': !active}),
                          active ? 'Кафе заблокировано' : 'Кафе разблокировано');
                    case 'delete':
                      _deleteCafe(cafe);
                  }
                },
                itemBuilder: (_) => [
                  _menuItem('edit', Icons.edit_outlined, 'Название и лимит'),
                  _menuItem('user', Icons.person_add_alt, 'Добавить логин'),
                  _menuItem('block', active ? Icons.block : Icons.check_circle_outline,
                      active ? 'Заблокировать' : 'Разблокировать'),
                  _menuItem('delete', Icons.delete_outline, 'Удалить кафе', danger: true),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Оплата: до какого числа и кнопка продления
          Builder(builder: (_) {
            final status = accessLabel(cafe);
            return Row(
              children: [
                Icon(Icons.payments_outlined, color: status.color, size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(status.text,
                      style: TextStyle(color: status.color, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () async {
                    if (await showPaymentDialog(context, cafe)) _load();
                  },
                  child: const Text('Оплата', style: TextStyle(color: _accent)),
                ),
              ],
            );
          }),
          const SizedBox(height: 4),

          // Лимит — главное, ради чего этот экран: видно сразу и меняется в один клик
          InkWell(
            onTap: () => _editCafe(cafe),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.storefront_outlined,
                      color: count >= max ? Colors.orangeAccent : _accent, size: 18),
                  const SizedBox(width: 6),
                  Text('Филиалов: $count из $max',
                      style: TextStyle(
                          color: count >= max ? Colors.orangeAccent : Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  const Icon(Icons.edit, color: Colors.white24, size: 14),
                ],
              ),
            ),
          ),
          if (branches.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: branches
                  .map((b) => _chip('${b['name']} · ${b['slug']}', Colors.white38))
                  .toList(),
            ),
          ],
          const SizedBox(height: 14),
          const Text('ЛОГИНЫ',
              style: TextStyle(
                  color: Colors.white38, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (users.isEmpty)
            TextButton.icon(
              onPressed: () => _addUser(cafe),
              icon: const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 16),
              label: const Text('Логина нет — кафе не сможет войти. Создать',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 13)),
            ),
          for (final u in users) _userRow(u),
        ],
      ),
    );
  }

  Widget _userRow(Map<String, dynamic> u) {
    final active = u['is_active'] == true;
    return Row(
      children: [
        Icon(Icons.person_outline, color: active ? Colors.white54 : Colors.white24, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(u['login'] as String,
              style: TextStyle(
                  color: active ? Colors.white : Colors.white38,
                  decoration: active ? null : TextDecoration.lineThrough)),
        ),
        IconButton(
          tooltip: 'Сменить пароль',
          icon: const Icon(Icons.key_outlined, color: Colors.white54, size: 18),
          onPressed: () => _resetPassword(u),
        ),
        IconButton(
          tooltip: active ? 'Заблокировать логин' : 'Разблокировать логин',
          icon: Icon(active ? Icons.lock_outline : Icons.lock_open,
              color: active ? Colors.white54 : Colors.orangeAccent, size: 18),
          onPressed: () => _run(
              () => api.patch('/api/super/users/${u['id']}', {'is_active': !active}),
              active ? 'Логин заблокирован' : 'Логин разблокирован'),
        ),
        IconButton(
          tooltip: 'Удалить логин',
          icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 18),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: _surface,
                title: Text('Удалить логин ${u['login']}?',
                    style: const TextStyle(color: Colors.white)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Отмена')),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Удалить', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
            if (ok == true) {
              _run(() => api.delete('/api/super/users/${u['id']}'), 'Логин удалён');
            }
          },
        ),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String text,
      {bool danger = false}) {
    final color = danger ? Colors.redAccent : Colors.white70;
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Text(text, style: TextStyle(color: color)),
      ]),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 11)),
      );
}

class _Field {
  final String key;
  final String label;
  final String initial;
  final bool number;
  final String? hint;

  const _Field(this.key, this.label, {this.initial = '', this.number = false, this.hint});
}
