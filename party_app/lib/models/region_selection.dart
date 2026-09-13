import 'package:party_app/models/region_data.dart';

/// 시/도 + 구/시/군 **다중 선택**의 선택값 규격과 토글 규칙을 한곳에 모은 것.
///
/// 지역 목록 자체는 [RegionData]가 이미 중앙 관리하고 있어서 여기서 다시
/// 나열하지 않는다. 이 클래스는 "그 목록에서 고른 결과를 어떤 문자열로
/// 담고, 어떻게 켜고 끄고, 주소와 어떻게 대조하는가"만 책임진다 —
/// 장소대여 상단 퀵 지역 필터와 상세검색 지역 아코디언이 같은 규칙을
/// 쓰도록 하기 위함이다(둘 중 한쪽에만 규칙이 생기면 곧 어긋난다).
///
/// 선택값(키) 형식은 두 가지뿐이다.
/// - `'서울'`        → 서울 **전체**
/// - `'서울 강남구'` → 서울 강남구
class RegionSelection {
  RegionSelection._();

  /// 한 번에 고를 수 있는 지역 수.
  static const int maxCount = 5;

  /// 더 못 고를 때 보여주는 안내 문구.
  static const String maxReachedMessage = '지역은 최대 $maxCount개까지 선택할 수 있어요.';

  /// 시/도 전체를 뜻하는 키.
  static String cityKey(String city) => city;

  /// 특정 구/시/군을 뜻하는 키.
  static String districtKey(String city, String district) => '$city $district';

  /// 키가 가리키는 시/도.
  static String cityOf(String key) {
    final i = key.indexOf(' ');
    return i < 0 ? key : key.substring(0, i);
  }

  /// 키가 가리키는 구/시/군. 시/도 전체 선택이면 null.
  static String? districtOf(String key) {
    final i = key.indexOf(' ');
    return i < 0 ? null : key.substring(i + 1);
  }

  /// 시/도 전체 선택인지.
  static bool isWholeCity(String key) => !key.contains(' ');

  /// 어디에 붙어도 뜻이 통하는 표기 — '서울 전체' / '서울 강남구'.
  /// (키를 그대로 쓰면 '서울'이 구 이름처럼 보여서 전체 선택인지 헷갈린다.)
  static String label(String key) => isWholeCity(key) ? '$key 전체' : key;

  /// 시/도가 문맥상 이미 드러난 좁은 자리(선택 칩 등)용 짧은 표기 —
  /// '서울 전체' / '강남구'.
  static String shortLabel(String key) => districtOf(key) ?? '$key 전체';

  /// 선택된 것들 중 [city]에 속하는 개수(시/도 전체 선택도 1개로 센다).
  static int countInCity(Iterable<String> selection, String city) =>
      selection.where((k) => cityOf(k) == city).length;

  /// 지역 하나를 켜고 끈다.
  ///
  /// 같은 시/도 안에서 '전체'와 개별 구/시/군이 동시에 남지 않도록 정리한다 —
  /// '서울 전체'를 고르면 서울의 개별 구 선택은 모두 지우고, 반대로 개별 구를
  /// 고르면 '서울 전체'를 해제한다(의미가 겹치는 선택은 사용자에게도,
  /// 매칭 로직에도 혼란만 준다).
  ///
  /// 정리하고 난 결과가 [max]개를 넘으면 **아무것도 바꾸지 않고 false**를
  /// 돌려준다 — 호출부가 "최대 N개" 안내를 띄운다. 이미 고른 것을 해제하는
  /// 동작은 절대 막지 않는다.
  static bool toggle(Set<String> selection, String key, {int max = maxCount}) {
    if (selection.remove(key)) return true;

    final city = cityOf(key);
    // 겹치는 선택을 먼저 걷어낸 다음 개수를 따진다 — '서울 강남구/송파구'를
    // 고른 상태에서 '서울 전체'로 바꾸는 건 개수가 오히려 줄어드는 동작이라
    // 한도에 걸려 막히면 안 된다.
    final next = {...selection};
    if (isWholeCity(key)) {
      next.removeWhere((k) => k != key && cityOf(k) == city);
    } else {
      next.remove(cityKey(city));
    }
    if (next.length + 1 > max) return false;

    next.add(key);
    selection
      ..clear()
      ..addAll(next);
    return true;
  }

  /// [key]를 새로 고를 수 있는지 — 한도에 걸려 막히는 선택이면 false.
  /// 이미 고른 지역은 (해제할 수 있으므로) 항상 true.
  static bool canSelect(
    Iterable<String> selection,
    String key, {
    int max = maxCount,
  }) {
    if (selection.contains(key)) return true;
    final city = cityOf(key);
    final kept = isWholeCity(key)
        ? selection.where((k) => cityOf(k) != city)
        : selection.where((k) => k != cityKey(city));
    return kept.length + 1 <= max;
  }

  /// 주소 문자열이 지역 키 하나에 해당하는지.
  ///
  /// 시/도 전체 선택은 예전부터 쓰던 "주소에 시/도 이름이 들어있나"를 그대로
  /// 유지한다. 구/시/군까지 고른 경우에는 구 이름만 보면 다른 시/도의 동명
  /// 구(중구·서구·강서구 등)까지 걸리므로 시/도까지 함께 확인한다.
  static bool matchesAddress(String address, String key) {
    if (address.isEmpty) return false;
    final city = cityOf(key);
    final district = districtOf(key);
    if (district == null) return address.contains(city);
    if (!address.contains(district)) return false;
    if (address.contains(city)) return true;
    // '전라북도 전주시'처럼 축약형이 안 들어간 주소는 정식 명칭을 축약해
    // 다시 대조한다.
    return RegionData.extractRegion(RegionData.shortenRegionPrefix(address)) ==
        city;
  }

  /// 고른 지역 중 하나라도 주소에 해당하면 통과(OR). 고른 게 없으면 통과.
  static bool matchesAnyAddress(String address, Iterable<String> selection) {
    if (selection.isEmpty) return true;
    return selection.any((key) => matchesAddress(address, key));
  }
}
