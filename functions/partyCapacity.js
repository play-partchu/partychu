// 파티 참가 정원/자격 검증 + 참가비 계산 공통 헬퍼 — index.js(applyToParty/
// cancelApplication)와 packageBookings.js(숙박+파티 패키지 예약)가 동일한
// 로직을 공유한다. 원래 index.js의 applyToParty/cancelApplication 트랜잭션
// 본문에 있던 코드를 그대로 함수로 뽑아낸 것으로, 동작은 바뀌지 않는다.

const { HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

// 얼리버드 할인: earlyBirdEnabled/earlyBirdEndAt/earlyBirdDiscountPercent를
// 직접 읽어 신청 확정 시점의 실제 적용 금액(appliedFee)을 계산한다.
// (lib/utils/early_bird.dart의 계산 로직과 동일하게 유지해야 함)
function computeAppliedFee(data, gender) {
  let baseFee = 0;
  if (gender === 'male' && data.maleFee != null) baseFee = Number(data.maleFee);
  else if (gender === 'female' && data.femaleFee != null) baseFee = Number(data.femaleFee);
  else if (data.maleFee != null) baseFee = Number(data.maleFee);
  else if (data.femaleFee != null) baseFee = Number(data.femaleFee);
  else if (data.fee != null) baseFee = Number(data.fee);

  if (baseFee <= 0) return baseFee;
  if (data.earlyBirdEnabled !== true) return baseFee;

  const endAt = data.earlyBirdEndAt;
  if (!endAt || typeof endAt.toDate !== 'function') return baseFee;
  if (endAt.toDate().getTime() <= Date.now()) return baseFee; // 종료됨 → 정상가

  const pct = Number(data.earlyBirdDiscountPercent || 0);
  const discounted = Math.round(baseFee * (100 - pct) / 100);
  return discounted < 0 ? 0 : discounted;
}

// 다차수(1차/2차/3차) 파티의 "라운드별 정원" 모드에서, 선택한 라운드들의
// 참가비를 합산한다. 얼리버드 할인은 라운드별로 재적용하지 않는다(추후 필요
// 시 별도 작업).
function computeAppliedFeeForRounds(rounds, selectedRoundNumbers, gender) {
  return selectedRoundNumbers.reduce((sum, rn) => {
    const round = rounds.find((r) => r.roundNumber === rn);
    if (!round) return sum;
    const fee = gender === 'male' ? Number(round.maleFee || 0) : Number(round.femaleFee || 0);
    return sum + fee;
  }, 0);
}

// PartyChu는 환불률을 정하거나 권장하지 않는다 — 환불 규정은 전적으로 파티
// 등록/수정 시 호스트가 직접 입력한 refundPolicy 배열([{daysBefore, refundPercent}])을
// 그대로 따른다. 규정이 없거나(호스트 미설정) 해당 시점을 커버하는 구간이 없으면
// 환불 0%로 처리한다(임의로 유리하게/불리하게 추정하지 않음).
//
// 아직 실제 PG 환불 API가 연결되어 있지 않으므로, 여기서는 refundStatus를
// 'pending'으로 저장만 해두고 실제 환불 실행은 이후 PG 연동 시 이 필드를
// 구독/폴링하는 별도 처리로 연결하기 쉬운 구조로 남겨둔다.
function computeRefund(refundPolicy, appliedFee, partyDateTime) {
  if (!appliedFee || appliedFee <= 0) {
    return { refundPercent: 0, refundAmount: 0, refundStatus: 'not_applicable', matchedTier: null };
  }
  if (!Array.isArray(refundPolicy) || refundPolicy.length === 0) {
    return { refundPercent: 0, refundAmount: 0, refundStatus: 'pending', matchedTier: null };
  }
  if (!partyDateTime || typeof partyDateTime.toDate !== 'function') {
    return { refundPercent: 0, refundAmount: 0, refundStatus: 'pending', matchedTier: null };
  }

  const daysUntilParty =
    (partyDateTime.toDate().getTime() - Date.now()) / (1000 * 60 * 60 * 24);

  // daysBefore가 큰(더 관대한) 구간부터 확인해, 남은 일수가 그 구간의
  // daysBefore 이상이면 그 구간을 적용한다("N일 전"부터 적용되는 규정).
  const sorted = [...refundPolicy]
    .filter((t) => typeof t.daysBefore === 'number' && typeof t.refundPercent === 'number')
    .sort((a, b) => b.daysBefore - a.daysBefore);

  let matched = null;
  for (const tier of sorted) {
    if (daysUntilParty >= tier.daysBefore) {
      matched = tier;
      break;
    }
  }

  if (!matched) {
    return { refundPercent: 0, refundAmount: 0, refundStatus: 'pending', matchedTier: null };
  }

  const pct = Math.max(0, Math.min(100, matched.refundPercent));
  const amount = Math.round((appliedFee * pct) / 100);
  return { refundPercent: pct, refundAmount: amount, refundStatus: 'pending', matchedTier: matched };
}

// 파티 정원에 참가자 1명 자리를 "예약"한다 — 자격 검증(이미신청/모집상태/
// 마감일/연령제한/성별) + 정원 확인 + 카운터 증가분을 계산해서 돌려준다.
// 호출자는 이미 트랜잭션 안에서 partyRef를 읽어(partyData) 넘겨야 하고,
// 반환된 updateData로 transaction.update(partyRef, updateData)를 직접
// 호출해야 한다(이 함수 자체는 쓰기를 하지 않는 순수 계산 함수).
//
// applyToParty(정상 신청)와 createPendingPackageBooking(패키지 예약의 pending
// 단계 — 결제 전에 미리 자리를 선점) 양쪽에서 동일하게 쓴다.
function reserveApplicantSlot(partyData, { uid, gender, birthYear, selectedRounds }) {
  const data = partyData;
  const hasMultipleRounds = data.hasMultipleRounds === true;
  const roundCapacityMode = data.roundCapacityMode || 'unified';
  let roundsArr = null;
  let effectiveSelectedRounds = null;
  if (hasMultipleRounds) {
    roundsArr = Array.isArray(data.rounds) ? data.rounds : [];
    const validRoundNumbers = new Set(roundsArr.map((r) => r.roundNumber));
    const requested =
      Array.isArray(selectedRounds) && selectedRounds.length > 0
        ? selectedRounds
        : [1]; // 방어적 기본값 — UI는 항상 선택값을 보내야 함
    const invalid = requested.filter((n) => !validRoundNumbers.has(n));
    if (invalid.length > 0) {
      throw new HttpsError('invalid-argument', '존재하지 않는 라운드가 포함되어 있습니다.');
    }
    effectiveSelectedRounds = [...new Set(requested)].sort((a, b) => a - b);
  }

  const appliedFee =
    hasMultipleRounds && roundCapacityMode === 'perRound'
      ? computeAppliedFeeForRounds(roundsArr, effectiveSelectedRounds, gender)
      : computeAppliedFee(data, gender);

  if ((data.applicants || []).includes(uid)) {
    throw new HttpsError('already-exists', '이미신청');
  }

  if ((data.recruitStatus || '모집중') !== '모집중') {
    throw new HttpsError('failed-precondition', '마감');
  }

  if (data.recruitDeadlineAt && data.recruitDeadlineAt.toDate() < new Date()) {
    throw new HttpsError('failed-precondition', '마감');
  }

  if (data.ageRestrictionEnabled === true) {
    if (birthYear == null) throw new HttpsError('failed-precondition', '연령미인증');
    const min = data.minBirthYear != null ? Number(data.minBirthYear) : null;
    const max = data.maxBirthYear != null ? Number(data.maxBirthYear) : null;
    if (min != null && birthYear < min) throw new HttpsError('failed-precondition', '연령제한');
    if (max != null && birthYear > max) throw new HttpsError('failed-precondition', '연령제한');
  }

  const genderCapacityMode = data.genderCapacityMode || 'unlimited';
  let updateData;

  if (hasMultipleRounds && roundCapacityMode === 'perRound') {
    // 라운드별 정원 모드 — 성별 인증 필요(라운드마다 남녀 정원이 따로 있으므로).
    if (gender !== 'male' && gender !== 'female') {
      throw new HttpsError('failed-precondition', '미인증');
    }

    // Firestore 배열은 원소 하나만 원자적으로 증가시킬 수 없어서, 배열
    // 전체를 읽어(이미 트랜잭션에서 읽은 data.rounds) 메모리에서 선택된
    // 라운드들만 수정한 뒤 배열 통째로 다시 쓴다.
    const updatedRounds = roundsArr.map((r) => ({ ...r }));

    // 1단계: 선택한 라운드 전부에 자리가 있는지 먼저 검증 — 하나라도
    // 마감이면 여기서 throw해 트랜잭션 전체를 취소한다(부분 신청 방지).
    for (const rn of effectiveSelectedRounds) {
      const round = updatedRounds.find((r) => r.roundNumber === rn);
      const maleCapacity = Number(round.maleCapacity || 0);
      const femaleCapacity = Number(round.femaleCapacity || 0);
      const currentMale = Number(round.currentMaleCount || 0);
      const currentFemale = Number(round.currentFemaleCount || 0);
      if (gender === 'male' && currentMale >= maleCapacity) {
        throw new HttpsError('failed-precondition', '마감');
      }
      if (gender === 'female' && currentFemale >= femaleCapacity) {
        throw new HttpsError('failed-precondition', '마감');
      }
    }

    // 2단계: 검증을 통과했으니 선택한 라운드들의 카운터를 실제로 증가.
    for (const rn of effectiveSelectedRounds) {
      const round = updatedRounds.find((r) => r.roundNumber === rn);
      if (gender === 'male') round.currentMaleCount = Number(round.currentMaleCount || 0) + 1;
      if (gender === 'female') round.currentFemaleCount = Number(round.currentFemaleCount || 0) + 1;
      round.currentParticipants =
        Number(round.currentMaleCount || 0) + Number(round.currentFemaleCount || 0);
    }

    // 라운드를 모르는 기존 코드(피드 카드 등)를 위해 상단 정원 필드는
    // 라운드 전체 합계로 갱신한다.
    const aggMax = updatedRounds.reduce((s, r) => s + Number(r.maxCapacity || 0), 0);
    const aggCurrent = updatedRounds.reduce((s, r) => s + Number(r.currentParticipants || 0), 0);

    updateData = {
      rounds: updatedRounds,
      applicants: admin.firestore.FieldValue.arrayUnion(uid),
      maxParticipants: aggMax,
      maxCapacity: aggMax,
      currentParticipants: aggCurrent,
      people: `${aggCurrent}/${aggMax}명`,
    };
  } else if (genderCapacityMode === 'unlimited') {
    const current = Number(data.currentParticipants || 0);
    const max = Number(data.maxParticipants || data.maxCapacity || 0);
    const genderLimit = data.genderLimit || 'all';
    const currentMale = Number(data.currentMaleCount || 0);
    const currentFemale = Number(data.currentFemaleCount || 0);

    if (genderLimit === 'male' || genderLimit === 'female') {
      if (gender !== 'male' && gender !== 'female') {
        throw new HttpsError('failed-precondition', '미인증');
      }
      if (genderLimit !== gender) {
        throw new HttpsError('failed-precondition', '성별제한');
      }
    }

    if (max > 0 && current >= max) throw new HttpsError('failed-precondition', '마감');

    const newCount = current + 1;
    updateData = {
      currentParticipants: newCount,
      people: `${newCount}/${max}명`,
      applicants: admin.firestore.FieldValue.arrayUnion(uid),
    };
    if (genderLimit === 'male') updateData.currentMaleCount = currentMale + 1;
    if (genderLimit === 'female') updateData.currentFemaleCount = currentFemale + 1;
  } else {
    // 남녀별 정원 모드
    if (gender !== 'male' && gender !== 'female') {
      throw new HttpsError('failed-precondition', '미인증');
    }

    const maleCapacity = Number(data.maleCapacity || 0);
    const femaleCapacity = Number(data.femaleCapacity || 0);
    const currentMale = Number(data.currentMaleCount || 0);
    const currentFemale = Number(data.currentFemaleCount || 0);

    if (gender === 'male' && currentMale >= maleCapacity) {
      throw new HttpsError('failed-precondition', '마감');
    }
    if (gender === 'female' && currentFemale >= femaleCapacity) {
      throw new HttpsError('failed-precondition', '마감');
    }

    const newMale = gender === 'male' ? currentMale + 1 : currentMale;
    const newFemale = gender === 'female' ? currentFemale + 1 : currentFemale;
    const newTotal = newMale + newFemale;
    updateData = {
      currentParticipants: newTotal,
      people: `${newTotal}/${maleCapacity + femaleCapacity}명`,
      applicants: admin.firestore.FieldValue.arrayUnion(uid),
    };
    if (gender === 'male') updateData.currentMaleCount = newMale;
    if (gender === 'female') updateData.currentFemaleCount = newFemale;
  }

  return { updateData, appliedFee, effectiveSelectedRounds };
}

// reserveApplicantSlot의 역연산 — 정원 카운터를 되돌린다. 호출자가
// transaction.update(partyRef, updateData)를 직접 호출해야 한다(순수 계산
// 함수). cancelApplication(정상 취소)과 createPendingPackageBooking의 pending
// 홀드가 결제 전에 만료/취소될 때(expireStalePackageBookings, 결제 취소) 양쪽에서
// 동일하게 쓴다.
function releaseApplicantSlot(partyData, { uid, gender, selectedRounds }) {
  const genderCapacityMode = partyData.genderCapacityMode || 'unlimited';
  const updateData = {
    applicants: admin.firestore.FieldValue.arrayRemove(uid),
    approvedApplicants: admin.firestore.FieldValue.arrayRemove(uid),
    rejectedApplicants: admin.firestore.FieldValue.arrayRemove(uid),
  };

  const hasMultipleRounds = partyData.hasMultipleRounds === true;
  const roundCapacityMode = partyData.roundCapacityMode || 'unified';

  if (hasMultipleRounds && roundCapacityMode === 'perRound') {
    // reserveApplicantSlot의 라운드별 증가 로직을 그대로 역산한다.
    const roundsArr = Array.isArray(partyData.rounds) ? partyData.rounds : [];
    const updatedRounds = roundsArr.map((r) => ({ ...r }));
    const selected = Array.isArray(selectedRounds) ? selectedRounds : [];
    for (const rn of selected) {
      const round = updatedRounds.find((r) => r.roundNumber === rn);
      if (!round) continue; // 신청 이후 라운드가 사라진 경우(발생하지 않아야 함) 대비
      if (gender === 'male') {
        round.currentMaleCount = Math.max(0, Number(round.currentMaleCount || 0) - 1);
      }
      if (gender === 'female') {
        round.currentFemaleCount = Math.max(0, Number(round.currentFemaleCount || 0) - 1);
      }
      round.currentParticipants =
        Number(round.currentMaleCount || 0) + Number(round.currentFemaleCount || 0);
    }
    const aggMax = updatedRounds.reduce((s, r) => s + Number(r.maxCapacity || 0), 0);
    const aggCurrent = updatedRounds.reduce((s, r) => s + Number(r.currentParticipants || 0), 0);
    updateData.rounds = updatedRounds;
    updateData.maxParticipants = aggMax;
    updateData.maxCapacity = aggMax;
    updateData.currentParticipants = aggCurrent;
    updateData.people = `${aggCurrent}/${aggMax}명`;
  } else if (genderCapacityMode === 'unlimited') {
    const current = Math.max(0, Number(partyData.currentParticipants || 0) - 1);
    const max = Number(partyData.maxParticipants || partyData.maxCapacity || 0);
    updateData.currentParticipants = current;
    updateData.people = `${current}/${max}명`;
    const genderLimit = partyData.genderLimit || 'all';
    if (genderLimit === 'male') {
      updateData.currentMaleCount = Math.max(0, Number(partyData.currentMaleCount || 0) - 1);
    }
    if (genderLimit === 'female') {
      updateData.currentFemaleCount =
        Math.max(0, Number(partyData.currentFemaleCount || 0) - 1);
    }
  } else {
    const maleCapacity = Number(partyData.maleCapacity || 0);
    const femaleCapacity = Number(partyData.femaleCapacity || 0);
    let currentMale = Number(partyData.currentMaleCount || 0);
    let currentFemale = Number(partyData.currentFemaleCount || 0);
    if (gender === 'male') currentMale = Math.max(0, currentMale - 1);
    if (gender === 'female') currentFemale = Math.max(0, currentFemale - 1);
    const newTotal = currentMale + currentFemale;
    updateData.currentMaleCount = currentMale;
    updateData.currentFemaleCount = currentFemale;
    updateData.currentParticipants = newTotal;
    updateData.people = `${newTotal}/${maleCapacity + femaleCapacity}명`;
  }

  return updateData;
}

module.exports = {
  computeAppliedFee,
  computeAppliedFeeForRounds,
  computeRefund,
  reserveApplicantSlot,
  releaseApplicantSlot,
};
