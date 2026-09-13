/// `users/{uid}.businessVerification` 맵을 관리자 화면에서 읽기 위한 모델.
///
/// ⚠️ **새로 저장하는 값이 하나도 없다.** 이 맵은 국세청 진위확인을 실제로
/// 호출하는 `verifyBusinessRegistration`(functions/businessVerification.js)이
/// Admin SDK로만 쓰고, 클라이언트 쓰기는 규칙이 완전히 막아둔 곳이다. 관리자
/// 화면은 그 값을 **그대로 읽기만** 한다 — 가입일·UID·이메일 같은 계정정보도
/// 회원 문서에 이미 있는 값을 쓰고 여기에 중복 저장하지 않는다.
///
/// admin_app은 party_app과 별개 Flutter 프로젝트라 party_app의
/// business_verification.dart를 import할 수 없어, 화면에 필요한 만큼만
/// 같은 필드 이름으로 다시 정의한다(admin_firestore_service.dart의
/// kRegions1이 RegionData를 복제하는 것과 같은 이유).
///
/// ⚠️ `settlementInfo.hostType`('개인'/'사업자')과 혼동하면 안 된다. 그쪽은
/// 정산 화면에서 사용자가 **직접 고르는 자기신고 값**이라 사업자 여부의 근거로
/// 쓸 수 없다. 이 화면이 "사업자"라고 부르는 것은 언제나 아래 상태값이다.
///
/// ── 상태는 두 축이다 ──────────────────────────────────────────────────
/// [BizStatus]           국세청이 확인한 **사업자 정보의 진위**
/// [BizAuthorization]    이 계정이 그 사업자를 **쓸 수 있는 권한**
///
/// 사업자등록증 사본 한 장이면 진위 3항목이 전부 나오므로, [BizStatus]만으로는
/// 남의 사업자로도 `verified`가 된다. 그래서 **관리자 화면이 '인증 완료'라고
/// 말해도 되는 조건은 [BusinessInfo.isVerified](둘 다 만족) 하나뿐이다.**
enum BizStatus {
  /// businessVerification 맵 자체가 없음 = 사업자 인증을 시도한 적 없는 일반회원.
  none('', '일반회원'),
  unverified('unverified', '미인증'),

  /// 국세청 확인을 끝내지 못함(API 장애·서비스키 미등록 등).
  pending('pending', '심사 필요'),

  /// 통과 — 사업자등록번호·대표자명·개업일자 일치 + 계속사업자.
  verified('verified', '인증 완료'),

  /// 등록되지 않은 번호이거나 입력 정보가 국세청 등록정보와 다름.
  failed('failed', '인증 실패'),

  /// 실존하지만 휴업 또는 폐업 상태.
  suspended('suspended', '휴·폐업');

  const BizStatus(this.key, this.label);
  final String key;
  final String label;

  static BizStatus fromKey(String? key) {
    if (key == null || key.isEmpty) return BizStatus.none;
    for (final s in BizStatus.values) {
      if (s.key == key) return s;
    }
    return BizStatus.unverified;
  }
}

/// 이 계정이 사업자를 **쓸 수 있는 권한** — `businessVerification.authorization`.
///
/// 서버(functions/businessVerification.js)만 기록한다.
enum BizAuthorization {
  /// 사업자 확인 자체가 성립하지 않았거나, 아직 이 필드를 쓰기 전의 문서.
  none('none', '권한 없음'),

  /// NICE 본인확인 실명 == 국세청이 확인한 대표자명 + 사업자번호 점유 성공.
  self('self', '본인 명의'),

  /// 대표자가 NICE 본인확인 후 이 계정에 운영 권한을 명시적으로 부여했다.
  /// (functions/businessDelegation.js — businessDelegations 문서가 정본)
  delegated('delegated', '대표자 위임'),

  /// 사업자는 확인됐지만 이 계정의 사용 권한은 없다(타인 명의 · 중복 점유).
  pendingOwnerApproval('pendingOwnerApproval', '대표자 확인 필요');

  const BizAuthorization(this.key, this.label);
  final String key;
  final String label;

  /// 모르는 값·빈 값은 전부 [none] — 판정을 못 했을 때 권한을 인정하지 않는다.
  static BizAuthorization fromKey(String? key) {
    for (final a in BizAuthorization.values) {
      if (a.key == key) return a;
    }
    return BizAuthorization.none;
  }
}

class BusinessInfo {
  const BusinessInfo({
    required this.status,
    this.authorization = BizAuthorization.none,
    this.authorizationReason,
    this.delegationId = '',
    this.businessNumber = '',
    this.businessName = '',
    this.representativeName = '',
    this.businessAddress = '',
    this.openingDate = '',
    this.ntsStatusLabel = '',
    this.taxType = '',
    this.failReason,
    this.verifiedAt,
    this.lastCheckedAt,
    this.previousBusinessNumber = '',
    this.changeCount = 0,
    this.pendingChangeBusinessNumber = '',
    this.pendingChangeStatus = BizStatus.none,
    this.pendingChangeFailReason,
    this.pendingChangeAuthorization = BizAuthorization.none,
  });

