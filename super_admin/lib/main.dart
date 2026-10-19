import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'api_client.dart';
import 'login_screen.dart';
import 'screens/super_admin_shell.dart';

/// Главная админка платформы — отдельный сайт, только для веба.
/// Раздаётся сервером меню по адресу /menu-kg/.
void main() => runApp(const SuperAdminApp());

class SuperAdminApp extends StatefulWidget {
  const SuperAdminApp({super.key});

  @override
  State<SuperAdminApp> createState() => _SuperAdminAppState();
}

class _SuperAdminAppState extends State<SuperAdminApp> {
  /// Токен только в памяти: перезагрузка страницы — это вход заново
  bool _signedIn = false;

  Future<void> _logout() async {
    await api.logout();
    if (mounted) setState(() => _signedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Главная админка',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: const ColorScheme.dark(primary: Color(0xFFD4AF37)),
        useMaterial3: true,
        fontFamily: GoogleFonts.manrope().fontFamily,
      ),
      home: _signedIn
          ? SuperAdminShell(onLogout: _logout)
          : LoginScreen(onSignedIn: () => setState(() => _signedIn = true)),
    );
  }
}
