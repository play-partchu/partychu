// ─────────────────────────────────────────────────────────────────────────────
// 매장 이벤트·프로모션 — "결제가 없는 홍보"만 담는 별도 구조.
//
// "오늘 혼술 환영", "직장인 할인", "외국인 환영", "보드게임 가능"처럼 파는
// 물건이 아니라 **알리는 내용**이다. 상품([PlaceProduct])과 섞으면 손님이
// "이건 사는 건가 아닌가"를 헷갈리고, 재고·주문·QR 같은 개념이 전부 무의미한
// 데이터로 따라붙는다. 그래서 컬렉션부터 분리한다.
//
// Firestore 저장 형태
//   placePromotions/{promotionId}
//     placeId / placeCollection / hostId  ← placeProducts와 같은 소속 축
//     linkedProductIds: [productId, ...]  ← 결제가 필요한 내용이면 상품을 건다
//
// 상품과 달리 주문·재고가 없으므로 서버 함수도 필요 없다 — 사장님이
// firestore.rules 아래에서 직접 쓰고, 손님은 읽기만 한다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:party_app/models/host_offering.dart';
import 'package:party_app/models/event_apply.dart';
import 'package:party_app/models/event_inquiry_notice.dart';
import 'package:party_app/models/listing_inquiry.dart';
import 'package:party_app/models/place_promotion_media_draft.dart';

/// 프로모션 태그 프리셋 — 자주 쓰는 문구를 미리 준비해 오타·표기 흔들림을
/// 줄인다. 목록 필터로도 쓸 수 있게 값 자체를 그대로 저장한다.
const List<String> kPromotionTagPresets = [
  '오늘 혼술 환영',
  '직장인 할인',
  '외국인 환영',
  '보드게임 가능',
  '단체 환영',
  '생일 이벤트',
  '커플 할인',
  '학생 할인',
  '반려동물 동반',
  '주차 지원',
];

/// 이벤트의 갈래. 손님이 "이게 축제인지, 깎아주는 건지, 파는 건지"를 카드
/// 한 줄에서 구분하도록 이모지를 함께 둔다.
///
/// [package]는 **홍보만** 한다 — 실제 가격·재고·결제가 필요한 묶음은
/// placeProducts로 등록하고 [PlacePromotion.linkedProductIds]로 연결한다.
enum PromotionType {
  // 🎪 — 여기 셋은 전부 **매장 이벤트** 안의 갈래다([HostOffering.placeEvent]).
  // 예전에는 이 갈래도 🎉를 써서 카드에서 파티와 같은 것으로 읽혔다.
  event('event', kPlaceEventEmoji, '이벤트'),
  benefit('benefit', '🏷️', '할인·혜택'),
  package('package', '🎁', '패키지');

  const PromotionType(this.key, this.emoji, this.label);

  final String key;
  final String emoji;
  final String label;

  static PromotionType fromKey(String? key) {
    for (final t in PromotionType.values) {
      if (t.key == key) return t;
    }
    // 유형이 없던 시절의 문서는 전부 일반 이벤트로 본다.
    return PromotionType.event;
  }
}

/// 진행 요일 표기 — `DateTime.monday`(1) ~ `DateTime.sunday`(7)를 그대로 쓴다.
const List<String> kWeekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

/// 프로모션의 지금 노출 상태. 상품과 같은 방식으로 **계산**하고 저장하지
/// 않는다([PlacePromotion.statusAt]) — 저장하면 기간이 지나며 틀어진다.
enum PromotionStatus {
  scheduled('scheduled', '시작 전'),
  running('running', '진행 중'),
  ended('ended', '종료'),
  hidden('hidden', '숨김');

  const PromotionStatus(this.key, this.label);

  final String key;
  final String label;

  /// 손님 화면에 보여줄 상태인가 — 숨김/종료는 감춘다.
  bool get isPublic =>
      this == PromotionStatus.running || this == PromotionStatus.scheduled;

  static PromotionStatus fromKey(String? key) {
    for (final s in PromotionStatus.values) {
      if (s.key == key) return s;
    }
    return PromotionStatus.running;
  }
}

