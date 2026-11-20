import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../download/download.dart';
import '../models.dart';

/// A QR code (a truck's or an operator's): preview, PNG download, and — when
/// [onReissue] is given — issuing a new code. Pops true when it was re-issued.
class QrCodeDialog extends StatefulWidget {
  const QrCodeDialog({
    super.key,
    required this.title,
    required this.filename,
    required this.issuedAt,
    required this.loadPng,
    this.caption,
    this.onReissue,
    this.reissueWarning = 'Obecny kod przestanie działać od razu. Trzeba będzie wydrukować nowy.',
  });

  final String title;
  final String filename;
  final DateTime issuedAt;
  final Future<Uint8List> Function() loadPng;

  /// Shown under the code, e.g. the link a truck sticker opens.
  final String? caption;

  /// Issues a new code; returns its issue time and new caption. Null hides the button.
  final Future<(DateTime, String?)> Function()? onReissue;
  final String reissueWarning;

  @override
  State<QrCodeDialog> createState() => _QrCodeDialogState();
}

class _QrCodeDialogState extends State<QrCodeDialog> {
  late DateTime _issuedAt = widget.issuedAt;
  late String? _caption = widget.caption;
  Uint8List? _png;
  String? _error;
  bool _busy = false;
  bool _reissued = false;

  @override
  void initState() {
    super.initState();
    _loadPng();
  }

  Future<void> _loadPng() async {
    try {
      final png = await widget.loadPng();
      if (mounted) setState(() => _png = png);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _download() async {
    if (_png == null) return;
    final saved = await saveBytes(_png!, widget.filename, 'image/png');
    if (!saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nie udało się zapisać pliku.')));
    }
  }

  Future<void> _reissue() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nowy kod QR — ${widget.title}?'),
        content: Text(widget.reissueWarning),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Wygeneruj nowy')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (issuedAt, caption) = await widget.onReissue!();
      setState(() {
        _issuedAt = issuedAt;
        _caption = caption;
        _png = null;
        _reissued = true;
      });
      await _loadPng();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return AlertDialog(
      title: Text('Kod QR — ${widget.title}'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 240,
              height: 240,
              child: _png != null
                  ? Image.memory(_png!, filterQuality: FilterQuality.none)
                  : const Center(child: CircularProgressIndicator()),
            ),
            const SizedBox(height: 8),
            if (_caption != null) SelectableText(_caption!, style: small, textAlign: TextAlign.center),
            Text('Wydany: ${formatDateTime(_issuedAt)}', style: small),
            if (_reissued)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Nowy kod wydany — wydrukuj go ponownie.',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        if (widget.onReissue != null)
          TextButton.icon(
            onPressed: _busy ? null : _reissue,
            icon: const Icon(Icons.autorenew),
            label: const Text('Nowy kod'),
          ),
        TextButton.icon(
          onPressed: _png == null ? null : _download,
          icon: const Icon(Icons.download),
          label: const Text('PNG'),
        ),
        FilledButton(onPressed: () => Navigator.of(context).pop(_reissued), child: const Text('Zamknij')),
      ],
    );
  }
}
