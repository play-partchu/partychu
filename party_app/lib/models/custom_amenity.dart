/// 호스트가 직접 입력하는 **기타 편의 서비스**의 정본.
///
/// ── 왜 별도 필드인가 ──────────────────────────────────────────────────────
/// 정식 편의·서비스는 [PlaceFeatures]가, 좌석·이용 옵션은
/// [PlaceFacilityCatalog]가 정본이다. 둘 다 **닫힌 어휘**다 — 값이 코드에 있고
/// 필터 화면이 그 목록을 그대로 훑는다. 호스트가 만든 말("루프탑", "보드게임
/// 대여")을 그 어휘에 끼워 넣으면
///
///   · [PlaceFeature] enum이 런타임에 자라야 하고(불가능하고 위험하다),
///   · 필터 화면이 "고를 수 있는 값"을 더 이상 코드로 알 수 없어진다.
///
/// 그래서 자유 입력은 **완전히 다른 축**에 둔다. 정식 어휘는 하나도 건드리지
/// 않고, 이 파일이 그 축의 전부다.
///
/// 장소대여에는 이미 `commonFacilities`라는 자유 입력 가능한 배열이 있지만
/// 재사용하지 않는다 — 프리셋([ListingConstants.placeFacilities])과 호스트가
/// 친 값을 **한 배열에 섞어** 담고 있고, 그 필드는 OR로 걸리는 기존 편의시설
/// 필터의 정본이다. 거기에 기타를 합치면 "정식 편의시설"과 "호스트가 만든 말"이
/// 구분되지 않고, 결합 규칙도 두 개가 겹친다. 기존 필드는 그대로 두고 새 축만
/// 옆에 세운다.
///
/// ── 저장 형태 ─────────────────────────────────────────────────────────────
/// ```
/// customAmenities: ['루프탑', '보드게임 대여', '반려동물 물그릇']
/// ```
/// **플레이스(events)와 장소대여(places)가 같은 필드 이름을 쓴다.** 유형별로
/// 필드를 나누면 목록·지도가 두 벌의 판정을 들고 다녀야 하고, 같은 말이 두
/// 이름으로 쌓인다.
///
/// 표시 원문을 그대로 담는다("루프탑"). 비교·검색은 [normalize]가 만든 키로
/// 하되 그 키는 **저장하지 않는다** — 정규화 규칙이 나중에 바뀌어도 이미 쌓인
/// 문서를 고칠 일이 없어야 하기 때문이다.
library;

/// 초성 탐색에서 항목이 속하는 묶음 하나.
///
/// 한글은 첫 글자의 초성, 영문은 대문자 한 글자, 숫자는 `0-9`, 그 밖(이모지·
/// 기호로 시작하는 값)은 `#`로 모은다.
class CustomAmenityGroup implements Comparable<CustomAmenityGroup> {
  /// 탭에 그려지는 글자('ㄹ', 'B', '0-9', '#').
  final String label;

  /// 정렬 순서 — 한글(0) → 영문(1) → 숫자(2) → 기타(3).
  final int rank;

  const CustomAmenityGroup(this.label, this.rank);

  @override
  bool operator ==(Object other) =>
      other is CustomAmenityGroup && other.label == label;

  @override
  int get hashCode => label.hashCode;

  @override
  int compareTo(CustomAmenityGroup other) {
    if (rank != other.rank) return rank.compareTo(other.rank);
    return label.compareTo(other.label);
  }

  @override
  String toString() => label;
}

/// 목록에 뿌릴 기타 편의 서비스 한 줄 — 표시 원문 + 현재 검색 범위의 개수.
class CustomAmenityEntry {
  /// 비교·필터에 쓰는 정규화 키.
  final String key;

  /// 화면에 그대로 보여줄 원문. 같은 키의 표기가 여럿이면 가장 많이 쓰인 것.
  final String label;

  /// 지금 검색 범위에서 이 항목을 가진 플레이스 수. 항상 1 이상이다
  /// (0건은 애초에 목록에 오르지 않는다).
  final int count;

  const CustomAmenityEntry({
    required this.key,
    required this.label,
    required this.count,
  });

  CustomAmenityGroup get group => CustomAmenities.groupOf(label);
}

class CustomAmenities {
  CustomAmenities._();

  /// Firestore 필드 이름 — events / places 공용.
  static const String field = 'customAmenities';

