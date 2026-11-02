// סכמה 7 של אוצריא: book.contentHash, line.charCount, ומבנה המסד שהמנוע כותב.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_library_offline/src/engine/builder.dart';
import 'package:my_library_offline/src/engine/common.dart';
import 'package:my_library_offline/src/engine/content_hash.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('bookContentHash (BookContentHash.kt)', () {
    // הערכים חושבו בנפרד במימוש Python של BookContentHash.kt (hashlib.sha256 על התג, ולכל שורה
    // b'L' + struct.pack('>q', lineIndex) + struct.pack('>i', len(utf8)) + utf8; 8 הבתים הראשונים
    // כ-'>q'; 0 -> 1). המימוש הזה אומת מול contentHash ששמור ב-seforim.db רשמי (db_version 36,
    // סכמה 7): 40 ספרים ראשונים בלי line_note, 0 אי-התאמות.
    test('ספר ריק: התג בלבד', () {
      expect(bookContentHash(const []), 6680358728597189694);
    });
    test('שורה אחת', () {
      expect(bookContentHash(const ['a']), -5962971294534080742);
    });
    test('עברית, שורה ריקה, תגיות וישויות', () {
      expect(
        bookContentHash(const ['<h1>ספר בדיקה</h1>', 'שורה ראשונה', '', 'abc &amp; <b>def</b>']),
        -7393328176948616796,
      );
    });
    test('חישוב מצטבר זהה לחישוב על הרשימה', () {
      final h = BookContentHasher()
        ..addLine(0, '<h1>ספר בדיקה</h1>')
        ..addLine(1, 'שורה ראשונה')
        ..addLine(2, '')
        ..addLine(3, 'abc &amp; <b>def</b>');
      expect(h.close(), -7393328176948616796);
    });
  });

  test('countVisibleChars (HtmlCharCounter.kt)', () {
    expect(countVisibleChars(''), 0);
    expect(countVisibleChars('<h1>ספר</h1>'), 3);
    expect(countVisibleChars('a &amp; b'), 5);
    expect(countVisibleChars('a & b c d e f g'), 15); // & בלי ; בטווח 10 תווים נספר כתו
    expect(countVisibleChars('<b>x</b>&nbsp;'), 2);
  });

  test('בנייה: מסד בסכמה 7', () {
    final tmp = Directory.systemTemp.createTempSync('schema7_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final books = Directory(p.join(tmp.path, 'books', 'קטגוריה'))..createSync(recursive: true);
    final lines = ['<h1>ספר א</h1>', '<h2>פרק א</h2>', 'שורה &amp; <b>מודגשת</b>', 'שורה שנייה'];
    File(p.join(books.path, 'ספר א.txt')).writeAsStringSync('${lines.join('\n')}\n');
    File(p.join(books.path, 'פירוש על ספר א.txt')).writeAsStringSync('<h1>פירוש</h1>\nפירוש לשורה\n');
    final out = p.join(tmp.path, 'out.db');

    final r = buildLibrary(
      BuildOptions(booksDir: p.join(tmp.path, 'books'), outPath: out, libraryId: 'mylib-test', displayName: 'בדיקה'),
    );
    expect(r.compressed, isFalse);

    final db = sqlite3.open(out, mode: OpenMode.readOnly);
    addTearDown(db.close);
    Set<String> cols(String t) => {for (final c in db.select("SELECT name FROM pragma_table_info('$t')")) c['name'] as String};
    final tables = {for (final r in db.select("SELECT name FROM sqlite_master WHERE type='table'")) r['name'] as String};

    expect(
      tables,
      containsAll([
        'line_content', 'line_ref', 'line_dh', 'book_version', 'version_line', //
        'banner', 'book_banner', 'book_protection', 'line_divine_name', 'line_note', 'line_note_divine_name',
      ]),
    );
    expect(tables, isNot(contains('zstd_dict')));
    expect(cols('line'), isNot(contains('content')));
    expect(cols('line'), contains('charCount'));
    expect(cols('line_dh'), contains('dhDisplay'));
    final meta = {for (final r in db.select('SELECT key, value FROM schema_meta')) r['key']: r['value']};
    expect(meta['db_schema_version'], '7');
    expect(meta['db_version'], '1');

    // book.contentHash כפי ש-BookContentHash.hasColumn דורש
    expect(
      db.select(
        "SELECT 1 FROM pragma_table_info('book') WHERE name='contentHash' AND upper(type)='INTEGER' "
        "AND \"notnull\"=1 AND dflt_value='0'",
      ),
      hasLength(1),
    );
    // version_line.content מותר ב-NULL (סכמה 6 ומעלה)
    expect(db.select("SELECT \"notnull\" FROM pragma_table_info('version_line') WHERE name='content'").single['notnull'], 0);

    final book = db.select("SELECT id, contentHash FROM book WHERE title='ספר א'").single;
    expect(book['contentHash'], bookContentHash(lines));
    final rows = db.select(
      'SELECT l.lineIndex, l.charCount, typeof(lc.content) AS t, lc.content FROM line l '
      'JOIN line_content lc ON lc.id = l.id WHERE l.bookId = ? ORDER BY l.lineIndex',
      [book['id']],
    );
    expect([for (final r in rows) r['content']], lines);
    expect([for (final r in rows) r['t']], everyElement('text'));
    expect([for (final r in rows) r['charCount']], [5, 5, 13, 10]);
    expect(db.select('SELECT COUNT(*) AS n FROM line').single['n'], db.select('SELECT COUNT(*) AS n FROM line_content').single['n']);
    expect(db.select('SELECT COUNT(*) AS n FROM book WHERE contentHash = 0').single['n'], 0);
  });
}
