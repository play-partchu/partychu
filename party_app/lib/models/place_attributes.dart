/// 플레이스의 **세부 속성**(attribute) 정본.
///
/// ── 카테고리 / 특징 / 속성의 역할 분리 ────────────────────────────────────
/// 셋을 한 배열에 섞어 담으면(예전 `themeTags` 방식) 곧 엉킨다 — "클럽"과
/// "힙합"과 "콜키지 가능"이 같은 층에 있으면 필터가 무엇을 묻는 것인지 코드에서
/// 사라진다. 그래서 층을 셋으로 갈랐다.
///
///   · 카테고리 = 무슨 가게인가        → [PlaceTaxonomy] (`placeCategory`)
///   · 특징     = 한 번에 켜고 끄는 조건 → [PlaceFeatures]  (`placeFeatures`)
///   · 속성     = 그 안의 구체적인 값    → 이 파일          (`placeAttributes`)
///
/// 힙합·하이볼·와인·보드게임처럼 **여러 값 중 무엇인가**를 묻는 것이 속성이고,
/// 콜키지 가능·금연·대형스크린처럼 **있냐 없냐**를 묻는 것이 특징이다. 특징은
/// 대부분 속성에서 자동으로 유도된다([PlaceFeatures.of]) — 호스트가 같은 것을
/// 두 번 고르게 하지 않기 위해서다.
///
/// ── 저장 형태 (Firestore) ─────────────────────────────────────────────────
/// ```
/// placeAttributes: {
///   musicGenres: ['HIPHOP', 'R&B'],
///   corkage:     ['콜키지 프리'],        // 단일 선택도 배열로 담는다
///   unlimited:   ['하이볼', '고기·BBQ'],
/// }
/// placeAttributeDetails: {
///   unlimited: { price: '29,000원', time: '2시간', condition: '2인 이상' },
///   screen:    { size: '150인치', hdmi: true, ott: true },
/// }
/// ```
/// 단일 선택 그룹도 **배열**로 저장한다 — 나중에 다중으로 바뀌어도 저장 형태를
/// 바꾸지 않아도 되고, 읽는 쪽이 타입을 분기할 필요가 없다.
///
/// 카탈로그에 없는 그룹 키가 문서에 들어 있어도 **그대로 보존한다**(앱 버전
/// 차이). 옛 버전 앱이 저장을 다시 하면서 새 버전이 넣은 값을 지우면 안 된다.
library;

import 'package:party_app/models/place_taxonomy.dart';

/// 상세 입력란 하나의 타입.
enum PlaceDetailFieldType { text, number, toggle }

/// 속성에 딸린 상세 입력란(크기·이용시간·비용 등).
class PlaceDetailField {
  const PlaceDetailField({
    required this.key,
    required this.label,
    this.type = PlaceDetailFieldType.text,
    this.hint,
  });

  /// `placeAttributeDetails[groupKey][key]`에 저장되는 키. 변경 금지.
  final String key;
  final String label;
  final PlaceDetailFieldType type;
  final String? hint;
}

/// 그룹 안의 선택지 하나.
class PlaceAttributeOption {
  const PlaceAttributeOption(this.label, {this.emoji, this.displayLabel});

  /// **저장값**. 배포 후 변경 금지 — 이 문자열이 그대로 Firestore에 들어가고,
  /// 바꾸는 순간 그 값으로 저장된 플레이스가 필터에서 사라진다.
  final String label;

  final String? emoji;

  /// 화면에만 쓰는 글자 — 저장값은 그대로 두고 **보이는 말만** 바꿔야 할 때.
  /// null이면 [label]을 그대로 보여준다.
  ///
  /// 지금 쓰는 곳은 `'콜키지 프리'` 하나다: 게스트·호스트에게는 '콜키지 무료'로
  /// 보이지만 저장값은 옛 문서와 같은 `'콜키지 프리'`로 남는다.
  final String? displayLabel;

  /// 화면에 적을 글자(이모지 제외).
  String get text => displayLabel ?? label;

  String get display => emoji == null ? text : '$emoji $text';
}

/// 속성 그룹 하나 = `placeAttributes`의 키 하나.
class PlaceAttributeGroup {
  const PlaceAttributeGroup({
    required this.key,
    required this.title,
    required this.emoji,
    this.options = const [],
    this.details = const [],
    this.detailsOn,
    this.singleChoice = false,
    this.categories = const [],
    this.featureKeys = const [],
    this.hint,
  });

  /// Firestore 키. 변경 금지.
  final String key;
  final String title;
  final String emoji;
  final List<PlaceAttributeOption> options;

  /// 이 그룹에 딸린 상세 입력란.
  final List<PlaceDetailField> details;

  /// 상세 입력란을 펼치는 조건 — 이 선택지들 중 하나라도 고르면 펼친다.
  /// null이면 그룹에서 **뭐라도 골랐을 때** 펼친다(선택지가 없으면 항상).
  final Set<String>? detailsOn;

  final bool singleChoice;

  /// 이 그룹을 **어느 대분류에서 먼저 물을지**. 비어 있으면 모든 대분류 공통이다.
  ///
  /// ⚠️ 이것은 "그 업종에만 보여준다"가 아니라 **"어느 묶음에 넣는다"**이다.
  /// 특징을 켜는 그룹([featureKeys])은 여기 없는 업종의 등록 화면에도 나온다
  /// ([PlaceAttributeCatalog.extraGroupsFor]) — 업종에 맞는 것이 위로 오고
  /// 나머지는 '그 밖의 편의·서비스' 묶음으로 내려갈 뿐이다.
  final List<String> categories;

  /// 이 그룹이 켜는 **편의·서비스 특징**([PlaceFeatures]의 key).
  ///
  /// 문자열로 적는 이유는 방향 때문이다 — 특징 쪽이 이 파일을 읽어 값을
  /// 유도하므로([PlaceFeatures.of]) 반대로 import할 수 없다. 키가 실재하는지와
  /// 실제로 그 특징이 켜지는지는 테스트(place_amenity_host_parity_test.dart)가
  /// 못 박는다.
  ///
  /// 값이 있다는 것은 **게스트가 업종과 상관없이 그 조건으로 검색한다**는
  /// 뜻이다(지도 상세필터·✨ 편의·서비스 시트는 [PlaceFeatures.selectable]
  /// 전부를 보여준다). 그래서 이 목록이 비어 있지 않은 그룹은 [categories]와
  /// 무관하게 모든 업종의 등록 화면에 자리를 갖는다 — 그렇지 않으면 "게스트는
  /// 찾는데 호스트는 켤 수 없는" 조건이 생긴다.
  final List<String> featureKeys;

  final String? hint;

  String get display => '$emoji $title';

  bool appliesTo(String? category) =>
      categories.isEmpty || (category != null && categories.contains(category));

  bool hasOption(String label) => options.any((o) => o.label == label);

  /// 고른 값들로 상세 입력란을 펼칠지.
  bool showsDetails(Set<String> selected) {
    if (details.isEmpty) return false;
    if (options.isEmpty) return true;
    final trigger = detailsOn;
    if (trigger == null) return selected.isNotEmpty;
    return selected.any(trigger.contains);
  }
}

/// 앱 전체가 공유하는 속성 정의. **새 속성은 여기에만 추가한다.**
class PlaceAttributeCatalog {
  PlaceAttributeCatalog._();

  /// Firestore 필드 이름.
  static const String field = 'placeAttributes';
  static const String detailField = 'placeAttributeDetails';

