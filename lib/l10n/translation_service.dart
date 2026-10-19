import 'package:flutter/material.dart';

// Глобальный текущий язык приложения
final ValueNotifier<Locale> currentLocale = ValueNotifier(const Locale('ru'));

/// Язык, который гость выбрал переключателем; null — не выбирал, и меню
/// показывается на языке телефона или основном.
String? chosenLanguage;

void chooseLanguage(String code) {
  chosenLanguage = code;
  currentLocale.value = Locale(code);
}

/// Язык, на котором показывать меню филиала с языками [languages]
/// (первый — основной): выбранный гостем, если он в меню есть; иначе язык
/// телефона гостя; иначе основной.
String pickLanguage(List<String> languages, String? chosen, String device) {
  if (chosen != null && languages.contains(chosen)) return chosen;
  if (languages.contains(device)) return device;
  return languages.first;
}
