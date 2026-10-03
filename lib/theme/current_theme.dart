import 'package:flutter/material.dart';
import 'theme_config.dart';

// Глобальный текущий тип темы
final ValueNotifier<AppThemeType> currentTheme = ValueNotifier(AppThemeType.midnight);