  // ── 흡연 정책 ─────────────────────────────────────────────────────────
  //
  // "흡연 가능 true/false" 하나로는 현실을 못 담는다 — 실내는 금연인데 밖에
  // 흡연구역이 있는 가게가 가장 흔하다. 그래서 **좌석이 금연인가**와 **흡연할
  // 곳이 있는가**를 각각 읽어낼 수 있는 다섯 갈래로 나눈다
  // ([smokeFreeSeating] / [hasSmokingArea]).
  static const String smokingKey = 'smoking';
  static const String smokeFreeAll = '전 구역 금연';
  static const String smokeFreeIndoor = '실내 금연 / 야외 흡연 가능';
  static const String smokingRoom = '별도 흡연실 있음';
  static const String smokingArea = '별도 흡연구역 있음';
  static const String smokingAllowed = '흡연 가능 매장';

  static const smoking = PlaceAttributeGroup(
    key: smokingKey,
    title: '흡연 정책',
    emoji: '🚭',
    hint: '가장 가까운 것 하나만 골라주세요.',
    singleChoice: true,
    // 다섯 갈래가 두 특징으로 갈린다 — 좌석이 금연인가 / 담배 피울 곳이 있는가.
    featureKeys: ['금연', '흡연공간'],
    options: [
      PlaceAttributeOption(smokeFreeAll, emoji: '🚭'),
      PlaceAttributeOption(smokeFreeIndoor, emoji: '🚭'),
      PlaceAttributeOption(smokingRoom, emoji: '🚬'),
      PlaceAttributeOption(smokingArea, emoji: '🚬'),
      PlaceAttributeOption(smokingAllowed, emoji: '🚬'),
    ],
  );

  /// 좌석이 금연인가 — '흡연 가능 매장'만 아니면 앉는 자리는 금연이다.
  static bool smokeFreeSeating(String policy) => policy != smokingAllowed;

  /// 담배 피울 곳이 있는가 — '전 구역 금연'만 없다.
  static bool hasSmokingArea(String policy) => policy != smokeFreeAll;

  // ── 클럽 전용 ─────────────────────────────────────────────────────────

  /// 클럽·라이브의 하위 탐색 **정본**. 예전의 클럽 소분류('힙합클럽')와
  /// 같은 말을 두 곳에 저장하지 않도록, 장르는 여기 하나에만 적는다
  /// ([PlaceTaxonomy.legacyClubGenresOf]가 옛 값을 이쪽으로 읽어 준다).
  static const String musicGenresKey = 'musicGenres';

  static const musicGenres = PlaceAttributeGroup(
    key: musicGenresKey,
    title: '음악 장르',
    emoji: '🎧',
    hint: '주로 트는 장르를 모두 골라주세요.',
    categories: ['클럽', '라이브·공연'],
    // featureKeys 없음 — 장르만으로는 아무 특징도 안 켜진다. 🎧 DJ가 켜지는
    // 것은 '클럽 대분류 + 장르'가 함께일 때뿐이라([PlaceFeatures.of] ⑤),
    // 이 그룹 하나로 켤 수 있는 조건이 아니다.
    options: [
      PlaceAttributeOption('HIPHOP'),
      PlaceAttributeOption('R&B'),
      PlaceAttributeOption('EDM'),
      PlaceAttributeOption('House'),
      PlaceAttributeOption('Techno'),
      PlaceAttributeOption('K-POP'),
      PlaceAttributeOption('Latin'),
      PlaceAttributeOption('All Mix'),
    ],
  );

  static const dj = PlaceAttributeGroup(
    key: 'dj',
    title: 'DJ',
    emoji: '🎧',
    // 클럽·라이브·BAR에서 먼저 묻지만, DJ를 부르는 날이 있는 카페·맛집도
    // 게스트가 🎧로 찾는다 — 그래서 다른 업종에서도 켤 자리가 있어야 한다.
    categories: ['클럽', '라이브·공연', 'BAR'],
    featureKeys: ['DJ'],
    options: [PlaceAttributeOption('DJ 있음', emoji: '🎧')],
    detailsOn: {'DJ 있음'},
    details: [
      PlaceDetailField(key: 'lineup', label: '오늘 DJ · 라인업', hint: '예) DJ SODA'),
    ],
  );

  static const String clubEntryKey = 'clubEntry';
  static const String clubEntryPaid = '입장료 있음';
  static const String clubEntryFree = '무료입장 가능';

  static const clubEntry = PlaceAttributeGroup(
    key: clubEntryKey,
    title: '입장 정보',
    emoji: '🎟',
    categories: ['클럽'],
    // '🪑 테이블 예약'을 켜기는 하지만, 같은 조건이 **방문 예약 설정**으로도
    // 켜진다([PlaceFeatures.of] ⑦-1). 다른 길이 이미 모든 업종에 열려 있으므로
    // 클럽 전용 여섯 칸을 카페 등록 화면까지 끌고 가지 않는다
    // ([PlaceAttributeCatalog.featuresCoveredElsewhere]).
    featureKeys: ['테이블예약'],
    options: [
      PlaceAttributeOption('테이블 예약 가능', emoji: '🪑'),
      PlaceAttributeOption('신분증 필수', emoji: '🪪'),
      PlaceAttributeOption('드레스코드 있음', emoji: '👗'),
      // 입장료는 아래 상세 입력란(entryFee·freeEntry)에 금액으로 이미 적히지만,
      // **검색에 걸리려면 고른 값**이 있어야 한다 — 상세란은 자유 문장이라
      // 필터가 읽지 못한다. 그래서 "돈을 받나 / 공짜로 들어갈 길이 있나"만
      // 값으로 따로 켠다(금액 자체는 계속 상세란이 정본).
      PlaceAttributeOption(clubEntryPaid, emoji: '🎟'),
      PlaceAttributeOption(clubEntryFree, emoji: '🆓'),
    ],
    details: [
      PlaceDetailField(key: 'entryFee', label: '입장료', hint: '예) 20,000원'),
      PlaceDetailField(
        key: 'freeEntry',
        label: '무료입장 조건',
        hint: '예) 23시 이전 여성 무료',
      ),
      PlaceDetailField(key: 'peakTime', label: '피크타임', hint: '예) 23시~02시'),
      PlaceDetailField(key: 'ageLimit', label: '연령 제한', hint: '예) 19세 이상'),
      PlaceDetailField(key: 'dressCode', label: '드레스코드', hint: '예) 슬리퍼 불가'),
      PlaceDetailField(key: 'bottlePrice', label: '바틀 가격대', hint: '예) 15만원~'),
    ],
  );

  // ── 무제한 ────────────────────────────────────────────────────────────
  //
  // "무제한 있음" 하나로는 검색이 안 된다 — 게스트가 찾는 것은 "하이볼 무제한",
  // "BBQ 무제한"처럼 **무엇이** 무제한인가다.
  static const String unlimitedKey = 'unlimited';

  // 저장값 상수 — 화면·필터·표시 문구가 **같은 문자열 하나**를 보게 한다.
  // 앞 일곱 개는 이미 배포된 값이라 글자 하나도 바꾸지 않는다.
  static const String unlimitedMeat = '고기·BBQ';
  static const String unlimitedFood = '음식';
  static const String unlimitedBeer = '맥주';
  static const String unlimitedWine = '와인';
  static const String unlimitedHighball = '하이볼';
  static const String unlimitedAlcohol = '주류';
  static const String unlimitedDrink = '음료';
  // 여기부터가 새로 더한 갈래 — 업종마다 '무제한'의 뜻이 다르기 때문이다.
  // 노래방은 시간이, 놀거리는 이용 횟수가, 파티룸은 체류시간이 무제한이다.
  static const String unlimitedKaraokeTime = '노래방 시간';
  static const String unlimitedPlay = '놀거리 이용';
  static const String unlimitedStayTime = '이용시간';
  static const String unlimitedEtc = '기타';

