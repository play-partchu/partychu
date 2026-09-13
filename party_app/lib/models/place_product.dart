// ─────────────────────────────────────────────────────────────────────────────
// 플레이스 공통 "상품·이용권" 모델.
//
// 술집·바·카페(`events`)와 공간대여·숙박(`places`)이 **같은 구조 하나**를 쓴다.
// 업종별로 상품 스키마를 따로 만들면 카드/구매/QR/정산 화면이 전부 두 벌이
// 되므로, 공통 필드 + 유형별 부가 필드([typeData]) 한 겹으로 통일한다.
//
// Firestore 저장 형태
//   placeProducts/{productId}
//     placeId        : 소속 플레이스 문서 id
//     placeCollection: 'events' | 'places'  ← 어느 컬렉션의 플레이스인지
//     type           : PlaceProductType.key
//     typeData       : { 유형별 부가 필드 }   ← 유형이 늘어도 스키마 변경 없음
//     ...공통 필드
//
// 예약(placeReservationGroups·packageBookings)과 파티 결제(applications)는
// 전혀 건드리지 않는 **독립 컬렉션**이다. 다만 [PlaceProductSaleChannel]로
// "예약에 붙는 부가상품"도 표현할 수 있고, 주문 문서가 예약 id를 함께 들고
// 있어 나중에 예약 상세에서 되짚을 수 있다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';

/// 판매 유형 13종. 선언 순서가 곧 드롭다운 표시 순서다.
enum PlaceProductType {
  // 이름에 '유료'를 붙여 둔 이유 — 결제 없이 신청하는 **방문 예약**
  // ([PlaceVisitReservationConfig])이 따로 있어서, 그냥 '좌석 예약'이라고 하면
  // 업주도 손님도 둘을 구분하지 못한다. 이쪽은 돈을 내고 자리를 사는 상품이다.
  seatReservation('seat', '🪑', '유료 좌석권'),
  ticket('ticket', '🎟', '입장권'),
  drinkVoucher('drink', '🍹', '음료 이용권'),
  foodVoucher('food', '🍽', '음식·안주 이용권'),
  bottle('bottle', '🍾', '바틀·주류 예약'),
  timePass('time_pass', '⏱', '시간제 이용권'),
  unlimitedPass('unlimited', '♾️', '무제한 이용권'),
  packageDeal('package', '📦', '패키지 상품'),
  experience('experience', '🎯', '체험·게임 참가권'),
  dailyDeal('daily_deal', '⚡', '오늘의 특가'),
  stamp('stamp', '🔖', '스탬프 적립권'),
  membership('membership', '💳', '멤버십'),
  etc('etc', '🎁', '기타 상품');

  const PlaceProductType(this.key, this.emoji, this.label);

  /// Firestore에 저장되는 안정적 식별자 — 라벨이 바뀌어도 이 값은 고정이다.
  final String key;
  final String emoji;
  final String label;

  /// 카드 배지에 그대로 쓰는 문구 — "🪑 유료 좌석권".
  String get badgeLabel => '$emoji $label';

  /// 모르는 값이면 [etc]로 본다 — 새 유형이 붙은 서버 데이터를 옛 앱이
  /// 읽어도 목록에서 사라지지 않고 "기타 상품"으로라도 보이게 하려는 것.
  static PlaceProductType fromKey(String? key) {
    for (final t in PlaceProductType.values) {
      if (t.key == key) return t;
    }
    return PlaceProductType.etc;
  }

  /// 이 유형이 "날짜·시간을 지정해 쓰는" 상품인지 — QR 사용 처리 때 서버가
  /// 예약 일시까지 검증해야 하는 유형들이다([PlaceProductOrder.useAt]).
  bool get isDateBound => switch (this) {
    PlaceProductType.seatReservation ||
    PlaceProductType.ticket ||
    PlaceProductType.bottle ||
    PlaceProductType.experience => true,
    _ => false,
  };
}

/// 판매 방식 — 단독으로 파는 상품인지, 예약에 붙는 부가상품인지.
///
/// 공간대여·숙박에서 "조식 이용권"처럼 숙박 예약에 얹어 파는 상품과, 로비에서
/// 따로 파는 상품을 같은 구조로 다루기 위한 축이다.
enum PlaceProductSaleChannel {
  standalone('standalone', '단독 판매'),
  reservationAddon('reservation_addon', '예약 시 추가 옵션으로 판매'),
  both('both', '단독 판매 및 예약 추가 옵션 모두 사용');

  const PlaceProductSaleChannel(this.key, this.label);

  final String key;
  final String label;

