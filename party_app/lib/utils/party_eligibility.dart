enum PartyEligibility { eligible, ageLimited, genderLimited, genderCapacityFull }

/// 사용자의 본인확인 정보(성별/생년월일)를 기준으로 신청 가능 여부를 반환합니다.
/// 검사 순서: 성별 제한 → 연령 제한 → 성비 맞춤 정원
PartyEligibility checkPartyEligibility(
  Map<String, dynamic> partyData,
  String? userGender,
  int? userBirthYear,
) {
  final genderLimit = partyData['genderLimit'] as String? ?? 'all';
  if (genderLimit == 'male' && userGender != 'male') return PartyEligibility.genderLimited;
  if (genderLimit == 'female' && userGender != 'female') return PartyEligibility.genderLimited;

  final ageRestrictionEnabled = partyData['ageRestrictionEnabled'] as bool? ?? false;
  if (ageRestrictionEnabled) {
    final minBirthYear = (partyData['minBirthYear'] as num?)?.toInt();
    final maxBirthYear = (partyData['maxBirthYear'] as num?)?.toInt();
    if (userBirthYear == null) return PartyEligibility.ageLimited;
    if (minBirthYear != null && userBirthYear < minBirthYear) return PartyEligibility.ageLimited;
    if (maxBirthYear != null && userBirthYear > maxBirthYear) return PartyEligibility.ageLimited;
  }

  final genderCapacityMode = partyData['genderCapacityMode'] as String? ?? 'unlimited';
  if (genderCapacityMode == 'separate') {
    if (userGender == 'male') {
      final maleCapacity = (partyData['maleCapacity'] as num?)?.toInt() ?? 0;
      final currentMale = (partyData['currentMaleCount'] as num?)?.toInt() ?? 0;
      if (maleCapacity > 0 && currentMale >= maleCapacity) return PartyEligibility.genderCapacityFull;
    } else if (userGender == 'female') {
      final femaleCapacity = (partyData['femaleCapacity'] as num?)?.toInt() ?? 0;
      final currentFemale = (partyData['currentFemaleCount'] as num?)?.toInt() ?? 0;
      if (femaleCapacity > 0 && currentFemale >= femaleCapacity) return PartyEligibility.genderCapacityFull;
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
  }
}