  static const unlimited = PlaceAttributeGroup(
    key: unlimitedKey,
    title: '무제한',
    emoji: '♾',
    hint: '무제한으로 제공하는 것을 모두 골라주세요.',
    // 놀거리·체험이 새로 들어온다 — '노래방 시간 무제한'을 물을 곳이 없었다.
    //
    // 라이브·공연도 넣는다 — ✨ 편의·서비스 시트의 '♾ 무제한' 묶음은 업종을
    // 가리지 않고 뜨고 추천 갈래까지 정해져 있는데
    // ([PlaceQuickPicks] _unlimitedHead의 '라이브·공연'), 정작 그 업종
    // 호스트에게는 켤 자리가 없어 아무도 걸리지 않는 조건이었다.
    // 저장값은 그대로고 **등록 화면에 이 묶음이 뜨는 업종만** 늘어난다.
    categories: [
      '맛집',
      '술집',
      'BAR',
      '혼술바',
      '카페·디저트',
      '클럽',
      '놀거리',
      '체험·클래스',
      '라이브·공연',
    ],
    featureKeys: ['무제한'],
    options: [
      PlaceAttributeOption(unlimitedMeat),
      PlaceAttributeOption(unlimitedFood),
      PlaceAttributeOption(unlimitedBeer),
      PlaceAttributeOption(unlimitedWine),
      PlaceAttributeOption(unlimitedHighball),
      PlaceAttributeOption(unlimitedAlcohol),
      PlaceAttributeOption(unlimitedDrink),
      PlaceAttributeOption(unlimitedKaraokeTime),
      PlaceAttributeOption(unlimitedPlay),
      PlaceAttributeOption(unlimitedStayTime),
      PlaceAttributeOption(unlimitedEtc),
    ],
    details: [
      PlaceDetailField(key: 'price', label: '가격', hint: '예) 1인 29,000원'),
      PlaceDetailField(key: 'time', label: '이용 가능 시간', hint: '예) 2시간'),
      PlaceDetailField(key: 'condition', label: '이용 조건', hint: '예) 2인 이상 주문'),
    ],
  );

  /// 무제한 값 하나를 **게스트가 읽는 문장**으로 — '하이볼' → '하이볼 무제한'.
  ///
  /// 카드·상세·필터 칩이 전부 이 함수 하나를 부른다. '무제한'이라고만 적으면
  /// 무엇이 무제한인지 알 수 없고, 화면마다 따로 문장을 만들면 같은 값이 어떤
  /// 곳에서는 '하이볼 무제한', 어떤 곳에서는 '무제한 하이볼'이 된다.
  static String unlimitedPhrase(String value) => switch (value) {
    // 이미 '시간'·'이용'이라는 말을 품은 값은 그대로 붙이면 읽히고,
    unlimitedKaraokeTime => '노래방 시간 무제한',
    unlimitedPlay => '놀거리 이용 무제한',
    unlimitedStayTime => '이용시간 무제한',
    unlimitedFood => '뷔페·음식 무제한',
    // '기타 무제한'은 문장이 안 된다 — 갈래를 안 밝힌 것뿐이라 그냥 '무제한'.
    unlimitedEtc => '무제한',
    _ => '$value 무제한',
  };

  /// 이모지까지 붙인 표기 — '♾ 하이볼 무제한'.
  static String unlimitedDisplay(String value) => '♾ ${unlimitedPhrase(value)}';

  // ── 구워주는 서비스 ───────────────────────────────────────────────────
  //
  // '구워주는 집 true/false'로 두면 정작 손님이 궁금한 것이 사라진다 — 처음부터
  // 끝까지 직원이 굽는 집과 첫 판만 굽는 집은 같은 가게가 아니다. 그래서 저장은
  // **서비스 방식 하나**로 하고, 게스트 빠른필터에서는 그중 '구워주는' 갈래를
  // 묶어 🔥 칩 하나로 검색한다([PlaceFeatures.grill]).
  static const String grillKey = 'grillService';
  static const String grillAll = '직원이 전부 구워줌';
  static const String grillOnRequest = '요청 시 구워줌';
  static const String grillFirstOnly = '첫 판만 구워줌';
  static const String grillSelf = '직접 구움';

  static const grillService = PlaceAttributeGroup(
    key: grillKey,
    title: '구워주는 서비스',
    emoji: '🔥',
    hint: '고기를 누가 굽는지 하나만 골라주세요.',
    singleChoice: true,
    categories: ['맛집', '다이닝·파인다이닝', '술집', '놀거리', '체험·클래스'],
    featureKeys: ['구워줌'],
    options: [
      // 구워 주는 세 갈래는 같은 🔥로 묶는다 — 빠른필터의 '🔥 구워줘요'를 누르고
      // 들어온 사람이 상세에서 같은 표식을 찾을 수 있어야 한다.
      PlaceAttributeOption(grillAll, emoji: '🔥'),
      PlaceAttributeOption(grillOnRequest, emoji: '🔥'),
      PlaceAttributeOption(grillFirstOnly, emoji: '🔥'),
      PlaceAttributeOption(grillSelf, emoji: '🧑‍🍳'),
    ],
    detailsOn: {grillAll, grillOnRequest, grillFirstOnly},
    details: [
      PlaceDetailField(key: 'note', label: '안내', hint: '예) 첫 판은 직원이 구워드려요'),
      PlaceDetailField(key: 'fee', label: '추가비용', hint: '예) 없음 / 1인 2,000원'),
    ],
  );

  /// 직원이 구워 주는가 — '직접 구움'만 아니면 어떤 형태로든 구워 준다.
  static bool grillServed(String value) => value != grillSelf;

  // ── 조리 제공 ─────────────────────────────────────────────────────────
  //
  // '구워주는 서비스'와 **다른 질문**이다. 구워주는 서비스는 "고기를 누가
  // 굽는가"이고, 이쪽은 "손님이 조리를 아예 안 해도 되는가"다. 파스타집처럼
  // 구울 것이 없는 가게도 조리되어 나오고, 고깃집처럼 직접 굽는 가게도
  // 밑반찬·찌개는 조리되어 나온다 — 두 값은 서로를 배제하지 않는다.
  //
  // 그래서 [grillService]에 선택지를 하나 더 붙이지 않고 **그룹을 따로** 둔다.
  // 그쪽은 singleChoice라 값을 더하면 '구워줌'과 '조리되어 나옴'을 동시에
  // 고를 수 없게 된다.
  static const String cookedKey = 'cookedService';

  /// 저장값 — **이모지가 없는 안정적인 값**이다. 배포 후 변경 금지
  /// (파일 상단의 저장값 규칙과 같다). 화면 표기는 [cookedPhrase]가 만든다.
  static const String cookedServed = '조리되어 나옴';

  static const cookedService = PlaceAttributeGroup(
    key: cookedKey,
    title: '조리 제공',
    emoji: '🍽️',
    hint: '손님이 직접 굽거나 조리하지 않아도 되면 골라주세요.',
    // 구워주는 서비스와 같은 업종에서 먼저 묻는다 — 바로 옆에서 이어 물어야
    // 호스트가 두 질문의 차이를 알아챈다. 그 밖의 업종에서도 켤 수 있다
    // (안주가 조리되어 나오는 BAR·혼술바, 조리 음식을 내는 카페가 있다).
    categories: ['맛집', '다이닝·파인다이닝', '술집', '놀거리', '체험·클래스'],
    featureKeys: ['조리제공'],
    options: [PlaceAttributeOption(cookedServed, emoji: '🍽️')],
  );

