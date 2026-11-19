import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../download/download.dart';
import '../providers.dart';

const xlsxMimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// "Eksport do Excel": downloads [path] (a /reports/…xlsx) with the filters
/// [query] gives at the moment of the press — what the list shows.
class ExportButton extends ConsumerStatefulWidget {
  const ExportButton({super.key, required this.path, this.query, this.tooltip = 'Eksport do Excel'});

  final String path;
  final Map<String, dynamic> Function()? query;
  final String tooltip;

  @override
  ConsumerState<ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends ConsumerState<ExportButton> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await ref.read(reportsRepositoryProvider).xlsx(widget.path, widget.query?.call());
      final saved = await saveBytes(file.bytes, file.filename, xlsxMimeType);
      messenger.showSnackBar(
        SnackBar(content: Text(saved ? 'Pobrano ${file.filename}.' : 'Pobieranie działa w wersji przeglądarkowej.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: widget.tooltip,
    onPressed: _busy ? null : _export,
    icon: _busy
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.table_view_outlined),
  );
}
