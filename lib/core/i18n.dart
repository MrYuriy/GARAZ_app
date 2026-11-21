import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Interface languages. Polish is the default and the source: the texts in the
/// code are Polish and serve as the keys; `assets/i18n/<lang>.json` maps them
/// to another language. A text missing from a file shows in Polish, so a half
/// translation degrades to Polish, never to a raw key.
///
/// Only the interface changes: reports, PDF cards and the Excel files the
/// server makes stay Polish, and so do the dictionaries' entries (data).
const kLanguages = ['pl', 'uk', 'en'];
const kDefaultLanguage = 'pl';
const _kStorageKey = 'garaz_ui_lang';

const kLanguageNames = {'pl': 'Polski', 'uk': 'Українська', 'en': 'English'};

class I18n {
  I18n._();
  static final I18n instance = I18n._();

  Map<String, String> _active = const {};
  String lang = kDefaultLanguage;

  Future<void> load(String l) async {
    lang = kLanguages.contains(l) ? l : kDefaultLanguage;
    if (lang == kDefaultLanguage) {
      _active = const {};
      return;
    }
    try {
      final raw = await rootBundle.loadString('assets/i18n/$lang.json');
      _active = (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      _active = const {};
    }
  }

  String t(String text, [Map<String, Object?>? params]) {
    var s = _active[text] ?? text;
    if (params != null) params.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }
}

/// The text in the chosen language; `{name}` placeholders filled from [params].
/// Usable anywhere: the whole app rebuilds on a language change.
String tr(String text, [Map<String, Object?>? params]) => I18n.instance.t(text, params);

/// Loads the saved choice before the first frame (Polish when there is none).
Future<void> loadSavedLanguage([FlutterSecureStorage storage = const FlutterSecureStorage()]) async {
  String? saved;
  try {
    saved = await storage.read(key: _kStorageKey);
  } catch (_) {}
  await I18n.instance.load(saved ?? kDefaultLanguage);
}

class LanguageController extends Notifier<String> {
  static const _storage = FlutterSecureStorage();

  @override
  String build() => I18n.instance.lang;

  Future<void> set(String l) async {
    if (!kLanguages.contains(l) || l == state) return;
    await I18n.instance.load(l);
    try {
      await _storage.write(key: _kStorageKey, value: l);
    } catch (_) {}
    state = l;
  }
}

final languageProvider = NotifierProvider<LanguageController, String>(LanguageController.new);

/// "PL" / "UA" / "EN" in a corner: opens the list of languages.
class LanguageButton extends ConsumerWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    return PopupMenuButton<String>(
      tooltip: tr('Język'),
      initialValue: lang,
      onSelected: (l) => ref.read(languageProvider.notifier).set(l),
      itemBuilder: (_) => [
        for (final l in kLanguages)
          PopupMenuItem(
            value: l,
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text(_code(l), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text(kLanguageNames[l]!),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.translate, size: 20),
            const SizedBox(width: 6),
            Text(_code(lang), style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  static String _code(String l) => l == 'uk' ? 'UA' : l.toUpperCase();
}
