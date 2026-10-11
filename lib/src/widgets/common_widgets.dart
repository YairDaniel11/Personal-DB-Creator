import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../engine/auto_links.dart';
import '../theme/app_tokens.dart';
import 'app_card.dart';

/// מציג את ההודעה האחרונה של הקונטרולר, עם כפתור סגירה.
class MessageBanner extends StatelessWidget {
  const MessageBanner({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final msg = controller.lastMessage;
    if (msg == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final err = controller.lastMessageIsError;
    final bg = err ? cs.errorContainer : cs.secondaryContainer;
    final fg = err ? cs.onErrorContainer : cs.onSecondaryContainer;
    return Container(
      padding: const EdgeInsetsDirectional.only(start: AppTokens.spaceMD, end: AppTokens.spaceXS),
      decoration: BoxDecoration(color: bg, borderRadius: AppTokens.borderRadiusAll),
      child: Row(
        children: [
          Icon(err ? Icons.error_outline : Icons.check_circle_outline, color: fg, size: 20),
          const SizedBox(width: AppTokens.spaceSM),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSM),
              child: SelectableText(msg, style: TextStyle(color: fg)),
            ),
          ),
          IconButton(
            tooltip: 'סגור',
            icon: Icon(Icons.close, color: fg, size: 20),
            onPressed: controller.clearMessage,
          ),
        ],
      ),
    );
  }
}

/// כרטיס התקדמות של פעולה ארוכה, עם כפתור "עצור".
class ActivityCard extends StatelessWidget {
  const ActivityCard({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final a = controller.activity;
    if (a == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(a.title, style: theme.textTheme.titleMedium)),
              TextButton(
                onPressed: a.cancelled ? null : controller.cancelActivity,
                child: Text(a.cancelled ? 'עוצר...' : 'עצור'),
              ),
            ],
          ),
          if (a.detail.isNotEmpty) ...[
            const SizedBox(height: AppTokens.spaceXS),
            Text(
              a.detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: AppTokens.spaceSM),
          ClipRRect(
            borderRadius: AppTokens.borderRadiusAll,
            child: LinearProgressIndicator(value: a.progress),
          ),
        ],
      ),
    );
  }
}

/// תגית קטנה בצבע לפי מצב.
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.kind = TagKind.neutral});

  final String label;
  final TagKind kind;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = switch (kind) {
      TagKind.good => (cs.primaryContainer, cs.onPrimaryContainer),
      TagKind.warn => (cs.tertiaryContainer, cs.onTertiaryContainer),
      TagKind.error => (cs.errorContainer, cs.onErrorContainer),
      TagKind.neutral => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceSM, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: AppTokens.borderRadiusAll),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: AppTokens.fontSM, fontWeight: FontWeight.w600),
      ),
    );
  }
}

enum TagKind { good, warn, error, neutral }

/// תגית סטטוס קישורים של ספר.
class LinkStatusTag extends StatelessWidget {
  const LinkStatusTag(this.status, {super.key});

  final LinkStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
    LinkStatus.linked => const Tag('קושר', kind: TagKind.good),
    LinkStatus.notLinked => const Tag('לא קושר', kind: TagKind.warn),
    LinkStatus.manual => const Tag('קישורים משלך'),
    LinkStatus.disabled => const Tag('בוטל'),
  };
}

/// שורת מספר + תווית בכרטיס סיכום.
class StatTile extends StatelessWidget {
  const StatTile(this.value, this.label, {super.key});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMD, vertical: AppTokens.spaceSM),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainer, borderRadius: AppTokens.borderRadiusAll),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// עמוד ברוחב מוגבל וממורכז, כמו בשאר המסכים.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppTokens.contentMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppTokens.spaceMD),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// טקסט משני (אפור).
class Hint extends StatelessWidget {
  const Hint(this.text, {super.key, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: error ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// נתיב קובץ: תמיד משמאל לימין (אחרת "C:\ספרים" מתהפך בממשק עברי), מיושר לימין.
class PathText extends StatelessWidget {
  const PathText(this.path, {super.key, this.maxLines});

  final String path;
  final int? maxLines;

  /// סימן כיוון שמאל-לימין אחרי כל מפריד: כל חלק בנתיב עומד בפני עצמו, וסדר החלקים נשמר.
  static final _lrm = String.fromCharCode(0x200E);
  static final _sep = String.fromCharCode(0x5C); // לוכסן הפוך

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: SelectableText(
      path.replaceAll(_sep, '$_sep$_lrm').replaceAll('/', '/$_lrm'),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
      maxLines: maxLines,
    ),
  );
}
