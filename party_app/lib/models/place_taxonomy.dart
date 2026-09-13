/// 플레이스 **대분류/소분류**의 정본.
///
/// ── 왜 업종(businessTypes)과 따로 만드는가 ────────────────────────────────
/// 기존 `businessTypes`(술집·바·카페·라운지·포차·클럽·기타)는 "무슨 가게인가"를
/// 7개로만 나눈 값이라, "오늘 어디서 뭐 하고 놀지"를 묻는 탐색에는 층이 모자란다
/// (힙합클럽을 찾는 사람이 '클럽'까지밖에 못 간다). 그래서 대분류 9개 + 소분류로
/// 다시 나눈다.
///
/// **기존 필드를 지우지 않는다.** `businessTypes`는 그대로 두고, 새 문서는
/// [PlaceTaxonomy.categoryField]에 대분류를 적는다. 새 필드가 없는 문서는
/// [categoryOf]가 `businessTypes`에서 대분류를 **유추**하므로, 옛 플레이스도
/// 새 카테고리 바에서 제자리에 나타난다.
///
/// ── 저장값은 한국어 라벨 그대로 ───────────────────────────────────────────
/// `themeTags`·`facilityOptions`와 같은 관례다 — 콘솔에서 바로 읽히고
/// `array-contains`에도 그대로 쓸 수 있다. 그래서 **한 번 배포된 라벨은 바꾸지
/// 않는다**(바꾸면 이미 등록된 문서가 필터에서 사라진다).
///
/// 부르는 이름을 바꾸고 싶을 때는 라벨이 아니라 [PlaceCategory.name]을 준다
/// ('맛집' → 화면에서는 '푸드'). 저장값·필터 매칭은 그대로고 표기만 바뀐다.
///
/// ⚠️ 공간대여(places 컬렉션)·숙박은 여기 들어오지 않는다. 별도 카테고리로
///    이미 존재하고 파는 것이 다르다(빌리는 것 vs 찾아가는 것).
library;

/// 대분류 하나.
class PlaceCategory {
  const PlaceCategory({
    required this.label,
    required this.emoji,
    required this.subcategories,
    this.retiredSubcategories = const [],
    this.name,
    this.short,
    this.aliases = const [],
    this.retired = false,
  });

  /// **저장값**. Firestore `placeCategory`에 그대로 들어간다 — 배포 후 변경
  /// 금지(바꾸면 이미 등록된 문서가 필터에서 사라진다).
  final String label;

  /// **화면에 부르는 이름**. 저장값과 보이는 이름을 갈라 두는 자리다 —
  /// '맛집'을 '푸드'로 바꾸는 것처럼 부르는 말만 바꿀 때 이미 저장된 문서를
  /// 건드리지 않기 위함이다(`themeTags`의 [ListingConstants.placeThemeTagLabel]
  /// 과 같은 관례). 따로 정하지 않으면 [label] 그대로.
  final String? name;

  /// 이 대분류로 **함께 읽는** 다른 이름 — 화면 이름('푸드')이나 옛 이름이
  /// 값으로 들어와도 [byLabel]이 같은 대분류로 되돌린다. 저장된 조건이나
  /// 딥링크가 화면 이름을 들고 있어도 대분류가 통째로 풀려버리지 않게 한다.
  final List<String> aliases;

  /// 카테고리 바처럼 **칸이 좁은 자리**에만 쓰는 짧은 표기.
  ///
  /// 1단 바는 열 칸이 화면 폭을 나눠 갖는다(360px에서 칸당 약 65px).
  /// '카페·디저트'·'라이브·공연'을 그대로 넣으면 글자가 뭉개져 무슨
  /// 카테고리인지 읽히지 않는다. **저장값은 언제나 [label]**이고 이건
  /// 표기일 뿐이라, 짧게 줄여도 필터 매칭에는 아무 영향이 없다.
  final String? short;

  /// 화면에 쓰는 이름 — 따로 정하지 않았으면 저장값 그대로.
  String get displayName => name ?? label;

  /// 좁은 자리에 쓸 표기 — 따로 정하지 않았으면 [displayName] 그대로.
  String get shortLabel => short ?? displayName;

  final String emoji;

  /// 소분류 저장값들. 순서가 곧 화면 순서다.
  final List<String> subcategories;

  /// **새로 고를 수는 없지만 읽기는 계속 되는** 소분류
  /// ([ListingConstants.retiredPlaceThemeTags]와 같은 관례).
  ///
  /// 이미 이 값으로 등록된 문서가 있으므로 지우지 않는다 — 카드·상세에는
  /// 그대로 보이고, [hasSubcategory]도 이 값을 이 대분류의 것으로 인정한다
  /// (그래야 대분류를 껐을 때 옛 소분류가 남지 않는다).
  final List<String> retiredSubcategories;

