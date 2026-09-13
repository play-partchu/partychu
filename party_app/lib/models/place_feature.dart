/// 플레이스 **빠른 탐색 특징**(feature)의 정본.
///
/// ── 특징은 저장하는 값이 아니라 '읽어내는 값'이다 ─────────────────────────
/// 게스트가 지도 위에서 한 번 눌러 거르는 조건(🍶 콜키지 가능 · 🚭 금연 ·
/// 🎂 생일혜택 …)은 대부분 이미 다른 곳에 저장돼 있다 — 콜키지는
/// `placeAttributes.corkage`에, 반려동물은 `petPolicy`에, 생일은 옛
/// `eventSubtype`에. 그걸 특징 배열에 **한 번 더** 적게 하면
///
///   · 호스트가 같은 것을 두 번 고르게 되고
///   · 두 값이 어긋나는 순간 어느 쪽이 정본인지 알 수 없어진다.
///
/// 그래서 특징은 [PlaceFeatures.of]가 문서에서 **유도**한다. 필터는 이 함수가
/// 만든 집합 하나만 보므로, 새 특징을 더할 때 고칠 곳도 이 파일 하나다.
///
/// ── 하위호환이 여기서 끝난다 ──────────────────────────────────────────────
/// 옛 문서에는 새 필드가 하나도 없다. 그래도 `themeTags`·`petPolicy`·
/// `facilityOptions`·`eventSubtype`·영업시간은 있으므로, 그 값들로 유도되는
/// 특징은 **옛 문서에서도 그대로 켜진다**. 새 구조를 넣었다고 옛 플레이스가
/// 필터에서 사라지지 않는 이유다.
///
/// `placeFeatures` 배열은 유도할 수 없는 것(핫플처럼 호스트가 직접 선언하는
/// 값)만 담는 보조 저장소다.
library;

import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/pet_policy.dart';
import 'package:party_app/models/place_attributes.dart';
import 'package:party_app/models/place_corkage.dart';
import 'package:party_app/models/place_facility_options.dart';
import 'package:party_app/models/place_taxonomy.dart';
import 'package:party_app/models/place_weekly_hours.dart';
// 혜택 필드 이름 하나만 빌려 온다 — 같은 상수를 모델 층에 다시 적으면
// 한쪽만 바뀌었을 때 '혜택 있음'이 조용히 꺼진다.
import 'package:party_app/widgets/partychu_perk.dart' show kPartychuPerkField;

/// 빠른 필터 한 칸.
class PlaceFeature {
  const PlaceFeature({
    required this.key,
    required this.emoji,
    required this.label,
    this.quick = false,
    this.retired = false,
  });

  /// 저장값이자 필터 값. 배포 후 변경 금지.
  final String key;
  final String emoji;
  final String label;

  /// true면 지도/목록 상단 **가로스크롤 2단**에 바로 노출된다.
  /// 나머지는 '더보기' 상세필터에서만 고른다 — 첫 화면에 전부 깔면 무엇을
  /// 눌러야 할지 알 수 없게 된다.
  final bool quick;

  /// **필터 화면에서 더 이상 고를 수 없는** 특징.
  ///
  /// 값을 지우는 것이 아니다 — [PlaceFeatures.of]는 계속 유도하고, 예전에
  /// 저장·공유된 필터 상태에 이 값이 들어 있어도 판정은 그대로 걸린다.
  /// 다만 새로 고를 자리를 어느 화면에도 두지 않는다([PlaceFeatures.selectable]).
  final bool retired;

  String get display => '$emoji $label';
}

class PlaceFeatures {
  PlaceFeatures._();

  /// Firestore 필드 이름 — 호스트가 직접 선언하는 특징만 담는다.
  static const String field = 'placeFeatures';

  // ── 정의 ──────────────────────────────────────────────────────────────
  //
  // quick: true인 것이 2단 가로스크롤에 그대로 나간다(순서도 이 순서).

