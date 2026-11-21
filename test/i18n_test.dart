import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every text the app passes to tr('…') has a version in each language, with the same
/// {placeholders}. Texts without letters to translate ("{label}: {t}") are
/// fine to leave out: they show as they are.
void main() {
  final lit = RegExp(r"(?<![\w.])tr\(\s*'((?:[^'\\\n]|\\.)*)'");
  final placeholder = RegExp(r'\{\w+\}');
  final words = RegExp('[a-ząćęłńóśźż]{3}');

  String unescape(String s) => s.replaceAll(r'\n', '\n').replaceAll(r"\'", "'");

  final used = <String>{};
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
    for (final m in lit.allMatches(f.readAsStringSync())) {
      used.add(unescape(m.group(1)!));
    }
  }

  for (final lang in ['uk', 'en']) {
    final file = (jsonDecode(File('assets/i18n/$lang.json').readAsStringSync()) as Map).cast<String, String>();

    test('$lang: every translatable text has a version', () {
      final missing = [
        for (final k in used)
          if (!file.containsKey(k) && words.hasMatch(k.replaceAll(placeholder, '')) && !k.startsWith('API:')) k,
      ];
      expect(missing, isEmpty);
    });

    test('$lang: translations keep the placeholders', () {
      for (final e in file.entries) {
        final a = placeholder.allMatches(e.key).map((m) => m[0]).toSet();
        final b = placeholder.allMatches(e.value).map((m) => m[0]).toSet();
        expect(b, a, reason: e.key);
      }
    });
  }
}
