import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'l10n/app_localizations.dart';
import 'l10n/translation_service.dart';
import 'screens/welcome_screen.dart';
import 'theme/theme_config.dart';
import 'theme/current_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey, // ignore: deprecated_member_use
  );

  // Ориентация задаётся не здесь, а в WelcomeScreen: до первого кадра размер
  // экрана ещё не известен, а телефон и планшет нуждаются в разном поведении.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const CafeAndalusRoot());
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
          return ValueListenableBuilder<AppThemeType>(
            valueListenable: currentTheme,
            builder: (context, themeType, child) {
              final config = ThemeConfig.palettes[themeType]!;
              return MaterialApp(
                title: 'Cafe Andalus',
                debugShowCheckedModeBanner: false,
                locale: locale,
                supportedLocales: const [
                  Locale('ru'),
                  Locale('en'),
                  Locale('tr'),
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
                home: const WelcomeScreen(),
              );
            },
          );
        },
      ),
    );
  }
}
