// 이벤트 저장이 실패했을 때 **무슨 말을 하는가.**
//
// ── 이 파일이 막는 재발 ─────────────────────────────────────────────────────
// 예전에는 permission-denied가 아닌 모든 실패를 "저장에 실패했어요. 잠시 후
// 다시 시도해주세요."로 뭉갰다. 그래서 사진 업로드 콜러블이 없어 막힌 것도,
// 사업자 권한이 없는 것도, 네트워크가 끊긴 것도 전부 같은 문장으로 나왔고
// 호스트는 무엇을 고쳐야 하는지 알 수 없었다.
//
// ── 판정의 원칙 ─────────────────────────────────────────────────────────────
// firestore.rules는 **어느 조건에서 막았는지 알려주지 않는다** —
// permission-denied 한 줄뿐이다. 그래서 앱이 부모 플레이스와 사업자 권한을
// 실제로 되읽고, **확인한 사실만** 말한다.
//
// ⚠️ 확인하지 않은 것을 원인으로 지목하면 안 된다. 소유권 문제인데 "사업자
//    인증을 확인하세요"라고 하면 호스트는 멀쩡한 인증 화면만 들여다보다 끝난다.
//
// 규칙이 실제로 무엇을 허용/거부하는지는 여기가 아니라
// functions/placeEventRules.selfcheck.js(실제 Rules 엔진)가 본다.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/business_verification.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/services/place_event_entry.dart';

const _placeId = 'ev-mine';
const _collection = 'events';

/// 권한까지 열린 정상 사업자.
const _authorized = BusinessVerification(
  status: BusinessVerificationStatus.verified,
  authorization: BusinessAuthorization.self,
);

/// 권한 축이 기록되기 전에 인증을 마친 계정.
const _legacyVerified = BusinessVerification(
  status: BusinessVerificationStatus.verified,
);

const _pendingApproval = BusinessVerification(
  status: BusinessVerificationStatus.verified,
  authorization: BusinessAuthorization.pendingOwnerApproval,
);

