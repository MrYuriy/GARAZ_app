import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';

class IncidentStatusChip extends StatelessWidget {
  const IncidentStatusChip({super.key, required this.status});

  final IncidentStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      IncidentStatus.newReport => (Colors.red.shade50, Colors.red.shade800),
      IncidentStatus.inProgress => (Colors.amber.shade100, Colors.brown.shade800),
      IncidentStatus.closed => (Colors.green.shade50, Colors.green.shade800),
    };
    return Chip(
      label: Text(
        status.label,
        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
      ),
      backgroundColor: bg,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
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
