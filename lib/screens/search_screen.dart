import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../menu_store.dart';
import '../models/product.dart';
import '../responsive.dart';
import '../search.dart';
import '../theme/current_theme.dart';
import '../theme/theme_config.dart';
import '../widgets/motion.dart';
import '../widgets/product_card.dart';

/// Поиск блюд по всему меню филиала. Ищет по уже загруженному меню,
/// поэтому работает мгновенно и без интернета.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  List<Product> _results = const [];

  @override
  void initState() {
    super.initState();
    // Меню обновили, пока поиск открыт, — результаты пересчитываются
    menuStore.data.addListener(_search);
  }

  @override
  void dispose() {
    menuStore.data.removeListener(_search);
    _query.dispose();
    super.dispose();
  }

  void _search() {
    if (!mounted) return;
    setState(() {
      _results = searchDishes(menuStore.data.value?.items ?? const [], _query.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = appTheme.value;
    final l = AppLocalizations.of(context);
    final isDesktop = Responsive.isWide(MediaQuery.of(context).size);

    return Scaffold(
      backgroundColor: config.bg,
      appBar: AppBar(
        backgroundColor: config.surface,
        foregroundColor: config.text,
        titleSpacing: 0,
        // Поле — отдельная скруглённая плашка со значком: сразу видно,
        // куда печатать, а не просто курсор в шапке
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextField(
            controller: _query,
            autofocus: true,
            onChanged: (_) => _search(),
            textInputAction: TextInputAction.search,
            style: GoogleFonts.manrope(fontSize: 17, color: config.text),
            cursorColor: config.accent,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: config.text.withValues(alpha: 0.06),
              hintText: l.searchHint,
              hintStyle: TextStyle(color: config.text.withValues(alpha: 0.4)),
              prefixIcon: Icon(Icons.search_rounded, color: config.accent),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close_rounded, color: config.text.withValues(alpha: 0.6)),
                      onPressed: () {
                        _query.clear();
                        _search();
                      },
                    ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: config.accent.withValues(alpha: 0.6)),
              ),
            ),
          ),
        ),
      ),
      // Подсказка, «ничего не найдено» и результаты сменяют друг друга
      // плавно, а не рывком на каждую букву
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: _query.text.trim().isEmpty
            ? _hint(config, Icons.search_rounded, l.searchStart)
            : _results.isEmpty
                ? _hint(config, Icons.search_off_rounded, l.nothingFound)
                : CustomScrollView(
                    key: const ValueKey('results'),
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(isDesktop ? 40 : 20, 16, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            '${l.found}: ${_results.length}',
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              color: config.text.withValues(alpha: 0.5),
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(isDesktop ? 40 : 20, 12, isDesktop ? 40 : 20, 40),
                        sliver: SliverGrid(
                          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: (isDesktop ? 260 : 300) * config.gridScale,
                            childAspectRatio: isDesktop ? 0.65 : 0.7,
                            crossAxisSpacing: isDesktop ? 25 : 15,
                            mainAxisSpacing: isDesktop ? 25 : 15,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => FadeSlideIn(
                              key: ValueKey(_results[i].id),
                              index: i,
                              child: LuxuryCard(
                                product: _results[i],
                                config: config,
                                onAdd: addToCart,
                              ),
                            ),
                            childCount: _results.length,
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _hint(ThemeConfig config, IconData icon, String text) {
    return Center(
      key: ValueKey(text),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: config.text.withValues(alpha: 0.25)),
          const SizedBox(height: 12),
          Text(
            text,
            style: GoogleFonts.manrope(fontSize: 16, color: config.text.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }
}