  /// 한 항목의 최대 글자 수.
  ///
  /// 검색 키워드로 쓰는 값이라 문장이 들어오면 아무도 그 말로 검색하지
  /// 않는다. 그렇다고 "반려동물 물그릇"(8자)·"유아용 의자"(6자)처럼 자연스럽게
  /// 두세 단어가 필요한 항목까지 막으면 안 되므로, 그보다 넉넉하되 설명문은
  /// 확실히 걸리는 자리에 둔다.
  static const int maxLength = 20;

  /// 한 플레이스가 가질 수 있는 항목 수 — 이보다 많으면 태그 뿌리기다.
  static const int maxCount = 20;

  /// 입력 영역에 그대로 쓰는 안내 문구. 화면마다 다시 쓰지 않는다.
  static const String inputGuide = '사용자가 쉽게 검색할 수 있도록 짧고 명확한 단어로 입력해주세요.';

  /// 안내 아래에 붙는 보조 예시.
  static const String inputExamples = '예) 루프탑, 보드게임, 유아의자, 반려동물 물그릇';

  /// 입력칸 placeholder — 예시를 길게 늘어놓으면 그만큼 길게 써도 된다고 읽힌다.
  static const String inputHint = '예) 루프탑';

  /// 길이를 넘겼을 때 보여줄 문구.
  static const String tooLongMessage = '편의 서비스는 검색하기 쉬운 짧은 단어로 입력해주세요.';

  // ── 정규화 ──────────────────────────────────────────────────────────────

  /// 비교·검색·중복 판정에 쓰는 **단 하나의** 키.
  ///
  /// 화면마다 `a.trim() == b.trim()` 같은 비교를 흩어 놓으면 "유아의자"와
  /// "유아 의자"가 어떤 화면에서는 같고 어떤 화면에서는 다른 값이 된다.
  ///
  /// 규칙:
  ///  · 앞뒤 공백 제거
  ///  · 사이 공백은 **전부 삭제**(붙여 쓴 말과 띄어 쓴 말을 같게 본다)
  ///  · 영문은 소문자로
  ///  · 중간점·하이픈처럼 표기 취향으로 갈리는 구분자 제거
  ///
  /// 한글 자모 분해나 유의어 판단은 하지 않는다 — "유아의자"와 "아기의자"는
  /// 다른 말이고, 그 둘을 합치는 것은 자동완성이 할 일이지
  /// ([suggestionsFor]) 정규화가 할 일이 아니다.
  static String normalize(String raw) {
    final buffer = StringBuffer();
    for (final rune in raw.trim().toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      if (_ignored.contains(ch)) continue;
      buffer.write(ch);
    }
    return buffer.toString();
  }

  /// 정규화에서 지우는 문자 — 공백과 표기 취향으로 갈리는 구분자.
  static const Set<String> _ignored = {
    ' ',
    '\t',
    ' ', // 줄바꿈 없는 공백(모바일 키보드가 넣는 경우가 있다)
    '·',
    '-',
    '_',
    '/',
    ',',
  };

  /// 두 표기가 같은 항목인지.
  static bool sameItem(String a, String b) => normalize(a) == normalize(b);

  // ── 검증 ────────────────────────────────────────────────────────────────

  /// 입력값을 저장 가능한 형태로 다듬는다 — 저장할 수 없으면 null.
  ///
  /// 원문 표기는 **자연스럽게 유지한다**: 앞뒤 공백만 떼고 사이 공백·대소문자는
  /// 호스트가 친 그대로 둔다(정규화는 비교용이지 표기용이 아니다).
  static String? clean(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (normalize(trimmed).isEmpty) return null;
    return trimmed;
  }

  /// 저장 전 검증 — 통과하면 null, 막아야 하면 사용자에게 보여줄 문구.
  static String? validate(String raw, {Iterable<String> existing = const []}) {
    final cleaned = clean(raw);
    if (cleaned == null) return '편의 서비스 이름을 입력해주세요.';
    if (cleaned.characters > maxLength) return tooLongMessage;
    final key = normalize(cleaned);
    for (final e in existing) {
      if (normalize(e) == key) return '이미 추가한 편의 서비스예요.';
    }
    return null;
  }

  // ── 문서 읽기 / 쓰기 ────────────────────────────────────────────────────

