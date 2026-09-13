import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:party_app/models/bank_codes.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';

/// 환불계좌 인증 상태 — 서버 refundAccountVerify.js의 STATUS와 키가 1:1이다.
///
/// ⚠ 호스트 수취계좌의 [PayoutAccountStatus]와 **같은 모양이지만 다른 값**이다.
///   한 사람이 호스트이면서 게스트일 수 있으므로 절대 섞어 읽지 않는다.
enum RefundAccountStatus {
  /// 미등록 — 인증된 계좌를 넣은 적이 없다(옛 자유입력 계좌만 있는 경우 포함).
  none('none', '미등록'),

  /// 인증 필요 — 계좌는 있는데 확인되지 않았다(실패했거나, 계좌가 바뀌었거나).
  required('required', '인증 필요'),

  /// 인증 완료 — 이 계좌로만 무통장입금 신청이 가능하다.
  verified('verified', '인증 완료');

  const RefundAccountStatus(this.key, this.label);

  final String key;
  final String label;

  static RefundAccountStatus fromKey(String? key) {
    for (final s in values) {
      if (s.key == key) return s;
    }
    return RefundAccountStatus.none;
  }
}

/// 참가자 **환불계좌** — 무통장입금으로 낸 돈을 돌려받을 본인 계좌.
///
/// ⚠ 호스트 정산계좌(users/{uid}.settlementInfo)와 **다른 필드, 다른 용도**다.
///   - 정산계좌: 파티츄 → 호스트 (호스트가 받을 돈)
///   - 환불계좌: 파티츄 → 참가자 (참가자가 돌려받을 돈)
///   한 사람이 호스트이면서 참가자일 수 있으므로 절대 같은 필드에 두지 않는다.
///
/// 저장 위치는 본인 문서(users/{uid}.refundAccount)이고 규칙상 본인·관리자만
/// 읽는다. 실제 환불 요청이 접수될 때는 서버가 **그 시점의 사본**을
/// refundRequests에 따로 박아두므로, 나중에 여기를 고쳐도 접수된 건은 안 바뀐다.
class RefundAccount {
  final String bankName;
  final String accountNumber;
  final String accountHolder;

  /// 금융기관 코드 — 성명조회(인증)에 필요하다. 인증이 없던 시절에 자유 입력
  /// 은행명만으로 저장된 옛 계좌는 이 값이 비어 있고, 그런 계좌는 서버가
  /// **인증되지 않은 것으로 읽는다**(정본: refundAccountVerify.statusOf).
  final String bankCode;

  const RefundAccount({
    required this.bankName,
    required this.accountNumber,
    required this.accountHolder,
    this.bankCode = '',
  });

  bool get isComplete =>
      bankName.trim().isNotEmpty &&
      accountNumber.trim().isNotEmpty &&
      accountHolder.trim().isNotEmpty;

  /// 마이페이지 요약 한 줄 — '카카오뱅크 ****1234'.
  ///
  /// 수취계좌([PayoutAccount.maskedSummary])와 **같은 함수·같은 모양**이다
  /// ([BankCodes.maskedSummary]) — 같은 화면에 나란히 서는 두 줄이라 자릿수도
  /// 기호도 어긋나면 안 된다.
  ///
  /// 기관명은 저장된 [bankName]을 그대로 쓴다. 인증을 마친 계좌의 이 값은
  /// 서버가 기관코드 표에서 채운 것이라([BankCodes]와 같은 표) 임의 문자열이
  /// 아니다.
  String get maskedSummary => BankCodes.maskedSummary(
    bankName: bankName,
    accountNumber: accountNumber,
  );

