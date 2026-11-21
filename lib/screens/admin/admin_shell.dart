import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/current_branch.dart';
import '../../responsive.dart';
import '../../database.dart';
import '../../models/branch.dart';
import 'admin_categories_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_reviews_screen.dart';
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

  /// Широкая вёрстка — планшет-киоск и монитор; узкая — телефон, а заодно
  /// телефон в альбоме: там не хватает высоты, и боковой рейке, которой
  /// нужно ~700 px, стоять негде.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) =>
          Responsive.isWideConstraints(c) ? _wide() : _compact(),
    );
  }

  /// Экраны разделов. Один IndexedStack на обе вёрстки: он держит все
  /// экраны живыми, поэтому «Заказы» и «Отзывы» получают признак
  /// активности — иначе опрос сервера шёл бы и с закрытых вкладок.
  Widget _pages() => IndexedStack(
    index: _selectedIndex,
    children: [
      AdminOrdersScreen(active: _selectedIndex == 0),
      AdminReviewsScreen(active: _selectedIndex == 1),
      const AdminCategoriesScreen(),
      const AdminProductsScreen(),
      const AdminShopScreen(),
      const AdminStyleScreen(),
    ],
  );

  Widget _wide() {
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

                // Навигационные кнопки. «Заказы» первыми: в них заходят
                // десятки раз в день, и только там видно заказ целиком
                _NavItem(
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long,
                  label: 'Заказы',
                  isActive: _selectedIndex == 0,
                  onTap: () => setState(() => _selectedIndex = 0),
                ),
                const SizedBox(height: 6),
                _NavItem(
                  icon: Icons.star_border_rounded,
                  activeIcon: Icons.star_rounded,
                  label: 'Отзывы',
                  isActive: _selectedIndex == 1,
                  onTap: () => setState(() => _selectedIndex = 1),
                ),
                const SizedBox(height: 6),
                _NavItem(
                  icon: Icons.category_outlined,
                  activeIcon: Icons.category,
                  label: 'Категории',
                  isActive: _selectedIndex == 2,
                  onTap: () => setState(() => _selectedIndex = 2),
                ),
                const SizedBox(height: 6),
                _NavItem(
                  icon: Icons.fastfood_outlined,
                  activeIcon: Icons.fastfood,
                  label: 'Товары',
                  isActive: _selectedIndex == 3,
                  onTap: () => setState(() => _selectedIndex = 3),
                ),
                const SizedBox(height: 6),
                _NavItem(
                  icon: Icons.store_outlined,
                  activeIcon: Icons.store,
                  label: 'Филиал',
                  isActive: _selectedIndex == 4,
                  onTap: () => setState(() => _selectedIndex = 4),
                ),
                const SizedBox(height: 6),
                _NavItem(
                  icon: Icons.palette_outlined,
                  activeIcon: Icons.palette,
                  label: 'Оформление',
                  isActive: _selectedIndex == 5,
                  onTap: () => setState(() => _selectedIndex = 5),
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
                Expanded(child: _pages()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- телефон

  /// Телефонная вёрстка: разделы — нижней панелью, а не колонкой слева.
  /// Колонка забирала 120 px из 360 — треть экрана у того, ради чего в
  /// админку и заходят.
  Widget _compact() {
    return Scaffold(
      backgroundColor: _bgColor,
      // Клавиатуру вычитает из себя внутренний Scaffold экрана. Если и
      // этот начнёт её вычитать, вычтется дважды — и экрану достанется
      // отрицательная высота. Нижняя панель на время набора прячется под
      // клавиатурой, как везде на телефоне
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          const BillingBanner(),
          _branchStrip(),
          Expanded(child: _pages()),
        ],
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  /// Какой филиал сейчас правим. В широкой вёрстке это видно в рейке
  /// всегда; на телефоне без такой строки легко переписать меню не тому
  /// залу.
  Widget _branchStrip() => ValueListenableBuilder<Branch?>(
    valueListenable: currentBranch,
    builder: (context, branch, child) => Material(
      color: _surfaceColor,
      child: InkWell(
        onTap: _switchBranch,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.store_outlined, color: _accentColor, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  branch?.name ?? 'Филиал не выбран',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(Icons.expand_more, color: Colors.white38, size: 18),
            ],
          ),
        ),
      ),
    ),
  );

  /// Нижняя панель: три самых частых раздела и «Ещё».
  ///
  /// Кнопки — тот же _NavItem, что в рейке: одинаковый вид и одинаковые
  /// цвета. Готовый NavigationBar взял бы цвета из темы приложения, а она
  /// следует оформлению кафе и бывает светлой — админка же всегда тёмная.
  /// Разделы, спрятанные в шторку «Ещё»: индекс → иконка и подпись.
  /// Пока открыт такой раздел, четвёртая кнопка показывает его, а не
  /// «Ещё»: иначе на телефоне не видно, где ты находишься.
  static const _more = {
    2: (Icons.category_outlined, Icons.category, 'Категории'),
    4: (Icons.store_outlined, Icons.store, 'Филиал'),
    5: (Icons.palette_outlined, Icons.palette, 'Оформление'),
  };

  Widget _bottomBar() {
    final more = _more[_selectedIndex];
    return Container(
      color: _surfaceColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: _NavItem(
                  key: const Key('nav_orders'),
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long,
                  label: 'Заказы',
                  isActive: _selectedIndex == 0,
                  onTap: () => setState(() => _selectedIndex = 0),
                ),
              ),
              Expanded(
                child: _NavItem(
                  key: const Key('nav_reviews'),
                  icon: Icons.star_border_rounded,
                  activeIcon: Icons.star_rounded,
                  label: 'Отзывы',
                  isActive: _selectedIndex == 1,
                  onTap: () => setState(() => _selectedIndex = 1),
                ),
              ),
              Expanded(
                child: _NavItem(
                  key: const Key('nav_products'),
                  icon: Icons.fastfood_outlined,
                  activeIcon: Icons.fastfood,
                  label: 'Товары',
                  isActive: _selectedIndex == 3,
                  onTap: () => setState(() => _selectedIndex = 3),
                ),
              ),
              Expanded(
                child: _NavItem(
                  key: const Key('nav_more'),
                  icon: more?.$1 ?? Icons.more_horiz,
                  activeIcon: more?.$2 ?? Icons.more_horiz,
                  label: more?.$3 ?? 'Ещё',
                  isActive: more != null,
                  onTap: _showMore,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Остальное: редкие разделы, смена филиала и выход.
  void _showMore() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _moreItem(ctx, Icons.category_outlined, 'Категории', index: 2),
            _moreItem(ctx, Icons.store_outlined, 'Филиал', index: 4),
            _moreItem(ctx, Icons.palette_outlined, 'Оформление', index: 5),
            Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
            _moreItem(
              ctx,
              Icons.swap_horiz,
              'Сменить филиал',
              onTap: _switchBranch,
            ),
            _moreItem(
              ctx,
              Icons.exit_to_app,
              'Выйти из админки',
              // Закрывает админку; сессию снимет welcome_screen
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moreItem(
    BuildContext sheet,
    IconData icon,
    String label, {
    int? index,
    VoidCallback? onTap,
  }) {
    final isActive = index != null && index == _selectedIndex;
    return ListTile(
      leading: Icon(icon, color: isActive ? _accentColor : Colors.white54),
      title: Text(
        label,
        style: GoogleFonts.manrope(
          color: isActive ? _accentColor : Colors.white,
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      onTap: () {
        Navigator.pop(sheet);
        if (index != null) {
          setState(() => _selectedIndex = index);
        } else {
          onTap!();
        }
      },
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
    super.key,
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
          // min обязателен: в нижней панели Row отдаёт детям всю высоту
          // экрана, и кнопка растянулась бы во весь экран
          mainAxisSize: MainAxisSize.min,
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