  // 저장값('핫플')은 그대로 두고 보이는 이름만 바꾼다 — 이미 등록된
  // 플레이스의 placeFeatures/themeTags에 '핫플'이 들어 있고, 필터 판정도
  // 그 값으로 걸린다.
  static const hot = PlaceFeature(
    key: '핫플',
    emoji: '📸',
    label: '사진맛집',
    quick: true,
  );
  static const unlimited = PlaceFeature(
    key: '무제한',
    emoji: '♾',
    label: '무제한',
    quick: true,
  );
  /// 🍶 콜키지 가능 — **무료·유료를 가리지 않고** 술을 가져갈 수 있는 집.
  ///
  /// 예전에는 '🍷 콜키지 프리'로 무료인 집만 걸렀다. 게스트가 묻는 것은
  /// "가져가도 되나"이지 "공짜인가"가 아니라서, 유료로 받는 집이 검색에서
  /// 통째로 빠지고 있었다. 무료/유료 구분은 필터가 아니라 **목록 카드의
  /// 배지**로 푼다([PlaceCorkage.cardBadge]).
  ///
  /// ⚠️ [key]는 옛 이름 `'콜키지프리'` 그대로다 — 이 문자열은 호스트가 직접
  /// 선언한 `placeFeatures` 배열과 골라 둔 빠른필터에 남아 있을 수 있어서,
  /// 바꾸면 그 값들이 조용히 아무 데도 걸리지 않게 된다. 바뀐 것은 **무엇을
  /// 묻는가**(판정)와 **뭐라고 적는가**(표기)뿐이다.
  static const corkageAvailable = PlaceFeature(
    key: '콜키지프리',
    emoji: '🍶',
    label: '콜키지 가능',
    quick: true,
  );
  static const private = PlaceFeature(
    key: '프라이빗',
    emoji: '🔒',
    label: '프라이빗',
    quick: true,
  );
  static const bigScreen = PlaceFeature(
    key: '대형스크린',
    emoji: '🖥',
    label: '대형스크린',
    quick: true,
  );
  static const play = PlaceFeature(
    key: '놀거리',
    emoji: '🎲',
    label: '놀거리',
    quick: true,
  );
  // 🎂는 '케이크 반입'과 같은 얼굴이라 둘이 구분되지 않았다 — 생일 쪽을
  // 🎈으로 옮긴다(저장값 '생일혜택'은 그대로).
  static const birthday = PlaceFeature(
    key: '생일혜택',
    emoji: '🎈',
    label: '생일혜택',
    quick: true,
  );
  static const dj = PlaceFeature(
    key: 'DJ',
    emoji: '🎧',
    label: 'DJ',
    quick: true,
  );
  static const live = PlaceFeature(
    key: '라이브',
    emoji: '🎤',
    label: '라이브',
    quick: true,
  );
  static const lateNight = PlaceFeature(
    key: '심야영업',
    emoji: '🌙',
    label: '심야영업',
    quick: true,
  );
  static const smokeFree = PlaceFeature(
    key: '금연',
    emoji: '🚭',
    label: '금연',
    quick: true,
  );
  static const smokingArea = PlaceFeature(
    key: '흡연공간',
    emoji: '🚬',
    label: '흡연공간 있음',
    quick: true,
  );
  static const pet = PlaceFeature(
    key: '반려동물',
    emoji: '🐶',
    label: '반려동물',
    quick: true,
  );
  static const parking = PlaceFeature(
    key: '주차',
    emoji: '🚗',
    label: '주차',
    quick: true,
  );
  static const firepit = PlaceFeature(
    key: '불멍',
    emoji: '🔥',
    label: '불멍',
    quick: true,
  );
  static const pool = PlaceFeature(
    key: '수영장',
    emoji: '🏊',
    label: '수영장',
    quick: true,
  );

  // ── 더보기(상세필터)에서만 고르는 것들 ────────────────────────────────
  static const eventNow = PlaceFeature(
    key: '이벤트중',
    emoji: '🎉',
    label: '이벤트 진행중',
  );
  static const partychuPerk = PlaceFeature(
    key: '파티츄혜택',
    emoji: '🎁',
    label: '파티츄 혜택',
  );
  static const groupSeat = PlaceFeature(key: '단체석', emoji: '👥', label: '단체석');
  static const outsideFood = PlaceFeature(
    key: '외부음식',
    emoji: '🍕',
    label: '외부음식 가능',
  );
  static const cakeBringIn = PlaceFeature(
    key: '케이크반입',
    emoji: '🎂',
    label: '케이크 반입',
  );
  static const delivery = PlaceFeature(
    key: '배달음식',
    emoji: '🛵',
    label: '배달음식 가능',
  );
  static const bringAlcohol = PlaceFeature(
    key: '주류반입',
    emoji: '🍾',
    label: '주류 반입',
  );
  static const valet = PlaceFeature(key: '발렛', emoji: '🛎', label: '발렛');

