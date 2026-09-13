/// 사업자 인증 상태 — `users/{uid}.businessVerification` 맵을 읽는 모델.
///
/// 이 문서는 본인과 관리자만 읽을 수 있고(firestore.rules users 규칙),
/// 클라이언트는 쓰기가 완전히 막혀 있다. 값을 만드는 곳은 국세청 진위확인을
/// 실제로 호출하는 `verifyBusinessRegistration`(Cloud Functions) 하나뿐이다.
///
/// ⚠️ `settlementInfo.hostType`('개인'/'사업자')과 혼동하면 안 된다. 그쪽은
/// 정산 화면에서 사용자가 직접 고르는 값이라 권한 판정에 쓸 수 없다.
///
/// ── 상태는 두 축이다 ──────────────────────────────────────────────────
/// [BusinessVerificationStatus]  국세청이 확인한 **사업자 정보의 진위**
/// [BusinessAuthorization]       이 계정이 그 사업자를 **쓸 수 있는 권한**
///
/// 사업자등록번호·대표자명·개업일자는 사업자등록증 사본 한 장에 전부 적혀
/// 있어서, 진위만으로는 남의 사업자로도 통과한다. 그래서 **권한의 근거는
/// 둘을 모두 만족하는 [BusinessVerification.isVerified] 하나뿐이다** —
/// 화면이 `status == verified`를 직접 보면 그 순간 우회로가 생긴다.
enum BusinessVerificationStatus {
  /// 아직 인증을 시도하지 않음.
  unverified('unverified', '미인증'),

  /// 국세청 확인을 끝내지 못함(API 장애·서비스키 미등록 등). 다시 시도하면 된다.
  pending('pending', '심사 필요'),

  /// 통과 — 사업자등록번호·대표자명·개업일자가 일치하고 계속사업자다.
  verified('verified', '인증 완료'),

  /// 등록되지 않은 번호이거나 입력 정보가 국세청 등록정보와 다르다.
  failed('failed', '인증 실패'),

  /// 실존하지만 휴업 또는 폐업 상태다.
  suspended('suspended', '휴·폐업 확인 필요');

  const BusinessVerificationStatus(this.key, this.label);

  final String key;
  final String label;

  static BusinessVerificationStatus fromKey(String? key) {
    for (final s in BusinessVerificationStatus.values) {
      if (s.key == key) return s;
    }
    return BusinessVerificationStatus.unverified;
  }
}

/// 이 계정이 사업자를 **쓸 수 있는 권한** — `businessVerification.authorization`.
///
/// 서버(functions/businessVerification.js)만 기록한다. 클라이언트는 이 맵
/// 전체를 쓸 수 없다(firestore.rules users 잠금 필드).
enum BusinessAuthorization {
  /// 사업자 확인 자체가 성립하지 않았다(status != verified).
  none('none', '권한 없음'),

  /// NICE 본인확인 실명이 국세청이 확인한 대표자명과 일치하고, 사업자번호
  /// 점유까지 성공했다.
  ///
  /// ⚠️ 이름이 같다는 것이 동일인의 증명은 아니다 — 동명이인은 이 판정을
  ///    그대로 통과한다. 국세청 응답에 대표자의 CI·생년월일·연락처가 없어
  ///    현재 계약 범위에서 더 좁힐 방법이 없다.
  ///
  ///    서버가 그 사업자에 대표자 CI를 적어 두기는 하지만, 그 값도 **이름
  ///    대조로 얻은 것**이라 "확인된 대표자"가 아니다. 그것이 해주는 일은
  ///    서로 다른 CI가 같은 사업자의 대표자를 주장할 때 **충돌을 자동으로
  ///    알아채고 멈추는 것**뿐이다(functions/businessVerification.js의
  ///    REP_VERIFICATION_LEVEL).
  self('self', '본인 명의 확인'),