  /// **새로 고를 수는 없지만 읽기는 계속 되는** 대분류.
  ///
  /// [retiredSubcategories]를 소분류에서 하던 일을 대분류에서 하는 축이다.
  /// 등록·수정 화면의 칩 목록에서만 빠지고([PlaceTaxonomy.selectable]),
  /// 그 밖의 모든 것은 그대로다:
  ///   · 지도·검색의 카테고리 바에 계속 나온다([all]) — 빼면 이 대분류로
  ///     등록된 가게에 **닿을 길이 사라진다**.
  ///   · [categoryOf]·[matchesCategory]·[byLabel]이 전부 그대로 인정한다.
  ///   · 상세·카드·추천이 읽는 표(업종별 특징·상세 블록)도 그대로 둔다.
  ///
  /// ⚠️ 저장값은 **절대 건드리지 않는다.** 이미 이 대분류로 등록된 문서를
  ///    일괄 수정하거나 지우지 않는다 — 되돌릴 수 없고, 호스트가 직접 고른
  ///    값을 서버가 말없이 바꾸는 일이기 때문이다.
  final bool retired;

  /// 이 대분류의 소분류 전부 — 고를 수 있는 것 + 은퇴한 것.
  List<String> get allSubcategories => [
    ...subcategories,
    ...retiredSubcategories,
  ];

  /// '🔥 클럽' — 칩·제목에 쓰는 표기.
  String get display => '$emoji $displayName';
}

class PlaceTaxonomy {
  PlaceTaxonomy._();

  /// Firestore 필드 이름 — 대분류(문자열 하나).
  static const String categoryField = 'placeCategory';

  /// Firestore 필드 이름 — 소분류(문자열 배열).
  static const String subcategoryField = 'placeSubcategories';

  // ── 대분류 ────────────────────────────────────────────────────────────
  //
  // 클럽은 술집·BAR 아래로 숨기지 않고 **독립 대분류**로 둔다. 힙합클럽을
  // 찾는 사람이 '클럽 → 힙합클럽' 두 번으로 닿아야 하기 때문이다.

  // '맛집'은 **저장값**이고 화면에서는 '푸드'로 부른다. 라벨 자체를 바꾸면
  // 이미 `placeCategory: '맛집'`으로 등록된 문서가 전부 이 대분류에서
  // 사라지므로, 부르는 이름만 [name]으로 갈라 둔다(되돌리기도 한 줄이다).
  static const restaurant = PlaceCategory(
    label: '맛집',
    name: '푸드',
    aliases: ['푸드', '음식'],
    emoji: '🍽',
    // ⚠️ 이 **순서가 정본**이다. 업종 시트([PlaceQuickPicks.foodKinds])·등록
    //    화면([PlaceCategorySection])·상세검색 시트가 전부 이 목록을 그대로
    //    훑어 그리므로, 여기 순서를 고치면 세 화면이 함께 따라온다. 화면마다
    //    따로 늘어놓으면 같은 업종이 자리마다 다른 칸에 있게 된다.
    //
    //    "무엇을 먹느냐"가 앞이다 — 고기·해산물이 먼저 오고, 나라별 갈래
    //    (한식·중식·일식·양식)가 그 뒤, 글로벌 푸드와 기타가 마지막이다.
    //    나라별 옛 소분류 여섯은 글로벌 푸드 바로 뒤에 붙여 둔다 — 시트에서는
    //    글로벌푸드 한 칸으로 묶여 안 보이지만([legacyGlobalFoodSubcategories]),
    //    등록·상세검색에는 그대로 나오므로 부모 옆자리가 맞다.
    subcategories: [
      '고기·BBQ',
      '해산물',
      '한식',
      '중식',
      '일식',
      '양식',
      '글로벌 푸드',
      '멕시칸',
      '인도',
      '태국',
      '베트남',
      '중동',
      '지중해',
      '기타',
    ],
  );

