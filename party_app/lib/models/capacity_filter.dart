/// 인원(최대 수용 인원) 필터의 **정본**.
///
/// 플레이스(events) 탭과 장소대여(places) 탭이 같은 버튼·같은 선택지·같은
/// 판정을 쓰도록 값 해석을 한 곳에 모았다. 두 탭이 각자 판정하면 같은 문서인데
/// 탭마다 결과가 달라진다.
///
/// ## 새 필드를 만들지 않는다
///
/// 최대 수용 인원의 정본은 이미 있다 — 장소대여 등록 화면이 **룸별
/// `capacityMax`의 최댓값**을 문서 최상단 `capacityMax`로 집계해 저장한다
/// (place_register_screen). 읽는 순서도 목록 카드([PlaceCardInfo])와 똑같이
/// 맞춰서, 카드에 '최대 20명'이라고 적힌 장소가 20명 필터에서 빠지는 일이
/// 없게 한다.
///
/// ## 값이 없으면 거르지 않는다
///
/// `capacityMax`가 0이거나 아예 없는 문서는 **"0명 수용"이 아니라 "호스트가
/// 인원을 입력하지 않음"**이다. 실제로 룸에 인원을 적지 않은 장소가 있고,
/// 플레이스(events)는 등록 화면에서 인원을 묻지도 않아 이 필드가 애초에
/// 없다. 그런 문서를 0명으로 취급해 숨기면 "인원 8명"을 고른 순간 멀쩡한
/// 장소들이 통째로 사라진다. 그래서 **모르면 통과시킨다**.
///
/// (장소대여 상세검색의 기존 `capacityRanges` 필터는 `capacity > 0` 조건이라
///  미입력 장소를 숨긴다 — 그쪽은 "10~20명" 같은 구간을 묻는 조건이라 값이
///  없으면 어느 구간에도 넣을 수 없기 때문이고, 이 필터와는 성격이 다르다.)
class CapacityFilter {
  CapacityFilter._();

  /// 고를 수 있는 가장 작은 인원 — 0명·음수는 뜻이 없다.
  static const int minPeople = 1;

  /// 고를 수 있는 가장 큰 인원.
  ///
  /// 판정이 `수용 인원 >= 고른 인원`이라 이 상한은 **사용자가 요청할 수 있는
  /// 인원**의 한계일 뿐, 장소가 가질 수 있는 수용 인원을 제한하지 않는다.
  /// 그래도 너무 낮게 잡으면 대형 공간을 찾는 사람이 막히므로, 실제 데이터에서
  /// 볼 수 있는 값보다 한참 위인 세 자리 끝까지 열어 둔다.
  static const int maxPeople = 999;

  // ── 게스트가 생각하는 인원 구간 ──────────────────────────────────
  //
  // 게스트는 '13명을 받는 곳'이 아니라 '우리 일행 11~20명이 들어가는 곳'을
  // 찾는다. 그래서 **표시만** 구간으로 정리한다 — 저장값도 판정도 예전
  // 그대로 정수 하나이고([matches]의 `수용 인원 >= 고른 인원`), 구간은
  // 그 정수를 읽기 좋게 부르는 이름일 뿐이다.
  //
  // 각 구간이 들고 있는 수는 **그 구간의 최대 인원**이다. '일행 전부가
  // 들어가야 한다'가 이 필터의 뜻이라, 5~10명 일행에게는 10명을 받을 수
  // 있는 곳을 찾아 주는 것이 맞다. 마지막 구간만 위가 열려 있어 50명을
  // '넘는' 51로 둔다 — 정확히 50명인 일행은 '21~50명'에 속한다.
  //
  // ⚠️ 이 수들을 바꾸면 이미 저장된 필터가 다른 구간 이름으로 보인다.
  //    (필터 결과 자체는 달라지지 않는다 — 판정은 언제나 정수 비교다.)
  static const List<({String label, int people})> presets = [
    (label: '4명 이하', people: 4),
    (label: '5~10명', people: 10),
    (label: '11~20명', people: 20),
    (label: '21~50명', people: 50),
    (label: '50명+', people: 51),
  ];

  /// 이 인원이 구간 버튼 중 하나와 정확히 같으면 그 구간, 아니면 null.
  static String? presetLabel(int people) {
    for (final p in presets) {
      if (p.people == people) return p.label;
    }
    return null;
  }

  /// 버튼·칩에 쓰는 표기 — '7명'. **어떤 숫자든 같은 방식으로** 적는다.
  ///
  /// 구간 이름('11~20명')을 여기 쓰지 않는 이유: 20과 21이 나란히 존재하는데
  /// 20에만 구간 이름이 붙으면 "20명 이상"이라는 **다른 뜻**으로 읽힌다
  /// (판정은 어느 값이든 똑같이 `>=`다). 예전 고정 버튼 시절 마지막
  /// 선택지에만 '20명+'를 붙였다가 같은 이유로 걷어낸 이력이 있고,
  /// `test/capacity_filter_test.dart`가 그 계약을 고정하고 있다.
  ///
  /// 구간은 **고르는 순간에만** 보여준다 — [presets]를 쓰는 인원 선택
  /// 시트의 지름길 버튼이 그 자리다.
  static String label(int people) => '$people명';

  /// 입력값을 유효한 인원으로 다듬는다 — 범위를 벗어나면 끝값으로 당긴다.
  static int clamp(int people) => people < minPeople
      ? minPeople
      : (people > maxPeople ? maxPeople : people);

  /// 사용자가 적어 넣은 문자열을 인원으로 읽는다.
  /// 숫자가 아니거나 0·음수면 null — 호출부는 '적용'을 막는다.
  static int? parse(String raw) {
    final n = int.tryParse(raw.trim());
    if (n == null || n < minPeople) return null;
    return n > maxPeople ? maxPeople : n;
  }

  /// 문서의 최대 수용 인원. 값이 없으면 0(= 모름).
  ///
  /// 읽는 순서는 목록 카드와 동일하다 — 룸 스키마 `capacityMax`, 구 스키마
  /// `capacity` / `maxCapacity`.
  static int capacityOf(Map<String, dynamic> data) =>
      (data['capacityMax'] as num?)?.toInt() ??
      (data['capacity'] as num?)?.toInt() ??
      (data['maxCapacity'] as num?)?.toInt() ??
      0;

  /// 이 장소가 [minPeople]명을 받을 수 있는가.
  ///
  /// - [minPeople]이 null이면 조건이 없는 것이라 항상 true.
  /// - 인원을 모르는 장소(0)는 **거르지 않는다**(위 설명 참고).
  /// - 그 외에는 `최대 수용 인원 >= 고른 인원`.
  static bool matches(Map<String, dynamic> data, int? minPeople) {
    if (minPeople == null) return true;
    final capacity = capacityOf(data);
    if (capacity <= 0) return true; // 모름 → 숨기지 않는다
    return capacity >= minPeople;
  }
}
