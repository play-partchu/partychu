import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/utils/firestore_error_log.dart';

/// 플랫폼 전체 호스트 정책 — Firestore `appConfig/policy` 문서 하나로 관리한다.
/// 코드 배포 없이 이 문서의 값만 바꾸면 정책이 즉시 바뀐다
/// ([AppUpdateService]의 `appConfig/version`과 같은 방식).
///
/// 문서 구조 (Firebase Console에서 직접 생성):
/// ```
/// appConfig/policy
/// {
///   individualHostOpeningEnabled: false   // 개인(사업자 미인증) 호스트가
///                                         // 직접 모집 오픈을 할 수 있는가
///   individualHostPartyCreateEnabled: false // 개인(사업자 미인증) 호스트가
///                                           // 새 파티를 **만들** 수 있는가
/// }
/// ```
///
/// ⚠️ 두 값은 **다른 것을 연다.** 오픈은 "이미 만든 파티의 모집을 여는가"이고,
/// 생성은 "파티를 만들 수 있는가" 자체다. 지금은 개인 호스트의 파티 등록을
/// 준비 중이라 생성부터 잠겨 있고, 열리면 그 다음 단계로 오픈이 남는다.
///
/// ⚠️ 이 값은 **버튼을 보여줄지 말지**를 정할 뿐이다. 실제 차단은
/// `openPartyRecruiting`(Cloud Functions)이 같은 문서를 다시 읽어서 한다 —
/// 앱을 거치지 않은 요청도 서버에서 막힌다.
///
/// ⚠️ 정책이 true로 바뀌어도 기존 오픈예정 파티가 자동으로 열리지는 않는다.
/// 호스트가 각자 자기 게시물에서 "모집 오픈"을 눌러야 한다.
class HostOpenPolicyService {
  HostOpenPolicyService._();

  static const _docPath = 'appConfig/policy';

  /// 문서가 없거나 읽기에 실패하면 **잠긴 것으로 본다**. 정책 조회 실패를
  /// "열림"으로 처리하면 네트워크 장애가 곧 정책 우회가 되기 때문이다.
  static const _lockedByDefault = false;

  static Stream<bool> watchIndividualHostOpeningEnabled() {
    return FirebaseFirestore.instance
        .doc(_docPath)
        .snapshots()
        .map((s) => s.data()?['individualHostOpeningEnabled'] == true)
        .handleError((e, st) {
          logFirestoreStreamError(
            'HostOpenPolicyService.watchIndividualHostOpeningEnabled',
            e,
            st,
          );
        });
  }

  static Future<bool> individualHostOpeningEnabled() =>
      _readFlag('individualHostOpeningEnabled');

  /// 개인(사업자 미인증) 호스트가 **새 파티를 만들 수 있는가.**
  ///
  /// 지금은 false로 운영한다 — 개인 호스트의 파티 등록을 준비 중이라 등록
  /// 진입 자체를 막고 안내만 띄운다([PartyCreateEligibility]). 준비가 끝나면
  /// 이 문서의 값만 true로 바꾸면 열린다 — **앱 재배포가 필요 없다.**
  ///
  /// 사업자 인증을 마친 호스트는 이 값을 보지 않는다(항상 등록할 수 있다).
  /// 기존 파티의 조회·수정·관리와 이벤트 등록도 이 값과 무관하다.
  ///
  /// ⚠️ 이 값은 **버튼을 보여줄지 말지**를 정할 뿐이다. 실제 차단은
  /// firestore.rules의 `parties` create와 `createParty`(Cloud Functions)가
  /// 같은 문서를 다시 읽어서 한다 — 구버전 앱이나 SDK 직접 호출도 막힌다.
  static Future<bool> individualHostPartyCreateEnabled() =>
      _readFlag('individualHostPartyCreateEnabled');

  /// 정책 값 하나를 읽는다. 문서가 없거나 읽기에 실패하면 [_lockedByDefault].
  static Future<bool> _readFlag(String key) async {
    try {
      final snap = await FirebaseFirestore.instance
          .doc(_docPath)
          .get()
          .timeout(const Duration(seconds: 5));
      return snap.data()?[key] == true;
    } catch (e, st) {
      logFirestoreStreamError('HostOpenPolicyService.$key', e, st);
      return _lockedByDefault;
    }
  }
}
