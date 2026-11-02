// book.contentHash של סכמה 7 של אוצריא: חותם 64 סיביות של טקסט השורות של ספר, שלפיו אוצריא
// יודעת אילו ספרים לאנדקס מחדש בלי לקרוא אותם. העתק מדויק של BookContentHash.kt ב-SeforimLibrary
// (generator/common/.../db/BookContentHash.kt):
//
//   SHA-256 על: התג FORMAT_TAG, ואז לכל שורה לפי lineIndex: 'L', lineIndex (i64), אורך ה-UTF-8 (i32),
//   בתי ה-UTF-8 של הטקסט (הטקסט המפוענח, כך שדחיסה לא משנה את החותם); ואחריהן שורות line_note
//   (המסד האישי אינו כותב line_note, ולכן אין כאן חלק כזה). הכול big-endian.
//   הערך: 8 הבתים הראשונים של התקציר כ-i64 עם סימן, big-endian; 0 שמור ל"לא ידוע" והופך ל-1.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// תג הפורמט של החותם (זהה ל-BookContentHash.FORMAT_TAG).
const bookContentHashFormatTag = 'seforim-book-content-v1';

/// חותם התוכן של ספר ששורותיו [lines], כש-lineIndex של השורה ה-i הוא i.
int bookContentHash(List<String> lines) {
  final hasher = BookContentHasher();
  for (var i = 0; i < lines.length; i++) {
    hasher.addLine(i, lines[i]);
  }
  return hasher.close();
}

/// חישוב מצטבר: [addLine] לפי סדר lineIndex, ואז [close].
class BookContentHasher {
  BookContentHasher() {
    _in.add(utf8.encode(bookContentHashFormatTag));
  }

  final _digest = _DigestSink();
  late final ByteConversionSink _in = sha256.startChunkedConversion(_digest);
  final _header = ByteData(13);

  void addLine(int lineIndex, String text) {
    final bytes = utf8.encode(text);
    _header
      ..setUint8(0, 0x4C) // 'L'
      ..setInt64(1, lineIndex)
      ..setInt32(9, bytes.length);
    _in.add(_header.buffer.asUint8List());
    _in.add(bytes);
  }

  int close() {
    _in.close();
    final bytes = _digest.value!.bytes;
    var value = 0;
    for (var i = 0; i < 8; i++) {
      value = (value << 8) | bytes[i];
    }
    return value == 0 ? 1 : value;
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
