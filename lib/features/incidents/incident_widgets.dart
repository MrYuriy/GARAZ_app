import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/widgets/filter_bar.dart';

class IncidentStatusChip extends StatelessWidget {
  const IncidentStatusChip({super.key, required this.status});

  final IncidentStatus status;

  @override
  Widget build(BuildContext context) {
    return StatusPill(
      label: status.label,
      color: switch (status) {
        IncidentStatus.newReport => Colors.red,
        IncidentStatus.inProgress => Colors.amber,
        IncidentStatus.closed => Colors.green,
      },
    );
  }
}

IconData incidentTypeIcon(IncidentType t) => switch (t) {
  IncidentType.awaria => Icons.build_circle_outlined,
  IncidentType.uszkodzenie => Icons.broken_image_outlined,
  IncidentType.kolizja => Icons.car_crash_outlined,
};

/// A report photo fetched with the session (photos are not public URLs).
class IncidentPhoto extends ConsumerWidget {
  const IncidentPhoto({
    super.key,
    required this.incidentId,
    required this.photoId,
    this.thumb = true,
    this.size,
    this.fit = BoxFit.cover,
  });

  final int incidentId;
  final int photoId;
  final bool thumb;
  final double? size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final future = ref.read(incidentsRepositoryProvider).photo(incidentId, photoId, thumb: thumb);
    return SizedBox(
      width: size,
      height: size,
      child: FutureBuilder<Uint8List>(
        future: future,
        builder: (_, snap) {
          if (snap.hasData) return Image.memory(snap.data!, fit: fit, gaplessPlayback: true);
          if (snap.hasError) return const Center(child: Icon(Icons.broken_image_outlined));
          return const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
        },
      ),
    );
  }
}

String formatMth(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

/// A report in a list: first photo, truck, kind and category, driver, time, marks, status.
class IncidentTile extends StatelessWidget {
  const IncidentTile({super.key, required this.incident, required this.onTap});

  final Incident incident;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final i = incident;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: i.photos.isEmpty
            ? SizedBox(width: 56, height: 56, child: Icon(incidentTypeIcon(i.type)))
            : IncidentPhoto(incidentId: i.id, photoId: i.photos.first.id, size: 56),
      ),
      title: Row(
        children: [
          Text(tr('{name} · ', {'name': i.truck.name}), style: const TextStyle(fontWeight: FontWeight.w700)),
          Icon(incidentTypeIcon(i.type), size: 18),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              tr('{label} · {name}', {'label': i.type.label, 'name': i.category.name}),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: [
                i.driver,
                formatDateTime(i.occurredAt),
                if (i.mth != null) 'MTH ${formatMth(i.mth!)}',
                if (i.outOfService) tr('wyłączony z eksploatacji'),
              ].join(' · '),
            ),
            for (final f in i.flags) ...[
              const TextSpan(text: '  '),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(Icons.warning_amber, size: 16, color: scheme.error),
              ),
              TextSpan(
                text: ' ${incidentFlagLabel(f)}',
                style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
      trailing: IncidentStatusChip(status: i.status),
    );
  }
}