  /// 대표자가 NICE 본인확인을 마친 뒤 이 계정에 운영 권한을 명시적으로
  /// 부여했다. 근거 문서 id가 [BusinessVerification.delegationId]에 함께 적힌다.
  ///
  /// 대표자가 언제든 취소할 수 있고, 취소되면 곧바로 [pendingOwnerApproval]로
  /// 돌아간다(권한만 닫히고 사업자 진위는 그대로다).
  delegated('delegated', '대표자 위임'),

  /// 사업자는 확인됐지만 이 계정의 사용 권한은 아직 없다.
  /// (대표자명이 본인과 다르거나, 다른 계정이 이미 그 사업자를 쓰고 있다.)
  pendingOwnerApproval('pendingOwnerApproval', '대표자 확인 필요');

  const BusinessAuthorization(this.key, this.label);

  final String key;
  final String label;

  /// 모르는 값·빈 값은 전부 [none]이다 — 판정을 못 했을 때 권한을 주지
  /// 않는다(fail-closed). 서버가 authorization을 쓰기 전에 저장된 문서도
  /// 여기로 떨어져 권한이 열리지 않는다.
  static BusinessAuthorization fromKey(String? key) {
    for (final a in BusinessAuthorization.values) {
      if (a.key == key) return a;
    }
    return BusinessAuthorization.none;
  }
}

/// 권한이 열리지 않은 이유 — `businessVerification.authorizationReason`.
class BusinessAuthReason {
  BusinessAuthReason._();

  /// NICE 실명과 국세청이 확인한 대표자명이 다르다(타인 명의).
  static const representativeMismatch = 'representativeMismatch';

  /// 이 사업자번호를 이미 다른 계정이 쓰고 있다.
  static const ownedByAnotherAccount = 'ownedByAnotherAccount';

  /// 이름은 같지만, 이 사업자에 **기존에 확인된 대표자 본인확인 정보와
  /// 일치하지 않는다.**
  ///
  /// ⚠️ "이 사람이 대표자가 아니다"라는 뜻이 아니다. 기존 값도 이름 대조로
  ///    얻은 것이라 먼저 확인된 쪽이 진짜라는 보장이 없다 — 이것은 **충돌
  ///    감지**이지 판정이 아니고, 어느 쪽이 맞는지는 사람이 정한다.
  static const representativeCiMismatch = 'representativeCiMismatch';

  /// 대표자가 부여했던 운영 권한을 취소했다.
  static const delegationRevoked = 'delegationRevoked';
}

/// 진행 중이던 **사업자 정보 변경 시도** 중 실패한 마지막 건
/// (`businessVerification.pendingChange`).
///
/// 이 칸이 있다는 것은 "새 사업자정보로 다시 인증해봤지만 아직 통과하지
/// 못했다"는 뜻이다. **계정의 인증 상태는 여전히 [BusinessVerification.status]**
/// 이고, 이 값은 화면이 "무엇 때문에 실패했는지"를 알려주기 위한 부속 정보다.
/// 새 인증이 성공하는 순간 서버가 이 칸을 지운다(businessVerification.js의
/// resolveVerificationWrite).
class BusinessChangeAttempt {
  const BusinessChangeAttempt({
    required this.status,
    this.authorization = BusinessAuthorization.none,
    this.authorizationReason,
    this.businessNumber = '',
    this.representativeName = '',
    this.openingDate = '',
    this.businessName = '',
    this.businessAddress = '',
    this.businessBaseAddress = '',
    this.businessDetailAddress = '',
    this.failReason,
  });

  final BusinessVerificationStatus status;

  /// 이 변경 시도가 권한까지 얻었는지 — 국세청은 통과했는데 대표자명이
  /// 달라 막힌 경우를 '인증 실패'와 갈라 보여주기 위해 함께 담는다.
  final BusinessAuthorization authorization;
  final String? authorizationReason;
  final String businessNumber;
  final String representativeName;
  final String openingDate;
  final String businessName;
  final String businessAddress;
  final String businessBaseAddress;
  final String businessDetailAddress;
  final String? failReason;

