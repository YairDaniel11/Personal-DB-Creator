// בונה מסד ספרים אישי לאוצריא (SQLite): ספרים + קטגוריות + דורות + מחברים + קישורים.
// תרגום של build_personal_db.py + compress_personal_db.py מ-MyLibraryforOtzaria, בלי רשת ובלי GitHub.
//
// - כל שורת קובץ = שורה במסד (lineIndex = מספר שורה בקובץ פחות 1). כותרות <h1>-<h6> = תוכן עניינים.
// - קטגוריות = התיקיות. דורות ומחברים מ-<קבצי קישורים וסדר הדורות>/דורות.csv.
// - קישורים: אוטומטיים (מחולל הקישורים) + links.csv של המשתמש -> external_link אל הספרייה הרשמית;
//   <ספר>_links.json -> קישורים בין ספרי המסד עצמו.
// - מזהים יציבים: אם קובץ הפלט כבר קיים (בנייה קודמת של אותה ספרייה), ספרים/קטגוריות קיימים שומרים מזהה,
//   וגרסת המסד עולה ב-1.
// - דחיסה: בספרייה גדולה טקסט השורות נדחס ב-zstd עם המילון של הספרייה הרשמית (סכמה 6 של אוצריא).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'auto_links.dart';
import 'common.dart';
import 'dh_lines.dart';
import 'seforim_db.dart';
import 'zstd.dart';

/// מזהה = bookId * rowStride + מונה: שורות ותוכן עניינים של ספר לא תלויים בספרים אחרים.
const rowStride = 1 << 20;

/// מתחת לגודל הזה (סך הטקסט) הדחיסה לא משתלמת: המילון לבדו כ-2MB.
const compressThresholdBytes = 3 * 1024 * 1024;

class BuildCancelled implements Exception {
  @override
  String toString() => 'הפעולה בוטלה';
}

class BuildError implements Exception {
  BuildError(this.message);
  final String message;
  @override
  String toString() => message;
}

class BuildOptions {
  BuildOptions({
    required this.booksDir,
    required this.outPath,
    required this.libraryId,
    required this.displayName,
    this.officialDb,
    this.author = '',
    this.autoLinks = true,
    this.dhLines = true,
    this.compress = true,
    this.forceCompress = false,
    this.overrides = const {},
  });

  final String booksDir;
  final String outPath;
  final String libraryId;
  final String displayName;
  final String? officialDb;
  final String author;
  final bool autoLinks;
  final bool dhLines;

  /// לדחוס כשמשתלם (ספרייה גדולה ויש מילון בספרייה הרשמית).
  final bool compress;

  /// לדחוס גם ספרייה קטנה (לבדיקות).
  final bool forceCompress;
  final Map<String, String> overrides;
}

class BuildResult {
  BuildResult({
    required this.outPath,
    required this.version,
    required this.books,
    required this.lines,
    required this.categories,
    required this.officialLinks,
    required this.innerLinks,
    required this.sizeBytes,
    required this.compressed,
    required this.stableFromPrevious,
    required this.reports,
    required this.stats,
    required this.warnings,
  });

  final String outPath;
  final int version;
  final int books;
  final int lines;
  final int categories;
  final int officialLinks;
  final int innerLinks;
  final int sizeBytes;
  final bool compressed;
  final bool stableFromPrevious;
  final List<BookLinkReport> reports;
  final Map<String, int> stats;
  final List<String> warnings;
}

/// דיווח התקדמות: [fraction] בין 0 ל-1 (או null = לא ידוע).
typedef ProgressFn = void Function(String title, String detail, double? fraction);

class _Ids {
  _Ids([Map<Object, int>? prev]) : map = {...?prev} {
    next = map.values.fold<int>(0, (a, b) => a > b ? a : b) + 1;
  }
  final Map<Object, int> map;
  late int next;

  int get(Object key) => map[key] ??= next++;
}

/// נתונים מבנייה קודמת: מזהים, גרסה, library_id.
class PreviousDb {
  PreviousDb({
    required this.libraryId,
    required this.version,
    required this.category,
    required this.book,
    required this.tocText,
    required this.author,
    required this.generation,
  });

  final String? libraryId;
  final int version;
  final Map<Object, int> category, book, tocText, author, generation;

