import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../controllers/app_controller.dart';
import '../theme/app_surfaces.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_title_bar.dart';
import '../widgets/common_widgets.dart';
import 'build_screen.dart';
import 'help_screen.dart';
import 'links_screen.dart';
import 'settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller, this.customTitleBar = false});

  final AppController controller;

  /// שורת כותרת משלנו במקום מסגרת המערכת (רק כשהחלון הוכן בלי מסגרת).
  final bool customTitleBar;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _shortcutKeys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
  ];

  static const _settingsIndex = 3;
  static const _titles = ['בניית ספרייה', 'קישורים', 'עזרה', 'הגדרות'];

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
    final hasTop = c.lastMessage != null || c.activity != null;

    final body = CallbackShortcuts(
      bindings: {
        for (var i = 0; i < _shortcutKeys.length; i++) SingleActivator(_shortcutKeys[i], control: true): () => _goTo(i),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _index < _settingsIndex ? _index : null,
                onDestinationSelected: _goTo,
                labelType: NavigationRailLabelType.all,
                minWidth: 84,
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.spaceMD),
                      child: _SettingsRailButton(
                        selected: _index == _settingsIndex,
                        onTap: () => _goTo(_settingsIndex),
                      ),
                    ),
                  ),
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
                ],
              ),
              VerticalDivider(width: 1, color: AppSurfaces.divider(context)),
              Expanded(
                child: Column(
                  children: [
                    AnimatedPadding(
                      duration: AppTokens.animNormal,
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.fromLTRB(
                        AppTokens.spaceMD,
                        hasTop ? AppTokens.spaceMD : 0,
                        AppTokens.spaceMD,
                        0,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: AppTokens.contentMaxWidth),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              MessageBanner(controller: c),
                              if (c.lastMessage != null && c.activity != null)
                                const SizedBox(height: AppTokens.spaceSM),
                              AnimatedSize(
                                duration: AppTokens.animNormal,
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.topCenter,
                                child: c.activity == null
                                    ? const SizedBox(width: double.infinity)
                                    : ActivityCard(controller: c),
                              ),
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
        ),
      ),
    );
    if (!widget.customTitleBar) return body;
    return Column(
      children: [
        AppTitleBar(screenTitle: _titles[_index]),
        Expanded(child: body),
      ],
    );
  }
}

class _SettingsRailButton extends StatelessWidget {
  const _SettingsRailButton({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          key: const ValueKey('nav-settings'),
          color: selected ? cs.secondaryContainer : Colors.transparent,
          borderRadius: AppTokens.borderRadiusAll,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 56,
              height: 32,
              child: Icon(
                selected ? FluentIcons.settings_24_filled : FluentIcons.settings_24_regular,
                color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text('הגדרות', style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}
