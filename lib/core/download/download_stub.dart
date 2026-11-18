import 'dart:typed_data';

/// Returns false: no download on this platform yet.
Future<bool> saveBytes(Uint8List bytes, String filename, String mimeType) async => false;

/// Returns false: no viewer on this platform yet.
Future<bool> openBytes(Uint8List bytes, String mimeType) async => false;
