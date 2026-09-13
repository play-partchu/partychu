/// 장소대여·파티샵·파트너 탭의 프리셋 옵션 중앙 관리.
/// 등록 화면과 상세검색 화면이 동일한 값을 참조해 필터가 실제로 매칭되도록 한다.
library;

import 'package:party_app/models/host_offering.dart';

class ListingConstants {
  ListingConstants._();

  // ── 공통 지역(시/도) ────────────────────────────────────────────────
  static const List<String> regions = [
    '서울',
    '경기',
    '인천',
    '강원',
    '충북',
    '충남',
    '대전',
    '세종',
    '전북',
    '전남',
    '광주',
    '경북',
    '경남',
    '대구',
    '울산',
    '부산',
    '제주',
  ];

  // ── 장소대여 ─────────────────────────────────────────────────────────
  static const List<String> placeTypes = [
    '파티룸',
    '펜션',
    '게스트하우스',
    '호텔',
    '캠핑장',
    '스튜디오',
    '루프탑',
    '바',
    '카페',
    '공연장',
    '기타',
  ];

  static const List<String> placeFacilities = [
    '주차',
    '와이파이',
    '취사 가능',
    '바베큐',
    '수영장',
    '노래방',
    '음향시설',
    '빔프로젝터',
    '냉난방',
    '반려동물 가능',
  ];

  static const List<String> placePriceRanges = [
    '3만원 이하',
    '3~5만원',
    '5~10만원',
    '10~20만원',
    '20만원 이상',
  ];

  static const List<String> placeCapacityRanges = [
    '10명 이하',
    '10~20명',
    '20~50명',
    '50~100명',
    '100명 이상',
  ];

  // ── 파티샵 ───────────────────────────────────────────────────────────
  //
  // 파티샵 **상품 카테고리의 정본**. 상품 등록(`party_market_register_screen`의
  // 상품 추가 시트 · `party_shop_product_register_screen`)의 칩, 상세검색 시트
  // ([ShopDetailSearchSheet])의 칩, 등록 유형 안내의 예시 줄까지 전부 이 목록
  // 하나를 읽는다 — 화면마다 손으로 적은 사본은 없다.
  //
  // ⚠️ 이 배열의 **문자열이 곧 저장값**이다.
  //  · 상품 문서의 `category`와 샵 문서의 집계 배열 `categories`에 이 글자가
  //    그대로 들어가고, 목록 필터도 문자열 대조로 고른다
  //    (`_shopFilter.categories.any((c) => categories.contains(c))`).
  //  · 그래서 **이미 있는 값의 글자를 고치거나 빼면** 그 값으로 등록된 상품이
  //    검색·필터에서 그대로 사라진다. 늘리는 것만 안전하다.
  //  · 순서는 화면에 칩이 서는 순서일 뿐 저장에 관여하지 않는다. 다만 첫 칸은
  //    **새 상품의 기본 카테고리**라(`shopCategories.first`) 바꾸지 않는다.
  //
  // 🍰 '케이크/디저트' — 2026-08-31 추가. 주문제작 케이크·레터링 케이크·도시락
  //    케이크·컵케이크·쿠키·디저트류가 갈 곳이 없어 '케이터링/음료'(출장 뷔페·
  //    음료 쪽으로 읽힌다)나 '기타'로 흩어져 있었다. 먹는 것이라는 점만 같고
  //    사는 방식이 전혀 다르다 — 그래서 케이터링 **바로 앞**에 둔다.
  //    (기존 상품의 저장값은 하나도 건드리지 않는다. '케이터링/음료'로 등록된
  //    케이크는 그 값 그대로 남고, 호스트가 수정 화면에서 옮길 수 있다.)
  //    🛠 주문제작([kMadeToOrderField])과는 **완전히 다른 축**이다. 카테고리는
  //    무엇을 파는가, 주문제작은 재고를 세는가 — 둘은 함께 켤 수 있다.
  static const List<String> shopCategories = [
    '의상/코스튬',
    '파티소품',
    '풍선/데코',
    '케이크/디저트',
    '케이터링/음료',
    '조명/음향',
    '기프트/답례품',
    '폭죽/불꽃',
    '기타',
  ];

  static const List<String> shopPriceRanges = [
    '1만원 이하',
    '1~3만원',
    '3~5만원',
    '5~10만원',
    '10만원 이상',
  ];

  // ── 파티크루(파트너) ──────────────────────────────────────────────────
  static const List<String> crewRoles = [
    'DJ',
    'MC',
    '가수',
    '댄서',
    '비보이',
    '사진작가',
    '영상촬영',
    '바텐더',
    '진행요원',
    '안전요원',
    '모델',
    '기타',
  ];

  static const List<String> crewPayTypes = ['유료', '협의', '무료'];

  static const List<String> crewRecruitCounts = ['1명', '2~3명', '4~5명', '6명 이상'];