  /// 문서에서 기타 편의 서비스 목록을 읽는다.
  ///
  /// 필드가 없는 옛 문서는 빈 목록이다 — 그래서 기존 플레이스는 이 축의
  /// 필터에서만 빠지고, 정식 편의·서비스 판정은 조금도 달라지지 않는다.
  static List<String> of(Map<String, dynamic> data) {
    final raw = data[field];
    // 배열이 아닌 값(콘솔에서 손댄 문서, 옛 스키마)은 없는 것으로 본다 —
    // 여기서 터지면 목록·지도·상세가 통째로 빈 화면이 된다.
    if (raw is! List) return const [];
    return sanitize(raw.whereType<String>());
  }

  /// 저장할 배열을 만든다 — 공백 정리 · 빈 값 제거 · 정규화 기준 중복 제거 ·
  /// 길이/개수 제한. **하나의 긴 문자열로 합치지 않는다.**
  ///
  /// 중복이 겹치면 **먼저 온 표기**를 남긴다(호스트가 처음 친 표기가 그 가게의
  /// 표기다).
  ///
  /// [maxLength]·[maxCount]는 **같은 성격의 다른 축**이 이 규칙을 그대로
  /// 쓰면서 자기 상한만 다르게 둘 수 있도록 열어 둔 것이다
  /// ([CustomPlayItems] — 놀거리 이름은 더 짧고 개수도 더 적다). 안 넘기면
  /// 기타 편의 서비스의 상한이다.
  static List<String> sanitize(
    Iterable<String> raw, {
    int? maxLength,
    int? maxCount,
  }) {
    final lengthCap = maxLength ?? CustomAmenities.maxLength;
    final countCap = maxCount ?? CustomAmenities.maxCount;
    final seen = <String>{};
    final result = <String>[];
    for (final item in raw) {
      final cleaned = clean(item);
      if (cleaned == null) continue;
      if (cleaned.characters > lengthCap) continue;
      final key = normalize(cleaned);
      if (!seen.add(key)) continue;
      result.add(cleaned);
      if (result.length >= countCap) break;
    }
    return result;
  }

  /// 문서에 쓸 값 — 비어 있으면 빈 배열을 그대로 쓴다(필드를 지우지 않는다.
  /// 지우면 "한 번도 안 쓴 문서"와 "전부 뺀 문서"가 구분되지 않는다).
  static List<String> toStored(Iterable<String> raw) => sanitize(raw);

  // ── 필터 판정 ───────────────────────────────────────────────────────────

  /// 이 문서의 정규화 키 집합 — 필터·검색이 모두 이 하나만 본다.
  static Set<String> keysOf(Map<String, dynamic> data) =>
      of(data).map(normalize).toSet();

  /// [wanted]를 **전부** 가진 문서인지.
  ///
  /// [wanted]에는 필터가 들고 있는 **표시 원문**이 들어온다 — 여기서 정규화해
  /// 비교하므로 호출부가 표기를 맞출 필요가 없다("루프탑"으로 고른 필터가
  /// "루프 탑"으로 저장된 플레이스도 잡는다).
  ///
  /// AND인 이유: 이 축은 게스트 화면에서 ✨ 편의·서비스와 같은 자리에 서고,
  /// 그쪽 판정이 AND다([PlaceFeatures.matchesAll]). 한 화면의 같은 줄에서
  /// 고른 조건이 어떤 것은 좁히고 어떤 것은 넓히면 결과를 읽을 수 없다.
  static bool matchesAll(Map<String, dynamic> data, Set<String> wanted) {
    if (wanted.isEmpty) return true;
    return keysOf(data).containsAll(wanted.map(normalize));
  }

  /// 표시 원문 묶음을 정규화 키 묶음으로 — 화면이 "이미 고른 항목인가"를
  /// 물을 때 쓴다.
  static Set<String> keysFrom(Iterable<String> labels) =>
      labels.map(normalize).toSet();

  /// [labels] 안에 [label]과 같은 항목이 있는지(표기 차이를 무시).
  static bool contains(Iterable<String> labels, String label) =>
      keysFrom(labels).contains(normalize(label));

  // ── 목록 만들기 ─────────────────────────────────────────────────────────