  /// 게스트에게 보이는 말투 — 저장값('조리되어 나옴')은 그대로 두고 표기만
  /// 바꾼다. 카드·상세가 손님에게 말을 거는 자리라서 '나옴'보다 '나와요'다
  /// ([grillPhrase]와 같은 규칙).
  static String cookedPhrase(String value) =>
      value == cookedServed ? '조리되어 나와요' : value;

  /// 게스트에게 보이는 말투 — 저장값('…구워줌')은 그대로 두고 표기만 바꾼다.
  /// 카드·상세가 손님에게 말을 거는 자리라서 '구워줌'보다 '구워줘요'가 맞다.
  static String grillPhrase(String value) => switch (value) {
    grillAll => '직원이 전부 구워줘요',
    grillOnRequest => '요청 시 구워줘요',
    grillFirstOnly => '첫 판만 구워줘요',
    grillSelf => '직접 구워요',
    _ => value,
  };

  /// 값 하나를 카드·상세에서 읽히는 문구로. 그룹마다 말투가 다른 곳은 여기
  /// 하나를 거치게 해서, 화면마다 다른 문장이 생기지 않게 한다.
  /// 표기만 바꾼다 — 저장값도 필터 판정도 건드리지 않는다.
  static String phraseOf(String groupKey, String value) => switch (groupKey) {
    unlimitedKey => unlimitedPhrase(value),
    grillKey => grillPhrase(value),
    cookedKey => cookedPhrase(value),
    _ => value,
  };

  // ── 주류 / 콜키지 ─────────────────────────────────────────────────────

  /// 주류 종류 그룹의 키 — 아래 [servedDrinks]가 옛 문서를 이어 읽을 때 쓴다.
  /// 값은 예전 그대로다(변경 금지).
  static const String alcoholTypesKey = 'alcoholTypes';

  static const alcoholTypes = PlaceAttributeGroup(
    key: alcoholTypesKey,
    title: '주류 종류',
    emoji: '🥃',
    // ⚠️ 이 그룹은 featureKeys가 없어 [extraGroupsFor]가 건지지 못한다. 즉
    //    여기 없는 대분류로 저장하면 [pruneAttributesFor]가 고른 값을 통째로
    //    지운다 — 새 대분류를 추가할 때 이 줄을 함께 보지 않으면 와인 리스트가
    //    말없이 사라진다. 다이닝이 그래서 여기 있다.
    categories: ['술집', 'BAR', '혼술바', '맛집', '다이닝·파인다이닝', '클럽'],
    options: [
      PlaceAttributeOption('와인'),
      PlaceAttributeOption('위스키'),
      PlaceAttributeOption('하이볼'),
      PlaceAttributeOption('칵테일'),
      PlaceAttributeOption('생맥주'),
      PlaceAttributeOption('사케'),
      PlaceAttributeOption('전통주'),
    ],
  );

  static const String corkageKey = 'corkage';

  // ── 콜키지 저장값 네 가지 ────────────────────────────────────────────────
  //
  // 판정·표시는 전부 [PlaceCorkage]가 맡는다(place_corkage.dart). 여기서는
  // **저장값이 무엇인지**만 정한다. 넷 다 배포 후 변경 금지다.
  //
  // `'콜키지 프리'`는 게스트·호스트에게 '콜키지 무료'로 보이지만 저장값은
  // 옛 문서와 같게 둔다 — [PlaceAttributeOption.displayLabel]로 보이는 말만
  // 바꿨고 마이그레이션은 하지 않는다.
  //
  // `'콜키지 가능'`(무료인지 유료인지 모름)은 **선택지에서 빼지 않는다.**
  // [PlaceAttributes.toMap]이 선택지 목록에 없는 라벨을 저장에서 떨구기
  // 때문에, 빼는 순간 그렇게 등록해 둔 가게가 다음 저장 때 콜키지를 잃는다.
  static const String corkageNotAllowed = '콜키지 불가';
  static const String corkageAllowed = '콜키지 가능';
  static const String corkageFree = '콜키지 프리';
  static const String corkagePaid = '콜키지 유료';

  static const corkage = PlaceAttributeGroup(
    key: corkageKey,
    title: '콜키지',
    emoji: '🍶',
    hint: '술을 가져와도 되는지 하나만 골라주세요.',
    singleChoice: true,
    categories: ['술집', 'BAR', '혼술바', '맛집', '다이닝·파인다이닝', '클럽'],
    // 이 그룹에서 유도되는 빠른 특징 — 키는 옛 이름 그대로다(하위호환).
    // 무엇을 묻는지는 '무료인가'에서 '허용하는가'로 바뀌었다
    // ([PlaceFeatures.corkageAvailable], [PlaceCorkage.isAllowed]).
    featureKeys: ['콜키지프리'],
    options: [
      PlaceAttributeOption(corkageNotAllowed, emoji: '🚫'),
      PlaceAttributeOption(corkageAllowed, emoji: '🍾'),
      PlaceAttributeOption(corkageFree, emoji: '🍶', displayLabel: '콜키지 무료'),
      PlaceAttributeOption(corkagePaid, emoji: '💵'),
    ],
    detailsOn: {corkagePaid},
    details: [
      PlaceDetailField(key: 'fee', label: '콜키지 비용', hint: '예) 1병 10,000원'),
    ],
  );

  // ── 무알콜 음료 ───────────────────────────────────────────────────────
  //
  // 위 '주류 종류'에 끼워 넣지 않는다 — 무알콜은 주류가 아니라서, 그 그룹에
  // 넣으면 "이 집 술 뭐 있어요"를 묻는 자리에 술이 아닌 값이 섞인다.
  //
  // 대신 대형스크린·불멍·수영장과 **같은 모양**으로 둔다 — 값 하나짜리 그룹은
  // 이 카탈로그에 이미 넷이나 있고(있다/없다만 묻는 것들), 그 길을 그대로
  // 따르면 저장·복원·상세 표시·필터가 전부 기존 경로를 탄다.
  //
  // 업종을 가리지 않는다([categories] 없음) — 술을 파는 곳이든 아니든 "술
  // 안 마시는 사람이 시킬 게 있나"는 어디서나 물을 수 있어야 한다. 업종을
  // 좁히면 그 업종 호스트만 켤 수 없는데 게스트는 검색할 수 있는, 지금 고치려는
  // 바로 그 어긋남이 다시 생긴다.
  static const String drinksKey = 'drinks';
  static const String nonAlcoholicDrink = '무알콜 음료 있음';

  static const drinks = PlaceAttributeGroup(
    key: drinksKey,
    title: '무알콜 음료',
    emoji: '🥤',
    hint: '술을 안 마시는 손님이 시킬 수 있는 음료가 있으면 골라주세요.',
    featureKeys: ['무알콜'],
    options: [PlaceAttributeOption(nonAlcoholicDrink, emoji: '🥤')],
  );