  /// 🥤 무알콜 음료 — "술을 안 마시는 사람도 같이 갈 수 있나".
  /// 호스트는 [PlaceAttributeCatalog.drinks]에서 고르고, 아래 ③이 그 값을
  /// 이 특징으로 읽는다(새 저장 필드를 만들지 않는다).
  /// 손님이 직접 노래할 수 있는 곳 — 저장값은 이모지 없는 '노래가능'이고
  /// 화면 표기만 '🎤 노래 가능'이다(다른 특징과 같은 관례).
  ///
  /// 라이브(무대 공연)·DJ·노래방 시간 무제한과는 별개 축이다.
  static const singing = PlaceFeature(key: '노래가능', emoji: '🎤', label: '노래 가능');

  /// 손님이 **듣고 싶은 곡을 신청**할 수 있는 곳(매장·DJ·공연 운영자에게).
  /// [singing](직접 부른다)과는 독립된 조건이라 합치지 않는다.
  static const songRequest = PlaceFeature(
    key: '노래신청',
    emoji: '🎵',
    label: '노래 신청 가능',
  );

  /// 주요 경기를 매장에서 볼 수 있는 곳 — 종목은 나누지 않는다(값 하나).
  static const sportsBroadcast = PlaceFeature(
    key: '스포츠중계',
    emoji: '📺',
    label: '스포츠 중계',
  );
  static const nonAlcoholic = PlaceFeature(
    key: '무알콜',
    emoji: '🥤',
    label: '무알콜 음료',
  );

  /// 🥃 하이볼 — 하이볼을 **파는** 집. 호스트는
  /// [PlaceAttributeCatalog.servedDrinks]에서 켜고, 아래 ③이 그 값을 읽는다.
  ///
  /// 주류 종류에 '하이볼'을 이미 골라 둔 옛 문서도 함께 읽는다(다리) —
  /// 같은 것을 두 번 고르게 하지 않는 이 파일의 관례 그대로다.
  ///
  /// [PlaceAttributeCatalog.unlimited]의 '하이볼'(♾ 하이볼 무제한)과는 다른
  /// 축이다 — 그쪽은 "무제한인가"이고 이쪽은 "파는가"다.
  static const highball = PlaceFeature(key: '하이볼', emoji: '🥃', label: '하이볼');

  /// 🏺 막걸리 — 막걸리를 **파는** 집.
  ///
  /// 주류 종류의 '전통주'로는 켜지 않는다 — 전통주는 소주·약주까지 아우르는
  /// 더 넓은 말이라, 그걸 막걸리로 읽으면 없는 집이 걸린다.
  ///
  /// 이모지가 🍶(사케병)가 아니라 🏺(항아리)인 이유: 🍶는 이미 [corkageAvailable]
  /// 이 쓰고 있어서 필터 목록에 두 칩이 같은 얼굴로 나란히 섰다. 🎂가 겹쳐
  /// 생일혜택을 🎈으로 옮긴 것과 같은 이유다 — **한 화면에 같은 이모지 둘**은
  /// 고르는 사람에게 둘을 구별할 단서를 주지 않는다.
  static const makgeolli = PlaceFeature(key: '막걸리', emoji: '🏺', label: '막걸리');

  /// 🕛 24시간 — **필터에서는 은퇴했다.**
  ///
  /// 24시간은 편의·서비스가 아니라 영업시간이다. 운영시간 정보
  /// (`isOpen24Hours`·`placeWeeklyHours`)는 그대로 두고 아래 ⑩도 그대로
  /// 유도하지만, 고를 자리만 없앤다 — 예전에 저장된 필터 상태에 '24시간'이
  /// 들어 있어도 판정은 예전 그대로 걸린다.
  static const open24 = PlaceFeature(
    key: '24시간',
    emoji: '🕛',
    label: '24시간',
    retired: true,
  );
  static const bbq = PlaceFeature(key: 'BBQ', emoji: '🍖', label: 'BBQ');
  static const tableReservation = PlaceFeature(
    key: '테이블예약',
    emoji: '🪑',
    label: '테이블 예약',
  );
  static const soloFriendly = PlaceFeature(
    key: '혼자가능',
    emoji: '🙋',
    label: '혼자 가기 좋은',
  );

  /// 🔥 구워주는 집 — 게스트는 이 한 칸으로 찾고, **어떻게** 구워 주는지는
  /// 상세페이지가 [PlaceAttributeCatalog.grillService] 값으로 보여준다.
  /// '직접 구움'은 여기 걸리지 않는다([PlaceAttributeCatalog.grillServed]).
  static const grill = PlaceFeature(key: '구워줌', emoji: '🔥', label: '구워주는 집');