  /// 지금 검색 범위의 문서들에서 기타 편의 서비스 목록을 만든다.
  ///
  /// **새 쿼리를 만들지 않는다** — 목록·지도가 이미 메모리에 들고 있는 문서를
  /// 그대로 넘겨받는다([ListingSources]가 events/places를 통째로 읽고 필터는
  /// 전부 클라이언트에서 건다). 그래서 개수도 "지금 보고 있는 범위의 개수"가
  /// 되고, 0건 항목은 애초에 만들어지지 않는다.
  ///
  /// 같은 키에 표기가 여럿이면(루프탑 / 루프 탑) **가장 많이 쓰인 표기**를
  /// 대표로 쓰고, 동률이면 사전순으로 정해 화면이 새로고침마다 바뀌지 않게 한다.
  static List<CustomAmenityEntry> catalogOf(
    Iterable<Map<String, dynamic>> docs,
  ) => catalogOfLists(docs.map(of));

  /// 집계 본체 — **문서에서 항목을 이미 꺼낸 상태**로 받는다.
  ///
  /// 같은 성격의 다른 자유기재 축이 이 집계를 그대로 쓰기 위한 입구다
  /// ([CustomPlayItems.catalogOf]). 목록·개수·대표 표기·정렬 규칙이 한 곳에만
  /// 있어야 축마다 목록이 다른 순서로 나오지 않는다.
  ///
  /// [perDoc]의 한 원소 = 한 문서의 항목들. 문서 안 중복은 이미 걸러져 있다고
  /// 본다(각 축의 `of`가 sanitize를 거친다).
  static List<CustomAmenityEntry> catalogOfLists(
    Iterable<List<String>> perDoc,
  ) {
    final counts = <String, int>{};
    final labels = <String, Map<String, int>>{};
    for (final items in perDoc) {
      for (final item in items) {
        final key = normalize(item);
        counts[key] = (counts[key] ?? 0) + 1;
        (labels[key] ??= <String, int>{}).update(
          item,
          (n) => n + 1,
          ifAbsent: () => 1,
        );
      }
    }

    final entries = <CustomAmenityEntry>[
      for (final e in counts.entries)
        CustomAmenityEntry(
          key: e.key,
          label: _representativeLabel(labels[e.key]!),
          count: e.value,
        ),
    ];
    entries.sort((a, b) {
      // 많이 쓰인 것이 위 — 게스트가 실제로 만날 확률이 높은 순서다.
      if (a.count != b.count) return b.count.compareTo(a.count);
      return a.label.compareTo(b.label);
    });
    return entries;
  }

  static String _representativeLabel(Map<String, int> variants) {
    var best = '';
    var bestCount = -1;
    for (final e in variants.entries) {
      if (e.value > bestCount ||
          (e.value == bestCount && e.key.compareTo(best) < 0)) {
        best = e.key;
        bestCount = e.value;
      }
    }
    return best;
  }

  /// 호스트가 입력하는 동안 보여줄 **기존 항목 후보**.
  ///
  /// 새 말을 만들기 전에 이미 쓰이는 말을 먼저 고르게 하려는 것이다 —
  /// 유아의자 / 아기의자 / 유아 의자가 따로 쌓이는 것을 줄인다.
  ///
  /// [query]가 비어 있으면 많이 쓰인 순 상위 [limit]개(= 무엇을 적는 칸인지
  /// 보여주는 역할), 값이 있으면 정규화 키로 **부분 일치**하는 것만.
  /// [exclude]는 이미 이 플레이스가 고른 항목이다.
  static List<CustomAmenityEntry> suggestionsFor(
    List<CustomAmenityEntry> catalog,
    String query, {
    Iterable<String> exclude = const [],
    int limit = 6,
  }) {
    final taken = exclude.map(normalize).toSet();
    final q = normalize(query);
    final matched = <CustomAmenityEntry>[];
    for (final e in catalog) {
      if (taken.contains(e.key)) continue;
      if (q.isNotEmpty && !e.key.contains(q)) continue;
      matched.add(e);
      if (matched.length >= limit) break;
    }
    return matched;
  }

  // ── 초성 탐색 ───────────────────────────────────────────────────────────

  /// 초성 탐색 탭을 붙일지 — 항목이 적으면 전부 한 번에 보여주는 편이 빠르다.
  static const int initialTabThreshold = 15;