  /// 왜 실패했는지 — 기존 인증 상태 문구와 섞이지 않게 별도로 만든다.
  /// 문구 자체는 [BusinessVerification.guidance]를 그대로 재사용한다.
  String get guidance => BusinessVerification(
    status: status,
    authorization: authorization,
    authorizationReason: authorizationReason,
    failReason: failReason,
  ).guidance;

  /// '123-45-67890'.
  String get formattedBusinessNumber => BusinessVerification(
    status: status,
    businessNumber: businessNumber,
  ).formattedBusinessNumber;

  static BusinessChangeAttempt? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    return BusinessChangeAttempt(
      status: BusinessVerificationStatus.fromKey(map['status'] as String?),
      authorization: BusinessAuthorization.fromKey(
        map['authorization'] as String?,
      ),
      authorizationReason: map['authorizationReason'] as String?,
      businessNumber: map['businessNumber'] as String? ?? '',
      representativeName: map['representativeName'] as String? ?? '',
      openingDate: map['openingDate'] as String? ?? '',
      businessName: map['businessName'] as String? ?? '',
      businessAddress: map['businessAddress'] as String? ?? '',
      businessBaseAddress: map['businessBaseAddress'] as String? ?? '',
      businessDetailAddress: map['businessDetailAddress'] as String? ?? '',
      failReason: map['failReason'] as String?,
    );
  }
}

class BusinessVerification {
  const BusinessVerification({
    required this.status,
    this.authorization = BusinessAuthorization.none,
    this.authorizationReason,
    this.delegationId = '',
    this.businessNumber = '',
    this.representativeName = '',
    this.openingDate = '',
    this.businessName = '',
    this.businessAddress = '',
    this.businessBaseAddress = '',
    this.businessDetailAddress = '',
    this.ntsStatusLabel = '',
    this.taxType = '',
    this.failReason,
    this.nameMatched,
    this.addressMatched,
    this.pendingChange,
    this.previousBusinessNumber = '',
  });

  final BusinessVerificationStatus status;

  /// 이 계정이 그 사업자를 쓸 수 있는가 — [status]와 **함께 봐야** 한다.
  final BusinessAuthorization authorization;

  /// 권한이 열리지 않은 이유([BusinessAuthReason]).
  final String? authorizationReason;

  /// [BusinessAuthorization.delegated]일 때 그 근거가 된 위임 문서 id.
  ///
  /// **비어 있는 delegated는 권한으로 인정하지 않는다** — 서버의
  /// isBusinessAuthorized()·firestore.rules와 같은 조건이다. 셋은 항상
  /// 함께 쓰이므로, id가 빈 delegated는 어떤 정상 경로로도 만들어지지 않는다.
  final String delegationId;
  final String businessNumber;
  final String representativeName;

  /// yyyymmdd.
  final String openingDate;

  /// 상호명. 국세청 통과 조건은 아니지만 입력은 필수다
  /// (BusinessVerificationScreen). **기본값 ''는 그대로 둔다** — 이 필드가
  /// 필수가 되기 전에 인증을 마친 문서에는 값이 없을 수 있다.
  final String businessName;

  /// 사업자등록증상 주소. **실제 파티/플레이스 개최 주소와는 별개다** —
  /// 한 사업자가 여러 매장을 운영하거나 본점 주소가 다를 수 있으므로
  /// 콘텐츠 주소와 일치할 것을 강제하지 않는다.
  final String businessAddress;

  /// 주소검색으로 고른 기본주소 / 사용자가 적은 상세주소.
  ///
  /// [businessAddress]가 정본이고 이 둘은 그것을 나눠 담은 값이다. **기본값 ''를
  /// 그대로 둔다** — 주소를 나눠 저장하기 전에 인증을 마친 문서에는 두 키가
  /// 아예 없다(그 문서는 [businessAddress] 한 덩어리만 갖고 있다).
  final String businessBaseAddress;
  final String businessDetailAddress;