  /// 다이닝·파인다이닝 — 신규 대분류(2026-08-30).
  ///
  /// ── 왜 '맛집'의 소분류가 아니라 대분류인가 ────────────────────────────
  /// 파인다이닝을 찾는 사람은 **무엇을 먹느냐보다 어떤 자리냐**를 먼저 고른다.
  /// 그 축은 한식·일식과 같은 층이 아니라 그 위층이다.
  ///
  /// ── 두 대분류는 묻는 축이 다르다 ──────────────────────────────────────
  ///   푸드      → **무엇을 먹나** (한식 / 중식 / 일식 / 양식 …)
  ///   다이닝    → **어떤 자리인가** (다이닝 / 파인다이닝)
  ///
  /// 한때 이 대분류의 소분류로 음식 종류를 그대로 썼다. '다이닝 → 일식'으로
  /// 등록하면 두 축을 한 번에 말할 수 있다는 계산이었는데, 정작 화면에서는
  /// 같은 층에 음식 종류가 두 번 나와 **무엇을 고르는 자리인지**가 흐려졌다.
  /// 음식 종류는 푸드에서 찾는 개념으로 되돌리고, 여기서는 자리의 격만 묻는다.
  ///
  /// ⚠️ 그래서 음식 종류 값은 [retiredSubcategories]로 내려갔다 — **지우지
  ///    않았다.** 새로 고를 수만 없고, 이미 그 값으로 저장된 문서는 카드·상세에
  ///    그대로 보이고 소분류 필터에도 그대로 걸린다. 특히 [hasSubcategory]가
  ///    계속 참이라, '다이닝 + 일식'으로 저장해 둔 필터 조건이 대분류를 켤 때
  ///    조용히 풀리지 않는다([EventFilter]가 그 규칙으로 소분류를 털어낸다).
  ///
  /// ── 저장값 ────────────────────────────────────────────────────────────
  /// '다이닝'·'파인다이닝'은 `placeSubcategories` 배열에 **그냥 문자열로**
  /// 들어간다 — 다른 소분류와 똑같고, 구조를 바꾼 것이 하나도 없다.
  ///
  /// '전체'는 값이 아니다. 이 대분류만 켜고 소분류를 하나도 안 고른 상태가
  /// 곧 전체이고, 화면의 '전체' 칩은 그 상태를 만드는 버튼일 뿐이다
  /// ([PlaceCategoryExplorer]의 드릴 층). 값으로 만들면 "전체로 저장된 가게"가
  /// 생겨 아무 뜻도 없는 소분류가 하나 늘어난다.
  static const dining = PlaceCategory(
    label: '다이닝·파인다이닝',
    short: '다이닝',
    aliases: ['다이닝', '파인다이닝'],
    emoji: '🥂',
    subcategories: ['다이닝', '파인다이닝'],
    // 음식 종류는 이제 푸드([restaurant])가 맡는다. 여기 남은 것은 순전히
    // 하위호환이다 — 값이 같으므로 '일식'으로 좁힌 게스트에게 이 문서도
    // 예전 그대로 걸린다([matchesAnySubcategory]는 대분류를 보지 않는다).
    retiredSubcategories: [
      '한식',
      '중식',
      '일식',
      '양식',
      '고기·BBQ',
      '해산물',
      '글로벌 푸드',
      '기타',
    ],
  );

  static const cafe = PlaceCategory(
    label: '카페·디저트',
    short: '카페',
    emoji: '☕',
    subcategories: ['카페', '베이커리', '디저트', '브런치', '티·전통차', '이색카페'],
  );

  /// 술집 — 기존 소분류는 **그대로 두고**, 뒤에 바(bar) 갈래를 이어 붙였다.
  ///
  /// BAR가 등록 화면에서 내려가면서([bar]) '와인바·위스키바·칵테일바…'를 새로
  /// 고를 길이 없어진다. 그 값들을 여기로 옮겨 받지 않으면 와인바 사장님이
  /// 자기 가게를 표현할 칸이 사라진다("술집"까지밖에 못 간다).
  ///
  /// ⚠️ **저장값을 그대로 재사용한다** — 새 이름을 짓지 않는다. 그래서 이미
  ///    `placeSubcategories: ['와인바']`로 등록된 BAR 문서가 소분류 필터에서
  ///    새로 등록된 술집 와인바와 **같이** 걸린다([matchesAnySubcategory]는
  ///    대분류를 보지 않고 소분류 값만 본다). 값을 새로 지었다면 옛 문서와
  ///    새 문서가 영영 다른 칸으로 갈라졌을 것이다.
  ///
  /// 앞쪽 여섯(포차·호프·펍…)이 기존 순서 그대로인 것도 의도다 — 이미 이
  /// 순서로 고르던 화면들이 그대로 따라온다.
  static const pub = PlaceCategory(
    label: '술집',
    emoji: '🍻',
    subcategories: [
      '포차',
      '호프·펍',
      '이자카야',
      '요리주점',
      '전통주',
      '실내포차',
      '와인바',
      '위스키바',
      '칵테일바',
      '하이볼바',
      '루프탑바',
      '라운지바',
    ],
  );

  /// BAR — **등록에서 은퇴**했다(2026-08-30). 읽기는 전부 그대로다.
  ///
  /// 술집 아래에 이미 '호프·펍'이 있고 혼술바까지 따로 있어, 대분류 BAR는
  /// 세 칸이 같은 것을 가리키는 상태였다. 그래서 등록 화면의 칩만 내리고
  /// ([PlaceTaxonomy.selectable]) 소분류는 [pub]이 그대로 이어받았다.
  ///
  /// ⚠️ 지도·검색의 카테고리 바에는 **계속 나온다**([all]). 여기서 빼면
  ///    `placeCategory: 'BAR'`로 등록된 가게와 옛 `businessTypes: ['바']`에서
  ///    BAR로 유추되는 가게에 닿을 길이 통째로 사라진다
  ///    ([_legacyBusinessTypeToCategory]의 '바'·'라운지'가 여기로 온다).
  ///    소분류도 그대로 남긴다 — 이미 저장된 '와인바'를 이 대분류의 것으로
  ///    계속 인정해야 [hasSubcategory]가 맞다.
  static const bar = PlaceCategory(
    label: 'BAR',
    emoji: '🍸',
    retired: true,
    subcategories: ['와인바', '위스키바', '칵테일바', '하이볼바', '루프탑바', '라운지바'],
  );

