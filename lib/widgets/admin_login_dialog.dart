import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../config/server_config.dart';

/// Вход по логину и паролю. Возвращает [Me] вошедшего или null при отмене.
///
/// Пускает только администраторов кафе. Логины выдаёт главный
/// администратор платформы в своей веб-админке (/menu-kg/).
/// Регистрации в приложении нет намеренно: иначе любой посетитель
/// создал бы себе аккаунт и получил право править меню.
Future<Me?> showAdminLogin(BuildContext context) =>
    showDialog<Me>(context: context, builder: (_) => const AdminLoginDialog());

class AdminLoginDialog extends StatefulWidget {
  const AdminLoginDialog({super.key});

  @override
  State<AdminLoginDialog> createState() => _AdminLoginDialogState();
}

class _AdminLoginDialogState extends State<AdminLoginDialog> {
  final _loginCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String? _errorText;
  bool _busy = false;

  static const _accent = Color(0xFFD4AF37);

  @override
  void dispose() {
    _loginCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final login = _loginCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (login.isEmpty || password.isEmpty) {
      setState(() => _errorText = 'Введите логин и пароль');
      return;
    }

    setState(() {
      _busy = true;
      _errorText = null;
    });

    try {
      final me = await api.login(login, password);
      // Главная админка платформы — отдельный сайт, в приложении меню
      // (и тем более на планшете в зале) её нет
      if (me.isSuper) {
        await api.logout();
        throw ApiException(403,
            'Главная админка открывается только в браузере: $serverUrl/menu-kg/');
      }
      if (mounted) Navigator.pop(context, me);
    } on ApiException catch (e) {
      // Сервер отвечает одинаково и на неизвестный логин, и на неверный
      // пароль — это защита от перебора, показываем его текст как есть.
      if (mounted) {
        setState(() {
          _busy = false;
          _errorText = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _errorText = 'Нет связи с сервером: $e';
        });
      }
    }
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
      prefixIcon: Icon(icon, color: Colors.white38, size: 18),
      enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.white24)),
      focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: _accent)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.admin_panel_settings, color: _accent, size: 20),
          SizedBox(width: 8),
          Text('Режим администратора',
              style: TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _loginCtrl,
              autofocus: true,
              enabled: !_busy,
              autocorrect: false,
              style: const TextStyle(color: Colors.white),
              decoration: _decoration('Логин', Icons.person_outline),
              onChanged: (_) {
                if (_errorText != null) setState(() => _errorText = null);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              enabled: !_busy,
              style: const TextStyle(color: Colors.white),
              decoration: _decoration('Пароль', Icons.lock_outline),
              onChanged: (_) {
                if (_errorText != null) setState(() => _errorText = null);
              },
              onSubmitted: (_) => _signIn(),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.redAccent, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _errorText!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: _accent, foregroundColor: Colors.black),
          onPressed: _busy ? null : _signIn,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.black),
                )
              : const Text('Войти',
                  style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
