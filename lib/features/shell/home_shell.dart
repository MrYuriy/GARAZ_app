import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';

class _Tab {
  const _Tab(this.branch, this.label, this.icon, {this.adminOnly = false});

  final int branch;
  final String label;
  final IconData icon;
  final bool adminOnly;
}

const _tabs = [
  _Tab(1, 'Użytkownicy', Icons.group_outlined, adminOnly: true),
  _Tab(3, 'Słowniki', Icons.list_alt),
  _Tab(2, 'Dziennik', Icons.history, adminOnly: true),
  _Tab(0, 'Konto', Icons.person_outline),
];

/// Navigation rail on wide screens (office), bottom bar on phones.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(authControllerProvider).user?.role.isAdmin ?? false;
    final tabs = _tabs.where((t) => isAdmin || !t.adminOnly).toList();
    final selected = tabs.indexWhere((t) => t.branch == navigationShell.currentIndex).clamp(0, tabs.length - 1);
    void go(int i) => navigationShell.goBranch(tabs[i].branch, initialLocation: tabs[i].branch == navigationShell.currentIndex);

    final wide = MediaQuery.sizeOf(context).width >= 720;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selected,
              onDestinationSelected: go,
              labelType: NavigationRailLabelType.all,
              leading: const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Icon(Icons.forklift, size: 32)),
              destinations: [
                for (final t in tabs) NavigationRailDestination(icon: Icon(t.icon), label: Text(t.label)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: tabs.length < 2
          ? null
          : NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: go,
              destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.icon), label: t.label)],
            ),
    );
  }
}