  // ── 하이볼 · 막걸리 ───────────────────────────────────────────────────
  //
  // 게스트가 "🥃 하이볼 하는 집" / "🏺 막걸리 하는 집"으로 **콕 집어 찾는**
  // 두 가지. 위 [drinks](무알콜 음료)와 같은 모양이다 — 값 몇 개짜리 그룹이
  // 특징을 켜고, 저장·복원·카드·상세·필터가 전부 기존 경로를 그대로 탄다.
  //
  // ── 왜 '주류 종류'에 얹지 않았나 ──────────────────────────────────────
  // [alcoholTypes]에 이미 '하이볼'이 있지만, 그 그룹은 **특징을 하나도 켜지
  // 않는다** — 업종 안에서만 뜻이 있는 값이라 술집·BAR·맛집·클럽 등록
  // 화면에만 나온다(place_amenity_host_parity_test가 못 박고 있다).
  // 거기에 featureKeys를 붙이면 와인·위스키·사케까지 카페·놀거리 등록
  // 화면으로 딸려 나온다 — 이번 요청과 무관한 항목들이 움직인다.
  //
  // 그래서 **업종을 가리지 않는 새 그룹**을 둔다([categories] 없음). 하이볼을
  // 파는 카페도, 막걸리를 파는 맛집도 켤 자리가 있어야 게스트 필터와 어긋나지
  // 않는다.
  //
  // 대신 하이볼은 **옛 문서를 잇는 다리**를 놓는다 — 주류 종류에 '하이볼'을
  // 이미 골라 둔 가게는 여기서 다시 켜지 않아도 필터에 걸린다
  // ([PlaceFeatures.of], 노래방↔노래가능과 같은 관례). 막걸리는 그런 옛 값이
  // 없다 — '전통주'는 소주·약주까지 아우르는 다른 말이라 다리를 놓지 않는다.
  static const String servedDrinksKey = 'servedDrinks';
  static const String highballServed = '하이볼 판매';
  static const String makgeolliServed = '막걸리 판매';

  static const servedDrinks = PlaceAttributeGroup(
    key: servedDrinksKey,
    title: '하이볼 · 막걸리',
    emoji: '🥃',
    hint: '판매하는 것을 골라주세요.',
    featureKeys: ['하이볼', '막걸리'],
    options: [
      PlaceAttributeOption(highballServed, emoji: '🥃'),
      // 🏺 — 🍶는 콜키지가 이미 쓰고 있다([PlaceFeatures.makgeolli] 주석).
      PlaceAttributeOption(makgeolliServed, emoji: '🏺'),
    ],
  );

  // ── 시설 ──────────────────────────────────────────────────────────────

  static const String screenKey = 'screen';

  static const screen = PlaceAttributeGroup(
    key: screenKey,
    title: '대형스크린',
    emoji: '🖥',
    featureKeys: ['대형스크린'],
    options: [
      PlaceAttributeOption('대형스크린 있음', emoji: '🖥'),
      PlaceAttributeOption('HDMI 연결 가능'),
      PlaceAttributeOption('OTT 연결 가능'),
    ],
    detailsOn: {'대형스크린 있음'},
    details: [PlaceDetailField(key: 'size', label: '크기', hint: '예) 150인치')],
  );

  static const String playItemsKey = 'playItems';

  static const playItems = PlaceAttributeGroup(
    key: playItemsKey,
    title: '놀거리',
    emoji: '🎲',
    hint: '매장에서 즐길 수 있는 것을 모두 골라주세요.',
    // '노래방'을 고르면 🎤 노래 가능까지 함께 켜진다(옛 문서를 잇는 다리).
    featureKeys: ['놀거리', '노래가능'],
    options: [
      PlaceAttributeOption('보드게임'),
      PlaceAttributeOption('다트'),
      PlaceAttributeOption('당구'),
      PlaceAttributeOption('노래방'),
      PlaceAttributeOption('오락기'),
      PlaceAttributeOption('콘솔게임'),
      PlaceAttributeOption('기타'),
    ],
  );

  // ── 노래 ──────────────────────────────────────────────────────────────
  //
  // 두 칸은 **서로 다른 조건**이라 하나로 합치지 않는다.
  //
  //   · 노래 가능      — 손님이 **직접 부른다**(노래방 기기·마이크).
  //   · 노래 신청 가능 — 손님이 **듣고 싶은 곡을 신청한다**(매장·DJ·공연
  //     운영자에게). 부르는 것이 아니다.
  //
  // 라이브 공연(무대에서 남이 부른다)·DJ 유무·노래방 시간 무제한(얼마나 오래
  // 쓰나)과도 각각 묻는 것이 다르다.
  //
  // 저장값은 이모지 없는 문자열이고, 화면 표기는 특징 쪽
  // ([PlaceFeatures.singing] · [PlaceFeatures.songRequest])이 붙인다.
  static const String singingKey = 'singing';

  /// Firestore `placeAttributes.singing` 배열에 그대로 들어가는 값.
  static const String singingAvailable = '노래 가능';

  /// 같은 배열에 들어가는 **다른** 값 — 켜고 끄는 것도 따로다.
  static const String songRequestAvailable = '노래 신청 가능';

  static const singing = PlaceAttributeGroup(
    key: singingKey,
    title: '노래',
    emoji: '🎤',
    hint: '해당하는 것을 모두 골라주세요. 직접 부르는 것과 곡을 신청하는 것은 다른 항목이에요.',
    featureKeys: ['노래가능', '노래신청'],
    options: [
      PlaceAttributeOption(singingAvailable, emoji: '🎤'),
      PlaceAttributeOption(songRequestAvailable, emoji: '🎵'),
    ],
  );

  // ── 스포츠 중계 ────────────────────────────────────────────────────────
  //
  // 월드컵·축구·야구·올림픽을 **종목별로 나누지 않는다** — 중계는 시즌마다
  // 무엇을 트는지가 바뀌는데 종목을 저장값으로 굳히면 그때마다 값이 늘고,
  // 게스트가 묻는 것은 "여기서 경기를 볼 수 있나" 하나다.
  static const String sportsKey = 'sports';

  /// Firestore `placeAttributes.sports` 배열에 그대로 들어가는 값.
  static const String sportsBroadcast = '스포츠 중계';

  static const sports = PlaceAttributeGroup(
    key: sportsKey,
    title: '스포츠 중계',
    emoji: '📺',
    hint: '주요 경기를 매장에서 볼 수 있으면 골라주세요.',
    featureKeys: ['스포츠중계'],
    options: [PlaceAttributeOption(sportsBroadcast, emoji: '📺')],
  );

  static const String firepitKey = 'firepit';

  static const firepit = PlaceAttributeGroup(
    key: firepitKey,
    title: '불멍',
    emoji: '🔥',
    featureKeys: ['불멍'],
    options: [PlaceAttributeOption('불멍 가능', emoji: '🔥')],
    detailsOn: {'불멍 가능'},
    details: [
      PlaceDetailField(key: 'time', label: '이용시간', hint: '예) 19시~24시'),
      PlaceDetailField(key: 'fee', label: '추가비용 · 안내', hint: '예) 1팀 20,000원'),
    ],
  );

  static const String poolKey = 'pool';

  static const pool = PlaceAttributeGroup(
    key: poolKey,
    title: '수영장',
    emoji: '🏊',
    featureKeys: ['수영장'],
    options: [
      PlaceAttributeOption('실내 수영장', emoji: '🏊'),
      PlaceAttributeOption('야외 수영장', emoji: '🏖'),
    ],
    details: [
      PlaceDetailField(key: 'season', label: '이용 가능 시기', hint: '예) 6~9월'),
      PlaceDetailField(key: 'time', label: '이용 가능 시간', hint: '예) 10시~20시'),
      PlaceDetailField(key: 'fee', label: '추가비용 · 안내'),
    ],
  );

