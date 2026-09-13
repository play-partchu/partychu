// ─────────────────────────────────────────────────────────────────────────────
// 게스트가 보는 **QR 한 장** — 파티·예약·이용권이 같은 모양으로 들어온다.
//
// 왜 하나로 모으나: 호스트에게 스캐너가 하나이듯 손님에게도 QR 화면은 하나여야
// 한다. 유형마다 화면을 따로 만들면 "QR이 언제 생기고 언제 못 쓰게 되는지"가
// 화면마다 갈라지고, 실제로 예전 이용권 QR에만 있던 '한 번 쓰면 끝' 안내가
// 파티에는 빠지는 식으로 어긋난다.
//
// 이 클래스는 **표시할 값만** 담는다. 유효성은 판단하지 않는다 — QR을 실제로
// 쓸 수 있는지는 호스트가 스캔하는 순간 서버가 원본 문서를 다시 읽어 정한다
// (functions/checkInRules.js). 화면이 스스로 "쓸 수 있다"고 말하면 서버 판정과
// 어긋나는 순간 손님이 현장에서 거절당한다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

import 'package:party_app/models/check_in_result.dart' show CheckInDomain;

/// QR 한 장이 지금 어떤 상태인가 — 색과 문구만 가른다.
enum CheckInPassState {
  /// 아직 쓰지 않았다.
  ready,

  /// 이미 체크인·사용됐다.
  used,

  /// 지금은 쓸 수 없다(결제 전 등). QR은 보여주되 안내를 함께 적는다.
  pending,
}

/// 게스트 QR 화면 한 벌.
///
/// 화면([CheckInQrCard])은 이 값만 보고 그린다. 파티·예약·이용권은 각자
/// 팩토리에서 자기 필드를 이 모양으로 옮기고, 그 뒤로는 구분되지 않는다.
class CheckInPass {
  const CheckInPass({
    required this.domain,
    required this.token,
    required this.title,
    required this.statusLabel,
    required this.state,
    this.subtitle = '',
    this.at,
    this.endAt,
    this.personName = '',
    this.itemLabel = '',
    this.notice,
  });

  /// 파티 / 예약 / 이용권 — 배지 문구는 [CheckInDomain.label]을 그대로 쓴다
  /// (호스트 스캔 결과 화면과 같은 단어여야 현장에서 말이 갈리지 않는다).
  final CheckInDomain domain;

  /// QR에 실리는 값. 서버가 발급한 난수 토큰이거나(파티·예약) 이용권 코드다.
  ///
  /// **비어 있으면 QR이 아직 없다** — 승인 전 신청, 확정 전 예약, 결제 전
  /// 이용권이 그렇다. 그때는 QR을 여는 버튼 자체를 띄우지 않는다.
  final String token;

  /// 파티명 · 플레이스명 · 상품명.
  final String title;

  /// 제목 아래 한 줄 — 장소, 객실, 매장 이름 등.
  final String subtitle;

  /// 이용 일시(시작). 숙박처럼 구간이 있으면 [endAt]까지 함께 그린다.
  final DateTime? at;
  final DateTime? endAt;

  /// 참가자·예약자 성함. 호스트가 신분증과 대조하는 값이라 실명을 쓴다.
  final String personName;

  /// 이용 대상 / 구매 상품 — '4명', '디럭스룸 · 1박', '좌석권 2개'.
  final String itemLabel;

  /// '참가 확정' · '예약 확정' · '사용 완료' 같은 현재 상태 한 마디.
  final String statusLabel;

  final CheckInPassState state;

  /// 상태만으로는 부족한 한 줄(결제 안내 등). 없으면 그리지 않는다.
  final String? notice;

  /// 지금 보여줄 QR이 있는가.
  bool get hasQr => token.isNotEmpty;

  // ── 파티 신청 → QR 한 벌 ──────────────────────────────────────────────────
  //
  // 파티는 예약·이용권과 달리 모델 클래스가 없다(신청 문서를 맵 그대로
  // 읽는다). 그래서 변환을 여기 둔다 — 화면이 직접 필드를 꺼내 쓰면 회차
  // 파티의 일시를 어느 화면은 파티 시작으로, 어느 화면은 회차 시작으로 그리는
  // 어긋남이 생긴다.

  /// 신청 문서 + 파티 문서에서 게스트 QR 한 벌을 만든다.
  ///
  /// [app]은 `parties/{id}/applications/{id}` 문서, [party]는 그 파티 문서다.
  /// [personName]은 참가자 실명(호스트가 신분증과 대조하는 값).
  factory CheckInPass.fromPartyApplication({
    required Map<String, dynamic> app,
    required Map<String, dynamic> party,
    required String personName,
  }) {
    // 정기 파티는 저장된 partyDateTime이 첫 회차(과거)라 그대로 쓰면 안 된다 —
    // 내가 신청한 회차가 있으면 **그 회차**가 이 QR의 일시다.
    final at =
        _dt(app['occurrenceStartAt']) ??
        _dt(app['partyDateTime']) ??
        _dt(party['dateTime']);
    final checkedIn = _dt(app['checkedInAt']) != null;

    return CheckInPass(
      domain: CheckInDomain.party,
      token: app['checkInToken'] as String? ?? '',
      title: party['title'] as String? ?? '파티',
      subtitle:
          party['location'] as String? ?? party['address'] as String? ?? '',
      at: at,
      endAt: _dt(app['occurrenceEndAt']),
      personName: personName,
      itemLabel: _partyItemLabel(app),
      statusLabel: checkedIn ? '체크인 완료' : '참가 확정',
      state: checkedIn ? CheckInPassState.used : CheckInPassState.ready,
      notice: _paymentNotice(app['payment']),
    );
  }

  /// '1+2차 통합권' / '2차' / '참가 1명' — 무엇으로 들어가는지 한 줄.
  static String _partyItemLabel(Map<String, dynamic> app) {
    final packageName = app['packageName'] as String?;
    if (packageName != null && packageName.isNotEmpty) return packageName;
    final rounds = (app['selectedRounds'] as List?)
        ?.map((e) => (e as num?)?.toInt())
        .whereType<int>()
        .toList();
    if (rounds != null && rounds.isNotEmpty) {
      return rounds.map((n) => '$n차').join(', ');
    }
    return '참가 1명';
  }

  /// 결제가 아직 안 끝난 건에만 붙는 한 줄.
  ///
  /// 서버 판정(checkInRules.paymentBlockReason)과 **같은 뜻**을 손님 말로 옮긴
  /// 것이다 — QR은 있지만 돈이 확인되기 전에는 통과하지 않는다는 사실을
  /// 현장에 가기 전에 알려 준다. 판정 자체는 하지 않는다(서버가 한다).
  static String? _paymentNotice(Object? raw) {
    if (raw is! Map) return null;
    final status = raw['status'] as String?;
    if (status == null || status == 'paid') return null;
    return raw['method'] == 'on_site'
        ? '현장에서 결제한 뒤에 입장할 수 있어요.'
        : '입금이 확인된 뒤에 입장할 수 있어요.';
  }

  static DateTime? _dt(Object? v) =>
      v is Timestamp ? v.toDate().toLocal() : (v is DateTime ? v : null);
}
