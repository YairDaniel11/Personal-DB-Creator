import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../engine/auto_links.dart';
import '../engine/builder.dart';
import '../engine/common.dart';
import '../engine/linker_core.dart' show linkHeader;
import '../engine/seforim_db.dart';
import '../services/jobs.dart';
import '../services/settings_store.dart';

/// פעולה ארוכה שרצה עכשיו.
class Activity {
  Activity(this.title);
  String title;
  String detail = '';
  double? progress;
  bool cancelled = false;
}

class AppController extends ChangeNotifier {
  Settings settings = Settings();
  bool loaded = false;

  LibraryScan? scan;
  String? scanError;
  bool scanning = false;

  /// שגיאה בקובץ seforim.db (null = תקין או לא נבחר).
  String? officialError;

  Activity? activity;
  BuildResult? lastResult;

  /// דוח הקישורים האחרון (מבדיקה או מבנייה).
  List<BookLinkReport>? reports;

  /// שמות הספרים בספרייה הרשמית (לבחירת יעד ידנית).
  List<String>? officialTitles;

  String? lastMessage;
  bool lastMessageIsError = false;

  bool get busy => activity != null;
  ThemeMode get themeMode => settings.themeMode;
  bool get hasOfficial => settings.officialDb.isNotEmpty && officialError == null;

  /// מה חסר כדי לבנות (null = אפשר לבנות).
  String? get buildBlocker {
    if (settings.booksDir.isEmpty) return 'בחרו תיקיית ספרים';
    if (scan != null && scan!.books == 0) return 'אין ספרים בתיקייה';
    if (settings.outPath.isEmpty) return 'בחרו היכן לשמור את המסד';
    if (settings.displayName.trim().isEmpty) return 'תנו שם לספרייה';
    return null;
  }

  Future<void> init() async {
    settings = await SettingsStore.load();
    if (settings.libraryId.isEmpty) settings.libraryId = newLibraryId();
    if (settings.officialDb.isEmpty || !File(settings.officialDb).existsSync()) {
      settings.officialDb = findSeforimDb() ?? settings.officialDb;
    }
    loaded = true;
    _validateOfficial();
    notifyListeners();
    await _save();
    if (settings.booksDir.isNotEmpty) unawaited(rescan());
  }

  Future<void> _save() => SettingsStore.save(settings).catchError((_) {});

  void _changed() {
    notifyListeners();
    _save();
  }

  void showMessage(String msg, {bool error = false}) {
    lastMessage = msg;
    lastMessageIsError = error;
    notifyListeners();
  }

  void clearMessage() {
    lastMessage = null;
    notifyListeners();
  }

  // ─── הגדרות ───────────────────────────────────────────────────────

  void setThemeMode(ThemeMode m) {
    settings.themeMode = m;
    _changed();
  }

  Future<void> setBooksDir(String dir) async {
    settings.booksDir = dir;
    reports = null;
    if (settings.outDir.isEmpty) settings.outDir = p.dirname(dir);
    if (settings.outName.isEmpty) settings.outName = '${p.basename(dir)}.db';
    _changed();
    await rescan();
  }

  Future<void> rescan() async {
    final dir = settings.booksDir;
    if (dir.isEmpty) return;
    if (!Directory(dir).existsSync()) {
      scan = null;
      scanError = 'התיקייה לא נמצאה: $dir';
      notifyListeners();
      return;
    }
    scanning = true;
    scanError = null;
    notifyListeners();
    try {
      scan = await runJob(scanJob, dir);
    } catch (e) {
      scan = null;
      scanError = 'סריקת התיקייה נכשלה: $e';
    }
    scanning = false;
    notifyListeners();
  }

  void _validateOfficial() {
    officialError = settings.officialDb.isEmpty ? null : SeforimDb.validate(settings.officialDb);
  }

  void setOfficialDb(String path) {
    settings.officialDb = path;
    officialTitles = null;
    reports = null;
    _validateOfficial();
    _changed();
  }

  /// מחפש את seforim.db במיקומים המוכרים.
  bool detectOfficial() {
    final f = findSeforimDb();
    if (f == null) return false;
    setOfficialDb(f);
    return true;
  }

  void setOutDir(String dir) {
    settings.outDir = dir;
    _changed();
  }

  void setOutName(String name) {
    settings.outName = name.trim();
    _changed();
  }

  /// בחירת מסד קיים: ממשיכים לעדכן אותו (אותו מזהה ספרייה, הגרסה עולה).
  void useExistingDb(String path) {
    final id = libraryIdOf(path);
    if (id == null) {
      showMessage('הקובץ שנבחר אינו מסד שנבנה בתוכנה הזו (או ב-MyLibraryforOtzaria).', error: true);
      return;
    }
    settings.outDir = p.dirname(path);
    settings.outName = p.basename(path);
    settings.libraryId = id;
    _changed();
    showMessage('המסד יעודכן לגרסה הבאה, עם אותו מזהה ספרייה ($id).');
  }

  void setDisplayName(String v) {
    settings.displayName = v;
    _changed();
  }

  void setAuthor(String v) {
    settings.author = v;
    _changed();
  }

  void setAutoLinks(bool v) {
    settings.autoLinks = v;
    _changed();
  }

