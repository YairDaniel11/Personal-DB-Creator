import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../controllers/app_controller.dart';
import '../engine/auto_links.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_card.dart';
import '../widgets/common_widgets.dart';

enum _Filter { all, linked, notLinked, other }

/// דוח הקישורים: לכל ספר אם קושר, לאיזה יעד ובאיזה כלל, או למה לא. אפשר לבחור יעד ידנית.
class LinksScreen extends StatefulWidget {
  const LinksScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<LinksScreen> createState() => _LinksScreenState();
}

class _LinksScreenState extends State<LinksScreen> {
  var _filter = _Filter.all;
  var _query = '';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  AppController get c => widget.controller;

  Future<void> _export() async {
    final bytes = Uint8List.fromList(utf8.encode(c.linksCsv()));
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'שמירת קובץ הקישורים',
        fileName: 'links.csv',
        bytes: bytes,
        mimeType: 'text/csv',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );
      if (uri != null) c.showMessage('קובץ הקישורים נשמר.');
    } catch (e) {
      c.showMessage('השמירה נכשלה: $e', error: true);
    }
  }

  Future<void> _chooseTarget(BookLinkReport r) async {
    final titles = await c.loadTitles();
    if (!mounted) return;
    final res = await showDialog<_TargetChoice>(
      context: context,
      builder: (_) => _TargetDialog(stem: r.stem, titles: titles, current: c.settings.overrides[r.stem]),
    );
    if (res != null) await c.setOverride(r.stem, res.target);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final reports = c.reports;
        final theme = Theme.of(context);
        final children = <Widget>[
          AppCard(
            title: 'קישורים אוטומטיים',
            icon: FluentIcons.link_24_regular,
            info:
                'הבדיקה מראה מה ייקשר בבנייה, בלי לבנות. ספר שלא זוהה יעד עבורו (או שזוהה יעד שגוי) '
                'אפשר לקשר ידנית: בוחרים את הספר שהוא מפרש, והתוכנה מתאימה את הכותרות למבנה שלו. '
                'הבחירה נשמרת ותשמש בכל בנייה.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('לכל ספר: אם קושר, לאיזה ספר ובאיזה כלל, או למה לא.'),
                const SizedBox(height: AppTokens.spaceMD),
                Wrap(
                  spacing: AppTokens.spaceSM,
                  runSpacing: AppTokens.spaceSM,
                  children: [
                    FilledButton.icon(
                      onPressed: c.busy || c.settings.booksDir.isEmpty || !c.hasOfficial ? null : () => c.analyze(),
                      icon: const Icon(FluentIcons.search_24_regular),
                      label: Text(reports == null ? 'בדוק קישורים' : 'בדוק שוב'),
                    ),
                    if (reports != null)
                      OutlinedButton.icon(
                        onPressed: c.busy ? null : _export,
                        icon: const Icon(FluentIcons.arrow_download_24_regular),
                        label: const Text('ייצוא links.csv'),
                      ),
                    if (c.settings.overrides.isNotEmpty)
                      TextButton.icon(
                        onPressed: c.busy ? null : () => _confirmClear(context),
                        icon: const Icon(FluentIcons.arrow_reset_24_regular),
                        label: Text('נקה ${c.settings.overrides.length} בחירות ידניות'),
                      ),
                  ],
                ),
                if (!c.hasOfficial) ...[
                  const SizedBox(height: AppTokens.spaceSM),
                  const Hint('נדרשת הספרייה של אוצריא (seforim.db). בחרו אותה במסך הבנייה.', error: true),
                ],
              ],
            ),
          ),
          if (reports == null && !c.busy)
            const EmptyState(
              icon: FluentIcons.link_24_regular,
              title: 'עוד לא נבדקו קישורים',
              message: 'לחצו "בדוק קישורים" כדי לראות לכל ספר לאיזה ספר הוא יקושר, בלי לבנות את הספרייה.',
            ),
        ];
        if (reports != null) {
          final linked = reports.where((r) => r.status == LinkStatus.linked).toList();
          final total = linked.fold<int>(0, (a, r) => a + r.count);
          children.add(
            Wrap(
              spacing: AppTokens.spaceSM,
              runSpacing: AppTokens.spaceSM,
              children: [
                StatTile('${linked.length}', 'ספרים קושרו'),
                StatTile('${reports.where((r) => r.status == LinkStatus.notLinked).length}', 'לא קושרו'),
                StatTile('$total', 'שורות מקושרות'),
              ],
            ),
          );
          final notLinkedCount = reports.where((r) => r.status == LinkStatus.notLinked).length;
          final otherCount = reports
              .where((r) => r.status == LinkStatus.manual || r.status == LinkStatus.disabled)
              .length;
          final search = TextField(
            controller: _search,
            decoration: InputDecoration(
              prefixIcon: const Icon(FluentIcons.search_24_regular),
              hintText: 'חיפוש ספר',
              isDense: true,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'נקה חיפוש',
                      icon: const Icon(FluentIcons.dismiss_24_regular, size: 18),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          );
          final filter = SegmentedButton<_Filter>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: _Filter.all, label: Text('הכול (${reports.length})')),
              ButtonSegment(value: _Filter.linked, label: Text('קושרו (${linked.length})')),
              ButtonSegment(value: _Filter.notLinked, label: Text('לא קושרו ($notLinkedCount)')),
              ButtonSegment(value: _Filter.other, label: Text('אחר ($otherCount)')),
            ],
            selected: {_filter},
            onSelectionChanged: (s) => setState(() => _filter = s.first),
          );
          children.add(
            LayoutBuilder(
              builder: (context, box) => box.maxWidth < 900
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        search,
                        const SizedBox(height: AppTokens.spaceSM),
                        Align(alignment: AlignmentDirectional.centerStart, child: filter),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: search),
                        const SizedBox(width: AppTokens.spaceSM),
                        filter,
                      ],
                    ),
            ),
          );
          final shown = reports.where((r) {
            if (_query.isNotEmpty && !r.stem.contains(_query) && !(r.target ?? '').contains(_query)) return false;
            return switch (_filter) {
              _Filter.all => true,
              _Filter.linked => r.status == LinkStatus.linked,
              _Filter.notLinked => r.status == LinkStatus.notLinked,
              _Filter.other => r.status == LinkStatus.manual || r.status == LinkStatus.disabled,
            };
          }).toList();
          if (shown.isEmpty) {
            children.add(
              EmptyState(
                icon: FluentIcons.search_24_regular,
                title: reports.isEmpty ? 'אין ספרים' : 'אין ספרים שמתאימים לסינון',
              ),
            );
          }
          return PageBody(
            itemCount: shown.length,
            itemBuilder: (context, i) =>
                _BookRow(report: shown[i], busy: c.busy, onChoose: () => _chooseTarget(shown[i]), theme: theme),
            children: children,
          );
        }
        return PageBody(children: children);
      },
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ניקוי בחירות ידניות'),
        content: const Text('כל היעדים שבחרתם ידנית יימחקו, והספרים יחזרו לזיהוי האוטומטי. להמשיך?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('נקה')),
        ],
      ),
    );
    if (ok == true) {
      c.clearOverrides();
      await c.analyze();
    }
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({required this.report, required this.busy, required this.onChoose, required this.theme});

  final BookLinkReport report;
  final bool busy;
  final VoidCallback onChoose;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final details = <String>[
      if (r.rel.isNotEmpty) r.rel.join(' / '),
      if (r.status == LinkStatus.linked) ...[
        '← ${r.target}',
        r.method,
        '${r.count} קישורים${r.coverage != null ? ' (כיסוי ${(r.coverage! * 100).round()}%)' : ''}',
      ],
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMD, vertical: AppTokens.spaceSM),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(r.stem, style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: AppTokens.spaceSM),
                      LinkStatusTag(r.status),
                      if (r.overridden) ...[const SizedBox(width: AppTokens.spaceXS), const Tag('יעד ידני')],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Hint(details.join(' · ')),
                  if (r.reason.isNotEmpty) Hint(r.reason),
                ],
              ),
            ),
            if (r.status != LinkStatus.manual)
              TextButton.icon(
                onPressed: busy ? null : onChoose,
                icon: const Icon(FluentIcons.edit_24_regular, size: 18),
                label: const Text('בחר יעד'),
              ),
          ],
        ),
      ),
    );
  }
}