  /// 혼술바는 BAR의 소분류가 아니라 **독립 대분류**다 — "혼자 마시러 갈 곳"은
  /// 업종이 아니라 목적이라, BAR 안에 묻어 두면 두 번 들어가야 닿는다.
  ///
  /// ⚠️ 이 이름은 예전부터 특징 태그(`themeTags`의 '혼술바')로도 쓰였다. 이미
  ///    그 태그를 단 플레이스가 있으므로, 대분류로 올리면서도 **태그 쪽을
  ///    지우지 않는다** — [_matchesLegacyCategory]가 그 문서까지 이 대분류로
  ///    함께 걸어 준다(저장값을 건드리지 않는 하위호환).
  ///
  /// 소분류는 새로 만들지 않고 BAR·술집에서 쓰던 저장값을 그대로 쓴다.
  static const soloBar = PlaceCategory(
    label: '혼술바',
    emoji: '🍷',
    subcategories: ['와인바', '위스키바', '하이볼바', '칵테일바', '전통주', '기타'],
  );

  /// 클럽의 하위 탐색은 **소분류가 아니라 음악 장르**로 한다.
  ///
  /// '힙합클럽'(소분류)과 'HIPHOP'(`placeAttributes.musicGenres`)은 같은 말을
  /// 두 곳에 저장하는 구조였다 — 한쪽만 고른 가게가 다른 쪽 화면에서 빠지고,
  /// 둘이 어긋나면 어느 쪽이 정본인지 알 수 없다. 그래서 **장르 하나를 정본**
  /// 으로 두고([PlaceAttributeCatalog.musicGenres]), 소분류 쪽은 새로 고를 수
  /// 없게 비웠다.
  ///
  /// ⚠️ 이미 저장된 소분류는 **지우지 않는다** — [retiredSubcategories]에
  /// 남겨 카드·상세에 그대로 보이고, [legacyClubGenresOf]가 그 값을 장르로
  /// 읽어 새 장르 필터에도 함께 걸리게 한다.
  /// 저장값은 '클럽' 그대로, 화면에서만 **'클럽·댄스'**로 부른다(2026-08-30).
  ///
  /// 클럽 하나로는 나이트·별밤·댄스펍 사장님이 이 칸을 자기 것으로 읽지
  /// 않았다. 그렇다고 라벨을 '클럽·댄스'로 바꾸면 이미
  /// `placeCategory: '클럽'`으로 등록된 문서가 전부 이 대분류에서 사라진다.
  /// 그래서 [restaurant]('맛집' → '푸드')과 **똑같은 방법**을 쓴다 —
  /// 저장값·필터 매칭은 손대지 않고 [name]만 준다. 마이그레이션이 없다.
  ///
  /// [aliases]는 되돌리는 다리다 — 새 이름이 필터 값이나 딥링크로 들어와도
  /// [byLabel]이 이 대분류로 풀어 준다.
  ///
  /// ── 소분류는 '장르'가 아니라 '업장 형태'만 받는다 ──────────────────────
  /// 장르(HIPHOP·EDM…)의 정본은 여전히 `placeAttributes.musicGenres` 하나다
  /// ([PlaceAttributeCatalog.musicGenres]). 여기 되살린 넷은 **장르로는 표현할
  /// 수 없는 업장 형태**라 그 축과 겹치지 않는다 — '나이트'는 음악이 아니라
  /// 영업 형태고, '별밤·7080'은 세대/편성이다. 그래서 '힙합클럽'과 'HIPHOP'이
  /// 같은 말을 두 곳에 저장하던 옛 문제가 다시 생기지 않는다.
  ///
  /// '라운지클럽'·'댄스클럽'은 **새 값이 아니다** — 은퇴 목록에 있던 저장값을
  /// 다시 고를 수 있게 되돌린 것뿐이다(이미 그 값으로 등록된 문서가 있다).
  /// 새로 만든 값은 '나이트'와 '별밤·7080' 둘뿐이다.
  ///
  /// DJ클럽은 값을 만들지 않는다 — 🎧 DJ 특징([PlaceAttributeCatalog.dj])이
  /// 이미 그 축을 들고 있어, 값을 또 만들면 한쪽만 고른 가게가 갈라진다.
  static const club = PlaceCategory(
    label: '클럽',
    name: '클럽·댄스',
    short: '클럽',
    aliases: ['클럽·댄스', '댄스'],
    emoji: '🔥',
    subcategories: ['나이트', '별밤·7080', '라운지클럽', '댄스클럽'],
    // 장르로 읽어낼 수 있는 값들만 은퇴로 남는다([_legacyClubSubcategoryToGenre]).
    // '기타'는 장르로도 형태로도 옮길 수 없어 그대로 은퇴다.
    retiredSubcategories: ['힙합클럽', 'EDM클럽', '테크노', '기타'],
  );