void main() {
  tearDown(PlaceEventEntry.debugResetSource);

  /// 부모 소유 여부와 사업자 권한을 고정한다.
  /// [owns]가 null이면 "확인하지 못했다"는 뜻이다.
  void use({bool? owns = true, BusinessVerification verification = _authorized}) {
    PlaceEventEntry.debugSetSource(
      owns: (_, _) async => owns,
      verification: () async => verification,
    );
  }

  Future<String> messageFor(Object error) => PlaceEventEntry.saveFailureMessage(
    error,
    placeId: _placeId,
    placeCollection: _collection,
  );

  FirebaseException denied() => FirebaseException(
    plugin: 'cloud_firestore',
    code: 'permission-denied',
    message: 'Missing or insufficient permissions.',
  );

  // ── 권한 거부 ─────────────────────────────────────────────────────────
  group('권한 거부는 무엇이 막았는지 되물어 말한다', () {
    test('부모가 내 플레이스가 아니면 소유권을 말한다', () async {
      use(owns: false);
      expect(await messageFor(denied()), '이 장소의 호스트만 이벤트를 등록할 수 있어요.');
    });

    // 소유권이 원인인데 사업자 인증을 지목하면 엉뚱한 곳을 고치러 간다.
    test('소유권이 원인이면 사업자 인증을 지목하지 않는다', () async {
      use(owns: false, verification: _legacyVerified);
      expect(await messageFor(denied()), isNot(contains('사업자 인증')));
    });

    test('부모는 내 것인데 대표자 확인 대기면 그 사실을 말한다', () async {
      use(verification: _pendingApproval);
      expect(
        await messageFor(denied()),
        '대표자 확인이 완료되어야 이벤트를 등록할 수 있어요.',
      );
    });

    test('부모는 내 것인데 사업자 권한이 없으면 재확인을 안내한다', () async {
      use(verification: _legacyVerified);
      expect(await messageFor(denied()), '사업자 인증 상태를 다시 확인해주세요.');
    });

    // 소유권도 사업자 권한도 멀쩡한데 막혔다면 남은 것은 isVerifiedMember다.
    test('둘 다 멀쩡하면 계정 상태를 보라고 말한다', () async {
      use();
      expect(await messageFor(denied()), contains('본인확인을 마친 계정만'));
    });

    // 모르는 것을 단정하면 안 된다 — 부모를 못 읽었을 때 "남의 장소"라고
    // 말하면 자기 장소인 호스트에게 거짓말이 된다.
    test('부모를 확인하지 못하면 단정하지 않는다', () async {
      use(owns: null, verification: _legacyVerified);
      expect(await messageFor(denied()), PlaceEventEntry.genericSaveFailure);
    });

    // 타입을 잃고 올라온 예외도 예전과 같은 문자열 판정으로 받는다.
    test('문자열로만 올라온 permission-denied도 잡는다', () async {
      use(owns: false);
      expect(
        await messageFor(
          Exception('[cloud_firestore/permission-denied] insufficient'),
        ),
        '이 장소의 호스트만 이벤트를 등록할 수 있어요.',
      );
    });
  });

  // ── 미디어 업로드 ─────────────────────────────────────────────────────
  //
  // 사진·동영상은 이벤트 저장과 **다른 단계**다. 업로드가 막혀도 입력한 내용은
  // 멀쩡하므로, 사진을 빼고 저장하면 되는 길을 알려준다.
  group('미디어 업로드 실패는 저장 실패와 구분한다', () {
    test('업로드 실패는 일반 실패 문구를 쓰지 않는다', () async {
      use();
      final msg = await messageFor(
        const CloudflareUploadException(kind: 'callable', detail: 'not-found: …'),
      );
      expect(msg, isNot(PlaceEventEntry.genericSaveFailure));
      expect(msg, contains('사진'));
      expect(msg, contains('사진을 빼고 저장'), reason: '지금 할 수 있는 일을 알려줘야 한다');
    });

    test('서버가 사람이 읽을 문장을 줬으면 그대로 보여준다', () async {
      use();
      expect(
        await messageFor(
          const CloudflareUploadException(
            kind: 'r2',
            statusCode: 400,
            detail: 'invalid-argument',
            userMessage: '파일이 너무 큽니다. 최대 10MB까지 올릴 수 있어요.',
          ),
        ),
        '파일이 너무 큽니다. 최대 10MB까지 올릴 수 있어요.',
      );
    });

    // 업로드 실패에는 부모·사업자 권한을 되묻지 않는다 — 관계가 없다.
    test('업로드 실패는 권한을 되묻지 않는다', () async {
      var asked = false;
      PlaceEventEntry.debugSetSource(
        owns: (_, _) async {
          asked = true;
          return true;
        },
        verification: () async {
          asked = true;
          return _authorized;
        },
      );
      await messageFor(
        const CloudflareUploadException(kind: 'callable', detail: 'not-found'),
      );
      expect(asked, isFalse);
    });
  });

  // ── 그 밖 ─────────────────────────────────────────────────────────────
  group('일시적 실패에만 기존 문구를 쓴다', () {
    test('네트워크·서버 오류는 일반 실패 문구', () async {
      use();
      for (final e in [
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        FirebaseException(plugin: 'cloud_firestore', code: 'deadline-exceeded'),
        Exception('SocketException: Failed host lookup'),
      ]) {
        expect(await messageFor(e), PlaceEventEntry.genericSaveFailure);
      }
    });

    // 색인이 없으면 목록 조회가 failed-precondition으로 죽는다 —
    // 권한 문제가 아니므로 사업자 인증을 지목하면 안 된다.
    test('색인 없음(failed-precondition)은 권한 문구를 쓰지 않는다', () async {
      use(verification: _legacyVerified);
      final msg = await messageFor(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'failed-precondition',
          message: 'The query requires an index.',
        ),
      );
      expect(msg, PlaceEventEntry.genericSaveFailure);
      expect(msg, isNot(contains('사업자')));
    });
  });
}