  /// 🍽️ 조리되어 나와요 — 손님이 직접 굽거나 조리하지 않아도 되는 곳.
  ///
  /// [grill]과 **별개의 조건**이다. 구워주는 집은 "고기를 누가 굽는가"에 대한
  /// 답이고, 이쪽은 "손님이 조리를 아예 안 해도 되는가"에 대한 답이다. 둘 다
  /// 켜진 가게도(직원이 구워주고 밑반찬도 조리되어 나옴), 이것만 켜진
  /// 가게도(구울 것이 없는 파스타집) 있다.
  ///
  /// 저장값은 `placeAttributes.cookedService`의
  /// [PlaceAttributeCatalog.cookedServed]에서 유도한다 — 특징 키('조리제공')도
  /// 저장값('조리되어 나옴')도 **이모지가 없고**, 🍽️는 표기에서만 붙는다.
  static const cookedServed = PlaceFeature(
    key: '조리제공',
    emoji: '🍽️',
    label: '조리되어 나와요',
  );

  /// 🍸 바좌석 — 새 필드가 아니다. 이미 저장돼 있는 좌석 유형
  /// (`facilityOptions.seatingTypes`의 카운터석·바 테이블)에서 유도한다.
  static const barSeat = PlaceFeature(key: '바좌석', emoji: '🍸', label: '바좌석');

  /// **전체 어휘.** [of]가 유도할 수 있는 값 전부 — 은퇴한 것까지 포함한다.
  /// 판정([matchesAll])과 하위호환이 이 목록을 본다.
  static const List<PlaceFeature> all = [
    hot,
    unlimited,
    corkageAvailable,
    private,
    bigScreen,
    play,
    birthday,
    dj,
    live,
    lateNight,
    smokeFree,
    smokingArea,
    pet,
    parking,
    firepit,
    pool,
    eventNow,
    partychuPerk,
    groupSeat,
    outsideFood,
    cakeBringIn,
    delivery,
    bringAlcohol,
    valet,
    open24,
    bbq,
    tableReservation,
    soloFriendly,
    grill,
    cookedServed,
    barSeat,
    nonAlcoholic,
    highball,
    makgeolli,
    singing,
    songRequest,
    sportsBroadcast,
  ];

  /// **필터 화면이 보여주는 목록.** 순서가 곧 화면 순서다.
  ///
  /// 편의·서비스 시트·지도 상세필터·상세검색 시트가 전부 이 하나를 훑는다 —
  /// 화면마다 따로 늘어놓으면 "여기선 고를 수 있는데 저기선 없는" 항목이
  /// 생긴다. 은퇴한 값([PlaceFeature.retired])만 빠진다.
  static List<PlaceFeature> get selectable =>
      all.where((f) => !f.retired).toList(growable: false);

  /// 2단 가로스크롤에 나가는 것만.
  static List<PlaceFeature> get quick =>
      all.where((f) => f.quick).toList(growable: false);

  /// '더보기' 상세필터에서만 고르는 것.
  static List<PlaceFeature> get extra =>
      all.where((f) => !f.quick).toList(growable: false);

  static PlaceFeature? byKey(String key) {
    for (final f in all) {
      if (f.key == key) return f;
    }
    return null;
  }

  static String labelOf(String key) => byKey(key)?.label ?? key;

  static String displayOf(String key) => byKey(key)?.display ?? key;

  /// 호스트가 등록 화면에서 **직접** 켜던 특징. 지금은 하나도 없다.
  ///
  /// 마지막까지 남아 있던 것이 '핫플'(📸 사진맛집)인데, 등록 폼의 '특징 태그'
  /// 칩을 걷어내면서 함께 사라졌다 — 가게가 스스로 붙이는 홍보 문구라 검색
  /// 조건의 근거가 되지 못했다. 이제 모든 특징은 다른 값에서 유도된다([of]).
  ///
  /// 이미 `themeTags: ['핫플']`이 달린 문서는 [of]가 예전과 똑같이 읽어 주므로
  /// 필터·카드·상세에서 그대로 걸린다. 일괄 정리는 하지 않는다.
  static const List<PlaceFeature> hostDeclared = <PlaceFeature>[];

  // ── 유도 ──────────────────────────────────────────────────────────────

