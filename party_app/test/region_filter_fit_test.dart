import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/widgets/main/region_filter_fit.dart';

/// 장소대여 상단 줄의 지역 버튼 — **필터명은 어떤 폭에서도 말줄임하지 않는다**.
///
/// 예전에는 좁은 폰에서 `지…`가 됐다. 그 회귀를 여기서 잡는다.
void main() {
  // ── 실제 줄 폭 ──────────────────────────────────────────────────────────
  //
  // 줄은 좌우 16씩 여백을 뺀 폭이고(_buildPlaceFilter의 fromLTRB(16,…,16,…)),
  // 그 안에서 대여유형·인원·보기방식·검색·정렬이 고정 폭으로 먼저 앉는다.
  // 지역 버튼이 받는 것은 그 나머지다. 아래는 화면 폭별 **최악값**(대여유형
  // 글씨까지 붙고 지역을 여러 개 고른 경우)을 넉넉히 잡은 값이다.
  double rowWidth(double screen) => screen - 32;

  /// 지역 버튼이 실제로 받는 자리 — 고정 컨트롤(대여유형 아이콘만 38 ·
  /// 인원 38 · 보기방식 54 · 돋보기 48 · 정렬 48 · 간격 4×5=20)을 뺀 나머지.
  double regionRoom(double screen) => rowWidth(screen) - 246;

  group('필터명은 절대 잘리지 않는다', () {
    for (final screen in [320.0, 360.0, 390.0]) {
      test('${screen.toInt()}dp — 고른 지역이 없을 때', () {
        final fit = RegionFilterFit.resolve(
          maxWidth: regionRoom(screen),
          count: 0,
        );
        expect(fit.label, anyOf('지역선택', '지역'));
        expect(fit.label, isNot(contains('…')));
        expect(fit.label, isNot(contains('...')));
        expect(
          fit.width,
          lessThanOrEqualTo(regionRoom(screen)),
          reason: '${screen.toInt()}dp에서 버튼이 남은 자리를 넘으면 overflow가 난다',
        );
      });

      test('${screen.toInt()}dp — 지역 3개를 골랐을 때', () {
        final fit = RegionFilterFit.resolve(
          maxWidth: regionRoom(screen),
          count: 3,
        );
        expect(fit.label, startsWith('지역'));
        expect(fit.label, isNot(contains('…')));
        expect(fit.width, lessThanOrEqualTo(regionRoom(screen)));
      });
    }
  });

  group('"지역" 두 글자는 어떤 폭에서도 온전히 남는다', () {
    test('자리가 아무리 좁아도 라벨은 최소 "지역"이다', () {
      for (var w = 0.0; w <= 400; w += 1) {
        final fit = RegionFilterFit.resolve(maxWidth: w, count: 0);
        expect(
          fit.label,
          startsWith('지역'),
          reason: 'maxWidth=$w에서 라벨이 "$fit.label"로 줄었다',
        );
        expect(fit.label.length, greaterThanOrEqualTo(2));
      }
    });

    test('가장 좁은 후보도 "지역"을 통째로 담는다', () {
      final narrowest = RegionFilterFit.candidates(0).last;
      expect(narrowest.label, '지역');
      expect(narrowest.showIcon, isFalse);
      expect(narrowest.showChevron, isFalse);
      // 40px 남짓 — 실기기에서 지역 버튼이 이보다 좁아지지 않는다.
      expect(narrowest.width, lessThan(45));
    });
  });

  group('덜어내는 순서 — 장식부터, 이름은 마지막', () {
    test('자리가 넉넉하면 핀·화살표·전체 이름이 다 나온다', () {
      final fit = RegionFilterFit.resolve(maxWidth: 400, count: 2);
      expect(fit.label, '지역선택 (2)');
      expect(fit.showIcon, isTrue);
      expect(fit.showChevron, isTrue);
      expect(fit.hPadding, 14);
    });

    test('핀이 화살표보다 먼저 떨어진다', () {
      final cs = RegionFilterFit.candidates(0);
      final iconGone = cs.indexWhere((c) => !c.showIcon);
      final chevronGone = cs.indexWhere((c) => !c.showChevron);
      expect(iconGone, lessThan(chevronGone));
    });

    test('이름이 짧아지기 전에 핀이 먼저 떨어진다', () {
      final cs = RegionFilterFit.candidates(2);
      final iconGone = cs.indexWhere((c) => !c.showIcon);
      final nameShort = cs.indexWhere((c) => !c.label.startsWith('지역선택'));
      expect(iconGone, lessThan(nameShort));
    });

    test('후보는 넓은 것부터 좁은 것 순이다 — 훑기가 성립하려면', () {
      final widths = RegionFilterFit.candidates(2).map((c) => c.width).toList();
      for (var i = 1; i < widths.length; i++) {
        expect(
          widths[i],
          lessThanOrEqualTo(widths[i - 1]),
          reason: '$i번째 후보가 앞 후보보다 넓다',
        );
      }
    });
  });

  group('폭 계산이 실제로 그리는 것과 맞는다', () {
    testWidgets('measureText는 렌더링된 글자 폭과 같다', (tester) async {
      const text = '지역선택 (2)';
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: Text(text, key: key, style: RegionFilterFit.textStyle),
          ),
        ),
      );
      final rendered = tester.getSize(find.byKey(key)).width;
      expect(RegionFilterFit.measureText(text), closeTo(rendered, 0.5));
    });
  });
}