  void setDhLines(bool v) {
    settings.dhLines = v;
    _changed();
  }

  void setCompress(bool v) {
    settings.compress = v;
    _changed();
  }

  void regenerateLibraryId() {
    settings.libraryId = newLibraryId();
    _changed();
  }

  void clearOverrides() {
    settings.overrides = {};
    reports = null;
    _changed();
  }

  // ─── פעולות ארוכות ─────────────────────────────────────────────────

  void cancelActivity() {
    activity?.cancelled = true;
    notifyListeners();
  }

  Future<T?> _run<T>(
    String title,
    Future<T> Function(ProgressListener onProgress, bool Function() cancelled) job,
  ) async {
    if (busy) return null;
    final a = activity = Activity(title);
    lastMessage = null;
    notifyListeners();
    try {
      return await job((t, d, f) {
        a
          ..title = t
          ..detail = d
          ..progress = f;
        notifyListeners();
      }, () => a.cancelled);
    } on BuildCancelled {
      showMessage('הפעולה בוטלה.');
      return null;
    } on BuildError catch (e) {
      showMessage(e.message, error: true);
      return null;
    } catch (e) {
      showMessage('שגיאה: $e', error: true);
      return null;
    } finally {
      activity = null;
      notifyListeners();
    }
  }

  Future<bool> build() async {
    final blocker = buildBlocker;
    if (blocker != null) {
      showMessage(blocker, error: true);
      return false;
    }
    final s = settings;
    final opts = BuildOptions(
      booksDir: s.booksDir,
      outPath: s.outPath,
      libraryId: s.libraryId,
      displayName: s.displayName.trim(),
      author: s.author.trim(),
      officialDb: hasOfficial ? s.officialDb : null,
      autoLinks: s.autoLinks,
      dhLines: s.dhLines,
      compress: s.compress,
      overrides: Map.of(s.overrides),
    );
    final r = await _run(
      'בונה את הספרייה',
      (onProgress, cancelled) => runJob(buildJob, opts, onProgress: onProgress, isCancelled: cancelled),
    );
    if (r == null) return false;
    lastResult = r;
    if (r.reports.isNotEmpty || !s.autoLinks) reports = r.reports;
    notifyListeners();
    unawaited(rescan());
    return true;
  }

  Future<void> analyze({Set<String>? only}) async {
    if (settings.booksDir.isEmpty) {
      showMessage('בחרו קודם תיקיית ספרים', error: true);
      return;
    }
    if (!hasOfficial) {
      showMessage('בדיקת קישורים דורשת את הספרייה הרשמית של אוצריא (seforim.db)', error: true);
      return;
    }
    final args = AnalyzeArgs(settings.booksDir, settings.officialDb, Map.of(settings.overrides), only);
    final r = await _run(
      'בודק קישורים',
      (onProgress, cancelled) => runJob(analyzeJob, args, onProgress: onProgress, isCancelled: cancelled),
    );
    if (r == null) return;
    if (only != null && reports != null) {
      final byStem = {for (final x in r) x.stem: x};
      reports = [for (final x in reports!) byStem[x.stem] ?? x];
    } else {
      reports = r;
    }
    notifyListeners();
  }

  Future<List<String>> loadTitles() async {
    final cached = officialTitles;
    if (cached != null) return cached;
    if (!hasOfficial) return const [];
    final titles = await runJob(titlesJob, settings.officialDb);
    officialTitles = titles;
    return titles;
  }

  /// יעד ידני לספר: [target] = שם ספר, '' = בלי קישורים, null = חזרה לזיהוי אוטומטי.
  Future<void> setOverride(String stem, String? target) async {
    if (target == null) {
      settings.overrides.remove(stem);
    } else {
      settings.overrides[stem] = target;
    }
    _changed();
    if (reports != null) await analyze(only: {stem});
  }

  /// links.csv של כל הקישורים האוטומטיים (לשימוש חוזר או לבדיקה).
  String linksCsv() {
    final b = StringBuffer('\uFEFF');
    String f(String v) => v.contains(RegExp('[",\r\n]')) ? '"${v.replaceAll('"', '""')}"' : v;
    for (final r in [
      linkHeader,
      for (final rep in reports ?? const <BookLinkReport>[])
        if (rep.status == LinkStatus.linked) ...rep.csvRows(),
    ]) {
      b
        ..write(r.map(f).join(','))
        ..write('\r\n');
    }
    return b.toString();
  }

  /// פותח את סייר הקבצים על הקובץ או התיקייה.
  static Future<void> reveal(String path) async {
    try {
      if (Platform.isWindows) {
        if (File(path).existsSync()) {
          await Process.run('explorer.exe', ['/select,', path]);
        } else {
          await Process.run('explorer.exe', [path]);
        }
      } else if (Platform.isMacOS) {
        await Process.run('open', File(path).existsSync() ? ['-R', path] : [path]);
      } else {
        await Process.run('xdg-open', [File(path).existsSync() ? p.dirname(path) : path]);
      }
    } catch (_) {}
  }

  /// תיקיית הקישורים של הספרייה (יוצר אותה אם אינה קיימת).
  String linksDir() => p.join(settings.booksDir, linksDirName);
}