/// 매장 이벤트·프로모션 한 건.
class PlacePromotion {
  const PlacePromotion({
    required this.id,
    required this.placeId,
    required this.placeCollection,
    required this.hostId,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.tags,
    required this.audience,
    required this.startAt,
    required this.endAt,
    required this.isVisible,
    this.hiddenAt,
    required this.linkedProductIds,
    required this.sortOrder,
    this.type = PromotionType.event,
    this.imageUrls = const [],
    this.videoUrl,
    this.videoUid,
    this.videoThumbnailUrl,
    this.isAlways = false,
    this.weekdays = const [],
    this.startTime,
    this.endTime,
    this.benefit = '',
    this.priceText = '',
    this.conditions = '',
    this.reservationRequired = false,
    this.reservationGuide = '',
    this.sourcePartyId,
    this.sourcePartyTitle,
    this.inquiryEnabled = ListingInquiry.defaultEnabled,
    this.inquiryOffNotice = EventInquiryNotice.defaultNotice,
    this.inquiryOffNoticeText = '',
    this.applyMode = EventApplyMode.defaultMode,
    this.coverMediaType,
    this.coverImageUrl,
    this.coverVideoUrl,
    this.coverVideoUid,
    this.coverThumbnailUrl,
    this.basicCardPhotoCrops = const {},
    this.mediaDraft,
  });

  final String id;
  final String placeId;

  /// 'events'(술집·바·카페) 또는 'places'(공간대여·숙박).
  final String placeCollection;
  final String hostId;

  final String title;
  final String description;
  final String imageUrl;

  /// [kPromotionTagPresets] 값 또는 직접 입력한 문구.
  final List<String> tags;

  /// 대상 조건 — "20~30대", "2인 이상 방문 시" 같은 자유 입력.
  final String audience;

  final DateTime? startAt;
  final DateTime? endAt;

  /// 사장님이 켜고 끄는 노출 스위치. 기간과 무관하게 최우선이다.
  final bool isVisible;

  /// 감춘 시각 — **자동 삭제(14일)의 기준점**이다([goneAt]).
  ///
  /// 서버만 쓰는 값이 아니라 화면도 읽는다('자동삭제 D-8'). 값을 적는 곳은
  /// [PlacePromotionService](종료/다시 노출)이고, **[toMap]에는 담지 않는다** —
  /// 담으면 내용만 고친 저장이 기준점을 매번 새로 써 기한이 무한히 밀린다.
  /// 이 필드가 없던 시절 감춰 둔 이벤트는 null이라 자동 삭제 대상이 아니다.
  final DateTime? hiddenAt;

  /// 실제 결제가 필요한 내용이면 관련 상품을 걸어둔다 — 손님이 프로모션에서
  /// 곧바로 그 상품 구매로 넘어갈 수 있다.
  final List<String> linkedProductIds;

  final int sortOrder;

  // ── 아래는 "기존 장소에 이벤트만 추가" 기능에서 더해진 항목들 ───────────
  // 전부 기본값이 있는 선택 필드다 — 이 필드들이 없던 시절의 문서도 그대로
  // 읽히고, 예전 등록 폼(URL 한 줄 입력)으로 만든 이벤트도 계속 동작한다.

  final PromotionType type;

  /// 업로드한 사진들. 예전 폼이 쓰던 [imageUrl](URL 직접 입력) 한 장과
  /// 공존하며, 화면에서는 [allImageUrls]로 합쳐 쓴다.
  final List<String> imageUrls;

  final String? videoUrl;
  final String? videoUid;
  final String? videoThumbnailUrl;

  /// 상시 진행 — 켜면 시작일/종료일과 무관하게 계속 '진행 중'이다.
  final bool isAlways;

  /// 진행 요일. `DateTime.monday`(1) ~ `DateTime.sunday`(7). 비어 있으면 매일.
  final List<int> weekdays;

  /// 'HH:mm' 문자열. 둘 다 없으면 시간 제한 없음.
  final String? startTime;
  final String? endTime;

  /// 혜택 내용 — "샴페인 무제한 29,000원"처럼 무엇을 주는지.
  final String benefit;

  /// 가격·할인 표기 — "1+1", "20% 할인"처럼 자유 입력.
  final String priceText;

  /// 이용 조건 — "2인 이상", "예약 필수" 같은 단서.
  final String conditions;

