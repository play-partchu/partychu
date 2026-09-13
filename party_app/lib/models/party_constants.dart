/// 파티 유형·분위기 중앙 관리.
/// 새 항목 추가/삭제 시 이 파일만 수정하면 앱 전체에 반영된다.
class PartyConstants {
  PartyConstants._();

  static const List<String> partyTypes = [
    '하우스파티',
    '게스트하우스 파티',
    '풀파티',
    '루프탑 파티',
    '클럽 파티',
    'EDM 파티',
    'DJ 파티',
    '라이브 파티',
    '공연 파티',
    '포차 파티',
    '와인 파티',
    '칵테일 파티',
    '맥주 파티',
    'BBQ 파티',
    '캠핑 파티',
    '글램핑 파티',
    '요트 파티',
    '선상 파티',
    '페스티벌',
    '맥주축제',
    '뮤직 페스티벌',
    '라운지 파티',
    '프라이빗 파티',
    '애프터파티',
    '시즌 파티',
    '코스프레 파티',
    '할로윈 파티',
    '크리스마스 파티',
    '신년 파티',
    '외국인 파티',
    '펍 파티',
    '소개팅 파티',
    '돌싱',
  ];

  /// 파티 유형의 화면 표시용 라벨(이모지+짧은 이름) — 검색값(위 [partyTypes]의
  /// 원문 문자열)은 Firestore 저장·필터 매칭에 그대로 쓰이므로 절대 바꾸지
  /// 않고, 화면에 보여줄 때만 이 맵을 거쳐 짧은 라벨로 바꿔치기한다.
  static const Map<String, String> partyTypeLabels = {
    '하우스파티': '🏠 하우스',
    '게스트하우스 파티': '🏡 게스트하우스',
    '풀파티': '🎉 풀파티',
    '루프탑 파티': '🌇 루프탑',
    '클럽 파티': '🎧 클럽',
    'EDM 파티': '🎵 EDM',
    // 🎤는 '라이브'와 겹쳐 두 칩이 같은 얼굴이 됐다 — DJ는 턴테이블에 얹는
    // 판(📀)으로. 🎧는 이미 '클럽'이 쓰고 있다.
    'DJ 파티': '📀 DJ',
    '라이브 파티': '🎤 라이브',
    '공연 파티': '🎭 공연',
    '포차 파티': '🍻 포차',
    '와인 파티': '🍷 와인',
    '칵테일 파티': '🍸 칵테일',
    '맥주 파티': '🍺 맥주',
    'BBQ 파티': '🥩 BBQ',
    '캠핑 파티': '🏕️ 캠핑',
    '글램핑 파티': '⛺ 글램핑',
    '요트 파티': '🛥️ 요트',
    '선상 파티': '🚢 선상',
    '페스티벌': '🎪 페스티벌',
    '맥주축제': '🍺 맥주축제',
    '뮤직 페스티벌': '🎶 뮤직 페스티벌',
    '라운지 파티': '🥂 라운지',
    '프라이빗 파티': '🔒 프라이빗',
    '애프터파티': '✨ 애프터',
    '시즌 파티': '🌸 시즌',
    '코스프레 파티': '🎭 코스프레',
    '할로윈 파티': '🎃 할로윈',
    '크리스마스 파티': '🎄 크리스마스',
    '신년 파티': '🎆 신년',
    '외국인 파티': '🌐 외국인',
    '펍 파티': '🍻 펍',
    '소개팅 파티': '💑 소개팅',
    // 돌싱만 라벨에 이모지가 없다 — 앞에 붙는 것은 글자가 아니라 이미지
    // 아이콘이고, 그 경로는 [typeVibeIconAssets]가 따로 들고 있다. 여기에
    // 이모지를 넣으면 아이콘과 이모지가 둘 다 붙는다.
    '돌싱': '돌싱',
  };

  /// 이모지 대신 **이미지 아이콘**을 앞에 다는 항목 — 값 → asset 경로.
  ///
  /// 저장값([partyTypes] / [vibes])에는 경로도 이모지도 들어가지 않는다.
  /// Firestore에 남는 것은 언제나 `'돌싱'` 같은 안정적인 문자열 하나뿐이고,
  /// 아이콘은 **그리는 순간에만** 이 표를 거쳐 붙는다. 그래서 아이콘 그림을
  /// 바꾸거나 없애도 이미 저장된 파티는 하나도 건드리지 않는다.
  ///
  /// 그리는 쪽은 [PartyTypeVibeIcon]이 하나로 맡는다 — 파일이 없거나 디코딩에
  /// 실패해도 칩이 깨지지 않게 대체 아이콘으로 떨어진다.
  static const Map<String, String> typeVibeIconAssets = {
    '돌싱': 'assets/images/party_type_dolsing.png',
  };

  /// 이 값 앞에 붙일 이미지 아이콘 경로 — 없으면 null(= 이모지 항목).
  static String? iconAssetFor(String value) => typeVibeIconAssets[value];

  /// 검색값(원문)을 화면 표시용 라벨로 변환 — 매핑이 없는 값(과거 데이터의
  /// '기타' 등)은 원문 그대로 보여준다.
  static String labelFor(String type) => partyTypeLabels[type] ?? type;