  static PreviousDb? read(String path) {
    if (!File(path).existsSync()) return null;
    Database? db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
      final meta = {
        for (final r in db.select('SELECT key, value FROM schema_meta')) r['key'] as String: '${r['value']}',
      };
      final rows = {
        for (final r in db.select('SELECT id, parentId, title FROM category'))
          r['id'] as int: (r['parentId'] as int?, r['title'] as String),
      };
      final cache = <int, String>{};
      String full(int i) => cache[i] ??= () {
        final (par, t) = rows[i]!;
        return par != null && rows.containsKey(par) ? '${full(par)}\u0000$t' : t;
      }();
      return PreviousDb(
        libraryId: meta['library_id'],
        version: int.tryParse(meta['db_version'] ?? '') ?? 0,
        category: {for (final i in rows.keys) full(i): i},
        book: {for (final r in db.select('SELECT id, title FROM book')) r['title'] as String: r['id'] as int},
        tocText: {for (final r in db.select('SELECT id, text FROM tocText')) r['text'] as String: r['id'] as int},
        author: {for (final r in db.select('SELECT id, name FROM author')) r['name'] as String: r['id'] as int},
        generation: {for (final r in db.select('SELECT id, name FROM generation')) r['name'] as String: r['id'] as int},
      );
    } catch (_) {
      return null;
    } finally {
      db?.close();
    }
  }
}

String _schema(bool compressed) =>
    '''
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE category (
  id INTEGER PRIMARY KEY, parentId INTEGER, title TEXT NOT NULL,
  level INTEGER NOT NULL DEFAULT 0, orderIndex INTEGER NOT NULL DEFAULT 999);
CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE);
CREATE TABLE generation (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE);
CREATE TABLE author (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE);
CREATE TABLE book (
  id INTEGER PRIMARY KEY, categoryId INTEGER NOT NULL, sourceId INTEGER NOT NULL,
  title TEXT NOT NULL, heShortDesc TEXT, orderIndex INTEGER NOT NULL DEFAULT 999,
  totalLines INTEGER NOT NULL DEFAULT 0, isBaseBook INTEGER NOT NULL DEFAULT 0,
  hasSourceConnection INTEGER NOT NULL DEFAULT 0, hasAltStructures INTEGER NOT NULL DEFAULT 0,
  fileType TEXT DEFAULT 'txt');
CREATE TABLE book_author (bookId INTEGER NOT NULL, authorId INTEGER NOT NULL, PRIMARY KEY (bookId, authorId));
CREATE TABLE book_generation (bookId INTEGER NOT NULL, generationId INTEGER NOT NULL, PRIMARY KEY (bookId, generationId));
CREATE TABLE line (
  id INTEGER PRIMARY KEY, bookId INTEGER NOT NULL, lineIndex INTEGER NOT NULL,
  ${compressed ? '' : 'content TEXT NOT NULL, '}heRef TEXT, tocEntryId INTEGER);
CREATE INDEX idx_line_book_index ON line(bookId, lineIndex);
${compressed ? '''CREATE TABLE line_content (id INTEGER PRIMARY KEY NOT NULL, content BLOB NOT NULL);
CREATE TABLE zstd_dict (id INTEGER PRIMARY KEY NOT NULL, dict BLOB NOT NULL);''' : ''}
CREATE TABLE tocText (id INTEGER PRIMARY KEY, text TEXT NOT NULL UNIQUE);
CREATE TABLE tocEntry (
  id INTEGER PRIMARY KEY, bookId INTEGER NOT NULL, parentId INTEGER, textId INTEGER NOT NULL,
  level INTEGER NOT NULL, lineId INTEGER, isLastChild INTEGER NOT NULL DEFAULT 0,
  hasChildren INTEGER NOT NULL DEFAULT 0);
CREATE INDEX idx_toc_book ON tocEntry(bookId);
CREATE TABLE line_toc (lineId INTEGER PRIMARY KEY, tocEntryId INTEGER NOT NULL);
CREATE TABLE connection_type (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE);
CREATE TABLE external_link (
  sourceBookId INTEGER NOT NULL, sourceLineIndex INTEGER NOT NULL,
  targetSource TEXT, targetTitle TEXT NOT NULL, targetRef TEXT,
  targetLineIndex INTEGER, connectionType TEXT);
CREATE INDEX idx_external_link_source ON external_link(sourceBookId, sourceLineIndex);
''';

