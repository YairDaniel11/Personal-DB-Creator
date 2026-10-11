import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../theme/app_tokens.dart';
import '../widgets/app_card.dart';
import '../widgets/common_widgets.dart';

/// עזרה: איך מסדרים את הספרים ומה צריך כדי שהקישורים ייווצרו.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageBody(
      children: [
        _Section(
          title: 'איך זה עובד',
          icon: FluentIcons.lightbulb_24_regular,
          children: [
            _Steps([
              'מסדרים את הספרים (קבצי TXT בפורמט אוצריא) בתיקיות במחשב. כל תיקייה היא קטגוריה.',
              'בוחרים את התיקייה בתוכנה ולוחצים "בנה את הספרייה".',
              'באוצריא: הגדרות ← ספרייה ← מסדי ספרים אישיים ← ייבא קובץ מסד, ובוחרים את הקובץ שנוצר.',
            ]),
            SizedBox(height: AppTokens.spaceSM),
            Hint('הכול נעשה במחשב, בלי חיבור לרשת. התוכנה רק קוראת את הספרייה של אוצריא (seforim.db), ולא משנה אותה.'),
          ],
        ),
        _Section(
          title: 'מבנה התיקיות',
          icon: FluentIcons.folder_24_regular,
          children: [
            Text('התיקייה שבוחרים היא "המדף". בתוכה תיקיות (קטגוריות), ובהן הספרים:'),
            _Code('''הספרים שלי
  תלמוד בבלי
    סדר נזיקין
      חידושים על בבא מציעא.txt
  הלכה
    ביאור על שולחן ערוך אורח חיים.txt
  קבצי קישורים וסדר הדורות      (לא חובה)
    דורות.csv
    קישורים
      שלי
        links.csv'''),
            _Bullets([
              'שם הקובץ הוא שם הספר. "חידושי הריטב"א על בבא מציעא.txt" יופיע באוצריא בשם "חידושי הריטב"א על בבא מציעא".',
              'כותרות בתוך הספר (תגיות h1 עד h6) הופכות לתוכן עניינים.',
              'לא נכנסים: קבצים שאינם TXT, קבצי README, וקבצים שמונחים ישירות בתיקייה הראשית ולא בתוך קטגוריה.',
            ]),
          ],
        ),
        _Section(
          title: 'קישורים לתלמוד הבבלי',
          icon: FluentIcons.book_24_regular,
          children: [
            Text('פירוש או חידושים על מסכת מקושרים לדף המתאים בגמרא, כשמתקיימים שלושה תנאים:'),
            _Steps([
              'הספר בתיקייה "תלמוד בבלי" (בכל תת-תיקייה, למשל "תלמוד בבלי/סדר נזיקין"), ולא ב"שס וגשל".',
              'שם המסכת כתוב בשם הקובץ, למשל "חידושים על בבא מציעא.txt". אפשר גם כותרת h2 בתוך הספר: "מסכת בבא מציעא".',
              'כל דף מסומן בכותרת משלו:',
            ]),
            _Code(ltr: true, '''<h2>ב.</h2>
הטקסט שעל עמוד א של דף ב
<h2>ב:</h2>
הטקסט שעל עמוד ב של דף ב'''),
            _Bullets([
              'נקודה (ב.) היא עמוד א, ושתי נקודות (ב:) הן עמוד ב. אפשר גם "יד, ב" או "דף ב ע"א".',
              'הכותרת חייבת להיות בתגית h2 (או h3 עד h6). "ב." בלי כותרת לא מזוהה.',
              'שורה שמתחילה בדיבור המתחיל מודגש (בתגית b) מקושרת לשורה המדויקת בגמרא, ולא רק לראש הדף.',
              'שורה ריקה, שורת כותרת והשורה הראשונה בקובץ לא מקושרות. דף שלא קיים בגמרא של אוצריא מדולג.',
            ]),
          ],
        ),
        _Section(
          title: 'קישורים לשאר הספרים',
          icon: FluentIcons.library_24_regular,
          children: [
            Text('גם לתנ"ך, שולחן ערוך, רמב"ם, ירושלמי ועוד התוכנה מנסה ליצור קישורים:'),
            _Bullets([
              'היא מחפשת בשם הקובץ את הספר שעליו הוא מפרש, בדרך כלל אחרי המילה "על": "ביאור על שולחן ערוך אורח חיים.txt" יקושר ל"שולחן ערוך, אורח חיים".',
              'הכותרות בספר צריכות להתאים למבנה ספר היעד: "פרק א" או "סימן ב" בכותרת h2, ובמשנה תורה גם "הלכה ג" בכותרת h3.',
              'הקישור נכתב רק אם לפחות חצי משורות הספר הצליחו להיקשר למקום שקיים באמת באוצריא.',
              'ספרים בתיקיות "תנך/ראשונים" ו"תנך/תרגומים" מקושרים לפי פרק. תרגום שיש בו שורה לכל פסוק מקושר פסוק-פסוק.',
            ]),
            SizedBox(height: AppTokens.spaceSM),
            Hint(
              'זה זיהוי כללי ולא תמיד מדויק. במסך "קישורים" רואים לכל ספר מה זוהה, ואפשר לבחור את היעד ידנית או לבטל קישורים לספר.',
            ),
          ],
        ),
        _Section(
          title: 'קישורים משלכם, מחברים ודורות',
          icon: FluentIcons.document_table_24_regular,
          children: [
            _Bullets([
              'קבצי links.csv בתיקייה "קבצי קישורים וסדר הדורות/קישורים/<שם כלשהו>/" נכללים כמות שהם, והספרים שבהם לא מקבלים קישורים אוטומטיים.',
              'עמודות links.csv: מקור (מספר שורה, מ-1), ספר_מקור, מקור_אישי, ספר_יעד, מיקום_יעד (למשל "פרק א", "סימן ב", "ב."), סוג, יעד_אישי, קטגוריית_מקור.',
              'דורות.csv באותה תיקייה, עם העמודות ספר, קטגוריה, דור, מחבר, מוסיף לכל ספר מחבר ודור.',
              'קובץ <שם ספר>_links.json (בפורמט אוצריא) ליד הספר יוצר קישורים בין ספרים שבספרייה שלכם.',
              'אפשר לייצא את הקישורים האוטומטיים כ-links.csv במסך "קישורים", לתקן, ולשים בתיקייה הזו.',
            ]),
          ],
        ),
        _Section(
          title: 'עדכון הספרייה',
          icon: FluentIcons.arrow_sync_24_regular,
          children: [
            _Bullets([
              'הוספתם, מחקתם או שיניתם ספרים? בונים שוב לאותו קובץ. הוא מתעדכן לגרסה הבאה, וספרים קיימים שומרים על המזהים שלהם.',
              'באוצריא מייבאים שוב את הקובץ המעודכן.',
              'במחשב אחר: "המשך לעדכן מסד קיים" במסך הבנייה, ובוחרים את הקובץ, כדי שהגרסה תמשיך מאותו מקום.',
            ]),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard(
    title: title,
    icon: icon,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

class _Steps extends StatelessWidget {
  const _Steps(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < items.length; i++)
        Padding(
          padding: const EdgeInsets.only(top: AppTokens.spaceXS),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Expanded(child: Text(items[i])),
            ],
          ),
        ),
    ],
  );
}

class _Bullets extends StatelessWidget {
  const _Bullets(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final t in items)
        Padding(
          padding: const EdgeInsets.only(top: AppTokens.spaceXS),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 18, child: Text('•')),
              Expanded(child: Text(t)),
            ],
          ),
        ),
    ],
  );
}

class _Code extends StatelessWidget {
  const _Code(this.text, {this.ltr = false});

  final String text;

  /// קוד עם תגיות: משמאל לימין, אחרת "<h2>ב.</h2>" מתהפך.
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: AppTokens.spaceSM),
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: AppTokens.borderRadiusAll),
      child: SelectableText(text, textDirection: ltr ? TextDirection.ltr : null, style: const TextStyle(height: 1.5)),
    );
  }
}
