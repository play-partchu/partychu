// ─────────────────────────────────────────────────────────────────────────────
// 새 플레이스를 등록할 수 있는가 — **신규 플레이스 생성 진입의 유일한 관문.**
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
// ── 파티 등록 관문과 다른 점 ─────────────────────────────────────────────────
// [PartyCreateEligibility]에는 `appConfig/policy`로 개인 호스트에게 열어주는
// 예외가 있다. **플레이스에는 그 예외가 없다** — 플레이스는 실제 매장·공간을
// 운영하는 사업자만 올리는 것이라 정책 문서로 열고 닫을 값이 아니다. 그래서
// 여기서는 정책 문서를 읽지 않는다.
//
// ── 무엇을 막고 무엇을 막지 않는가 ───────────────────────────────────────────
// 막는 것은 **새 플레이스를 만드는 진입뿐**이다. 등록 폼을 여는 모든 길이 여기를
// 지난다 — 등록 유형 화면의 "플레이스 등록", 상단바 "등록하기"(플레이스·장소대여
// 탭), 임시저장 이어쓰기, 이벤트 등록 안내 시트의 "플레이스 등록하기".
//
// 막지 않는 것: 기존 플레이스의 조회·수정·관리, 이벤트(placePromotions) 등록,
// 룸·상품처럼 이미 만든 플레이스에 딸린 문서.
//
// ⚠️ 여기는 **화면을 열지 말지**를 정할 뿐이다. 실제 차단은 firestore.rules의
// `events`/`places` create가 같은 조건(isBusinessVerified)을 다시 보고 한다 —
// 구버전 앱이나 SDK 직접 호출도 거기서 막힌다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'package:party_app/models/business_verification.dart';
import 'package:party_app/screens/business_verification_screen.dart';
import 'package:party_app/services/business_verification_service.dart';
import 'package:party_app/services/registration_limits.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 새 플레이스 등록 자격.
enum PlaceCreateGate {
  /// 만들 수 있다 — 사업자 인증을 마쳤다.
  allowed,

  /// 사업자 인증을 마치지 않아 아직 만들 수 없다
  /// (unverified·pending·failed·suspended 전부 여기다).
  blockedNotBusiness,
}

class PlaceCreateEligibility {
  PlaceCreateEligibility._();

  // ── 테스트 주입점 ───────────────────────────────────────────────────────
  // 이 프로젝트의 Dart 테스트에는 Firestore 페이크가 없다
  // (place_party_link_payload_test.dart 상단 주석). 운영 코드는 null이라
  // 실물 Firestore를 그대로 쓴다.
  static Future<BusinessVerification> Function()? _verificationOverride;

  /// 인증 화면 대신 열 라우트(테스트 전용).
  ///
  /// [BusinessVerificationScreen]은 실물 Firestore를 읽어서 위젯 테스트에서
  /// 띄울 수 없다. "다녀온 뒤 다시 읽는다"를 검증하려면 다녀올 화면이
  /// 있어야 하므로, 그 자리만 갈아 끼운다.
  static Route<void> Function()? _verificationRouteOverride;

  @visibleForTesting
  static void debugSetSource(
    Future<BusinessVerification> Function()? verification,
  ) {
    _verificationOverride = verification;
  }

  @visibleForTesting
  static void debugSetVerificationRoute(Route<void> Function()? route) {
    _verificationRouteOverride = route;
  }

  @visibleForTesting
  static void debugResetSource() {
    _verificationOverride = null;
    _verificationRouteOverride = null;
  }

  /// 지금 이 계정의 사업자 인증 상태. 못 읽으면
  /// [BusinessVerification.none](미인증)이다 — 조회 실패가 곧 통과가 되면
  /// 안 된다([BusinessVerificationService.fetch]가 이미 그렇게 돌려준다).
  static Future<BusinessVerification> verification() {
    final override = _verificationOverride;
    if (override != null) return override();
    return BusinessVerificationService.fetch();
  }

  /// 지금 이 계정이 새 플레이스를 만들 수 있는지.
  static Future<PlaceCreateGate> evaluate() async {
    // verified만 사업자다 — pending/failed/suspended는 아직 아니다.
    return (await verification()).isVerified
        ? PlaceCreateGate.allowed
        : PlaceCreateGate.blockedNotBusiness;
  }

