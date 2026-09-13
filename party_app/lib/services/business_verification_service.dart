import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:party_app/models/business_verification.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';

/// 사업자 인증 — 국세청 진위확인/상태조회는 **서버에서만** 부른다.
///
/// 앱은 입력값을 `verifyBusinessRegistration` 콜러블에 넘기기만 하고,
/// 서비스키는 물론 국세청 응답 원문도 보지 않는다. 결과는 서버가
/// `users/{uid}.businessVerification`에 기록하며, 앱은 그 문서를 읽기만 한다
/// (클라이언트 쓰기는 firestore.rules에서 막혀 있다).
class BusinessVerificationService {
  BusinessVerificationService._();

  static const _region = 'asia-northeast3';

  static DocumentReference<Map<String, dynamic>> get _userRef =>
      FirebaseFirestore.instance.collection('users').doc(UserSession.userId);

  // ── 테스트 주입점 ───────────────────────────────────────────────────────
  // 이 프로젝트의 Dart 테스트에는 Firestore·Functions 페이크가 없다
  // ([PlaceCreateEligibility]와 같은 방식). 운영 코드는 null이라 실물
  // Firestore·콜러블을 그대로 쓴다.
  //
  // 제출 경로가 **서버까지 닿는지**를 위젯 테스트가 볼 수 있어야 해서 둔다 —
  // 입력값이 다 맞는데도 화면이 콜러블 호출 전에 조용히 멈추는 버그는 모델만
  // 검사해서는 잡히지 않는다(서버 로그에도 아무것도 남지 않는다).
  static Future<BusinessVerification> Function()? _fetchOverride;
  static Future<BusinessVerifyResult> Function(Map<String, dynamic> payload)?
  _verifyOverride;

  @visibleForTesting
  static void debugSetSource({
    Future<BusinessVerification> Function()? fetch,
    Future<BusinessVerifyResult> Function(Map<String, dynamic> payload)? verify,
  }) {
    _fetchOverride = fetch;
    _verifyOverride = verify;
  }

  @visibleForTesting
  static void debugResetSource() {
    _fetchOverride = null;
    _verifyOverride = null;
  }

  /// 마이페이지·등록 화면이 구독할 현재 인증 상태.
  static Stream<BusinessVerification> watch() {
    if (UserSession.userId.isEmpty) {
      return Stream.value(BusinessVerification.none);
    }
    return _userRef
        .snapshots()
        .map((s) => BusinessVerification.fromUserDoc(s.data()))
        .handleError(
          (e, st) => logFirestoreStreamError(
            'BusinessVerificationService.watch',
            e,
            st,
          ),
        );
  }

  /// 한 번만 읽기 — 등록 진입 시 "사업자 인증이 필요합니다" 판단용.
  static Future<BusinessVerification> fetch() async {
    final override = _fetchOverride;
    if (override != null) return override();
    if (UserSession.userId.isEmpty) return BusinessVerification.none;
    try {
      final snap = await _userRef.get();
      return BusinessVerification.fromUserDoc(snap.data());
    } catch (e, st) {
      logFirestoreStreamError('BusinessVerificationService.fetch', e, st);
      return BusinessVerification.none;
    }
  }

