import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/place_area.dart';

/// 공간 평수([PlaceArea])의 약속을 고정한다.
///
/// 플레이스 등록/수정, 장소대여 등록/수정, 콤보 등록 두 갈래가 전부 이 모델
/// 하나를 부르므로, 여기가 맞으면 여섯 입구의 판정이 갈릴 수 없다.
///
/// 입력은 자유 타이핑이 아니라 **1평 단위 휠**이다
/// ([PlaceArea.optionAt] / `PlaceAreaPickerSheet`). 그래서 소수는 새로 고를 수
/// 없고, 옛 문서에 남은 소수는 **읽어서 그대로** 보여 준다.
void main() {
  group('검증 — 0 이하·문자·과대값은 저장되지 않는다', () {
    test('비어 있으면 요청 문구가 나온다', () {
      expect(PlaceArea.validate(''), PlaceArea.requiredMessage);
      expect(PlaceArea.validate('   '), PlaceArea.requiredMessage);
      expect(PlaceArea.validate(null), PlaceArea.requiredMessage);
    });

    test('문자는 통과하지 못한다', () {
      for (final bad in ['20평', 'abc', '2 0', '이십', '--3']) {
        expect(PlaceArea.isValid(bad), isFalse, reason: bad);
      }
    });

    test('0 이하는 통과하지 못한다', () {
      expect(PlaceArea.validate('0'), PlaceArea.tooSmallMessage);
      expect(PlaceArea.validate('0.0'), PlaceArea.tooSmallMessage);
      expect(PlaceArea.validate('-5'), PlaceArea.tooSmallMessage);
    });

    test('하한 미만 — 1평보다 작은 값은 고를 수 없다', () {
      expect(PlaceArea.validate('0.5'), PlaceArea.tooSmallMessage);
      expect(PlaceArea.isValid('1'), isTrue, reason: '하한 자체는 허용');
    });

    test('비정상적으로 큰 값은 통과하지 못한다', () {
      expect(PlaceArea.isValid('5000'), isTrue, reason: '상한 자체는 허용');
      expect(PlaceArea.validate('5000.1'), PlaceArea.tooLargeMessage);
      expect(PlaceArea.validate('999999'), PlaceArea.tooLargeMessage);
    });

    test('1평 단위가 아니면 조용히 반올림하지 않고 거절한다', () {
      expect(PlaceArea.validate('12.5'), PlaceArea.notWholeMessage);
      expect(PlaceArea.validate('20.05'), PlaceArea.notWholeMessage);
    });

    test('정상값은 통과한다', () {
      for (final ok in ['20', '20.0', '1', '5000', ' 33 ']) {
        expect(PlaceArea.validate(ok), isNull, reason: ok);
      }
    });
  });

  group('휠 — 1평부터 5,000평까지 모든 정수', () {
    test('칸 수와 양 끝 값', () {
      expect(PlaceArea.optionCount, 5000);
      expect(PlaceArea.optionAt(0), 1);
      expect(PlaceArea.optionAt(PlaceArea.optionCount - 1), 5000);
    });

    test('평수 → 칸, 칸 → 평수가 서로를 되돌린다', () {
      for (final pyeong in [1, 20, 137, 5000]) {
        expect(
          PlaceArea.optionAt(PlaceArea.indexOfPyeong(pyeong.toDouble())),
          pyeong,
          reason: '$pyeong',
        );
      }
    });

    test('범위 밖 값은 가장 가까운 칸에서 열린다 — 값이 잘리지는 않는다', () {
      expect(PlaceArea.indexOfPyeong(0), 0);
      expect(PlaceArea.indexOfPyeong(-3), 0);
      expect(PlaceArea.indexOfPyeong(99999), PlaceArea.optionCount - 1);
      // 옛 문서의 소수는 가까운 칸에 서고, 저장값 자체는 그대로 남는다.
      expect(PlaceArea.optionAt(PlaceArea.indexOfPyeong(12.5)), 13);
      expect(PlaceArea.of({PlaceArea.field: 12.5}), 12.5);
    });

    test('처음 여는 값은 고를 수 있는 값이다', () {
      expect(PlaceArea.isValid('${PlaceArea.defaultPyeong}'), isTrue);
    });
  });

  group('저장값 — 숫자 타입이고 문자열이 아니다', () {
    test('parse는 double을 돌려준다', () {
      expect(PlaceArea.parse('20'), 20.0);
      expect(PlaceArea.parse('5000'), 5000.0);
      expect(PlaceArea.parse('20'), isA<double>());
    });

    test('검증에 걸리는 입력은 parse도 null이다 — 저장 경로가 열리지 않는다', () {
      for (final bad in ['', '0', '-1', '20평', '12.5', '20000']) {
        expect(PlaceArea.parse(bad), isNull, reason: bad);
      }
    });
  });

  group('표기 — 단위는 읽는 쪽이 붙인다', () {
    test('정수는 소수점을 떼고 적는다', () {
      expect(PlaceArea.format(20), '20');
      expect(PlaceArea.labelOf({PlaceArea.field: 20.0}), '20평');
      expect(PlaceArea.displayOf({PlaceArea.field: 20.0}), '📐 20평');
    });

    test('네 자리부터 쉼표가 붙는다 — 저장용 문자열에는 붙지 않는다', () {
      expect(PlaceArea.labelOf({PlaceArea.field: 1250}), '1,250평');
      expect(PlaceArea.format(1250), '1250');
    });

    test('옛 문서의 소수는 첫째 자리까지 그대로 적는다', () {
      expect(PlaceArea.labelOf({PlaceArea.field: 12.5}), '12.5평');
    });

    test('int로 저장된 값도 그대로 읽는다', () {
      expect(PlaceArea.labelOf({PlaceArea.field: 20}), '20평');
    });

    test('㎡는 환산해서 보여만 주고 저장하지 않는다', () {
      expect(PlaceArea.summary(20), '20평 · 약 66.1㎡');
      expect(PlaceArea.summaryOf({PlaceArea.field: 1250}), startsWith('1,250평 · 약 '));
      expect(PlaceArea.summaryOf(const {'name': '옛 플레이스'}), isNull);
    });
  });

  group('하위호환 — 필드가 없던 옛 문서', () {
    test('필드가 없으면 null이라 상세 화면에서 줄이 통째로 빠진다', () {
      expect(PlaceArea.of(const {'name': '옛 플레이스'}), isNull);
      expect(PlaceArea.labelOf(const {'name': '옛 플레이스'}), isNull);
      expect(PlaceArea.displayOf(const {'name': '옛 플레이스'}), isNull);
    });

    test('수정 화면은 빈 칸으로 열려 이번 저장에서 채워진다', () {
      expect(PlaceArea.textOf(const {'name': '옛 플레이스'}), '');
      // 빈 칸은 곧바로 필수 검증에 걸린다.
      expect(
        PlaceArea.validate(PlaceArea.textOf(const {'name': '옛 플레이스'})),
        PlaceArea.requiredMessage,
      );
    });

    test('값이 있던 문서는 그 값이 입력칸에 그대로 돌아온다', () {
      expect(PlaceArea.textOf({PlaceArea.field: 20.0}), '20');
      expect(PlaceArea.textOf({PlaceArea.field: 12.5}), '12.5');
    });

    test('상한을 넘겨 저장돼 있던 값도 화면에서는 사라지지 않는다', () {
      // 읽기는 있는 그대로 — 범위는 새로 고를 때만 강제한다.
      expect(PlaceArea.of({PlaceArea.field: 9000}), 9000.0);
      expect(PlaceArea.labelOf({PlaceArea.field: 9000}), '9,000평');
    });

    test('이상한 값이 들어 있어도 화면이 깨지지 않는다', () {
      expect(PlaceArea.of({PlaceArea.field: 0}), isNull);
      expect(PlaceArea.of({PlaceArea.field: -3}), isNull);
      expect(PlaceArea.of({PlaceArea.field: double.nan}), isNull);
      expect(PlaceArea.of({PlaceArea.field: '무제한'}), isNull);
      // 어쩌다 문자열로 들어간 정상값은 살려 읽는다(쓰기는 언제나 숫자다).
      expect(PlaceArea.of({PlaceArea.field: '20'}), 20.0);
    });
  });
}
