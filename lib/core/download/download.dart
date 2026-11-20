/// Save bytes from the API as a file the user keeps (a PDF of labels, a QR PNG),
/// or open them in a viewer.
///
/// On the web: a browser download or a new tab. On the phone: the share sheet
/// (save to Drive, send, print) or an installed viewer.
library;

export 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart' if (dart.library.io) 'download_io.dart';
