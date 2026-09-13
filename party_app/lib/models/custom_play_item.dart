/// 호스트가 직접 입력하는 **기타 놀거리**의 정본.
///
/// ── 프리셋은 손대지 않는다 ────────────────────────────────────────────────
/// 놀거리 선택지(보드게임·다트·당구·노래방·오락기·콘솔게임·기타)는
/// [PlaceAttributeCatalog.playItems]가 정본이고, 그 값들은
/// `placeAttributes.playItems` 배열에 그대로 들어간다. 호스트가 만든 말
/// ("포켓볼", "테이블축구")을 **그 배열에 섞으면**
///
///   · 프리셋 목록이 코드에서 닫힌 어휘가 아니게 되고(게스트 필터가 고를 수
///     있는 값을 더 이상 코드로 알 수 없다),
///   · '기타'를 껐다 켜는 것과 자유기재 값의 생사가 한 배열에 엉킨다.
///
/// 그래서 자유기재는 **문서 루트의 별도 배열**에 담는다. 프리셋 배열은
/// 조금도 달라지지 않는다.
///
/// ── 저장 형태 ─────────────────────────────────────────────────────────────
/// ```
/// placeAttributes: { playItems: ['보드게임', '기타'] }   // 정본 그대로
/// customPlayItems: ['포켓볼', '테이블축구', '마작']       // 이 파일
/// ```
/// 필드 이름을 `customPlayItems`로 둔 이유는 짝을 눈으로 찾게 하기 위해서다 —
/// `playItems`를 grep하면 프리셋 그룹과 이 배열이 함께 잡힌다. 이름 규칙은
/// 옆 축인 [CustomAmenities](`customAmenities`)와 같다.
///
/// ── '기타'가 켜져 있을 때만 살아 있는 값이다 ──────────────────────────────
/// 값의 생사는 **저장 시점에** [activeFor]가 정한다 — '기타'를 끈 채 저장하면
/// 빈 배열이 들어간다. 반대로 화면에서 '기타'를 잠깐 껐다고 입력해 둔 열 개를
/// 그 자리에서 지우지는 않는다(호스트가 실수로 한 번 누른 것이 되돌릴 수 없는
/// 삭제가 되면 안 된다). 임시저장에는 '기타'와 무관하게 담기므로, 다시 켜면
/// 그대로 돌아온다.
///
/// ── 비교 규칙은 새로 만들지 않는다 ────────────────────────────────────────
/// 정규화·중복 판정·초성 묶음은 [CustomAmenities]의 것을 **그대로 쓴다**.
/// 같은 성격의 자유 입력이 축마다 다른 규칙으로 비교되면, "포켓볼"과 "포켓 볼"이
/// 어느 화면에서는 같고 어느 화면에서는 다른 값이 된다.
library;

import 'package:party_app/models/custom_amenity.dart';
import 'package:party_app/models/place_attributes.dart';

/// 목록 한 줄 — 기타 편의 서비스와 **같은 타입**이다(표시 원문 + 개수).
typedef CustomPlayItemEntry = CustomAmenityEntry;

/// 초성 묶음 — 역시 같은 타입이다.
typedef CustomPlayItemGroup = CustomAmenityGroup;

class CustomPlayItems {
  CustomPlayItems._();

  /// Firestore 필드 이름 — 매장 플레이스(`events`) 문서의 루트.
  ///
  /// 장소대여(`places`)에는 붙지 않는다. 놀거리는 `placeAttributes` 축에
  /// 딸린 값인데 그 축 자체가 events 전용이다(장소대여 등록 화면에는
  /// [PlaceAttributesSection]이 없고, [PlaceFilter]에도 attributes가 없다).
  static const String field = 'customPlayItems';

  /// 짝이 되는 프리셋 그룹 키(`placeAttributes.playItems`).
  static const String groupKey = PlaceAttributeCatalog.playItemsKey;

  /// 이 입력을 여는 프리셋 선택지 — 저장값 그대로.
  static const String etcOption = '기타';

  /// 한 플레이스가 등록할 수 있는 항목 수.
  static const int maxCount = 10;

  /// 한 항목의 최대 글자 수.
  ///
  /// 기타 편의 서비스(20자)보다 짧다 — 놀거리는 "포켓볼"·"테이블축구"·
  /// "VR게임"처럼 **이름 하나**이고, 게스트가 그 이름으로 목록에서 찾는다.
  /// 설명이 붙기 시작하면("2층에 있는 포켓볼 테이블") 아무도 그 말로 찾지 않는다.
  static const int maxLength = 12;

  // ── 화면 문구 ───────────────────────────────────────────────────────────

  static const String sectionTitle = '기타 놀거리';

  static const String inputGuide =
      '목록에 없는 놀거리를 직접 추가해주세요. 최대 $maxCount개까지 등록할 수 있어요.';

  static const String inputHint = '놀거리 이름 입력';

  /// 빈 값·길이 초과에 함께 쓰는 안내. 두 경우 모두 호스트가 해야 할 일은
  /// 같다 — 짧고 명확한 이름을 적는 것이다.
  static const String shortNameMessage = '놀거리 이름을 짧고 명확하게 입력해주세요.';

  static const String duplicateMessage = '이미 추가한 놀거리예요.';

