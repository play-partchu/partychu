/// 통합 QR 체크인의 **공용 결과 한 벌**.
///
/// 호스트에게 스캐너는 하나뿐이므로 결과 화면도 하나다. 그래서 파티든 예약이든
/// 이용권이든 **같은 모양**으로 받아 같은 위젯이 그린다 — 유형별로 다른 값은
/// [detail]에 담기고, 화면은 있는 줄만 그린다.
///
/// 값은 전부 서버 `resolveCheckInToken`이 만든다(functions/checkInRules.js).
/// 화면이 Firestore를 직접 뒤져 종류를 판별하지 않는다 — 그렇게 하면 권한
/// 검증이 화면마다 흩어지고, 게스트가 남의 QR로 문서를 열어보는 길이 생긴다.
library;

import 'package:party_app/utils/applicant_identity.dart';

/// QR 하나가 가리키는 이용의 종류. 문자열은 서버 저장값이라 변경 금지.
enum CheckInDomain {
  party('party', '파티'),
  reservation('place_reservation', '예약'),
  voucher('product_voucher', '이용권'),

  /// 서버가 모르는 값을 돌려준 경우(앱이 서버보다 오래됨).
  unknown('', 'QR');

  const CheckInDomain(this.key, this.label);

  final String key;
  final String label;

  static CheckInDomain fromKey(String? key) {
    for (final d in values) {
      if (d.key.isNotEmpty && d.key == key) return d;
    }
    return unknown;
  }
}

/// 지금 이 QR로 무엇을 할 수 있는가.
enum CheckInStatus {
  /// 사용 처리 가능.
  ready('ready'),

  /// 이미 체크인·사용 완료 — 다시 찍어도 소용없다.
  done('done'),

  /// 지금은 쓸 수 없다(결제 전·날짜 아님·취소됨 …).
  blocked('blocked');

  const CheckInStatus(this.key);

  final String key;

  static CheckInStatus fromKey(String? key) {
    for (final s in values) {
      if (s.key == key) return s;
    }
    return blocked;
  }
}

/// 스캔 결과 한 건.
class CheckInResult {
  const CheckInResult({
    required this.ok,
    required this.domain,
    required this.status,
    required this.guest,
    this.blockReason,
    this.title = '',
    this.subtitle = '',
    this.at,
    this.endAt,
    this.people,
    this.quantity,
    this.purchasedItem = '',
    this.paymentMethod,
    this.paymentStatus,
    this.paymentAmount,
    this.checkedInAt,
    this.detail = const {},
    this.canConfirmPayment = false,
  });

  /// 지금 '사용 처리' 버튼을 열어도 되는가.
  final bool ok;

  final CheckInDomain domain;
  final CheckInStatus status;

  /// 호스트에게 보여줄 신원 — 파티 신청자 목록과 **같은 정본**이다
  /// ([ApplicantIdentity]). 나이는 여기서 계산한다(서버가 보내지 않는다).
  ///
  /// 토큰을 못 찾았거나 권한이 없으면 null이다 — 그때는 아무 정보도 없다.
  final ApplicantIdentity? guest;

  /// 막힌 이유(서버가 만든 한글 문장). 없으면 null.
  final String? blockReason;

  /// 파티명 · 플레이스명.
  final String title;

  /// 장소 · 객실/패키지 이름 등 제목 아래 한 줄.
  final String subtitle;

  /// 파티 일시 · 예약 시작 · 이용 예정일.
  final DateTime? at;

  /// 예약 종료(숙박 체크아웃 등). 없으면 null.
  final DateTime? endAt;

  /// 예약 인원 — 파티 신청은 1.
  final int? people;

  /// 이용권 수량.
  final int? quantity;

  /// 구매한 상품·이용권·객실 이름.
  final String purchasedItem;

  /// 'bank_transfer' | 'on_site' — 결제가 없는 건은 null.
  final String? paymentMethod;

  /// 'awaiting_deposit' | 'on_site_scheduled' | 'paid' … — 없으면 null.
  final String? paymentStatus;

  final int? paymentAmount;

  /// 이미 처리된 건의 처리 시각.
  final DateTime? checkedInAt;

  /// 유형별 부가 정보. 화면은 아는 키만 읽는다.
  final Map<String, dynamic> detail;

  /// 이 화면에서 곧바로 현장결제·입금을 확인할 수 있는가.
  /// 확인하면 그 순간 이용권이 발급되고 사용 처리가 열린다.
  final bool canConfirmPayment;

  /// 서버가 "권한 없음/없는 QR"로 돌려준 응답인지 — 이때는 아무것도 없다.
  bool get isEmpty => guest == null && title.isEmpty;

  static DateTime? _ms(Object? v) {
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    return null;
  }

  static int? _int(Object? v) => v is num ? v.toInt() : null;

  factory CheckInResult.fromMap(Map<Object?, Object?> m) {
    final rawGuest = m['guest'];
    return CheckInResult(
      ok: m['ok'] == true,
      domain: CheckInDomain.fromKey(m['domain'] as String?),
      status: CheckInStatus.fromKey(m['checkInStatus'] as String?),
      guest: rawGuest is Map<Object?, Object?>
          ? ApplicantIdentity.fromMap(rawGuest)
          : null,
      blockReason: (m['blockReason'] as String?)?.isNotEmpty == true
          ? m['blockReason'] as String
          : null,
      title: m['title'] as String? ?? '',
      subtitle: m['subtitle'] as String? ?? '',
      at: _ms(m['atMs']),
      endAt: _ms(m['endAtMs']),
      people: _int(m['people']),
      quantity: _int(m['quantity']),
      purchasedItem: m['purchasedItem'] as String? ?? '',
      paymentMethod: m['paymentMethod'] as String?,
      paymentStatus: m['paymentStatus'] as String?,
      paymentAmount: _int(m['paymentAmount']),
      checkedInAt: _ms(m['checkedInAtMs']),
      detail: m['detail'] is Map
          ? Map<String, dynamic>.from(m['detail'] as Map)
          : const {},
      canConfirmPayment: m['canConfirmPayment'] == true,
    );
  }
}