/// תווית ({פרשת בראשית}), כותרת או שורה ריקה: לא מקשרים אותן.
final _label = RegExp(r'^\s*(\{[^}]*\}|<h[1-6][^>]*>.*</h[1-6]>)?\s*$');
final _dafLoc = RegExp(r'^\S+[.:]$');
final _squashRe = RegExp(r'\s+');
String _squash(String t) => t.replaceAll(_squashRe, '');

/// דורות.csv: שם ספר -> שורה (שם כפול עם קטגוריה: ברירת מחדל לשורה בלי קטגוריה).
Map<String, Map<String, String>> loadDorot(String linksDir) {
  final f = File(p.join(linksDir, 'דורות.csv'));
  final rows = <String, Map<String, String>>{};
  if (!f.existsSync()) return rows;
  for (final r in readCsvDicts(f.path)) {
    final name = r['ספר'] ?? '';
    if (name.isEmpty) continue;
    if (!rows.containsKey(name) || (r['קטגוריה'] ?? '').isEmpty) rows[name] = r;
  }
  return rows;
}

/// מאגר קטן של שורות ספרים שנקראו (לבדיקת תוכן שורות בקישורים, בלי להחזיק את כל הספרייה בזיכרון).
class _LineCache {
  _LineCache(this.paths);
  final Map<String, String> paths;
  final _cache = <String, List<String>>{};

  List<String>? of(String title) {
    final hit = _cache.remove(title);
    if (hit != null) return _cache[title] = hit;
    final path = paths[title];
    if (path == null) return null;
    final lines = readBookLines(path, dropTrailingEmpty: true);
    if (_cache.length >= 4) _cache.remove(_cache.keys.first);
    return _cache[title] = lines;
  }
}

