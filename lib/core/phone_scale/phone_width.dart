/// The phone's real screen width when the browser lays the page out wider.
///
/// Chrome's "Wersja na komputer" (desktop site) renders a ~980 px wide page on
/// a ~400 px phone and ignores the viewport tag, so everything comes out tiny.
/// A site cannot turn that mode off; it can only notice it and scale up.
library;

export 'phone_width_stub.dart' if (dart.library.js_interop) 'phone_width_web.dart';