  bool get allowsStandalone => this != PlaceProductSaleChannel.reservationAddon;
  bool get allowsAddon => this != PlaceProductSaleChannel.standalone;

  static PlaceProductSaleChannel fromKey(String? key) {
    for (final c in PlaceProductSaleChannel.values) {
      if (c.key == key) return c;
    }
    return PlaceProductSaleChannel.standalone;
  }
}

/// 상품 판매 상태. [PlaceProduct.statusAt]이 기간·재고·수동중지에서 계산하므로
/// 이 값을 Firestore에 정본으로 저장하지 않는다(저장하면 시간이 지나며 틀어진다).
/// 다만 목록 쿼리를 위해 파생값을 미러로 함께 적는다([PlaceProduct.toMap]).
enum PlaceProductStatus {
  scheduled('scheduled', '판매 예정'),
  onSale('on_sale', '판매 중'),
  soldOut('sold_out', '품절'),
  ended('ended', '판매 종료'),
  stopped('stopped', '판매 중지');

  const PlaceProductStatus(this.key, this.label);

  final String key;
  final String label;

  /// 지금 구매 버튼을 누를 수 있는 상태인가.
  bool get isBuyable => this == PlaceProductStatus.onSale;

  static PlaceProductStatus fromKey(String? key) {
    for (final s in PlaceProductStatus.values) {
      if (s.key == key) return s;
    }
    return PlaceProductStatus.onSale;
  }
}

/// 주문(이용권) 상태.
///
/// `결제 완료`와 `사용 가능`을 나눈 이유 — 결제는 끝났지만 이용 시작일이 아직
/// 안 온 상품(예: 다음 주 행사 입장권)이 있어서다. QR 사용 처리는 반드시
/// [usable] 상태에서만 통과시킨다.
enum PlaceProductOrderStatus {
  paymentPending('payment_pending', '결제 대기'),
  paid('paid', '결제 완료'),
  usable('usable', '사용 가능'),
  used('used', '사용 완료'),
  cancelled('cancelled', '취소'),
  refunded('refunded', '환불'),
  expired('expired', '기간 만료');

  const PlaceProductOrderStatus(this.key, this.label);

  final String key;
  final String label;

  /// 이 상태에서 QR 사용 처리를 받아줄 수 있는가 — 서버 검증의 1차 조건.
  bool get isRedeemable => this == PlaceProductOrderStatus.usable;

  /// 사용자가 "아직 살아 있는 이용권"으로 보게 되는 상태.
  bool get isAlive =>
      this == PlaceProductOrderStatus.paid ||
      this == PlaceProductOrderStatus.usable;

