import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/download/download.dart';
import '../../core/models.dart';
import '../../core/providers.dart';

/// A truck's QR code: preview, download, and (administrators) issue a new one.
/// Pops true when the code was re-issued.
class TruckQrDialog extends ConsumerStatefulWidget {
  const TruckQrDialog({super.key, required this.truck});

  final Truck truck;

  @override
  ConsumerState<TruckQrDialog> createState() => _TruckQrDialogState();
}

class _TruckQrDialogState extends ConsumerState<TruckQrDialog> {
  late Truck _truck = widget.truck;
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
      final png = await ref.read(trucksRepositoryProvider).qrPng(_truck.id);
      if (mounted) setState(() => _png = png);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _download() async {
    if (_png == null) return;
    final saved = await saveBytes(_png!, 'qr-${_truck.number}.png', 'image/png');
    if (!saved && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pobieranie działa w wersji przeglądarkowej.')));
    }
  }

  Future<void> _reissue() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nowy kod QR dla ${_truck.number}?'),
        content: const Text('Obecna naklejka przestanie działać od razu. Trzeba będzie wydrukować i nakleić nową.'),
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
      final truck = await ref.read(trucksRepositoryProvider).reissueQr(_truck.id);
      setState(() {
        _truck = truck;
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
    final isAdmin = ref.watch(authControllerProvider).user?.role.isAdmin ?? false;
    final small = Theme.of(context).textTheme.bodySmall;
    return AlertDialog(
      title: Text('Kod QR — ${_truck.number}'),
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
            SelectableText(_truck.qrUrl, style: small, textAlign: TextAlign.center),
            Text('Wydany: ${formatDateTime(_truck.qrIssuedAt)}', style: small),
            if (_reissued)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Nowy kod wydany — wydrukuj i naklej nową etykietę.',
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
        if (isAdmin)
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