  /// '신한은행 ••••1234' — 확인 시트에서 쓰는 형태.
  ///
  /// [maskedSummary]와 자리가 다르다: 이쪽은 "이 계좌로 받겠다"를 확인받는
  /// 시트 본문이라 지금 표기를 그대로 둔다(마이페이지 요약과 통일해야 하는
  /// 것은 목록 줄 쪽이다).
  ///
  /// 계좌번호 전체를 다시 그릴 이유가 없다. 본인이 어느 계좌인지 알아보는 데는
  /// 기관명과 뒤 네 자리면 충분하고, 어깨너머로 읽히는 위험만 줄어든다.
  /// 네 자리보다 짧은 계좌번호는 있는 만큼만 남긴다.
  String get maskedLabel {
    final digits = accountNumber.trim();
    final tail = digits.length <= 4
        ? digits
        : digits.substring(digits.length - 4);
    return '${bankName.trim()} ••••$tail';
  }

  /// 취소 흐름이 서버로 보내는 형태 — 예전 그대로 세 값이다(서버
  /// refundAccounts.normalizeRefundAccount가 이 모양을 받는다).
  Map<String, dynamic> toMap() => {
    'bankName': bankName.trim(),
    'accountNumber': accountNumber.trim(),
    'accountHolder': accountHolder.trim(),
  };

  static RefundAccount? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final a = RefundAccount(
      bankName: (map['bankName'] as String? ?? '').trim(),
      accountNumber: (map['accountNumber'] as String? ?? '').trim(),
      accountHolder: (map['accountHolder'] as String? ?? '').trim(),
      bankCode: (map['bankCode'] as String? ?? '').trim(),
    );
    return a.isComplete ? a : null;
  }
}

/// 계좌 + 인증 상태를 함께 든 값 — 화면과 안내가 이 하나만 본다.
class RefundAccountState {
  final RefundAccount? account;
  final RefundAccountStatus status;

  /// 인증에 실패한 이유 코드(서버 FAIL_REASON). 실패했을 때만 있다.
  final String? failReason;

  const RefundAccountState({
    required this.account,
    required this.status,
    this.failReason,
  });

  static const empty = RefundAccountState(
    account: null,
    status: RefundAccountStatus.none,
  );

  bool get isVerified => status == RefundAccountStatus.verified;
}

class RefundAccountService {
  RefundAccountService._();

  static final _db = FirebaseFirestore.instance;

  /// 이전에 등록해 둔 환불계좌 — 입력 화면의 기본값으로 쓴다.
  /// 매번 처음부터 치게 하지 않는 것이 목적이다.
  static Future<RefundAccount?> load() async {
    final uid = UserSession.userId;
    if (uid.isEmpty) return null;
    try {
      final snap = await _db.collection('users').doc(uid).get();
      return RefundAccount.fromMap(
        snap.data()?['refundAccount'] as Map<String, dynamic>?,
      );
    } catch (_) {
      return null;
    }
  }

  /// 계좌와 **인증 상태**를 함께 읽는다 — 무통장입금 신청 가능 여부의 정본.
  ///
  /// 지문 대조는 서버가 하지만(refundAccountVerify.statusOf), 화면이 매번
  /// 콜러블을 부를 이유는 없으므로 같은 규칙을 여기서도 읽는다. 최종 판정은
  /// 언제나 서버다(applyToParty의 assertRefundAccountVerified).
  static Future<RefundAccountState> fetchState() async {
    final uid = UserSession.userId;
    if (uid.isEmpty) return RefundAccountState.empty;
    try {
      final snap = await _db.collection('users').doc(uid).get();
      return stateOfUserDoc(snap.data());
    } catch (_) {
      // 읽지 못했으면 "인증됐다"고 볼 수 없다 — 안내가 한 번 더 뜰 뿐이고,
      // 최종 판정은 서버가 다시 한다.
      return RefundAccountState.empty;
    }
  }

  /// 마이페이지 요약 줄이 구독하는 스트림 — 수취계좌
  /// ([PayoutAccountService.watch])와 **같은 모양**이다.
  ///
  /// 화면을 다시 열지 않아도 인증을 마치고 돌아온 순간 줄이 바뀌어야 한다.
  /// 읽기 전용이다 — 계좌를 만들거나 상태를 바꾸는 경로는 여전히 콜러블
  /// 하나뿐이다([verify]).
  static Stream<RefundAccountState> watch() {
    final uid = UserSession.userId;
    if (uid.isEmpty) return Stream.value(RefundAccountState.empty);
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((s) => stateOfUserDoc(s.data()))
        .handleError(
          (Object e, StackTrace st) =>
              logFirestoreStreamError('RefundAccountService.watch', e, st),
        );
  }