  final BizStatus status;

  /// 권한 축 — [status]와 **함께 봐야** 한다.
  final BizAuthorization authorization;

  /// 권한이 열리지 않은 이유('representativeMismatch' ·
  /// 'representativeCiMismatch' · 'ownedByAnotherAccount' · 'delegationRevoked').
  final String? authorizationReason;

  /// authorization == delegated일 때 그 근거가 된 businessDelegations 문서 id.
  final String delegationId;
  final String businessNumber;
  final String businessName;
  final String representativeName;
  final String businessAddress;

  /// yyyymmdd 원문.
  final String openingDate;

  /// 국세청 납세자 상태 문구('계속사업자'/'휴업자'/'폐업자').
  final String ntsStatusLabel;
  final String taxType;
  final String? failReason;

  /// **현재 사업자번호가 처음 통과한 시각.** 같은 번호를 다시 확인한 것만으로는
  /// 갱신되지 않고, 사업자번호를 바꿔 재인증하면 새 사업자의 인증일로 다시
  /// 잡힌다(functions/businessVerification.js의 resolveVerificationWrite).
  final DateTime? verifiedAt;
  final DateTime? lastCheckedAt;

  /// 사업자번호를 바꿔 재인증했을 때 남는 **직전 번호**(감사용).
  /// 비어 있으면 한 번도 교체한 적이 없다는 뜻이다.
  final String previousBusinessNumber;

  /// 사업자번호를 교체한 횟수.
  final int changeCount;

  /// 아직 통과하지 못한 **변경 시도**가 있으면 그 사업자번호.
  ///
  /// 이 값이 있어도 위 [status]와 [businessNumber]는 **여전히 인증된 사업자의
  /// 것**이다 — 변경은 새 정보가 국세청을 통과한 순간에만 반영되므로, 실패한
  /// 시도가 기존 인증을 흔들지 않는다. 운영에서 "바꾸려다 막힌 사람"을 찾을 때
  /// 쓰라고 남긴다.
  final String pendingChangeBusinessNumber;

  /// 그 변경 시도가 어디서 막혔는지(status/failReason).
  final BizStatus pendingChangeStatus;
  final String? pendingChangeFailReason;

  /// 그 변경 시도가 **권한까지 얻었는지**.
  ///
  /// ⚠️ 이것을 빼먹으면 관리자 화면이 거짓말을 한다. 타인 명의 사업자로 바꾸려던
  /// 시도는 국세청은 통과하므로 `pendingChangeStatus`가 `verified`다 — 그것만
  /// 보여주면 "변경 시도 중: 222-22-22222 — 인증 완료"가 되어 변경이 성공한
  /// 것처럼 읽힌다. 실제로는 대표자 승인을 기다리는 중이다.
  final BizAuthorization pendingChangeAuthorization;

  bool get hasPendingChange => pendingChangeBusinessNumber.isNotEmpty;

  /// 변경 시도의 실제 상태 한 줄 — [statusLabel]과 같은 규칙을 시도 쪽에 적용한다.
  String get pendingChangeStatusLabel =>
      pendingChangeStatus == BizStatus.verified &&
          pendingChangeAuthorization != BizAuthorization.self &&
          pendingChangeAuthorization != BizAuthorization.delegated
      ? '대표자 확인 필요'
      : pendingChangeStatus.label;

  static const none = BusinessInfo(status: BizStatus.none);

  /// 사업자 여부 — 인증을 **시도한 적이 있으면** 사업자 회원으로 본다.
  /// (통과 여부는 [isVerified]로 따로 표시한다. 심사 중이거나 실패한 사람도
  /// 일반회원과는 구분해서 보여야 운영에서 후속 처리를 할 수 있다.)
  bool get isBusiness => status != BizStatus.none;

  /// **권한까지 열린 사업자인가** — 진위(status)만으로는 부족하다.
  /// party_app의 BusinessVerification.isVerified, 서버의
  /// isBusinessAuthorized(), firestore.rules의 isBusinessVerified()와
  /// 같은 판정식이다(넷이 갈리면 화면마다 다른 사실을 말하게 된다).
  bool get isVerified =>
      status == BizStatus.verified &&
      (authorization == BizAuthorization.self ||
          authorization == BizAuthorization.delegated);

  /// 사업자는 확인됐는데 권한만 없는 상태 — 실패가 아니다.
  bool get needsOwnerApproval =>
      status == BizStatus.verified &&
      authorization == BizAuthorization.pendingOwnerApproval;

