import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

class DaneShell extends StatelessWidget {
  const DaneShell({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= 760;

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.blur_circular_rounded),
                  label: Text('Dane'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.forum_outlined),
                  label: Text('Chat'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.security_rounded),
                  label: Text('Permissions'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.bolt_rounded),
                  label: Text('Automation'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.tune_rounded),
                  label: Text('Settings'),
                ),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.blur_circular_rounded),
            label: 'Dane',
          ),
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.security_rounded),
            label: 'Access',
          ),
          NavigationDestination(
            icon: Icon(Icons.bolt_rounded),
            label: 'Actions',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
