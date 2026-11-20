import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import 'report_repository.dart';

/// Reports that could not be sent — no signal in the warehouse — kept on the
/// phone with their photos and sent as soon as the server answers: when the app
/// starts or comes back to the front, and every minute while any are waiting.
/// Each keeps its `client_uuid`, so a report that did reach the server before
/// the answer was lost is still filed once.
///
/// The phone app only; the web form has nowhere safe to keep photos.
bool get outboxSupported => !kIsWeb;

/// Worth trying again later: no connection, the server busy or down.
bool isRetryable(ApiException e) => e.statusCode == 0 || e.statusCode == 429 || e.statusCode >= 500;

class OutboxItem {
  const OutboxItem({
    required this.id,
    required this.dir,
    required this.report,
    required this.photoFiles,
    required this.truckNumber,
    required this.savedAt,
    this.rejected,
  });

  final String id; // the report's client_uuid
  final Directory dir;
  final Map<String, dynamic> report;
  final List<String> photoFiles;
  final String truckNumber;
  final DateTime savedAt;

  /// The server refused it (e.g. the operator card is not valid): sending again
  /// will not help; the operator should report it once more.
  final String? rejected;
}

class OutboxState {
  const OutboxState({this.items = const [], this.sending = false});

  final List<OutboxItem> items;
  final bool sending;

  List<OutboxItem> get waiting => [
    for (final i in items)
      if (i.rejected == null) i,
  ];
  List<OutboxItem> get rejected => [
    for (final i in items)
      if (i.rejected != null) i,
  ];
}

final outboxProvider = NotifierProvider<Outbox, OutboxState>(Outbox.new);

class Outbox extends Notifier<OutboxState> {
  Timer? _timer;
  AppLifecycleListener? _lifecycle;

  @override
  OutboxState build() {
    if (outboxSupported) {
      _lifecycle = AppLifecycleListener(onResume: flush);
      _timer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (state.waiting.isNotEmpty) flush();
      });
      ref.onDispose(() {
        _timer?.cancel();
        _lifecycle?.dispose();
      });
      Future.microtask(() async {
        await _reload();
        await flush();
      });
    }
    return const OutboxState();
  }

  static Future<Directory> _root() async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/outbox');
    return dir.create(recursive: true);
  }

  Future<void> _reload() async {
    final items = <OutboxItem>[];
    await for (final entry in (await _root()).list()) {
      if (entry is! Directory) continue;
      try {
        final meta = jsonDecode(await File('${entry.path}/meta.json').readAsString()) as Map<String, dynamic>;
        items.add(
          OutboxItem(
            id: entry.uri.pathSegments.where((s) => s.isNotEmpty).last,
            dir: entry,
            report: (meta['report'] as Map).cast<String, dynamic>(),
            photoFiles: [for (final p in meta['photos'] as List) p as String],
            truckNumber: meta['truck_number'] as String,
            savedAt: DateTime.parse(meta['saved_at'] as String),
            rejected: meta['rejected'] as String?,
          ),
        );
      } catch (_) {
        // Half-written (the app was killed while saving): nothing to send.
        await entry.delete(recursive: true);
      }
    }
    items.sort((a, b) => a.savedAt.compareTo(b.savedAt));
    state = OutboxState(items: items, sending: state.sending);
  }

  /// Keeps the report on the phone; [flush] sends it later.
  Future<void> add(Map<String, dynamic> report, List<ReportPhoto> photos, String truckNumber) async {
    final id = report['client_uuid'] as String;
    final dir = await Directory('${(await _root()).path}/$id.tmp').create(recursive: true);
    final names = <String>[];
    for (var i = 0; i < photos.length; i++) {
      final name = '${i}_${photos[i].name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}';
      await File('${dir.path}/$name').writeAsBytes(photos[i].bytes, flush: true);
      names.add(name);
    }
    await File('${dir.path}/meta.json').writeAsString(
      jsonEncode({
        'report': report,
        'photos': names,
        'truck_number': truckNumber,
        'saved_at': DateTime.now().toIso8601String(),
      }),
      flush: true,
    );
    // Only a complete folder gets its final name.
    await dir.rename('${(await _root()).path}/$id');
    await _reload();
  }

  /// Sends what is waiting, oldest first; stops at the first failed connection.
  Future<void> flush() async {
    if (!outboxSupported || state.sending || state.waiting.isEmpty) return;
    state = OutboxState(items: state.items, sending: true);
    final repo = ref.read(reportRepositoryProvider);
    try {
      for (final item in state.waiting) {
        final photos = [
          for (final name in item.photoFiles)
            ReportPhoto(
              Uint8List.fromList(await File('${item.dir.path}/$name').readAsBytes()),
              name.split('_').skip(1).join('_'),
            ),
        ];
        try {
          await repo.submit(item.report, photos);
          await item.dir.delete(recursive: true);
        } on ApiException catch (e) {
          if (isRetryable(e)) break;
          final meta = File('${item.dir.path}/meta.json');
          final data = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
          data['rejected'] = e.message;
          await meta.writeAsString(jsonEncode(data), flush: true);
        }
      }
    } finally {
      await _reload();
      state = OutboxState(items: state.items, sending: false);
    }
  }

  Future<void> remove(OutboxItem item) async {
    if (await item.dir.exists()) await item.dir.delete(recursive: true);
    await _reload();
  }
}

/// The last data of each truck seen on this phone, so the form opens without a
/// signal for a truck scanned before.
class TruckCache {
  static Future<File> _file(String token) async {
    final dir = await Directory('${(await getApplicationSupportDirectory()).path}/trucks').create(recursive: true);
    return File('${dir.path}/${base64Url.encode(utf8.encode(token))}.json');
  }

  static Future<void> save(String token, Map<String, dynamic> json) async {
    if (!outboxSupported) return;
    try {
      await (await _file(token)).writeAsString(jsonEncode(json), flush: true);
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> read(String token) async {
    if (!outboxSupported) return null;
    try {
      final file = await _file(token);
      if (!await file.exists()) return null;
      return (jsonDecode(await file.readAsString()) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }
}

/// "Oczekujące zgłoszenia": what is waiting to be sent, and what the server refused.
class OutboxBanner extends ConsumerWidget {
  const OutboxBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(outboxProvider);
    if (state.items.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final waiting = state.waiting;
    return Card(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (waiting.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.schedule_send),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Niewysłane zgłoszenia: ${waiting.length}. '
                      'Wyślemy je automatycznie, gdy będzie internet.',
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: state.sending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : TextButton(
                        onPressed: () => ref.read(outboxProvider.notifier).flush(),
                        child: const Text('Wyślij teraz'),
                      ),
              ),
            ],
            for (final item in state.rejected)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.error_outline, color: scheme.error),
                title: Text('Wózek ${item.truckNumber} — zgłoszenie odrzucone'),
                subtitle: Text('${item.rejected} Zgłoś zdarzenie jeszcze raz.'),
                trailing: IconButton(
                  tooltip: 'Usuń',
                  onPressed: () => ref.read(outboxProvider.notifier).remove(item),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
