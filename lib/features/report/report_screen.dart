import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import 'incident_fields.dart';
import 'outbox.dart';
import 'report_repository.dart';
import 'scan_dialog.dart';
import '../../core/i18n.dart';
import '../../core/widgets/forklift_loader.dart';

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

  /// The code is unknown: loading it again cannot help, scanning another can.
  bool _unknownCode = false;

  String? _operatorToken;
  String? _operatorName;
  bool _checkingOperator = false;

  /// Scanned without a signal: the server checks the card when the report goes out.
  bool _operatorUnchecked = false;

  final _draft = IncidentDraft();

  /// Made once per report and kept across retries, so a resend is not a second report.
  String _clientUuid = const Uuid().v4();
  bool _sending = false;
  String? _error;
  ({int id, bool truckOutOfService})? _sent;

  /// Kept on the phone for later: there was no signal.
  bool _queued = false;

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
    setState(() {
      _loadError = null;
      _unknownCode = false;
    });
    try {
      final truck = await _repo.truck(widget.truckToken);
      _draft.setTruck(truck);
      if (mounted) setState(() => _truck = truck);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _unknownCode = e.statusCode == 404;
        _loadError = _unknownCode
            ? tr(
                'Nie rozpoznano kodu wózka. Zeskanuj naklejkę na wózku jeszcze raz. Jeśli to nie pomoże, naklejka mogła zostać wymieniona — zgłoś to przełożonemu.',
              )
            : e.message;
      });
    }
  }

  /// Another truck code, in place of the unknown one.
  Future<void> _scanTruck() async {
    final code = await ScanDialog.open(context, tr('Zeskanuj naklejkę wózka'));
    if (code == null || !mounted) return;
    context.pushReplacement('/t/${Uri.encodeComponent(qrToken(code))}');
  }

  Future<void> _scanOperator() async {
    final code = await ScanDialog.open(context, tr('Zeskanuj swoją kartę'));
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
        _operatorUnchecked = false;
      });
    } on ApiException catch (e) {
      if (outboxSupported && isRetryable(e)) {
        setState(() {
          _operatorToken = code;
          _operatorName = tr('Karta zeskanowana');
          _operatorUnchecked = true;
        });
        return;
      }
      setState(
        () => _error = e.statusCode == 404 ? tr('Nie rozpoznano karty operatora. Spróbuj jeszcze raz.') : e.message,
      );
    } finally {
      if (mounted) setState(() => _checkingOperator = false);
    }
  }

  String? get _missing {
    if (_operatorToken == null) return tr('Zeskanuj swoją kartę operatora.');
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
    final report = {
      'client_uuid': _clientUuid,
      'truck_token': widget.truckToken,
      'operator_token': _operatorToken,
      ..._draft.toJson(),
      'reported_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      final sent = await _repo.submit(report, _draft.photos);
      if (mounted) setState(() => _sent = sent);
    } on ApiException catch (e) {
      if (outboxSupported && isRetryable(e)) {
        try {
          await ref.read(outboxProvider.notifier).add(report, _draft.photos, _truck!.number);
          if (mounted) setState(() => _queued = true);
          return;
        } catch (_) {
          // Could not save on the phone either: say so below.
        }
      }
      if (!mounted) return;
      setState(
        () => _error = e.statusCode == 0
            ? tr('Brak połączenia. Zgłoszenie nie zostało wysłane — spróbuj ponownie, gdy będzie zasięg.')
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
      _queued = false;
      _clientUuid = const Uuid().v4();
    });
    _draft.clear();
    _load(); // fresh last hour meter and truck status
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No sign-in here: the language is picked in the corner.
      appBar: AppBar(title: Text(tr('Zgłoszenie zdarzenia')), actions: const [LanguageButton()]),
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
            if (_unknownCode)
              FilledButton.icon(
                onPressed: _scanTruck,
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(tr('Zeskanuj ponownie')),
              )
            else
              // No connection or a server error: the same code may load now.
              OutlinedButton(onPressed: _load, child: Text(tr('Spróbuj ponownie'))),
          ],
        ),
      );
    }
    final truck = _truck;
    if (truck == null) return const Center(child: ForkliftLoader());
    if (_sent != null || _queued) return _done(context, truck);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const OutboxBanner(),
        if (truck.offline)
          Card(
            color: scheme.secondaryContainer,
            child: ListTile(
              leading: Icon(Icons.signal_wifi_off),
              title: Text(tr('Brak internetu')),
              subtitle: Text(tr('Wypełnij zgłoszenie — zapiszemy je na telefonie i wyślemy, gdy wróci zasięg.')),
            ),
          ),
        _truckCard(context, truck),
        const SizedBox(height: 12),
        stepTitle(context, tr('1. Operator')),
        Card(
          child: ListTile(
            leading: Icon(
              _operatorName == null ? Icons.badge_outlined : Icons.check_circle,
              color: _operatorName == null ? null : Colors.green,
            ),
            title: Text(_operatorName ?? tr('Zeskanuj swoją kartę operatora')),
            subtitle: Text(
              _operatorName == null
                  ? tr('Kod QR na karcie.')
                  : _operatorUnchecked
                  ? tr('Bez zasięgu — kartę sprawdzimy przy wysyłce.')
                  : tr('Karta rozpoznana.'),
            ),
            trailing: _checkingOperator
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : FilledButton.tonalIcon(
                    onPressed: _sending ? null : _scanOperator,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(_operatorName == null ? tr('Skanuj') : tr('Zmień')),
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
          label: Text(_sending ? tr('Wysyłanie…') : tr('Wyślij zgłoszenie')),
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
        title: Text(
          tr('Wózek {number}', {'number': truck.number}),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text([truck.truckType, ?truck.make, if (stopped) 'już wyłączony z eksploatacji'].join(' · ')),
      ),
    );
  }

  Widget _done(BuildContext context, ReportTruck truck) {
    final sent = _sent;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sent == null) ...[
            const Icon(Icons.schedule_send, size: 72, color: Colors.orange),
            const SizedBox(height: 16),
            Text(tr('Zapisano na telefonie'), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              tr(
                'Wózek {number}. Brak internetu — zgłoszenie zostanie wysłane automatycznie, gdy telefon połączy się z siecią. Nie odinstalowuj aplikacji do tego czasu.\n\nJeśli wózek jest niesprawny, nie używaj go i powiadom przełożonego.',
                {'number': truck.number},
              ),
              textAlign: TextAlign.center,
            ),
          ] else ...[
            const Icon(Icons.check_circle, size: 72, color: Colors.green),
            const SizedBox(height: 16),
            Text(tr('Zgłoszenie wysłane'), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              tr('Wózek {number} · zgłoszenie nr {id}', {'number': truck.number, 'id': sent.id}),
              textAlign: TextAlign.center,
            ),
          ],
          if (sent != null && sent.truckOutOfService) ...[
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  tr('Wózek jest wyłączony z eksploatacji. Nie używaj go, dopóki administrator go nie przywróci.'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _again,
            icon: const Icon(Icons.add),
            label: Text(tr('Kolejne zgłoszenie dla tego wózka')),
          ),
          // Opened from the app's start screen (not from a link): back to it.
          if (Navigator.of(context).canPop()) ...[
            const SizedBox(height: 8),
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Gotowe'))),
          ],
        ],
      ),
    );
  }
}
