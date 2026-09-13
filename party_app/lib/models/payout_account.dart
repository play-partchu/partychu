/// 호스트 **수취계좌** — 참가자가 무통장입금으로 돈을 보내는 계좌.
///
/// ── 이 앱의 계좌 세 가지 ──────────────────────────────────────────────────
///   1. 참가자 → **호스트**    = 이 모델 (users/{uid}.payoutAccount)
///   2. 파티츄 → 호스트        = 정산계좌 (users/{uid}.settlementInfo,
///      SettlementInfoScreen) — 플랫폼 정산이 생길 때 쓸 자리
///   3. 호스트/파티츄 → 참가자 = 환불계좌 (RefundAccountService)
///
/// 1과 2는 같은 계좌일 수 있지만 **역할이 다르다**. 지금 참가비가 실제로 오가는
/// 것은 1뿐이고, 2는 플랫폼 정산이 생길 때 쓸 자리다.
///
/// ── 클라이언트는 이 값을 쓰지 못한다 ─────────────────────────────────────
/// 계좌도 인증 상태도 서버(verifyPayoutAccount 콜러블)만 기록한다. 앱은 읽기만
/// 하고, 저장은 언제나 인증을 거친다 — "저장은 됐는데 인증은 안 된" 상태를
/// 따로 만들지 않기 위해서다(그 상태가 있으면 어느 계좌가 안내되는지 흐려진다).
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:party_app/models/bank_codes.dart';

/// 수취계좌 상태 — 서버 `functions/payoutAccounts.js`의 STATUS와 1:1.
enum PayoutAccountStatus {
  /// 미등록 — 아직 계좌를 넣은 적이 없다.
  none('none', '미등록'),

  /// 인증 필요 — 계좌는 있는데 확인되지 않았다(실패했거나, 계좌를 바꿨거나).
  required('required', '인증 필요'),

  /// 인증 완료 — 이 계좌만 참가자에게 안내된다.
  verified('verified', '인증 완료');

  const PayoutAccountStatus(this.key, this.label);

  final String key;
  final String label;

  static PayoutAccountStatus fromKey(String? key) {
    for (final s in values) {
      if (s.key == key) return s;
    }
    return PayoutAccountStatus.none;
  }

  bool get isVerified => this == PayoutAccountStatus.verified;
}

/// 입금을 받을 계좌의 **명의** — 서버 ACCOUNT_TYPE과 1:1.
///
/// 사업자 자격이나 사업자 인증 상태와는 아무 관계가 없다. 사업자 호스트가
/// 대표자 개인계좌를 골라도 사업자 인증은 그대로다 — 이 값은 "게스트가
/// 입금할 계좌의 명의가 개인인지 사업자인지"만 구분한다.
enum PayoutAccountType {
  personal('personal', '대표자 개인계좌'),
  business('business', '사업자 · 법인 계좌');

  const PayoutAccountType(this.key, this.label);

  final String key;
  final String label;

  /// 모르는 값·없는 값은 개인으로 읽는다 — 이 필드가 없던 기존 문서가
  /// 그대로 열려야 하고, 사업자 경로는 명시적으로 고른 경우에만 탄다.
  static PayoutAccountType fromKey(String? key) {
    for (final t in values) {
      if (t.key == key) return t;
    }
    return PayoutAccountType.personal;
  }
}

/// 인증이 실패한 이유 — 서버 FAIL_REASON과 1:1. 문구는 앱이 만든다.
enum PayoutAccountFailReason {
  notConfigured('notConfigured'),
  apiUnavailable('apiUnavailable'),
  accountNotFound('accountNotFound'),
  holderMismatch('holderMismatch'),
  identityMismatch('identityMismatch'),
  businessNotVerified('businessNotVerified'),
  businessHolderMismatch('businessHolderMismatch');

  const PayoutAccountFailReason(this.key);

  final String key;

  static PayoutAccountFailReason? fromKey(String? key) {
    if (key == null) return null;
    for (final r in values) {
      if (r.key == key) return r;
    }
    return null;
  }

  /// 호스트에게 그대로 보여줄 안내. "무엇을 하면 되는지"까지 적는다 —
  /// 이유만 알려주고 다음 행동을 안 알려주면 같은 실패를 반복한다.
  String get message => switch (this) {
    PayoutAccountFailReason.notConfigured =>
      '계좌 인증 서비스 준비 중이에요. 준비가 끝나면 알려드릴게요.',
    PayoutAccountFailReason.apiUnavailable =>
      '지금은 예금주 조회가 어려워요. 잠시 후 다시 시도해주세요.',
    PayoutAccountFailReason.accountNotFound =>
      '조회되지 않는 계좌예요. 금융기관과 계좌번호를 다시 확인해주세요.',
    PayoutAccountFailReason.holderMismatch => '입력한 예금주명이 실제 예금주와 달라요.',
    PayoutAccountFailReason.identityMismatch =>
      '본인확인한 이름과 예금주가 달라요. 본인 명의 계좌만 등록할 수 있어요.',
    PayoutAccountFailReason.businessNotVerified =>
      '사업자 인증을 먼저 완료해야 사업자 · 법인 계좌를 쓸 수 있어요. '
          '대표자 개인계좌는 사업자 인증 없이도 등록할 수 있어요.',
    PayoutAccountFailReason.businessHolderMismatch =>
      '예금주가 사업자 인증에 등록된 대표자명과 달라요. '
          '대표자명 계좌를 쓰시거나, 상호명 계좌가 필요하면 문의해주세요.',
  };
}

