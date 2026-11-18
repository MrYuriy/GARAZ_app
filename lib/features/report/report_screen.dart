import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
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

  IncidentType? _type;
  int? _categoryId;
  bool _outOfService = false;
  final _mth = TextEditingController();
  final _description = TextEditingController();
  final List<ReportPhoto> _photos = [];

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
    _mth.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final truck = await _repo.truck(widget.truckToken);
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

  List<ReportCategory> get _categories =>
      _type == null ? const [] : _truck!.categories.where((c) => c.types.contains(_type)).toList();

  void _pickType(IncidentType type) {
    setState(() {
      _type = type;
      if (!_categories.any((c) => c.id == _categoryId)) _categoryId = null;
    });
  }

  void _pickCategory(int? id) {
    final category = _truck!.categories.where((c) => c.id == id).firstOrNull;
    setState(() {
      _categoryId = id;
      // The category's default; the operator may still change it.
      if (category != null) _outOfService = category.defaultOutOfService;
    });
  }

  double? get _mthValue => double.tryParse(_mth.text.trim().replaceAll(',', '.'));

  bool get _mthBelowLast {
    final last = _truck?.lastMth;
    final value = _mthValue;
    return last != null && value != null && value < last;
  }

  Future<void> _addPhotos(ImageSource source) async {
    final picker = ImagePicker();
    // Shrunk on the phone already; the server re-encodes anyway.
    const side = 2048.0;
    const quality = 80;
    final files = source == ImageSource.camera
        ? [?await picker.pickImage(source: source, maxWidth: side, maxHeight: side, imageQuality: quality)]
        : await picker.pickMultiImage(maxWidth: side, maxHeight: side, imageQuality: quality);
    for (final f in files) {
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photos.add(ReportPhoto(bytes, f.name.isEmpty ? 'zdjecie.jpg' : f.name));
        _error = null;
      });
    }
  }

  String? get _missing {
    if (_operatorToken == null) return 'Zeskanuj swoją kartę operatora.';
    if (_type == null) return 'Wybierz rodzaj zdarzenia.';
    if (_categoryId == null) return 'Wybierz kategorię.';
    if (_mth.text.trim().isNotEmpty && _mthValue == null) return 'Motogodziny: podaj liczbę, np. 1234,5.';
    if (_photos.isEmpty) return 'Dodaj co najmniej jedno zdjęcie.';
    return null;
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
        'incident_type': _type!.api,
        'category_id': _categoryId,
        'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
        'mth': _mthValue?.toStringAsFixed(1),
        'out_of_service': _outOfService,
        'reported_at': DateTime.now().toUtc().toIso8601String(),
      }, _photos);
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
      _type = null;
      _categoryId = null;
      _outOfService = false;
      _mth.clear();
      _description.clear();
      _photos.clear();
    });
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
        _step(context, '1. Operator'),
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
        _step(context, '2. Co się stało?'),
        SegmentedButton<IncidentType>(
          segments: [for (final t in IncidentType.values) ButtonSegment(value: t, label: Text(t.label))],
          selected: {?_type},
          emptySelectionAllowed: true,
          onSelectionChanged: _sending ? null : (s) => s.isEmpty ? null : _pickType(s.first),
        ),
        const SizedBox(height: 8),
        // The line between the three is not obvious: say what each one means.
        for (final t in IncidentType.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${t.label}: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: t.hint),
                ],
              ),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: _type == t ? scheme.primary : scheme.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          key: ValueKey('category-$_type'),
          initialValue: _categoryId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Kategoria',
            helperText: _type == null ? 'Najpierw wybierz rodzaj zdarzenia.' : null,
          ),
          items: [for (final c in _categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
          onChanged: _type == null || _sending ? null : _pickCategory,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Wózek wyłączony z eksploatacji'),
          subtitle: Text(
            _outOfService
                ? 'TAK — wózek zostanie zablokowany do decyzji administratora.'
                : 'NIE — wózek może dalej pracować.',
          ),
          value: _outOfService,
          onChanged: _sending ? null : (v) => setState(() => _outOfService = v),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _mth,
          enabled: !_sending,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(
            labelText: 'Motogodziny (MTH)',
            helperText: truck.lastMth == null ? 'Z licznika wózka.' : 'Ostatnio zgłoszono: ${_mthText(truck.lastMth!)}',
            errorText: _mthBelowLast
                ? 'Mniej niż ostatnio (${_mthText(truck.lastMth!)}). Sprawdź licznik — można wysłać.'
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          enabled: !_sending,
          maxLines: 3,
          maxLength: 2000,
          decoration: const InputDecoration(labelText: 'Opis (opcjonalnie)', alignLabelWithHint: true),
        ),
        const SizedBox(height: 4),
        _step(context, '3. Zdjęcia (co najmniej jedno)'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _photos.length; i++) _thumb(i),
            OutlinedButton.icon(
              onPressed: _sending ? null : () => _addPhotos(ImageSource.camera),
              icon: const Icon(Icons.photo_camera),
              label: const Text('Zrób zdjęcie'),
            ),
            OutlinedButton.icon(
              onPressed: _sending ? null : () => _addPhotos(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Z galerii'),
            ),
          ],
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

  String _mthText(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  Widget _step(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );

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

  Widget _thumb(int i) => Stack(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(_photos[i].bytes, width: 96, height: 96, fit: BoxFit.cover),
      ),
      Positioned(
        right: 0,
        top: 0,
        child: IconButton.filledTonal(
          visualDensity: VisualDensity.compact,
          tooltip: 'Usuń zdjęcie',
          onPressed: _sending ? null : () => setState(() => _photos.removeAt(i)),
          icon: const Icon(Icons.close, size: 16),
        ),
      ),
    ],
  );

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
        ],
      ),
    );
  }
}
