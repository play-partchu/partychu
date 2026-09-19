// ─────────────────────────────────────────────────────────────────────────────
// 장소대여 룸(옵션)의 가격 방식 — 가격을 정해 두는가, 문의로 받는가.
//
// 예: 클럽 통대관처럼 날짜·인원에 따라 금액이 달라 미리 적을 수 없는 옵션.
// 숫자 0원으로 두면 화면에 '₩0 / 시간'·'무료'로 보이고 즉시 예약까지 열린다 —
// 그래서 **문의로 받는다**는 사실을 따로 적는다.
//
// Firestore
//   placeRooms/{id}.priceType : 'fixed' | 'inquiry'
//   places/{id}.priceType     : 'fixed' | 'inquiry'  ← 룸이 전부 문의일 때
//                                                    카드 대표가를 '가격 문의'로
//
// **필드가 없으면 fixed다.** 이 필드가 생기기 전의 룸·장소는 모두 기존 그대로
// 숫자 요금(pricePerHour·1박 요금)으로 읽히고 예약된다.
// ─────────────────────────────────────────────────────────────────────────────

enum RoomPriceType {
  /// 숫자 요금 — 기존 동작 그대로(시간당·1박 요금으로 예약).
  fixed('fixed'),

  /// 가격 문의 — 숫자를 보이지 않고, 예약 대신 문의하기로 연결한다.
  inquiry('inquiry');

  const RoomPriceType(this.key);

  /// Firestore에 저장되는 값.
  final String key;

  /// 룸·장소 문서에서 쓰는 필드 이름.
  static const String field = 'priceType';

  /// 문서에서 읽는다 — 없거나 모르는 값이면 [fixed].
  static RoomPriceType of(Map<String, dynamic>? data) =>
      data?[field] == inquiry.key ? inquiry : fixed;
}

/// 가격 대신 보여주는 문구.
const String kInquiryPriceLabel = '가격 문의';

/// 이 룸이 가격 문의 옵션인지 — 예약·결제 대상이 아니다.
bool isInquiryRoom(Map<String, dynamic>? room) =>
    RoomPriceType.of(room) == RoomPriceType.inquiry;

/// 장소대여 문서의 대표가가 '가격 문의'인지(숫자 요금 룸이 하나도 없다).
bool isInquiryPlace(Map<String, dynamic>? place) =>
    RoomPriceType.of(place) == RoomPriceType.inquiry;
