import 'package:cloud_functions/cloud_functions.dart';

/// 탈퇴를 막고 있는 항목 하나 — 종류·건수·사용자에게 보여줄 문구.
class WithdrawalBlocker {
  final String kind;
  final int count;
  final String message;
  final String route;

  const WithdrawalBlocker({
    required this.kind,
    required this.count,
    required this.message,
    required this.route,
  });

  factory WithdrawalBlocker.fromMap(Map<String, dynamic> m) =>
      WithdrawalBlocker(
        kind: (m['kind'] ?? '').toString(),
        count: (m['count'] as num?)?.toInt() ?? 0,
        message: (m['message'] ?? '').toString(),
        route: (m['route'] ?? '').toString(),
      );
}

/// 탈퇴 상태 스냅샷.
class WithdrawalStatus {
  /// 'active' · 'withdrawal_pending' · 'withdrawn' 등 서버의 accountStatus.
  final String status;

  /// 대기 기간(일). 서버가 정하는 값을 그대로 받아 화면에 쓴다 — 앱에 7을
  /// 하드코딩하면 서버 정책을 바꿨을 때 안내만 옛날 값으로 남는다.
  final int graceDays;

  /// 완전 탈퇴 예정 시각. 대기 중일 때만 값이 있다.
  final DateTime? scheduledAt;

  /// 완료가 보류된 사유('settlement' 등). 대기 기간이 지났는데도 남아 있으면
  /// 사용자에게 왜 아직 처리되지 않았는지 알려줘야 한다.
  final String? hold;

  final List<WithdrawalBlocker> blockers;

  const WithdrawalStatus({
    required this.status,
    required this.graceDays,
    this.scheduledAt,
    this.hold,
    this.blockers = const [],
  });

  bool get isPending => status == 'withdrawal_pending';
  bool get isWithdrawn => status == 'withdrawn';
  bool get canRequest => !isPending && !isWithdrawn && blockers.isEmpty;

  /// 완전 탈퇴까지 남은 일수(올림). 오늘이 마지막 날이면 0이 아니라 1이 되도록
  /// 올림한다 — "0일 남음"은 사용자에게 이미 끝났다는 뜻으로 읽힌다.
  int get daysLeft {
    final at = scheduledAt;
    if (at == null) return 0;
    final diff = at.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return diff.inHours ~/ 24 + (diff.inHours % 24 > 0 ? 1 : 0);
  }
}

/// 회원 탈퇴 신청·취소·조회. 모든 판단은 서버가 한다.
///
/// 앱이 자체적으로 "탈퇴 가능"을 판정하지 않는 이유: 진행 중인 예약·주문·환불이
/// 있는지는 여러 컬렉션을 가로질러 봐야 알 수 있고, 그 규칙은 콘텐츠 삭제와
/// 같은 값을 써야 한다(서버 contentCleanup.js). 앱에 옮겨 적으면 두 곳이
/// 갈라진다.
class AccountWithdrawalService {
  AccountWithdrawalService._();

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    // Timestamp가 JSON으로 내려오면 _seconds 형태가 된다.
    if (v is Map && v['_seconds'] != null) {
      return DateTime.fromMillisecondsSinceEpoch(
        (v['_seconds'] as num).toInt() * 1000,
      );
    }
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static WithdrawalStatus _parse(Map<String, dynamic> d) => WithdrawalStatus(
    status: (d['status'] ?? 'active').toString(),
    graceDays: (d['graceDays'] as num?)?.toInt() ?? 7,
    scheduledAt: _toDate(d['scheduledAt']),
    hold: d['hold']?.toString(),
    blockers: ((d['blockers'] as List?) ?? const [])
        .map(
          (e) => WithdrawalBlocker.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
  );

  /// 현재 상태와 (대기 중이 아니라면) 지금 신청할 수 있는지를 함께 받는다.
  static Future<WithdrawalStatus> fetchStatus() async {
    final res = await _fn.httpsCallable('getAccountWithdrawalStatus').call();
    return _parse(Map<String, dynamic>.from(res.data as Map));
  }

  /// 탈퇴 신청. 막는 사유가 있으면 [WithdrawalStatus.blockers]가 채워진 채로
  /// 돌아오고 상태는 바뀌지 않는다.
  static Future<WithdrawalStatus> request({
    String? reason,
    String? reasonCode,
  }) async {
    final res = await _fn.httpsCallable('requestAccountWithdrawal').call({
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      // 선택형 코드만 계정에 남는다. 자유서술(reason)은 서버가 uid 없이 따로
      // 쌓으므로 탈퇴 후에도 누가 썼는지 알 수 없다 — accountWithdrawal.js 참고.
      if (reasonCode != null && reasonCode.isNotEmpty) 'reasonCode': reasonCode,
    });
    final d = Map<String, dynamic>.from(res.data as Map);
    if (d['success'] == false) {
      return WithdrawalStatus(
        status: 'active',
        graceDays: (d['graceDays'] as num?)?.toInt() ?? 7,
        blockers: ((d['blockers'] as List?) ?? const [])
            .map(
              (e) => WithdrawalBlocker.fromMap(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
      );
    }
    return WithdrawalStatus(
      status: 'withdrawal_pending',
      graceDays: (d['graceDays'] as num?)?.toInt() ?? 7,
      scheduledAt: _toDate(d['scheduledAt']),
    );
  }

  /// 탈퇴 취소 — 대기 기간 안에서만 된다.
  static Future<void> cancel() async {
    await _fn.httpsCallable('cancelAccountWithdrawal').call();
  }
}
