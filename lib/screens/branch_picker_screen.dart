import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../api/api_client.dart';
import '../config/current_branch.dart';
import '../database.dart';
import '../models/branch.dart';
import '../theme/current_theme.dart';
import '../theme/theme_config.dart';
import '../widgets/admin_login_dialog.dart';
import '../widgets/auth_image.dart';

/// Выбор филиала. Появляется, только когда филиал неизвестен: на планшете
/// при первой установке или в вебе, если ссылку открыли без `?branch=`.
///
/// В базе меню многих кафе, поэтому гостю список не показывается: он
/// попадает в меню по QR-коду. Планшет настраивает сотрудник — входит
/// своим логином и выбирает филиал своего кафе.
///
/// Экран не переходит никуда сам — он лишь выставляет [currentBranch],
/// а подмену на главный экран делает `home` в main.dart. Иначе выбор
/// филиала и смена `home` сработали бы одновременно и дали два перехода.
class BranchPickerScreen extends StatefulWidget {
  const BranchPickerScreen({super.key});

  @override
  State<BranchPickerScreen> createState() => _BranchPickerScreenState();
}

class _BranchPickerScreenState extends State<BranchPickerScreen> {
  final DatabaseService _db = DatabaseService();

  List<Branch> _branches = [];
  bool _loading = false;
  bool _selecting = false;

  /// Вошёл сотрудник кафе — показываем его филиалы
  bool _signedIn = false;

  /// Список филиалов не получен: нет связи или ошибка сервера
  String? _error;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // Ушли с экрана, не выбрав филиал — вход не должен остаться висеть
    if (_signedIn && !_selecting) api.logout();
    super.dispose();
  }

  Future<void> _signIn() async {
    final me = await showAdminLogin(context);
    if (me == null || !mounted) return;

    setState(() => _signedIn = true);
    final branches = await _loadBranches();

    // Единственный филиал выбирать не о чем — сразу открываем его.
    if (branches.length == 1) _select(branches.first);
  }

  /// Ошибка связи показывается как ошибка, а не как «филиалов нет».
  Future<List<Branch>> _loadBranches() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    List<Branch> branches = const [];
    String? error;
    try {
      branches = await _db.getBranches();
    } catch (e) {
      error = '$e';
    }
    if (mounted) {
      setState(() {
        _branches = branches;
        _error = error;
        _loading = false;
      });
    }
    return branches;
  }

  Future<void> _select(Branch branch) async {
    if (_selecting) return;
    setState(() => _selecting = true);
    HapticFeedback.selectionClick();
    await saveBranchSlug(branch.slug);
    // Филиал запомнен — вход больше не нужен, админка спросит пароль заново
    await api.logout();
    currentBranch.value = branch;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeConfig>(
      valueListenable: appTheme,
      builder: (context, config, child) {

        return Scaffold(
          backgroundColor: config.bg,
          body: SafeArea(
            child: Center(
              child: _loading
                  ? CircularProgressIndicator(color: config.accent)
                  : !_signedIn
                      ? _buildWelcome(config)
                      : _branches.isEmpty
                          ? _buildEmpty(config)
                          : _buildList(config),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWelcome(ThemeConfig config) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_scanner_rounded,
              size: 64, color: config.accent.withValues(alpha: 0.7)),
          const SizedBox(height: 20),
          Text(
            'Отсканируйте QR-код',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: config.text,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Меню откроется по QR-коду на столе заведения.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: config.text.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 40),
          TextButton.icon(
            onPressed: _signIn,
            icon: Icon(Icons.login, color: config.text.withValues(alpha: 0.5), size: 18),
            label: Text('Вход для сотрудников',
                style: TextStyle(color: config.text.withValues(alpha: 0.5))),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeConfig config) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.storefront_outlined,
              size: 64, color: config.text.withValues(alpha: 0.3)),
          const SizedBox(height: 20),
          Text(
            _error ?? 'Филиалы не найдены',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: config.text,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _error != null
                ? 'Проверьте подключение к интернету и повторите.'
                : 'Создайте филиал в главной админке.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: config.text.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 30),
          OutlinedButton.icon(
            onPressed: _loadBranches,
            icon: Icon(Icons.refresh, color: config.accent, size: 18),
            label: Text('Повторить', style: TextStyle(color: config.accent)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: config.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ThemeConfig config) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'ВЫБЕРИТЕ ФИЛИАЛ',
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: config.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Сохранится на этом устройстве. Поменять можно в админке.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 13,
              color: config.text.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 35),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              children: _branches
                  .map((b) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _buildTile(b, config),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(Branch branch, ThemeConfig config) {
    return GestureDetector(
      onTap: _selecting ? null : () => _select(branch),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: config.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: config.accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AuthImage(
                url: branch.logoUrl,
                width: 58,
                height: 58,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    branch.name,
                    style: GoogleFonts.outfit(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: config.text,
                    ),
                  ),
                  if (branch.slogan.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      branch.slogan,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: config.text.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 18, color: config.accent),
          ],
        ),
      ),
    );
  }
}
