import 'package:flutter_test/flutter_test.dart';
import 'package:my_library_offline/src/engine/common.dart';

void main() {
  test('שמות ספרים: גרשיים וגרש אחידים כמו בספרייה הרשמית', () {
    expect(dbBookTitle('שו״ת הרשב״א'), 'שו"ת הרשב"א');
    expect(dbBookTitle('שו"ת הרשב"א'), 'שו"ת הרשב"א');
    expect(dbBookTitle('מהר׳׳ם'), "מהר''ם");
  });
  test('שמות קטגוריות: ״ כמו תנ״ך ברשמית', () {
    expect(dbCategoryTitle('תנ"ך'), 'תנ״ך');
    expect(dbCategoryTitle('תנ״ך'), 'תנ״ך');
  });
}
