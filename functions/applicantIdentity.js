/**
 * 호스트에게 보여줄 **신청자 신원 한 벌**을 users 문서에서 만든다.
 *
 * 원래 index.js의 getApplicants 안에만 있던 코드를 그대로 꺼낸 것이다 —
 * 통합 신청자 관리(getHostApplicationInbox)가 같은 정보를 내려주게 되면서
 * 두 곳이 되었는데, 판정이 갈리면 "파티별 화면에는 실명이 뜨는데 통합
 * 목록에는 안 뜨는" 식으로 호스트가 보는 사실이 화면마다 달라진다.
 *
 * 규칙(원본 주석 그대로)
 * - 성별·생년월일은 **본인확인으로 확인된 값만** 쓴다. 프로필에서 임의로 고칠
 *   수 있는 값이나 신청 문서에 찍힌 옛 스냅샷을 쓰면 호스트가 보는 정보가
 *   사실과 달라진다.
 * - 나이는 내려보내지 않는다 — 한 번 계산해 저장하면 해가 바뀌어도 옛 나이가
 *   그대로 남는다. 화면이 생년월일로 그때그때 계산한다.
 * - 실명은 **호스트에게만** 나간다. 이 정보를 내려보내는 콜러블은 전부 맨 앞에서
 *   호스트 본인인지 확인하므로, 참가자끼리 서로의 실명을 볼 수 있는 경로는 없다.
 * - 탈퇴·삭제된 계정은 `{ available: false }` 하나로 끝난다. 화면은 이 값을
 *   '탈퇴한 회원'으로 그린다(applicant_identity.dart).
 *
 * @param {object|null} userData users/{uid} 문서 데이터. 문서가 없으면 null.
 * @returns {{identity: object, name: string, gender: string}}
 *   `name`·`gender`는 이 정보를 이미 쓰고 있는 옛 필드다(성별 뱃지 등).
 */
function buildApplicantIdentity(userData) {
  const u = userData || null;
  const name = u ? (u.name || '(이름 없음)') : '(알 수 없음)';

  const isWithdrawn = !u || u.accountStatus === 'withdrawn';
  const isVerified = !!u && u.identityVerified === true;
  const identity = isWithdrawn
    ? { available: false }
    : {
        available: true,
        // 본인확인 완료 여부를 **그대로** 내려보낸다.
        //
        // 화면이 "성별이 비어 있으면 미확인"으로 추측하던 것을 대신한다 —
        // 본인확인은 마쳤는데 성별이 비어 있는 계정이 하나라도 있으면 그 추측은
        // 틀린 답을 낸다. 호스트는 입장 확인 때 '본인확인 완료' 배지를 근거로
        // 신분증을 대조하므로, 그 배지만은 추측이 아니라 사실이어야 한다.
        verified: isVerified,
        nickname: u.nickname || '',
        name: isVerified ? (u.name || '') : '',
        gender: isVerified ? (u.gender || '') : '',
        birthYear: isVerified ? (u.birthYear ?? null) : null,
        birthMonth: isVerified ? (u.birthMonth ?? null) : null,
        birthDay: isVerified ? (u.birthDay ?? null) : null,
      };

  // 탈퇴한 회원이면 identity에 gender 자체가 없으므로 빈 문자열로 맞춘다.
  return { identity, name, gender: identity.gender || '' };
}

module.exports = { buildApplicantIdentity };
