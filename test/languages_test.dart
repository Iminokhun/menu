import 'dart:io';

import 'package:cafe_andalus_menu/l10n/app_localizations.dart';
import 'package:cafe_andalus_menu/l10n/languages.dart';
import 'package:cafe_andalus_menu/l10n/translation_service.dart';
import 'package:cafe_andalus_menu/models/branch.dart';
import 'package:cafe_andalus_menu/models/product.dart';
import 'package:cafe_andalus_menu/screens/admin/translations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('список языков', () {
    final codes = menuLanguages.map((l) => l.code).toList();

    test('совпадает со списком сервера', () {
      final server = File('server/lib/languages.dart').readAsStringSync();
      final list = RegExp(r'menuLanguages = \[([^\]]*)\]').firstMatch(server)!;
      final serverCodes =
          RegExp(r"'(\w+)'").allMatches(list[1]!).map((m) => m[1]).toList();
      expect(serverCodes, codes);
    });

    test('на каждый язык переведены все кнопки меню', () {
      final keys = AppLocalizations.keysByLanguage;
      expect(keys.keys.toSet(), codes.toSet());
      for (final code in codes) {
        expect(keys[code], keys['ru'], reason: 'язык $code');
      }
    });
  });

  group('язык гостя', () {
    test('выбранный гостем, если он есть в меню', () {
      expect(pickLanguage(['ky', 'ru', 'en'], 'en', 'ru'), 'en');
    });
    test('гость не выбирал — язык телефона, а не прежний на экране', () {
      expect(pickLanguage(['ky', 'ru', 'en'], null, 'en'), 'en');
    });
    test('иначе язык телефона', () {
      expect(pickLanguage(['ky', 'ru', 'en'], 'tr', 'ru'), 'ru');
    });
    test('иначе основной язык филиала', () {
      expect(pickLanguage(['ky', 'en'], 'tr', 'de'), 'ky');
    });
  });

  group('филиал', () {
    test('языки с сервера, неизвестные пропускаются', () {
      final b = Branch.fromJson({
        'id': 'b',
        'languages': ['ky', 'xx', 'en', 5],
      });
      expect(b.languages, ['ky', 'en']);
      expect(b.mainLanguage, 'ky');
    });
    test('без языков (старый сервер, старая копия меню) — русский', () {
      expect(Branch.fromJson({'id': 'b'}).languages, ['ru']);
      expect(Branch.fromJson({'id': 'b', 'languages': []}).languages, ['ru']);
    });
  });

  group('блюдо', () {
    final dish = Product.dishFromJson({
      'id': 'd',
      'name': 'Борщ',
      'description': 'Со сметаной',
      'i18n': {
        'en': {'name': 'Borscht', 'description': ''},
        'ky': 'не перевод',
        'tr': {'name': 7},
      },
    });

    test('перевод, если есть; иначе основной текст', () {
      expect(dish.localizedName('en'), 'Borscht');
      expect(dish.localizedDesc('en'), 'Со сметаной');
      expect(dish.localizedName('de'), 'Борщ');
    });
    test('переводы неожиданного вида не ломают блюдо', () {
      expect(dish.localizedName('ky'), 'Борщ');
      expect(dish.localizedName('tr'), 'Борщ');
    });
    test('для поиска — названия на всех языках', () {
      expect(dish.allNames, ['Борщ', 'Borscht']);
    });
  });

  group('поля переводов в админке', () {
    test('поля — на дополнительные языки, основной пропускается', () {
      final t = Translations(null, ['ru', 'en', 'ky'], ['name']);
      expect(t.languages, ['en', 'ky']);
    });

    test('перевод на убранный из филиала язык сохраняется', () {
      final t = Translations(
        {
          'en': {'name': 'Soup'},
          'tr': {'name': 'Çorba'},
        },
        ['ru', 'en'],
        ['name'],
      );
      t.controller('en', 'name').text = ' Soup of the day ';
      expect(t.toJson(), {
        'tr': {'name': 'Çorba'},
        'en': {'name': 'Soup of the day'},
      });
    });

    test('стёртый перевод убирается', () {
      final t = Translations(
        {
          'en': {'name': 'Soup'},
        },
        ['ru', 'en'],
        ['name'],
      );
      t.controller('en', 'name').text = '';
      expect(t.toJson(), isEmpty);
    });
  });
}
