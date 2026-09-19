import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:party_app/services/block_service.dart';
import 'package:party_app/services/pre_registration_visibility.dart';
import 'package:party_app/widgets/party_card_widget.dart';

/// 공개 목록에 노출되는 **세 종류 콘텐츠의 정본 데이터 소스**.
///
/// 파티 목록(메인 탭)·플레이스 목록·장소대여 목록, 그리고 통합 지도가 모두
/// 여기를 거친다. 지도용 컬렉션을 따로 만들지 않고 목록과 **같은 쿼리 + 같은
/// 노출 판정**을 쓰기 위한 곳이다 — 삭제됨/비공개 콘텐츠가 목록에서는 빠졌는데
/// 지도에만 남는 일을 구조적으로 막는다.
///
/// ⚠️ 쿼리를 여기서만 만드는 것이 핵심이다. 컬렉션 이름이나 서버측 필터를
/// 호출부에서 다시 쓰면 두 화면이 곧 어긋난다(플레이스의 `isActive` 서버
/// 필터처럼 "필드가 없는 문서를 제외한다"는 미묘한 차이가 있는 조건은 특히).
///
/// ── 차단한 사용자의 글은 여기서 함께 걸러진다 ──────────────────────────────
///
/// 노출 판정을 이미 세 곳(목록·지도·플레이스 피드)이 공유하고 있으므로,
/// 차단 필터를 **판정 안쪽에** 넣으면 부르는 쪽을 하나도 고치지 않아도 모든
/// 화면에 같은 규칙이 걸린다. 화면마다 따로 걸렀다면 "목록에서는 사라졌는데
/// 지도에는 남아 있다"가 반드시 생긴다.
///
/// 차단 목록을 아직 못 읽었으면 빈 집합이라 아무것도 걸러지지 않는다
/// (fail-open) — 차단 기능의 오류가 목록을 통째로 비우지는 않는다.
class ListingSources {
  ListingSources._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ── 파티 (parties) ────────────────────────────────────────────────
  //
  // 파티는 서버측 필터가 없다 — 정기 파티의 "남은 회차" 판정처럼 문서 하나만
  // 보고는 알 수 없는 조건이 섞여 있어 노출 판정을 전부 클라이언트에서 한다
  // ([PartyCard.isVisibleInList]).
  static Query<Map<String, dynamic>> parties() => _db.collection('parties');

  /// 파티 목록 노출 판정 — 삭제됨 + 지난 파티(정기는 남은 회차 없음)를 뺀다.
  static bool isPartyVisible(Map<String, dynamic> data, {DateTime? now}) =>
      !BlockService.isBlockedOwner(data) &&
      !PreRegistrationVisibility.isHidden(data) &&
      PartyCard.isVisibleInList(data, now: now);

  // ── 플레이스 (events) ─────────────────────────────────────────────
  //
  // ⚠️ `isActive == true` 서버 필터는 **필드가 아예 없는 문서를 제외**한다.
  // 그것이 플레이스 목록의 오래된 동작이고, 지도도 같은 문서 집합을 봐야
  // 하므로 쿼리를 그대로 공유한다(지도만 조건을 풀면 목록에 없는 플레이스가
  // 지도에서 튀어나온다). `orderBy('createdAt')`도 마찬가지로 정렬뿐 아니라
  // "createdAt이 없는 문서는 빠진다"는 필터로도 작동하므로 함께 둔다.
  static Query<Map<String, dynamic>> events() => _db
      .collection('events')
      .where('isActive', isEqualTo: true)
      .orderBy('createdAt', descending: true);

  /// 위 쿼리를 통과한 뒤에도 한 번 더 확인하는 클라이언트 판정.
  /// 쿼리와 중복이지만, 캐시로 먼저 내려온 문서나 다른 경로로 받아온 문서에도
  /// 같은 규칙이 걸리게 하는 안전망이다.
  static bool isEventVisible(Map<String, dynamic> data) =>
      !BlockService.isBlockedOwner(data) &&
      !PreRegistrationVisibility.isHidden(data) &&
      data['isDeleted'] != true &&
      data['isActive'] == true;

  // ── 장소대여 (places) ─────────────────────────────────────────────
  //
  // 여기는 반대로 **서버측 필터를 쓰지 않는다.** `isActive` 필드가 없는 옛
  // 문서까지 통째로 사라지는 문제가 있어서(→ "내 장소" 화면과 개수가 달라짐)
  // 조건 없이 전부 받고 아래 [isRentalVisible]로 거른다.
  static Query<Map<String, dynamic>> places() => _db.collection('places');

  /// 장소대여 노출 판정 — **명시적으로 false인 것만** 숨긴다("내 장소" 화면의
  /// 진행중/숨김 판정과 정확히 같은 규칙이라 두 화면의 개수가 일치한다).
  static bool isRentalVisible(Map<String, dynamic> data) =>
      !BlockService.isBlockedOwner(data) &&
      !PreRegistrationVisibility.isHidden(data) &&
      data['isDeleted'] != true &&
      data['isActive'] != false;
}