  /// 옛 클럽 소분류 → 음악 장르 저장값. 이 표가 다리다 — '힙합클럽'으로
  /// 등록된 가게가 새 '힙합' 장르 칩에서 빠지지 않는다.
  ///
  /// 장르로 옮길 수 없는 값('라운지클럽'·'댄스클럽'·'기타')은 넣지 않는다 —
  /// 억지로 대응시키면 없던 뜻이 생긴다.
  static const Map<String, String> _legacyClubSubcategoryToGenre = {
    '힙합클럽': 'HIPHOP',
    'EDM클럽': 'EDM',
    '테크노': 'Techno',
  };

  /// 이 문서의 옛 클럽 소분류에서 읽어낼 수 있는 음악 장르들.
  /// 필터가 `musicGenres`를 볼 때 여기에 나온 값을 **함께** 친다.
  static Set<String> legacyClubGenresOf(Map<String, dynamic> data) {
    final subs = subcategoriesOf(data);
    if (subs.isEmpty) return const {};
    return {
      for (final s in subs)
        if (_legacyClubSubcategoryToGenre[s] != null)
          _legacyClubSubcategoryToGenre[s]!,
    };
  }

  /// 라이브·공연 — **등록에서 은퇴**했다(2026-08-30). 읽기는 전부 그대로다.
  ///
  /// 라이브는 "무슨 가게인가"가 아니라 **그 가게가 무엇을 제공하는가**다.
  /// 같은 재즈바가 술집이기도 하고 카페이기도 한데 대분류를 하나만 고를 수
  /// 있으니, 라이브를 고르는 순간 업종을 말할 자리를 잃었다. 그래서 이 축은
  /// 속성으로 옮겼다 — 이미 있던 [PlaceAttributeCatalog.purposes]의
  /// '라이브공연'이 그 자리고, 그 값이 🎤 라이브 특징을 켠다
  /// ([PlaceFeatures.of] ③). 새 분류 체계를 만들지 않았다.
  ///
  /// ⚠️ 기존 문서는 **아무것도 잃지 않는다.**
  ///    · 지도·검색 카테고리 바에 계속 나온다([all]).
  ///    · `placeCategory: '라이브·공연'` 문서는 🎤 라이브 특징이 여전히
  ///      **자동으로** 켜진다([PlaceFeatures.of] ⑤의 대분류 유도) — 호스트가
  ///      속성을 다시 고르지 않아도 라이브 필터에 그대로 걸린다.
  ///    · 소분류('라이브펍'·'재즈바'…)도 그대로 남겨 카드·상세에 보인다.
  static const live = PlaceCategory(
    label: '라이브·공연',
    short: '라이브',
    emoji: '🎤',
    retired: true,
    subcategories: ['라이브펍', '재즈바', '라이브카페', '인디공연', 'DJ 공연', '공연장'],
  );

  static const play = PlaceCategory(
    label: '놀거리',
    emoji: '🎮',
    subcategories: [
      '보드게임',
      '방탈출',
      '노래방',
      '다트',
      '당구',
      '볼링',
      '오락실',
      '콘솔게임',
      '기타',
    ],
  );

  // 저장값은 '체험·클래스' 그대로 두고 **부르는 이름만** '체험/클래스'다.
  // 예전에는 좁은 카테고리 바에서 '체험'으로만 줄여 불러, 원데이클래스를
  // 찾는 사람에게는 이 칸이 자기 것으로 읽히지 않았다.
  //
  // 'short'는 두지 않는다 — 바의 글자는 [PlaceCategoryGrid]가 FittedBox로
  // 줄여 그리므로 긴 이름도 칸 안에 들어간다. 짧은 표기를 따로 두면 바에서만
  // 다시 '체험'으로 갈라진다.
  //
  // 'aliases'의 '체험'은 되돌리는 다리다 — 예전 표기가 필터 값·딥링크로
  // 들어와도 [byLabel]이 이 대분류로 풀어 준다.
  static const experience = PlaceCategory(
    label: '체험·클래스',
    name: '체험/클래스',
    aliases: ['체험'],
    emoji: '🎨',
    subcategories: ['공방', '원데이클래스', '쿠킹', '드로잉', '향수·캔들', '액티비티', '기타'],
  );