  // ── 플레이스(구 이벤트) ───────────────────────────────────────────────
  // 업종이 아니라 플레이스의 특징(테마) — 등록 시 다중 선택 가능하고,
  // 목록 상단 빠른 필터에서도 여러 개를 동시에 켤 수 있다.
  // ── 더 이상 고를 수 없는 태그 ────────────────────────────────────
  // 여기 실린 태그는 **저장된 값을 건드리지 않는다** — 이미 이 태그를 단
  // 플레이스가 있고, 데이터를 지우면 되돌릴 수 없다. 그래서 선택지 목록
  // ([placeThemeTags])에서만 빼고 표기표([placeThemeTagEmojis])에는 남겨 둔다:
  //   · 새로 고를 수는 없다(등록·콤보등록·상세검색 선택지가 이 목록이다)
  //   · 이미 달린 문서는 상세페이지·카드에 그대로 보이고 검색어로도 찾힌다
  //   · 그 문서를 수정·저장해도 태그가 사라지지 않는다(등록 화면은 문서의
  //     태그를 통째로 읽어 들고 화면에 없는 것은 건드리지 않은 채 그대로
  //     다시 쓴다 — 칩이 켜고 끄는 것은 이 목록에 있는 태그뿐이다)
  //
  // · '알바생 훈남훈녀' — 2026-08-25, 선택지에서만 제외.
  // · '혼술바'         — 2026-08-25, **독립 대분류로 승격**됐다
  //   ([PlaceTaxonomy.soloBar]). 같은 말을 대분류와 태그 두 군데서 고르게
  //   두면 어느 쪽이 정본인지 알 수 없어지고, 한쪽만 고른 가게가 다른 쪽
  //   화면에서 빠진다. 그래서 **정본은 대분류 하나**로 두고 태그는 읽기
  //   전용으로 남긴다 — 옛 문서의 `themeTags: ['혼술바']`는
  //   [PlaceTaxonomy.matchesAnyCategory]가 새 혼술바 대분류로 함께 걸어
  //   주므로(legacy 다리) 그 가게들이 검색에서 사라지지 않는다.
  static const List<String> retiredPlaceThemeTags = ['알바생 훈남훈녀', '혼술바'];

  static const List<String> placeThemeTags = ['핫플', '이벤트'];

  // 업종 — 플레이스 상세검색에서 고르는 매장 종류. 특징 태그
  // ([placeThemeTags])와는 층이 다르다: 업종은 "무슨 가게인가", 태그는 "어떤
  // 분위기인가"다.
  static const List<String> eventBusinessTypes = [
    '술집',
    '바',
    '카페',
    '라운지',
    '포차',
    '클럽',
    '기타',
  ];

  // 플레이스 가격대 — 1인 기준 예상 지출. 장소대여([placePriceRanges])는
  // 시간당 대관료라 구간이 훨씬 크므로 따로 둔다.
  static const List<String> eventPriceRanges = [
    '무료',
    '1만원 이하',
    '1~3만원',
    '3~5만원',
    '5만원 이상',
  ];

  static const Map<String, String> placeThemeTagEmojis = {
    // 저장값 '핫플'은 그대로다 — 보이는 이름만 '📸 사진맛집'으로 바꾼다
    // (특징 쪽 표기도 같다: [PlaceFeatures.hot]).
    '핫플': '📸',
    // 🎪 = **매장 이벤트**(placePromotions). 파티(🎉)와 절대 겹치지 않는다 —
    // 예전에는 이 태그도 🎉라, 카드 배지만 보면 "여기서 파티를 하나?"로
    // 읽혔다([HostOffering]).
    '이벤트': kPlaceEventEmoji,
    // 아래 둘은 선택지에서 빠졌지만([retiredPlaceThemeTags]) 이미 달린 문서를
    // 그리려면 표기가 남아 있어야 한다 — 지우면 그 태그가 상세페이지에서
    // 이모지 없이 맨 글자로 뜬다. '혼술바'의 🍷는 대분류
    // [PlaceTaxonomy.soloBar]와 같은 이모지라, 옛 태그와 새 대분류가 화면에서
    // 같은 것으로 읽힌다.
    '혼술바': '🍷',
    '알바생 훈남훈녀': '😎',
  };

  /// 이벤트 특징 태그의 **저장값**. Firestore `themeTags` 배열에 이 문자열
  /// 그대로 들어가고, 필터도 이 값으로 매칭한다 — 화면 문구가 바뀌어도 이
  /// 값은 절대 바꾸지 않는다(바꾸면 이미 등록된 문서가 필터에서 사라진다).
  static const String placeEventTag = '이벤트';