  final String ntsStatusLabel;
  final String taxType;
  final String? failReason;

  /// 상호명/주소 대조 결과 — null은 "판단하지 않음"이다(국세청이 이 두
  /// 항목을 일치/불일치로 단정해주지 않는다). false여도 인증은 통과한다.
  final bool? nameMatched;
  final bool? addressMatched;

  /// 아직 통과하지 못한 **사업자 정보 변경 시도**. null이면 진행 중인 변경이
  /// 없다는 뜻이다. 이 값이 있어도 위 [status]는 그대로다 — 변경은 성공한
  /// 순간에만 반영되기 때문이다([BusinessChangeAttempt]).
  final BusinessChangeAttempt? pendingChange;

  /// 사업자번호를 바꿔 재인증했을 때 남는 직전 번호(감사용). 사용자 화면에는
  /// 쓰지 않는다 — 관리자 화면과 운영 추적용이다.
  final String previousBusinessNumber;

  static const none = BusinessVerification(
    status: BusinessVerificationStatus.unverified,
  );

  /// **사업자 권한의 유일한 판정식** — 진위와 권한을 둘 다 본다.
  ///
  /// 서버의 isBusinessAuthorized()와 firestore.rules의 isBusinessVerified()가
  /// 같은 두 조건을 각자의 문법으로 다시 쓴다. 셋이 갈리면 '앱은 열어줬는데
  /// 서버가 막는' 상태가 되므로, 조건을 바꿀 때는 세 곳을 함께 본다.
  bool get isVerified =>
      status == BusinessVerificationStatus.verified &&
      (authorization == BusinessAuthorization.self ||
          (authorization == BusinessAuthorization.delegated &&
              delegationId.isNotEmpty));

  /// 국세청 확인은 끝났는데 **이 계정의 사용 권한이 없는** 상태 전부.
  ///
  /// ⚠️ 화면은 반드시 이 값을 보고 갈라야 한다. `status`만 보고 그리면
  ///    '인증 완료'라고 말하면서 등록은 막는 모순 상태가 만들어진다 —
  ///    사용자는 완료 화면과 차단 안내 사이를 무한히 오간다.
  bool get verifiedWithoutAuthorization =>
      status == BusinessVerificationStatus.verified && !isVerified;

  /// 사업자는 확인됐는데 **권한만 없는** 상태.
  ///
  /// 이것은 실패가 아니다 — 사업자등록 정보는 국세청에서 맞다고 확인됐고,
  /// 다만 이 계정이 그 사업자의 대표자가 아닐 뿐이다. 화면이 '인증 실패'로
  /// 말하면 사용자는 입력이 틀린 줄 알고 같은 값을 계속 다시 넣는다.
  ///
  /// 여기서 풀 방법은 **다른 사람(대표자)의 행동**뿐이라, 아래
  /// [needsReverification]과 갈라 둔다.
  bool get needsOwnerApproval =>
      status == BusinessVerificationStatus.verified &&
      authorization == BusinessAuthorization.pendingOwnerApproval;

  /// 권한이 없지만 **본인이 다시 확인하기만 하면 풀리는** 상태.
  ///
  /// 대부분은 권한 축(authorization)이 생기기 **전에** 인증을 마친 계정이다.
  /// 그 문서에는 authorization 키가 아예 없어 [BusinessAuthorization.none]으로
  /// 읽히고, 그래서 진위는 verified인데 권한은 열리지 않는다. 같은 정보로 한 번
  /// 더 확인을 돌리면 서버가 그때 권한을 판정해 기록한다
  /// (functions/businessVerification.js의 decideAuthorization).
  ///
  /// 근거 문서 id가 빈 `delegated`(정상 경로로는 만들어지지 않는 값)도 여기로
  /// 온다 — 역시 다시 확인하면 서버가 새로 판정한다.
  ///
  /// ⚠️ 이 상태를 '인증 완료'로 되돌려 통과시키면 안 된다. 권한 판정을
  ///    되돌리는 것이 아니라, **화면이 실제 상태를 말하게 하고 다시 확인할
  ///    길을 여는 것**이 이 값의 목적이다.
  bool get needsReverification =>
      verifiedWithoutAuthorization && !needsOwnerApproval;

