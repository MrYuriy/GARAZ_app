import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/forklift_loader.dart';

/// Whether the start screen has played its animation through once; the router
/// keeps the start screen until then, however fast the session is known.
final splashShownProvider = StateProvider<bool>((_) => false);

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(child: ForkliftLoader(onFirstLoop: () => ref.read(splashShownProvider.notifier).state = true)),
    );
  }
}
