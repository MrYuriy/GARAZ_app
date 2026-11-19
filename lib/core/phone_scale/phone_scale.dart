import 'package:flutter/widgets.dart';

import 'phone_width.dart';

/// Lays the app out at the phone's real width and scales it up to fill the
/// page, when the browser shows it as a desktop site on a phone (see
/// [phoneWidthInDesktopMode]). Anywhere else it changes nothing.
class PhoneScale extends StatelessWidget {
  const PhoneScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final real = phoneWidthInDesktopMode();
    final mq = MediaQuery.of(context);
    if (real == null || mq.size.width <= real) return child;
    final k = mq.size.width / real;
    final size = mq.size / k;
    return FittedBox(
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: size,
        child: MediaQuery(
          data: mq.copyWith(
            size: size,
            devicePixelRatio: mq.devicePixelRatio * k,
            padding: mq.padding / k,
            viewPadding: mq.viewPadding / k,
            viewInsets: mq.viewInsets / k,
          ),
          child: child,
        ),
      ),
    );
  }
}