  /// 다시 시도해볼 만한 상태인가(입력을 고치거나 API 복구를 기다리면 된다).
  ///
  /// 권한까지 얻지 못했으면 여기 해당한다 — 대표자명을 잘못 친 사용자가
  /// 다시 입력할 길이 있어야 한다(그렇지 않으면 화면이 막다른 길이 된다).
  bool get canRetry => !isVerified;

  /// 이미 인증을 마쳐서 "사업자 정보 변경"으로 들어가야 하는 상태인가.
  ///
  /// 사업자등록번호는 법인 전환·업종 변경·폐업 후 재개업으로 바뀔 수 있어서,
  /// 인증 완료가 곧 마지막 상태는 아니다.
  bool get canChange => isVerified;

  /// 실패한 채로 남아 있는 변경 시도가 있는가.
  bool get hasPendingChange => pendingChange != null;

  /// 상태 카드의 제목. 권한이 없는데 '인증 완료'라고 쓰면 거짓말이 된다.
  String get headline {
    // 이 상태는 **실패가 아니다.** 사업자 정보는 국세청에서 확인이 끝났고
    // 남은 것은 대표자 확인 하나뿐이라, 제목은 끝난 사실부터 말한다.
    // 무엇이 남았는지는 바로 아래 [guidance]가 이어서 말한다 — 제목까지
    // "필요해요"로 시작하면 사용자는 인증이 실패한 줄로 읽는다.
    if (needsOwnerApproval) return '사업자 정보는 확인됐어요';
    if (needsReverification) return '사업자 권한 확인이 필요해요';
    return status.label;
  }

  /// 사용자에게 보여줄 안내 문구.
  String get guidance {
    // 권한 축을 **먼저** 본다 — 이 두 경우 status는 'verified'라서 아래 switch를
    // 그대로 태우면 '인증 완료'라고 안내하게 된다(등록은 막히는데).
    if (needsReverification) {
      return '사업자 정보는 국세청에서 확인됐지만, 이 계정이 그 사업자를 쓸 수 있는지는 '
          '아직 확인되지 않았어요. 저장된 정보 그대로 한 번만 다시 확인하면 바로 '
          '사용할 수 있어요.';
    }
    if (needsOwnerApproval) {
      switch (authorizationReason) {
        case BusinessAuthReason.delegationRevoked:
          return '대표자가 운영 권한을 취소했어요. '
              '다시 사용하시려면 대표자에게 승인을 다시 받아주세요.';
        case BusinessAuthReason.representativeCiMismatch:
          // 사용자에게 "당신이(또는 그분이) 대표자가 아니다"라고 말하지 않는다.
          // 우리가 아는 것은 두 본인확인 정보가 다르다는 사실뿐이다.
          return '이 사업자에 기존에 확인된 대표자 본인확인 정보와 일치하지 않아 '
              '자동으로 처리할 수 없어요. 고객센터로 문의해주세요.';
        case BusinessAuthReason.ownedByAnotherAccount:
          return '이미 다른 계정에서 사용 중인 사업자등록번호예요. '
              '대표자의 승인이 필요해요.';
        default:
          // 기본 사유는 '가입자 실명 != 대표자명'이다. 왜 막혔는지를 사용자가
          // 아는 말로만 적는다 — 내부 용어(authorization·pendingOwnerApproval
          // 같은 값 이름)는 화면에 절대 내보내지 않는다.
          return '가입자와 대표자 이름이 달라 대표자 확인이 필요합니다. '
              '대표자명을 잘못 입력했다면 다시 확인해주세요.';
      }
    }
    switch (status) {
      case BusinessVerificationStatus.verified:
        // 여기 닿았다는 것은 위 두 갈래를 지났다는 뜻이라 **권한까지 열린**
        // 상태다(isVerified). 그래서 두 축을 모두 말한다 — 진위만 확인된
        // 상태에서 이 문구가 나오면 그 자체가 이번 버그다.
        return '국세청 확인과 사업자 권한 확인이 모두 끝났어요. '
            '이제 파티와 플레이스를 등록할 수 있어요.';
      case BusinessVerificationStatus.pending:
        return failReason == 'apiKeyMissing'
            ? '국세청 확인 준비가 아직 끝나지 않았어요. 잠시 후 다시 시도해주세요.'
            : '국세청 확인이 일시적으로 어려웠어요. 잠시 후 다시 시도해주세요.';
      case BusinessVerificationStatus.failed:
        return failReason == 'notRegistered'
            ? '국세청에 등록되지 않은 사업자등록번호예요. 번호를 다시 확인해주세요.'
            : '입력하신 사업자등록 정보가 국세청 등록정보와 일치하지 않아요. '
                  '사업자등록증의 사업자등록번호·대표자명·개업일자를 확인해주세요.';
      case BusinessVerificationStatus.suspended:
        return failReason == 'closed'
            ? '폐업 상태로 조회됐어요. 현재 운영 중인 사업자만 인증할 수 있어요.'
            : '휴업 상태로 조회됐어요. 영업을 재개한 뒤 다시 시도해주세요.';
      case BusinessVerificationStatus.unverified:
        return '사업자등록증에 적힌 그대로 입력하면 국세청에서 바로 확인해드려요.';
    }
  }

