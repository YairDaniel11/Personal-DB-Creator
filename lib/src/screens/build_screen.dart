import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../controllers/app_controller.dart';
import '../engine/builder.dart' show BuildResult, formatBytes;
import '../theme/app_tokens.dart';
import '../widgets/app_card.dart';
import '../widgets/common_widgets.dart';

/// המסך הראשי: בוחרים תיקיית ספרים, ובלחיצה אחת נבנה מסד אישי לאוצריא עם קישורים.
class BuildScreen extends StatefulWidget {
  const BuildScreen({super.key, required this.controller, required this.onGoLinks});

  final AppController controller;
  final VoidCallback onGoLinks;

  @override
  State<BuildScreen> createState() => _BuildScreenState();
}

class _BuildScreenState extends State<BuildScreen> {
  late final _name = TextEditingController(text: widget.controller.settings.displayName);
  late final _author = TextEditingController(text: widget.controller.settings.author);
  late final _outName = TextEditingController(text: widget.controller.settings.outName);
  var _syncedOutName = '';

  @override
  void dispose() {
    _name.dispose();
    _author.dispose();
    _outName.dispose();
    super.dispose();
  }

  AppController get c => widget.controller;

  Future<void> _pickBooks() async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: 'בחירת תיקיית הספרים');
    if (dir != null) await c.setBooksDir(dir);
  }

  Future<void> _pickOfficial() async {
    final f = await FilePicker.pickFile(
      dialogTitle: 'בחירת seforim.db של אוצריא',
      type: FileType.custom,
      allowedExtensions: const ['db'],
    );
    if (f?.path != null) c.setOfficialDb(f!.path!);
  }

  Future<void> _pickOutDir() async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: 'היכן לשמור את המסד');
    if (dir != null) c.setOutDir(dir);
  }

  Future<void> _pickExisting() async {
    final f = await FilePicker.pickFile(
      dialogTitle: 'בחירת מסד קיים לעדכון',
      type: FileType.custom,
      allowedExtensions: const ['db'],
    );
    if (f?.path != null) c.useExistingDb(f!.path!);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        // שם הקובץ עשוי להשתנות מבחוץ (בחירת תיקייה / מסד קיים)
        if (c.settings.outName != _syncedOutName && c.settings.outName != _outName.text) {
          _outName.text = c.settings.outName;
        }
        _syncedOutName = c.settings.outName;
        return PageBody(
          children: [
            _booksCard(context),
            _officialCard(context),
            _detailsCard(context),
            _outputCard(context),
            _buildCard(context),
            if (c.lastResult != null && !c.busy) _ResultCard(result: c.lastResult!, onGoLinks: widget.onGoLinks),
          ],
        );
      },
    );
  }

  Widget _booksCard(BuildContext context) {
    final s = c.settings;
    final scan = c.scan;
    return AppCard(
      title: '1. תיקיית הספרים',
      icon: FluentIcons.folder_24_regular,
      info:
          'תיקייה שבה הספרים (קבצי TXT בפורמט אוצריא) מסודרים בתיקיות. כל תיקייה הופכת לקטגוריה באוצריא, '
          'ושם הקובץ הוא שם הספר. קבצים שמונחים ישירות בתיקייה הראשית, קבצי README וקבצים שאינם TXT לא נכנסים.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s.booksDir.isEmpty) const Hint('עדיין לא נבחרה תיקייה.') else PathText(s.booksDir),
          if (c.scanning) ...[
            const SizedBox(height: AppTokens.spaceSM),
            const Hint('סורק...'),
          ] else if (c.scanError != null) ...[
            const SizedBox(height: AppTokens.spaceSM),
            Hint(c.scanError!, error: true),
          ] else if (scan != null) ...[
            const SizedBox(height: AppTokens.spaceSM),
            Wrap(
              spacing: AppTokens.spaceSM,
              runSpacing: AppTokens.spaceXS,
              children: [
                Tag('${scan.books} ספרים', kind: scan.books > 0 ? TagKind.good : TagKind.error),
                Tag('${scan.categories} קטגוריות'),
                Tag(formatBytes(scan.totalBytes)),
                if (scan.linkCsvFiles > 0) Tag('${scan.linkCsvFiles} קבצי links.csv'),
                if (scan.hasDorot) const Tag('דורות.csv'),
              ],
            ),
            if (scan.books == 0) ...[
              const SizedBox(height: AppTokens.spaceSM),
              const Hint(
                'לא נמצאו ספרים. הספרים צריכים להיות בתוך תיקיות (קטגוריות), ולא ישירות בתיקייה שנבחרה.',
                error: true,
              ),
            ],
            if (scan.rootFiles > 0) ...[
              const SizedBox(height: AppTokens.spaceSM),
              Hint(
                '${scan.rootFiles} קבצי TXT מונחים ישירות בתיקייה הראשית ולא ייכנסו. העבירו אותם לתיקייה (קטגוריה).',
              ),
            ],
            if (scan.duplicates.isNotEmpty) ...[
              const SizedBox(height: AppTokens.spaceSM),
              Hint(
                'ספרים עם אותו שם בכמה תיקיות (לא יקושרו אוטומטית): ${scan.duplicates.take(5).join(', ')}'
                '${scan.duplicates.length > 5 ? '...' : ''}',
              ),
            ],
          ],
          const SizedBox(height: AppTokens.spaceMD),
          Wrap(
            spacing: AppTokens.spaceSM,
            runSpacing: AppTokens.spaceSM,
            children: [
              if (s.booksDir.isEmpty)
                FilledButton.icon(
                  onPressed: c.busy ? null : _pickBooks,
                  icon: const Icon(FluentIcons.folder_open_24_regular),
                  label: const Text('בחר תיקייה'),
                )
              else ...[
                OutlinedButton.icon(
                  onPressed: c.busy ? null : _pickBooks,
                  icon: const Icon(FluentIcons.folder_open_24_regular),
                  label: const Text('החלף תיקייה'),
                ),
                TextButton.icon(
                  onPressed: c.busy || c.scanning ? null : c.rescan,
                  icon: const Icon(FluentIcons.arrow_sync_24_regular),
                  label: const Text('סרוק שוב'),
                ),
                TextButton.icon(
                  onPressed: () => AppController.reveal(s.booksDir),
                  icon: const Icon(FluentIcons.open_24_regular),
                  label: const Text('פתח בסייר'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _officialCard(BuildContext context) {
    final s = c.settings;
    final ok = c.hasOfficial;
    return AppCard(
      title: '2. הספרייה של אוצריא (seforim.db)',
      icon: FluentIcons.library_24_regular,
      info:
          'הקובץ seforim.db של אוצריא שכבר מותקנת במחשב. התוכנה קוראת אותו בלבד (בלי לשנות אותו), '
          'כדי למצוא לכל ספר את המקום המדויק בספרייה הרשמית ולאמת את הקישורים. '
          'בלעדיו הספרייה תיבנה בלי קישורים.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Tag(ok ? 'נמצא' : (s.officialDb.isEmpty ? 'לא נמצא' : 'לא תקין'), kind: ok ? TagKind.good : TagKind.warn),
              const SizedBox(width: AppTokens.spaceSM),
              Expanded(
                child: s.officialDb.isEmpty
                    ? const Hint('לא נמצאה אוצריא מותקנת. בחרו את הקובץ ידנית.')
                    : PathText(s.officialDb, maxLines: 2),
              ),
            ],
          ),
          if (c.officialError != null) ...[
            const SizedBox(height: AppTokens.spaceSM),
            Hint(c.officialError!, error: true),
          ],
          const SizedBox(height: AppTokens.spaceMD),
          Wrap(
            spacing: AppTokens.spaceSM,
            runSpacing: AppTokens.spaceSM,
            children: [
              OutlinedButton.icon(
                onPressed: c.busy ? null : _pickOfficial,
                icon: const Icon(FluentIcons.document_search_24_regular),
                label: const Text('בחר קובץ'),
              ),
              TextButton.icon(
                onPressed: c.busy
                    ? null
                    : () {
                        if (!c.detectOfficial()) c.showMessage('לא נמצא seforim.db במיקומים המוכרים.', error: true);
                      },
                icon: const Icon(FluentIcons.search_24_regular),
                label: const Text('חפש אוטומטית'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailsCard(BuildContext context) {
    final s = c.settings;
    final ok = c.hasOfficial;
    return AppCard(
      title: '3. פרטי הספרייה',
      icon: FluentIcons.edit_24_regular,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _name,
                  enabled: !c.busy,
                  decoration: const InputDecoration(
                    labelText: 'שם הספרייה (כפי שיוצג באוצריא)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: c.setDisplayName,
                ),
              ),
              const SizedBox(width: AppTokens.spaceSM),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _author,
                  enabled: !c.busy,
                  decoration: const InputDecoration(labelText: 'שם העורך (לא חובה)', border: OutlineInputBorder()),
                  onChanged: c.setAuthor,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSM),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('קישורים אוטומטיים'),
            subtitle: Text(
              ok
                  ? 'קישור כל ספר למקור שעליו הוא מפרש (גמרא, תנ"ך, שולחן ערוך, רמב"ם ועוד), לפי שם הקובץ והכותרות'
                  : 'דורש את הספרייה של אוצריא (seforim.db)',
            ),
            value: s.autoLinks && ok,
            onChanged: c.busy || !ok ? null : c.setAutoLinks,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('קישור לשורה המדויקת בגמרא'),
            subtitle: const Text('בפירוש על הש"ס: לפי הדיבור המתחיל המודגש, ולא רק לראש הדף'),
            value: s.dhLines && ok,
            onChanged: c.busy || !ok ? null : c.setDhLines,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('דחיסת הטקסט'),
            subtitle: const Text(
              'מקטינה מאוד ספרייה גדולה (מעל 3MB), באותה שיטה כמו הספרייה הרשמית. ספרייה קטנה לא נדחסת.',
            ),
            value: s.compress && ok,
            onChanged: c.busy || !ok ? null : c.setCompress,
          ),
        ],
      ),
    );
  }

  Widget _outputCard(BuildContext context) {
    final s = c.settings;
    final exists = s.outPath.isNotEmpty && File(s.outPath).existsSync();
    return AppCard(
      title: '4. קובץ המסד',
      icon: FluentIcons.database_24_regular,
      info:
          'הקובץ שייווצר ויוכנס לאוצריא. כשבונים שוב לאותו קובץ, הוא מתעדכן לגרסה הבאה, '
          'וספרים קיימים שומרים על המזהים שלהם (כך הסימניות וההיסטוריה באוצריא נשמרות).',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: s.outDir.isEmpty ? const Hint('לא נבחרה תיקייה.') : PathText(s.outDir, maxLines: 2)),
              const SizedBox(width: AppTokens.spaceSM),
              OutlinedButton.icon(
                onPressed: c.busy ? null : _pickOutDir,
                icon: const Icon(FluentIcons.folder_open_24_regular),
                label: const Text('בחר תיקייה'),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMD),
          TextField(
            controller: _outName,
            enabled: !c.busy,
            textDirection: TextDirection.rtl,
            decoration: const InputDecoration(labelText: 'שם הקובץ', suffixText: '.db', border: OutlineInputBorder()),
            onChanged: (v) {
              _syncedOutName = v.trim();
              c.setOutName(v);
            },
          ),
          const SizedBox(height: AppTokens.spaceSM),
          Hint(exists ? 'הקובץ קיים: הוא יעודכן לגרסה הבאה.' : 'קובץ חדש ייווצר.'),
          const SizedBox(height: AppTokens.spaceSM),
          TextButton.icon(
            onPressed: c.busy ? null : _pickExisting,
            icon: const Icon(FluentIcons.history_24_regular),
            label: const Text('המשך לעדכן מסד קיים...'),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    final blocker = c.buildBlocker;
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: blocker == null && !c.busy && !c.scanning ? c.build : null,
              icon: const Icon(FluentIcons.building_bank_toolbox_24_regular),
              label: Text(
                'בנה את הספרייה',
                style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onPrimary),
              ),
            ),
          ),
          const SizedBox(height: AppTokens.spaceSM),
          Center(
            child: Hint(
              blocker ??
                  (c.hasOfficial ? 'הכול נעשה במחשב, בלי חיבור לרשת.' : 'בלי seforim.db הספרייה תיבנה בלי קישורים.'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.onGoLinks});

  final BuildResult result;
  final VoidCallback onGoLinks;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final linked = r.reports.where((x) => x.count > 0).length;
    return AppCard(
      title: 'הספרייה נבנתה',
      icon: FluentIcons.checkmark_circle_24_regular,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PathText(r.outPath),
          const SizedBox(height: AppTokens.spaceMD),
          Wrap(
            spacing: AppTokens.spaceSM,
            runSpacing: AppTokens.spaceSM,
            children: [
              StatTile('${r.version}', 'גרסה'),
              StatTile('${r.books}', 'ספרים'),
              StatTile('${r.officialLinks}', 'קישורים לספרייה הרשמית'),
              if (r.innerLinks > 0) StatTile('${r.innerLinks}', 'קישורים בין ספריך'),
              StatTile(formatBytes(r.sizeBytes), r.compressed ? 'גודל (דחוס)' : 'גודל'),
            ],
          ),
          if (r.reports.isNotEmpty) ...[
            const SizedBox(height: AppTokens.spaceSM),
            Hint(
              '$linked מתוך ${r.reports.length} ספרים קושרו אוטומטית'
              '${(r.stats['dh_to_line'] ?? 0) > 0 ? '; ${r.stats['dh_to_line']} קישורים לשורה המדויקת בגמרא' : ''}.',
            ),
          ],
          for (final w in r.warnings) ...[const SizedBox(height: AppTokens.spaceXS), Hint(w, error: true)],
          const SizedBox(height: AppTokens.spaceMD),
          const Text('להכנסה לאוצריא: הגדרות ← ספרייה ← מסדי ספרים אישיים ← ייבא קובץ מסד.'),
          if (r.version > 1) const Hint('גרסה חדשה של ספרייה שכבר הוכנסה: מייבאים שוב את הקובץ, והוא מחליף את הקודם.'),
          const SizedBox(height: AppTokens.spaceMD),
          Wrap(
            spacing: AppTokens.spaceSM,
            runSpacing: AppTokens.spaceSM,
            children: [
              FilledButton.icon(
                onPressed: () => AppController.reveal(r.outPath),
                icon: const Icon(FluentIcons.folder_open_24_regular),
                label: const Text('הצג את הקובץ'),
              ),
              OutlinedButton.icon(
                onPressed: onGoLinks,
                icon: const Icon(FluentIcons.link_24_regular),
                label: const Text('לדוח הקישורים'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
