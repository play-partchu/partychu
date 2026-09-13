// 회원 관리 '나이' 칸 표기 — `91년생 · 36세`.
//
// 나이는 DB에 저장하지 않는다. 본인확인이 저장한 birthYear 하나로 화면에서
// 계산하므로, 해가 바뀌면 저절로 한 살이 오른다 — 그 성질까지 여기서 잡는다.
//
// 예전 표기(`36세 (2)`)에 붙던 숫자는 주민등록번호 뒷자리 첫 숫자였다. 다시
// 들어오지 않도록 "괄호가 없다"도 함께 확인한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:partychu_admin/screens/members_screen.dart';

void main() {
  // 요청에 적힌 예시 그대로 — 2026년 기준.
  final now2026 = DateTime(2026, 1, 1);

  group('2026년 기준 표기', () {
    test('1991년생 → 91년생 · 36세', () {
      expect(memberAgeLabel(1991, now: now2026), '91년생 · 36세');
    });

    test('1998년생 → 98년생 · 29세', () {
      expect(memberAgeLabel(1998, now: now2026), '98년생 · 29세');
    });

    // 2000년대생은 두 자리로 0을 채운다 — '4년생'이 되면 안 된다.
    test('2004년생 → 04년생 · 23세', () {
      expect(memberAgeLabel(2004, now: now2026), '04년생 · 23세');
    });

    test('2000년생 → 00년생 · 27세', () {
      expect(memberAgeLabel(2000, now: now2026), '00년생 · 27세');
    });
  });

  test('본인확인 전이라 생년 데이터가 없으면 - 로 남는다', () {
    expect(memberAgeLabel(null, now: now2026), '-');
  });

  // 나이를 저장하지 않는 이유가 이것이다 — 같은 회원이 해가 바뀌면 한 살
  // 많아져야 하고, 그 일이 저절로 일어나야 한다.
  test('해가 바뀌면 같은 생년의 나이가 한 살 오른다', () {
    expect(memberAgeLabel(1991, now: DateTime(2026, 12, 31)), '91년생 · 36세');
    expect(memberAgeLabel(1991, now: DateTime(2027, 1, 1)), '91년생 · 37세');
  });

  // 생일이 지났는지는 보지 않는다(한국 나이) — 연초든 연말이든 같은 값이다.
  test('같은 해 안에서는 날짜가 달라도 값이 같다', () {
    final janFirst = memberAgeLabel(1998, now: DateTime(2026, 1, 1));
    final decLast = memberAgeLabel(1998, now: DateTime(2026, 12, 31));
    expect(janFirst, decLast);
  });

  test('주민등록번호 뒷자리 숫자였던 괄호는 더 이상 붙지 않는다', () {
    for (final year in [1991, 1998, 2000, 2004]) {
      final label = memberAgeLabel(year, now: now2026);
      expect(label.contains('('), isFalse, reason: label);
      expect(label.contains(')'), isFalse, reason: label);
    }
  });

  // 생년월일 칸 — 본인확인(NICE)이 저장한 값만 쓴다.
  group('생년월일 표기', () {
    test('연·월·일이 다 있으면 1991.03.15', () {
      expect(memberBirthDateLabel(1991, 3, 15), '1991.03.15');
    });

    test('월·일이 없는 옛 기록은 연도만', () {
      expect(memberBirthDateLabel(1991, null, null), '1991');
    });

    test('본인확인 전이라 연도가 없으면 -', () {
      expect(memberBirthDateLabel(null, 3, 15), '-');
    });

    // 한 줄로 붙여 보면 화면에 실제로 나가는 두 줄이 된다.
    test('요청 예시: 1991.03.15 / 91년생 · 36세', () {
      expect(memberBirthDateLabel(1991, 3, 15), '1991.03.15');
      expect(memberAgeLabel(1991, now: DateTime(2026, 1, 1)), '91년생 · 36세');
    });
  });
}
