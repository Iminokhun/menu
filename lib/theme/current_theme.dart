import 'package:flutter/material.dart';

import '../models/branch.dart';
import 'theme_config.dart';

/// Тема меню на экране. Её задаёт кафе в админке («Оформление»), а
/// main.dart пересчитывает при каждой смене филиала или его оформления.
final ValueNotifier<ThemeConfig> appTheme =
    ValueNotifier(ThemeConfig.forStyle(const BranchStyle()));
