import 'payment_method.dart';

/// 네 도메인(파티 신청·플레이스 방문예약·장소대여·파티샵 주문)이 함께 쓰는
/// **결제 상태**.
///
/// 도메인마다 이미 자기 진행 상태를 갖고 있다(신청 `applied`, 예약 `pending`
/// /`requested`, 주문 `payment_pending` …). 그것은 "주문이 어디까지 갔는가"이고,
/// 이 enum은 **"돈이 어디까지 갔는가"**만 말한다. 둘을 한 값에 섞으면
/// '입금대기'인지 '승인대기'인지 구분할 수 없게 되므로 따로 둔다.
///
/// 가장 중요한 규칙: **결제완료처럼 보이지 않게 한다.** 무통장입금은 입금이
/// 확인되기 전까지 [awaitingDeposit], 현장결제는 방문해서 낼 때까지
/// [onSiteScheduled]다. [paid]는 서버가 실제 입금·결제를 확인했을 때만 쓴다
/// (지금은 PG가 없으므로 클라이언트가 이 값을 만들 일이 없다).
enum PaymentStatus {
  /// **승인이 나야 입금을 요구하는 흐름**에서 승인을 기다리는 구간
  /// (플레이스 방문예약의 승인제 매장). 승인되는 순간 서버가
  /// [awaitingDeposit]으로 바꾸고 그때부터 입금기한이 시작된다.
  ///
  /// 승인 전에 입금을 받으면 거절 시 계좌로 수동 환불해야 하는데 PG가 없어
  /// 자동 환불이 불가능하다 — 그래서 이 구간을 둔다.
  awaitingApproval(
    key: 'awaiting_approval',
    label: '승인대기',
    description: '승인되면 입금 안내를 보내드려요',
  ),
  awaitingDeposit(
    key: 'awaiting_deposit',
    label: '입금대기',
    description: '입금이 확인되면 확정돼요',
  ),

  /// 입금은 했다고 알려졌지만 **아직 대조되지 않은** 상태.
  /// (사용자가 '입금했어요'를 눌렀거나, 관리자가 확인을 시작한 구간)
  /// [awaitingDeposit]과 [paid] 사이를 메워서, 확인 중인 건과 아직 아무 일도
  /// 없는 건을 목록에서 구분할 수 있게 한다.
  depositPending(
    key: 'deposit_pending',
    label: '입금확인중',
    description: '입금 내역을 확인하고 있어요',
  ),
  onSiteScheduled(
    key: 'on_site_scheduled',
    label: '현장결제 예정',
    description: '현장에서 결제하면 확정돼요',
  ),
  paid(key: 'paid', label: '결제완료', description: '결제가 확인됐어요'),
  cancelled(key: 'cancelled', label: '결제취소', description: '결제가 취소됐어요'),
  refunded(key: 'refunded', label: '환불완료', description: '환불이 끝났어요'),
  expired(key: 'expired', label: '기한만료', description: '입금기한이 지나 자동 취소됐어요');

  const PaymentStatus({
    required this.key,
    required this.label,
    required this.description,
  });

  /// 문서에 저장하는 값.
  final String key;

  /// 목록·상세에 그대로 붙이는 표기.
  final String label;

  final String description;

  /// 아직 돈을 받지 못한 상태인지 — '결제완료'로 오인되면 안 되는 구간이다.
  /// 입금확인중도 아직 확인 전이므로 여기에 든다.
  bool get isUnpaid =>
      this == awaitingApproval ||
      this == awaitingDeposit ||
      this == depositPending ||
      this == onSiteScheduled;

  /// 지금 이용자가 '입금했어요'를 누를 수 있는 상태인지 — 서버
  /// (depositFlow.assertCanMarkSent)와 **같은 조건**이다. 화면은 이 값으로만
  /// 버튼을 띄우고, 실제 차단은 서버가 다시 확인한다.
  bool get canMarkDepositSent => this == awaitingDeposit;

  /// 더 진행되지 않고 끝난 상태인지.
  bool get isClosed => this == cancelled || this == refunded || this == expired;

  static PaymentStatus? fromKey(String? key) {
    if (key == null) return null;
    for (final s in values) {
      if (s.key == key) return s;
    }
    return null;
  }