  /// 이 이벤트를 이용하려면 **미리 예약이 필요한가.**
  ///
  /// ⚠️ 예약 기능을 만드는 값이 아니다 — 게스트에게 "예약이 필요하다"고
  /// 알리는 표시다. 실제 예약은 장소 쪽 기능(플레이스의 방문 예약 · 장소대여의
  /// 룸 예약)이거나, 호스트에게 문의해서 잡는다. 그래서 이 값이 켜지면 문의
  /// 버튼이 반드시 보여야 한다([showsInquiryButton]).
  final bool reservationRequired;

  /// 예약을 어떻게 잡으면 되는지 — 호스트가 직접 적는 한두 줄.
  ///
  /// 예) '방문 전 문의하기를 눌러 희망 날짜와 인원을 알려주세요.'
  /// 비어 있으면 상세는 안내 제목만 보여준다(빈 상자를 그리지 않는다).
  /// 길이 상한은 호스트가 적는 다른 안내문과 같다
  /// ([ListingInquiry.maxGuideLength]).
  final String reservationGuide;

  // ── 원본 파티 추적 ─────────────────────────────────────────────────────
  // "이 파티를 기반으로 이벤트 등록"으로 만들어진 이벤트만 채워진다.
  //
  // **종속이 아니라 출처다.** 파티가 지워져도 이 이벤트는 남고, 파티를 고쳐도
  // 내용이 따라 바뀌지 않는다 — 호스트 화면에서 "어느 파티에서 나온 이벤트인지"
  // 알아보는 표시일 뿐이다. 그래서 제목까지 함께 적어 둔다(파티가 사라진 뒤에도
  // 이름은 남아야 한다).

  final String? sourcePartyId;
  final String? sourcePartyTitle;

  // ── 채팅 문의 받기 ─────────────────────────────────────────────────────
  //
  // ON/OFF는 파티·플레이스·장소대여와 **같은 필드**(inquiryEnabled) 하나다 —
  // 판정도 기본값도 [ListingInquiry]를 그대로 지난다. 필드가 없는 옛 이벤트는
  // 켜진 것으로 읽힌다.
  //
  // 끈 경우에 보여줄 안내만 이벤트 전용이다([EventInquiryNotice]). 다른
  // 도메인의 inquiryGuide와는 뜻이 반대라 같은 필드에 담을 수 없다.

  final bool inquiryEnabled;
  final EventInquiryNotice inquiryOffNotice;
  final String inquiryOffNoticeText;

  // ── 신청 받기 ──────────────────────────────────────────────────────────
  //
  // 매장 이벤트도 **직접 신청을 받을 수 있다**([EventApplyMode]). 신청 여부는
  // 파티와 매장 이벤트를 가르는 기준이 아니다 — 생일 이벤트처럼 매장이 여는
  // 행사인데 사전 신청을 받는 것이 얼마든지 있다.
  //
  // 필드가 없는 옛 이벤트는 [EventApplyMode.none]으로 읽혀 예전 그대로 동작한다.

  final EventApplyMode applyMode;

  /// 게스트 상세에서 문의 버튼을 보여줄지.
  ///
  /// 신청 방식이 '신청하기'만이면 문의 버튼은 접는다 — 호스트가 고른 모습이
  /// 그것이다. 반대로 이 값이 문의를 **켜지는 못한다**: 문의의 정본은 끝까지
  /// [ListingInquiry]다.
  ///
  /// 단 [reservationRequired]가 켜져 있으면 접지 않는다. 그 이벤트는 예약
  /// 기능을 갖고 있지 않아서 **문의가 예약을 잡는 유일한 길**인데, 신청 방식
  /// 하나 때문에 그 길이 사라지면 손님은 예약이 필요하다는 안내만 읽고 아무
  /// 데도 갈 수 없다. 여기서도 문의를 새로 켜지는 않는다 — 등록 화면이
  /// 사전 예약을 켤 때 [ListingInquiry] 스위치를 함께 켜고 잠근다.
  bool get showsInquiryButton =>
      inquiryEnabled && (reservationRequired || applyMode.allowsInquiry);

  /// 지금 이 이벤트에 신청 버튼을 그려야 하는가.
  ///
  /// 종료·숨김 이벤트에는 그리지 않는다 — 받을 수 없는 신청을 받는 자리를
  /// 남겨 두면 게스트는 보냈다고 생각하고 호스트는 받은 적이 없다. 판정은
  /// 목록·상세가 공유하는 [statusAt] 하나를 그대로 쓴다.
  bool showsApplyButtonAt(DateTime now) =>
      applyMode.receivesApplications && statusAt(now).isPublic;

