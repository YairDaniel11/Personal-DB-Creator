import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../controllers/app_controller.dart';
import '../theme/app_tokens.dart';
import '../widgets/common_widgets.dart';
import 'build_screen.dart';
import 'help_screen.dart';
import 'links_screen.dart';
import 'settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _goTo(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (!c.loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final screens = <Widget>[
      BuildScreen(controller: c, onGoLinks: () => _goTo(1)),
      LinksScreen(controller: c),
      const HelpScreen(),
      SettingsScreen(controller: c),
    ];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: _goTo,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSM),
              child: Image.asset('assets/icon.png', width: 40, height: 40),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(FluentIcons.building_bank_24_regular),
                selectedIcon: Icon(FluentIcons.building_bank_24_filled),
                label: Text('בניית ספרייה', textAlign: TextAlign.center),
              ),
              NavigationRailDestination(
                icon: Icon(FluentIcons.link_24_regular),
                selectedIcon: Icon(FluentIcons.link_24_filled),
                label: Text('קישורים'),
              ),
              NavigationRailDestination(
                icon: Icon(FluentIcons.question_circle_24_regular),
                selectedIcon: Icon(FluentIcons.question_circle_24_filled),
                label: Text('עזרה'),
              ),
              NavigationRailDestination(
                icon: Icon(FluentIcons.settings_24_regular),
                selectedIcon: Icon(FluentIcons.settings_24_filled),
                label: Text('הגדרות'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                if (c.lastMessage != null || c.activity != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppTokens.spaceMD, AppTokens.spaceMD, AppTokens.spaceMD, 0),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: AppTokens.contentMaxWidth),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (c.lastMessage != null) ...[
                              MessageBanner(controller: c),
                              const SizedBox(height: AppTokens.spaceSM),
                            ],
                            if (c.activity != null) ActivityCard(controller: c),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: IndexedStack(index: _index, children: screens),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
