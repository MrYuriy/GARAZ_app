import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import 'incident_fields.dart';
import 'report_repository.dart';
import 'scan_dialog.dart';

/// What a truck's sticker opens (`/t/<token>`): the operator scans their own
/// card, fills in the form, adds photos and sends. No sign-in.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key, required this.truckToken});

  final String truckToken;

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  ReportTruck? _truck;
  String? _loadError;

  String? _operatorToken;
  String? _operatorName;
  bool _checkingOperator = false;

  final _draft = IncidentDraft();

  /// Made once per report and kept across retries, so a resend is not a second report.
  String _clientUuid = const Uuid().v4();
  bool _sending = false;
  String? _error;
  ({int id, bool truckOutOfService})? _sent;

  ReportRepository get _repo => ref.read(reportRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final truck = await _repo.truck(widget.truckToken);
      _draft.setTruck(truck);
      if (mounted) setState(() => _truck = truck);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _loadError = e.statusCode == 404
            ? 'Nie rozpoznano kodu wózka. Naklejka mogła zostać wymieniona — zgłoś to przełożonemu.'
            : e.message,
      );
    }
  }

  Future<void> _scanOperator() async {
    final code = await ScanDialog.open(context, 'Zeskanuj swoją kartę');
    if (code == null || !mounted) return;
    setState(() {
      _checkingOperator = true;
      _error = null;
    });
    try {
      final name = await _repo.checkOperator(widget.truckToken, code);
      setState(() {
        _operatorToken = code;
        _operatorName = name;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.statusCode == 404 ? 'Nie rozpoznano karty operatora. Spróbuj jeszcze raz.' : e.message);
    } finally {
      if (mounted) setState(() => _checkingOperator = false);
    }
  }

  String? get _missing {
    if (_operatorToken == null) return 'Zeskanuj swoją kartę operatora.';
    return _draft.missing(photoRequired: true);
  }

  Future<void> _send() async {
    final missing = _missing;
    if (missing != null) {
      setState(() => _error = missing);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final sent = await _repo.submit({
        'client_uuid': _clientUuid,
        'truck_token': widget.truckToken,
        'operator_token': _operatorToken,
        ..._draft.toJson(),
        'reported_at': DateTime.now().toUtc().toIso8601String(),
      }, _draft.photos);
      if (mounted) setState(() => _sent = sent);
    } on ApiException catch (e) {
      setState(
        () => _error = e.statusCode == 0
            ? 'Brak połączenia. Zgłoszenie nie zostało wysłane — spróbuj ponownie, gdy będzie zasięg.'
            : e.message,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Another report for the same truck, by the same operator.
  void _again() {
    setState(() {
      _sent = null;
      _clientUuid = const Uuid().v4();
    });
    _draft.clear();
    _load(); // fresh last hour meter and truck status
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zgłoszenie zdarzenia')),
      body: Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_2, size: 64, color: scheme.error),
            const SizedBox(height: 16),
            Text(_loadError!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _load, child: const Text('Spróbuj ponownie')),
          ],
        ),
      );
    }
    final truck = _truck;
    if (truck == null) return const Center(child: CircularProgressIndicator());
    if (_sent != null) return _done(context, truck);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _truckCard(context, truck),
        const SizedBox(height: 12),
        stepTitle(context, '1. Operator'),
        Card(
          child: ListTile(
            leading: Icon(
              _operatorName == null ? Icons.badge_outlined : Icons.check_circle,
              color: _operatorName == null ? null : Colors.green,
            ),
            title: Text(_operatorName ?? 'Zeskanuj swoją kartę operatora'),
            subtitle: _operatorName == null ? const Text('Kod QR na karcie.') : const Text('Karta rozpoznana.'),
            trailing: _checkingOperator
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : FilledButton.tonalIcon(
                    onPressed: _sending ? null : _scanOperator,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(_operatorName == null ? 'Skanuj' : 'Zmień'),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        IncidentFields(
          draft: _draft,
          firstStep: 2,
          photoRequired: true,
          enabled: !_sending,
          onChanged: () => setState(() => _error = null),
        ),
        const SizedBox(height: 20),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: TextStyle(color: scheme.error)),
          ),
        if (_sending) const LinearProgressIndicator(),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: const Icon(Icons.send),
          label: Text(_sending ? 'Wysyłanie…' : 'Wyślij zgłoszenie'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ],
    );
  }

  Widget _truckCard(BuildContext context, ReportTruck truck) {
    final stopped = truck.status == TruckStatus.outOfService;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.forklift, size: 36),
        title: Text('Wózek ${truck.number}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text([truck.truckType, ?truck.make, if (stopped) 'już wyłączony z eksploatacji'].join(' · ')),
      ),
    );
  }

  Widget _done(BuildContext context, ReportTruck truck) {
    final sent = _sent!;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 72, color: Colors.green),
          const SizedBox(height: 16),
          Text('Zgłoszenie wysłane', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('Wózek ${truck.number} · zgłoszenie nr ${sent.id}', textAlign: TextAlign.center),
          if (sent.truckOutOfService) ...[
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Wózek jest wyłączony z eksploatacji. Nie używaj go, dopóki administrator go nie przywróci.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _again,
            icon: const Icon(Icons.add),
            label: const Text('Kolejne zgłoszenie dla tego wózka'),
          ),
          // Opened from the app's start screen (not from a link): back to it.
          if (Navigator.of(context).canPop()) ...[
            const SizedBox(height: 8),
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Gotowe')),
          ],
        ],
      ),
    );
  }
}
