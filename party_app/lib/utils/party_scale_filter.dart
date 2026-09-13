import 'package:party_app/widgets/party_card_widget.dart';

/// 파티 상세검색의 **파티 규모 필터** — "이 파티가 몇 명을 모으는 파티인가".
///
/// ## 남은 자리가 아니라 정원이다
///
/// 예전 이 자리에는 '인원' 필터가 있었고 "우리 N명이 지금 신청할 수 있는
/// 파티"를 뜻했다 — 남은 자리·모집 마감을 함께 보는 조건이었다. 그건 게스트가
/// 이 칸에서 묻는 것과 다르다. 여기서 고르는 수는 **일행 수도 잔여석도 아니고
/// 파티의 크기**다("소규모 모임이냐 대형 파티냐").
///
/// 그래서 이 필터는 **최대 모집 인원 하나만** 본다.
///
///   · 현재 신청자 수 → 안 본다
///   · 남은 자리      → 안 본다
///   · 모집 마감 여부 → 안 본다
///
/// 그 조건들은 '내가 참여 가능한 파티만 보기'가 이미 맡고 있다(성별·연령·
/// 잔여석·모집상태). 두 필터는 묻는 것이 달라서 섞으면 안 된다 — 섞으면
/// "51~100명 파티"를 찾는 사람에게 마감된 대형 파티가 사라져, 규모로 훑어보는
/// 일 자체가 불가능해진다.
///
/// ## 정본은 이미 있다 — 새 필드를 만들지 않는다
///
/// 최대 모집 인원은 [PartyCard.maxParticipants]가 정본이다. 카드에 찍히는
/// "3 / 10명"의 오른쪽 숫자, 상세 화면의 모집 인원, 그리고 등록 화면이 저장하는
/// 값이 전부 이 함수 하나를 지난다.
///
///   · 성비 맞춤(`genderCapacityMode == 'separate'`)
///       → `maleCapacity + femaleCapacity`
///   · 그 외 → `maxParticipants` ?? `maxCapacity`
///
/// 등록 화면(party_registration_data)은 같은 값을 `maxCapacity`와
/// `maxParticipants` 두 이름으로 함께 쓰므로, 둘 중 하나만 가진 옛 문서도
/// 위 순서에서 그대로 읽힌다. **마이그레이션이 필요 없다.**
///
/// ## 규모를 모르는 파티
///
/// 구간 필터는 값이 없으면 어느 구간에도 넣을 수 없다 — '2~5명'과 '51~100명'에
/// 동시에 넣을 수는 없기 때문이다. 그래서 정원이 0이거나 없는 문서는 구간을
/// 고르는 동안 빠진다(장소대여 상세검색의 `capacityRanges`와 같은 태도다).
/// 등록 화면이 모집 인원을 필수로 받으므로([PartyRegistrationData.validate]가
/// `maxCapacity <= 0`을 막는다) 실제로 걸리는 문서는 없다시피 하고, 조건을
/// 끄면(=전체) 예전과 똑같이 전부 보인다.
class PartyScaleFilter {
  PartyScaleFilter._();

  /// 상세검색에서 고를 수 있는 규모 구간. 순서가 곧 화면 순서다.
  ///
  /// 경계는 서로 겹치지 않는다 — 5명은 첫 구간, 10명은 둘째, 20명은 셋째,
  /// 50명은 넷째, 100명은 다섯째, 101명부터 마지막이다.
  ///
  /// ⚠️ [id]는 고른 조건을 가리키는 값이라 바꾸지 않는다(라벨만 바꾼다).
  static const List<PartyScaleRange> options = [
    PartyScaleRange(id: '2-5', label: '2~5명', min: 2, max: 5),
    PartyScaleRange(id: '6-10', label: '6~10명', min: 6, max: 10),
    PartyScaleRange(id: '11-20', label: '11~20명', min: 11, max: 20),
    PartyScaleRange(id: '21-50', label: '21~50명', min: 21, max: 50),
    PartyScaleRange(id: '51-100', label: '51~100명', min: 51, max: 100),
    PartyScaleRange(id: '100+', label: '100명 이상', min: 101),
  ];

  /// id로 구간 찾기 — 모르는 값이면 null.
  static PartyScaleRange? byId(String? id) {
    if (id == null) return null;
    for (final r in options) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// 버튼·칩·요약에 쓰는 표기 — '11~20명'. 모르는 값이면 그대로 돌려준다.
  static String label(String id) => byId(id)?.label ?? id;

  /// 이 파티의 **최대 모집 인원**. 없으면 0(= 모름).
  /// 카드·상세와 같은 함수를 쓰므로 화면마다 다른 수가 나올 수 없다.
  static int capacityOf(Map<String, dynamic> data) =>
      PartyCard.maxParticipants(data);

  /// 이 파티의 규모가 고른 구간에 드는가.
  ///
  /// - [rangeId]가 null이거나 모르는 값이면 조건이 없는 것이라 항상 true.
  /// - 정원을 모르는 파티(0)는 어느 구간에도 들지 않는다(위 설명 참고).
  /// - 그 외에는 `구간 최소 <= 최대 모집 인원 <= 구간 최대`.
  static bool matches(Map<String, dynamic> data, String? rangeId) {
    final range = byId(rangeId);
    if (range == null) return true;
    final capacity = capacityOf(data);
    if (capacity <= 0) return false;
    return range.contains(capacity);
  }
}

/// 규모 구간 하나 — 위가 열린 마지막 구간만 [max]가 null이다.
class PartyScaleRange {
  const PartyScaleRange({
    required this.id,
    required this.label,
    required this.min,
    this.max,
  });

  /// 고른 조건을 가리키는 값. 배포 후 변경 금지.
  final String id;

  /// 화면 표기 — '21~50명'.
  final String label;

  /// 이 구간에 드는 가장 작은 모집 인원(포함).
  final int min;

  /// 이 구간에 드는 가장 큰 모집 인원(포함). null이면 위가 열려 있다.
  final int? max;

  /// 경계는 양 끝을 포함한다 — 20명은 '11~20명'이고 '21~50명'이 아니다.
  bool contains(int people) {
    if (people < min) return false;
    final upper = max;
    return upper == null || people <= upper;
  }
}
