// 환불 정책 최소 1개 — **모든 등록 유형에 같은 규칙**인지 고정한다.
//
// 예전에는 환불 규정이 "설정 (선택)"이라 구간 없이도 저장됐고, 그 문서로 참가자가
// 취소하면 환불이 계산되지 않았다([computeRefundPreview]의 policyMissing).
// 이제 파티·파티+숙박 콤보(파티/룸)·플레이스+파티 콤보·장소대여(룸)가 모두
// [RefundPolicyRule] 한 곳을 보고 저장을 막는다.
//
// 여기서 보는 것은 둘이다.
//  1. 규칙 자체 — 0개는 막고, 1개·여러 개는 통과시키고, 문구가 고정돼 있다.
//  2. 전수 적용 — 환불 규정을 **편집할 수 있는 화면은 하나도 빠짐없이** 그
//     규칙을 참조한다(새 등록 유형이 생겨도 이 테스트가 잡는다).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/utils/refund_policy.dart';

void main() {
  List<RefundTier> tiers(int n) => [
    for (var i = 0; i < n; i++)
      RefundTier(daysBefore: 7 - i, refundPercent: 100 - i * 10),
  ];

  group('공용 규칙', () {
    test('최소 개수와 안내 문구는 한 곳에 고정돼 있다', () {
      expect(RefundPolicyRule.minTiers, 1);
      expect(RefundPolicyRule.requiredMessage, '환불 정책을 1개 이상 선택해주세요.');
    });

    test('0개 — 저장 불가', () {
      expect(RefundPolicyRule.isSatisfied(tiers(0)), isFalse);
      expect(RefundPolicyRule.isMissing(tiers(0)), isTrue);
      expect(
        RefundPolicyRule.validate(tiers(0)),
        RefundPolicyRule.requiredMessage,
      );
      // 요약이 비어야 각 화면이 "필수 항목이에요"를 그린다.
      expect(RefundPolicyRule.summaryLabel(tiers(0)), isNull);
    });

    test('1개 — 저장 가능', () {
      expect(RefundPolicyRule.isSatisfied(tiers(1)), isTrue);
      expect(RefundPolicyRule.isMissing(tiers(1)), isFalse);
      expect(RefundPolicyRule.validate(tiers(1)), isNull);
      expect(RefundPolicyRule.summaryLabel(tiers(1)), '1단계 환불 규정 설정됨');
    });

    test('여러 개 — 저장 가능', () {
      for (final n in [2, 3, 5]) {
        expect(RefundPolicyRule.isSatisfied(tiers(n)), isTrue, reason: '$n개');
        expect(RefundPolicyRule.validate(tiers(n)), isNull, reason: '$n개');
        expect(RefundPolicyRule.summaryLabel(tiers(n)), '$n단계 환불 규정 설정됨');
      }
    });

    test('기존 빈 문서 — 읽기는 되고, 저장만 막힌다', () {
      // Firestore에 refundPolicy가 아예 없던 옛 문서.
      final loaded = RefundTier.listFromDynamic(null);
      expect(loaded, isEmpty, reason: '읽기 자체는 성공한다(화면 진입 허용)');
      expect(
        RefundPolicyRule.isMissing(loaded),
        isTrue,
        reason: '다시 저장할 때 막힌다',
      );

      // 구간을 하나 채우면 곧바로 통과한다.
      loaded.add(RefundTier(daysBefore: 3, refundPercent: 50));
      expect(RefundPolicyRule.isSatisfied(loaded), isTrue);
    });

    test('결제가 없는 유형(무료)도 예외가 없다', () {
      // 규칙은 금액을 보지 않는다 — 무료 파티·무료 예약도 같은 판정이다.
      expect(RefundPolicyRule.isMissing(tiers(0)), isTrue);
      // 환불 "계산"이 0원을 따로 다루는 것과는 별개다.
      final preview = computeRefundPreview(
        refundPolicy: const [],
        appliedFee: 0,
        partyDateTime: DateTime(2026, 12, 1),
      );
      expect(preview.policyMissing, isFalse, reason: '계산 로직은 건드리지 않았다');
    });
  });

  group('전수 적용', () {
    /// 환불 규정을 **편집할 수 있는** 파일 — 공용 편집기/편집 화면을 여는 곳.
    /// (정의 파일 자체는 뺀다.)
    const definitions = {
      'lib/widgets/refund_policy_editor.dart',
      'lib/screens/party_refund_policy_screen.dart',
      'lib/utils/refund_policy.dart',
    };

    List<File> editorFiles() {
      final out = <File>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final rel = entity.path.replaceAll(r'\', '/');
        if (definitions.contains(rel)) continue;
        final src = entity.readAsStringSync();
        if (src.contains('RefundPolicyEditor(') ||
            src.contains('PartyRefundPolicyScreen(')) {
          out.add(entity);
        }
      }
      return out;
    }

    test('환불 규정을 편집하는 화면을 실제로 찾아낸다', () {
      final files = editorFiles().map((f) => f.path).toList();
      expect(files, isNotEmpty, reason: '탐지 방식이 깨졌다 — 아래 전수 검사가 무의미해진다');
    });

    test('편집 화면은 하나도 빠짐없이 공용 규칙으로 저장을 막는다', () {
      // 단순히 규칙을 import만 한 것으로는 부족하다 — 저장 게이트에 쓰는
      // 판정(isMissing)이 실제로 들어 있어야 한다.
      final missing = <String>[];
      for (final f in editorFiles()) {
        if (!f.readAsStringSync().contains('RefundPolicyRule.isMissing(')) {
          missing.add(f.path);
        }
      }
      expect(
        missing,
        isEmpty,
        reason:
            '환불 규정을 편집하는데 최소 1개 규칙(RefundPolicyRule.isMissing)으로 저장을\n'
            '막지 않는 화면이 있다. 화면마다 검증을 따로 적지 말고 공용 규칙을 그대로 쓰자:\n'
            '${missing.join('\n')}',
      );
    });

    test('요약 문구를 화면에서 따로 만들지 않는다', () {
      // '${tiers.length}단계 환불 규정 설정됨'을 직접 조립하던 자리는 모두
      // RefundPolicyRule.summaryLabel로 옮겼다 — 한쪽만 바뀌는 일이 없도록.
      final offenders = <String>[];
      for (final f in editorFiles()) {
        final src = f.readAsStringSync();
        if (src.contains('단계 환불 규정 설정됨')) offenders.add(f.path);
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });
}
