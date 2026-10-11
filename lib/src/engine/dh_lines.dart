// התאמת דיבור מתחיל (ד"ה) בפירוש על הש"ס לשורת הגמרא המדויקת ב-seforim.db: תרגום של dh_lines.py.
//
// heRef ברמת שורה: 'ברכות, ב., ד' = עמוד ב. שורה ד. טקסט השורה ב-line_content (zstd עם מילון).

import 'seforim_db.dart';

final _nikud = RegExp('[\u0591-\u05C7]');
final _tag = RegExp(r'<[^>]*>');
final _quotes = RegExp('[\\"\'׳״“”‘’`]');
final _punct = RegExp(r'[^א-ת\s]');
final _boldStart = RegExp(r'^\s*(?:<[^>]+>\s*)*?<b>(.*?)</b>');
final _ws = RegExp(r'\s+');

/// קיצורי גמרא נפוצים בד"ה: מורחבים בשני הצדדים לפני ההשוואה.
const abbr = {
  'אר': 'אמר רבי', 'תר': 'תנו רבנן', 'שמ': 'שמע מינה', 'מט': 'מאי טעמא', 'הק': 'הכי קאמר', //
  'סד': 'סלקא דעתך', 'אעג': 'אף על גב', 'אעפ': 'אף על פי', 'כש': 'כל שכן', 'תש': 'תא שמע', //
  'תק': 'תנא קמא', 'אאכ': 'אלא אם כן', 'אכ': 'אם כן', 'וכ': 'וכן', 'עכ': 'על כן', 'מנל': 'מנא לן', //
  'ר': 'רבי', 'רא': 'רבי אליעזר', 'רע': 'רבי עקיבא', 'רש': 'רבי שמעון', 'רמ': 'רבי מאיר', //
  'בש': 'בית שמאי', 'בה': 'בית הלל',
};

/// מילים שאינן מאפיינות: סוף ד"ה ('וכו'').
const _cut = {'וכו', 'וכולי', 'כולי', 'כו', 'וגו', 'וגומר', 'ועוד', 'עכ'};

/// סימוני פתיחה שאינם חלק מטקסט הגמרא.
const _lead = {'מתני', 'מתניתין', 'גמ', 'גמרא', 'בגמרא', 'הג', 'בא', 'שם', 'במשנה', 'משנה'};

/// מילים מנורמלות: בלי תגים, ניקוד, גרשיים וסימני פיסוק; מקף = רווח; קיצורים מורחבים.
List<String> words(String? text) {
  var t = (text ?? '').replaceAll(_tag, ' ');
  t = t.replaceAll(_nikud, '').replaceAll('־', ' ').replaceAll('—', ' ').replaceAll('-', ' ').replaceAll('׃', ' ');
  final out = <String>[];
  for (final raw in t.split(_ws)) {
    if (raw.isEmpty) continue;
    final hasQ = _quotes.hasMatch(raw);
    final w = raw.replaceAll(_quotes, '').replaceAll(_punct, '');
    if (w.isEmpty) continue;
    final a = abbr[w];
    if (a != null && (hasQ || w == 'ר') && w.length <= 3) {
      out.addAll(a.split(' '));
    } else {
      out.add(w);
    }
  }
  return out;
}

final _skeletonCache = <String, String>{};

String skeleton(String w) => _skeletonCache[w] ??= () {
  final s = w
      .replaceAll('ו', '')
      .replaceAll('י', '')
      .replaceAll('ך', 'כ')
      .replaceAll('ם', 'מ')
      .replaceAll('ן', 'נ')
      .replaceAll('ף', 'פ')
      .replaceAll('ץ', 'צ');
  return s.isEmpty ? w : s;
}();

const _prefixes = 'ודהבלמכש';

/// שוויון מילים סביל: שלד (כתיב מלא/חסר), הבדל בקידומת אחת, או טעות אות אחת במילה ארוכה.
bool same(String a, String b) {
  if (a == b) return true;
  final sa = skeleton(a), sb = skeleton(b);
  if (sa == sb) return true;
  if (sa.length > 3 && sb.length > 3) {
    if (_prefixes.contains(sa[0]) && sa.substring(1) == sb) return true;
    if (_prefixes.contains(sb[0]) && sb.substring(1) == sa) return true;
    if (sa.length == sb.length && sa.length >= 5) {
      var diff = 0;
      for (var i = 0; i < sa.length && diff <= 1; i++) {
        if (sa[i] != sb[i]) diff++;
      }
      if (diff <= 1) return true;
    }
  }
  return false;
}

/// ד"ה מודגש בתחילת שורת פירוש: רשימת מילים מנורמלות, או null.
List<String>? extractDh(String? content) {
  final m = _boldStart.firstMatch(content ?? '');
  if (m == null) return null;
  final raw = m[1]!;
  if (raw.length > 160) return null;
  final ws = words(raw);
  if (ws.isEmpty || ws.length > 12) return null;
  return cleanDh(ws);
}

