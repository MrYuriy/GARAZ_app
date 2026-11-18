import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import 'permit_dialog.dart';
import 'permit_widgets.dart';

enum _Filter {
  all('Wszystkie'),
  expiring('Wygasające ($expiringSoonDays dni)'),
  suspended('Zawieszone'),
  expired('Wygasłe');

  const _Filter(this.label);

  final String label;
}

/// The permits register across operators, soonest to expire first.
/// New permits are added from the operator's page.
class PermitsScreen extends ConsumerStatefulWidget {
  const PermitsScreen({super.key});

  @override
  ConsumerState<PermitsScreen> createState() => _PermitsScreenState();
}

class _PermitsScreenState extends ConsumerState<PermitsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  _Filter _filter = _Filter.all;
  PageOf<Permit>? _page;
  bool _loading = false;
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(permitsRepositoryProvider)
          .list(
            query: _search.text.trim(),
            status: switch (_filter) {
              _Filter.expiring => PermitStatus.active,
              _Filter.suspended => PermitStatus.suspended,
              _Filter.expired => PermitStatus.expired,
              _Filter.all => null,
            },
            expiringWithinDays: _filter == _Filter.expiring ? expiringSoonDays : null,
          );
      if (mounted) setState(() => _page = page);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _open(Permit p) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => PermitDialog(permit: p),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _page?.items ?? const <Permit>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Uprawnienia'),
        actions: [IconButton(tooltip: 'Odśwież', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: _search,
                    onChanged: _onSearch,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Szukaj: nr pozwolenia, nazwisko',
                    ),
                  ),
                ),
                for (final f in _Filter.values)
                  ChoiceChip(
                    label: Text(f.label),
                    selected: _filter == f,
                    onSelected: (_) {
                      setState(() => _filter = f);
                      _load();
                    },
                  ),
                if (_page != null) Text('Razem: ${_page!.total}'),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: items.isEmpty && !_loading
                ? const Center(child: Text('Brak uprawnień. Nowe dodasz na stronie operatora.'))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = items[i];
                      return ListTile(
                        onTap: () => _open(p),
                        title: Text('${p.operatorName} · ${p.number}'),
                        subtitle: Text(
                          [p.category.name, p.truckTypes.map((t) => t.name).join(', '), validityText(p)].join(' · '),
                        ),
                        trailing: PermitStatusChip(status: p.status, daysLeft: p.daysLeft),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
