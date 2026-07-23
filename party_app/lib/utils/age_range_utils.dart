/// 나이 ↔ 출생연도 변환 + 파티 대상 유형별 선택 가능 나이 범위.
///
/// 회원 본인확인 정보나 파티 연령 제한 모두 생년월일 전체가 아니라
/// "출생연도"만 저장하므로(`UserSession.birthYear`, `minBirthYear`/
/// `maxBirthYear`), 만 나이를 월/일까지 정밀하게 계산하지 않고 "현재 연도 -
/// 출생연도"로 근사한다 — 기존 저장 데이터의 정밀도와 동일한 수준이라
/// 새로운 오차를 만들지 않는다.
library;

/// 파티 대상 유형 — 연령 선택 가능 범위(하한/상한)가 유형별로 다르다.
///
/// 지금 파티 등록 화면에는 `audienceType`을 고르는 UI 자체가 없고, 항상
/// [adult]로 등록된다(연령대 설정 진입 경로: `party_register_screen.dart`
/// "연령대 설정" 행 → `showAgeRestrictionSheet` → `showAgePickerSheet`,
/// 아래 [partyAgeRangeFor] 참고). [youth]/[mixed]는 청소년 전용 파티 기능이
/// 실제로 만들어질 때 등록 화면에서 유형을 선택하게 하고 그 값을 그대로
/// 넘기면 되도록 미리 마련해 둔 자리 — 지금은 아무 화면도 이 값을 만들어
/// 넘기지 않는다.
enum PartyAudienceType {
  /// 성인 전용 — 현재 유일하게 실제 등록 흐름에서 쓰이는 유형.
  adult,

  /// 청소년 전용 — 아직 등록 화면에 연결되지 않음(추후 기능).
  youth,

  /// 성인·청소년 혼합 — 현재 허용하지 않음(추후에도 별도 정책 논의 필요).
  mixed,
}

class PartyAgeRange {
  final int minAge;
  final int maxAge;

  const PartyAgeRange({required this.minAge, required this.maxAge});
}

/// 유형별 선택 가능 나이 범위 — 하드코딩을 이 표 하나로 모아, 나중에
/// `audienceType`이 실제 등록 화면에 노출될 때 이 값만 조정하면 되게 한다.
///
/// - adult: 대한민국 법정 성년 기준 만 19세 이상.
/// - youth: 청소년보호법상 "청소년"은 만 19세 미만이므로 상한을 18세로
///   맞추고, 하한은 요청대로 우선 14세로 둔다(실제 청소년 전용 파티 기능을
///   만들 때 관련 법령·정책을 다시 검토해야 함 — 지금은 상한만 법 기준을
///   반영한 잠정값).
/// - mixed: 현재 허용하지 않는 유형이라 값 자체를 쓰지 않는다(호출부에서
///   이 유형으로 진입하지 못하게 막아야 함 — `partyAgeRangeFor`는 안전망으로
///   adult 범위를 반환한다).
const Map<PartyAudienceType, PartyAgeRange> _kAudienceAgeRanges = {
  PartyAudienceType.adult: PartyAgeRange(minAge: 19, maxAge: 80),
  PartyAudienceType.youth: PartyAgeRange(minAge: 14, maxAge: 18),
};

/// [audienceType]에 대응하는 선택 가능 나이 범위. [PartyAudienceType.mixed]는
/// 아직 허용되지 않는 유형이라 표에 없고, 안전망으로 성인 범위를 돌려준다 —
/// 혼합 유형을 실제로 열 때는 이 함수를 쓰기 전에 먼저 그 정책부터 정해야
/// 한다.
PartyAgeRange partyAgeRangeFor(PartyAudienceType audienceType) =>
    _kAudienceAgeRanges[audienceType] ?? _kAudienceAgeRanges[PartyAudienceType.adult]!;

int ageFromBirthYear(int birthYear) => DateTime.now().year - birthYear;

int birthYearFromAge(int age) => DateTime.now().year - age;
