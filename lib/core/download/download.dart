/// Save bytes from the API as a file the user keeps (a PDF of labels, a QR PNG).
///
/// On the web this is a normal browser download; elsewhere it is not wired yet
/// (printing is done from the office web panel).
library;

export 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart';
