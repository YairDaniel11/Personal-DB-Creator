// בדיקת המנוע מול ספרייה רשמית אמיתית. רצה רק כשמוגדרים:
//   OFFICIAL_DB  = נתיב ל-seforim.db
//   CORPUS_DIR   = תיקיית ספרי בדיקה
//   OUT_DB       = קובץ הפלט
//   ZSTD_LIB_PATH = libzstd (בהרצת flutter test הפלאגין אינו טעון)
// אופציונלי: COMPRESS=1 לדחיסה גם בספרייה קטנה.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_library_offline/src/engine/builder.dart';

void main() {
  final env = Platform.environment;
  final official = env['OFFICIAL_DB'], corpus = env['CORPUS_DIR'], out = env['OUT_DB'];
  final skip = official == null || corpus == null || out == null ? 'חסרים OFFICIAL_DB/CORPUS_DIR/OUT_DB' : null;

  test(
    'בניית ספרייה מלאה',
    () {
      final sw = Stopwatch()..start();
      final r = buildLibrary(
        BuildOptions(
          booksDir: corpus!,
          outPath: out!,
          libraryId: env['LIBRARY_ID'] ?? 'mylib-test',
          displayName: 'בדיקה',
          officialDb: official,
          compress: true,
          forceCompress: env['COMPRESS'] == '1',
        ),
        progress: (t, d, f) {},
      );
      // ignore: avoid_print
      print(
        'books=${r.books} lines=${r.lines} links=${r.officialLinks} inner=${r.innerLinks} '
        'v=${r.version} compressed=${r.compressed} size=${r.sizeBytes} ${sw.elapsedMilliseconds}ms\n${r.stats}',
      );
      for (final rep in r.reports) {
        // ignore: avoid_print
        print('${rep.status.name}\t${rep.stem}\t${rep.target}\t${rep.method}\t${rep.count}\t${rep.reason}');
      }
      for (final w in r.warnings) {
        // ignore: avoid_print
        print('warning: $w');
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
