import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/i18n.dart';
import 'core/phone_scale/phone_scale.dart';
import 'core/providers.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'features/report/outbox.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadSavedLanguage();
  runApp(const ProviderScope(child: GarazApp()));
}

class GarazApp extends ConsumerStatefulWidget {
  const GarazApp({super.key});

  @override
  ConsumerState<GarazApp> createState() => _GarazAppState();
}

class _GarazAppState extends ConsumerState<GarazApp> {
  @override
  void initState() {
    super.initState();
    // Restore the session before the first redirects settle.
    Future.microtask(() => ref.read(authControllerProvider.notifier).bootstrap());
  }

  @override
  Widget build(BuildContext context) {
    // Starts the outbox at launch: reports saved without a signal go out as soon as they can.
    ref.listen(outboxProvider, (_, _) {});
    final lang = ref.watch(languageProvider);
    return MaterialApp.router(
      title: 'GARAZ',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
      locale: Locale(lang),
      supportedLocales: [for (final l in kLanguages) Locale(l)],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // A phone showing the page as a desktop site still gets a phone-sized app.
      // go_router caches its pages, so a new locale alone leaves most screens in
      // the old language: a new key on the routed subtree rebuilds them all.
      builder: (_, child) => KeyedSubtree(
        key: ValueKey(lang),
        child: PhoneScale(child: child!),
      ),
    );
  }
}