  // ── 대표 미디어 ────────────────────────────────────────────────────────
  //
  // 필드 이름은 **파티·플레이스와 같다.** 읽는 쪽이 앱 전체에서 하나
  // ([getPartyCoverMedia])라 이름이 갈리면 이벤트만 대표를 못 찾는다.
  // 값을 만드는 쪽도 공용 헬퍼([MediaUploadService.resolveCoverFields]) 하나다.
  //
  // 전부 선택 필드다 — 이 값들이 없던 시절의 이벤트는 null이라, 화면이
  // 예전처럼 `allImageUrls`의 첫 장(또는 동영상)을 대표로 본다.

  final String? coverMediaType;
  final String? coverImageUrl;
  final String? coverVideoUrl;
  final String? coverVideoUid;
  final String? coverThumbnailUrl;

  /// 사진 URL → 기본 카드 크롭({x, y, scale}). 파티와 같은 구조다.
  final Map<String, Map<String, double>> basicCardPhotoCrops;

  /// 아직 **올리지 않은** 미디어 — 장소를 처음 등록하는 중에 고른 파일들.
  ///
  /// 문서가 아직 없어 곧바로 올릴 수 없으므로 여기 담아 두고, 장소가 만들어진
  /// 직후 [PlacePromotionSection.save]가 공용 업로더로 올려 [imageUrls]·
  /// [videoUrl]·cover 필드로 바꾼다(메뉴 사진의 `localImagePath`와 같은 방식).
  ///
  /// ⚠️ **Firestore에 쓰지 않는다** — [toMap]이 이 값을 담지 않고 [fromMap]도
  ///    읽지 않는다. 저장 구조는 이 필드가 생기기 전과 완전히 같다.
  final PlacePromotionMediaDraft? mediaDraft;

  /// 대표가 동영상으로 지정돼 있는가.
  ///
  /// 지정이 아예 없는 옛 이벤트는 "사진이 하나도 없고 동영상만 있으면
  /// 동영상"이라는 기존 규칙을 따른다 — 상세 갤러리가 예전과 똑같이 보인다.
  bool get coverIsVideo => coverMediaType == 'video'
      ? (coverVideoUrl ?? videoUrl ?? '').isNotEmpty
      : (coverMediaType == null && allImageUrls.isEmpty && hasVideo);

  /// [getPartyCoverMedia]가 읽는 모양으로 맞춘 지도.
  ///
  /// 상세·카드가 파티와 **같은 함수**로 대표를 읽게 하려고 둔다. 이벤트만
  /// 따로 해석하는 코드를 만들면 크롭·포컬 규칙이 조용히 갈라진다.
  Map<String, dynamic> get coverMediaMap => {
    'coverMediaType': coverMediaType,
    'coverImageUrl': coverImageUrl,
    'coverVideoUrl': coverVideoUrl,
    'coverVideoUid': coverVideoUid,
    'coverThumbnailUrl': coverThumbnailUrl,
    'basicCardPhotoCrops': basicCardPhotoCrops,
    'images': allImageUrls,
    'videoUrl': videoUrl,
    'videoUid': videoUid,
    'videoThumbnailUrl': videoThumbnailUrl,
  };

  /// 문의를 끈 자리에 대신 보여줄 한 줄. 보여줄 것이 없으면 빈 문자열이다.
  String get inquiryOffText => inquiryEnabled
      ? ''
      : (inquiryOffNotice == EventInquiryNotice.custom
            ? inquiryOffNoticeText
            : inquiryOffNotice.label);

  /// 자동 분류·검색이 보는 **텍스트 정본** — 호스트가 직접 적는 칸 전부다.
  ///
  /// 소분류 판정([ListingConstants.autoEventSubtypeFor])이 이 목록을 본다.
  /// 제목 하나만 검사하면 "9월 한 달 생일자 무료" 같은 내용이 혜택 칸에만
  /// 적혔을 때 놓치기 때문이다.
  List<String> get searchTexts => [
    title,
    description,
    benefit,
    priceText,
    conditions,
    audience,
    ...tags,
  ];

