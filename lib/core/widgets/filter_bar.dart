import 'package:flutter/material.dart';

/// Below this width the filters hide behind an icon in the search field.
const _narrow = 720.0;

/// One choice in a [FilterGroup].
class FilterOption {
  const FilterOption(this.label, {required this.selected, required this.onSelected});

  final String label;
  final bool selected;
  final VoidCallback onSelected;
}

/// A set of filters picked one at a time ("Status"), or a single on/off
/// switch ([FilterGroup.toggle]).
class FilterGroup {
  const FilterGroup({required this.title, required this.options, this.activeLabel, this.onClear}) : toggle = null;

  FilterGroup.toggle({
    required this.title,
    required bool value,
    required ValueChanged<bool> onChanged,
    this.activeLabel,
  }) : toggle = (value, onChanged),
       options = const [],
       onClear = activeLabel == null ? null : (() => onChanged(!value));

  final String title;
  final List<FilterOption> options;
  final (bool, ValueChanged<bool>)? toggle;

  /// What the list is narrowed to, shown as a chip under the search; null
  /// while the group is at its default (nothing to show, nothing to clear).
  final String? activeLabel;

  /// Puts the group back to its default (the ✕ on the chip).
  final VoidCallback? onClear;
}

/// The search field, filters and "Razem" count above a list.
///
/// On a phone the filters live in a sheet behind an icon in the search field;
/// under the search only the filters in use show, each with a ✕. On a wide
/// screen they stay inline as chips.
///
/// [groups] is a function so the open sheet can redraw after each pick.
class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    this.searchController,
    this.onSearch,
    this.searchHint,
    required this.groups,
    this.total,
    this.pickerLabel,
  });

  final TextEditingController? searchController;
  final ValueChanged<String>? onSearch;
  final String? searchHint;

  /// Without a search field: the label of the field that opens the sheet
  /// (e.g. the dictionary shown).
  final String? pickerLabel;

  final List<FilterGroup> Function() groups;
  final int? total;

  bool get _hasSearch => searchController != null;

  @override
  Widget build(BuildContext context) {
    final count = total == null ? null : Text('Razem: $total', style: Theme.of(context).textTheme.bodySmall);
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= _narrow ? _wide(context, count) : _phone(context, count),
    );
  }

  Widget _wide(BuildContext context, Widget? count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_hasSearch) SizedBox(width: 320, child: _searchField(context, withIcon: false)),
          for (final g in groups()) ...[
            if (g.toggle case (final value, final onChanged))
              FilterChip(label: Text(g.title), selected: value, onSelected: onChanged)
            else
              for (final o in g.options)
                ChoiceChip(label: Text(o.label), selected: o.selected, onSelected: (_) => o.onSelected()),
          ],
          ?count,
        ],
      ),
    );
  }

  Widget _phone(BuildContext context, Widget? count) {
    final active = [
      for (final g in groups())
        if (g.activeLabel != null) g,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _hasSearch ? _searchField(context, withIcon: true, badge: active.length) : _picker(context),
          if (active.isNotEmpty || count != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final g in active)
                          InputChip(
                            label: Text(g.activeLabel!),
                            onPressed: () => _openSheet(context),
                            onDeleted: g.onClear,
                            deleteButtonTooltipMessage: 'Usuń filtr',
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ),
                  if (count != null) Padding(padding: const EdgeInsets.only(left: 8), child: count),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _searchField(BuildContext context, {required bool withIcon, int badge = 0}) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: searchController,
      onChanged: onSearch,
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search),
        hintText: searchHint,
        suffixIcon: withIcon && groups().isNotEmpty
            ? IconButton(
                tooltip: 'Filtry',
                onPressed: () => _openSheet(context),
                icon: Badge(
                  isLabelVisible: badge > 0,
                  backgroundColor: scheme.primary,
                  textColor: scheme.onPrimary,
                  label: Text('$badge'),
                  child: Icon(Icons.tune, color: badge > 0 ? scheme.primary : null),
                ),
              )
            : null,
      ),
    );
  }

  /// A field-like button standing in for the search on screens without one.
  Widget _picker(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => _openSheet(context),
      child: InputDecorator(
        decoration: const InputDecoration(isDense: true, suffixIcon: Icon(Icons.tune)),
        child: Text(pickerLabel ?? 'Filtry', style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, redraw) {
          // Each pick changes the screen's state; redraw to show it here too.
          void pick(VoidCallback act) {
            act();
            redraw(() {});
          }

          final theme = Theme.of(sheetContext);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final g in groups()) ...[
                    if (g.toggle case (final value, final onChanged))
                      SwitchListTile(title: Text(g.title), value: value, onChanged: (v) => pick(() => onChanged(v)))
                    else ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                        child: Text(
                          g.title,
                          style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
                        ),
                      ),
                      for (final o in g.options)
                        ListTile(
                          leading: Icon(
                            o.selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                            color: o.selected ? theme.colorScheme.primary : null,
                          ),
                          title: Text(o.label),
                          selected: o.selected,
                          onTap: () => pick(o.onSelected),
                        ),
                    ],
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: FilledButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Gotowe')),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A small coloured status label: a dot and a word. Fixed colours, not the
/// theme's, so green / amber / red read the same on every screen.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color, this.tooltip});

  final String label;
  final MaterialColor color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? color.shade900.withValues(alpha: 0.6) : color.shade50;
    final fg = dark ? color.shade100 : color.shade900;
    final dot = dark ? color.shade300 : color.shade600;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600, height: 1.2),
          ),
        ],
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip, child: pill);
  }
}
