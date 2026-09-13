// 공휴일 표가 규칙대로 펼쳐지는지 눈으로 확인하는 일회성 스크립트.
// 실행: dart run tool/holiday_check.dart
import 'package:party_app/models/korean_holidays.dart';

void main() {
  const w = ['월', '화', '수', '목', '금', '토', '일'];
  for (final y in [2025, 2026, 2027, 2028]) {
    final list = KoreanHolidays.of(y).values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    print('== $y ==');
    for (final h in list) {
      print(
        '${h.date.toString().substring(0, 10)}'
        '(${w[h.date.weekday - 1]}) ${h.name}',
      );
    }
  }
}
