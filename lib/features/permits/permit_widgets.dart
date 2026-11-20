import 'package:flutter/material.dart';

import '../../core/models.dart';

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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soon = status == PermitStatus.active && daysLeft != null && daysLeft! <= expiringSoonDays;
    // Fixed colours, not the theme's: green / amber / red must read the same
    // on every screen, and the brand colour is amber already.
    final MaterialColor base = switch (status) {
      PermitStatus.active when soon => Colors.amber,
      PermitStatus.active => Colors.green,
      PermitStatus.suspended => Colors.blueGrey,
      PermitStatus.expired => Colors.red,
      PermitStatus.archived => Colors.grey,
      null => Colors.grey,
    };
    final bg = dark ? base.shade900 : base.shade100;
    final fg = dark ? base.shade100 : base.shade900;
    return Chip(
      label: Text(status?.label ?? 'Brak uprawnień', style: TextStyle(color: fg)),
      backgroundColor: bg,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// "ważne do 2027-03-31 (za 12 dni)" — "dni" fits every count but 1, which is said in words.
String validityText(PermitBrief p) {
  final when = switch (p.daysLeft) {
    0 => 'ostatni dzień',
    1 => 'jutro ostatni dzień',
    > 1 => 'za ${p.daysLeft} dni',
    -1 => 'wczoraj',
    _ => '${-p.daysLeft} dni temu',
  };
  return 'ważne do ${formatDay(p.validUntil)} ($when)';
}