  static const String bbqKey = 'bbq';

  static const bbq = PlaceAttributeGroup(
    key: bbqKey,
    title: 'BBQ',
    emoji: '🍖',
    categories: ['맛집', '술집', '놀거리', '체험·클래스'],
    featureKeys: ['BBQ'],
    options: [
      PlaceAttributeOption('BBQ 가능', emoji: '🍖'),
      PlaceAttributeOption('그릴 제공'),
      PlaceAttributeOption('숯 제공'),
      PlaceAttributeOption('우천 시 가능'),
    ],
    detailsOn: {'BBQ 가능'},
    details: [
      PlaceDetailField(key: 'time', label: '이용시간'),
      PlaceDetailField(key: 'fee', label: '비용 · 안내'),
    ],
  );

  static const String parkingKey = 'parking';

  static const parking = PlaceAttributeGroup(
    key: parkingKey,
    title: '주차',
    emoji: '🚗',
    featureKeys: ['주차', '발렛'],
    options: [
      PlaceAttributeOption('주차 가능', emoji: '🚗'),
      PlaceAttributeOption('발렛 가능', emoji: '🛎'),
      PlaceAttributeOption('무료 주차'),
    ],
  );

  // ── 모임 / 목적 ───────────────────────────────────────────────────────
  //
  // 파티츄가 일반 지도앱과 갈라지는 자리다 — "어디서 뭐 하고 놀지"를 목적으로
  // 바로 묻는다.
  static const String purposesKey = 'purposes';

  static const purposes = PlaceAttributeGroup(
    key: purposesKey,
    title: '이런 모임에 좋아요',
    emoji: '🥂',
    hint: '어떤 자리에 어울리는지 골라주세요.',
    // 목적 세 가지가 그대로 특징이 된다 — 프라이빗·단체석·라이브공연.
    featureKeys: ['프라이빗', '단체석', '라이브'],
    options: [
      PlaceAttributeOption('데이트'),
      PlaceAttributeOption('소개팅'),
      PlaceAttributeOption('생일파티'),
      PlaceAttributeOption('단체모임'),
      PlaceAttributeOption('회식'),
      PlaceAttributeOption('2차'),
      PlaceAttributeOption('춤추기'),
      PlaceAttributeOption('라이브공연'),
      PlaceAttributeOption('조용한 대화'),
      PlaceAttributeOption('프라이빗'),
      PlaceAttributeOption('단체석'),
    ],
  );

  /// 반입 조건 — **외부 음식은 여기 없다.** 기존 `facilityOptions.outsideFood`가
  /// 이미 그 값을 들고 있어서, 같은 것을 두 곳에 저장하면 곧 어긋난다.
  static const String bringInKey = 'bringIn';

  static const bringIn = PlaceAttributeGroup(
    key: bringInKey,
    title: '반입 조건',
    emoji: '🎁',
    featureKeys: ['케이크반입', '배달음식', '주류반입'],
    options: [
      PlaceAttributeOption('케이크 반입 가능', emoji: '🎂'),
      PlaceAttributeOption('배달음식 가능', emoji: '🛵'),
      PlaceAttributeOption('주류 반입 가능', emoji: '🍾'),
    ],
  );

  // ── 생일 혜택 ─────────────────────────────────────────────────────────
  //
  // 기존 '이벤트 진행중' 태그 + `eventSubtype: 생일파티 이벤트`와 **연결**된다.
  // 여기 값이 있으면 [PlaceFeatures]가 생일혜택 특징을 켜 주므로, 호스트가
  // 같은 것을 두 번 고를 필요가 없다.
  static const String birthdayPerksKey = 'birthdayPerks';

  static const birthdayPerks = PlaceAttributeGroup(
    key: birthdayPerksKey,
    title: '생일 혜택',
    // 등록 화면의 이 묶음과 필터의 '생일혜택' 특징([PlaceFeatures.birthday])은
    // 같은 것을 가리키므로 아이콘도 같이 간다.
    emoji: '🎈',
    hint: '생일 손님에게 무엇을 주는지 골라주세요.',
    featureKeys: ['생일혜택'],
    options: [
      PlaceAttributeOption('케이크'),
      PlaceAttributeOption('음료 · 주류 서비스'),
      PlaceAttributeOption('생일상'),
      PlaceAttributeOption('장식'),
      PlaceAttributeOption('할인'),
      PlaceAttributeOption('기타'),
    ],
  );

  /// 저장/복원/화면이 인식하는 전체 그룹. 순서가 곧 등록 화면 순서다.
  static const List<PlaceAttributeGroup> all = [
    // 카테고리 전용이 먼저 — 대분류를 고르면 가장 먼저 물어야 하는 것들.
    musicGenres, dj, clubEntry,
    // 조리 제공은 구워주는 서비스 **바로 다음**이다 — 등록 화면에서 두 질문이
    // 나란히 서야 "누가 굽는가"와 "조리를 아예 안 해도 되는가"가 다른 질문임이
    // 드러난다.
    unlimited, grillService, cookedService, alcoholTypes, corkage, drinks,
    // 하이볼·막걸리 — 마시는 것을 묻는 그룹들 바로 옆.
    servedDrinks,
    // 공통 시설·조건.
    smoking, screen, playItems, singing, sports, firepit, pool, bbq, parking,
    purposes, bringIn, birthdayPerks,
  ];

  static PlaceAttributeGroup? groupOf(String key) {
    for (final g in all) {
      if (g.key == key) return g;
    }
    return null;
  }

  /// 이 대분류에서 **먼저** 물어볼 그룹들 — 등록 화면 위쪽 묶음.
  static List<PlaceAttributeGroup> groupsFor(String? category) =>
      all.where((g) => g.appliesTo(category)).toList();

  /// 다른 길로도 켜지는 특징 — 그 특징 하나 때문에 그룹을 모든 업종으로
  /// 끌고 가지 않는다.
  ///
  ///   · 🪑 테이블 예약 — 클럽의 '입장 정보' 말고 **방문 예약 설정**으로도
  ///     켜지고([PlaceFeatures.of] ⑦-1), 그쪽은 업종을 가리지 않는다.
  ///
  /// 여기 적은 특징이 그 그룹의 유일한 길이 되는 순간 게스트만 검색할 수 있는
  /// 조건이 되므로, 값을 뺄 때는 대체 경로가 살아 있는지 함께 본다
  /// (place_amenity_host_parity_test.dart가 업종별로 확인한다).
  static const Set<String> featuresCoveredElsewhere = {'테이블예약'};

  /// 이 대분류 표에는 없지만 **그래도 물어야 하는** 그룹들 — 등록 화면
  /// '그 밖의 편의·서비스' 묶음.
  ///
  /// 게스트의 편의·서비스 필터는 업종을 가리지 않는다(지도 상세필터·✨
  /// 편의·서비스 시트가 [PlaceFeatures.selectable] 전부를 보여준다). 그래서
  /// 특징을 켜는 그룹([PlaceAttributeGroup.featureKeys])은 업종 표에 없어도
  /// 고를 자리가 있어야 한다 — 없으면 "카페 사장은 🍽️ 조리되어 나와요를 켤
  /// 수 없는데 손님은 그 조건으로 검색하는" 어긋남이 생긴다.
  ///
  /// 특징을 하나도 안 켜는 그룹(음악 장르·주류 종류)은 여기 오지 않는다 —
  /// 그것들은 업종 안에서만 뜻이 있는 값이고, 필터도 같은 규칙으로 보여준다
  /// ([askableFor]를 상세검색 시트가 함께 쓴다).
  static List<PlaceAttributeGroup> extraGroupsFor(String? category) => [
    for (final g in all)
      if (!g.appliesTo(category) &&
          g.featureKeys.any((k) => !featuresCoveredElsewhere.contains(k)))
        g,
  ];

