import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen camera that pops the first QR code it reads. A text field
/// below it takes the code by hand, for a camera that will not cooperate.
class ScanDialog extends StatefulWidget {
  const ScanDialog({super.key, required this.title});

  final String title;

  static Future<String?> open(BuildContext context, String title) =>
      Navigator.of(context)
          .push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => ScanDialog(title: title)));

  @override
  State<ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends State<ScanDialog> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  final _manual = TextEditingController();
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    _manual.dispose();
    super.dispose();
  }

  void _finish(String? value) {
    final code = value?.trim() ?? '';
    if (_done || code.isEmpty) return;
    _done = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            // Dark like a viewfinder, also behind the "no camera" message.
            child: ColoredBox(
              color: Colors.black,
              child: MobileScanner(
                controller: _controller,
                onDetect: (capture) => _finish(capture.barcodes.firstOrNull?.rawValue),
                errorBuilder: (_, error) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Brak dostępu do aparatu (${error.errorCode.name}). '
                      'Zezwól na aparat w przeglądarce albo wpisz kod poniżej.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manual,
                      decoration: const InputDecoration(labelText: 'Albo wpisz kod', isDense: true),
                      onSubmitted: _finish,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: () => _finish(_manual.text), child: const Text('OK')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
