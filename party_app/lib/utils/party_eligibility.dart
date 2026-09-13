import 'package:party_app/models/party_age_restriction.dart';
import 'package:party_app/models/party_gender_recruit.dart';
import 'package:party_app/models/party_occurrence_recruit.dart';

enum PartyEligibility {
  eligible,
  ageLimited,
  genderLimited,
  genderCapacityFull,

  /// 호스트가 **내 성별의 모집만** 닫아 뒀다 — 파티 전체는 아직 모집중이다
  /// ([PartyGenderRecruit]). 정원이 찼다는 뜻이 아니라 호스트가 직접 내린
  /// 상태라, 자리가 남아 있어도 신청할 수 없다.
  maleRecruitClosed,
  femaleRecruitClosed,
}

/// 사용자의 본인확인 정보(성별/생년월일)를 기준으로 신청 가능 여부를 반환합니다.
/// 검사 순서: 성별 제한 → 성별 모집 상태 → 연령 제한 → 성비 맞춤 정원
///
/// 성별 모집 상태는 호스트가 남/여를 따로 열고 닫는 설정이다
/// ([PartyGenderRecruit]) — '남성 모집마감 + 여성 모집중'이면 남성만 여기서
/// 걸리고 여성은 그대로 통과한다. 파티 **전체**의 모집 상태(recruitStatus·
/// 마감 시각·오픈예정)는 여기서 보지 않는다 — 그건 예전 그대로
/// [PartyCard.effectiveStatus] 쪽 판정이다.
///
/// 연령 제한은 **성별별**이라 자기 성별의 범위만 본다(남성 25~35 / 여성
/// 23~32이면 24세 남성은 불가, 24세 여성은 가능). 성별 필드가 없는 기존 파티는
/// 옛 공통 범위를 남녀 모두에게 적용한다 — [PartyAgeRestriction] 참고.
///
/// **이 판정은 화면 표시용이다.** 실제 차단은 서버(reserveApplicantSlot)가
/// 같은 규칙으로 한다 — 콜러블을 직접 불러도 우회되지 않는다.
/// [occurrenceId]는 **정기 파티에서 어느 회차를 묻는지**다. 호스트가 회차마다
/// 성별 모집을 따로 닫을 수 있어서([PartyOccurrenceRecruit]), 회차를 알면 그
/// 회차의 값으로 판정한다. 넘기지 않으면 예전 그대로 문서 값이다 — 회차 칸이
/// 없는 파티는 어느 쪽이든 결과가 같다.
PartyEligibility checkPartyEligibility(
  Map<String, dynamic> partyData,
  String? userGender,
  int? userBirthYear, {
  String? occurrenceId,
}) {
  final genderLimit = partyData['genderLimit'] as String? ?? 'all';
  if (genderLimit == 'male' && userGender != 'male') {
    return PartyEligibility.genderLimited;
  }
  if (genderLimit == 'female' && userGender != 'female') {
    return PartyEligibility.genderLimited;
  }

  // 성별별 모집 상태 — 성별을 모르는 사용자(비로그인·미인증)는 여기서 걸리지
  // 않는다(isClosedFor가 양쪽 다 닫힌 파티에서만 참이고, 그 경우는 이미
  // 공통 상태가 '모집마감'이다). 로그인 유도는 호출부가 예전 그대로 한다.
  if (userGender == 'male' &&
      PartyOccurrenceRecruit.isMaleClosed(
        partyData,
        occurrenceId: occurrenceId,
      )) {
    return PartyEligibility.maleRecruitClosed;
  }
  if (userGender == 'female' &&
      PartyOccurrenceRecruit.isFemaleClosed(
        partyData,
        occurrenceId: occurrenceId,
      )) {
    return PartyEligibility.femaleRecruitClosed;
  }

  final age = PartyAgeRestriction.fromMap(partyData);
  if (!age.allows(userGender, userBirthYear)) {
    return PartyEligibility.ageLimited;
  }

  final genderCapacityMode =
      partyData['genderCapacityMode'] as String? ?? 'unlimited';
  if (genderCapacityMode == 'separate') {
    if (userGender == 'male') {
      final maleCapacity = (partyData['maleCapacity'] as num?)?.toInt() ?? 0;
      final currentMale = (partyData['currentMaleCount'] as num?)?.toInt() ?? 0;
      if (maleCapacity > 0 && currentMale >= maleCapacity) {
        return PartyEligibility.genderCapacityFull;
      }
    } else if (userGender == 'female') {
      final femaleCapacity =
          (partyData['femaleCapacity'] as num?)?.toInt() ?? 0;
      final currentFemale =
          (partyData['currentFemaleCount'] as num?)?.toInt() ?? 0;
      if (femaleCapacity > 0 && currentFemale >= femaleCapacity) {
        return PartyEligibility.genderCapacityFull;
      }
    }
  }

  return PartyEligibility.eligible;
}

String eligibilityLabel(PartyEligibility eligibility) {
  switch (eligibility) {
    case PartyEligibility.eligible:
      return '신청 가능';
    case PartyEligibility.ageLimited:
      return '🔒 연령 제한';
    case PartyEligibility.genderLimited:
      return '🔒 성별 제한';
    case PartyEligibility.genderCapacityFull:
      return '🔒 해당 성별 마감';
    case PartyEligibility.maleRecruitClosed:
      return '🔒 ${PartyGenderRecruit.maleClosedLabel}';
    case PartyEligibility.femaleRecruitClosed:
      return '🔒 ${PartyGenderRecruit.femaleClosedLabel}';
  }
}

String eligibilityReason(PartyEligibility eligibility) {
  switch (eligibility) {
    case PartyEligibility.eligible:
      return '';
    case PartyEligibility.ageLimited:
      return '연령 조건에 맞지 않아 신청할 수 없습니다.';
    case PartyEligibility.genderLimited:
      return '성별 조건에 맞지 않아 신청할 수 없습니다.';
    case PartyEligibility.genderCapacityFull:
      return '해당 성별 정원이 마감되어 신청할 수 없습니다.';
    case PartyEligibility.maleRecruitClosed:
      return '남성 모집이 마감되어 신청할 수 없습니다.';
    case PartyEligibility.femaleRecruitClosed:
      return '여성 모집이 마감되어 신청할 수 없습니다.';
  }
}