  /// 화면에 쓸 사진 목록 — 업로드한 사진이 있으면 그걸 쓰고, 없으면 예전
  /// 폼의 URL 한 장으로 되돌아간다.
  List<String> get allImageUrls => imageUrls.isNotEmpty
      ? imageUrls
      : (imageUrl.isEmpty ? const [] : [imageUrl]);

  bool get hasVideo => (videoUrl ?? '').isNotEmpty;

  /// "매주 금·토" / "매일" — 요일을 안 정했으면 null(굳이 '매일'을 적지 않는다).
  String? get weekdayLabel {
    if (weekdays.isEmpty || weekdays.length >= 7) return null;
    final sorted = [...weekdays]..sort();
    return '매주 ${sorted.map((d) => kWeekdayLabels[(d - 1).clamp(0, 6)]).join('·')}';
  }

  /// "20:00 ~ 24:00" — 시간을 안 정했으면 null.
  String? get timeLabel {
    if ((startTime ?? '').isEmpty && (endTime ?? '').isEmpty) return null;
    if ((startTime ?? '').isNotEmpty && (endTime ?? '').isNotEmpty) {
      return '$startTime ~ $endTime';
    }
    return (startTime ?? '').isNotEmpty ? '$startTime~' : '~$endTime';
  }

  /// [now] 시점의 노출 상태. 우선순위 — 숨김 > 종료 > 시작 전 > 진행 중.
  ///
  /// 상시 진행([isAlways])이면 날짜로는 끝나지 않는다 — 사장님이 [isVisible]을
  /// 끄기 전까지 계속 '진행 중'이다.
  PromotionStatus statusAt(DateTime now) {
    if (!isVisible) return PromotionStatus.hidden;
    if (isAlways) return PromotionStatus.running;
    if (endAt != null && now.isAfter(_dayEnd(endAt!))) {
      return PromotionStatus.ended;
    }
    if (startAt != null && now.isBefore(_dayStart(startAt!))) {
      return PromotionStatus.scheduled;
    }
    return PromotionStatus.running;
  }

  static DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _dayEnd(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59);

  /// **손님에게 보이지 않게 된 시각** — 자동 삭제(14일)를 세는 기준점이다.
  ///
  /// 그렇게 되는 길은 둘이고, 둘 다 겪었다면 **먼저 일어난 쪽**이 기준이다.
  ///   · 기간 종료 — [endAt]이 가리키는 날의 끝(23:59:59)
  ///   · 호스트가 '종료'를 누름 — [hiddenAt]
  ///
  /// 아직 보이는 이벤트, 상시 진행(노출 중), 그리고 기준점을 모르는 옛 숨김
  /// 이벤트(hiddenAt이 없다)는 null이다 — **null이면 지우지 않는다.** 화면도
  /// 그럴 때는 아무 말도 하지 않는다([AutoDeleteRetention.label]이 null).
  ///
  /// ⚠️ functions/index.js의 deleteExpiredPromotions와 **같은 규칙**이어야
  ///    한다. 앱이 'D-3'이라고 써 놓고 서버가 이미 지웠으면 안 된다.
  DateTime? goneAt([DateTime? now]) {
    final at = now ?? DateTime.now();
    final stamps = <DateTime>[];
    if (endAt != null && !isAlways && at.isAfter(_dayEnd(endAt!))) {
      stamps.add(_dayEnd(endAt!));
    }
    if (!isVisible && hiddenAt != null) stamps.add(hiddenAt!);
    if (stamps.isEmpty) return null;
    stamps.sort();
    return stamps.first;
  }

  /// "8.1 ~ 8.31" 같은 기간 한 줄. 기간을 안 정했으면 null(상시).
  ///
  /// 상시 진행이면 날짜가 남아 있어도 무시한다 — "8.1~8.31 상시 진행"처럼
  /// 서로 어긋나 보이는 표기를 막는다.
  String? get periodLabel {
    String d(DateTime t) => '${t.month}.${t.day}';
    if (isAlways) return null;
    if (startAt == null && endAt == null) return null;
    if (startAt != null && endAt != null) {
      return '${d(startAt!)} ~ ${d(endAt!)}';
    }
    if (endAt != null) return '${d(endAt!)}까지';
    return '${d(startAt!)}부터';
  }