  /// **새 플레이스 등록 진입 앞에 세우는 관문.**
  ///
  /// 통과하면 true를 돌려주고 호출부가 그대로 등록 화면을 연다. 막히면 안내를
  /// 띄우고 false를 돌려준다 — 호출부는 아무 데도 보내지 않는다.
  ///
  /// 자격을 못 읽었을 때도 막는다([evaluate]가 fail-closed다).
  ///
  /// ── 인증 화면을 다녀오면 **다시 읽는다** ─────────────────────────────
  /// 예전에는 안내 시트가 인증 화면을 열어 두고 곧바로 false를 돌려줬다.
  /// 그래서 인증을 마치고 돌아와도 관문은 이미 끝나 있었고, 사용자는 등록을
  /// 처음부터 다시 눌러야 했다. 여기서 화면이 닫힐 때까지 기다렸다가
  /// **서버의 최신 상태를 다시 읽어** 통과 여부를 정한다.
  ///
  /// ⚠️ 다시 읽은 값도 [BusinessVerification.isVerified]로만 판정한다 —
  ///    "방금 인증 화면을 다녀왔으니 통과"로 만들면 그것이 곧 우회로다.
  ///    실패·취소·대표자 승인 대기는 전부 false다(등록 화면으로 억지로
  ///    보내지 않는다).
  /// ── 등록 개수도 함께 본다 ────────────────────────────────────────────
  /// [kind]를 주면 그 유형의 상한까지 확인한다([RegistrationLimits]).
  /// 플레이스와 장소대여는 **서로 다른 통**이라(각각 10개) 어느 쪽을 만들려는
  /// 것인지 아는 호출부만 넘긴다. 유형이 아직 안 정해진 자리(등록 유형 선택
  /// 앞단 등)는 넘기지 않고, 그런 길도 결국 등록 화면의 저장 직전 검사에서
  /// 다시 걸린다.
  static Future<bool> ensure(
    BuildContext context, {
    RegistrationKind? kind,
  }) async {
    final v = await verification();
    if (!v.isVerified) {
      if (!context.mounted) return false;

      final goToVerification = await showBusinessRequiredNotice(context, v);
      if (goToVerification != true || !context.mounted) return false;

      await Navigator.push<void>(
        context,
        _verificationRouteOverride?.call() ??
            webFramedRoute<void>((_) => const BusinessVerificationScreen()),
      );
      if (!context.mounted) return false;
      if (!(await verification()).isVerified) return false;
    }

    if (kind == null) return true;
    if (!context.mounted) return false;
    return RegistrationLimits.ensure(context, kind);
  }

  /// 사업자 인증 안내 — 파티 쪽 안내와 달리 **갈 곳이 있다.** 인증만 마치면
  /// 바로 등록할 수 있으므로 사업자 인증 화면으로 보낸다.
  ///
  /// 상태별 문구는 [BusinessVerification.guidance]를 그대로 쓴다 — 여기서
  /// 따로 지어내면 마이페이지·정산 화면과 말이 갈라진다.
  ///
  /// 사용자가 인증 화면으로 가기를 고르면 **true**를 돌려준다. 화면을 여는
  /// 것은 [ensure]가 한다 — 여기서 열면 그 화면이 닫히는 것을 기다릴 수 없어
  /// 인증을 마치고 돌아와도 관문이 다시 판정하지 못한다.
  @visibleForTesting
  static Future<bool?> showBusinessRequiredNotice(
    BuildContext context,
    BusinessVerification v,
  ) {
    // 무엇을 해야 하는 상태인지에 따라 제목과 버튼이 갈린다.
    //
    // ⚠️ 국세청 확인을 이미 통과한 사람에게 "사업자 인증 다시 확인하기"만
    //    보여 주면, 인증 화면에 갔다가 "이미 됐는데?" 하고 돌아와 같은 시트를
    //    다시 만난다. 남은 일이 **대표자 승인**인지 **본인의 재확인**인지를
    //    버튼이 구분해 말한다.
    final (String title, String actionLabel) = switch (v) {
      _ when v.needsOwnerApproval => (
        '플레이스 등록에 대표자 승인이 필요해요',
        '대표자 승인 받으러 가기',
      ),
      _ when v.needsReverification => (
        '사업자 권한 확인이 한 번 더 필요해요',
        '사업자 권한 확인하기',
      ),
      _ when v.status == BusinessVerificationStatus.unverified => (
        '플레이스 등록은 사업자 인증이 필요해요',
        '사업자 인증하기',
      ),
      // pending·failed·suspended — 이미 시도해 봤고 다시 하면 되는 상태.
      _ => ('플레이스 등록은 사업자 인증이 필요해요', '사업자 인증 다시 확인하기'),
    };

    return showModalBottomSheet<bool>(
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
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '매장·즐길거리, 공간대여·숙박은 사업자 인증을 마친 호스트만 '
                  '새로 등록할 수 있어요.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: Color(0xFF8A5A72),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  v.guidance,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: Color(0xFF8A5A72),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    // 시트를 닫으면서 "가겠다"만 알린다 — 화면은 [ensure]가
                    // 열고 닫힐 때까지 기다린다(인증을 마치고 돌아왔을 때
                    // 안내 시트가 남아 있으면 안 되는 것도 그대로다).
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6FA0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      actionLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black54,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('나중에', style: TextStyle(fontSize: 14)),
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