  /// 이 문서가 가진 특징 전부. 필터·카드·상세가 **모두 이 하나**만 본다.
  static Set<String> of(Map<String, dynamic> data) {
    final result = <String>{};

    // ① 호스트가 직접 선언한 값(새 필드).
    final declared = (data[field] as List?)?.whereType<String>() ?? const [];
    result.addAll(declared);

    // ② 기존 특징 태그 — '핫플'과 '이벤트 진행중'은 예전부터 여기 있었다.
    final tags = _themeTags(data);
    if (tags.contains('핫플')) result.add(hot.key);
    if (tags.contains(ListingConstants.placeEventTag)) result.add(eventNow.key);

    // ③ 새 속성에서 유도.
    final attrs = PlaceAttributes.fromDoc(data);
    if (attrs.selected(PlaceAttributeCatalog.unlimitedKey).isNotEmpty) {
      result.add(unlimited.key);
    }
    // 콜키지는 **허용 여부**만 본다 — 무료·유료·(무료유료 미상) 셋 다 켠다.
    // 판정 규칙은 카드·상세와 같은 정본 하나를 쓴다([PlaceCorkage]).
    if (PlaceCorkage.fromAttributes(attrs).isAllowed) {
      result.add(corkageAvailable.key);
    }
    if (attrs.isSelected(PlaceAttributeCatalog.screenKey, '대형스크린 있음')) {
      result.add(bigScreen.key);
    }
    if (attrs.selected(PlaceAttributeCatalog.playItemsKey).isNotEmpty) {
      result.add(play.key);
    }
    // 노래 — 호스트가 '노래' 그룹에서 직접 켠다. 놀거리에 '노래방'을 이미
    // 골라 둔 가게도 같은 뜻이므로 함께 읽는다(옛 문서를 잇는 다리) —
    // 새 필드를 만들지 않는 이 파일의 관례 그대로다.
    if (attrs.isSelected(
          PlaceAttributeCatalog.singingKey,
          PlaceAttributeCatalog.singingAvailable,
        ) ||
        attrs.isSelected(PlaceAttributeCatalog.playItemsKey, '노래방')) {
      result.add(singing.key);
    }
    // 노래 신청 — 같은 '노래' 그룹의 **다른 값**이다(직접 부르는 것과 별개).
    if (attrs.isSelected(
      PlaceAttributeCatalog.singingKey,
      PlaceAttributeCatalog.songRequestAvailable,
    )) {
      result.add(songRequest.key);
    }
    // 스포츠 중계 — 종목을 나누지 않으므로 값도 하나다.
    if (attrs.isSelected(
      PlaceAttributeCatalog.sportsKey,
      PlaceAttributeCatalog.sportsBroadcast,
    )) {
      result.add(sportsBroadcast.key);
    }
    if (attrs.selected(PlaceAttributeCatalog.birthdayPerksKey).isNotEmpty) {
      result.add(birthday.key);
    }
    if (attrs.isSelected('dj', 'DJ 있음')) result.add(dj.key);
    if (attrs.isSelected(PlaceAttributeCatalog.firepitKey, '불멍 가능')) {
      result.add(firepit.key);
    }
    if (attrs.selected(PlaceAttributeCatalog.poolKey).isNotEmpty) {
      result.add(pool.key);
    }
    final parkingPicks = attrs.selected(PlaceAttributeCatalog.parkingKey);
    if (parkingPicks.isNotEmpty) result.add(parking.key);
    if (parkingPicks.contains('발렛 가능')) result.add(valet.key);
    if (attrs.isSelected(PlaceAttributeCatalog.bbqKey, 'BBQ 가능')) {
      result.add(bbq.key);
    }
    if (attrs.isSelected(PlaceAttributeCatalog.clubEntryKey, '테이블 예약 가능')) {
      result.add(tableReservation.key);
    }
    // 술을 안 마시는 손님이 시킬 게 있나 — 호스트가 등록 화면
    // ([PlaceAttributeCatalog.drinks])에서 직접 고른다.
    if (attrs.isSelected(
      PlaceAttributeCatalog.drinksKey,
      PlaceAttributeCatalog.nonAlcoholicDrink,
    )) {
      result.add(nonAlcoholic.key);
    }
    // 하이볼 — 호스트가 켠 값이 정본이고, 주류 종류에 '하이볼'을 이미 골라 둔
    // 옛 문서도 같은 뜻이므로 함께 읽는다(노래방↔노래가능과 같은 다리).
    if (attrs.isSelected(
          PlaceAttributeCatalog.servedDrinksKey,
          PlaceAttributeCatalog.highballServed,
        ) ||
        attrs.isSelected(PlaceAttributeCatalog.alcoholTypesKey, '하이볼')) {
      result.add(highball.key);
    }
    // 막걸리 — 다리를 놓지 않는다('전통주'는 막걸리보다 넓은 말이다).
    if (attrs.isSelected(
      PlaceAttributeCatalog.servedDrinksKey,
      PlaceAttributeCatalog.makgeolliServed,
    )) {
      result.add(makgeolli.key);
    }
    // 구워주는 서비스 — '직접 구움'은 서비스가 아니므로 켜지 않는다.
    final grillPick = attrs.single(PlaceAttributeCatalog.grillKey);
    if (grillPick != null && PlaceAttributeCatalog.grillServed(grillPick)) {
      result.add(grill.key);
    }
    // 조리 제공 — 구워주는 서비스와 **따로** 읽는다(같은 가게가 둘 다 켤 수 있다).
    if (attrs.isSelected(
      PlaceAttributeCatalog.cookedKey,
      PlaceAttributeCatalog.cookedServed,
    )) {
      result.add(cookedServed.key);
    }
    final bringInPicks = attrs.selected(PlaceAttributeCatalog.bringInKey);
    if (bringInPicks.contains('케이크 반입 가능')) result.add(cakeBringIn.key);
    if (bringInPicks.contains('배달음식 가능')) result.add(delivery.key);
    if (bringInPicks.contains('주류 반입 가능')) result.add(bringAlcohol.key);
    final purposePicks = attrs.selected(PlaceAttributeCatalog.purposesKey);
    if (purposePicks.contains('프라이빗')) result.add(private.key);
    if (purposePicks.contains('단체석')) result.add(groupSeat.key);
    if (purposePicks.contains('라이브공연')) result.add(live.key);

    // ④ 흡연 정책 — 좌석 금연과 흡연공간 유무는 **각각** 읽어낸다.
    //    '실내 금연 + 별도 흡연구역'인 가게는 두 필터 모두에 걸린다.
    final smoking = attrs.single(PlaceAttributeCatalog.smokingKey);
    if (smoking != null) {
      if (PlaceAttributeCatalog.smokeFreeSeating(smoking)) {
        result.add(smokeFree.key);
      }
      if (PlaceAttributeCatalog.hasSmokingArea(smoking)) {
        result.add(smokingArea.key);
      }
    }

    // ⑤ 대분류에서 유도 — 라이브·공연 가게는 '라이브'를 따로 켜지 않아도 된다.
    final category = PlaceTaxonomy.categoryOf(data);
    if (category == PlaceTaxonomy.live.label) result.add(live.key);
    if (category == PlaceTaxonomy.play.label) result.add(play.key);
    if (category == PlaceTaxonomy.club.label &&
        attrs.selected('musicGenres').isNotEmpty) {
      result.add(dj.key);
    }

    // ⑥ 기존 좌석·편의 옵션(facilityOptions) — 이미 저장돼 있는 값이라
    //    새로 묻지 않는다.
    final facilities = _facilities(data);
    final seats = facilities.selected(PlaceFacilityCatalog.seatingTypes.key);
    final conveniences = facilities.selected(
      PlaceFacilityCatalog.seatingConveniences.key,
    );
    if (seats.contains('개별룸') || conveniences.contains('전체 대관 가능')) {
      result.add(private.key);
    }
    if (seats.contains('단체석') || conveniences.contains('단체 이용 가능')) {
      result.add(groupSeat.key);
    }
    if (conveniences.contains('1인 방문 가능') ||
        conveniences.contains('혼자 앉기 편한 좌석')) {
      result.add(soloFriendly.key);
    }
    // 혼술바에서 가장 먼저 묻는 "혼자 앉을 바가 있나" — 이미 저장된 좌석
    // 유형에서 그대로 읽는다(호스트에게 다시 묻지 않는다).
    if (seats.contains('카운터석') || seats.contains('바 테이블')) {
      result.add(barSeat.key);
    }
    if (facilities.isSelected(
      PlaceFacilityCatalog.outsideFood.key,
      PlaceFacilityCatalog.outsideFoodAllowedLabel,
    )) {
      result.add(outsideFood.key);
    }

    // ⑦ 기존 생일 이벤트 — 옛 문서는 소분류 하나로만 표시돼 있다.
    if (data['eventSubtype'] == ListingConstants.birthdayEventSubtype) {
      result.add(birthday.key);
    }

    // ⑦-1 방문 예약 — '🪑 테이블 예약'은 예전에 클럽 전용 '입장 정보'
    //     그룹에서만 켤 수 있었다([PlaceAttributeCatalog.clubEntry]는
    //     categories: ['클럽']). 그래서 게스트는 모든 업종에서 이 조건으로
    //     검색할 수 있는데 정작 맛집·술집 호스트는 켤 방법이 없었다.
    //
    //     새 필드를 만들지 않고 **이미 있는 방문 예약 설정**을 읽는다 —
    //     "자리를 미리 잡아둘 수 있나"는 두 값이 같은 말이고, 등록 화면의
    //     방문 예약 섹션(VisitReservationSection)이 이미 그것을 받고 있다.
    final visit = data['visitReservation'];
    if (visit is Map && visit['enabled'] == true) {
      result.add(tableReservation.key);
    }

    // ⑧ 기존 파티츄 혜택.
    final perk = data[kPartychuPerkField];
    if (perk is String && perk.trim().isNotEmpty) result.add(partychuPerk.key);

    // ⑨ 기존 반려동물 정책.
    if (_petPolicy(data).isAllowed) result.add(pet.key);

    // ⑩ 영업시간 — 24시간·심야는 이미 저장된 운영시간에서 그대로 읽는다.
    if (data['isOpen24Hours'] == true) {
      result
        ..add(open24.key)
        ..add(lateNight.key);
    }
    final hours = weeklyHoursOf(data);
    if (hours != null) {
      if (_anyDay(hours, (d) => d.is24Hours)) {
        result
          ..add(open24.key)
          ..add(lateNight.key);
      }
      if (_anyDay(hours, _isLateNight)) result.add(lateNight.key);
    }

    return result;
  }

