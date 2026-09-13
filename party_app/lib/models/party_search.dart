import 'package:party_app/models/party_constants.dart';

/// 파티 목록 **검색어 매칭의 정본**.
///
/// 상단 검색창 한 칸이 찾는 범위가 여기 전부 들어 있다 —
///
///   · 제목 (`title`)
///   · 장소 (`placeName` · `location` · `address` · `roadAddress` ·
///     `jibunAddress` · `detailAddress` · `district`)
///   · 키워드 (`description` · `partyTypes` · `vibes`, 유형은 화면 표기까지)
///   · **태그** (`tags`)
///
/// ## 왜 태그가 여기 있나
///
/// 예전에는 상세검색에 '태그' 카드가 따로 있었다. 그런데 태그는 원래부터 이
/// 검색창에서도 걸렸기 때문에, 같은 것을 묻는 자리가 둘이었다 — 검색창에
/// 태그명을 쳐도 나오고, 카드에 넣어도 나왔다. 그래서 카드를 없애고 입구를
/// 검색창 하나로 모았다.
///
/// **조건 자체는 없애지 않았다.** `PartyFilter.tagKeywords`와 그 판정은 그대로
/// 남아 있어서, 예전에 걸어 둔 태그 조건은 계속 걸러 주고 선택 칩에서 뺄 수
/// 있다. 여기서 하는 일은 "검색어가 태그에도 걸리는가"뿐이다.
///
/// ## 왜 장소 필드가 이렇게 많나
///
/// 힌트에 '장소'라고 적혀 있는데 실제로는 제목만 찾고 있었다. 파티 문서는
/// 등록 화면이 장소명과 주소를 따로 저장하고, 주소도 도로명·지번·표시용이
/// 섞여 있다([RegionData.formatCardLocation]가 카드에 지역을 적을 때 보는
/// 목록과 같다). 하나만 보면 "적어 놓은 대로 쳤는데 안 나오는" 검색이 된다.
///
/// 판정 규칙은 다른 탭의 검색(main_screen의 `_matchesTextQuery`)과 같다 —
/// 대소문자 무시, 앞의 `#` 제거, 부분 일치.
bool partySearchMatches(Map<String, dynamic> data, String query) {
  if (query.isEmpty) return true;
  final q = query.toLowerCase().replaceFirst('#', '');

  for (final field in _textFields) {
    final value = data[field];
    if (value is String && value.toLowerCase().contains(q)) return true;
  }

  for (final field in _listFields) {
    final value = data[field];
    if (value is List &&
        value.any((e) => e is String && e.toLowerCase().contains(q))) {
      return true;
    }
  }

  // 파티 유형은 저장값과 화면 표기가 다르다 — 화면에 적힌 그대로 쳐도 찾을 수
  // 있어야 한다(저장값 대조만으로는 안 나온다).
  final types = (data['partyTypes'] as List?)?.cast<String>() ?? const [];
  if (types.any((t) => PartyConstants.labelFor(t).toLowerCase().contains(q))) {
    return true;
  }

  // 분위기도 같다 — 저장값('💃 춤')과 화면 표기('🤸 춤')가 갈라진 값이 있다.
  final vibes = (data['vibes'] as List?)?.cast<String>() ?? const [];
  if (vibes.any(
    (v) => PartyConstants.vibeLabelFor(v).toLowerCase().contains(q),
  )) {
    return true;
  }

  return false;
}

const List<String> _textFields = [
  'title',
  'description',
  // ── 장소 ──
  'placeName',
  'location',
  'address',
  'roadAddress',
  'jibunAddress',
  'detailAddress',
  'district',
];

const List<String> _listFields = ['partyTypes', 'vibes', 'tags'];
