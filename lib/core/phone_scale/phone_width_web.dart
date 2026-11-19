import 'package:web/web.dart' as web;

/// The screen's real width in CSS pixels when a touch phone shows the page as a
/// desktop site (laid out much wider than the screen), otherwise null.
///
/// `?phoneWidth=400` in the address forces it, to try the scaling on a computer.
double? phoneWidthInDesktopMode() {
  final forced = double.tryParse(Uri.base.queryParameters['phoneWidth'] ?? '');
  if (forced != null && forced > 0) return forced;

  final w = web.window;
  final touch = w.navigator.maxTouchPoints > 0 && w.matchMedia('(pointer: coarse)').matches;
  final screen = w.screen.width.toDouble();
  final page = w.innerWidth.toDouble();
  // A phone's screen; a page at least a third wider than it means desktop mode.
  // Tablets and touch laptops (wider screens) are left alone.
  if (!touch || screen <= 0 || screen > 600 || page < screen * 1.3) return null;
  return screen;
}
