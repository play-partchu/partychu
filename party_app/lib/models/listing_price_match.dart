// 💳 가격 조건 판정 — 종류마다 **이미 쓰던 규칙 그대로**를 한곳에 모은 것이다.
//
// 새 가격 체계가 아니다. 목록 탭이 쓰던 판정을 그대로 옮겨 와서 목록과 지도가
// 같은 함수를 부르게 한다(예전에는 같은 switch가 목록·지도에 따로 있었다).
// 종류마다 값의 성질이 달라 칸도 규칙도 다르다:
//
//   · 🎉 파티      — 참가비 숫자([PartyPricing.displayPrice], 성별가는 낮은 쪽).
//                   [PartyFilter.feeRanges], 칸은 [partyFeeRanges].
//   · 🏠 장소대여  — 시간당 요금 숫자(pricePerHour). [PlaceFilter.priceRanges],
//                   칸은 [ListingConstants.placePriceRanges].
//   · 🏬 플레이스  — 등록할 때 고른 **가격대 라벨 문자열**(priceRange). 숫자가
//                   없으므로 라벨이 그대로 같은지만 본다.
//                   [EventFilter.priceRanges], 칸은 [ListingConstants.eventPriceRanges].
//
// 🎊 공공 축제는 이 판정을 걸지 않는다 — 원본에 금액 숫자가 없다(요금은
// '무료(일부 유료)' 같은 자유 문장뿐이라 어느 가격대에도 넣을 수 없다).
import 'package:party_app/models/party_pricing.dart';
import 'package:party_app/models/room_price_type.dart';

/// 🎉 파티 참가비 칸 — 상세검색 시트의 참가비와 **같은 목록**이다.
const List<String> partyFeeRanges = [
  '무료',
  '1만원 이하',
  '1~3만원',
  '3~5만원',
  '5~10만원',
  '10~20만원',
  '20만원 이상',
];

/// 참가비 [fee]원이 칸 [range]에 드는가. 모르는 칸은 거르지 않는다(true).
bool partyFeeInRange(int fee, String range) {
  switch (range) {
    case '무료':
      return fee <= 0;
    case '1만원 이하':
      return fee > 0 && fee <= 10000;
    case '1~3만원':
      return fee > 10000 && fee <= 30000;
    case '3~5만원':
      return fee > 30000 && fee <= 50000;
    case '5~10만원':
      return fee > 50000 && fee <= 100000;
    case '10~20만원':
      return fee > 100000 && fee <= 200000;
    case '20만원 이상':
      return fee > 200000;
    default:
      return true;
  }
}

/// 장소대여 시간당 요금 [price]원이 칸 [range]에 드는가.
///
/// 가장 낮은 칸이 `price > 0`인 것은 예전 그대로다 — 0원(무료) 공간은 어느
/// 칸에도 들지 않는다.
bool rentalPriceInRange(int price, String range) {
  switch (range) {
    case '3만원 이하':
      return price > 0 && price <= 30000;
    case '3~5만원':
      return price > 30000 && price <= 50000;
    case '5~10만원':
      return price > 50000 && price <= 100000;
    case '10~20만원':
      return price > 100000 && price <= 200000;
    case '20만원 이상':
      return price > 200000;
    default:
      return true;
  }
}

/// 🎉 파티 문서가 고른 참가비 칸들 중 하나에 드는가. 칸이 비었으면 조건 없음.
bool partyFeeMatches(Map<String, dynamic> data, Set<String> ranges) {
  if (ranges.isEmpty) return true;
  final fee = PartyPricing.fromMap(data).displayPrice;
  return ranges.any((r) => partyFeeInRange(fee, r));
}

/// 🏠 장소대여 문서가 고른 가격 칸들 중 하나에 드는가.
///
/// **가격 문의 공간은 어느 칸에도 넣지 않는다** — 금액을 모르는 것이지 0원이
/// 아니다(0원으로 읽으면 가장 낮은 칸에 잘못 걸린다). 목록 탭과 같은 규칙이다.
bool rentalPriceMatches(Map<String, dynamic> data, Set<String> ranges) {
  if (ranges.isEmpty) return true;
  if (RoomPriceType.of(data) == RoomPriceType.inquiry) return false;
  final price = (data['pricePerHour'] as num?)?.toInt() ?? 0;
  return ranges.any((r) => rentalPriceInRange(price, r));
}

/// 🏬 플레이스 문서의 가격대 라벨이 고른 칸에 드는가.
///
/// 플레이스는 숫자가 없고 등록할 때 고른 라벨(priceRange) 하나뿐이라, 목록
/// 탭처럼 라벨이 같은지만 본다. 라벨이 없는 문서는 조건을 켜면 빠진다.
bool eventPriceMatches(Map<String, dynamic> data, Set<String> ranges) {
  if (ranges.isEmpty) return true;
  final range = (data['priceRange'] as String?) ?? '';
  return ranges.contains(range);
}