  /// 고른 특징을 **모두** 가졌는가(AND). 빠른 필터는 겹쳐 누를수록 좁아진다.
  static bool matchesAll(Map<String, dynamic> data, Set<String> wanted) {
    if (wanted.isEmpty) return true;
    return of(data).containsAll(wanted);
  }

  /// 카드·지도 핀에 띄울 특징 — 고른 필터를 **앞으로** 당겨 왜 걸렸는지 바로
  /// 읽히게 한다. 주소보다 이게 먼저 보여야 "가볼 만한 곳인가"가 판단된다.
  static List<PlaceFeature> highlightsOf(
    Map<String, dynamic> data, {
    Set<String> prefer = const {},
    int max = 4,
  }) {
    final owned = of(data);
    final ordered = <PlaceFeature>[
      ...all.where((f) => prefer.contains(f.key) && owned.contains(f.key)),
      ...all.where((f) => !prefer.contains(f.key) && owned.contains(f.key)),
    ];
    return ordered.take(max).toList();
  }

  /// 특징 하나를 **값까지 담아** 적는다 — '무제한'보다 '♾ 하이볼 무제한'이,
  /// '대형스크린'보다 '🖥 150인치'가 훨씬 많은 것을 말해 준다.
  ///
  /// 카드 요약 줄과 상세페이지 상단 칩이 **같은 함수**를 부른다. 화면마다 따로
  /// 문장을 만들면 목록에서는 '무제한', 상세에서는 '하이볼 무제한'이 되어 같은
  /// 가게가 화면마다 다른 이름을 갖는다.
  ///
  /// 값이 하나도 없으면(옛 문서) 특징 이름을 그대로 돌려주므로, 새 구조를
  /// 모르는 플레이스도 예전과 똑같이 보인다.
  static List<String> labelsFor(
    String key,
    PlaceAttributes attrs, {
    bool detailed = false,
  }) {
    if (key == corkageAvailable.key) {
      // 필터는 '가능'만 묻지만([PlaceCorkage.isAllowed]) **표시는 무료·유료를
      // 가른다** — 목록 카드에서 바로 구분되지 않으면 상세페이지에 들어가야만
      // 알 수 있게 되고, 그건 카드에 콜키지 배지를 다는 이유를 없앤다.
      //
      // 카드는 짧게(`🍶 병당 20,000원`), 상세는 자세히(`🍶 콜키지 가능 · 유료
      // · 1병 10,000원`). 문구를 만드는 곳은 [PlaceCorkage] 하나다.
      final corkage = PlaceCorkage.fromAttributes(attrs);
      final text = detailed ? corkage.detailText : corkage.cardBadge;
      return text == null ? const [] : [text];
    }
    if (key == unlimited.key) {
      final picks = attrs.selected(PlaceAttributeCatalog.unlimitedKey);
      if (picks.isEmpty) return [unlimited.display];
      // 카탈로그 순서대로 — 어느 화면에서 봐도 같은 순서로 읽힌다.
      return [
        for (final o in PlaceAttributeCatalog.unlimited.options)
          if (picks.contains(o.label))
            PlaceAttributeCatalog.unlimitedDisplay(o.label),
      ];
    }
    if (key == grill.key) {
      // '구워주는 집'이 아니라 **어떻게** 구워 주는지를 적는다.
      final pick = attrs.single(PlaceAttributeCatalog.grillKey);
      return [
        pick == null
            ? grill.display
            : '${grill.emoji} ${PlaceAttributeCatalog.grillPhrase(pick)}',
      ];
    }
    if (key == bigScreen.key) {
      final size = attrs.detailText(PlaceAttributeCatalog.screenKey, 'size');
      return [size.isEmpty ? bigScreen.display : '🖥 $size'];
    }
    if (key == smokeFree.key || key == smokingArea.key) {
      // 흡연 정책은 고른 갈래를 그대로 — '🚭 전 구역 금연', '🚬 별도 흡연실
      // 있음'처럼 읽혀야 한다. 두 특징이 같은 문구가 되므로 위에서 중복을
      // 걸러 준다([highlightLabelsOf]).
      final policy = attrs.single(PlaceAttributeCatalog.smokingKey);
      if (policy == null) return const [];
      final option = PlaceAttributeCatalog.smoking.options.firstWhere(
        (o) => o.label == policy,
        orElse: () => PlaceAttributeOption(policy),
      );
      return [option.display];
    }
    return [displayOf(key)];
  }

