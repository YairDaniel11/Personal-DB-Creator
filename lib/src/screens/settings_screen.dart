import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../controllers/app_controller.dart';
import '../services/settings_store.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_card.dart';
import '../widgets/common_widgets.dart';

/// גרסת התוכנה (מוזרקת בבנייה ב-GitHub Actions).
const appVersion = String.fromEnvironment('APP_VERSION');

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  Future<void> _confirmNewId(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('מזהה ספרייה חדש'),
        content: const Text(
          'המסד הבא ייחשב באוצריא לספרייה חדשה ונפרדת, ולא לעדכון של הקודמת. '
          'מתאים רק כשרוצים ליצור ספרייה שנייה. להמשיך?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('צור מזהה חדש')),
        ],
      ),
    );
    if (ok == true) controller.regenerateLibraryId();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        return PageBody(
          children: [
            AppCard(
              title: 'ערכת נושא',
              icon: FluentIcons.paint_brush_24_regular,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(FluentIcons.desktop_24_regular, size: 18),
                      label: Text('מערכת'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(FluentIcons.weather_sunny_24_regular, size: 18),
                      label: Text('בהיר'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(FluentIcons.weather_moon_24_regular, size: 18),
                      label: Text('כהה'),
                    ),
                  ],
                  selected: {c.themeMode},
                  onSelectionChanged: (s) => c.setThemeMode(s.first),
                ),
              ),
            ),
            Card(
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: const Icon(FluentIcons.wrench_24_regular),
                  title: const Text('מתקדם'),
                  subtitle: const Text('מזהה הספרייה ובחירות ידניות'),
                  childrenPadding: const EdgeInsets.all(AppTokens.spaceMD),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('מזהה הספרייה'),
                    const SizedBox(height: AppTokens.spaceXS),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(c.settings.libraryId, style: const TextStyle(fontFamily: 'Consolas')),
                        ),
                        CopyButton(c.settings.libraryId, onCopied: () => c.showMessage('מזהה הספרייה הועתק.')),
                      ],
                    ),
                    const SizedBox(height: AppTokens.spaceXS),
                    const Hint('לפיו אוצריא מזהה שמסד חדש הוא גרסה של אותה ספרייה. אין צורך לשנות אותו.'),
                    const SizedBox(height: AppTokens.spaceSM),
                    OutlinedButton.icon(
                      onPressed: c.busy ? null : () => _confirmNewId(context),
                      icon: const Icon(FluentIcons.add_24_regular),
                      label: const Text('צור מזהה חדש (ספרייה נפרדת)'),
                    ),
                    const Divider(height: AppTokens.spaceLG * 2),
                    Text('יעדים שנבחרו ידנית: ${c.settings.overrides.length}'),
                    const SizedBox(height: AppTokens.spaceSM),
                    OutlinedButton.icon(
                      onPressed: c.busy || c.settings.overrides.isEmpty ? null : c.clearOverrides,
                      icon: const Icon(FluentIcons.arrow_reset_24_regular),
                      label: const Text('נקה בחירות ידניות'),
                    ),
                    const Divider(height: AppTokens.spaceLG * 2),
                    const Text('קובץ ההגדרות'),
                    const SizedBox(height: AppTokens.spaceXS),
                    PathText(SettingsStore.configDir()),
                  ],
                ),
              ),
            ),
            AppCard(
              title: 'אודות',
              icon: FluentIcons.info_24_regular,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ספרייה אישית לאוצריא'),
                  const SizedBox(height: 4),
                  Hint(appVersion.isEmpty ? 'גרסת פיתוח' : 'גרסה $appVersion'),
                  const SizedBox(height: AppTokens.spaceSM),
                  const Hint(
                    'בונה מסד ספרים אישי לאוצריא מתיקיית ספרים במחשב, עם קישורים לספרייה הרשמית. '
                    'עובד בלי חיבור לרשת. מבוסס על MyLibraryforOtzaria ועל מנוע "מחולל הקישורים".',
                  ),
                  const SizedBox(height: AppTokens.spaceXS),
                  const Hint('פרויקט קהילתי שאינו קשור לתוכנת אוצריא הרשמית.'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