  /// 이 수단을 고르면 **바로 어떤 상태가 되는지**. 화면과 저장이 같은 규칙을
  /// 보게 해서 "고를 때는 입금대기라 했는데 목록에는 결제완료"가 생기지 않게
  /// 한다. 아직 열지 않은 수단은 상태를 만들지 않는다(null).
  static PaymentStatus? initialFor(PaymentMethod method) => switch (method) {
    PaymentMethod.bankTransfer => awaitingDeposit,
    PaymentMethod.onSite => onSiteScheduled,
    // PG를 붙이기 전까지 카드·이체·가상계좌·간편결제는 상태 자체가 없다.
    _ => null,
  };
}

/// 신청·예약·주문 문서에 붙는 **결제 정보 한 덩어리**(`payment` 필드).
///
/// 결제수단 선택 화면이 돌려주는 값이면서, 그 뒤로도 계속 자라는 그릇이다 —
/// 입금 확인(`depositedAt`), 확정(`paidAt`), 취소·환불 시각이 같은 객체에
/// 쌓인다. 그래서 이름이 '선택(Selection)'이 아니라 [PaymentInfo]다.
///
/// 확장 규칙
/// - 새 항목은 **필드로 추가**하고 [toMap]/[fromMap] 양쪽에 같은 키로 적는다.
/// - 아직 모델에 없는 서버 측 항목(입금자 은행, 관리자 메모 등)은 [extra]에
///   그대로 실려 오가므로, 앱을 고치지 않아도 값이 유실되지 않는다.
/// - 시각은 전부 `...Ms`(epoch milliseconds)로 적는다 — Cloud Functions와
///   Firestore Timestamp 사이에서 형식이 갈리지 않게.
class PaymentInfo {
  final PaymentMethod method;
  final PaymentStatus status;

  /// 무통장입금일 때 입금자명(비워두면 신청자 이름을 쓴다).
  final String? depositorName;

  /// 무통장입금 기한.
  final DateTime? depositDeadline;

  /// 입금이 있었다고 알려진 시각 — '입금했어요'를 누르거나 서버가 내역을
  /// 발견한 때. 상태로는 [PaymentStatus.depositPending]에 해당한다.
  final DateTime? depositedAt;

  /// 결제가 **확인**된 시각(서버만 채운다).
  final DateTime? paidAt;

  final DateTime? cancelledAt;

  /// 안내받은 입금 계좌의 **스냅샷** — 신청/주문이 만들어질 때 서버가 그때의
  /// 계좌를 문서에 함께 적어 둔다(functions/paymentInfo.js의 BANK_ACCOUNT).
  ///
  /// 나중에 파티츄 계좌가 바뀌어도 **그때 안내한 계좌**를 그대로 보여줘야
  /// 사용자가 자기 이체내역과 대조할 수 있다. 그래서 화면은 상수가 아니라
  /// 이 값을 먼저 쓴다([PaymentInfo.bankAccount]).
  final String? bankName;
  final String? accountNumber;
  final String? accountHolder;

  /// 아직 모델에 없는 항목들 — 그대로 실어 나른다(유실 방지).
  final Map<String, dynamic> extra;

  const PaymentInfo({
    required this.method,
    required this.status,
    this.depositorName,
    this.depositDeadline,
    this.depositedAt,
    this.paidAt,
    this.cancelledAt,
    this.bankName,
    this.accountNumber,
    this.accountHolder,
    this.extra = const {},
  });

  /// 실제로 입금해야 하는 금액(원). 서버가 payment.amount로 적어 준다.
  int? get amount {
    final v = extra['amount'];
    return v is num ? v.toInt() : null;
  }

  /// 화면에 보여줄 입금 계좌 — **문서에 박힌 스냅샷**뿐이다. 없으면 null.
  ///
  /// 폴백 상수는 없앴다. 예전에는 스냅샷이 없으면 파티츄 공용 계좌를 대신
  /// 보여줬는데, 지금 참가비는 **호스트가 직접 받는다** — 폴백이 남아 있으면
  /// 계좌가 없는 건에서 엉뚱한 계좌로 송금이 일어난다. 값이 없으면 화면은
  /// 계좌 줄 자체를 그리지 않고 문의 안내를 띄운다.
  ///
  /// 스냅샷을 남기기 전에 만들어진 옛 문서에는 그때 안내했던 파티츄 계좌가
  /// 그대로 들어 있으므로, 그 건들은 지금도 예전 안내 그대로 보인다.
  ({String bank, String number, String holder})? get bankAccount {
    final bank = (bankName ?? '').trim();
    final number = (accountNumber ?? '').trim();
    final holder = (accountHolder ?? '').trim();
    if (bank.isEmpty || number.isEmpty || holder.isEmpty) return null;
    return (bank: bank, number: number, holder: holder);
  }