  /// 카드 요약 줄·상세 상단 칩이 그대로 그리는 표기 목록.
  /// [highlightsOf]와 같은 순서(고른 필터가 앞)로, 값이 있는 특징은 값으로.
  static List<String> highlightLabelsOf(
    Map<String, dynamic> data, {
    Set<String> prefer = const {},
    int max = 4,
    /// true면 상세페이지용으로 더 자세히 적는다(콜키지 요금 원문 등).
    /// 목록 카드는 좁으므로 기본값(false)의 짧은 표기를 쓴다.
    bool detailed = false,
  }) {
    final attrs = PlaceAttributes.fromDoc(data);
    final result = <String>[];
    for (final feature in highlightsOf(data, prefer: prefer, max: all.length)) {
      for (final label in labelsFor(feature.key, attrs, detailed: detailed)) {
        if (result.contains(label)) continue;
        result.add(label);
        if (result.length >= max) return result;
      }
    }
    return result;
  }

  // ── 문서 읽기 도우미 ──────────────────────────────────────────────────

  /// 특징 태그 — 새 데이터는 `themeTags`, 옛 문서는 단일 `category`.
  /// (main_screen의 `_placeThemeTags`와 같은 규칙이다.)
  static List<String> _themeTags(Map<String, dynamic> data) {
    final tags = (data['themeTags'] as List?)?.whereType<String>().toList();
    if (tags != null && tags.isNotEmpty) return tags;
    final legacy = data['category'] as String?;
    return legacy != null && legacy.isNotEmpty ? [legacy] : const [];
  }