List<String> cleanDh(List<String> input) {
  var ws = List<String>.of(input);
  for (var i = 0; i < ws.length; i++) {
    if (_cut.contains(ws[i]) && i > 0) return ws.sublist(0, i);
  }
  while (ws.isNotEmpty && _cut.contains(ws.last)) {
    ws.removeLast();
  }
  return ws;
}

/// הד"ה כמות שהוא, ובלי סימון פתיחה ('גמרא', 'מתני'').
List<List<String>> dhVariants(List<String> ws) => [ws, if (ws.length > 1 && _lead.contains(ws.first)) ws.sublist(1)];

/// (k, chars): כמה מילות ד"ה (מהתחלה) תואמות ברצף בשורה; ממשיך לשורה הבאה אם הד"ה גולש.
(int, int) matchInLine(List<String> dh, List<String> toks, List<String> nxt) {
  var bestK = 0, bestChars = 0;
  final n = dh.length;
  for (var p = 0; p < toks.length; p++) {
    var k = 0, chars = 0;
    final seqLen = toks.length - p + nxt.length;
    while (k < n && k < seqLen) {
      final idx = p + k;
      final tok = idx < toks.length ? toks[idx] : nxt[idx - toks.length];
      if (!same(dh[k], tok)) break;
      chars += dh[k].length;
      k++;
    }
    if (k > bestK || (k == bestK && chars > bestChars)) {
      bestK = k;
      bestChars = chars;
    }
  }
  return (bestK, bestChars);
}

/// אורך תת-סדרה משותפת (לפי הסדר, עם דילוגים) בין הד"ה לטקסט, ומספר התווים המותאמים.
(int, int) lcsInLine(List<String> dh, List<String> toks) {
  final n = dh.length, m = toks.length;
  if (n == 0 || m == 0) return (0, 0);
  final l = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  final c = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < m; j++) {
      if (same(dh[i], toks[j])) {
        l[i + 1][j + 1] = l[i][j] + 1;
        c[i + 1][j + 1] = c[i][j] + dh[i].length;
      } else if (l[i][j + 1] >= l[i + 1][j]) {
        l[i + 1][j + 1] = l[i][j + 1];
        c[i + 1][j + 1] = c[i][j + 1];
      } else {
        l[i + 1][j + 1] = l[i + 1][j];
        c[i + 1][j + 1] = c[i + 1][j];
      }
    }
  }
  return (l[n][m], c[n][m]);
}

/// שורת גמרא: (lineIndex, heRef, מילים).
typedef GLine = (int, String, List<String>);

/// קורא שורות גמרא מ-seforim.db: מסכת -> עמודים (לפי heRef) -> שורות.
class GemaraText {
  GemaraText(this.db);
  final SeforimDb db;
  final _cache = <String, (Map<String, List<GLine>>, List<String>)?>{};
  bool? _split;

  bool isGemara(String title) => masechet(title) != null;

  (Map<String, List<GLine>>, List<String>)? masechet(String title) {
    if (_cache.containsKey(title)) return _cache[title];
    (Map<String, List<GLine>>, List<String>)? res;
    final rows = db.db.select('SELECT b.id FROM book b JOIN category c ON c.id=b.categoryId WHERE b.title=?', [title]);
    if (rows.length == 1) {
      final bid = rows.first['id'] as int;
      final top =
          db.db.select(
                'WITH RECURSIVE up(id,parentId,title) AS (SELECT c.id,c.parentId,c.title FROM book b '
                'JOIN category c ON c.id=b.categoryId WHERE b.id=? UNION ALL SELECT c.id,c.parentId,c.title '
                "FROM category c JOIN up ON c.id=up.parentId) SELECT group_concat(title,'/') AS t FROM up",
                [bid],
              ).first['t']
              as String?;
      final parts = top?.split('/') ?? const <String>[];
      // טקסט הבסיס: תלמוד בבלי > סדר X > מסכת (ולא תלמוד בבלי > ראשונים/אחרונים)
      if (parts.contains('תלמוד בבלי') && parts.any((s) => s.startsWith('סדר '))) {
        _split ??= db.hasTable('line_content');
        final q = _split!
            ? 'SELECT l.lineIndex, l.heRef, lc.content FROM line l JOIN line_content lc ON lc.id=l.id '
                  'WHERE l.bookId=? AND l.heRef IS NOT NULL ORDER BY l.lineIndex'
            : 'SELECT lineIndex, heRef, content FROM line WHERE bookId=? AND heRef IS NOT NULL ORDER BY lineIndex';
        final pages = <String, List<GLine>>{};
        final order = <String>[];
        final dec = db.decoder;
        for (final r in db.db.select(q, [bid])) {
          final he = r['heRef'] as String;
          final i = he.lastIndexOf(', ');
          if (i < 0) continue;
          final pre = he.substring(0, i);
          final list = pages[pre];
          if (list == null) {
            pages[pre] = [];
            order.add(pre);
          }
          pages[pre]!.add((r['lineIndex'] as int, he, words(dec.text(r['content']))));
        }
        if (pages.isNotEmpty) res = (pages, order);
      }
    }
    return _cache[title] = res;
  }