  /// 등록 화면과 상세검색이 **함께 쓰는** 전체 목록 — 업종 표가 앞,
  /// '그 밖의 편의·서비스'가 뒤. 두 화면이 각자 목록을 만들지 않게 하려고
  /// 여기 하나로 둔다.
  static List<PlaceAttributeGroup> askableFor(String? category) => [
    ...groupsFor(category),
    ...extraGroupsFor(category),
  ];

  /// 라벨의 이모지 — 카탈로그에 없는(옛) 라벨은 빈 문자열.
  static String? emojiFor(String label) {
    for (final g in all) {
      for (final o in g.options) {
        if (o.label == label) return o.emoji;
      }
    }
    return null;
  }
}

/// 한 플레이스의 속성 선택 결과. 불변 — 바꿀 때는 새 인스턴스를 돌려준다.
class PlaceAttributes {
  const PlaceAttributes._(this.selections, this.details);

  /// 그룹 키 → 고른 라벨들.
  final Map<String, Set<String>> selections;

  /// 그룹 키 → 상세 입력란 키 → 값(String 또는 bool).
  final Map<String, Map<String, Object>> details;

  factory PlaceAttributes.empty() => const PlaceAttributes._({}, {});

  bool get isEmpty => selections.values.every((s) => s.isEmpty);

  bool get isNotEmpty => !isEmpty;

  Set<String> selected(String groupKey) =>
      selections[groupKey] ?? const <String>{};

  bool isSelected(String groupKey, String label) =>
      selected(groupKey).contains(label);

  /// 단일 선택 그룹의 값 하나 — 없으면 null.
  String? single(String groupKey) {
    final set = selected(groupKey);
    return set.isEmpty ? null : set.first;
  }

  Object? detail(String groupKey, String fieldKey) =>
      details[groupKey]?[fieldKey];

  String detailText(String groupKey, String fieldKey) {
    final v = detail(groupKey, fieldKey);
    return v is String ? v : '';
  }

  bool detailFlag(String groupKey, String fieldKey) =>
      detail(groupKey, fieldKey) == true;

  /// 고른 것이 하나라도 있는 그룹들 — 상세화면이 블록을 그릴지 판단할 때.
  bool hasAnyIn(List<PlaceAttributeGroup> groups) =>
      groups.any((g) => selected(g.key).isNotEmpty);

  PlaceAttributes toggle(String groupKey, String label) {
    final next = _copySelections();
    final set = next.putIfAbsent(groupKey, () => <String>{});
    final nextDetails = _copyDetails();
    if (set.contains(label)) {
      set.remove(label);
    } else {
      if (PlaceAttributeCatalog.groupOf(groupKey)?.singleChoice ?? false) {
        set.clear();
      }
      set.add(label);
    }
    // 상세 입력란이 닫히면 그 값도 함께 버린다 — 화면에서 사라진 값이 문서에만
    // 남아 있으면, 다음에 다시 켰을 때 예전 값이 되살아난다.
    final group = PlaceAttributeCatalog.groupOf(groupKey);
    if (group != null && !group.showsDetails(set)) {
      nextDetails.remove(groupKey);
    }
    return PlaceAttributes._(next, nextDetails);
  }

  /// 상세 입력란 값 지정. 빈 문자열·false는 저장하지 않는다(= 미입력).
  PlaceAttributes withDetail(String groupKey, String fieldKey, Object? value) {
    final next = _copyDetails();
    final group = next.putIfAbsent(groupKey, () => <String, Object>{});
    final empty =
        value == null ||
        value == false ||
        (value is String && value.trim().isEmpty);
    if (empty) {
      group.remove(fieldKey);
      if (group.isEmpty) next.remove(groupKey);
    } else {
      group[fieldKey] = value is String ? value.trim() : value;
    }
    return PlaceAttributes._(_copySelections(), next);
  }

  Map<String, Set<String>> _copySelections() => {
    for (final e in selections.entries) e.key: {...e.value},
  };

  Map<String, Map<String, Object>> _copyDetails() => {
    for (final e in details.entries) e.key: {...e.value},
  };

  int get selectedCount =>
      selections.values.fold(0, (sum, set) => sum + set.length);

  /// 카탈로그 순서대로 고른 라벨을 늘어놓는다 — 카드·상세 요약이 항상 같은
  /// 순서로 읽힌다.
  List<String> summaryLabels({int max = 4}) {
    final result = <String>[];
    for (final group in PlaceAttributeCatalog.all) {
      for (final option in group.options) {
        if (!isSelected(group.key, option.label)) continue;
        // 화면에 적는 글자는 [PlaceAttributeOption.text] — 저장값이 아니다.
        // (콜키지는 저장값 '콜키지 프리'를 '콜키지 무료'로 보여준다.)
        result.add(option.text);
        if (result.length >= max) return result;
      }
    }
    return result;
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    for (final group in PlaceAttributeCatalog.all) {
      final picked = group.options
          .map((o) => o.label)
          .where((label) => isSelected(group.key, label))
          .toList();
      if (picked.isNotEmpty) map[group.key] = picked;
    }
    // 카탈로그에 없는 그룹(앱 버전 차이)도 그대로 돌려준다.
    for (final e in selections.entries) {
      if (PlaceAttributeCatalog.groupOf(e.key) != null) continue;
      if (e.value.isNotEmpty) map[e.key] = e.value.toList();
    }
    return map;
  }

  Map<String, dynamic> detailsToMap() {
    final map = <String, dynamic>{};
    for (final e in details.entries) {
      if (e.value.isEmpty) continue;
      map[e.key] = Map<String, Object>.from(e.value);
    }
    return map;
  }

  static PlaceAttributes fromMap(
    Map<String, dynamic>? map, [
    Map<String, dynamic>? detailMap,
  ]) {
    final selections = <String, Set<String>>{};
    for (final e in (map ?? const {}).entries) {
      final raw = e.value;
      // 옛 문서가 단일 선택을 문자열 하나로 적었을 수도 있다 — 둘 다 읽는다.
      final picked = switch (raw) {
        List() => raw.whereType<String>().toSet(),
        String() when raw.isNotEmpty => {raw},
        _ => <String>{},
      };
      if (picked.isNotEmpty) selections[e.key] = picked;
    }

    final details = <String, Map<String, Object>>{};
    for (final e in (detailMap ?? const {}).entries) {
      final raw = e.value;
      if (raw is! Map) continue;
      final fields = <String, Object>{};
      for (final f in raw.entries) {
        final key = f.key;
        final value = f.value;
        if (key is! String || value == null) continue;
        if (value is String && value.trim().isEmpty) continue;
        if (value is String || value is bool || value is num) {
          fields[key] = value;
        }
      }
      if (fields.isNotEmpty) details[e.key] = fields;
    }

    return PlaceAttributes._(selections, details);
  }

  /// 문서 한 벌에서 바로 읽는다 — 호출부가 필드 이름을 알 필요가 없다.
  static PlaceAttributes fromDoc(Map<String, dynamic> data) {
    final raw = data[PlaceAttributeCatalog.field];
    final rawDetails = data[PlaceAttributeCatalog.detailField];
    return PlaceAttributes.fromMap(
      raw is Map ? Map<String, dynamic>.from(raw) : null,
      rawDetails is Map ? Map<String, dynamic>.from(rawDetails) : null,
    );
  }

