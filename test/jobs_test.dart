// הרצת עבודות ב-isolate: התקדמות, תוצאה, וביטול שמשאיר את הקובץ הקודם שלם.
// רצה רק עם OFFICIAL_DB, CORPUS_DIR, OUT_DB ו-ZSTD_LIB_PATH (ראו engine_build_test.dart).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_library_offline/src/engine/auto_links.dart';
import 'package:my_library_offline/src/engine/builder.dart';
import 'package:my_library_offline/src/services/jobs.dart';

void main() {
  final env = Platform.environment;
  final official = env['OFFICIAL_DB'], corpus = env['CORPUS_DIR'], out = env['OUT_DB'];
  final skip = official == null || corpus == null || out == null ? 'חסרים OFFICIAL_DB/CORPUS_DIR/OUT_DB' : null;

  BuildOptions opts() => BuildOptions(
    booksDir: corpus!,
    outPath: out!,
    libraryId: 'mylib-jobs',
    displayName: 'בדיקה',
    officialDb: official,
    overrides: const {'ספר רעיונות': 'בראשית'},
  );

  test('בנייה ב-isolate עם התקדמות', () async {
    final titles = <String>{};
    final r = await runJob(buildJob, opts(), onProgress: (t, d, f) => titles.add(t));
    expect(r.books, greaterThan(0));
    expect(File(out!).existsSync(), isTrue);
    expect(titles, contains('בונה את המסד'));
    // יעד ידני: "ספר רעיונות" -> בראשית (פרק א בכותרת h2)
    final idea = r.reports.firstWhere((x) => x.stem == 'ספר רעיונות');
    expect(idea.overridden, isTrue);
    // ignore: avoid_print
    print('override: ${idea.status} ${idea.target} ${idea.reason}');
  }, skip: skip);

  test('ביטול משאיר את הקובץ הקודם', () async {
    final before = File(out!).readAsBytesSync();
    await expectLater(runJob(buildJob, opts(), isCancelled: () => true), throwsA(isA<BuildCancelled>()));
    expect(File(out).readAsBytesSync(), before);
    expect(File('$out.part').existsSync(), isFalse);
  }, skip: skip);

  test('בדיקת קישורים לספר אחד', () async {
    final r = await runJob(analyzeJob, AnalyzeArgs(corpus!, official!, const {}, {'פירוש על בראשית'}));
    expect(r.single.status, LinkStatus.linked);
    expect(r.single.target, 'בראשית');
  }, skip: skip);
}