/// 지금 내 수취계좌 상태 한 벌 — 화면이 이 하나만 보고 그린다.
class PayoutAccount {
  const PayoutAccount({
    this.status = PayoutAccountStatus.none,
    this.bankCode,
    this.accountNumber,
    this.accountHolder,
    this.accountType = PayoutAccountType.personal,
    this.failReason,
    this.verifiedAt,
  });

  static const PayoutAccount none = PayoutAccount();

  final PayoutAccountStatus status;
  final String? bankCode;
  final String? accountNumber;
  final String? accountHolder;

  /// 이 계좌의 명의 — 인증 규칙이 갈리는 기준이다.
  final PayoutAccountType accountType;

  /// 마지막 인증이 실패했다면 그 이유. 인증 완료면 null.
  final PayoutAccountFailReason? failReason;

  /// 인증이 완료된 시각 — 서버 `payoutAccountVerification.checkedAt`.
  ///
  /// 30일 잠금의 기준점이다. 인증 완료 상태가 아니면 의미가 없다(서버도
  /// 같은 판정을 한다 — `functions/payoutAccounts.js`의 lockedUntilOf).
  final DateTime? verifiedAt;

  /// 인증 완료 후 수취계좌를 잠그는 기간.
  ///
  /// ⚠️ 서버 `functions/payoutAccounts.js`의 LOCK_DAYS와 **같은 값**이어야
  /// 한다. 판정의 정본은 언제나 서버다 — 여기 값은 화면 안내용이고, 앱이
  /// 먼저 막지 못해도 서버가 같은 자리에서 거절한다.
  static const int lockDays = 30;

  /// 계좌를 다시 바꿀 수 있게 되는 시각. 잠금 대상이 아니면 null.
  DateTime? get changeAllowedAt {
    final at = verifiedAt;
    if (!isVerified || at == null) return null;
    return at.add(const Duration(days: lockDays));
  }

  /// 지금 계좌가 잠겨 있는가. 경계는 **정확히 30일**이다.
  bool get isChangeLocked {
    final until = changeAllowedAt;
    return until != null && DateTime.now().isBefore(until);
  }

  /// 화면에 그대로 쓰는 해제일 — YYYY.MM.DD.
  String? get changeAllowedDateText {
    final at = changeAllowedAt;
    if (at == null) return null;
    final local = at.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}.$month.$day';
  }

  /// 잠금 중 변경을 시도했을 때 보여줄 안내 — 서버 lockedMessage와 같은 문구.
  String get changeLockedMessage =>
      '인증된 수취계좌는 인증 완료 후 $lockDays일 동안 변경할 수 없어요. '
      '${changeAllowedDateText ?? ''}부터 변경 가능합니다.';

  String? get bankName => BankCodes.nameOf(bankCode);

  bool get isVerified => status.isVerified;

  /// 목록·요약에 쓰는 한 줄 — '국민은행 ****1234'.
  ///
  /// 계좌번호 전체는 **참가자에게 안내할 때만** 쓴다(그래야 이체할 수 있다).
  /// 호스트 본인 화면의 요약·관리자 목록·로그에는 이 마스킹을 쓴다.
  String get maskedSummary => BankCodes.maskedSummary(
    bankName: bankName,
    accountNumber: accountNumber,
  );

  /// users/{uid} 문서에서 읽는다. 상태 판정 자체는 **서버가 이미 해 둔 값**을
  /// 그대로 쓴다 — 앱이 다시 계산하면 두 기준이 갈린다.
  factory PayoutAccount.fromUserDoc(Map<String, dynamic>? data) {
    final account = data?['payoutAccount'] as Map<String, dynamic>?;
    final verification =
        data?['payoutAccountVerification'] as Map<String, dynamic>?;
    if (account == null) return PayoutAccount.none;

    final bankCode = account['bankCode'] as String?;
    final accountNumber = account['accountNumber'] as String?;
    final accountHolder = account['accountHolder'] as String?;
    if ((bankCode ?? '').isEmpty ||
        (accountNumber ?? '').isEmpty ||
        (accountHolder ?? '').isEmpty) {
      return PayoutAccount.none;
    }

    final status = PayoutAccountStatus.fromKey(
      verification?['status'] as String?,
    );
    return PayoutAccount(
      // 계좌만 있고 인증 기록이 없으면 '인증 필요'다(서버도 같은 판정).
      status: status == PayoutAccountStatus.none
          ? PayoutAccountStatus.required
          : status,
      bankCode: bankCode,
      accountNumber: accountNumber,
      accountHolder: accountHolder,
      accountType: PayoutAccountType.fromKey(account['accountType'] as String?),
      failReason: PayoutAccountFailReason.fromKey(
        verification?['failReason'] as String?,
      ),
      verifiedAt: _dateOf(verification?['checkedAt']),
    );
  }

  /// Firestore Timestamp를 DateTime으로. 읽을 수 없으면 null.
  ///
  /// null이면 잠금 계산을 하지 않는다 — 기록이 깨진 계정을 영구히 묶어
  /// 두는 쪽이 더 나쁘다(서버 toMillis도 같은 선택을 한다).
  static DateTime? _dateOf(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