  /// **읽기의 전체 목록** — 지도·검색의 카테고리 바가 이 순서를 쓴다.
  /// 푸드 · 다이닝 · 카페 · 술집 · 혼술바 · BAR · 클럽·댄스 · 라이브 · 놀거리 · 체험.
  ///
  /// 은퇴한 대분류(BAR·라이브)도 **여기 그대로 있다** — 빼면 그 값으로 등록된
  /// 가게에 닿을 길이 사라진다. 등록 화면만 [selectable]을 쓴다.
  ///
  /// 다이닝이 푸드 **바로 뒤**인 것은 순서 이상의 뜻이 있다:
  /// [categoryOfSubcategory]는 먼저 찾은 대분류를 돌려주므로, 음식 종류
  /// 소분류('일식')는 앞에 있는 [restaurant]로 풀린다. 다이닝은 그 값들을
  /// 하위호환으로만 들고 있으므로([dining]의 retiredSubcategories) 해석의
  /// 정본은 언제나 푸드여야 한다.
  ///
  /// 혼술바가 BAR보다 앞이다 — '혼자 마시러 갈 곳'을 찾는 사람이 더 많고,
  /// BAR 뒤에 두면 둘이 같은 것으로 읽혀 지나친다.
  static const List<PlaceCategory> all = [
    restaurant,
    dining,
    cafe,
    pub,
    soloBar,
    bar,
    club,
    live,
    play,
    experience,
  ];

  /// **지금 살아 있는** 대분류 — 등록 화면의 칩과 홈/지도의 카테고리 바가
  /// 함께 쓴다.
  ///
  /// [all]과 갈라 두는 이유는 하나다 — 새로 고르게 하고 싶지 않은 대분류와,
  /// 이미 그 값으로 등록된 가게를 찾을 수 없게 만드는 것은 전혀 다른 일이다.
  /// 앞은 이 목록이 맡고, 뒤는 [_retiredCategoryHome] 다리가 맡는다.
  ///
  /// ⚠️ 카테고리 바가 [all]이 아니라 이 목록을 쓰는 데는 **자리 제약**도 있다.
  ///    바는 한 줄 6칸이고 '전체'·'🎪 이벤트'·'파티샵'이 세 칸을 이미 쓴다 —
  ///    대분류가 아홉을 넘으면 세 줄이 되어 머리가 화면의 1/3을 먹고 카드가
  ///    한 장도 온전히 안 보인다(place_filter_bars_height_test가 못 박는다).
  static List<PlaceCategory> get selectable =>
      all.where((c) => !c.retired).toList();

  /// 저장값으로 대분류를 찾는다. 화면 이름('음식')이나 [PlaceCategory.aliases]
  /// 로 들어온 값도 같은 대분류로 풀어 준다 — 어딘가에 화면 이름이 저장돼
  /// 있어도 조건이 조용히 사라지지 않게 하기 위함이다.
  static PlaceCategory? byLabel(String? label) {
    if (label == null || label.isEmpty) return null;
    for (final c in all) {
      if (c.label == label) return c;
    }
    for (final c in all) {
      if (c.name == label || c.aliases.contains(label)) return c;
    }
    return null;
  }

  /// 들어온 이름을 **저장값**으로 되돌린다 — 화면 이름이 필터 값으로 새어
  /// 들어왔을 때 한 자리에서 바로잡는다. 모르는 값은 그대로 돌려준다.
  static String canonical(String label) => byLabel(label)?.label ?? label;

  static String emojiOf(String? label) => byLabel(label)?.emoji ?? '📍';

  /// '🔥 클럽' — 라벨만 아는 자리에서 쓰는 표기.
  static String displayOf(String label) {
    final c = byLabel(label);
    return c == null ? label : c.display;
  }

  /// '푸드' — 저장값만 아는 자리에서 쓰는 화면 이름(이모지 없이).
  static String nameOf(String label) => byLabel(label)?.displayName ?? label;

  // ── 기존 데이터 잇기 ──────────────────────────────────────────────────
  //
  // 옛 문서에는 대분류가 없다. 대신 `businessTypes`(다중) 또는 옛 단일
  // `businessType`이 있으므로, 거기서 대분류를 유추한다 — 이 표가 없으면
  // 옛 플레이스가 새 카테고리 바에서 전부 사라진다(하위호환의 핵심).
  //
  // 유추는 **읽을 때만** 한다. 문서를 건드려 값을 채워 넣지 않는다 —
  // 마이그레이션 배치는 되돌릴 수 없고, 호스트가 직접 고른 값과 유추한 값이
  // 섞이면 어느 쪽이 정본인지 알 수 없게 된다.
  static const Map<String, String> _legacyBusinessTypeToCategory = {
    '클럽': '클럽',
    '바': 'BAR',
    '라운지': 'BAR',
    '술집': '술집',
    '포차': '술집',
    '카페': '카페·디저트',
    // '기타'는 유추하지 않는다 — 어느 대분류인지 알 수 없다.
  };

  /// 옛 업종에서 유추할 수 있는 소분류. 대분류만으로는 정보가 줄어드는 값
  /// ('포차' → 술집 아래 '포차')을 살려 둔다.
  static const Map<String, String> _legacyBusinessTypeToSubcategory = {
    '포차': '포차',
    '라운지': '라운지바',
    '카페': '카페',
  };

