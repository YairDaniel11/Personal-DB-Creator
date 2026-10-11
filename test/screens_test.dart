// בדיקת עשן למסכים: כל מסך נבנה בלי שגיאות (גלישה, חריגות) בגודל חלון רגיל.
// עם SCREENSHOTS=1 נשמרות גם תמונות (flutter test --update-goldens) לבדיקה ויזואלית.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_library_offline/src/controllers/app_controller.dart';
import 'package:my_library_offline/src/engine/auto_links.dart';
import 'package:my_library_offline/src/engine/builder.dart';
import 'package:my_library_offline/src/screens/app_shell.dart';
import 'package:my_library_offline/src/services/jobs.dart';
import 'package:my_library_offline/src/theme/app_theme.dart';

Future<void> _loadFont(String family, String path) async {
  final f = File(path);
  if (!f.existsSync()) return;
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  await loader.load();
}

AppController _controller() {
  final c = AppController()
    ..loaded = true
    ..scan = LibraryScan(
      books: 8,
      categories: 8,
      rootFiles: 1,
      totalBytes: 12345,
      linkCsvFiles: 1,
      hasDorot: true,
      duplicates: const [],
    );
  c.settings
    ..booksDir = r'C:\ספרים\הספרים שלי'
    ..officialDb = r'C:\ProgramData\otzaria\books\seforim.db'
    ..outDir = r'C:\ספרים'
    ..outName = 'הספרים שלי.db'
    ..libraryId = 'mylib-test';
  c.reports = [
    BookLinkReport(
      stem: 'חידושי בדיקה על מסכת ברכות',
      rel: const ['תלמוד בבלי', 'סדר זרעים'],
      status: LinkStatus.linked,
      target: 'ברכות',
      method: 'תלמוד בבלי (כותרות דף)',
      rows: {for (var i = 3; i < 12; i++) i: ('ברכות', 'ב.')},
    ),
    BookLinkReport(
      stem: 'ביאור על שולחן ערוך אורח חיים',
      rel: const ['הלכה'],
      status: LinkStatus.linked,
      target: 'שולחן ערוך, אורח חיים',
      method: 'שולחן ערוך: סימן ברמה 2',
      coverage: 1,
      overridden: true,
      rows: {for (var i = 3; i < 11; i++) i: ('שולחן ערוך, אורח חיים', 'סימן א')},
    ),
    BookLinkReport(
      stem: 'ספר רעיונות',
      rel: const ['כללי'],
      status: LinkStatus.notLinked,
      reason: 'לא זוהה ספר יעד בשם הקובץ',
    ),
    BookLinkReport(
      stem: 'הערות שלי',
      rel: const ['כללי'],
      status: LinkStatus.manual,
      reason: 'יש לספר קישורים משלך (links.csv), והם נכללים כמות שהם',
    ),
  ];
  c.lastResult = BuildResult(
    outPath: r'C:\ספרים\הספרים שלי.db',
    version: 2,
    books: 8,
    lines: 107,
    categories: 8,
    officialLinks: 66,
    innerLinks: 2,
    sizeBytes: 2220032,
    compressed: true,
    stableFromPrevious: true,
    reports: c.reports!,
    stats: const {'dh_to_line': 6},
    warnings: const [],
  );
  return c;
}

void main() {
  final shots = Platform.environment['SCREENSHOTS'] == '1';

  setUpAll(() async {
    await _loadFont('Segoe UI', r'C:\Windows\Fonts\segoeui.ttf');
    await _loadFont('Consolas', r'C:\Windows\Fonts\consola.ttf');
    final pub = '${Platform.environment['LOCALAPPDATA']}\\Pub\\Cache\\hosted\\pub.dev';
    await _loadFont(
      'packages/fluentui_system_icons/FluentSystemIcons-Regular',
      '$pub\\fluentui_system_icons-1.1.273\\lib\\fonts\\FluentSystemIcons-Regular.ttf',
    );
    await _loadFont(
      'packages/fluentui_system_icons/FluentSystemIcons-Filled',
      '$pub\\fluentui_system_icons-1.1.273\\lib\\fonts\\FluentSystemIcons-Filled.ttf',
    );
    await _loadFont('MaterialIcons', r'C:\src\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf');
  });

  for (final dark in [false, true]) {
    for (final (i, name) in [(0, 'build'), (1, 'links'), (2, 'help'), (3, 'settings')]) {
      testWidgets('מסך $name ${dark ? 'כהה' : 'בהיר'}', (tester) async {
        tester.view.physicalSize = const Size(1280, 860);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final c = _controller();
        final theme = (dark ? AppTheme.dark() : AppTheme.light()).copyWith();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: 'Segoe UI')),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: AppShell(controller: c),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (i > 0) {
          final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
          rail.onDestinationSelected!(i);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        if (shots) {
          await expectLater(find.byType(AppShell), matchesGoldenFile('goldens/${name}_${dark ? 'dark' : 'light'}.png'));
        }
      });
    }
  }
}