/// בונה את המסד. רץ באופן סינכרוני (מיועד ל-isolate נפרד).
BuildResult buildLibrary(BuildOptions o, {ProgressFn? progress, void Function()? checkCancel}) {
  void say(String t, [String d = '', double? f]) => progress?.call(t, d, f);
  void cancelPoint() => checkCancel?.call();
  final stats = <String, int>{};
  void inc(String k, [int n = 1]) => stats[k] = (stats[k] ?? 0) + n;
  final warnings = <String>[];

  final root = p.normalize(o.booksDir);
  if (!Directory(root).existsSync()) throw BuildError('תיקיית הספרים לא נמצאה: $root');
  final linksDir = p.join(root, linksDirName);

  say('סורק את תיקיית הספרים');
  final files = scanBooks(root);
  if (files.isEmpty) {
    throw BuildError(
      'לא נמצאו ספרי TXT בתוך תיקיות. הספרים צריכים להיות בתיקייה (קטגוריה), ולא ישירות בתיקייה הראשית.',
    );
  }

  // בנייה קודמת: מזהים יציבים וגרסה
  final prev = PreviousDb.read(o.outPath);
  final samePrev = prev != null && prev.libraryId == o.libraryId;
  if (prev != null && !samePrev) {
    warnings.add('קובץ הפלט הקיים שייך לספרייה אחרת (${prev.libraryId}); הוא יוחלף, והגרסה מתחילה מ-1.');
  }
  final version = samePrev ? prev.version + 1 : 1;

  SeforimDb? official;
  if (o.officialDb != null && o.officialDb!.isNotEmpty) {
    final err = SeforimDb.validate(o.officialDb!);
    if (err != null) throw BuildError('הספרייה הרשמית (seforim.db): $err');
    official = SeforimDb(o.officialDb!);
  }

  final tmp = '${o.outPath}.part';
  Database? db;
  ZstdLineEncoder? encoder;
  try {
    // ── קישורים אוטומטיים ──
    var reports = <BookLinkReport>[];
    final existing = existingLinkStems(linksDir);
    if (official != null && o.autoLinks) {
      say('יוצר קישורים אוטומטיים', '', 0);
      reports = analyzeLinks(
        books: files,
        db: official,
        existing: existing,
        overrides: o.overrides,
        onProgress: (d, t, s) => say('יוצר קישורים אוטומטיים', s, t == 0 ? null : d / t),
        checkCancel: cancelPoint,
      );
    }

    // ── דחיסה ──
    var textBytes = 0;
    for (final f in files) {
      textBytes += File(f.path).lengthSync();
    }
    final dict = o.compress && official != null && (o.forceCompress || textBytes >= compressThresholdBytes)
        ? official.lineDictionary()
        : null;
    final compressed = dict != null;
    if (compressed) encoder = ZstdLineEncoder(dict.$2);

    // ── המסד ──
    for (final f in [tmp, '$tmp-journal']) {
      if (File(f).existsSync()) File(f).deleteSync();
    }
    File(tmp).parent.createSync(recursive: true);
    db = sqlite3.open(tmp);
    db.execute('PRAGMA journal_mode=OFF');
    db.execute('PRAGMA synchronous=OFF');
    db.execute(_schema(compressed));
    db.execute('BEGIN');
    final meta = {
      'library_id': o.libraryId,
      'db_version': '$version',
      'display_name': o.displayName,
      'library_name': o.displayName, // המפתח שאוצריא קוראת בפועל
      'description': 'ספרים מותאמים לאוצריא, עם קישורים לספרייה הרשמית',
      'author': o.author,
    };
    final insMeta = db.prepare('INSERT INTO schema_meta VALUES (?,?)');
    meta.forEach((k, v) => insMeta.execute([k, v]));
    insMeta.close();
    db.execute('INSERT INTO source(id,name) VALUES (1,?)', [o.displayName.isEmpty ? 'MyLibrary' : o.displayName]);
    db.execute("INSERT INTO connection_type(name) VALUES ('SOURCE')");
    if (compressed) db.execute('INSERT INTO zstd_dict VALUES (?,?)', [dict.$1, dict.$2]);

    final dorot = loadDorot(linksDir);
    final catIds = _Ids(samePrev ? prev.category : null);
    final bookAlloc = _Ids(samePrev ? prev.book : null);
    final tocTextIds = _Ids(samePrev ? prev.tocText : null);
    final genIds = _Ids(samePrev ? prev.generation : null);
    final authIds = _Ids(samePrev ? prev.author : null);
    final cats = <String, int>{}, gens = <String, int>{}, auths = <String, int>{};

    final insCat = db.prepare('INSERT INTO category(id,parentId,title,level,orderIndex) VALUES (?,?,?,?,?)');
    int catId(List<String> parts) {
      int? parent;
      for (var i = 0; i < parts.length; i++) {
        final k = parts.sublist(0, i + 1).join('\u0000');
        var id = cats[k];
        if (id == null) {
          id = cats[k] = catIds.get(k);
          insCat.execute([id, parent, parts[i], i, cats.length]);
        }
        parent = id;
      }
      return parent!;
    }

    int lookup(String table, Map<String, int> d, _Ids alloc, String name) {
      var id = d[name];
      if (id == null) {
        id = d[name] = alloc.get(name);
        db!.execute('INSERT INTO $table(id,name) VALUES (?,?)', [id, name]);
      }
      return id;
    }

    final insBook = db.prepare(
      'INSERT INTO book(id,categoryId,sourceId,title,orderIndex,totalLines) VALUES (?,?,?,?,?,?)',
    );
    final insLine = compressed
        ? db.prepare('INSERT INTO line(id,bookId,lineIndex,tocEntryId) VALUES (?,?,?,?)')
        : db.prepare('INSERT INTO line(id,bookId,lineIndex,content,tocEntryId) VALUES (?,?,?,?,?)');
    final insContent = compressed ? db.prepare('INSERT INTO line_content VALUES (?,?)') : null;
    final insToc = db.prepare('INSERT INTO tocEntry(id,bookId,parentId,textId,level,lineId) VALUES (?,?,?,?,?,?)');
    final insTocText = db.prepare('INSERT INTO tocText(id,text) VALUES (?,?)');
    final insLineToc = db.prepare('INSERT INTO line_toc VALUES (?,?)');
    final insBookGen = db.prepare('INSERT OR IGNORE INTO book_generation VALUES (?,?)');
    final insBookAuth = db.prepare('INSERT OR IGNORE INTO book_author VALUES (?,?)');

    final bookIds = <String, int>{};
    final bookPaths = <String, String>{};
    final tocWritten = <String>{};
    var totalLines = 0;
    for (var order = 1; order <= files.length; order++) {
      cancelPoint();
      final f = files[order - 1];
      final title = f.stem;
      say('בונה את המסד', title, order / files.length);
      final cid = catId(f.rel);
      final lines = readBookLines(f.path, dropTrailingEmpty: true);
      if (lines.length >= rowStride) throw BuildError('ספר ארוך מדי (מעל מיליון שורות): $title');
      // ספר בשם שכבר קיים (בתיקייה אחרת): מזהה חדש, והקישורים מתייחסים לראשון
      final dup = bookIds.containsKey(title);
      if (dup) {
        warnings.add('יש יותר מספר אחד בשם "$title"; הקישורים יתייחסו לראשון שבהם.');
      }
      final bid = bookAlloc.get(dup ? '$title\u0000${f.rel.join('/')}' : title);
      insBook.execute([bid, cid, 1, title, order, lines.length]);
      if (!dup) {
        bookIds[title] = bid;
        bookPaths[title] = f.path;
      }
      final d = dorot[title];
      if (d != null) {
        final gen = d['דור'] ?? '';
        final auth = d['מחבר'] ?? '';
        if (gen.isNotEmpty) insBookGen.execute([bid, lookup('generation', gens, genIds, gen)]);
        if (auth.isNotEmpty) insBookAuth.execute([bid, lookup('author', auths, authIds, auth)]);
      } else {
        inc('no_dorot');
      }

      final bookTocTexts = <String, int>{};
      final stack = <(int, int)>[]; // (entry id, level)
      final parents = <int>{};
      var entries = 0;
      int? curEntry;
      for (var i = 0; i < lines.length; i++) {
        final content = lines[i];
        final lid = bid * rowStride + i + 1;
        final m = headingToc.firstMatch(content);
        if (m != null) {
          final level = int.parse(m[1]!) - 1;
          var text = removeTags(m[2]!).trim();
          if (text.isEmpty) text = '-';
          var tid = bookTocTexts[text];
          if (tid == null) {
            tid = tocTextIds.get(text);
            if (tocWritten.add(text)) insTocText.execute([tid, text]);
            bookTocTexts[text] = tid;
          }
          while (stack.isNotEmpty && stack.last.$2 >= level) {
            stack.removeLast();
          }
          final parent = stack.isNotEmpty ? stack.last.$1 : null;
          if (parent != null) parents.add(parent);
          curEntry = bid * rowStride + ++entries;
          insToc.execute([curEntry, bid, parent, tid, level, lid]);
          stack.add((curEntry, level));
        }
        if (compressed) {
          insLine.execute([lid, bid, i, curEntry]);
          insContent!.execute([lid, encoder!.compressText(content)]);
        } else {
          insLine.execute([lid, bid, i, content, curEntry]);
        }
        if (curEntry != null) insLineToc.execute([lid, curEntry]);
      }
      for (final par in parents) {
        db.execute('UPDATE tocEntry SET hasChildren=1 WHERE id=?', [par]);
      }
      inc('books');
      totalLines += lines.length;
    }
    for (final s in [insCat, insBook, insLine, insToc, insTocText, insLineToc, insBookGen, insBookAuth]) {
      s.close();
    }
    insContent?.close();
    stats['lines'] = totalLines;

    // ── קישורים לספרייה הרשמית: נאספים, מתוקנים, ורק אז נכתבים ──
    final lineCache = _LineCache(bookPaths);
    final pending = <(String, String, String, String), List<(int, String, int)>>{};
    final seen = <(String, int, String)>{};

    void addLink(String src, String lineNo, String target, String loc, String kind) {
      if (!bookIds.containsKey(src)) return;
      inc('links_in_csv');
      final res = official?.resolve(target, loc);
      if (res == null) {
        inc('unresolved');
        return;
      }
      final (ref, li) = res;
      final line0 = (int.tryParse(lineNo.trim()) ?? 0) - 1;
      final lines = lineCache.of(src);
      if (lines == null || line0 < 0 || line0 >= lines.length || _label.hasMatch(lines[line0])) {
        inc('skipped_label'); // לא מקשרים תוויות כמו {פרשת בראשית}
        return;
      }
      if (!seen.add((src, line0, ref))) {
        inc('dup');
        return;
      }
      (pending[(src, target, loc, kind)] ??= []).add((line0, ref, li));
    }

    say('מקשר לספרייה הרשמית', '', null);
    for (final f in userLinkCsvFiles(linksDir)) {
      for (final r in readCsvDicts(f)) {
        addLink(r['ספר_מקור'] ?? '', r['מקור'] ?? '', r['ספר_יעד'] ?? '', r['מיקום_יעד'] ?? '', r['סוג'] ?? '');
      }
    }
    for (final rep in reports) {
      if (rep.status != LinkStatus.linked) continue;
      for (final r in rep.csvRows()) {
        addLink(r[1], r[0], r[3], r[4], r[5]);
      }
    }
    cancelPoint();

    // ד"ה -> שורה בגמרא: לפי סדר שורות המקור (הסמן שומר סדר בין פסקאות), רק ליעד 'מסכת + דף' בבבלי
    final dhMap = <(String, int, String, String), (String, int)>{};
    if (o.dhLines && official != null) {
      final matcher = DhMatcher(official);
      final work = <String, Set<(int, String, String)>>{};
      pending.forEach((key, items) {
        final (src, target, loc, _) = key;
        if (_dafLoc.hasMatch(loc) && matcher.g.isGemara(target)) {
          for (final (line0, _, _) in items) {
            (work[src] ??= {}).add((line0, target, loc));
          }
        }
      });
      var n = 0;
      for (final MapEntry(key: src, value: set) in work.entries) {
        cancelPoint();
        say('מתאים דיבור המתחיל לשורות הגמרא', src, work.isEmpty ? null : n++ / work.length);
        final lst = set.toList()
          ..sort((a, b) {
            if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
            final c = a.$2.compareTo(b.$2);
            return c != 0 ? c : a.$3.compareTo(b.$3);
          });
        final lines = lineCache.of(src)!;
        var cursor = 0;
        for (final (line0, target, loc) in lst) {
          final dh = extractDh(lines[line0]);
          if (dh == null || dh.isEmpty) {
            inc('dh_no_dh_stays_page');
            continue;
          }
          final hit = matcher.match(target, loc, dh, cursor);
          if (hit != null) {
            dhMap[(src, line0, target, loc)] = (hit.$1, hit.$2);
            cursor = hit.$2;
            inc('dh_to_line');
            inc('dh_${hit.$3}');
          } else {
            inc('dh_not_found_stays_page');
          }
        }
      }
    }

    say('כותב קישורים', '', null);
    final insExt = db.prepare('INSERT INTO external_link VALUES (?,?,?,?,?,?,?)');
    var officialLinks = 0;
    pending.forEach((key, items) {
      final (src, target, loc, kind) = key;
      items.sort((a, b) {
        if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
        final c = a.$2.compareTo(b.$2);
        return c != 0 ? c : a.$3.compareTo(b.$3);
      });
      // כתאב אלתאג' (מקרא): שורה אחת לפסוק, גם כשחלוקת הפסוקים בפרק שונה במעט מהרשמי
      final tajText = src.endsWith(" (כתאב אלתאג')") && !src.startsWith('תרגום');
      final verses = (kind == 'תרגום' || tajText) ? official?.verses(target, loc) : null;
      var list = items;
      if (verses != null && verses.isNotEmpty && verses.length == items.length) {
        // תרגום שורה-לפסוק: השורה ה-i מקושרת לפסוק ה-i
        list = [for (var i = 0; i < items.length; i++) (items[i].$1, verses[i].$1, verses[i].$2)];
        inc('verse_aligned', list.length);
      } else if (verses != null && verses.isNotEmpty && tajText) {
        list = [
          for (var i = 0; i < items.length; i++)
            (
              items[i].$1,
              verses[i < verses.length ? i : verses.length - 1].$1,
              verses[i < verses.length ? i : verses.length - 1].$2,
            ),
        ];
        inc('verse_aligned_clamped', list.length);
      }
      for (var (line0, ref, li) in list) {
        final hit = dhMap[(src, line0, target, loc)];
        if (hit != null) (ref, li) = hit;
        insExt.execute([bookIds[src], line0, 'official', target, ref, li, 'SOURCE']);
        officialLinks++;
      }
    });
    stats['links'] = officialLinks;

    // ── קישורים בין ספרי המסד עצמו (<ספר>_links.json) ──
    // מפרש (COMMENTARY): המפרש הוא המקור והבסיס הוא היעד. שאר הסוגים: ספר 1 מקור, ספר 2 יעד.
    final bySquashed = {for (final t in bookIds.keys) _squash(t): t};
    final jsonSeen = <(String, int, String, int, String)>{};
    var innerLinks = 0;
    for (final jf in _findJsonLinkFiles(root)) {
      final name = p.basename(jf);
      final baseTitle = bySquashed[_squash(name.substring(0, name.length - '_links.json'.length))];
      if (baseTitle == null) continue;
      final Object? entries;
      try {
        entries = jsonDecode(utf8.decode(File(jf).readAsBytesSync(), allowMalformed: true));
      } on FormatException {
        warnings.add('קובץ קישורים לא תקין (JSON): $name');
        continue;
      }
      if (entries is! List) continue; // למשל מילון טווחי תווים, לא קישורי ספרים
      for (final e in entries) {
        if (e is! Map || !e.containsKey('path_2')) continue;
        final p2 = '${e['path_2']}'.split(RegExp(r'[\\/]')).last;
        final other = bySquashed[_squash(p.basenameWithoutExtension(p2))];
        if (other == null) {
          inc('json_missing_book');
          continue;
        }
        final l1 = (int.tryParse('${e['line_index_1']}') ?? 0) - 1;
        final l2 = (int.tryParse('${e['line_index_2']}') ?? 0) - 1;
        if (l1 < 0 || l2 < 0) {
          inc('json_dup_or_bad');
          continue;
        }
        var kind = '${e['Conection Type'] ?? e['Connection Type'] ?? ''}'.trim().toUpperCase();
        if (kind.isEmpty) kind = 'OTHER';
        final commentary = kind == 'COMMENTARY';
        final src = commentary ? other : baseTitle;
        final sl = commentary ? l2 : l1;
        final tgt = commentary ? baseTitle : other;
        final tl = commentary ? l1 : l2;
        if (commentary) kind = 'SOURCE';
        if (!jsonSeen.add((src, sl, tgt, tl, kind))) {
          inc('json_dup_or_bad');
          continue;
        }
        insExt.execute([bookIds[src], sl, o.libraryId, tgt, null, tl, kind]);
        innerLinks++;
      }
    }
    insExt.close();
    stats['json_links'] = innerLinks;
    db.execute('UPDATE book SET hasSourceConnection=1 WHERE id IN (SELECT DISTINCT sourceBookId FROM external_link)');
    db.execute('COMMIT');
    cancelPoint();

    say('מסיים ומכווץ את הקובץ', '', null);
    db.execute('VACUUM');
    final ok = db.select('PRAGMA integrity_check').first.values.first;
    db.close();
    db = null;
    if (ok != 'ok') throw BuildError('בדיקת תקינות המסד נכשלה: $ok');

    final out = File(o.outPath);
    if (out.existsSync()) out.deleteSync();
    File(tmp).renameSync(o.outPath);

    return BuildResult(
      outPath: o.outPath,
      version: version,
      books: files.length,
      lines: totalLines,
      categories: cats.length,
      officialLinks: officialLinks,
      innerLinks: innerLinks,
      sizeBytes: File(o.outPath).lengthSync(),
      compressed: compressed,
      stableFromPrevious: samePrev,
      reports: reports,
      stats: stats,
      warnings: warnings,
    );
  } finally {
    encoder?.close();
    db?.close();
    official?.close();
    final t = File(tmp);
    if (t.existsSync()) {
      try {
        t.deleteSync();
      } catch (_) {}
    }
  }
}

/// כל קבצי *_links.json בתיקיית הספרים (בלי תיקיות נסתרות).
List<String> _findJsonLinkFiles(String root) {
  final out = <String>[];
  void walk(Directory d) {
    final List<FileSystemEntity> entries;
    try {
      entries = d.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final e in entries) {
      final name = p.basename(e.path);
      if (e is Directory) {
        if (!name.startsWith('.')) walk(e);
      } else if (e is File && name.endsWith('_links.json')) {
        out.add(e.path);
      }
    }
  }

  walk(Directory(root));
  return out..sort();
}

/// מזהה ספרייה חדש (אותיות קטנות, ספרות ומקף, כפי שאוצריא דורשת).
String newLibraryId() {
  final r = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  return 'mylib-$r';
}

/// גודל קובץ קריא.
String formatBytes(int b) {
  if (b < 1024) return '$b בתים';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)}KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)}MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)}GB';
}
