import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config/current_branch.dart';
import 'menu_store.dart';
import 'l10n/app_localizations.dart';
import 'l10n/languages.dart';
import 'l10n/translation_service.dart';
import 'models/branch.dart';
import 'screens/branch_picker_screen.dart';
import 'screens/menu_unavailable_screen.dart';
import 'screens/no_connection_screen.dart';
import 'screens/welcome_screen.dart';
import 'theme/theme_config.dart';
import 'theme/current_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Филиал определяем до первого кадра: ссылка `?branch=` в вебе, иначе
  // настройка, сохранённая на устройстве. Если ни того ни другого нет —
  // currentBranch останется null и откроется экран выбора.
  //
  // Меню берётся из сохранённой на устройстве копии — так оно открывается
  // и без интернета; свежее догружается следом.
  menuStore.data.addListener(_syncBranch);
  menuStore.status.addListener(_syncBranch);
  currentBranch.addListener(_syncTheme);
  currentBranch.addListener(_syncLanguage);
  final slug = await resolveBranchSlug();
  if (slug != null) await menuStore.open(slug);

  // Ориентация задаётся не здесь, а в WelcomeScreen: до первого кадра размер
  // экрана ещё не известен, а телефон и планшет нуждаются в разном поведении.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const CafeAndalusRoot());
}

/// Филиал на экране — тот, чьё меню загружено. Пустое меню сбрасывает
/// филиал, только если филиала больше нет: при обрыве сети остаётся копия.
void _syncBranch() {
  final menu = menuStore.data.value;
  if (menu != null) {
    final b = menu.branch;
    final cur = currentBranch.value;
    // Тот же филиал без изменений не переназначаем: иначе открытая админка
    // перечитала бы форму и потеряла несохранённые правки
    final same = cur != null &&
        cur.id == b.id &&
        cur.slug == b.slug &&
        cur.name == b.name &&
        cur.slogan == b.slogan &&
        cur.phone == b.phone &&
        cur.logoUrl == b.logoUrl &&
        cur.qrUrl == b.qrUrl &&
        cur.style == b.style &&
        listEquals(cur.languages, b.languages);
    if (!same) currentBranch.value = b;
  } else if (menuStore.status.value == MenuResult.notFound ||
      menuStore.status.value == MenuResult.unpaid) {
    currentBranch.value = null;
  }
}

/// Оформление, заданное кафе, применяется сразу: после «Сохранить» в
/// админке и после «Обновить» на экране гостя.
BranchStyle? _appliedStyle;
void _syncTheme() {
  final style = currentBranch.value?.style ?? const BranchStyle();
  if (style == _appliedStyle) return; // не перестраиваем всё приложение зря
  _appliedStyle = style;
  appTheme.value = ThemeConfig.forStyle(style);
}

/// Язык меню — один из языков филиала: кафе могло убрать язык, на котором
/// гость читал, или гость открыл другой филиал.
void _syncLanguage() {
  final branch = currentBranch.value;
  if (branch == null) return;
  final lang = pickLanguage(
    branch.languages,
    chosenLanguage,
    PlatformDispatcher.instance.locale.languageCode,
  );
  if (lang != currentLocale.value.languageCode) {
    currentLocale.value = Locale(lang);
  }
}

class CafeAndalusRoot extends StatelessWidget {
  const CafeAndalusRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: ValueListenableBuilder<Locale>(
        valueListenable: currentLocale,
        builder: (context, locale, child) {
          return ValueListenableBuilder<ThemeConfig>(
            valueListenable: appTheme,
            builder: (context, config, child) {
              return MaterialApp(
                title: 'menu.kg',
                debugShowCheckedModeBanner: false,
                locale: locale,
                supportedLocales: [
                  for (final l in menuLanguages) Locale(l.code),
                ],
                localizationsDelegates: const [
                  AppLocalizationsDelegate(),
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                theme: ThemeData(
                  brightness: config.brightness,
                  scaffoldBackgroundColor: config.bg,
                  useMaterial3: true,
                  textTheme: TextTheme(bodyMedium: GoogleFonts.manrope()),
                ),
                // Экран выбора филиала и главный экран подменяются здесь,
                // а не переходом в Navigator: сам выбор только выставляет
                // currentBranch, и смена филиала из админки работает так же.
                home: ValueListenableBuilder<Branch?>(
                  valueListenable: currentBranch,
                  builder: (context, branch, child) => branch != null
                      ? const WelcomeScreen()
                      // Филиал известен, но меню ни разу не скачивалось и
                      // сети нет — выбор филиала тут не поможет
                      : ValueListenableBuilder<MenuResult?>(
                          valueListenable: menuStore.status,
                          builder: (context, status, child) => switch (status) {
                            MenuResult.unpaid => const MenuUnavailableScreen(),
                            MenuResult.offlineNoCache when menuStore.slug != null =>
                              const NoConnectionScreen(),
                            _ => const BranchPickerScreen(),
                          },
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