  factory PlacePromotion.fromMap(
    String id,
    Map<String, dynamic> d,
  ) => PlacePromotion(
    id: id,
    placeId: d['placeId'] as String? ?? '',
    placeCollection: d['placeCollection'] as String? ?? 'events',
    hostId: d['hostId'] as String? ?? '',
    title: d['title'] as String? ?? '',
    description: d['description'] as String? ?? '',
    imageUrl: d['imageUrl'] as String? ?? '',
    tags: (d['tags'] as List?)?.cast<String>().toList() ?? const [],
    audience: d['audience'] as String? ?? '',
    startAt: _dateFrom(d['startAt']),
    endAt: _dateFrom(d['endAt']),
    isVisible: d['isVisible'] as bool? ?? true,
    hiddenAt: _dateFrom(d['hiddenAt']),
    linkedProductIds:
        (d['linkedProductIds'] as List?)?.cast<String>().toList() ?? const [],
    sortOrder: (d['sortOrder'] as num?)?.toInt() ?? 0,
    type: PromotionType.fromKey(d['type'] as String?),
    imageUrls: (d['imageUrls'] as List?)?.cast<String>().toList() ?? const [],
    videoUrl: d['videoUrl'] as String?,
    videoUid: d['videoUid'] as String?,
    videoThumbnailUrl: d['videoThumbnailUrl'] as String?,
    isAlways: d['isAlways'] as bool? ?? false,
    weekdays: ((d['weekdays'] as List?) ?? const [])
        .map((e) => (e as num).toInt())
        .toList(),
    startTime: d['startTime'] as String?,
    endTime: d['endTime'] as String?,
    benefit: d['benefit'] as String? ?? '',
    priceText: d['priceText'] as String? ?? '',
    conditions: d['conditions'] as String? ?? '',
    reservationRequired: d['reservationRequired'] as bool? ?? false,
    // 필드가 없던 옛 이벤트는 빈 문구다 — 안내 제목만 보인다.
    reservationGuide: _clampGuide(d['reservationGuide']),
    sourcePartyId: d['sourcePartyId'] as String?,
    sourcePartyTitle: d['sourcePartyTitle'] as String?,
    // 필드가 없는 옛 이벤트는 "문의 켜짐"으로 읽힌다 — 호스트가 끈 적이 없는데
    // 꺼진 것으로 취급하면 조용히 문의를 못 받게 된다(ListingInquiry와 같은 규칙).
    inquiryEnabled: ListingInquiry.isEnabled(d),
    inquiryOffNotice: EventInquiryNoticeFields.noticeOf(d),
    inquiryOffNoticeText: EventInquiryNoticeFields.customTextOf(d),
    applyMode: EventApplyMode.fromKey(d[EventApplyMode.field] as String?),
    coverMediaType: d['coverMediaType'] as String?,
    coverImageUrl: d['coverImageUrl'] as String?,
    coverVideoUrl: d['coverVideoUrl'] as String?,
    coverVideoUid: d['coverVideoUid'] as String?,
    coverThumbnailUrl: d['coverThumbnailUrl'] as String?,
    basicCardPhotoCrops: _cropsFrom(d['basicCardPhotoCrops']),
  );

  Map<String, dynamic> toMap({DateTime? now}) => {
    'placeId': placeId,
    'placeCollection': placeCollection,
    'hostId': hostId,
    'title': title,
    'description': description,
    'imageUrl': imageUrl,
    'tags': tags,
    'audience': audience,
    'startAt': startAt == null ? null : Timestamp.fromDate(startAt!),
    'endAt': endAt == null ? null : Timestamp.fromDate(endAt!),
    'isVisible': isVisible,
    'linkedProductIds': linkedProductIds,
    'sortOrder': sortOrder,
    'type': type.key,
    'imageUrls': imageUrls,
    'videoUrl': videoUrl,
    'videoUid': videoUid,
    'videoThumbnailUrl': videoThumbnailUrl,
    'isAlways': isAlways,
    'weekdays': weekdays,
    'startTime': startTime,
    'endTime': endTime,
    'benefit': benefit,
    'priceText': priceText,
    'conditions': conditions,
    'reservationRequired': reservationRequired,
    // 사전 예약을 끄면 안내 문구도 함께 지운다 — 꺼 둔 채 남겨 두면 나중에
    // 다시 켰을 때 예전 문구가 아무 예고 없이 되살아난다(inquiryGuide와 같은
    // 규칙).
    'reservationGuide': reservationRequired ? reservationGuide : '',
    'sourcePartyId': sourcePartyId,
    'sourcePartyTitle': sourcePartyTitle,
    // 문의 받기 — 켜면 OFF 안내 두 필드는 null로 지워진다.
    ListingInquiry.field: inquiryEnabled,
    // 신청 받기 — 필드가 없는 옛 이벤트는 읽는 쪽이 none으로 본다.
    EventApplyMode.field: applyMode.key,
    ...EventInquiryNoticeFields.toMap(
      inquiryEnabled: inquiryEnabled,
      notice: inquiryOffNotice,
      customText: inquiryOffNoticeText,
    ),
    // 대표 미디어 — 파티·플레이스와 같은 필드명.
    'coverMediaType': coverMediaType,
    'coverImageUrl': coverImageUrl,
    'coverVideoUrl': coverVideoUrl,
    'coverVideoUid': coverVideoUid,
    'coverThumbnailUrl': coverThumbnailUrl,
    'basicCardPhotoCrops': basicCardPhotoCrops,
    // 목록 쿼리용 파생 미러 — 정본은 항상 [statusAt]이다(상품과 같은 취급).
    'statusMirror': statusAt(now ?? DateTime.now()).key,
  };