  /// 국세청 확인 요청. 서버가 결과를 기록하므로, 호출 후에는 [watch]/[fetch]가
  /// 새 상태를 돌려준다.
  ///
  /// ## 이미 인증을 마친 계정의 "사업자 정보 변경"도 같은 경로다
  ///
  /// 별도 콜러블을 만들지 않는다 — 인증 로직이 둘로 갈리면 한쪽만 고쳐서
  /// 규칙이 어긋난다. 서버가 기존 기록과 비교해 최초 인증인지 변경인지
  /// 스스로 판단하고, **새 정보가 국세청을 통과한 순간에만** 교체한다
  /// (businessVerification.js의 resolveVerificationWrite).
  ///
  /// 그래서 새 번호가 틀렸거나 국세청 API가 죽어도 기존 인증은 그대로다 —
  /// 그 경우 [BusinessVerifyResult.keptExistingVerification]이 true로 온다.
  ///
  /// 보내는 값은 두 축이다.
  ///   · [businessNumber]·[representativeName]·[openingDate] — 국세청 진위확인의
  ///     **판정 대상**. 서버가 이 셋으로만 통과/불통과를 가른다.
  ///   · [businessName]·[businessAddress] — 앱에 저장할 사업자 정보. 국세청
  ///     통과 조건은 아니지만(본점 주소와 실제 개최 장소가 다른 것이 정상)
  ///     **입력은 필수**라 화면이 빈 값으로는 여기까지 오지 않는다.
  ///
  /// 서버는 이 둘을 비어 있어도 받아준다 — 구버전 앱이 그대로 동작해야 하기
  /// 때문이다. 필수 판정은 화면(BusinessVerificationScreen)이 한다.
  ///
  /// 실패 시 [FirebaseFunctionsException]을 그대로 던진다 — 화면이 message를
  /// 그대로 보여주면 된다(서버가 한국어 안내 문구로 던진다).
  static Future<BusinessVerifyResult> verify({
    required String businessNumber,
    required String representativeName,
    required String openingDate,
    required String businessName,

    /// 기본주소 + 상세주소를 합친 **전체 주소 한 줄**. 옛 문서의
    /// businessAddress와 같은 형태라 저장 자리도 그대로다.
    required String businessAddress,

    /// 주소검색으로 고른 기본주소 / 사용자가 적은 상세주소 — 나눠서도 남긴다.
    required String businessBaseAddress,
    required String businessDetailAddress,
  }) async {
    final payload = <String, dynamic>{
      'businessNumber': businessNumber,
      'representativeName': representativeName,
      'openingDate': openingDate,
      'businessName': businessName,
      'businessAddress': businessAddress,
      'businessBaseAddress': businessBaseAddress,
      'businessDetailAddress': businessDetailAddress,
    };

    final override = _verifyOverride;
    if (override != null) return override(payload);

    final callable = FirebaseFunctions.instanceFor(
      region: _region,
    ).httpsCallable('verifyBusinessRegistration');

    final res = await callable.call<Map<String, dynamic>>(payload);

    return BusinessVerifyResult(
      status: BusinessVerificationStatus.fromKey(res.data['status'] as String?),
      authorization: BusinessAuthorization.fromKey(
        res.data['authorization'] as String?,
      ),
      authorizationReason: res.data['authorizationReason'] as String?,
      // 구버전 서버는 이 두 키를 보내지 않는다 — 그때는 예전처럼 status만
      // 보고 동작한다(false 기본값이 곧 예전 동작이다).
      keptExistingVerification:
          res.data['keptExistingVerification'] as bool? ?? false,
      numberChanged: res.data['numberChanged'] as bool? ?? false,
    );
  }
}

/// [BusinessVerificationService.verify]의 결과.
///
/// [status]·[authorization] 모두 **이번 시도**의 판정이고, 계정의 상태와
/// 다를 수 있다 — [keptExistingVerification]이 true면 이번 시도는 권한을
/// 얻지 못했지만 기존 권한은 그대로 살아 있다는 뜻이다.
class BusinessVerifyResult {
  const BusinessVerifyResult({
    required this.status,
    this.authorization = BusinessAuthorization.none,
    this.authorizationReason,
    this.keptExistingVerification = false,
    this.numberChanged = false,
  });

  final BusinessVerificationStatus status;
  final BusinessAuthorization authorization;
  final String? authorizationReason;
  final bool keptExistingVerification;
  final bool numberChanged;

  /// **사업자 권한까지 얻었는가** — 진위(status)만으로는 부족하다.
  ///
  /// ⚠️ 여기서는 `self`만 인정한다. [BusinessVerification.isVerified]는
  ///    `delegated`도 인정하지만 **근거 문서 id가 있을 때만**이고, 이 콜러블은
  ///    delegationId를 돌려주지 않는다. id 없이 delegated를 통과시키면 정본보다
  ///    넓은 판정이 되어, 계정은 막혀 있는데 화면만 "인증 완료"라고 말하는
  ///    상태가 만들어진다(이번 버그와 같은 모양).
  ///
  ///    실제로 이 콜러블은 delegated를 만들지 않는다 — 위임 권한은
  ///    functions/businessDelegation.js가 따로 기록한다. 나중에 여기서
  ///    delegated를 돌려주게 된다면 **delegationId도 함께** 내려주고 이 판정도
  ///    정본과 같은 조건으로 넓혀야 한다.
  bool get isVerified =>
      status == BusinessVerificationStatus.verified &&
      authorization == BusinessAuthorization.self;

  /// 사업자는 확인됐는데 권한만 없는 경우 — 실패로 안내하면 안 된다.
  bool get needsOwnerApproval =>
      status == BusinessVerificationStatus.verified &&
      authorization == BusinessAuthorization.pendingOwnerApproval;

  /// 화면에 그대로 쓰는 안내 문구 — 문구의 정본은 모델 하나뿐이다.
  String get guidance => BusinessVerification(
    status: status,
    authorization: authorization,
    authorizationReason: authorizationReason,
  ).guidance;
}
