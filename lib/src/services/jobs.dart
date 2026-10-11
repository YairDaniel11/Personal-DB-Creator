import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import '../engine/auto_links.dart';
import '../engine/builder.dart';
import '../engine/common.dart';
import '../engine/seforim_db.dart';

/// הקשר של עבודה שרצה ב-isolate: דיווח התקדמות ובדיקת ביטול.
class JobContext {
  JobContext(this._send, this._flagAddress);
  final SendPort _send;
  final int _flagAddress;
  final _clock = Stopwatch()..start();
  var _lastTitle = '';

  void progress(String title, String detail, double? fraction) {
    // מצמצם הודעות: כותרת חדשה תמיד, ועדכוני פרטים לכל היותר כל 80ms
    if (title == _lastTitle && _clock.elapsedMilliseconds < 80) return;
    _lastTitle = title;
    _clock.reset();
    _send.send((title, detail, fraction));
  }

  void checkCancel() {
    if (Pointer<Uint8>.fromAddress(_flagAddress).value != 0) throw BuildCancelled();
  }
}

typedef ProgressListener = void Function(String title, String detail, double? fraction);

/// מריץ [fn] על [arg] ב-isolate נפרד, כדי שהממשק לא ייתקע. [isCancelled] נבדק כמה פעמים בשנייה.
Future<T> runJob<A, T>(
  T Function(A arg, JobContext ctx) fn,
  A arg, {
  ProgressListener? onProgress,
  bool Function()? isCancelled,
}) async {
  final port = ReceivePort();
  final sub = port.listen((m) {
    if (m is (String, String, double?)) onProgress?.call(m.$1, m.$2, m.$3);
  });
  // בית אחד בזיכרון נייטיבי: הדבר היחיד ששני ה-isolates יכולים לחלוק.
  final flag = malloc.allocate<Uint8>(1)..value = 0;
  final poll = Timer.periodic(const Duration(milliseconds: 150), (_) {
    if (isCancelled?.call() ?? false) flag.value = 1;
  });
  try {
    return await _spawn(fn, arg, flag.address, port.sendPort);
  } finally {
    poll.cancel();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    port.close();
    malloc.free(flag);
  }
}

/// ה-closure נוצר כאן ולא ב-[runJob] בכוונה: closure שומר את ההקשר שבו נוצר, ושם יש אובייקטים שאי אפשר לשלוח.
Future<T> _spawn<A, T>(T Function(A, JobContext) fn, A arg, int flag, SendPort send) =>
    Isolate.run(() => fn(arg, JobContext(send, flag)));

// ───────────────────────────── עבודות ─────────────────────────────

BuildResult buildJob(BuildOptions o, JobContext ctx) =>
    buildLibrary(o, progress: ctx.progress, checkCancel: ctx.checkCancel);

class AnalyzeArgs {
  AnalyzeArgs(this.booksDir, this.officialDb, this.overrides, [this.only]);
  final String booksDir;
  final String officialDb;
  final Map<String, String> overrides;
  final Set<String>? only;
}

List<BookLinkReport> analyzeJob(AnalyzeArgs a, JobContext ctx) {
  final err = SeforimDb.validate(a.officialDb);
  if (err != null) throw BuildError('הספרייה הרשמית (seforim.db): $err');
  final db = SeforimDb(a.officialDb);
  try {
    final books = scanBooks(a.booksDir);
    return analyzeLinks(
      books: books,
      db: db,
      existing: existingLinkStems(p.join(a.booksDir, linksDirName)),
      overrides: a.overrides,
      only: a.only,
      onProgress: (d, t, s) => ctx.progress('בודק קישורים', s, t == 0 ? null : d / t),
      checkCancel: ctx.checkCancel,
    );
  } finally {
    db.close();
  }
}

List<String> titlesJob(String officialDb, JobContext ctx) {
  final db = SeforimDb(officialDb);
  try {
    return db.titles();
  } finally {
    db.close();
  }
}

/// סיכום תיקיית הספרים להצגה לפני הבנייה.
class LibraryScan {
  LibraryScan({
    required this.books,
    required this.categories,
    required this.rootFiles,
    required this.totalBytes,
    required this.linkCsvFiles,
    required this.hasDorot,
    required this.duplicates,
  });

  final int books;
  final int categories;

  /// קבצי TXT בתיקייה הראשית (לא נכנסים לספרייה).
  final int rootFiles;
  final int totalBytes;
  final int linkCsvFiles;
  final bool hasDorot;

  /// שמות ספרים שמופיעים יותר מפעם אחת.
  final List<String> duplicates;
}

LibraryScan scanJob(String booksDir, JobContext ctx) {
  final books = scanBooks(booksDir);
  final cats = <String>{};
  var bytes = 0;
  for (final b in books) {
    for (var i = 1; i <= b.rel.length; i++) {
      cats.add(b.rel.sublist(0, i).join('/'));
    }
    bytes += File(b.path).lengthSync();
  }
  var root = 0;
  try {
    root = Directory(booksDir)
        .listSync()
        .whereType<File>()
        .where(
          (f) =>
              p.extension(f.path).toLowerCase() == '.txt' &&
              p.basenameWithoutExtension(f.path).toLowerCase() != 'readme',
        )
        .length;
  } on FileSystemException {
    // תיקייה שאין גישה אליה: מדווח 0
  }
  final linksDir = p.join(booksDir, linksDirName);
  return LibraryScan(
    books: books.length,
    categories: cats.length,
    rootFiles: root,
    totalBytes: bytes,
    linkCsvFiles: userLinkCsvFiles(linksDir).length,
    hasDorot: File(p.join(linksDir, 'דורות.csv')).existsSync(),
    duplicates: [
      for (final e in booksByStem(books).entries)
        if (e.value.length > 1) e.key,
    ],
  );
}

/// library_id של מסד קיים (כדי להמשיך לעדכן אותו), או null.
String? libraryIdOf(String path) => PreviousDb.read(path)?.libraryId;
