import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:party_app/services/listing_sources.dart';
import 'package:party_app/services/place_party_link_service.dart';

/// **🎉 With파티 판정의 정본** — 지금 파티가 걸려 있는 플레이스 id 집합.
///
/// ── 새 필드를 만들지 않는다 ───────────────────────────────────────────────
/// "이 플레이스에 파티가 붙어 있나"는 이미 저장돼 있다. 정본은
/// `parties/{id}.linkedEventId`이고([PlacePartyLink]), 플레이스 문서 쪽
/// `linkedPartyIds`는 한쪽만 갱신돼도 화면이 안 깨지도록 둔 **보조 배열**이라
/// 판정에 쓰면 안 된다. 그래서 여기서도 파티 쪽에서만 읽는다.
///
/// `withParty: true` 같은 수동 필드를 새로 두지 않는 이유도 같다 — 파티가
/// 지워지거나 지난 뒤에도 그 값이 남아 "파티 있다더니 없는" 플레이스가 된다.
/// 연결은 파티의 생사에 따라 매 순간 달라지므로 **읽을 때 계산한다**.
///
/// ── 어떤 파티를 '있다'로 치는가 ───────────────────────────────────────────
/// 파티 목록·지도가 쓰는 노출 판정 하나를 그대로 쓴다
/// ([ListingSources.isPartyVisible] → `PartyCard.isVisibleInList`). 삭제된
/// 파티, 이미 지난 파티, 남은 회차가 없는 정기 파티는 저절로 빠진다 — 여기서
/// 조건을 새로 쓰면 파티 탭에는 없는 파티 때문에 플레이스가 With파티로 뜬다.
///
/// ── 플레이스 하나는 한 번만 ───────────────────────────────────────────────
/// 집합(Set)이라 파티가 몇 개 붙어 있든 id는 하나다. 목록·지도는 플레이스
/// 문서를 그대로 그리므로 카드가 중복될 수 없다.
class PlacePartyIndex {
  const PlacePartyIndex(this.placeIds);

  /// 살아 있는 파티가 하나 이상 붙어 있는 **플레이스(`events`) 문서 id**.
  final Set<String> placeIds;

  /// 아직 파티를 못 읽었을 때. 이 상태로 With파티를 켜면 아무것도 안 나온다 —
  /// 목록이 잠깐 비는 편이, 파티가 없는 곳을 있다고 보여주는 것보다 낫다.
  static const PlacePartyIndex empty = PlacePartyIndex(<String>{});

  bool get isEmpty => placeIds.isEmpty;

  /// 이 플레이스에 지금 노출 가능한 파티가 붙어 있는가.
  bool has(String? placeId) =>
      placeId != null && placeId.isNotEmpty && placeIds.contains(placeId);

  /// 파티 문서들에서 색인을 만든다.
  ///
  /// [now]는 노출 판정에 그대로 넘어간다 — 테스트가 "내일 파티"·"어제 파티"를
  /// 고정된 시각으로 확인할 수 있어야 한다.
  static PlacePartyIndex fromParties(
    Iterable<Map<String, dynamic>> parties, {
    DateTime? now,
  }) {
    final ids = <String>{};
    for (final party in parties) {
      final placeId = PlacePartyLink.linkedEventIdOf(party);
      if (placeId == null || placeId.isEmpty) continue;
      // 이미 들어 있는 플레이스면 노출 판정을 다시 할 필요가 없다.
      if (ids.contains(placeId)) continue;
      if (!ListingSources.isPartyVisible(party, now: now)) continue;
      ids.add(placeId);
    }
    return PlacePartyIndex(ids);
  }

  /// Firestore 스냅샷에서 바로 — 노출 판정이 문서 id를 보는 경우가 있어
  /// 목록·지도가 하던 것과 같은 모양(`_docId` 포함)으로 넘긴다.
  static PlacePartyIndex fromSnapshot(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    DateTime? now,
  }) => fromParties(
    docs.map((d) => <String, dynamic>{'_docId': d.id, ...d.data()}),
    now: now,
  );

  /// 같은 집합인지 — 스트림이 새 스냅샷을 줄 때마다 화면을 다시 그리지 않도록
  /// 호출부가 이 비교로 걸러 낸다.
  bool sameAs(PlacePartyIndex other) =>
      placeIds.length == other.placeIds.length &&
      placeIds.containsAll(other.placeIds);
}