  /// 유추 우선순위 — 한 문서에 업종이 여럿일 때 무엇을 대표로 볼지.
  /// 좁은 쪽(클럽)이 넓은 쪽(술집)보다 먼저다.
  static const List<String> _legacyPriority = [
    '클럽',
    '바',
    '라운지',
    '포차',
    '술집',
    '카페',
  ];

  /// 문서의 업종 목록 — 다중 `businessTypes`가 정본이고, 단일 `businessType`은
  /// 하나짜리 목록으로 읽는다(등록 화면·필터와 같은 규칙).
  static List<String> businessTypesOf(Map<String, dynamic> data) {
    final list = (data['businessTypes'] as List?)?.whereType<String>().toList();
    if (list != null && list.isNotEmpty) return list;
    final single = data['businessType'] as String?;
    return single != null && single.isNotEmpty ? [single] : const [];
  }

  /// 이 문서의 대분류. 고르지도 유추하지도 못하면 null(= 미분류).
  ///
  /// 미분류 문서는 '전체'에서는 그대로 보이고, 특정 대분류를 켰을 때만 빠진다.
  static String? categoryOf(Map<String, dynamic> data) {
    final explicit = data[categoryField];
    if (explicit is String && byLabel(explicit) != null) return explicit;

    final types = businessTypesOf(data).toSet();
    for (final key in _legacyPriority) {
      if (types.contains(key)) return _legacyBusinessTypeToCategory[key];
    }
    return null;
  }

  /// 이 문서의 소분류들. 새 필드가 없으면 옛 업종에서 유추한다.
  static List<String> subcategoriesOf(Map<String, dynamic> data) {
    final list = (data[subcategoryField] as List?)
        ?.whereType<String>()
        .toList();
    if (list != null && list.isNotEmpty) return list;

    final types = businessTypesOf(data);
    final derived = <String>[];
    for (final t in types) {
      final sub = _legacyBusinessTypeToSubcategory[t];
      if (sub != null && !derived.contains(sub)) derived.add(sub);
    }
    return derived;
  }

  /// 문서의 특징 태그 — 새 데이터는 `themeTags`, 옛 문서는 단일 `category`.
  /// ([PlaceFeatures]·main_screen의 `_placeThemeTags`와 같은 규칙이다.)
  static List<String> _themeTags(Map<String, dynamic> data) {
    final tags = (data['themeTags'] as List?)?.whereType<String>().toList();
    if (tags != null && tags.isNotEmpty) return tags;
    final legacy = data['category'] as String?;
    return legacy != null && legacy.isNotEmpty ? [legacy] : const [];
  }

  // ── 은퇴한 대분류를 잇는 다리 ─────────────────────────────────────────
  //
  // BAR·라이브가 카테고리 바에서 내려가면 그 값으로 등록된 가게는 '전체'
  // 말고는 닿을 길이 없어진다. 저장값을 고치는 것은 답이 아니다 — 되돌릴 수
  // 없고 호스트가 고른 값을 말없이 바꾸는 일이다. 대신 **읽을 때** 살아 있는
  // 대분류 아래에서 함께 걸리게 한다.

  /// 은퇴한 대분류 → 그 가게들이 대신 걸릴 살아 있는 대분류.
  ///
  /// BAR → 술집은 뜻이 정확하다. 술집이 BAR의 소분류(와인바·위스키바…)를
  /// 그대로 이어받았으므로([pub]), 두 대분류가 이제 같은 것을 가리킨다.
  static const Map<String, String> _retiredCategoryHome = {'BAR': '술집'};

  /// 라이브·공연은 **소분류를 봐야** 집이 정해진다.
  ///
  /// 라이브는 업종이 아니라 콘텐츠라, '라이브·공연'이라는 값 하나로는 그
  /// 가게가 술집인지 카페인지 알 수 없다. 다행히 소분류가 그것을 말해 준다.
  /// 집을 알 수 없는 값('인디공연'·'DJ 공연'·'공연장')은 **넣지 않는다** —
  /// 억지로 술집에 넣으면 공연장이 술집 목록에 뜬다. 그 가게들은 '전체'와
  /// 🎤 라이브 특징으로 계속 찾힌다([PlaceFeatures.of] ⑤가 대분류만 보고
  /// 그 특징을 켜 주므로 호스트가 아무것도 다시 고르지 않아도 된다).
  static const Map<String, String> _retiredSubcategoryHome = {
    '라이브펍': '술집',
    '재즈바': '술집',
    '라이브카페': '카페·디저트',
  };