  /// 임시저장(JSON) — Timestamp 대신 밀리초를 쓴다.
  Map<String, dynamic> toDraftMap() => {
    ...toMap(),
    'id': id,
    'startAt': startAt?.millisecondsSinceEpoch,
    'endAt': endAt?.millisecondsSinceEpoch,
  };

  static List<Map<String, dynamic>> listToDraft(List<PlacePromotion> items) =>
      items.map((p) => p.toDraftMap()).toList();

  static List<PlacePromotion> listFromDraft(Object? raw) {
    if (raw is! List) return const [];
    final out = <PlacePromotion>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final map = Map<String, dynamic>.from(e);
      out.add(PlacePromotion.fromMap(map['id'] as String? ?? '', map));
    }
    return out;
  }

  PlacePromotion copyWith({
    String? id,
    String? title,
    String? description,
    String? imageUrl,
    List<String>? tags,
    String? audience,
    DateTime? startAt,
    DateTime? endAt,
    bool? isVisible,
    List<String>? linkedProductIds,
    int? sortOrder,
    PromotionType? type,
    List<String>? imageUrls,
    String? videoUrl,
    String? videoUid,
    String? videoThumbnailUrl,
    bool? isAlways,
    List<int>? weekdays,
    String? startTime,
    String? endTime,
    String? benefit,
    String? priceText,
    String? conditions,
    bool? reservationRequired,
    String? reservationGuide,
    String? sourcePartyId,
    String? sourcePartyTitle,
    bool? inquiryEnabled,
    EventInquiryNotice? inquiryOffNotice,
    String? inquiryOffNoticeText,
    EventApplyMode? applyMode,
    String? coverMediaType,
    String? coverImageUrl,
    String? coverVideoUrl,
    String? coverVideoUid,
    String? coverThumbnailUrl,
    Map<String, Map<String, double>>? basicCardPhotoCrops,
    PlacePromotionMediaDraft? mediaDraft,
    // null로 되돌리는 건 `??`로 표현할 수 없어 별도 스위치를 둔다 —
    // 편집 화면에서 영상·시간을 지울 때 쓴다.
    bool clearVideo = false,
    bool clearTime = false,
    bool clearMediaDraft = false,
  }) => PlacePromotion(
    id: id ?? this.id,
    placeId: placeId,
    placeCollection: placeCollection,
    hostId: hostId,
    title: title ?? this.title,
    description: description ?? this.description,
    imageUrl: imageUrl ?? this.imageUrl,
    tags: tags ?? this.tags,
    audience: audience ?? this.audience,
    startAt: startAt ?? this.startAt,
    endAt: endAt ?? this.endAt,
    isVisible: isVisible ?? this.isVisible,
    // hiddenAt은 화면이 고르는 값이 아니라 저장 시점에 서비스가 적는 값이라
    // copyWith 인자로 받지 않는다 — 읽어 온 값만 그대로 물려준다.
    hiddenAt: hiddenAt,
    linkedProductIds: linkedProductIds ?? this.linkedProductIds,
    sortOrder: sortOrder ?? this.sortOrder,
    type: type ?? this.type,
    imageUrls: imageUrls ?? this.imageUrls,
    videoUrl: clearVideo ? null : (videoUrl ?? this.videoUrl),
    videoUid: clearVideo ? null : (videoUid ?? this.videoUid),
    videoThumbnailUrl: clearVideo
        ? null
        : (videoThumbnailUrl ?? this.videoThumbnailUrl),
    isAlways: isAlways ?? this.isAlways,
    weekdays: weekdays ?? this.weekdays,
    startTime: clearTime ? null : (startTime ?? this.startTime),
    endTime: clearTime ? null : (endTime ?? this.endTime),
    benefit: benefit ?? this.benefit,
    priceText: priceText ?? this.priceText,
    conditions: conditions ?? this.conditions,
    reservationRequired: reservationRequired ?? this.reservationRequired,
    reservationGuide: reservationGuide ?? this.reservationGuide,
    sourcePartyId: sourcePartyId ?? this.sourcePartyId,
    sourcePartyTitle: sourcePartyTitle ?? this.sourcePartyTitle,
    inquiryEnabled: inquiryEnabled ?? this.inquiryEnabled,
    inquiryOffNotice: inquiryOffNotice ?? this.inquiryOffNotice,
    inquiryOffNoticeText: inquiryOffNoticeText ?? this.inquiryOffNoticeText,
    applyMode: applyMode ?? this.applyMode,
    // 대표가 동영상 → 사진으로 바뀌면 coverVideo*는 비워야 한다. clearVideo가
    // 영상 자체를 지우는 자리이므로 대표 값도 같은 스위치를 따른다.
    coverMediaType: coverMediaType ?? this.coverMediaType,
    coverImageUrl: coverImageUrl ?? this.coverImageUrl,
    coverVideoUrl: clearVideo ? null : (coverVideoUrl ?? this.coverVideoUrl),
    coverVideoUid: clearVideo ? null : (coverVideoUid ?? this.coverVideoUid),
    coverThumbnailUrl: coverThumbnailUrl ?? this.coverThumbnailUrl,
    basicCardPhotoCrops: basicCardPhotoCrops ?? this.basicCardPhotoCrops,
    // 올리고 나면 비워야 하는 값이라 `??`로는 지울 수 없다 — 메뉴 사진의
    // clearLocalImage와 같은 이유로 전용 스위치를 둔다.
    mediaDraft: clearMediaDraft ? null : (mediaDraft ?? this.mediaDraft),
  );

  factory PlacePromotion.empty({
    required String placeId,
    required String placeCollection,
    required String hostId,
    required int sortOrder,
  }) => PlacePromotion(
    id: '',
    placeId: placeId,
    placeCollection: placeCollection,
    hostId: hostId,
    title: '',
    description: '',
    imageUrl: '',
    tags: const [],
    audience: '',
    startAt: null,
    endAt: null,
    isVisible: true,
    linkedProductIds: const [],
    sortOrder: sortOrder,
  );
}