  static PlaceFacilityOptions _facilities(Map<String, dynamic> data) {
    final raw = data['facilityOptions'];
    return raw is Map
        ? PlaceFacilityOptions.fromMap(Map<String, dynamic>.from(raw))
        : PlaceFacilityOptions.empty();
  }

  static PetPolicy _petPolicy(Map<String, dynamic> data) {
    final raw = data['petPolicy'];
    return raw is Map
        ? PetPolicy.fromMap(Map<String, dynamic>.from(raw))
        : PetPolicy.empty();
  }

  /// 운영시간 — 등록 화면이 두 필드에 같은 값을 쓰므로 둘 다 본다
  /// (main_screen의 `_eventWeeklyHours`와 같은 규칙).
  static PlaceWeeklyHours? weeklyHoursOf(Map<String, dynamic> data) {
    final raw =
        (data['placeWeeklyHours'] as Map?) ??
        (data['weeklyOperatingHours'] as Map?);
    if (raw == null || raw.isEmpty) return null;
    return PlaceWeeklyHours.fromMap(Map<String, dynamic>.from(raw));
  }

  static bool _anyDay(
    PlaceWeeklyHours hours,
    bool Function(PlaceDayHours) test,
  ) {
    for (final day in PlaceWeeklyHours.weekdays) {
      final d = hours.get(day);
      if (d == null || d.isClosed) continue;
      if (test(d)) return true;
    }
    return false;
  }

  /// 자정을 넘겨 여는 날인가 — 종료가 시작보다 이르거나 같으면 다음 날까지
  /// 여는 것이고, 00:00에 닫는 것도 자정까지 여는 것이다.
  static bool _isLateNight(PlaceDayHours d) {
    if (d.is24Hours) return true;
    final open = d.open.hour * 60 + d.open.minute;
    final close = d.close.hour * 60 + d.close.minute;
    return close <= open || close == 0;
  }
}
