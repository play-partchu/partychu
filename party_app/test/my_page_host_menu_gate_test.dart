// 마이페이지 호스트 전용 메뉴 노출 조건 — **사업자 인증 완료 하나**로만 갈린다.
//
// 가려지는 넷:
//   👑 파티츄 호스트 · 신청자 · 예약자 관리 · 판매 통계 · 입금받을 계좌
//
// 이 파일이 붙잡는 회귀는 셋이다.
//   1. 기준이 **본인인증(NICE)**으로 미끄러지는 것 — 참가자도 전원 통과한다.
//   2. 기준이 **등록물 존재 여부**로 미끄러지는 것 — 인증만 마치고 아직 아무것도
//      등록하지 않은 호스트에게서 '처음 등록하러 들어갈 자리'가 사라진다.
//   3. 상태를 읽기 전에 일단 보여줬다가 지우는 것 — 참가자 화면에서 호스트
//      메뉴가 한 프레임 번쩍인 뒤 사라진다.
//
// 화면 자체는 Firebase 없이 그릴 수 없어서(users 문서 스트림 넷), 판정값은
// 모델로, 배선은 소스 가드로 확인한다 — account_ux_test.dart와 같은 방식이다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/business_verification.dart';

String _src(String path) => File(path).readAsStringSync();

/// 줄바꿈·들여쓰기를 지운 소스 — 포매터가 줄을 접거나 CRLF가 섞여도 배선
/// 가드가 깨지지 않게 한다(찾는 것은 배선이지 서식이 아니다).
String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 사업자 인증을 마친 계정의 users 문서 — 서버가 두 축을 모두 적은 모습.
Map<String, dynamic> _verifiedUser() => {
  'identityVerified': true,
  'businessVerification': {
    'status': 'verified',
    'authorization': 'self',
    'businessNumber': '1234567890',
    'representativeName': '홍길동',
    'ntsStatusLabel': '계속사업자',
  },
};

