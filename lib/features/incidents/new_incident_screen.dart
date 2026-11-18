import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../report/incident_fields.dart';
import '../report/report_repository.dart';
import '../report/scan_dialog.dart';

/// A report entered by a signed-in user for someone else: after a phone call,
/// for an operator without their card, or for a person outside the register.
/// Pops with the new report's id.
class NewIncidentScreen extends ConsumerStatefulWidget {
  const NewIncidentScreen({super.key});

  @override
  ConsumerState<NewIncidentScreen> createState() => _NewIncidentScreenState();
}

/// Who drove: a registered operator, or only a name.
enum _DriverMode { registered, unregistered }

class _NewIncidentScreenState extends ConsumerState<NewIncidentScreen> {
  ReportTruck? _truck;
  bool _loadingTruck = false;

  _DriverMode _mode = _DriverMode.registered;
  EntryRef? _operator;
  final _driverName = TextEditingController();

  DateTime _occurredAt = DateTime.now();
  final _draft = IncidentDraft();

  /// Made once and kept across retries, so a resend is not a second report.
  final String _clientUuid = const Uuid().v4();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _driverName.dispose();
    _draft.dispose();
    super.dispose();
  }

  Future<void> _setTruck(Future<ReportTruck> load, {required String notFound}) async {
    setState(() {
      _loadingTruck = true;
      _error = null;
    });
    try {
      final truck = await load;
      _draft.setTruck(truck);
      if (mounted) setState(() => _truck = truck);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.statusCode == 404 ? notFound : e.message);
    } finally {
      if (mounted) setState(() => _loadingTruck = false);
    }
  }

  Future<void> _scanTruck() async {
    final code = await ScanDialog.open(context, 'Zeskanuj naklejkę wózka');
    if (code == null || !mounted) return;
    await _setTruck(
      ref.read(incidentsRepositoryProvider).formTruckByQr(qrToken(code)),
      notFound: 'Nie rozpoznano kodu wózka (nieznany, wymieniony albo wózek wycofany).',
    );
  }

  Future<void> _pickTruck() async {
    final picked = await showDialog<Truck>(
      context: context,
      builder: (_) => _PickDialog<Truck>(
        title: 'Wybierz wózek',
        hint: 'Szukaj: numer wózka',
        load: (q) async {
          final page = await ref.read(trucksRepositoryProvider).list(query: q, limit: 50);
          return page.items.where((t) => t.status != TruckStatus.inactive).toList();
        },
        label: (t) => t.number,
        subtitle: (t) => [t.truckType.name, if (t.makeAndModel.isNotEmpty) t.makeAndModel, t.status.label].join(' · '),
      ),
    );
    if (picked == null || !mounted) return;
    await _setTruck(ref.read(incidentsRepositoryProvider).formTruck(picked.id), notFound: 'Wózek jest wycofany.');
  }

  Future<void> _scanOperator() async {
    final code = await ScanDialog.open(context, 'Zeskanuj kartę operatora');
    if (code == null || !mounted) return;
    setState(() => _error = null);
    try {
      final op = await ref.read(incidentsRepositoryProvider).operatorByQr(qrToken(code));
      if (mounted) setState(() => _operator = op);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.statusCode == 404 ? 'Nie rozpoznano karty operatora.' : e.message);
    }
  }

  Future<void> _pickOperator() async {
    final picked = await showDialog<Operator>(
      context: context,
      builder: (_) => _PickDialog<Operator>(
        title: 'Wybierz operatora',
        hint: 'Szukaj: imię i nazwisko',
        load: (q) async => (await ref.read(operatorsRepositoryProvider).list(query: q, limit: 50)).items,
        label: (o) => o.fullName,
        subtitle: (o) =>
            [?o.employer?.name, if (!o.isActive) 'nieaktywny', o.permitStatus?.label ?? 'brak uprawnień'].join(' · '),
      ),
    );
    if (picked != null && mounted) setState(() => _operator = EntryRef(picked.id, picked.fullName));
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_occurredAt));
    if (time == null) return;
    var picked = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    if (picked.isAfter(now)) picked = now;
    setState(() => _occurredAt = picked);
  }

  String? get _missing {
    if (_truck == null) return 'Wybierz wózek.';
    if (_mode == _DriverMode.registered && _operator == null) return 'Wybierz operatora.';
    if (_mode == _DriverMode.unregistered && _driverName.text.trim().isEmpty) {
      return 'Wpisz imię i nazwisko osoby, która jechała.';
    }
    return _draft.missing(photoRequired: false);
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
      final saved = await ref.read(incidentsRepositoryProvider).create({
        'client_uuid': _clientUuid,
        'truck_id': _truck!.id,
        if (_mode == _DriverMode.registered) 'operator_id': _operator!.id,
        if (_mode == _DriverMode.unregistered) 'operator_name': _driverName.text.trim(),
        ..._draft.toJson(),
        'occurred_at': _occurredAt.toUtc().toIso8601String(),
      }, _draft.photos);
      if (mounted) Navigator.of(context).pop(saved.id);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.statusCode == 0 ? 'Brak połączenia. Spróbuj ponownie.' : e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Dodaj zgłoszenie')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              stepTitle(context, '1. Wózek'),
              _truckCard(),
              const SizedBox(height: 12),
              stepTitle(context, '2. Kto jechał?'),
              _driverCard(),
              const SizedBox(height: 12),
              stepTitle(context, '3. Kiedy?'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.schedule),
                  title: Text(formatDateTime(_occurredAt)),
                  subtitle: const Text('Czas zdarzenia, jeśli wpisujesz je później.'),
                  trailing: TextButton(onPressed: _sending ? null : _pickTime, child: const Text('Zmień')),
                ),
              ),
              const SizedBox(height: 12),
              if (_truck == null)
                Text(
                  'Rodzaj, kategoria i zdjęcia — po wybraniu wózka.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                )
              else
                IncidentFields(
                  draft: _draft,
                  firstStep: 4,
                  photoRequired: false,
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
                icon: const Icon(Icons.save),
                label: Text(_sending ? 'Zapisywanie…' : 'Zapisz zgłoszenie'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _truckCard() {
    final t = _truck;
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          children: [
            ListTile(
              leading: Icon(Icons.forklift, size: 32, color: t == null ? null : Colors.green),
              title: Text(
                t == null ? 'Nie wybrano wózka' : 'Wózek ${t.number}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: t == null
                  ? const Text('Zeskanuj naklejkę albo wybierz z listy.')
                  : Text(
                      [
                        t.truckType,
                        ?t.make,
                        if (t.status == TruckStatus.outOfService) 'już wyłączony z eksploatacji',
                      ].join(' · '),
                    ),
              trailing: _loadingTruck
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
            ),
            _actions([
              FilledButton.tonalIcon(
                onPressed: _sending ? null : _scanTruck,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Skanuj'),
              ),
              OutlinedButton.icon(
                onPressed: _sending ? null : _pickTruck,
                icon: const Icon(Icons.list),
                label: const Text('Wybierz z listy'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _driverCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_DriverMode>(
              segments: const [
                ButtonSegment(value: _DriverMode.registered, icon: Icon(Icons.badge_outlined), label: Text('Operator')),
                ButtonSegment(
                  value: _DriverMode.unregistered,
                  icon: Icon(Icons.person_outline),
                  label: Text('Osoba spoza listy'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _sending ? null : (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 8),
            if (_mode == _DriverMode.registered) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _operator == null ? Icons.badge_outlined : Icons.check_circle,
                  color: _operator == null ? null : Colors.green,
                ),
                title: Text(_operator?.name ?? 'Nie wybrano operatora'),
                subtitle: _operator == null ? const Text('Zeskanuj jego kartę albo wybierz z listy.') : null,
              ),
              _actions([
                FilledButton.tonalIcon(
                  onPressed: _sending ? null : _scanOperator,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Skanuj kartę'),
                ),
                OutlinedButton.icon(
                  onPressed: _sending ? null : _pickOperator,
                  icon: const Icon(Icons.list),
                  label: const Text('Wybierz z listy'),
                ),
              ]),
            ] else ...[
              TextField(
                controller: _driverName,
                enabled: !_sending,
                maxLength: 128,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Imię i nazwisko',
                  helperText: 'Ktoś bez uprawnień albo spoza rejestru. Zgłoszenie dostanie oznaczenie.',
                  helperMaxLines: 2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actions(List<Widget> buttons) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Wrap(spacing: 8, runSpacing: 8, children: buttons),
  );
}

/// The token in a scanned code: a sticker holds a link ending in `/t/<token>`,
/// a card the token itself.
String qrToken(String code) => RegExp(r'/t/([A-Za-z0-9_-]+)').firstMatch(code)?.group(1) ?? code.trim();

/// A searchable list to pick one item from.
class _PickDialog<T> extends StatefulWidget {
  const _PickDialog({
    required this.title,
    required this.hint,
    required this.load,
    required this.label,
    required this.subtitle,
  });

  final String title;
  final String hint;
  final Future<List<T>> Function(String query) load;
  final String Function(T) label;
  final String Function(T) subtitle;

  @override
  State<_PickDialog<T>> createState() => _PickDialogState<T>();
}

class _PickDialogState<T> extends State<_PickDialog<T>> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<T>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await widget.load(_search.text.trim());
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        height: 480,
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search), hintText: widget.hint),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), _load);
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error!))
                  : items == null
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                  ? const Center(child: Text('Nic nie znaleziono.'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) => ListTile(
                        title: Text(widget.label(items[i])),
                        subtitle: Text(widget.subtitle(items[i])),
                        onTap: () => Navigator.pop(context, items[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj'))],
    );
  }
}