  /// 사업자등록번호 표시용 — '123-45-67890'.
  String get formattedBusinessNumber {
    final d = businessNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length != 10) return businessNumber;
    return '${d.substring(0, 3)}-${d.substring(3, 5)}-${d.substring(5)}';
  }

  /// 개업일자 표시용 — '2020.01.05'.
  String get formattedOpeningDate {
    final d = openingDate.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length != 8) return openingDate;
    return '${d.substring(0, 4)}.${d.substring(4, 6)}.${d.substring(6)}';
  }

  static BusinessVerification fromMap(Map<String, dynamic>? map) {
    if (map == null) return none;
    return BusinessVerification(
      status: BusinessVerificationStatus.fromKey(map['status'] as String?),
      authorization: BusinessAuthorization.fromKey(
        map['authorization'] as String?,
      ),
      authorizationReason: map['authorizationReason'] as String?,
      delegationId: map['delegationId'] as String? ?? '',
      businessNumber: map['businessNumber'] as String? ?? '',
      representativeName: map['representativeName'] as String? ?? '',
      openingDate: map['openingDate'] as String? ?? '',
      businessName: map['businessName'] as String? ?? '',
      businessAddress: map['businessAddress'] as String? ?? '',
      businessBaseAddress: map['businessBaseAddress'] as String? ?? '',
      businessDetailAddress: map['businessDetailAddress'] as String? ?? '',
      ntsStatusLabel: map['ntsStatusLabel'] as String? ?? '',
      taxType: map['taxType'] as String? ?? '',
      failReason: map['failReason'] as String?,
      nameMatched: map['nameMatched'] as bool?,
      addressMatched: map['addressMatched'] as bool?,
      // 서버가 성공 시 null로 지우므로 Map이 아닌 값이 그대로 올 수 있다.
      pendingChange: BusinessChangeAttempt.fromMap(
        map['pendingChange'] is Map
            ? Map<String, dynamic>.from(map['pendingChange'] as Map)
            : null,
      ),
      previousBusinessNumber: map['previousBusinessNumber'] as String? ?? '',
    );
  }

  /// 유저 문서 전체에서 꺼내기.
  static BusinessVerification fromUserDoc(Map<String, dynamic>? user) =>
      fromMap(
        user == null
            ? null
            : (user['businessVerification'] as Map<String, dynamic>?),
      );
}
