// ─────────────────────────────────────────────────────────────────────────────
// 새 파티를 만들 수 있는가 — **신규 생성 진입의 유일한 관문.**
//
// ── 정본은 사업자 인증 하나다 ────────────────────────────────────────────────
// 자격 판정은 `users/{uid}.businessVerification.status == 'verified'`
// ([BusinessVerification.isVerified]) 하나만 본다. 화면마다 `isBusiness` 같은
// 불리언을 따로 만들지 않는다 — 그러면 한 화면만 고쳐져 우회로가 생긴다.
//
// pending·failed·suspended·unverified는 전부 **미인증**이다. 국세청 확인을
// 통과한 verified만 사업자로 취급한다(그 판정은 서버만 쓴다 — 클라이언트는
// 이 필드에 쓸 수 없다).
//
// `settlementInfo.hostType`('개인'/'사업자')은 정산 화면에서 사용자가 직접
// 고르는 값이라 권한 판정에 쓸 수 없다([BusinessVerification] 상단 주석).
//
// ── 개인 호스트는 지금 잠겨 있다 ─────────────────────────────────────────────
// 준비가 끝나면 `appConfig/policy.individualHostPartyCreateEnabled`를 true로
// 바꾸는 것만으로 열린다 — 앱 재배포가 필요 없다. 문서가 없거나 읽기에
// 실패하면 **잠긴 것으로 본다**(fail-closed) — 정책 조회 실패가 곧 정책 우회가
// 되면 안 된다.
//
// ── 무엇을 막고 무엇을 막지 않는가 ───────────────────────────────────────────
// 막는 것은 **새 파티를 만드는 진입뿐**이다. 등록 폼을 여는 모든 길이 여기를
// 지난다 — 등록 화면, 임시저장 이어쓰기, 지난 파티 재등록, 플레이스 연결
// 화면의 "새 파티 만들기".
//
// 막지 않는 것: 기존 파티의 조회·수정·관리, 이벤트 등록.
//
// 플레이스 등록은 이 관문이 아니라 [PlaceCreateEligibility]가 지킨다 — 그쪽은
// 사업자 인증만 보고 개인 정책 예외가 없다.
//
// ⚠️ 여기는 **화면을 열지 말지**를 정할 뿐이다. 실제 차단은 firestore.rules의
// `parties` create와 `createParty`(Cloud Functions)가 같은 정책을 다시 읽어서
// 한다 — 구버전 앱이나 SDK 직접 호출도 거기서 막힌다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'package:party_app/services/business_verification_service.dart';
import 'package:party_app/services/host_open_policy_service.dart';
import 'package:party_app/services/registration_limits.dart';

/// 새 파티 생성 자격.
enum PartyCreateGate {
  /// 만들 수 있다 — 사업자 인증을 마쳤거나, 개인 등록이 열린 상태다.
  allowed,

  /// 개인(사업자 미인증) 호스트라 아직 만들 수 없다.
  blockedIndividual,
}

class PartyCreateEligibility {
  PartyCreateEligibility._();

  // ── 테스트 주입점 ───────────────────────────────────────────────────────
  // 이 프로젝트의 Dart 테스트에는 Firestore 페이크가 없다
  // (place_party_link_payload_test.dart 상단 주석). 운영 코드는 둘 다 null이라
  // 실물 Firestore를 그대로 쓴다.
  static Future<bool> Function()? _businessVerifiedOverride;
  static Future<bool> Function()? _individualEnabledOverride;

  @visibleForTesting
  static void debugSetSource({
    Future<bool> Function()? businessVerified,
    Future<bool> Function()? individualEnabled,
  }) {
    _businessVerifiedOverride = businessVerified;
    _individualEnabledOverride = individualEnabled;
  }

  @visibleForTesting
  static void debugResetSource() {
    _businessVerifiedOverride = null;
    _individualEnabledOverride = null;
  }

  /// 지금 이 계정이 새 파티를 만들 수 있는지.
  ///
  /// 사업자 인증을 마쳤으면 정책 문서를 **읽지도 않는다** — 개인 등록 정책은
  /// 사업자에게 아무 영향이 없어야 하고, 그 문서를 못 읽는다고 사업자 등록이
  /// 막히면 안 된다.
  static Future<PartyCreateGate> evaluate() async {
    if (await _isBusinessVerified()) return PartyCreateGate.allowed;
    return await _individualEnabled()
        ? PartyCreateGate.allowed
        : PartyCreateGate.blockedIndividual;
  }

  static Future<bool> _isBusinessVerified() async {
    final override = _businessVerifiedOverride;
    if (override != null) return override();
    final v = await BusinessVerificationService.fetch();
    // verified만 사업자다 — pending/failed/suspended는 아직 아니다.
    return v.isVerified;
  }

  static Future<bool> _individualEnabled() {
    final override = _individualEnabledOverride;
    if (override != null) return override();
    return HostOpenPolicyService.individualHostPartyCreateEnabled();
  }

  /// **새 파티 등록 진입 앞에 세우는 관문.**
  ///
  /// 통과하면 true를 돌려주고 호출부가 그대로 등록 화면을 연다. 막히면 안내를
  /// 띄우고 false를 돌려준다 — 호출부는 아무 데도 보내지 않는다.
  ///
  /// 자격을 못 읽었을 때도 막는다([evaluate]가 fail-closed다).
  ///
  /// ── 등록 개수도 여기서 본다 ──────────────────────────────────────────
  /// 자격과 개수는 성격이 다르지만(하나는 권한, 하나는 상한) **막는 자리는
  /// 같아야 한다.** 파티 등록 폼을 여는 길이 일곱 개인데, 개수 검사를 그중
  /// 몇 곳에만 두면 나머지가 그대로 우회로가 된다 — 실제로 예전에는 등록 탭
  /// 하나에만 있었다. 판정과 안내는 [RegistrationLimits] 한 곳에 있다.
  static Future<bool> ensure(BuildContext context) async {
    final gate = await evaluate();
    if (gate != PartyCreateGate.allowed) {
      if (!context.mounted) return false;
      await showIndividualNotice(context);
      return false;
    }
    if (!context.mounted) return false;
    return RegistrationLimits.ensure(context, RegistrationKind.party);
  }

  /// 개인 호스트 안내 — "곧 열린다"만 말하고 아무 데도 보내지 않는다.
  ///
  /// **플레이스 등록을 권하지 않는다.** 플레이스 등록도 사업자 자격이 필요한
  /// 길이라, 개인에게 그 버튼을 주면 눌러서 또 막히는 자리로 데려가게 된다.
  @visibleForTesting
  static Future<void> showIndividualNotice(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFFF7FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD6E4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '개인 파티 등록은 준비 중이에요',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  '사업자가 아닌 개인 호스트의 파티 등록 기능은 '
                  '약 한 달 후 이용할 수 있도록 준비하고 있어요.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: Color(0xFF8A5A72),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6FA0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '확인',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