  /// users/{uid} 문서 한 장 → 계좌 + 인증 상태.
  ///
  /// 판정 조건은 **서버(refundAccountVerify.statusOf)와 같은 규칙**이다:
  ///   ① `refundAccount`에 기관명·계좌번호·예금주가 다 있고
  ///   ② `refundAccountVerification.status == 'verified'`이며
  ///   ③ 그 계좌에 **기관코드가 있다**(코드 없이 자유 입력하던 옛 계좌는
  ///      성명조회를 거친 적이 없으므로 인증으로 치지 않는다).
  ///
  /// 지문 대조(accountFingerprint)까지는 앱이 하지 않는다 — 서버만 만들 수
  /// 있는 값이고, 최종 판정은 언제나 서버가 다시 한다
  /// (applyToParty의 assertRefundAccountVerified).
  @visibleForTesting
  static RefundAccountState stateOfUserDoc(Map<String, dynamic>? data) {
    final account = RefundAccount.fromMap(
      data?['refundAccount'] as Map<String, dynamic>?,
    );
    if (account == null) return RefundAccountState.empty;
    final v = data?['refundAccountVerification'] as Map<String, dynamic>?;
    final verified =
        v != null &&
        v['status'] == RefundAccountStatus.verified.key &&
        account.bankCode.isNotEmpty;
    return RefundAccountState(
      account: account,
      status: verified
          ? RefundAccountStatus.verified
          : RefundAccountStatus.required,
      failReason: v?['failReason'] as String?,
    );
  }

  /// 환불계좌 인증 — 서버가 성명조회로 확인하고 결과까지 기록한다.
  ///
  /// 호스트 수취계좌와 **같은 인증 엔진**을 쓰되 저장 자리가 다르다
  /// (functions/refundAccountVerify.js). 앱은 결과를 읽기만 한다 —
  /// `refundAccountVerification`은 규칙상 클라이언트가 쓸 수 없다.
  ///
  /// ── 실패는 세 갈래고, 부르는 쪽이 반드시 갈라서 다뤄야 한다 ────────────
  ///   ① 계좌번호·예금주가 틀린 **정상적인 인증 실패**는 예외가 아니다.
  ///      서버가 결과를 문서에 적으므로 [RefundAccountState.failReason]으로
  ///      온다 — 사용자가 입력을 고치면 풀린다.
  ///   ② [RefundAccountVerifyUnavailable] — 콜러블이 그 이름·리전에 **없다**.
  ///      사용자가 무엇을 고쳐도 절대 풀리지 않는다(배포 문제).
  ///   ③ 나머지 [FirebaseFunctionsException] — 서버가 판단해서 거절했다.
  static Future<RefundAccountState> verify({
    required String bankCode,
    required String bankName,
    required String accountNumber,
    required String accountHolder,
  }) async {
    try {
      await FirebaseFunctions.instanceFor(
        region: _region,
      ).httpsCallable(_verifyCallable).call({
        'bankCode': bankCode,
        'accountNumber': accountNumber,
        'accountHolder': accountHolder,
      });
    } on FirebaseFunctionsException catch (e) {
      if (_endpointMissingCodes.contains(e.code)) {
        throw RefundAccountVerifyUnavailable(
          code: e.code,
          functionName: _verifyCallable,
          region: _region,
        );
      }
      rethrow;
    }
    // 반환값을 그대로 믿지 않고 문서를 다시 읽는다 — 화면이 보는 값과 서버가
    // 판정에 쓰는 값이 언제나 같은 문서에서 나오게 한다.
    return fetchState();
  }

