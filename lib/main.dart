import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/phone_scale/phone_scale.dart';
import 'core/providers.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'features/report/outbox.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
    return MaterialApp.router(
      title: 'GARAZ',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
      locale: const Locale('pl'),
      supportedLocales: const [Locale('pl')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // A phone showing the page as a desktop site still gets a phone-sized app.
      builder: (_, child) => PhoneScale(child: child!),
    );
  }
}
