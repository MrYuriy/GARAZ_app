import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Starts a browser download of [bytes] as [filename].
Future<bool> saveBytes(Uint8List bytes, String filename, String mimeType) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  // Give the browser a moment to start reading the blob before freeing it.
  Future.delayed(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  return true;
}

/// Shows [bytes] in a new browser tab (a scanned PDF or photo).
Future<bool> openBytes(Uint8List bytes, String mimeType) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  web.window.open(url, '_blank');
  Future.delayed(const Duration(minutes: 5), () => web.URL.revokeObjectURL(url));
  return true;
}