  /// 목록·상세에 그대로 쓰는 한 줄 상태 문구.
  String get statusLabel =>
      needsOwnerApproval ? '대표자 확인 필요' : status.label;

  /// 권한이 열리지 않은 이유를 **정확한 한국어로** 옮긴다.
  ///
  /// ⚠️ representativeCiMismatch를 "대표자가 아님"으로 옮기면 안 된다. 서버가
  /// 사업자에 적어 두는 대표자 CI는 **이름 대조로 얻은 값**이라(그 사업자에
  /// 대해 대표자라고 주장하며 본인확인을 통과한 사람), 먼저 확인된 쪽이
  /// 진짜라는 보장이 없다. 동명이인이 먼저 확인을 마쳤다면 나중에 온 실제
  /// 대표자가 여기 걸린다 — 그래서 이것은 **충돌 감지**이지 판정이 아니다.
  /// (functions/businessVerification.js의 REP_VERIFICATION_LEVEL 참고)
  String get authorizationReasonLabel {
    switch (authorizationReason) {
      case 'representativeMismatch':
        return 'NICE 실명 ≠ 국세청 대표자명';
      case 'representativeCiMismatch':
        return '기존에 확인된 대표자 본인확인 정보와 불일치 — 어느 쪽이 실제 '
            '대표자인지는 확인 필요';
      case 'ownedByAnotherAccount':
        return '다른 계정이 이미 이 사업자를 사용 중';
      case 'delegationRevoked':
        return '대표자가 위임을 취소함';
      default:
        return authorizationReason ?? '';
    }
  }

  /// '123-45-67890'.
  String get formattedBusinessNumber {
    final d = businessNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length != 10) return businessNumber.isEmpty ? '-' : businessNumber;
    return '${d.substring(0, 3)}-${d.substring(3, 5)}-${d.substring(5)}';
  }

  /// '2020.01.05'.
  String get formattedOpeningDate {
    final d = openingDate.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length != 8) return openingDate.isEmpty ? '-' : openingDate;
    return '${d.substring(0, 4)}.${d.substring(4, 6)}.${d.substring(6)}';
  }

  static DateTime? _ts(dynamic v) {
    // cloud_firestore Timestamp를 import 없이 다루기 위해 duck typing —
    // 이 모델은 화면 표시 전용이라 Firestore 타입에 의존하지 않는다.
    if (v == null) return null;
    try {
      return (v as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }

  /// 회원 문서 전체에서 꺼낸다. 맵이 없으면 [none](= 일반회원).
  static BusinessInfo fromUserDoc(Map<String, dynamic>? user) {
    final map = user?['businessVerification'];
    if (map is! Map) return none;
    final m = Map<String, dynamic>.from(map);
    final rawPending = m['pendingChange'];
    final pending = rawPending is Map
        ? Map<String, dynamic>.from(rawPending)
        : null;
    return BusinessInfo(
      status: BizStatus.fromKey(m['status'] as String?),
      authorization: BizAuthorization.fromKey(m['authorization'] as String?),
      authorizationReason: m['authorizationReason'] as String?,
      delegationId: m['delegationId'] as String? ?? '',
      businessNumber: m['businessNumber'] as String? ?? '',
      businessName: m['businessName'] as String? ?? '',
      representativeName: m['representativeName'] as String? ?? '',
      businessAddress: m['businessAddress'] as String? ?? '',
      openingDate: m['openingDate'] as String? ?? '',
      ntsStatusLabel: m['ntsStatusLabel'] as String? ?? '',
      taxType: m['taxType'] as String? ?? '',
      failReason: m['failReason'] as String?,
      verifiedAt: _ts(m['verifiedAt']),
      lastCheckedAt: _ts(m['lastCheckedAt']),
      previousBusinessNumber: m['previousBusinessNumber'] as String? ?? '',
      changeCount: (m['changeCount'] as num?)?.toInt() ?? 0,
      // 성공하면 서버가 null로 지우므로 Map이 아닌 값이 그대로 올 수 있다.
      pendingChangeBusinessNumber: pending?['businessNumber'] as String? ?? '',
      pendingChangeStatus: BizStatus.fromKey(pending?['status'] as String?),
      pendingChangeFailReason: pending?['failReason'] as String?,
      pendingChangeAuthorization: BizAuthorization.fromKey(
        pending?['authorization'] as String?,
      ),
    );
  }

  /// '123-45-67890' — 임의의 사업자번호 문자열을 표시용으로 다듬는다.
  static String formatBusinessNumber(String raw) {
    final d = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length != 10) return raw.isEmpty ? '-' : raw;
    return '${d.substring(0, 3)}-${d.substring(3, 5)}-${d.substring(5)}';
  }
}
