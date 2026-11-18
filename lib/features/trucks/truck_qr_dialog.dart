import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/widgets/qr_code_dialog.dart';

/// A truck's QR sticker: preview, download, and (administrators) issue a new one.
/// Pops true when the code was re-issued.
class TruckQrDialog extends ConsumerWidget {
  const TruckQrDialog({super.key, required this.truck});

  final Truck truck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(authControllerProvider).user?.role.isAdmin ?? false;
    final repo = ref.read(trucksRepositoryProvider);
    return QrCodeDialog(
      title: truck.number,
      filename: 'qr-${truck.number}.png',
      issuedAt: truck.qrIssuedAt,
      caption: truck.qrUrl,
      loadPng: () => repo.qrPng(truck.id),
      reissueWarning: 'Obecna naklejka przestanie działać od razu. Trzeba będzie wydrukować i nakleić nową.',
      onReissue: isAdmin
          ? () async {
              final t = await repo.reissueQr(truck.id);
              return (t.qrIssuedAt, t.qrUrl);
            }
          : null,
    );
  }
}