void main() {
  final myPage = _src('lib/screens/my_page_screen.dart');

  // ── 1. 판정값 — 네 가지 계정 상태 ────────────────────────────────────
  group('노출 판정은 사업자 인증 완료 하나로 갈린다', () {
    test('일반 참가자 + 본인인증 완료 + 사업자 인증 전 → 숨김', () {
      // 본인인증은 참가자도 전부 마치는 절차라 호스트 판정에 쓸 수 없다.
      final v = BusinessVerification.fromUserDoc({
        'identityVerified': true,
        'identityVerifiedAt': 1756600000000,
      });
      expect(v.status, BusinessVerificationStatus.unverified);
      expect(v.isVerified, isFalse);
    });

    test('사업자 인증 완료 → 등록물이 0개여도 노출', () {
      // 등록물 수는 판정에 들어가지 않는다 — 이 문서에는 파티·플레이스·공간·
      // 크루에 대한 정보가 아예 없는데도 통과해야 한다.
      expect(BusinessVerification.fromUserDoc(_verifiedUser()).isVerified, isTrue);
    });

    test('사업자 인증 완료 → 등록물이 있어도 같은 값(노출)', () {
      // 등록물이 있다는 사실을 문서에 얹어도 판정이 달라지지 않아야 한다.
      final withContent = {
        ..._verifiedUser(),
        'hostedPartyCount': 3,
        'placeCount': 1,
      };
      expect(
        BusinessVerification.fromUserDoc(withContent).isVerified,
        BusinessVerification.fromUserDoc(_verifiedUser()).isVerified,
      );
      expect(BusinessVerification.fromUserDoc(withContent).isVerified, isTrue);
    });

    test('인증 해제 · 미완료 상태는 전부 숨김', () {
      // 진위조차 나지 않은 상태들.
      for (final status in ['unverified', 'pending', 'failed', 'suspended']) {
        final v = BusinessVerification.fromUserDoc({
          'businessVerification': {'status': status, 'authorization': 'self'},
        });
        expect(v.isVerified, isFalse, reason: 'status=$status');
      }

      // 진위는 남아 있는데 **권한만 닫힌** 상태들 — 대표자가 위임을 취소했거나
      // (delegationRevoked) 아직 대표자 확인을 못 받은 계정이다. 여기서
      // status만 보면 권한이 없는 계정에 호스트 메뉴가 열린다.
      final revoked = BusinessVerification.fromUserDoc({
        'businessVerification': {
          'status': 'verified',
          'authorization': 'pendingOwnerApproval',
          'authorizationReason': BusinessAuthReason.delegationRevoked,
        },
      });
      expect(revoked.status, BusinessVerificationStatus.verified);
      expect(revoked.isVerified, isFalse);

      // 위임 근거 문서가 없는 delegated도 열리지 않는다(fail-closed).
      final danglingDelegation = BusinessVerification.fromUserDoc({
        'businessVerification': {
          'status': 'verified',
          'authorization': 'delegated',
        },
      });
      expect(danglingDelegation.isVerified, isFalse);
    });
  });

  // ── 2. 배선 — 무엇이 게이트 뒤에 있는가 ──────────────────────────────
  group('마이페이지가 그 판정을 실제로 쓴다', () {
    test('게이트는 사업자 인증 스트림의 isVerified만 본다', () {
      expect(myPage.contains('class _BusinessVerifiedOnly'), isTrue);
      expect(
        myPage.contains('stream: BusinessVerificationService.watch()'),
        isTrue,
      );
      // 등록 자격 판정과 같은 값(isVerified)이다. status를 직접 보면
      // "메뉴는 열렸는데 등록은 막히는" 모순이 생긴다.
      expect(myPage.contains('snap.data?.isVerified ?? false'), isTrue);
      expect(myPage.contains("status == BusinessVerificationStatus.verified"), isFalse);
    });

    test('상태를 모르는 동안에는 숨긴 채로 시작한다 — 깜빡임 없음', () {
      // `snap.data`가 null인 첫 프레임은 false로 떨어져야 한다. `?? true`나
      // hasData 낙관 처리로 바뀌면 여기서 걸린다.
      expect(
        _flat(myPage).contains(
          'final verified = snap.data?.isVerified ?? false; '
          'if (!verified) return const SizedBox.shrink();',
        ),
        isTrue,
      );
    });

    test('호스트 카드 · 관리 · 통계 세 줄이 한 게이트 뒤에 함께 있다', () {
      // 셋은 _HostEntrySection 하나에 들어 있고(같은 숫자를 두 번 세지 않기
      // 위해서다), 그 위젯 전체가 게이트 안에 들어간다.
      expect(
        _flat(myPage).contains(
          '_BusinessVerifiedOnly( child: Padding( '
          'padding: const EdgeInsets.only(top: 12), '
          'child: _HostEntrySection(key: _hostSectionKey),',
        ),
        isTrue,
      );
      final hostSection = myPage.substring(
        myPage.indexOf('class _HostEntrySectionState'),
      );
      expect(hostSection.contains("title: '파티츄 호스트'"), isTrue);
      expect(hostSection.contains("label: '신청자 · 예약자 관리'"), isTrue);
      expect(hostSection.contains("label: '판매 통계'"), isTrue);
    });

    test('입금받을 계좌도 같은 게이트 뒤에 있다', () {
      expect(
        _flat(myPage).contains(
          '_BusinessVerifiedOnly( child: StreamBuilder<PayoutAccount>(',
        ),
        isTrue,
      );
      // 게이트를 씌운 자리는 이 둘뿐이다(호스트 진입 + 입금받을 계좌).
      expect(
        '_BusinessVerifiedOnly( child:'.allMatches(_flat(myPage)).length,
        2,
      );
    });

    test('참가자도 쓰는 줄은 가리지 않는다', () {
      // 환불 계좌(호스트 → 나)와 사업자 인증 정보(인증하러 들어갈 자리)는
      // 인증 전 계정에도 보여야 한다 — 후자를 가리면 인증할 길이 사라진다.
      final manage = myPage.substring(
        myPage.indexOf("title: const Text('사업자 인증 정보')"),
        myPage.indexOf("title: const Text('임시저장')"),
      );
      final refundLine = manage.indexOf("title: const Text('환불 계좌 관리')");
      final lastGate = manage.lastIndexOf('_BusinessVerifiedOnly');
      expect(refundLine, greaterThan(lastGate));
    });
  });

  // ── 3. 보지 말아야 할 것 ─────────────────────────────────────────────
  test('등록물 존재 여부는 판정에 쓰이지 않는다', () {
    // 이전 기준("등록물이 하나라도 있는 회원만")의 잔재가 남으면 인증만 마친
    // 호스트가 첫 등록을 하러 들어갈 자리를 잃는다.
    final gate = myPage.substring(
      myPage.indexOf('class _BusinessVerifiedOnly'),
      myPage.indexOf('class _HostEntrySection'),
    );
    for (final forbidden in ['collection(', 'count', 'Offering', 'Ownership']) {
      expect(gate.contains(forbidden), isFalse, reason: forbidden);
    }
  });
}