  /// 분위기 — 파티 유형과 달리 **저장값 자체가 이모지 라벨**이다(Firestore
  /// `vibes` 배열에 이 문자열이 그대로 들어간다). 그래서 이 목록의 문자열은
  /// 표기를 바꾸고 싶더라도 함부로 손대면 안 된다 — 예전에 저장된 파티의 값과
  /// 달라지는 순간 그 파티가 검색에서 사라진다. 보이는 글자만 바꿀 때는
  /// [vibeLabels]를 쓴다([partyTypeLabels]와 같은 방식).
  ///
  /// 여기서 빠진 값(아래 [retiredVibes])은 **고를 수만 없을 뿐** 지워지지
  /// 않는다 — 이미 저장된 파티는 그 값을 그대로 들고 있고, 상세 화면에도
  /// 그대로 뜨며, 검색어로도 계속 찾힌다.
  static const List<String> vibes = [
    '🍺 술 중심',
    '🙅 논알콜',
    '🎵 음악 중심',
    '💃 춤',
    '🌍 글로벌',
    '✨ 프리미엄',
    '🌅 야외',
    '🏡 실내',
  ];

  /// 더 이상 **새로 고를 수 없는** 분위기 — 저장값으로는 남아 있다.
  ///
  /// - `🔥 신나는` — 거의 모든 파티가 체크해 걸러내는 힘이 없었다.
  /// - `🎉 대규모` / `🏠 소규모` — 인원수(파티 총인원) 필터와 같은 것을
  ///   묻는 중복 조건이었다([PartyScaleFilter]).
  ///
  /// 등록·수정 화면은 이 값이 이미 걸려 있는 파티에 한해 칩을 계속 보여준다
  /// (그래야 끌 수 있다). 새로 켜는 길은 어디에도 없다.
  static const List<String> retiredVibes = ['🔥 신나는', '🎉 대규모', '🏠 소규모'];

  /// 분위기의 화면 표시용 라벨 — 저장값은 그대로 두고 **보이는 글자만**
  /// 바꾼다. 매핑이 없으면 저장값을 그대로 보여준다.
  static const Map<String, String> vibeLabels = {
    // 💃(춤추는 사람)는 클럽 느낌에 치우쳐 있어, 비보잉까지 아우르는
    // 🤸(재주넘기)로 바꿨다. 저장값('💃 춤')은 건드리지 않는다.
    '💃 춤': '🤸 춤',
  };

  /// 분위기 저장값 → 화면 표시용 라벨.
  static String vibeLabelFor(String vibe) => vibeLabels[vibe] ?? vibe;

  /// 화면에서 **하나로 합쳐 보여주는** '파티 유형 · 분위기' 항목 하나.
  ///
  /// [isVibe]는 화면에 드러나지 않는다 — 이 값이 [PartyFilter.vibes] 쪽에
  /// 저장되는지 [PartyFilter.partyTypes] 쪽에 저장되는지만 가린다. 고르는
  /// 사람에게 '하우스'와 '술 중심'은 똑같이 "어떤 파티인가"에 대한 답이라
  /// 목록에서는 구분하지 않는다.
  static List<({String value, bool isVibe, String label})>
  get typeVibeOptions => [
    for (final t in partyTypes) (value: t, isVibe: false, label: labelFor(t)),
    for (final v in vibes) (value: v, isVibe: true, label: vibeLabelFor(v)),
  ];

  /// [typeVibeOptions]에, **이미 골라져 있지만 목록에서 빠진 옛 값**을 뒤에
  /// 붙여 돌려준다([retiredVibes], 이름이 바뀐 옛 유형 등).
  ///
  /// 등록·수정 화면도 상세검색도 이 하나만 읽는다 — 그래야 등록할 때 고른
  /// 항목과 검색할 때 고르는 항목이 같은 목록·같은 라벨·같은 순서가 된다.
  /// 옛 값을 뒤에 붙이는 이유는 하나다: 보이지 않으면 끌 수도 없다.
  static List<({String value, bool isVibe, String label})> typeVibeOptionsFor({
    Set<String> selectedTypes = const {},
    Set<String> selectedVibes = const {},
  }) => [
    ...typeVibeOptions,
    for (final t in selectedTypes.where((t) => !partyTypes.contains(t)))
      (value: t, isVibe: false, label: labelFor(t)),
    for (final v in selectedVibes.where((v) => !vibes.contains(v)))
      (value: v, isVibe: true, label: vibeLabelFor(v)),
  ];

  /// '파티 유형 · 분위기'에서 고를 수 있는 **총 개수**.
  ///
  /// 유형 5개 / 분위기 3개로 따로 세던 것을 합쳤다 — 화면이 한 목록인데
  /// 한도가 둘이면, 어떤 칩은 켜지고 어떤 칩은 안 켜지는 이유를 고르는
  /// 사람이 알 길이 없다. 이제 **순서와 상관없이 합계만** 본다:
  /// `partyTypes.length + vibes.length <= maxTypeVibes`.
  ///
  /// 저장은 여전히 두 배열로 나뉘지만([PartyFilter.partyTypes] /
  /// [PartyFilter.vibes]) 한도 판정은 이 하나뿐이다.
  static const int maxTypeVibes = 8;

  /// 이미 [selected]개를 고른 상태에서 하나 더 고를 수 있는가 —
  /// 두 배열의 **합계**만 본다.
  ///
  /// 옛 문서가 한도를 넘겨 들고 있어도(마이그레이션하지 않는다) 이 판정은
  /// "더 못 고른다"만 말한다 — 이미 있는 값은 그대로 복원되고, 빼는 것은
  /// 언제나 된다.
  static bool canPickTypeVibe(int selected) => selected < maxTypeVibes;

  /// 한도에 걸렸을 때의 안내 — 화면마다 다른 말이 나오지 않게 한 곳에 둔다.
  static String get typeVibeLimitMessage =>
      '파티 유형 · 분위기는 최대 $maxTypeVibes개까지 선택할 수 있어요.';

  static const int maxTags = 6;
}
