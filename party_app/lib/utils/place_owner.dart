import 'package:firebase_auth/firebase_auth.dart';

import 'package:party_app/utils/user_session.dart';

// ══════════════════════════════════════════════════════════════════════════
// 플레이스(events / places) 소유자 판별
//
// ── 소유자 필드 조사 결과 ────────────────────────────────────────────────
// `events`·`places` 문서에 실제로 찍히는 소유자 필드는 **`hostId` 하나**다.
// `hostUid`는 `parties` 문서에만 쓰인다(파티 등록·콤보 등록 화면이 파티 쪽
// 문서에만 함께 저장한다).
//
// firestore.rules도 두 컬렉션 모두 같은 기준을 쓴다:
//
//   match /events/{eventId}   allow update, delete:
//       resource.data.hostId == uid() || isAdmin()
//   match /places/{placeId}   allow update / delete:
//       resource.data.hostId == uid() || isAdmin()
//
// 그래서 이 판정은 규칙과 정확히 같은 조건을 본다 — 화면에 버튼이 보이는
// 사용자는 서버에서도 쓰기가 허용되고, 그 반대도 성립한다. `hostUid`는
// 예전 문서가 그 필드만 갖고 있을 가능성에 대비한 **보조 조건**으로만 본다
// (규칙은 hostId만 보므로, hostUid로 통과해도 서버에서 막힌다 — 버튼을
// 넓게 열어주는 쪽이 아니라 좁게 유지하는 것이 목적이라 순서가 중요하다).
// ══════════════════════════════════════════════════════════════════════════

/// 지금 로그인한 사용자가 이 플레이스 문서를 수정할 수 있는지.
///
/// 비로그인이거나 데이터가 아직 없으면 false — 호출부는 이 값이 true일 때만
/// 수정 진입점을 노출한다.
bool canEditPlace(Map<String, dynamic>? data) {
  if (data == null || data.isEmpty) return false;

  // UserSession.userId가 아직 비어 있는 순간(앱 재시작 직후 등)이 있으므로
  // 소유자 비교는 항상 Firebase Auth uid를 정본으로 쓴다.
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  if (uid.isEmpty) return false;

  final hostId = (data['hostId'] as String?) ?? '';
  if (hostId.isNotEmpty && hostId == uid) return true;

  final hostUid = (data['hostUid'] as String?) ?? '';
  if (hostUid.isNotEmpty && hostUid == uid) return true;

  // 관리자도 규칙상 수정이 열려 있다(firestore.rules의 isAdmin()과 같은 기준).
  return UserSession.isAdmin;
}

/// 이 플레이스를 **내가 직접 등록**했는지 — 내 글을 내가 찜하는 건 의미가
/// 없어서 찜 버튼을 숨기는 데 쓴다.
///
/// [canEditPlace]와 달리 관리자는 포함하지 않는다. 관리자는 남의 플레이스도
/// 수정할 수 있어야 하지만, 남의 플레이스를 찜하는 것까지 막을 이유는 없다
/// — 두 판정을 하나로 합치면 관리자 계정에서 찜이 통째로 사라진다.
bool isMyPlace(Map<String, dynamic>? data) {
  if (data == null || data.isEmpty) return false;

  // canEditPlace와 같은 이유로 소유자 비교는 Firebase Auth uid를 정본으로 쓴다
  // (UserSession.userId는 앱 재시작 직후 잠깐 비어 있을 수 있다).
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  if (uid.isEmpty) return false;

  final hostId = (data['hostId'] as String?) ?? '';
  if (hostId.isNotEmpty && hostId == uid) return true;

  final hostUid = (data['hostUid'] as String?) ?? '';
  return hostUid.isNotEmpty && hostUid == uid;
}