  /// 모델이 직접 아는 키들 — [extra]를 가려낼 때 쓴다.
  static const Set<String> _knownKeys = {
    'method',
    'status',
    'depositorName',
    'depositDeadlineMs',
    'depositedAtMs',
    'paidAtMs',
    'cancelledAtMs',
    'bankName',
    'accountNumber',
    'accountHolder',
  };

  PaymentInfo copyWith({
    PaymentMethod? method,
    PaymentStatus? status,
    String? depositorName,
    DateTime? depositDeadline,
    DateTime? depositedAt,
    DateTime? paidAt,
    DateTime? cancelledAt,
    Map<String, dynamic>? extra,
  }) => PaymentInfo(
    method: method ?? this.method,
    status: status ?? this.status,
    depositorName: depositorName ?? this.depositorName,
    depositDeadline: depositDeadline ?? this.depositDeadline,
    depositedAt: depositedAt ?? this.depositedAt,
    paidAt: paidAt ?? this.paidAt,
    cancelledAt: cancelledAt ?? this.cancelledAt,
    // 계좌 스냅샷은 복사본에서도 유지된다 — 상태만 바꾼다고 안내 계좌가
    // 현재 상수로 되돌아가면 안 된다.
    bankName: bankName,
    accountNumber: accountNumber,
    accountHolder: accountHolder,
    extra: extra ?? this.extra,
  );

  static int? _ms(DateTime? d) => d?.millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
    ...extra,
    'method': method.key,
    'status': status.key,
    if (depositorName != null && depositorName!.isNotEmpty)
      'depositorName': depositorName,
    if (depositDeadline != null) 'depositDeadlineMs': _ms(depositDeadline),
    if (depositedAt != null) 'depositedAtMs': _ms(depositedAt),
    if (paidAt != null) 'paidAtMs': _ms(paidAt),
    if (cancelledAt != null) 'cancelledAtMs': _ms(cancelledAt),
    // 계좌 스냅샷은 **가지고 있을 때만** 다시 실어 보낸다.
    //
    // 계좌를 채우는 것은 서버다(호스트의 인증된 수취계좌 —
    // functions/paymentInfo.js). 앱이 여기서 값을 만들어 넣으면 서버가 정한
    // 계좌를 클라이언트가 덮어쓰는 통로가 된다. 이미 문서에 있던 값을 그대로
    // 되돌려 보내는 것만 허용한다(상태만 바꾸는 저장에서 계좌가 지워지지 않게).
    if (method == PaymentMethod.bankTransfer) ...{
      if ((bankName ?? '').isNotEmpty) 'bankName': bankName,
      if ((accountNumber ?? '').isNotEmpty) 'accountNumber': accountNumber,
      if ((accountHolder ?? '').isNotEmpty) 'accountHolder': accountHolder,
    },
  };

  static DateTime? _dateOf(Object? v) =>
      v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

  static PaymentInfo? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final method = PaymentMethod.fromKey(map['method'] as String?);
    final status = PaymentStatus.fromKey(map['status'] as String?);
    if (method == null || status == null) return null;
    return PaymentInfo(
      method: method,
      status: status,
      depositorName: map['depositorName'] as String?,
      depositDeadline: _dateOf(map['depositDeadlineMs']),
      depositedAt: _dateOf(map['depositedAtMs']),
      paidAt: _dateOf(map['paidAtMs']),
      cancelledAt: _dateOf(map['cancelledAtMs']),
      // 안내 당시 계좌 스냅샷 — 없으면 null로 두고 화면이 상수로 폴백한다.
      bankName: map['bankName'] as String?,
      accountNumber: map['accountNumber'] as String?,
      accountHolder: map['accountHolder'] as String?,
      extra: {
        for (final e in map.entries)
          if (!_knownKeys.contains(e.key)) e.key: e.value,
      },
    );
  }
}