  static const List<String> _choseong = [
    'ㄱ',
    'ㄲ',
    'ㄴ',
    'ㄷ',
    'ㄸ',
    'ㄹ',
    'ㅁ',
    'ㅂ',
    'ㅃ',
    'ㅅ',
    'ㅆ',
    'ㅇ',
    'ㅈ',
    'ㅉ',
    'ㅊ',
    'ㅋ',
    'ㅌ',
    'ㅍ',
    'ㅎ',
  ];

  /// 탭에 그리는 초성 — 쌍자음(ㄲ·ㄸ…)은 자기 탭을 갖지 않고 기본 자음으로
  /// 접힌다. 게스트는 'ㄲ'을 찾지 않고 'ㄱ'을 누른다.
  static const List<String> baseChoseong = [
    'ㄱ',
    'ㄴ',
    'ㄷ',
    'ㄹ',
    'ㅁ',
    'ㅂ',
    'ㅅ',
    'ㅇ',
    'ㅈ',
    'ㅊ',
    'ㅋ',
    'ㅌ',
    'ㅍ',
    'ㅎ',
  ];

  /// 쌍자음 → 묶이는 기본 자음.
  static const Map<String, String> _doubleToBase = {
    'ㄲ': 'ㄱ',
    'ㄸ': 'ㄷ',
    'ㅃ': 'ㅂ',
    'ㅆ': 'ㅅ',
    'ㅉ': 'ㅈ',
  };

  /// 숫자로 시작하는 항목이 모이는 탭.
  static const CustomAmenityGroup digitGroup = CustomAmenityGroup('0-9', 2);

  /// 한글·영문·숫자 어디에도 안 붙는 항목(이모지·기호로 시작).
  static const CustomAmenityGroup otherGroup = CustomAmenityGroup('#', 3);

  /// **표시 문자열의 첫 글자**로 묶음을 정한다.
  ///
  /// 정규화 키가 아니라 원문을 보는 이유: 게스트는 화면에 보이는 글자로
  /// 찾는다. 정규화가 지우는 문자(중간점 등)로 시작하는 값은 그 문자를 건너뛰고
  /// 첫 의미 글자를 본다.
  static CustomAmenityGroup groupOf(String label) {
    for (final rune in label.trim().runes) {
      final ch = String.fromCharCode(rune);
      if (_ignored.contains(ch)) continue;

      // 한글 완성형 가 ~ 힣 — 초성은 (코드 - 0xAC00) ~/ 588.
      if (rune >= 0xAC00 && rune <= 0xD7A3) {
        final cho = _choseong[(rune - 0xAC00) ~/ 588];
        return CustomAmenityGroup(_doubleToBase[cho] ?? cho, 0);
      }
      // 자모만 쓴 값('ㄱ자 바') — 그 자모 자체가 초성이다.
      if (rune >= 0x3131 && rune <= 0x314E) {
        return CustomAmenityGroup(_doubleToBase[ch] ?? ch, 0);
      }
      final upper = ch.toUpperCase();
      if (upper.codeUnitAt(0) >= 0x41 && upper.codeUnitAt(0) <= 0x5A) {
        return CustomAmenityGroup(upper, 1);
      }
      if (rune >= 0x30 && rune <= 0x39) return digitGroup;
      return otherGroup;
    }
    return otherGroup;
  }

  /// 묶음별로 갈라 정렬한 목록 — 한글(초성순) → 영문(A-Z) → 0-9 → #.
  /// 각 묶음 안은 개수 많은 순, 동률이면 사전순.
  static Map<CustomAmenityGroup, List<CustomAmenityEntry>> groupAll(
    List<CustomAmenityEntry> entries,
  ) {
    final grouped = <CustomAmenityGroup, List<CustomAmenityEntry>>{};
    for (final e in entries) {
      (grouped[e.group] ??= <CustomAmenityEntry>[]).add(e);
    }
    final keys = grouped.keys.toList()..sort();
    return {
      for (final k in keys)
        k: grouped[k]!
          ..sort((a, b) {
            if (a.count != b.count) return b.count.compareTo(a.count);
            return a.label.compareTo(b.label);
          }),
    };
  }
}

/// 글자 수 세기 — 이모지·결합 문자를 한 글자로 세기 위해 `characters`
/// 패키지를 쓰지 않고 룬 개수로 센다(이 앱은 해당 패키지를 직접 쓰지 않는다).
extension _RuneLength on String {
  int get characters => runes.length;
}
