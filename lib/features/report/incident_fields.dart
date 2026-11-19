import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models.dart';
import 'report_repository.dart';

/// What happened, as both report forms ask it: the public one an operator
/// opens from a truck's sticker, and the one a signed-in user fills in for
/// someone else. The truck (its categories and last hour meter) comes first.
class IncidentDraft extends ChangeNotifier {
  List<ReportCategory> _all = const [];
  double? lastMth;

  IncidentType? type;
  int? categoryId;
  bool outOfService = false;
  final mth = TextEditingController();
  final description = TextEditingController();
  final List<ReportPhoto> photos = [];

  /// A (new) truck: its categories, and its last hour meter for the warning.
  void setTruck(ReportTruck truck) {
    _all = truck.categories;
    lastMth = truck.lastMth;
    if (!categories.any((c) => c.id == categoryId)) categoryId = null;
    notifyListeners();
  }

  List<ReportCategory> get categories => type == null ? const [] : _all.where((c) => c.types.contains(type)).toList();

  void pickType(IncidentType value) {
    type = value;
    if (!categories.any((c) => c.id == categoryId)) categoryId = null;
    notifyListeners();
  }

  void pickCategory(int? id) {
    final category = _all.where((c) => c.id == id).firstOrNull;
    categoryId = id;
    // The category's default; whoever reports may still change it.
    if (category != null) outOfService = category.defaultOutOfService;
    notifyListeners();
  }

  void setOutOfService(bool value) {
    outOfService = value;
    notifyListeners();
  }

  /// The hour meter was typed into: its warning may change.
  void textChanged() => notifyListeners();

  double? get mthValue => double.tryParse(mth.text.trim().replaceAll(',', '.'));

  bool get mthBelowLast {
    final value = mthValue;
    return lastMth != null && value != null && value < lastMth!;
  }

  void addPhoto(ReportPhoto photo) {
    photos.add(photo);
    notifyListeners();
  }

  void removePhoto(int index) {
    photos.removeAt(index);
    notifyListeners();
  }

  /// The first thing still to fill in, or null when the fields are complete.
  String? missing({required bool photoRequired}) {
    if (type == null) return 'Wybierz rodzaj zdarzenia.';
    if (categoryId == null) return 'Wybierz kategorię.';
    if (mth.text.trim().isNotEmpty && mthValue == null) return 'Motogodziny: podaj liczbę, np. 1234,5.';
    if (photoRequired && photos.isEmpty) return 'Dodaj co najmniej jedno zdjęcie.';
    return null;
  }

  /// These fields as the API takes them.
  Map<String, dynamic> toJson() {
    final text = description.text.trim();
    return {
      'incident_type': type!.api,
      'category_id': categoryId,
      'description': text.isEmpty ? null : text,
      'mth': mthValue?.toStringAsFixed(1),
      'out_of_service': outOfService,
    };
  }

  void clear() {
    type = null;
    categoryId = null;
    outOfService = false;
    mth.clear();
    description.clear();
    photos.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    mth.dispose();
    description.dispose();
    super.dispose();
  }
}

/// The fields of an [IncidentDraft]: type, category, out of service, MTH,
/// description and photos. [firstStep] numbers its two headings.
class IncidentFields extends StatelessWidget {
  const IncidentFields({
    super.key,
    required this.draft,
    required this.firstStep,
    required this.photoRequired,
    this.enabled = true,
    this.onChanged,
  });

  final IncidentDraft draft;
  final int firstStep;
  final bool photoRequired;
  final bool enabled;

  /// Called after a photo is added (e.g. to clear a "add a photo" error).
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: draft, builder: (context, _) => _fields(context));

  Widget _fields(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        stepTitle(context, '$firstStep. Co się stało?'),
        SegmentedButton<IncidentType>(
          segments: [for (final t in IncidentType.values) ButtonSegment(value: t, label: Text(t.label))],
          selected: {?d.type},
          emptySelectionAllowed: true,
          // The fill marks the choice; a tick would wrap "Uszkodzenie" on a phone.
          showSelectedIcon: false,
          onSelectionChanged: enabled ? (s) => s.isEmpty ? null : d.pickType(s.first) : null,
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
                  ?.copyWith(color: d.type == t ? scheme.primary : scheme.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          key: ValueKey('category-${d.type}-${d.categories.length}'),
          initialValue: d.categoryId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Kategoria',
            helperText: d.type == null ? 'Najpierw wybierz rodzaj zdarzenia.' : null,
          ),
          items: [for (final c in d.categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
          onChanged: d.type == null || !enabled ? null : d.pickCategory,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Wózek wyłączony z eksploatacji'),
          subtitle: Text(
            d.outOfService
                ? 'TAK — wózek zostanie zablokowany do decyzji administratora.'
                : 'NIE — wózek może dalej pracować.',
          ),
          value: d.outOfService,
          onChanged: enabled ? d.setOutOfService : null,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: d.mth,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(
            labelText: 'Motogodziny (MTH)',
            helperText: d.lastMth == null ? 'Z licznika wózka.' : 'Ostatnio zgłoszono: ${_mthText(d.lastMth!)}',
            errorText: d.mthBelowLast
                ? 'Mniej niż ostatnio (${_mthText(d.lastMth!)}). Sprawdź licznik — można wysłać.'
                : null,
          ),
          onChanged: (_) => d.textChanged(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: d.description,
          enabled: enabled,
          maxLines: 3,
          maxLength: 2000,
          decoration: const InputDecoration(labelText: 'Opis (opcjonalnie)', alignLabelWithHint: true),
        ),
        const SizedBox(height: 4),
        stepTitle(context, '${firstStep + 1}. Zdjęcia ${photoRequired ? '(co najmniej jedno)' : '(opcjonalnie)'}'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < d.photos.length; i++) _thumb(i),
            OutlinedButton.icon(
              onPressed: enabled ? () => _addPhotos(context, ImageSource.camera) : null,
              icon: const Icon(Icons.photo_camera),
              label: const Text('Zrób zdjęcie'),
            ),
            OutlinedButton.icon(
              onPressed: enabled ? () => _addPhotos(context, ImageSource.gallery) : null,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Z galerii'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _addPhotos(BuildContext context, ImageSource source) async {
    final picker = ImagePicker();
    // Shrunk on the device already; the server re-encodes anyway.
    const side = 2048.0;
    const quality = 80;
    final files = source == ImageSource.camera
        ? [?await picker.pickImage(source: source, maxWidth: side, maxHeight: side, imageQuality: quality)]
        : await picker.pickMultiImage(maxWidth: side, maxHeight: side, imageQuality: quality);
    for (final f in files) {
      final bytes = await f.readAsBytes();
      if (!context.mounted) return;
      draft.addPhoto(ReportPhoto(bytes, f.name.isEmpty ? 'zdjecie.jpg' : f.name));
      onChanged?.call();
    }
  }

  Widget _thumb(int i) => Stack(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(draft.photos[i].bytes, width: 96, height: 96, fit: BoxFit.cover),
      ),
      Positioned(
        right: 0,
        top: 0,
        child: IconButton.filledTonal(
          visualDensity: VisualDensity.compact,
          tooltip: 'Usuń zdjęcie',
          onPressed: enabled ? () => draft.removePhoto(i) : null,
          icon: const Icon(Icons.close, size: 16),
        ),
      ),
    ],
  );

  static String _mthText(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
}

Widget stepTitle(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text(text, style: Theme.of(context).textTheme.titleMedium),
);