  /// 대분류로 올라오기 **전에** 다른 필드에 저장돼 있던 값으로도 이 대분류에
  /// 걸리는가.
  ///
  /// 지금은 혼술바 하나다 — 예전에는 특징 태그(`themeTags: ['혼술바']`)였다.
  /// 이 다리가 없으면 그 태그로 등록된 가게들이 새 '혼술바' 대분류에서 통째로
  /// 비어 보인다. 반대로 [categoryOf]는 **건드리지 않는다** — 그 문서들이 지금
  /// 걸려 있는 술집·BAR에서 빠져나가면 그쪽이 사라지기 때문이다(양쪽에 함께
  /// 보이는 쪽이 안전하다).
  static bool _matchesLegacyCategory(
    Map<String, dynamic> data,
    String category,
  ) {
    // ① 혼술바 — 예전에는 특징 태그였다.
    if (category == soloBar.label && _themeTags(data).contains(soloBar.label)) {
      return true;
    }

    // ② 은퇴한 대분류 — 저장값은 그대로 두고 살아 있는 대분류에서 함께 뜬다.
    //
    //    [categoryOf]는 여기서도 **건드리지 않는다** — 그 문서의 대분류는
    //    여전히 'BAR'이고, 카드·상세·업종별 표가 전부 그 값으로 그려진다.
    //    달라지는 것은 "술집을 켰을 때 함께 걸리는가" 하나뿐이다.
    final from = categoryOf(data);
    if (from == null) return false;
    if (_retiredCategoryHome[from] == category) return true;
    if (from == live.label) {
      for (final s in subcategoriesOf(data)) {
        if (_retiredSubcategoryHome[s] == category) return true;
      }
    }
    return false;
  }

  /// 대분류 하나를 골랐을 때 이 문서가 걸리는가.
  static bool matchesCategory(Map<String, dynamic> data, String category) =>
      categoryOf(data) == category || _matchesLegacyCategory(data, category);

  /// 고른 대분류들 중 하나라도 걸리는가(OR). 비어 있으면 조건 없음.
  static bool matchesAnyCategory(
    Map<String, dynamic> data,
    Set<String> categories,
  ) {
    if (categories.isEmpty) return true;
    final c = categoryOf(data);
    if (c != null && categories.contains(c)) return true;
    return categories.any((cat) => _matchesLegacyCategory(data, cat));
  }

  // ── 글로벌 푸드 통합 ──────────────────────────────────────────────────
  //
  // 푸드 소분류를 고르는 화면에서는 나라별 칸(멕시칸·인도·태국·베트남·중동·
  // 지중해)을 없애고 '글로벌 푸드' 한 칸으로 묶었다 — 여섯 칸이 시트의 절반을
  // 먹는데 정작 게스트가 묻는 것은 "한식이냐 아니냐" 수준이기 때문이다.
  //
  // ⚠️ 저장값은 **그대로 둔다**. 이미 `placeSubcategories: ['멕시칸']`으로
  //    등록된 문서가 있고, 마이그레이션은 되돌릴 수 없다. 대신 여기서 다리를
  //    놓는다 — '글로벌 푸드'를 고르면 나라별 값으로 저장된 문서도 함께 걸린다
  //    (옛 클럽 소분류를 장르로 읽어 주는 [legacyClubGenresOf]와 같은 관례).
  //
  //    반대 방향으로는 넓히지 않는다 — 상세검색에서 '멕시칸'만 콕 집어 고른
  //    사람에게 '글로벌 푸드'로만 등록된 가게를 끼워 주면 좁힌 뜻이 사라진다.

  /// 나라별 칸을 대신하는 소분류 저장값.
  static const String globalFood = '글로벌 푸드';

  /// '글로벌 푸드'로 묶기 전에 쓰던 나라별 소분류 저장값들.
  /// 고를 수는 없지만(시트에서 뺐다) 이미 저장된 문서는 계속 걸려야 한다.
  static const List<String> legacyGlobalFoodSubcategories = [
    '멕시칸',
    '인도',
    '태국',
    '베트남',
    '중동',
    '지중해',
  ];

  /// '글로벌 푸드'를 골랐다면 옛 나라별 값까지 넓힌 집합. 아니면 그대로.
  static Set<String> expandGlobalFood(Set<String> subcategories) =>
      subcategories.contains(globalFood)
      ? {...subcategories, ...legacyGlobalFoodSubcategories}
      : subcategories;

  /// 고른 소분류들 중 하나라도 걸리는가(OR). 비어 있으면 조건 없음.
  static bool matchesAnySubcategory(
    Map<String, dynamic> data,
    Set<String> subcategories,
  ) {
    if (subcategories.isEmpty) return true;
    final wanted = expandGlobalFood(subcategories);
    final subs = subcategoriesOf(data).toSet();
    return subs.any(wanted.contains);
  }

  /// 대분류 아래에 있는 소분류인지 — 상세검색 시트가 고른 대분류에 맞는
  /// 소분류만 보여줄 때 쓴다.
  static bool hasSubcategory(String category, String subcategory) =>
      byLabel(category)?.allSubcategories.contains(subcategory) ?? false;

  /// 소분류가 속한 대분류. 여러 대분류에 같은 이름('기타')이 있으므로 먼저
  /// 찾은 것을 돌려준다 — 호출부는 대분류를 이미 알고 있는 자리에서만 쓴다.
  static String? categoryOfSubcategory(String subcategory) {
    for (final c in all) {
      if (c.allSubcategories.contains(subcategory)) return c.label;
    }
    return null;
  }
}
