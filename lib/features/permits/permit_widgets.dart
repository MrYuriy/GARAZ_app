import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/widgets/filter_bar.dart';
import '../../core/i18n.dart';

/// Within this many days a permit counts as expiring (raport "wygasające uprawnienia").
const expiringSoonDays = 30;

/// Status of a permit — or "Brak uprawnień" when [status] is null.
class PermitStatusChip extends StatelessWidget {
  const PermitStatusChip({super.key, required this.status, this.daysLeft});

  final PermitStatus? status;

  /// Turns an active permit amber when it runs out within [expiringSoonDays].
  final int? daysLeft;

  @override
  Widget build(BuildContext context) {
    final soon = status == PermitStatus.active && daysLeft != null && daysLeft! <= expiringSoonDays;
    // The brand colour is amber already, so "expiring" amber is a status colour here.
    return StatusPill(
      label: status?.label ?? tr('Brak uprawnień'),
      color: switch (status) {
        PermitStatus.active when soon => Colors.amber,
        PermitStatus.active => Colors.green,
        PermitStatus.suspended => Colors.blueGrey,
        PermitStatus.expired => Colors.red,
        PermitStatus.archived => Colors.grey,
        null => Colors.grey,
      },
    );
  }
}

/// "ważne do 2027-03-31 (za 12 dni)" — "dni" fits every count but 1, which is said in words.
String validityText(PermitBrief p) {
  final when = switch (p.daysLeft) {
    0 => tr('ostatni dzień'),
    1 => tr('jutro ostatni dzień'),
    > 1 => tr('za {daysLeft} dni', {'daysLeft': p.daysLeft}),
    -1 => 'wczoraj',
    _ => tr('{daysLeft} dni temu', {'daysLeft': -p.daysLeft}),
  };
  return tr('ważne do {validUntil} ({when})', {'validUntil': formatDay(p.validUntil), 'when': when});
}