  /// שורות עמוד ('ב.' או 'ב:'), ובנוסף שורות העמוד הבא.
  (List<GLine>, List<GLine>)? pageLines(String title, String page) {
    final m = masechet(title);
    if (m == null) return null;
    final (pages, order) = m;
    final pre = '$title, $page';
    final cur = pages[pre];
    if (cur == null) return null;
    final i = order.indexOf(pre);
    return (cur, i + 1 < order.length ? pages[order[i + 1]]! : const <GLine>[]);
  }
}

/// מועמד: (lineIndex, heRef, סוג, k, chars). סוג: 2 = מלאה, 1 = חלקית, 0 = מטושטשת.
typedef _Cand = (int, String, int, int, int);

int _cmpTail(_Cand a, _Cand b) {
  if (a.$3 != b.$3) return a.$3.compareTo(b.$3);
  if (a.$4 != b.$4) return a.$4.compareTo(b.$4);
  return a.$5.compareTo(b.$5);
}

/// מקסימום לפי (k, chars, -lineIndex); הראשון בשוויון.
_Cand _best(List<_Cand> list) {
  var b = list.first;
  for (final c in list.skip(1)) {
    final cmp = c.$4 != b.$4 ? c.$4.compareTo(b.$4) : (c.$5 != b.$5 ? c.$5.compareTo(b.$5) : b.$1.compareTo(c.$1));
    if (cmp > 0) b = c;
  }
  return b;
}

class DhMatcher {
  DhMatcher(SeforimDb db) : g = GemaraText(db);
  final GemaraText g;

  List<_Cand> _cands(List<GLine> lines, List<List<String>> vars, {bool fuzzy = false, Set<int> skip = const {}}) {
    final out = <_Cand>[];
    for (var idx = 0; idx < lines.length; idx++) {
      final (li, he, toks) = lines[idx];
      if (fuzzy && skip.contains(li)) continue;
      final nxt = idx + 1 < lines.length ? lines[idx + 1].$3 : const <String>[];
      _Cand? best;
      for (final dh in vars) {
        final n = dh.length;
        if (n == 0) continue;
        _Cand? cand;
        final nn = nxt.length < n ? nxt : nxt.sublist(0, n);
        if (fuzzy) {
          if (n < 3) continue;
          final (lc, ch) = lcsInLine(dh, [...toks, ...nn]);
          if (lc >= 3 && lc * 4 >= n * 3 && ch >= 10) cand = (li, he, 0, lc, ch);
        } else {
          final (k, chars) = matchInLine(dh, toks, nn);
          if (k == n && chars >= 3) {
            cand = (li, he, 2, k, chars);
          } else if (k >= 2 && chars >= 8 && k * 2 >= n) {
            cand = (li, he, 1, k, chars);
          }
        }
        if (cand != null && (best == null || _cmpTail(cand, best) > 0)) best = cand;
      }
      if (best != null) out.add(best);
    }
    return out;
  }

  /// (heRef, lineIndex, סוג) של שורת הגמרא לד"ה בעמוד (או בבא אחריו), או null. [cursor] = שורה מינימלית.
  (String, int, String)? match(String title, String page, List<String> dh, int cursor) {
    if (dh.isEmpty) return null;
    final pl = g.pageLines(title, page);
    if (pl == null) return null;
    final (cur, nxt) = pl;
    final vars = dhVariants(dh);
    final cCur = _cands(cur, vars);
    for (final c in cCur) {
      if (c.$3 == 2 && c.$1 >= cursor) return (c.$2, c.$1, 'full');
    }
    final cNxt = nxt.isNotEmpty ? _cands(nxt.length > 60 ? nxt.sublist(0, 60) : nxt, vars) : const <_Cand>[];
    for (final c in cNxt) {
      if (c.$3 == 2 && c.$1 >= cursor) return (c.$2, c.$1, 'full_next');
    }
    final part = [
      for (final c in cCur)
        if (c.$3 == 1 && c.$1 >= cursor) c,
    ];
    if (part.isNotEmpty) {
      final b = _best(part);
      return (b.$2, b.$1, 'partial');
    }
    final fz = [
      for (final c in _cands(cur, vars, fuzzy: true, skip: {for (final c in cCur) c.$1}))
        if (c.$1 >= cursor) c,
    ];
    if (fz.isNotEmpty) {
      final b = _best(fz);
      return (b.$2, b.$1, 'fuzzy');
    }
    for (final c in [...cCur, ...cNxt]) {
      if (c.$3 == 2) return (c.$2, c.$1, 'reorder');
    }
    return null;
  }
}