  /// 이 코드가 오면 **콜러블이 그 이름·리전에 없다**는 뜻이다(HTTP 404).
  ///
  /// 추측이 아니라 서버 코드에서 확인한 사실이다: refundAccountVerify.js가
  /// 던지는 코드는 unauthenticated · invalid-argument · already-exists 셋뿐이고
  /// `not-found`/`unimplemented`는 **하나도 없다.** 그러니 이 두 코드는 서버의
  /// 판단일 수가 없고 라우팅 실패뿐이다. 서버가 언젠가 `not-found`를 던지게
  /// 바뀐다면 이 목록도 같이 손봐야 한다.
  static const _endpointMissingCodes = {'not-found', 'unimplemented'};

  /// 이름과 리전은 서버의 배포 대상과 **글자 그대로** 같아야 한다
  /// (functions/index.js의 exports.verifyRefundAccount,
  ///  functions/refundAccountVerify.js의 onCall region).
  static const _verifyCallable = 'verifyRefundAccount';
  static const _region = 'asia-northeast3';
}

/// 인증 실패 사유([RefundAccountState.failReason]) → 사용자에게 보여줄 문구.
///
/// 사유는 서버가 판정해 문서에 적은 값이고(FAIL_REASON), 여기서는 그것을
/// 사람 말로 옮기기만 한다. **"인증에 실패했어요" 하나로 뭉개지 않는 것**이
/// 이 표의 존재 이유다 — 계좌번호를 고쳐야 하는 실패와, 사용자가 아무리
/// 다시 눌러도 풀리지 않는 서비스 쪽 문제는 할 일이 정반대다.
///
/// 화면과 테스트가 같은 함수를 본다(화면 안에 두면 검증할 수가 없다).
String refundAccountFailMessage(String? reason) => switch (reason) {
  'accountNotFound' => '계좌를 찾을 수 없어요. 금융기관과 계좌번호를 확인해주세요.',
  'holderMismatch' => '예금주명이 은행에 등록된 이름과 달라요.',
  'identityMismatch' => '본인 명의 계좌만 등록할 수 있어요.',
  // 일시적 — 다시 시도하면 풀릴 수 있다.
  'apiUnavailable' => '계좌 확인 서비스가 잠시 불안정해요. 잠시 후 다시 시도해주세요.',
  // 설정 문제 — **재시도로는 풀리지 않는다.** 여기에 "다시 시도해주세요"를
  // 붙이면 사용자가 멀쩡한 자기 계좌를 몇 번이고 다시 치게 된다(콜러블이
  // 아예 없을 때와 같은 성격의 실패다 — [RefundAccountVerifyUnavailable]).
  'notConfigured' =>
    '계좌 확인 서비스가 아직 연결되지 않았어요. 입력하신 계좌 문제가 아니니 '
        '잠시 뒤 다시 확인해주세요.',
  _ => '계좌를 확인하지 못했어요. 입력한 내용을 다시 확인해주세요.',
};

/// 환불계좌 인증 콜러블이 **그 이름·리전에 없다** — 인증 실패가 아니라 장애다.
///
/// 계좌번호나 예금주가 틀려서 나는 실패와 절대 같이 다루면 안 된다. 그쪽은
/// 사용자가 입력을 고치면 풀리지만, 이쪽은 무엇을 고쳐도 풀리지 않는다. 같은
/// 문구로 뭉개면 사용자는 멀쩡한 자기 계좌를 몇 번이고 다시 친다.
class RefundAccountVerifyUnavailable implements Exception {
  const RefundAccountVerifyUnavailable({
    required this.code,
    required this.functionName,
    required this.region,
  });

  /// 원래 받은 코드 — `not-found`(대부분) 또는 `unimplemented`.
  final String code;

  /// 부르려던 콜러블 이름. 로그에 남겨야 배포 대상이 바로 드러난다.
  final String functionName;

  /// 부르려던 리전. 이름이 맞아도 리전이 다르면 똑같이 404다.
  final String region;

  @override
  String toString() =>
      'RefundAccountVerifyUnavailable(code: $code, '
      'function: $functionName, region: $region)';
}