  static PlaceProductOrderStatus fromKey(String? key) {
    for (final s in PlaceProductOrderStatus.values) {
      if (s.key == key) return s;
    }
    return PlaceProductOrderStatus.paymentPending;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 유형별 입력 항목 명세
//
// 등록 폼·검증·상세 표시가 전부 이 명세 하나를 읽는다 — 유형을 추가할 때
// 화면 코드를 건드리지 않고 여기 한 곳만 늘리면 되게 하려는 것.
// ─────────────────────────────────────────────────────────────────────────────

/// 입력칸의 종류 — 등록 폼이 어떤 위젯을 그릴지 결정한다.
enum ProductFieldKind {
  /// 한 줄 텍스트.
  text,

  /// 여러 줄 텍스트.
  multiline,

  /// 정수(개수·횟수·인원 등).
  count,

  /// 금액(원).
  money,

  /// 날짜 하나.
  date,

  /// 시각 하나('HH:mm').
  time,

  /// 분 단위 소요/이용 시간.
  minutes,

  /// 켜기/끄기.
  toggle,

  /// [ProductFieldSpec.choices] 중 하나 선택(직접 입력 허용 가능).
  choice,

  /// 자유롭게 여러 줄 항목을 추가하는 목록(포함 항목·혜택 등).
  itemList,
}

/// 유형별 부가 입력칸 하나의 명세.
class ProductFieldSpec {
  const ProductFieldSpec({
    required this.key,
    required this.label,
    required this.kind,
    this.choices = const [],
    this.allowCustomChoice = false,
    this.required = false,
    this.hint,
  });

  /// [PlaceProduct.typeData] 안에서 쓰는 키.
  final String key;
  final String label;
  final ProductFieldKind kind;

  /// [ProductFieldKind.choice]일 때의 보기.
  final List<String> choices;

  /// 보기 말고 직접 입력도 받을지("기타 직접 입력").
  final bool allowCustomChoice;

  final bool required;
  final String? hint;
}

/// 좌석 종류 보기 — 사장님이 가장 자주 쓰는 값들을 미리 채워두고, 없으면
/// 직접 입력하게 한다.
const List<String> kSeatKindChoices = [
  '일반 테이블',
  '바 테이블',
  '창가석',
  '소파석',
  '단체석',
  '룸',
  'VIP석',
];

/// 유형별 부가 입력 항목. 공통 항목([kCommonProductFields] 성격의 값들)은
/// [PlaceProduct]의 정식 필드라 여기 넣지 않는다.
const Map<PlaceProductType, List<ProductFieldSpec>> kProductTypeFields = {
  PlaceProductType.seatReservation: [
    ProductFieldSpec(
      key: 'seatKind',
      label: '좌석 종류',
      kind: ProductFieldKind.choice,
      choices: kSeatKindChoices,
      allowCustomChoice: true,
      required: true,
    ),
    ProductFieldSpec(
      key: 'useDate',
      label: '이용 날짜',
      kind: ProductFieldKind.date,
    ),
    ProductFieldSpec(
      key: 'startTime',
      label: '시작 시간',
      kind: ProductFieldKind.time,
    ),
    ProductFieldSpec(
      key: 'endTime',
      label: '종료 시간',
      kind: ProductFieldKind.time,
    ),
    ProductFieldSpec(
      key: 'useMinutes',
      label: '이용 시간',
      kind: ProductFieldKind.minutes,
      hint: '종료 시간 대신 이용 시간으로 정할 수도 있어요',
    ),
    ProductFieldSpec(
      key: 'capacity',
      label: '예약 가능 인원',
      kind: ProductFieldKind.count,
    ),
    ProductFieldSpec(
      key: 'seatCount',
      label: '예약 가능 좌석 수',
      kind: ProductFieldKind.count,
    ),
    ProductFieldSpec(
      key: 'depositOnly',
      label: '예약금만 받기',
      kind: ProductFieldKind.toggle,
      hint: '끄면 전체 금액을 결제받아요',
    ),
    ProductFieldSpec(
      key: 'visitTime',
      label: '방문 예정 시간',
      kind: ProductFieldKind.time,
    ),
  ],
  PlaceProductType.ticket: [
    ProductFieldSpec(
      key: 'eventName',
      label: '행사명',
      kind: ProductFieldKind.text,
      required: true,
    ),
    ProductFieldSpec(
      key: 'eventDate',
      label: '행사 날짜',
      kind: ProductFieldKind.date,
    ),
    ProductFieldSpec(
      key: 'entryOpenTime',
      label: '입장 시작 시간',
      kind: ProductFieldKind.time,
    ),
    ProductFieldSpec(
      key: 'entryCloseTime',
      label: '입장 마감 시간',
      kind: ProductFieldKind.time,
    ),
    ProductFieldSpec(
      key: 'capacity',
      label: '입장 가능 인원',
      kind: ProductFieldKind.count,
    ),
    ProductFieldSpec(
      key: 'ticketCount',
      label: '티켓 수량',
      kind: ProductFieldKind.count,
    ),
    ProductFieldSpec(
      key: 'ticketKind',
      label: '권종',
      kind: ProductFieldKind.choice,
      choices: ['1인권', '2인권', '단체권'],
      allowCustomChoice: true,
    ),
  ],
  PlaceProductType.drinkVoucher: [
    ProductFieldSpec(
      key: 'drinkName',
      label: '음료명',
      kind: ProductFieldKind.text,
      required: true,
    ),
    ProductFieldSpec(
      key: 'servingCount',
      label: '제공 수량',
      kind: ProductFieldKind.count,
    ),
    ProductFieldSpec(
      key: 'drinkOptions',
      label: '옵션 선택',
      kind: ProductFieldKind.itemList,
      hint: '생맥주, 칵테일, 커피, 웰컴드링크 등',
    ),
    ProductFieldSpec(
      key: 'exchangeFrom',
      label: '교환 가능 시작 시간',
      kind: ProductFieldKind.time,
    ),
    ProductFieldSpec(
      key: 'exchangeTo',
      label: '교환 가능 종료 시간',
      kind: ProductFieldKind.time,
    ),
  ],
  PlaceProductType.foodVoucher: [
    ProductFieldSpec(
      key: 'menuName',
      label: '메뉴명',
      kind: ProductFieldKind.text,
      required: true,
    ),
    ProductFieldSpec(
      key: 'servingCount',
      label: '제공 수량',
      kind: ProductFieldKind.count,
    ),
    ProductFieldSpec(
      key: 'visitDate',
      label: '방문 날짜',
      kind: ProductFieldKind.date,
    ),
    ProductFieldSpec(
      key: 'pickupTime',
      label: '수령 시간',
      kind: ProductFieldKind.time,
    ),
    ProductFieldSpec(
      key: 'serveOnArrival',
      label: '도착 즉시 제공',
      kind: ProductFieldKind.toggle,
    ),
    ProductFieldSpec(
      key: 'extraOptions',
      label: '추가 옵션',
      kind: ProductFieldKind.itemList,
    ),
  ],
  PlaceProductType.bottle: [
    ProductFieldSpec(
      key: 'liquorName',
      label: '주류명',
      kind: ProductFieldKind.text,
      required: true,
    ),
    ProductFieldSpec(
      key: 'volume',
      label: '용량',
      kind: ProductFieldKind.text,
      hint: '예: 700ml',
    ),
    ProductFieldSpec(
      key: 'bottleCount',
      label: '수량',
      kind: ProductFieldKind.count,
    ),
    ProductFieldSpec(
      key: 'keepService',
      label: '보관(킵) 가능',
      kind: ProductFieldKind.toggle,
    ),
    ProductFieldSpec(
      key: 'setupService',
      label: '세팅 제공',
      kind: ProductFieldKind.toggle,
    ),
    ProductFieldSpec(
      key: 'visitDate',
      label: '방문 날짜',
      kind: ProductFieldKind.date,
    ),
    ProductFieldSpec(
      key: 'visitTime',
      label: '방문 시간',
      kind: ProductFieldKind.time,
    ),
  ],
  PlaceProductType.timePass: [
    ProductFieldSpec(
      key: 'useMinutes',
      label: '이용 시간',
      kind: ProductFieldKind.minutes,
      required: true,
      hint: '1시간·2시간·4시간처럼 자주 쓰는 값 또는 직접 설정',
    ),
    ProductFieldSpec(
      key: 'availableFrom',
      label: '이용 시작 가능 시간',
      kind: ProductFieldKind.time,
    ),
    ProductFieldSpec(
      key: 'availableTo',
      label: '이용 종료 가능 시간',
      kind: ProductFieldKind.time,
    ),
    ProductFieldSpec(
      key: 'capacity',
      label: '이용 인원',
      kind: ProductFieldKind.count,
    ),
    ProductFieldSpec(
      key: 'extendable',
      label: '연장 가능',
      kind: ProductFieldKind.toggle,
    ),
    ProductFieldSpec(
      key: 'extendPrice',
      label: '연장 추가 금액',
      kind: ProductFieldKind.money,
    ),
  ],
  PlaceProductType.unlimitedPass: [
    ProductFieldSpec(
      key: 'includedItems',
      label: '제공 항목',
      kind: ProductFieldKind.itemList,
      required: true,
    ),
    ProductFieldSpec(
      key: 'availableFrom',
      label: '이용 가능 시작 시간',
      kind: ProductFieldKind.time,
    ),
    ProductFieldSpec(
      key: 'availableTo',
      label: '이용 가능 종료 시간',
      kind: ProductFieldKind.time,
    ),
    ProductFieldSpec(
      key: 'useMinutes',
      label: '이용 시간',
      kind: ProductFieldKind.minutes,
    ),
    ProductFieldSpec(
      key: 'restrictions',
      label: '이용 제한 및 주의사항',
      kind: ProductFieldKind.multiline,
    ),
  ],
  PlaceProductType.packageDeal: [
    ProductFieldSpec(
      key: 'includedItems',
      label: '포함 항목',
      kind: ProductFieldKind.itemList,
      required: true,
      hint: '예: 창가석 + 칵테일 2잔 + 안주',
    ),
    ProductFieldSpec(
      key: 'capacity',
      label: '이용 인원',
      kind: ProductFieldKind.count,
    ),
    ProductFieldSpec(
      key: 'useMinutes',
      label: '이용 시간',
      kind: ProductFieldKind.minutes,
    ),
    ProductFieldSpec(
      key: 'optionSurcharge',
      label: '옵션 추가금',
      kind: ProductFieldKind.money,
    ),
  ],
  PlaceProductType.experience: [
    ProductFieldSpec(
      key: 'programName',
      label: '프로그램명',
      kind: ProductFieldKind.text,
      required: true,
    ),
    ProductFieldSpec(
      key: 'sessionDate',
      label: '진행 날짜',
      kind: ProductFieldKind.date,
    ),
    ProductFieldSpec(
      key: 'sessionTime',
      label: '진행 시간',
      kind: ProductFieldKind.time,
    ),
    ProductFieldSpec(
      key: 'durationMinutes',
      label: '소요 시간',
      kind: ProductFieldKind.minutes,
    ),
    ProductFieldSpec(
      key: 'capacity',
      label: '정원',
      kind: ProductFieldKind.count,
    ),
    ProductFieldSpec(
      key: 'requirements',
      label: '준비물 또는 참가 조건',
      kind: ProductFieldKind.multiline,
    ),
  ],
  PlaceProductType.dailyDeal: [
    ProductFieldSpec(
      key: 'dealPrice',
      label: '특가 가격',
      kind: ProductFieldKind.money,
      required: true,
    ),
    ProductFieldSpec(
      key: 'limitedCount',
      label: '한정 수량',
      kind: ProductFieldKind.count,
    ),
    ProductFieldSpec(
      key: 'saleEndTime',
      label: '판매 종료 시각',
      kind: ProductFieldKind.time,
    ),
    ProductFieldSpec(
      key: 'sameDayOnly',
      label: '당일만 사용 가능',
      kind: ProductFieldKind.toggle,
    ),
    ProductFieldSpec(
      key: 'autoEndWhenSoldOut',
      label: '품절 시 자동 판매 종료',
      kind: ProductFieldKind.toggle,
    ),
  ],
  PlaceProductType.stamp: [
    ProductFieldSpec(
      key: 'earnCondition',
      label: '적립 조건',
      kind: ProductFieldKind.text,
      required: true,
      hint: '예: 1만원 이상 결제 시 1개',
    ),
    ProductFieldSpec(
      key: 'targetCount',
      label: '목표 횟수',
      kind: ProductFieldKind.count,
    ),
    ProductFieldSpec(
      key: 'reward',
      label: '달성 보상',
      kind: ProductFieldKind.text,
    ),
    ProductFieldSpec(
      key: 'validDays',
      label: '스탬프 유효기간(일)',
      kind: ProductFieldKind.count,
    ),
    ProductFieldSpec(
      key: 'dailyEarnLimit',
      label: '1일 적립 제한',
      kind: ProductFieldKind.count,
    ),
  ],
  PlaceProductType.membership: [
    ProductFieldSpec(
      key: 'periodKind',
      label: '이용 기간',
      kind: ProductFieldKind.choice,
      choices: ['월간', '기간제'],
      required: true,
    ),
    ProductFieldSpec(
      key: 'periodDays',
      label: '이용 일수',
      kind: ProductFieldKind.count,
    ),
    ProductFieldSpec(
      key: 'benefits',
      label: '멤버십 혜택',
      kind: ProductFieldKind.itemList,
    ),
    ProductFieldSpec(
      key: 'autoRenew',
      label: '자동 갱신',
      kind: ProductFieldKind.toggle,
    ),
    ProductFieldSpec(
      key: 'useLimit',
      label: '이용 횟수 제한',
      kind: ProductFieldKind.count,
    ),
  ],
  PlaceProductType.etc: [
    ProductFieldSpec(
      key: 'freeConditions',
      label: '이용 조건',
      kind: ProductFieldKind.multiline,
      hint: '상품 조건을 자유롭게 적어주세요',
    ),
  ],
};

/// [type]이 쓰는 부가 입력 항목 — 정의가 없으면 빈 목록.
List<ProductFieldSpec> fieldsForProductType(PlaceProductType type) =>
    kProductTypeFields[type] ?? const [];

/// 상품·이용권의 **'취소·환불 규정' 텍스트 규칙** — 빈 문자열 금지.
///
/// 파티·장소대여의 티어형 환불 규정(`RefundPolicyRule`)과는 **별개**다. 그쪽은
/// "N일 전 → X% 환불" 구간 목록이라 '최소 1개 구간'으로 세지만, 상품의
/// [PlaceProduct.refundPolicy]는 호스트가 자유롭게 적는 안내문 하나라 셀 구간이
/// 없다. 그래서 규칙도 문구도 여기 따로 둔다 — 두 개념을 한 규칙에 욱여넣으면
/// 어느 쪽을 고쳐도 다른 쪽이 이상해진다.
///
/// 상품·이용권 판매 자체는 여전히 **선택**이다. 이 규칙은 상품을 하나라도
/// 등록했을 때만 그 상품에 대해 적용된다.
///
/// 규정 없이 저장돼 있던 옛 상품은 **열람·수정 화면 진입까지 그대로** 열린다.
/// 막는 것은 저장 시점 하나뿐이다.
class PlaceProductRefundPolicyRule {
  PlaceProductRefundPolicyRule._();

  /// 입력칸 라벨 — 화면과 검증이 같은 이름을 쓰도록.
  static const String fieldLabel = '취소·환불 규정';

  /// 비었을 때 보여주는 안내.
  static const String requiredMessage = '상품의 취소·환불 규정을 입력해주세요.';

  /// 이 상품의 규정이 비었는가.
  static bool isMissingFor(PlaceProduct product) =>
      product.refundPolicy.trim().isEmpty;

  /// 규정이 빈 첫 상품의 위치 — 없으면 -1.
  static int firstMissingIndex(List<PlaceProduct> products) {
    for (var i = 0; i < products.length; i++) {
      if (isMissingFor(products[i])) return i;
    }
    return -1;
  }

  /// 규정이 빈 상품이 하나라도 있는가 — 저장을 막아야 하는 상태.
  static bool anyMissing(List<PlaceProduct> products) =>
      firstMissingIndex(products) >= 0;

  /// 저장 전 검증 — 통과하면 null, 아니면 [requiredMessage].
  static String? validate(List<PlaceProduct> products) =>
      anyMissing(products) ? requiredMessage : null;

  /// `TextFormField.validator`에 그대로 꽂는 형태.
  static String? validateText(String? value) =>
      (value ?? '').trim().isEmpty ? requiredMessage : null;
}

// ─────────────────────────────────────────────────────────────────────────────
// 상품 문서
// ─────────────────────────────────────────────────────────────────────────────

/// 플레이스가 파는 상품·이용권 한 건.
class PlaceProduct {
  const PlaceProduct({
    required this.id,
    required this.placeId,
    required this.placeCollection,
    required this.hostId,
    required this.type,
    required this.saleChannel,
    required this.name,
    required this.imageUrl,
    required this.description,
    required this.listPrice,
    required this.salePrice,
    required this.totalStock,
    required this.soldCount,
    required this.perPersonLimit,
    required this.saleStartAt,
    required this.saleEndAt,
    required this.useStartAt,
    required this.useEndAt,
    required this.useGuide,
    required this.refundPolicy,
    required this.useQrCheck,
    required this.manuallyStopped,
    required this.sortOrder,
    required this.typeData,
  });

  final String id;

  /// 소속 플레이스 문서 id.
  final String placeId;

  /// 플레이스가 어느 컬렉션 문서인지 — 술집·바·카페는 `events`,
  /// 공간대여·숙박은 `places`. 상품은 한 컬렉션에 모으고 이 값으로 되짚는다.
  final String placeCollection;

  /// 판매자(사장님) uid — 관리 화면 권한과 QR 사용 처리 권한의 기준.
  final String hostId;

  final PlaceProductType type;
  final PlaceProductSaleChannel saleChannel;

  // ── 공통 입력 ──────────────────────────────────────────────────────
  final String name;
  final String imageUrl;
  final String description;

  /// 정상 가격 — [salePrice]보다 크면 할인율을 계산해 보여준다.
  final int listPrice;

  /// 실제 결제 금액.
  final int salePrice;

  /// 판매 수량. 0이면 수량 제한 없음.
  final int totalStock;

  /// 지금까지 팔린 수량 — 결제 확정 시 서버가 올린다.
  final int soldCount;

  /// 1인당 구매 가능 수량. 0이면 제한 없음.
  final int perPersonLimit;

  final DateTime? saleStartAt;
  final DateTime? saleEndAt;
  final DateTime? useStartAt;
  final DateTime? useEndAt;

  final String useGuide;
  final String refundPolicy;

  /// QR 이용권을 발급할지 — 켜면 결제 후 주문마다 고유 QR이 생긴다.
  final bool useQrCheck;

  /// 사장님이 직접 판매를 멈춘 상태. 기간·재고와 무관하게 최우선이다.
  final bool manuallyStopped;

  /// 목록 표시 순서(작을수록 위). 순서 변경은 이 값만 다시 매긴다.
  final int sortOrder;

  /// 유형별 부가 필드 — 키는 [kProductTypeFields]의 [ProductFieldSpec.key].
  final Map<String, dynamic> typeData;

  /// 남은 수량. [totalStock]이 0(무제한)이면 null.
  int? get remainingStock =>
      totalStock <= 0 ? null : (totalStock - soldCount).clamp(0, totalStock);

  /// 할인율(%) — 정상가가 판매가보다 클 때만. 아니면 0.
  int get discountPercent {
    if (listPrice <= 0 || salePrice >= listPrice) return 0;
    return ((listPrice - salePrice) / listPrice * 100).round();
  }

  /// [now] 시점의 판매 상태.
  ///
  /// 우선순위 — 수동 중지 > 판매 종료 > 판매 예정 > 품절 > 판매 중.
  /// 품절을 기간보다 뒤에 두는 이유: 판매 기간이 끝난 상품은 남은 수량이
  /// 0이든 아니든 "판매 종료"로 읽는 게 사장님·구매자 모두에게 자연스럽다.
  PlaceProductStatus statusAt(DateTime now) {
    if (manuallyStopped) return PlaceProductStatus.stopped;
    if (saleEndAt != null && now.isAfter(saleEndAt!)) {
      return PlaceProductStatus.ended;
    }
    if (saleStartAt != null && now.isBefore(saleStartAt!)) {
      return PlaceProductStatus.scheduled;
    }
    final left = remainingStock;
    if (left != null && left <= 0) return PlaceProductStatus.soldOut;
    return PlaceProductStatus.onSale;
  }

  /// 오늘 바로 쓸 수 있는 상품인지 — 카드의 "오늘 사용 가능" 배지 판정.
  /// 이용 기간을 아예 안 정했으면 언제든 쓸 수 있다고 본다.
  bool isUsableOn(DateTime day) {
    if (useStartAt != null && day.isBefore(_dayStart(useStartAt!))) {
      return false;
    }
    if (useEndAt != null && day.isAfter(_dayEnd(useEndAt!))) return false;
    return true;
  }

  static DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _dayEnd(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59);

  factory PlaceProduct.fromMap(String id, Map<String, dynamic> d) {
    return PlaceProduct(
      id: id,
      placeId: d['placeId'] as String? ?? '',
      placeCollection: d['placeCollection'] as String? ?? 'events',
      hostId: d['hostId'] as String? ?? '',
      type: PlaceProductType.fromKey(d['type'] as String?),
      saleChannel: PlaceProductSaleChannel.fromKey(d['saleChannel'] as String?),
      name: d['name'] as String? ?? '',
      imageUrl: d['imageUrl'] as String? ?? '',
      description: d['description'] as String? ?? '',
      listPrice: (d['listPrice'] as num?)?.toInt() ?? 0,
      salePrice: (d['salePrice'] as num?)?.toInt() ?? 0,
      totalStock: (d['totalStock'] as num?)?.toInt() ?? 0,
      soldCount: (d['soldCount'] as num?)?.toInt() ?? 0,
      perPersonLimit: (d['perPersonLimit'] as num?)?.toInt() ?? 0,
      saleStartAt: _dateFrom(d['saleStartAt']),
      saleEndAt: _dateFrom(d['saleEndAt']),
      useStartAt: _dateFrom(d['useStartAt']),
      useEndAt: _dateFrom(d['useEndAt']),
      useGuide: d['useGuide'] as String? ?? '',
      refundPolicy: d['refundPolicy'] as String? ?? '',
      useQrCheck: d['useQrCheck'] as bool? ?? false,
      manuallyStopped: d['manuallyStopped'] as bool? ?? false,
      sortOrder: (d['sortOrder'] as num?)?.toInt() ?? 0,
      typeData: Map<String, dynamic>.from(
        (d['typeData'] as Map?) ?? const <String, dynamic>{},
      ),
    );
  }

  /// Firestore 저장 형태.
  ///
  /// [statusAt]으로 계산되는 판매 상태를 `statusMirror`로 함께 적는다 —
  /// 목록 쿼리(`where('statusMirror', isEqualTo: 'on_sale')`)에 쓰기 위한
  /// **파생 미러**라, 읽는 쪽은 반드시 [statusAt]을 정본으로 삼아야 한다
  /// (시간이 지나면 미러는 낡는다 — reservationMode 미러와 같은 취급).
  Map<String, dynamic> toMap({DateTime? now}) => {
    'placeId': placeId,
    'placeCollection': placeCollection,
    'hostId': hostId,
    'type': type.key,
    'saleChannel': saleChannel.key,
    'name': name,
    'imageUrl': imageUrl,
    'description': description,
    'listPrice': listPrice,
    'salePrice': salePrice,
    'totalStock': totalStock,
    'soldCount': soldCount,
    'perPersonLimit': perPersonLimit,
    'saleStartAt': _tsFrom(saleStartAt),
    'saleEndAt': _tsFrom(saleEndAt),
    'useStartAt': _tsFrom(useStartAt),
    'useEndAt': _tsFrom(useEndAt),
    'useGuide': useGuide,
    'refundPolicy': refundPolicy,
    'useQrCheck': useQrCheck,
    'manuallyStopped': manuallyStopped,
    'sortOrder': sortOrder,
    'typeData': typeData,
    'statusMirror': statusAt(now ?? DateTime.now()).key,
  };

  /// 임시저장(SharedPreferences JSON 미러)용 직렬화.
  ///
  /// [toMap]은 Firestore `Timestamp`를 담아 JSON으로 인코딩되지 않으므로,
  /// 날짜를 전부 밀리초로 바꾼 형태를 따로 만든다. 읽기는 [fromMap]이 두
  /// 형식을 모두 받아주므로([_dateFrom]) 복원 경로는 하나뿐이다.
  Map<String, dynamic> toDraftMap() => {
    ...toMap(),
    'id': id,
    'saleStartAt': saleStartAt?.millisecondsSinceEpoch,
    'saleEndAt': saleEndAt?.millisecondsSinceEpoch,
    'useStartAt': useStartAt?.millisecondsSinceEpoch,
    'useEndAt': useEndAt?.millisecondsSinceEpoch,
  };

  /// 임시저장에서 상품 목록을 되살린다 — 형식이 어긋난 항목은 조용히 건너뛴다.
  static List<PlaceProduct> listFromDraft(Object? raw) {
    if (raw is! List) return const [];
    final out = <PlaceProduct>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final map = Map<String, dynamic>.from(e);
      out.add(PlaceProduct.fromMap(map['id'] as String? ?? '', map));
    }
    return out;
  }

  static List<Map<String, dynamic>> listToDraft(List<PlaceProduct> items) =>
      items.map((p) => p.toDraftMap()).toList();

  PlaceProduct copyWith({
    String? id,
    PlaceProductType? type,
    PlaceProductSaleChannel? saleChannel,
    String? name,
    String? imageUrl,
    String? description,
    int? listPrice,
    int? salePrice,
    int? totalStock,
    int? soldCount,
    int? perPersonLimit,
    DateTime? saleStartAt,
    DateTime? saleEndAt,
    DateTime? useStartAt,
    DateTime? useEndAt,
    String? useGuide,
    String? refundPolicy,
    bool? useQrCheck,
    bool? manuallyStopped,
    int? sortOrder,
    Map<String, dynamic>? typeData,
  }) => PlaceProduct(
    id: id ?? this.id,
    placeId: placeId,
    placeCollection: placeCollection,
    hostId: hostId,
    type: type ?? this.type,
    saleChannel: saleChannel ?? this.saleChannel,
    name: name ?? this.name,
    imageUrl: imageUrl ?? this.imageUrl,
    description: description ?? this.description,
    listPrice: listPrice ?? this.listPrice,
    salePrice: salePrice ?? this.salePrice,
    totalStock: totalStock ?? this.totalStock,
    soldCount: soldCount ?? this.soldCount,
    perPersonLimit: perPersonLimit ?? this.perPersonLimit,
    saleStartAt: saleStartAt ?? this.saleStartAt,
    saleEndAt: saleEndAt ?? this.saleEndAt,
    useStartAt: useStartAt ?? this.useStartAt,
    useEndAt: useEndAt ?? this.useEndAt,
    useGuide: useGuide ?? this.useGuide,
    refundPolicy: refundPolicy ?? this.refundPolicy,
    useQrCheck: useQrCheck ?? this.useQrCheck,
    manuallyStopped: manuallyStopped ?? this.manuallyStopped,
    sortOrder: sortOrder ?? this.sortOrder,
    typeData: typeData ?? this.typeData,
  );

  /// 비어 있는 새 상품 초안 — 등록 화면의 "상품 추가"가 쓴다.
  factory PlaceProduct.empty({
    required String placeId,
    required String placeCollection,
    required String hostId,
    required int sortOrder,
    PlaceProductType type = PlaceProductType.seatReservation,
  }) => PlaceProduct(
    id: '',
    placeId: placeId,
    placeCollection: placeCollection,
    hostId: hostId,
    type: type,
    saleChannel: PlaceProductSaleChannel.standalone,
    name: '',
    imageUrl: '',
    description: '',
    listPrice: 0,
    salePrice: 0,
    totalStock: 0,
    soldCount: 0,
    perPersonLimit: 0,
    saleStartAt: null,
    saleEndAt: null,
    useStartAt: null,
    useEndAt: null,
    useGuide: '',
    refundPolicy: '',
    useQrCheck: false,
    manuallyStopped: false,
    sortOrder: sortOrder,
    typeData: const {},
  );
}

/// Firestore `Timestamp`/`DateTime`/밀리초 중 무엇이 와도 받아준다 —
/// 임시저장(SharedPreferences 미러)은 밀리초로 저장되기 때문.
DateTime? _dateFrom(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  return null;
}

Timestamp? _tsFrom(DateTime? d) => d == null ? null : Timestamp.fromDate(d);