  static const String fullMessage = '최대 $maxCount개까지 등록할 수 있어요.';

  static const String emptyBrowseMessage = '아직 등록된 기타 놀거리가 없어요.';

  static const String browseSubtitle = '호스트가 직접 등록한 놀거리예요';

  // ── 정규화 · 검증 (규칙은 [CustomAmenities]와 하나) ──────────────────────

  static String normalize(String raw) => CustomAmenities.normalize(raw);

  static bool sameItem(String a, String b) => CustomAmenities.sameItem(a, b);

  static String? clean(String raw) => CustomAmenities.clean(raw);

  /// 저장 전 검증 — 통과하면 null, 막아야 하면 사용자에게 보여줄 문구.
  static String? validate(String raw, {Iterable<String> existing = const []}) {
    final cleaned = clean(raw);
    if (cleaned == null) return shortNameMessage;
    if (cleaned.runes.length > maxLength) return shortNameMessage;
    final key = normalize(cleaned);
    for (final e in existing) {
      if (normalize(e) == key) return duplicateMessage;
    }
    if (existing.length >= maxCount) return fullMessage;
    return null;
  }

  // ── 문서 읽기 / 쓰기 ────────────────────────────────────────────────────

  /// 문서에서 기타 놀거리 목록을 읽는다. 필드가 없는 옛 문서는 빈 목록이다.
  static List<String> of(Map<String, dynamic> data) {
    final raw = data[field];
    if (raw is! List) return const [];
    return sanitize(raw.whereType<String>());
  }

  /// 저장할 배열 — 공백 정리 · 빈 값 제거 · 정규화 기준 중복 제거 ·
  /// 길이/개수 제한. 중복이 겹치면 **먼저 온 표기**를 남긴다.
  static List<String> sanitize(Iterable<String> raw) =>
      CustomAmenities.sanitize(raw, maxLength: maxLength, maxCount: maxCount);

  /// 문서에 쓸 값 — 비어 있으면 빈 배열을 그대로 쓴다(필드를 지우지 않는다).
  static List<String> toStored(Iterable<String> raw) => sanitize(raw);

  /// **저장 시점에 살아 있는 값.** 프리셋에서 '기타'를 고르지 않았으면
  /// 입력해 둔 값이 있어도 빈 배열이다 — 화면에서 꺼 둔 것이 문서에서는
  /// 켜져 있는 상태를 만들지 않는다.
  static List<String> activeFor(
    PlaceAttributes attrs,
    Iterable<String> items,
  ) => isEtcSelected(attrs) ? toStored(items) : const [];

  /// 프리셋 '기타'가 켜져 있는지.
  static bool isEtcSelected(PlaceAttributes attrs) =>
      attrs.isSelected(groupKey, etcOption);

  // ── 필터 판정 ───────────────────────────────────────────────────────────

  /// 이 문서의 정규화 키 집합.
  static Set<String> keysOf(Map<String, dynamic> data) =>
      of(data).map(normalize).toSet();

  /// [wanted] 중 **하나라도** 가진 문서인지.
  ///
  /// OR인 이유: 이 값들은 게스트 화면에서 놀거리 프리셋(보드게임·다트…)과
  /// 같은 줄에 서고, 그 그룹의 규칙이 "그룹 안은 OR"다
  /// ([EventFilter.attributes]). 같은 줄에서 고른 조건이 어떤 것은 넓히고
  /// 어떤 것은 좁히면 결과를 읽을 수 없다.
  static bool matchesAny(Map<String, dynamic> data, Set<String> wanted) {
    if (wanted.isEmpty) return true;
    final owned = keysOf(data);
    return wanted.map(normalize).any(owned.contains);
  }

  /// 표시 원문 묶음 → 정규화 키 묶음.
  static Set<String> keysFrom(Iterable<String> labels) =>
      labels.map(normalize).toSet();

  /// [labels] 안에 [label]과 같은 항목이 있는지(표기 차이를 무시).
  static bool contains(Iterable<String> labels, String label) =>
      keysFrom(labels).contains(normalize(label));

  // ── 목록 만들기 ─────────────────────────────────────────────────────────

  /// 지금 검색 범위의 문서들에서 기타 놀거리 목록을 만든다.
  ///
  /// **새 쿼리를 만들지 않는다** — 목록·지도가 이미 메모리에 들고 있는 문서를
  /// 그대로 넘겨받는다. 같은 키에 표기가 여럿이면 가장 많이 쓰인 표기를
  /// 대표로 쓴다(집계 규칙은 [CustomAmenities]와 하나).
  static List<CustomPlayItemEntry> catalogOf(
    Iterable<Map<String, dynamic>> docs,
  ) => CustomAmenities.catalogOfLists(docs.map(of));

  // ── 초성 탐색 ───────────────────────────────────────────────────────────

  /// 초성 탐색 탭을 붙이는 최소 항목 수 — 그보다 적으면 전부 한 번에 보여준다.
  static const int initialTabThreshold = CustomAmenities.initialTabThreshold;

  static CustomPlayItemGroup groupOf(String label) =>
      CustomAmenities.groupOf(label);

  static Map<CustomPlayItemGroup, List<CustomPlayItemEntry>> groupAll(
    List<CustomPlayItemEntry> entries,
  ) => CustomAmenities.groupAll(entries);
}
