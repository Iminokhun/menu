import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/current_branch.dart';
import '../../database.dart';
import '../../models/branch.dart';
import 'admin_categories_screen.dart';
import 'admin_products_screen.dart';
import 'admin_shop_screen.dart';
import 'admin_style_screen.dart';
import 'billing_banner.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selectedIndex = 0;

  static const _accentColor = Color(0xFFD4AF37);
  static const _bgColor = Color(0xFF0A0A0A);
  static const _surfaceColor = Color(0xFF1A1A1A);

  /// Переключение филиала. Меняет [currentBranch], на который подписаны
  /// все три экрана админки и экран гостя, и запоминает выбор на
  /// устройстве — чтобы планшет после перезапуска открыл тот же зал.
  Future<void> _switchBranch() async {
    List<Branch> branches;
    String? error;
    try {
      branches = await DatabaseService().getBranches();
      if (branches.isEmpty) error = 'Филиалы не найдены';
    } catch (e) {
      branches = const [];
      error = '$e';
    }
    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    final picked = await showDialog<Branch>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: _surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Филиал', style: TextStyle(color: Colors.white, fontSize: 18)),
        children: branches.map((b) {
          final isActive = b.id == currentBranch.value?.id;
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, b),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    isActive ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: isActive ? _accentColor : Colors.white24,
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      b.name,
                      style: TextStyle(
                        color: isActive ? Colors.white : Colors.white70,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  Text(b.slug, style: const TextStyle(color: Colors.white24, fontSize: 11)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );

    if (picked == null || picked.id == currentBranch.value?.id) return;
    await saveBranchSlug(picked.slug);
    currentBranch.value = picked;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: Row(
        children: [
          // === БОКОВАЯ НАВИГАЦИЯ ===
          Container(
            width: 120,
            color: _surfaceColor,
            child: Column(
              children: [
                const SizedBox(height: 30),

                // Лого
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _accentColor, width: 2),
                  ),
                  child: const Icon(Icons.admin_panel_settings, color: _accentColor, size: 26),
                ),
                const SizedBox(height: 6),
                Text(
                  'ADMIN',
                  style: GoogleFonts.manrope(
                    color: _accentColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),

                const SizedBox(height: 16),
                Divider(color: Colors.white.withValues(alpha: 0.1)),

                // Текущий филиал: видно сразу, в каком зале правишь меню
                ValueListenableBuilder<Branch?>(
                  valueListenable: currentBranch,
                  builder: (context, branch, child) => InkWell(
                    onTap: _switchBranch,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.swap_horiz, color: _accentColor, size: 18),
                          const SizedBox(height: 4),
                          Text(
                            branch?.name ?? 'не выбран',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              color: Colors.white70,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                Divider(color: Colors.white.withValues(alpha: 0.1)),
                const SizedBox(height: 10),

                // Навигационные кнопки
                _NavItem(
                  icon: Icons.category_outlined,
                  activeIcon: Icons.category,
                  label: 'Категории',
                  isActive: _selectedIndex == 0,
                  onTap: () => setState(() => _selectedIndex = 0),
                ),
                const SizedBox(height: 6),
                _NavItem(
                  icon: Icons.fastfood_outlined,
                  activeIcon: Icons.fastfood,
                  label: 'Товары',
                  isActive: _selectedIndex == 1,
                  onTap: () => setState(() => _selectedIndex = 1),
                ),
                const SizedBox(height: 6),
                _NavItem(
                  icon: Icons.store_outlined,
                  activeIcon: Icons.store,
                  label: 'Филиал',
                  isActive: _selectedIndex == 2,
                  onTap: () => setState(() => _selectedIndex = 2),
                ),
                const SizedBox(height: 6),
                _NavItem(
                  icon: Icons.palette_outlined,
                  activeIcon: Icons.palette,
                  label: 'Оформление',
                  isActive: _selectedIndex == 3,
                  onTap: () => setState(() => _selectedIndex = 3),
                ),

                const Spacer(),

                // Выход закрывает админку и завершает сессию: её снимает
                // welcome_screen сразу после возврата, поэтому отдельной
                // кнопки «выйти из аккаунта» здесь не нужно
                InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    child: Column(
                      children: [
                        const Icon(Icons.exit_to_app, color: Colors.white38, size: 24),
                        const SizedBox(height: 4),
                        Text(
                          'Выйти',
                          style: GoogleFonts.manrope(
                            color: Colors.white38,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),

          // Разделитель
          Container(width: 1, color: Colors.white.withValues(alpha: 0.08)),

          // === ОСНОВНОЙ КОНТЕНТ ===
          Expanded(
            child: Column(
              children: [
                const BillingBanner(),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: const [
                      AdminCategoriesScreen(),
                      AdminProductsScreen(),
                      AdminShopScreen(),
                      AdminStyleScreen(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFD4AF37);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 10),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isActive ? Border.all(color: accent.withValues(alpha: 0.4)) : null,
        ),
        child: Column(
          children: [
            Icon(isActive ? activeIcon : icon, color: isActive ? accent : Colors.white38, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                color: isActive ? accent : Colors.white38,
                fontSize: 9,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
