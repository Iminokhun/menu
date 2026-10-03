import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'admin_categories_screen.dart';
import 'admin_products_screen.dart';
import 'admin_shop_screen.dart';

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

                const SizedBox(height: 20),
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
                  label: 'Магазин',
                  isActive: _selectedIndex == 2,
                  onTap: () => setState(() => _selectedIndex = 2),
                ),

                const Spacer(),

                // Кнопка выхода
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
            child: IndexedStack(
              index: _selectedIndex,
              children: const [
                AdminCategoriesScreen(),
                AdminProductsScreen(),
                AdminShopScreen(),
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