  /// 특징 태그의 **화면 표기**. 저장값과 보이는 문구를 갈라 두는 자리다 —
  /// '이벤트'만으로는 "이벤트를 하는 가게"인지 "이벤트가 지금 열리는 중"인지
  /// 읽히지 않아 표기만 '이벤트 진행중'으로 바꿨다. 등록·수정·필터·카드·
  /// 상세가 전부 [placeThemeTagLabel]을 거치므로 표기가 갈라질 수 없다.
  ///
  /// ⚠️ 여기서는 '매장 이벤트'까지 적지 않는다 — 이 표기가 붙는 자리가
  /// **카드의 작은 배지**라, 이모지까지 붙으면 '🎪 매장 이벤트 진행중'이 되어
  /// 옆의 업종·분위기 배지를 밀어낸다. 이모지 🎪가 이미 파티(🎉)와 갈라 주고,
  /// 자리가 있는 곳(탐색 칸·상세 영역 머리)은 [HostOffering.placeEvent]의
  /// 정식 표기('🎪 매장 이벤트')를 쓴다.
  static const Map<String, String> placeThemeTagLabels = {
    placeEventTag: '이벤트 진행중',
    // '핫플'로 저장된 값을 '사진맛집'으로 부른다 — 등록·수정 화면의 칩,
    // 카드·상세의 태그, 필터 칩이 전부 이 표를 거치므로 한 곳만 고치면 된다.
    '핫플': '사진맛집',
  };

  /// 문서의 특징 태그 — 새 데이터는 `themeTags`(배열), 예전에 단일 `category`로
  /// 등록된 문서는 그 값을 태그 하나짜리 목록으로 읽는다.
  ///
  /// 태그의 뜻을 아는 곳이 여기라 읽는 규칙도 여기에 둔다 — 새 코드가 같은
  /// 규칙을 또 적지 않게 하기 위함이다(예전에 각자 적어 둔 사본들은
  /// main_screen `_placeThemeTags`·place_card_widget `placeThemeTags`·
  /// [PlaceFeatures]에 남아 있고, 규칙 자체는 넷 다 같다).
  static List<String> themeTagsOf(Map<String, dynamic> data) {
    final tags = (data['themeTags'] as List?)?.whereType<String>().toList();
    if (tags != null && tags.isNotEmpty) return tags;
    final legacy = data['category'] as String?;
    return legacy != null && legacy.isNotEmpty ? [legacy] : const [];
  }

  /// 이 플레이스가 '이벤트 진행중'을 켜 두었는가 — 🎪 이벤트 탐색의 **입구**다.
  /// (기간이 끝났는지까지 보는 판정은 [PlaceEventTaxonomy.isRunningAt]에 있다.)
  static bool hasEventTag(Map<String, dynamic> data) =>
      themeTagsOf(data).contains(placeEventTag);

  /// 태그 저장값 → 화면 표기. 표기를 따로 정하지 않은 태그는 저장값 그대로다.
  static String placeThemeTagLabel(String tag) =>
      placeThemeTagLabels[tag] ?? tag;

  /// 표기 → 저장값(역방향). 필터 칩처럼 **화면에 적힌 문구로 값을 되찾아야**
  /// 하는 곳에서 쓴다(지역 칩이 `RegionSelection.label`을 되짚는 것과 같다).
  static String placeThemeTagValue(String label) {
    for (final e in placeThemeTagLabels.entries) {
      if (e.value == label) return e.key;
    }
    return label;
  }

  // ── 이벤트 진행중 소분류 ─────────────────────────────────────────────
  // '이벤트 진행중'을 켠 플레이스만 고르는 한 단계 아래 갈래 —
  // Firestore `eventSubtype`(문자열 하나). 태그를 끄면 값을 남기지 않는다.
  //
  // 특징 태그([placeThemeTags])와 층이 다르다: 태그는 여러 개를 켜는 "성격",
  // 소분류는 진행 중인 이벤트가 **무엇인지** 하나만 고르는 값이다.
  static const String birthdayEventSubtype = '생일파티 이벤트';

  static const List<String> placeEventSubtypes = [birthdayEventSubtype];

  static const Map<String, String> placeEventSubtypeEmojis = {
    birthdayEventSubtype: '🎂',
  };

  /// 생일 이벤트로 자동 분류하는 낱말.
  ///
  /// '생일'만 있어도 '생일자'·'생일파티'가 함께 걸리지만(부분 문자열), 어떤
  /// 말을 노린 것인지 코드에 남겨 둔다 — 나중에 낱말을 빼거나 더할 때
  /// 판단 근거가 된다.
  static const List<String> birthdayEventKeywords = ['생일', '생일자', '생일파티'];

  /// 이벤트 글에서 소분류를 자동으로 고른다. 고를 수 없으면 null.
  ///
  /// [texts]는 **호스트가 직접 적는 칸 전부**를 넘긴다
  /// ([PlacePromotion.searchTexts]) — 제목 한 곳만 보면 "9월 한 달 생일자
  /// 무료" 같은 내용이 혜택 칸에만 적혔을 때 놓친다.

  static String? autoEventSubtypeFor(Iterable<String> texts) {
    for (final raw in texts) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      if (birthdayEventKeywords.any(t.contains)) return birthdayEventSubtype;
    }
    return null;
  }

  static String placeEventSubtypeLabel(String subtype) {
    final emoji = placeEventSubtypeEmojis[subtype];
    return emoji == null || emoji.isEmpty ? subtype : '$emoji $subtype';
  }
}