  /// 임시저장(Draft)도 같은 형태 — 특수 타입이 없어 그대로 JSON이 된다.
  Map<String, dynamic> toDraftMap() => {
    'selections': toMap(),
    'details': detailsToMap(),
  };

  static PlaceAttributes fromDraftMap(dynamic raw) {
    if (raw is! Map) return PlaceAttributes.empty();
    final selections = raw['selections'];
    final details = raw['details'];
    return PlaceAttributes.fromMap(
      selections is Map ? Map<String, dynamic>.from(selections) : null,
      details is Map ? Map<String, dynamic>.from(details) : null,
    );
  }
}

/// 대분류가 바뀌었을 때, **등록 화면에서 사라진** 그룹의 값을 털어낸다.
///
/// 클럽으로 등록했다가 카페로 바꾸면 음악 장르가 화면에서 사라지는데, 값은
/// 문서에 남아 필터에 계속 걸린다 — 그 어긋남을 등록 화면에서 끊는다.
///
/// ⚠️ 기준은 [PlaceAttributeCatalog.askableFor]다([groupsFor]가 아니다).
/// 편의·서비스를 켜는 그룹은 업종이 바뀌어도 '그 밖의 편의·서비스'로 계속
/// 화면에 있으므로, 호스트가 켜 둔 콜키지·조리 제공을 업종만 바꿨다고
/// 조용히 지우면 안 된다 — 화면에 남아 있는 값을 저장에서 빼는 셈이 된다.
PlaceAttributes pruneAttributesFor(PlaceAttributes attrs, String? category) {
  final askable = {
    for (final g in PlaceAttributeCatalog.askableFor(category)) g.key,
  };
  var next = attrs;
  for (final group in PlaceAttributeCatalog.all) {
    if (askable.contains(group.key)) continue;
    for (final label in attrs.selected(group.key)) {
      next = next.toggle(group.key, label);
    }
  }
  return next;
}

/// 대분류별 상세화면 블록 구성 — 카테고리마다 다른 정보를 보여주기 위한 표.
///
/// 상세화면이 카탈로그 전체를 그대로 늘어놓으면 클럽 페이지에 음식점용 항목이
/// 그대로 나온다. 어떤 대분류에서 무엇을 **먼저** 보여줄지는 여기 하나에만 적고,
/// 화면은 이 순서대로 그린다.
class PlaceDetailBlocks {
  PlaceDetailBlocks._();

  static const Map<String, List<String>> _order = {
    '맛집': [
      PlaceAttributeCatalog.unlimitedKey,
      // 고깃집에서 "누가 굽나"는 콜키지보다 먼저 읽혀야 한다.
      PlaceAttributeCatalog.grillKey,
      // 조리 제공은 구워주는 서비스 바로 옆에서 읽혀야 한다(다른 질문이다).
      PlaceAttributeCatalog.cookedKey,
      PlaceAttributeCatalog.corkageKey,
      'alcoholTypes',
      PlaceAttributeCatalog.bbqKey,
      PlaceAttributeCatalog.purposesKey,
      PlaceAttributeCatalog.smokingKey,
    ],
    // 다이닝 — "무엇을 마시며 먹느냐"가 먼저다. 코스와 함께 여는 술이
    // 이 업종의 첫 질문이라 주류 종류·콜키지가 맨 위로 온다.
    '다이닝·파인다이닝': [
      'alcoholTypes',
      PlaceAttributeCatalog.corkageKey,
      PlaceAttributeCatalog.cookedKey,
      PlaceAttributeCatalog.purposesKey,
      PlaceAttributeCatalog.unlimitedKey,
      PlaceAttributeCatalog.smokingKey,
    ],
    '카페·디저트': [
      PlaceAttributeCatalog.unlimitedKey,
      PlaceAttributeCatalog.purposesKey,
      PlaceAttributeCatalog.playItemsKey,
      PlaceAttributeCatalog.smokingKey,
    ],
    '술집': [
      'alcoholTypes',
      PlaceAttributeCatalog.unlimitedKey,
      PlaceAttributeCatalog.grillKey,
      // 조리 제공은 구워주는 서비스 바로 옆에서 읽혀야 한다(다른 질문이다).
      PlaceAttributeCatalog.cookedKey,
      PlaceAttributeCatalog.corkageKey,
      PlaceAttributeCatalog.playItemsKey,
      PlaceAttributeCatalog.purposesKey,
      PlaceAttributeCatalog.smokingKey,
    ],
    'BAR': [
      'alcoholTypes',
      PlaceAttributeCatalog.corkageKey,
      'dj',
      PlaceAttributeCatalog.purposesKey,
      PlaceAttributeCatalog.smokingKey,
    ],
    // 혼술바는 "혼자 앉아 뭘 마실 수 있나"가 먼저다 — 주류 종류가 맨 위로 온다.
    '혼술바': [
      'alcoholTypes',
      PlaceAttributeCatalog.corkageKey,
      PlaceAttributeCatalog.unlimitedKey,
      PlaceAttributeCatalog.purposesKey,
      PlaceAttributeCatalog.smokingKey,
    ],
    '클럽': [
      'musicGenres',
      'dj',
      'clubEntry',
      PlaceAttributeCatalog.smokingKey,
      PlaceAttributeCatalog.unlimitedKey,
    ],
    '라이브·공연': [
      'musicGenres',
      'dj',
      'alcoholTypes',
      PlaceAttributeCatalog.purposesKey,
      PlaceAttributeCatalog.smokingKey,
    ],
    '놀거리': [
      PlaceAttributeCatalog.playItemsKey,
      // 노래방 시간·놀거리 이용 무제한이 여기서 나온다.
      PlaceAttributeCatalog.unlimitedKey,
      PlaceAttributeCatalog.screenKey,
      PlaceAttributeCatalog.purposesKey,
      PlaceAttributeCatalog.smokingKey,
    ],
    '체험·클래스': [
      PlaceAttributeCatalog.purposesKey,
      PlaceAttributeCatalog.bbqKey,
      PlaceAttributeCatalog.grillKey,
      // 조리 제공은 구워주는 서비스 바로 옆에서 읽혀야 한다(다른 질문이다).
      PlaceAttributeCatalog.cookedKey,
      PlaceAttributeCatalog.unlimitedKey,
      PlaceAttributeCatalog.smokingKey,
    ],
  };

  /// 대분류에서 먼저 보여줄 그룹들 → 그 뒤에 나머지 그룹.
  /// 대분류를 모르는(옛) 문서도 값이 있는 그룹은 전부 보인다.
  static List<PlaceAttributeGroup> orderedFor(String? category) {
    final head = <PlaceAttributeGroup>[];
    for (final key in _order[category] ?? const <String>[]) {
      final g = PlaceAttributeCatalog.groupOf(key);
      if (g != null) head.add(g);
    }
    final rest = PlaceAttributeCatalog.all
        .where((g) => !head.contains(g))
        .toList();
    return [...head, ...rest];
  }

  /// 카테고리 표에 실린 대분류인지 — 표에 없으면 카탈로그 순서를 그대로 쓴다.
  static bool covers(String? category) =>
      category != null && _order.containsKey(category);

  /// 표가 [PlaceTaxonomy]의 대분류를 모두 덮는지 — self-check가 확인한다.
  static bool get coversAllCategories =>
      PlaceTaxonomy.all.every((c) => _order.containsKey(c.label));
}
