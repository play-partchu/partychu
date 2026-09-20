import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/place_taxonomy.dart';

/// 파티 외 콘텐츠(플레이스·장소대여·파티샵·파트너)의 검색어 매칭 정본.
///
/// 판정 규칙은 파티의 [partySearchMatches]와 같다(대소문자 무시, 앞의 '#'
/// 제거, 부분 일치). 컬렉션마다 제목·주소 필드 이름이 제각각(name/title,
/// address/roadAddress/location …)이라 **후보 필드를 전부 훑는** 한 벌을
/// 목록 탭과 지도 홈이 함께 쓴다(예전에는 main_screen 안에만 있었다).
bool listingTextMatches(Map<String, dynamic> data, String query) {
  if (query.isEmpty) return true;
  final q = query.toLowerCase().replaceFirst('#', '');
  const textFields = [
    'name',
    'title',
    'description',
    'intro',
    'address',
    'roadAddress',
    'location',
    'region',
    'type',
    'category',
    'role',
    'hostName',
  ];
  for (final field in textFields) {
    final value = data[field];
    if (value is String && value.toLowerCase().contains(q)) return true;
  }
  const listFields = [
    'themeTags',
    'tags',
    'categories',
    'businessTypes',
    'placeTypes',
    'facilities',
    // 장소대여 등록 화면이 실제로 쓰는 필드 — 옛 'facilities'만 훑고 있어
    // '주차'·'수영장'처럼 화면에 적힌 시설명으로 검색해도 안 나왔다.
    'commonFacilities',
    'regions',
    'roles',
  ];
  for (final field in listFields) {
    final value = data[field];
    if (value is List &&
        value.any((e) => e is String && e.toLowerCase().contains(q))) {
      return true;
    }
  }
  // 특징 태그는 **화면 표기로도** 찾을 수 있어야 한다 — 저장값은 '이벤트'인데
  // 사용자가 보는 문구는 '이벤트 진행중'이라, 위 루프(저장값 대조)만으로는
  // 화면에 적힌 그대로 검색했을 때 아무것도 안 나온다.
  final themeTags = (data['themeTags'] as List?)?.cast<String>();
  if (themeTags != null &&
      themeTags.any(
        (t) => ListingConstants.placeThemeTagLabel(t).toLowerCase().contains(q),
      )) {
    return true;
  }
  // 대분류도 **화면에 적힌 그대로** 찾을 수 있어야 한다 — 저장값과 부르는
  // 이름이 다른 칸이 있다('체험·클래스' → '체험/클래스', '맛집' → '푸드').
  // 저장값·화면 이름·짧은 표기·옛 이름을 한 줄로 훑는다.
  final category = PlaceTaxonomy.categoryOf(data);
  if (category != null) {
    final c = PlaceTaxonomy.byLabel(category);
    final names = <String>[
      category,
      if (c != null) ...[c.displayName, c.shortLabel, ...c.aliases],
    ];
    if (names.any((n) => n.toLowerCase().contains(q))) return true;
  }
  // 이벤트 소분류도 검색 대상 — 상세에 보이는 문구다(없는 문서는 건너뛴다).
  final subtype = data['eventSubtype'];
  if (subtype is String && subtype.toLowerCase().contains(q)) return true;
  return false;
}