class _TargetChoice {
  const _TargetChoice(this.target);

  /// שם ספר, '' = בלי קישורים, null = זיהוי אוטומטי.
  final String? target;
}

/// בחירת ספר היעד מתוך הספרייה הרשמית, עם חיפוש.
class _TargetDialog extends StatefulWidget {
  const _TargetDialog({required this.stem, required this.titles, this.current});

  final String stem;
  final List<String> titles;
  final String? current;

  @override
  State<_TargetDialog> createState() => _TargetDialogState();
}

class _TargetDialogState extends State<_TargetDialog> {
  var _q = '';

  @override
  Widget build(BuildContext context) {
    final q = norm(_q);
    final all = <String>[if (q.isNotEmpty) ...widget.titles.where((t) => norm(t).contains(q))];
    // הקצרים קודם: "ברכות" לפני "ברכות - פירוש..."
    all.sort((a, b) => a.length.compareTo(b.length));
    final matches = all.take(200).toList();
    return AlertDialog(
      title: Text('יעד עבור "${widget.stem}"'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Hint('בחרו את הספר שעליו הספר הזה מפרש (למשל "ברכות", "בראשית", "שולחן ערוך, אורח חיים").'),
            if (widget.current != null) ...[
              const SizedBox(height: AppTokens.spaceXS),
              Hint('נבחר כעת: ${widget.current!.isEmpty ? 'בלי קישורים' : widget.current}'),
            ],
            const SizedBox(height: AppTokens.spaceSM),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(FluentIcons.search_24_regular),
                hintText: 'חיפוש בספרייה של אוצריא',
                isDense: true,
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: AppTokens.spaceSM),
            Expanded(
              child: q.isEmpty
                  ? const Center(
                      child: EmptyState(icon: FluentIcons.search_24_regular, title: 'הקלידו חלק משם הספר'),
                    )
                  : matches.isEmpty
                  ? const Center(
                      child: EmptyState(icon: FluentIcons.document_search_24_regular, title: 'לא נמצא ספר בשם הזה'),
                    )
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (_, i) => ListTile(
                        dense: true,
                        title: Text(matches[i]),
                        selected: matches[i] == widget.current,
                        onTap: () => Navigator.pop(context, _TargetChoice(matches[i])),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, const _TargetChoice(null)),
          child: const Text('זיהוי אוטומטי'),
        ),
        TextButton(onPressed: () => Navigator.pop(context, const _TargetChoice('')), child: const Text('בלי קישורים')),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('ביטול')),
      ],
    );
  }
}
