import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// On the phone a file is written to the app's temporary folder first.
Future<File> _write(Uint8List bytes, String filename) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/exports');
  await dir.create(recursive: true);
  final safe = filename.replaceAll(RegExp(r'[\/:*?"<>|]'), '-');
  return File('${dir.path}/$safe').writeAsBytes(bytes, flush: true);
}

/// The system share sheet: save to Drive or Files, send, or print.
Future<bool> saveBytes(Uint8List bytes, String filename, String mimeType) async {
  final file = await _write(bytes, filename);
  final result = await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mimeType)],
      fileNameOverrides: [filename],
    ),
  );
  return result.status != ShareResultStatus.unavailable;
}

/// Opens the file in an installed viewer (a PDF reader prints from there too).
Future<bool> openBytes(Uint8List bytes, String mimeType) async {
  final ext = switch (mimeType) {
    'application/pdf' => 'pdf',
    'image/png' => 'png',
    'image/jpeg' => 'jpg',
    'image/webp' => 'webp',
    _ => 'bin',
  };
  final file = await _write(bytes, 'plik-${DateTime.now().millisecondsSinceEpoch}.$ext');
  final result = await OpenFilex.open(file.path, type: mimeType);
  return result.type == ResultType.done;
}