/// 호스트가 적는 안내문을 읽는 규칙 — 앞뒤 공백을 털고 상한에서 자른다.
/// 다른 경로로 들어온 긴 값이 있어도 화면이 무너지지 않는다
/// ([ListingInquiry.guideOf]와 같은 처리).
String _clampGuide(dynamic raw) {
  if (raw is! String) return '';
  final trimmed = raw.trim();
  return trimmed.length <= ListingInquiry.maxGuideLength
      ? trimmed
      : trimmed.substring(0, ListingInquiry.maxGuideLength);
}

/// Firestore의 중첩 지도 → 크롭 표. 모양이 어긋난 값은 조용히 버린다 —
/// 크롭 하나 때문에 이벤트 전체가 안 읽히면 안 된다.
Map<String, Map<String, double>> _cropsFrom(dynamic v) {
  if (v is! Map) return const {};
  final out = <String, Map<String, double>>{};
  v.forEach((key, value) {
    if (key is! String || value is! Map) return;
    final x = (value['x'] as num?)?.toDouble();
    final y = (value['y'] as num?)?.toDouble();
    final scale = (value['scale'] as num?)?.toDouble();
    if (x == null && y == null && scale == null) return;
    out[key] = {'x': x ?? 0.5, 'y': y ?? 0.5, 'scale': scale ?? 1.0};
  });
  return out;
}

DateTime? _dateFrom(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  return null;
}
