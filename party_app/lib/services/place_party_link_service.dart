import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:party_app/models/map_listing.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/widgets/party_card_widget.dart';

// ══════════════════════════════════════════════════════════════════════════
// 플레이스(events) ↔ 기존 파티(parties) 연결 서비스
//
// 매장이 있어도 일반 파티부터 먼저 등록한 호스트가 많아서, 나중에 플레이스를
// 등록했을 때 이미 올려둔 파티를 그 플레이스에 붙일 수 있어야 한다.
//
// ── 필드 설계 ─────────────────────────────────────────────────────────────
// 없어진 "플레이스+파티" 콤보 등록이 쓰던 필드를 **그대로** 재사용한다 —
// 새 연결 스키마를 따로 만들지 않는다. 그래서 옛 콤보 문서와 나중에 연결된
// 문서를 같은 쿼리 하나로 읽을 수 있다.
//
//   parties/{id}
//     linkedEventId        : String   — 연결된 플레이스(events) 문서 id. 정본.
//     usesRegisteredPlace  : bool     — 직접 입력이 아니라 등록된 플레이스를
//                                        쓰는 파티인지(콤보/사후연결 공통).
//     placeSnapshot        : Map      — 연결 시점의 플레이스 정보 사본.
//     previousPlaceSnapshot: Map      — 연결 직전의 파티 장소 정보(해제 복원용).
//
//   events/{id}
//     linkedPartyIds       : [String] — 빠른 표시용 보조 배열.
//     linkedPartyId        : String   — 콤보 등록이 만든 대표 파티(그대로 둔다).
//
// 실제 조회·권한 판단은 항상 `parties.linkedEventId` 기준이다. `linkedPartyIds`는
// 한쪽만 갱신돼도 화면이 깨지지 않는 보조 데이터일 뿐이라, 연결/해제는 늘
// WriteBatch로 양쪽 문서를 함께 갱신한다.
//
// ── 공간대여(places)도 같은 구조를 쓴다 ───────────────────────────────────
// 공간대여 호스트도 "이 공간에서 여는 파티"를 붙일 수 있어야 한다. 이때
// **새 필드를 만들지 않는다** — "숙박+파티" 콤보 등록이 이미 `linkedPlaceId`로
// 같은 관계(파티 → places 문서)를 표현하고 있어서, 콤보로 만든 파티와 나중에
// 연결한 파티가 같은 쿼리 하나에 잡힌다. 무엇이 다르냐면 **가리키는 컬렉션과
// 필드 이름뿐**이고, 그 둘만 [PartyLinkTarget]으로 갈라 놓았다.
//
//   parties/{id}.linkedEventId → events/{id}   (플레이스)
//   parties/{id}.linkedPlaceId → places/{id}   (공간대여)
//
// 파티 하나는 **둘 중 한 곳에만** 붙는다 — 후보를 고를 때 두 필드를 함께 보고
// (isLinkedToAny) 이미 어딘가에 붙은 파티는 빼기 때문이다.
// ══════════════════════════════════════════════════════════════════════════

/// 파티를 붙일 수 있는 등록물의 종류.
///
/// 연결의 의미도 절차도 같고 **가리키는 컬렉션과 필드 이름만** 다르다. 그래서
/// 서비스·화면을 두 벌로 만들지 않고 이 값 하나만 갈아 끼운다.
enum PartyLinkTarget {
  /// 플레이스 — `events` 컬렉션.
  place(collection: 'events', linkField: 'linkedEventId', noun: '플레이스'),

  /// 공간대여 — `places` 컬렉션. "숙박+파티" 콤보가 쓰던 필드를 그대로 쓴다.
  rental(collection: 'places', linkField: 'linkedPlaceId', noun: '공간대여');

  const PartyLinkTarget({
    required this.collection,
    required this.linkField,
    required this.noun,
  });

  /// 대상 문서가 들어 있는 컬렉션.
  final String collection;

  /// 파티 문서에서 이 대상을 가리키는 필드 이름.
  final String linkField;

  /// 화면 문구에 쓰는 이름('플레이스' / '공간대여').
  final String noun;

  /// 지도·메인 상단 탭이 쓰는 종류 값 — 목록에 붙는 이모지(📍/🏠)와 라벨을
  /// 여기서 가져온다. 연결 화면이 자기만의 기호를 새로 만들면 같은 공간이
  /// 화면마다 다른 얼굴을 갖게 된다.
  MapListingKind get listingKind => switch (this) {
    PartyLinkTarget.place => MapListingKind.place,
    PartyLinkTarget.rental => MapListingKind.rental,
  };
}

/// **파티를 만들기 전에 이미 정해져 있는 연결 대상.**
///
/// "파티 연결 관리 → 새 파티 만들기"로 들어온 등록 화면이 받는 유일한 추가
/// 컨텍스트다. 등록 화면은 이 값이 있으면 (1) 장소를 대상 정보로 채우고,
/// (2) 저장 직후 [PlacePartyLink.linkParties]로 그 대상에 붙인 뒤,
/// (3) 메인으로 돌아가는 대신 연결 관리 화면으로 결과를 들고 돌아간다.
///
/// null이면 등록 화면은 지금까지와 **완전히 같게** 동작한다 — 일반 등록 탭에서
/// 들어온 흐름은 이 값의 존재를 몰라도 된다.
///
/// [data]까지 들고 다니는 이유: 연결은 대상 문서의 장소 정보를 파티에 복사하고
/// 소유자(hostId)를 검사하므로 id만으로는 부족하다
/// ([PlacePartyLink.linkParties] 계약 참고).
class PartyPrelinkTarget {
  /// 플레이스(events)인지 공간대여(places)인지.
  final PartyLinkTarget target;

  /// 대상 문서 id.
  final String targetId;

  /// 대상 문서 데이터.
  final Map<String, dynamic> data;

  const PartyPrelinkTarget({
    required this.target,
    required this.targetId,
    required this.data,
  });

  /// 화면에 보여줄 대상 이름 — 비어 있으면 종류 이름('플레이스')으로 대체한다.
  String get displayName {
    final name = (data['name'] as String?)?.trim() ?? '';
    return name.isEmpty ? target.noun : name;
  }

  /// 목록에서 이름 아래에 붙는 위치 한 줄. 컬렉션마다 채워지는 필드가 달라
  /// (events는 `location`, places는 `address`가 먼저 차는 경우가 많다) 있는
  /// 것부터 고른다. 셋 다 비었으면 빈 문자열.
  String get displayLocation {
    for (final key in ['location', 'address', 'roadAddress']) {
      final v = (data[key] as String?)?.trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  /// 등록 폼에 붙는 한 줄 표기 — "📍 플레이스 · OO 혼술바".
  String get badgeLabel =>
      '${target.listingKind.emoji} ${target.listingKind.label} · $displayName';
}

/// 파티 문서에서 "장소"를 이루는 필드 묶음 — 연결 시 플레이스 값으로 덮어쓰고,
/// 해제 시 [PlacePartyLink.previousSnapshotField]에서 되돌리는 대상이다.
const List<String> kPartyLocationFields = <String>[
  'location',
  'address',
  'roadAddress',
  'jibunAddress',
  'detailAddress',
  'placeName',
  'latitude',
  'longitude',
  'region',
  'district',
];

/// 연결 후보 1건 — 파티 문서 + 새 플레이스와의 근접도 정보.
class PartyLinkCandidate {
  final String id;
  final Map<String, dynamic> data;

  /// 새 플레이스와 도로명/지번 주소가 완전히 같은 파티.
  final bool sameAddress;

  /// 새 플레이스까지의 직선거리(m). 좌표가 없으면 null.
  final double? distanceMeters;

  const PartyLinkCandidate({
    required this.id,
    required this.data,
    required this.sameAddress,
    required this.distanceMeters,
  });

  /// 목록에서 후보 위에 붙는 추천 사유 라벨. 추천 대상이 아니면 null.
  String? get recommendReason {
    if (sameAddress) return '주소가 같은 파티';
    final d = distanceMeters;
    if (d == null || d > PlacePartyLink.nearbyRadiusMeters) return null;
    if (d < 1000) return '이 플레이스와 가까운 파티 (약 ${d.round()}m)';
    return '이 플레이스와 가까운 파티 (약 ${(d / 1000).toStringAsFixed(1)}km)';
  }

  bool get isRecommended => recommendReason != null;
}

class PlacePartyLink {
  PlacePartyLink._();

  static const String linkedEventIdField = 'linkedEventId';
  static const String usesRegisteredPlaceField = 'usesRegisteredPlace';
  static const String snapshotField = 'placeSnapshot';
  static const String previousSnapshotField = 'previousPlaceSnapshot';
  static const String linkedPartyIdsField = 'linkedPartyIds';

  /// "가까운 파티"로 추천하는 반경.
  static const double nearbyRadiusMeters = 2000;

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ── 읽기 헬퍼 ───────────────────────────────────────────────────────────

  /// 이 파티가 [target]에 연결돼 있으면 그 문서 id. 없으면 null.
  static String? linkedIdOf(
    Map<String, dynamic> party, [
    PartyLinkTarget target = PartyLinkTarget.place,
  ]) {
    final id = party[target.linkField] as String?;
    return (id != null && id.isNotEmpty) ? id : null;
  }

  /// 이 파티가 이미 어떤 플레이스(events)에 연결돼 있는지. 없으면 null.
  static String? linkedEventIdOf(Map<String, dynamic> party) =>
      linkedIdOf(party, PartyLinkTarget.place);

  /// 이 파티가 `places` 문서에 묶여 있는지 — "숙박+파티" 콤보로 함께 등록됐거나
  /// 공간대여에 나중에 연결된 경우 둘 다 해당한다(필드가 같다).
  static bool isStayCombo(Map<String, dynamic> party) =>
      linkedIdOf(party, PartyLinkTarget.rental) != null;

  /// 이 파티가 붙어 있는 **종류**. 안 붙어 있으면 null.
  ///
  /// 등록·수정·상세가 "events냐 places냐"를 각자 필드 이름으로 따져 묻지
  /// 않도록 하는 단 하나의 판정이다. 파티 하나는 한 곳에만 붙으므로
  /// ([isLinkedToAny]) 먼저 걸리는 종류가 곧 답이다.
  static PartyLinkTarget? linkedTargetOf(Map<String, dynamic> party) {
    for (final t in PartyLinkTarget.values) {
      if (linkedIdOf(party, t) != null) return t;
    }
    return null;
  }

  /// 연결 종류와 문서 id를 함께 — 둘을 따로 읽다 어긋나는 일을 막는다.
  static ({PartyLinkTarget target, String id})? linkOf(
    Map<String, dynamic> party,
  ) {
    final target = linkedTargetOf(party);
    if (target == null) return null;
    return (target: target, id: linkedIdOf(party, target)!);
  }

  /// **이미 어딘가에 붙어 있는 파티인지.** 파티 하나는 플레이스든 공간대여든
  /// 한 곳에만 붙는다 — 두 곳에 동시에 붙으면 파티 문서의 장소 정보를 어느
  /// 쪽에 맞춰야 하는지 답이 없어진다. 후보 목록에서 빼는 기준이다.
  static bool isLinkedToAny(Map<String, dynamic> party) {
    for (final t in PartyLinkTarget.values) {
      if (linkedIdOf(party, t) != null) return true;
    }
    return false;
  }

  /// 신청자가 한 명이라도 있는 파티인지 — 장소를 바꾸면 이미 신청한 사람이
  /// 영향을 받으므로 경고를 띄우는 기준이다.
  static bool hasApplicants(Map<String, dynamic> party) {
    int len(String key) => (party[key] as List?)?.length ?? 0;
    if (len('applicants') > 0 || len('approvedApplicants') > 0) return true;
    final current = (party['currentParticipants'] as num?)?.toInt() ?? 0;
    return current > 0;
  }

  /// 삭제/종료 처리된 파티인지 — 후보 목록에서 제외한다.
  static bool isClosed(Map<String, dynamic> party) {
    if (party['isDeleted'] == true) return true;
    if (party['isActive'] == false) return true;
    final status = party['status'] as String?;
    if (status != null && status != 'active') return true;
    // 모집상태가 '종료'/'취소'로 손수 바뀐 파티 + 이미 날짜가 지난 파티.
    final effective = PartyCard.effectiveStatus(party);
    if (effective == '종료' || effective == '취소') return true;
    return !PartyCard.isVisibleInList(party);
  }

  // ── 내가 가진 공간 조회 ────────────────────────────────────────────────

  /// 이미 읽어 온 문서 목록에서 **내 소유의 살아있는 공간만** 골라
  /// [PartyPrelinkTarget] 목록으로 만든다.
  ///
  /// 쿼리에서 이미 `hostId`로 거르지만 여기서 한 번 더 본다 — 이 목록은
  /// "고르면 그 공간에 파티가 붙는" 목록이고, 남의 공간이 한 줄이라도 새면
  /// 고른 뒤 [linkParties]의 소유자 검사에 걸려 등록만 끝나고 연결은 실패한
  /// 상태가 된다. 순수 함수라 조회 없이 그대로 검증할 수 있다.
  ///
  /// 정렬은 종류별로 묶고(플레이스 → 공간대여) 각 묶음 안에서 최근 등록순 —
  /// 목록이 길어져도 "어느 쪽 공간인지"가 눈으로 먼저 갈린다.
  static List<PartyPrelinkTarget> spacesFrom({
    required String hostId,
    required Map<PartyLinkTarget, List<({String id, Map<String, dynamic> data})>>
    docsByTarget,
  }) {
    if (hostId.isEmpty) return const [];
    final spaces = <PartyPrelinkTarget>[];
    for (final target in PartyLinkTarget.values) {
      final docs = docsByTarget[target] ?? const [];
      final mine =
          docs
              .where((d) => (d.data['hostId'] as String? ?? '') == hostId)
              .where((d) => d.data['isDeleted'] != true)
              .toList()
            ..sort(
              (a, b) => _createdMillis(b.data).compareTo(_createdMillis(a.data)),
            );
      for (final d in mine) {
        spaces.add(
          PartyPrelinkTarget(target: target, targetId: d.id, data: d.data),
        );
      }
    }
    return spaces;
  }

  /// [hostId]가 등록한 플레이스(events) + 공간대여(places)를 한 목록으로.
  ///
  /// "파티 등록 진입에서 연결 선택 화면을 띄울지"를 정하는 값이라, 하나도
  /// 없으면 빈 목록이 나오고 호출부는 지금까지와 똑같이 등록 폼으로 바로
  /// 보낸다. 조회 실패도 빈 목록으로 본다 — 공간을 못 읽었다고 등록 자체를
  /// 막을 이유는 없다.
  static Future<List<PartyPrelinkTarget>> loadMySpaces({
    required String hostId,
  }) async {
    if (hostId.isEmpty) return const [];
    final docsByTarget =
        <PartyLinkTarget, List<({String id, Map<String, dynamic> data})>>{};
    for (final target in PartyLinkTarget.values) {
      try {
        final snap = await _db
            .collection(target.collection)
            .where('hostId', isEqualTo: hostId)
            .get();
        docsByTarget[target] = [
          for (final d in snap.docs) (id: d.id, data: d.data()),
        ];
      } catch (_) {
        docsByTarget[target] = const [];
      }
    }
    return spacesFrom(hostId: hostId, docsByTarget: docsByTarget);
  }

  // ── 후보 조회 ───────────────────────────────────────────────────────────

  /// [hostId]가 등록한 파티 중 **아직 어떤 플레이스에도 연결되지 않았고**
  /// 삭제·종료되지 않은 것만 골라, [place](events 문서 데이터) 기준으로
  /// 주소가 같은 파티 → 가까운 파티 → 나머지(최근 등록순)로 정렬해 돌려준다.
  ///
  /// 자동 연결은 하지 않는다 — 정렬·추천 라벨까지만 계산하고 선택은 호스트 몫.
  static Future<List<PartyLinkCandidate>> loadCandidates({
    required String hostId,
    required Map<String, dynamic> place,
    PartyLinkTarget target = PartyLinkTarget.place,
  }) async {
    if (hostId.isEmpty) return const [];
    // 복합 색인 없이 돌도록 hostId 하나로만 질의하고 나머지는 클라이언트에서
    // 거른다 — 한 호스트의 파티 수는 목록 화면에서 이미 통째로 읽는 규모다.
    final snap = await _db
        .collection('parties')
        .where('hostId', isEqualTo: hostId)
        .get();

    final placeLat = placeLatOf(place);
    final placeLng = placeLngOf(place);
    final placeAddresses = _addressKeys(place);

    final candidates = <PartyLinkCandidate>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      // 플레이스든 공간대여든 이미 붙어 있으면 후보가 아니다.
      if (isLinkedToAny(data)) continue;
      if (isClosed(data)) continue;

      final partyAddresses = _addressKeys(data);
      final sameAddress =
          placeAddresses.isNotEmpty &&
          partyAddresses.any(placeAddresses.contains);

      double? distance;
      final partyLat = _toDouble(data['latitude']);
      final partyLng = _toDouble(data['longitude']);
      if (placeLat != null &&
          placeLng != null &&
          partyLat != null &&
          partyLng != null) {
        distance = _distanceMeters(placeLat, placeLng, partyLat, partyLng);
      }

      candidates.add(
        PartyLinkCandidate(
          id: doc.id,
          data: data,
          sameAddress: sameAddress,
          distanceMeters: distance,
        ),
      );
    }

    candidates.sort((a, b) {
      if (a.sameAddress != b.sameAddress) return a.sameAddress ? -1 : 1;
      final da = a.distanceMeters;
      final db = b.distanceMeters;
      if (da != null && db != null && da != db) return da.compareTo(db);
      if (da != null && db == null) return -1;
      if (da == null && db != null) return 1;
      return _createdMillis(b.data).compareTo(_createdMillis(a.data));
    });
    return candidates;
  }

  /// [targetId]에 연결된 파티 목록 — 파티 문서의 연결 필드가 정본이므로
  /// 대상 문서의 보조 배열이 아니라 이 쿼리로 읽는다.
  static Future<List<({String id, Map<String, dynamic> data})>>
  loadLinkedParties(
    String targetId, {
    PartyLinkTarget target = PartyLinkTarget.place,
  }) async {
    if (targetId.isEmpty) return const [];
    final snap = await _db
        .collection('parties')
        .where(target.linkField, isEqualTo: targetId)
        .get();
    final list = snap.docs
        .where((d) => d.data()['isDeleted'] != true)
        .map((d) => (id: d.id, data: d.data()))
        .toList();
    list.sort((a, b) {
      final da = PartyCard.parsePartyDateTime(a.data);
      final db = PartyCard.parsePartyDateTime(b.data);
      if (da != null && db != null) return da.compareTo(db);
      if (da != null) return -1;
      if (db != null) return 1;
      return 0;
    });
    return list;
  }

  /// 연결된 파티 개수만 필요한 화면(호스트 카드의 관리 메뉴)용 경량 조회.
  static Future<int> countLinkedParties(
    String targetId, {
    PartyLinkTarget target = PartyLinkTarget.place,
  }) async => (await loadLinkedParties(targetId, target: target)).length;

  // ── 쓰기 payload (순수 함수) ────────────────────────────────────────────
  //
  // 아래 세 함수는 Firestore를 만지지 않고 **보낼 값만** 만든다. 이 프로젝트의
  // Dart 테스트에는 Firestore 페이크도 에뮬레이터도 없어서, 이렇게 떼어놓지
  // 않으면 "어느 필드에 무엇이 쓰이고 무엇이 지워지는지"를 검증할 방법이
  // 아예 없다(test/place_party_link_payload_test.dart가 이 값을 그대로 본다).

  /// 지금 세우는 [keep] 말고 **다른 연결 필드는 전부 지운다.**
  ///
  /// 파티 하나는 한 곳에만 붙는다는 규칙([isLinkedToAny])을 화면이 아니라
  /// payload 층에서 지킨다. 종류를 가로질러 바꿀 때(플레이스 A → 장소대여 B)
  /// 이전 필드가 남으면 `linkedEventId`와 `linkedPlaceId`가 동시에 유효해
  /// 보이고, 그때부터 목록·지도·상세가 어느 쪽을 정본으로 볼지 갈린다.
  /// [keep]이 null이면(해제) 두 필드를 모두 지운다.
  ///
  /// 없는 필드에 대한 delete는 무시되므로, 애초에 한 쪽만 있던 문서에
  /// 걸어도 안전하다.
  static Map<String, dynamic> clearOtherLinkFields(PartyLinkTarget? keep) => {
    for (final t in PartyLinkTarget.values)
      if (t != keep) t.linkField: FieldValue.delete(),
  };

  /// 파티 문서에 연결을 세우는 update payload.
  ///
  /// [previousLocation]은 연결 **직전**의 장소 필드 묶음이다 — 해제할 때
  /// 되돌릴 값이라, 이미 다른 공간에 붙어 있던 파티를 옮길 때는 "그 공간에서
  /// 가져온 주소"가 아니라 **원래 직접 입력했던 주소**를 물려줘야 한다
  /// (호출부가 [previousSnapshotField]를 먼저 본다).
  static Map<String, dynamic> linkUpdate({
    required PartyLinkTarget target,
    required String targetId,
    required Map<String, dynamic> place,
    required Map<String, dynamic> previousLocation,
  }) => <String, dynamic>{
    ...placeLocationFields(place),
    ...clearOtherLinkFields(target),
    target.linkField: targetId,
    usesRegisteredPlaceField: true,
    snapshotField: buildPlaceSnapshot(
      targetId: targetId,
      place: place,
      target: target,
    ),
    previousSnapshotField: previousLocation,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// 연결을 끊는 update payload — 종류와 무관하게 **두 연결 필드를 모두** 지운다.
  ///
  /// [restoreFrom]에 [previousSnapshotField] 값을 주면 연결 직전의 장소로
  /// 되돌리고, null이면 지금 표시 중인(=공간에서 가져온) 장소를 그대로 남긴다.
  static Map<String, dynamic> unlinkUpdate({
    Map<String, dynamic>? restoreFrom,
  }) {
    final update = <String, dynamic>{
      ...clearOtherLinkFields(null),
      usesRegisteredPlaceField: false,
      snapshotField: FieldValue.delete(),
      previousSnapshotField: FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (restoreFrom != null) {
      for (final key in kPartyLocationFields) {
        if (restoreFrom.containsKey(key)) update[key] = restoreFrom[key];
      }
    }
    return update;
  }

  /// 대상 문서(events/places)의 보조 배열 갱신 payload.
  static Map<String, dynamic> linkedPartyIdsUpdate({
    required List<String> partyIds,
    required bool add,
  }) => <String, dynamic>{
    linkedPartyIdsField: add
        ? FieldValue.arrayUnion(partyIds)
        : FieldValue.arrayRemove(partyIds),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// 연결을 옮길 때 물려줄 "원래 장소" — 이미 [previousSnapshotField]가 있으면
  /// 그것이 진짜 원본이므로 그대로 쓰고, 없을 때만 지금 값을 뜬다.
  static Map<String, dynamic> previousLocationFor(Map<String, dynamic> party) {
    final previous = party[previousSnapshotField];
    if (previous is Map) return Map<String, dynamic>.from(previous);
    return capturePartyLocation(party);
  }

  // ── 연결 / 해제 ─────────────────────────────────────────────────────────

  /// 파티 [partyIds]를 플레이스 [eventId]에 연결한다.
  ///
  /// 파티의 장소 정보(이름·주소·상세주소·좌표·대표이미지·유형·시설·상세링크)는
  /// 플레이스 값으로 덮어쓰지만, **제목·소개·일정·참가비·모집 설정은 손대지
  /// 않는다.** 연결 직전의 장소 값은 [previousSnapshotField]에 담아둬서 나중에
  /// 해제할 때 되돌릴 수 있게 한다.
  ///
  /// 양쪽 문서(parties N개 + events 1개)를 하나의 WriteBatch로 커밋하므로
  /// 한쪽만 연결된 상태가 남지 않는다.
  static Future<void> linkParties({
    required String targetId,
    required Map<String, dynamic> place,
    required List<String> partyIds,
    required String hostId,
    PartyLinkTarget target = PartyLinkTarget.place,
  }) async {
    if (partyIds.isEmpty) return;
    final placeHostId = place['hostId'] as String? ?? '';
    if (placeHostId != hostId) {
      throw StateError('내 ${target.noun}이 아니라 연결할 수 없어요.');
    }

    // 파티 문서를 먼저 읽어 소유자·현재 장소값을 확인한다(previous 스냅샷용).
    final refs = partyIds.map(_db.collection('parties').doc).toList();
    final snaps = await Future.wait(refs.map((r) => r.get()));

    final batch = _db.batch();
    final linkedIds = <String>[];

    for (var i = 0; i < snaps.length; i++) {
      final snap = snaps[i];
      final data = snap.data();
      if (data == null) continue;
      final partyHostId = data['hostId'] as String? ?? '';
      final partyHostUid = data['hostUid'] as String? ?? '';
      if (partyHostId != hostId && partyHostUid != hostId) {
        throw StateError('내가 등록한 파티만 연결할 수 있어요.');
      }
      batch.update(
        refs[i],
        linkUpdate(
          target: target,
          targetId: targetId,
          place: place,
          previousLocation: previousLocationFor(data),
        ),
      );
      linkedIds.add(refs[i].id);
    }

    if (linkedIds.isEmpty) return;
    batch.update(
      _db.collection(target.collection).doc(targetId),
      linkedPartyIdsUpdate(partyIds: linkedIds, add: true),
    );
    await batch.commit();
  }

  /// 파티 [partyId]와 [targetId]의 연결을 끊는다. 파티 문서 자체는
  /// 절대 지우지 않는다.
  ///
  /// [restorePreviousLocation]이 true면 연결 직전의 장소 정보로 되돌리고,
  /// false면 지금 표시 중인(=플레이스에서 가져온) 장소 정보를 그대로 남긴다.
  static Future<void> unlinkParty({
    required String targetId,
    required String partyId,
    required bool restorePreviousLocation,
    PartyLinkTarget target = PartyLinkTarget.place,
  }) async {
    final partyRef = _db.collection('parties').doc(partyId);
    final partySnap = await partyRef.get();
    final data = partySnap.data();

    final previous = data?[previousSnapshotField];
    final update = unlinkUpdate(
      restoreFrom: restorePreviousLocation && previous is Map
          ? Map<String, dynamic>.from(previous)
          : null,
    );

    final batch = _db.batch();
    batch.update(partyRef, update);
    batch.update(
      _db.collection(target.collection).doc(targetId),
      linkedPartyIdsUpdate(partyIds: [partyId], add: false),
    );
    await batch.commit();
  }

  /// 연결을 유지한 채 파티의 장소 스냅샷만 **현재 플레이스 값으로** 다시
  /// 맞춘다 — "플레이스 변경사항 반영" 버튼용. 신청자가 있는 파티에서는
  /// 호출부가 먼저 경고를 띄운다(자동 반영은 하지 않는다).
  static Future<void> refreshPlaceSnapshot({
    required String targetId,
    required String partyId,
    required Map<String, dynamic> place,
    PartyLinkTarget target = PartyLinkTarget.place,
  }) async {
    await _db.collection('parties').doc(partyId).update({
      ...placeLocationFields(place),
      snapshotField: buildPlaceSnapshot(
        targetId: targetId,
        place: place,
        target: target,
      ),
      usesRegisteredPlaceField: true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 연결된 파티를 **다른 공간으로** 갈아끼운다 — 이전 공간의 보조 배열까지
  /// 같은 배치에서 정리해 양쪽이 어긋나지 않게 한다.
  ///
  /// 종류를 가로질러도 된다(플레이스 ↔ 장소대여). 그럴 때 이전 종류의 연결
  /// 필드는 [linkUpdate]가 같은 배치에서 지우므로, 한 파티 문서에
  /// `linkedEventId`와 `linkedPlaceId`가 동시에 남는 상태는 만들어지지 않는다.
  /// 보조 배열도 **각자의 컬렉션**에서 빼고 넣는다 — 종류가 바뀌면 지우는 곳과
  /// 넣는 곳이 서로 다른 컬렉션이다.
  static Future<void> relinkParty({
    required String partyId,
    required PartyLinkTarget fromTarget,
    required String fromTargetId,
    required PartyLinkTarget toTarget,
    required String toTargetId,
    required Map<String, dynamic> toPlace,
    required String hostId,
  }) async {
    // 같은 문서로의 재연결은 할 일이 없다 — 종류가 같고 id도 같을 때만이다.
    if (fromTarget == toTarget && fromTargetId == toTargetId) return;
    // 남의 공간으로 옮기려는 요청은 문서를 읽기도 전에 막는다.
    if ((toPlace['hostId'] as String? ?? '') != hostId) {
      throw StateError('내 ${toTarget.noun}이 아니라 연결할 수 없어요.');
    }
    final partyRef = _db.collection('parties').doc(partyId);
    final partySnap = await partyRef.get();
    final data = partySnap.data();
    if (data == null) throw StateError('파티를 찾을 수 없어요.');
    final partyHostId = data['hostId'] as String? ?? '';
    final partyHostUid = data['hostUid'] as String? ?? '';
    if (partyHostId != hostId && partyHostUid != hostId) {
      throw StateError('내가 등록한 파티만 연결할 수 있어요.');
    }

    final batch = _db.batch();
    batch.update(
      partyRef,
      linkUpdate(
        target: toTarget,
        targetId: toTargetId,
        place: toPlace,
        // 이전 공간에서 가져온 장소값을 previous로 남기면 "원래 직접 입력했던
        // 주소"가 사라지므로, 이미 previous가 있으면 그대로 물려준다.
        previousLocation: previousLocationFor(data),
      ),
    );
    if (fromTargetId.isNotEmpty) {
      batch.update(
        _db.collection(fromTarget.collection).doc(fromTargetId),
        linkedPartyIdsUpdate(partyIds: [partyId], add: false),
      );
    }
    batch.update(
      _db.collection(toTarget.collection).doc(toTargetId),
      linkedPartyIdsUpdate(partyIds: [partyId], add: true),
    );
    await batch.commit();
  }

  // ── 스냅샷 만들기 ───────────────────────────────────────────────────────

  /// 플레이스(events) 문서에서 파티 문서에 그대로 복사할 장소 필드 묶음.
  /// 파티 제목·소개·일정·참가비·모집 설정은 여기에 포함되지 않는다.
  static Map<String, dynamic> placeLocationFields(Map<String, dynamic> place) {
    final address = place['address'] as String? ?? '';
    final detailAddress = place['detailAddress'] as String? ?? '';
    final location = (place['location'] as String?)?.isNotEmpty == true
        ? place['location'] as String
        : (address.isEmpty
              ? ''
              : '$address${detailAddress.isEmpty ? '' : ' $detailAddress'}');
    return <String, dynamic>{
      'placeName': place['name'] as String? ?? '',
      'location': location,
      'address': address,
      'roadAddress': place['roadAddress'] as String? ?? '',
      'jibunAddress': place['jibunAddress'] as String? ?? '',
      'detailAddress': detailAddress,
      'latitude': placeLatOf(place) ?? 0.0,
      'longitude': placeLngOf(place) ?? 0.0,
      'region': RegionData.extractRegion(address),
      'district': RegionData.extractDistrict(address),
    };
  }

  /// 연결 시점의 플레이스 정보 사본 — 이후 플레이스가 수정돼도 이미 연결된
  /// 파티의 상세 화면은 이 값을 그대로 보여준다(신청자가 생긴 뒤 장소가
  /// 갑자기 바뀌는 일을 막는다).
  static Map<String, dynamic> buildPlaceSnapshot({
    required String targetId,
    required Map<String, dynamic> place,
    PartyLinkTarget target = PartyLinkTarget.place,
  }) {
    return <String, dynamic>{
      // 키 이름은 `eventId` 그대로 둔다 — 이미 저장된 스냅샷을 읽는 화면들이
      // 이 키를 보고 있어서, 공간대여가 생겼다고 이름을 바꾸면 옛 문서가
      // 안 읽힌다. 어느 컬렉션의 id인지는 아래 `detailCollection`이 말해준다.
      'eventId': targetId,
      'name': place['name'] as String? ?? '',
      'address': place['address'] as String? ?? '',
      'roadAddress': place['roadAddress'] as String? ?? '',
      'jibunAddress': place['jibunAddress'] as String? ?? '',
      'detailAddress': place['detailAddress'] as String? ?? '',
      'location': place['location'] as String? ?? '',
      'latitude': placeLatOf(place) ?? 0.0,
      'longitude': placeLngOf(place) ?? 0.0,
      // 대표 이미지도 컬렉션마다 이름이 다르다 — events는 `mainImageUrl`,
      // places는 `coverImageUrl`(없으면 `imageUrls` 첫 장)을 쓴다.
      'mainImageUrl': _mainImageOf(place),
      'themeTags': (place['themeTags'] as List?)?.cast<String>() ?? <String>[],
      if (place['facilityOptions'] is Map)
        'facilityOptions': Map<String, dynamic>.from(
          place['facilityOptions'] as Map,
        ),
      // 어느 컬렉션의 문서인지 — 상세로 이동할 때 events / places를 가른다.
      'detailCollection': target.collection,
      // serverTimestamp 센티널은 중첩 맵 안에서도 동작하지만, 이 값은 "언제
      // 찍은 사본인지" 표시용이라 클라이언트 시각으로 충분하다.
      'linkedAt': Timestamp.now(),
    };
  }

  /// 지금 파티 문서에 들어 있는 장소 필드를 그대로 떠서 돌려준다(해제 복원용).
  static Map<String, dynamic> capturePartyLocation(Map<String, dynamic> data) {
    return <String, dynamic>{
      for (final key in kPartyLocationFields)
        if (data.containsKey(key)) key: data[key],
    };
  }

  // ── 작은 계산 헬퍼 ──────────────────────────────────────────────────────

  static Set<String> _addressKeys(Map<String, dynamic> data) {
    final keys = <String>{};
    for (final field in ['roadAddress', 'jibunAddress', 'address']) {
      final v = (data[field] as String?)?.trim();
      if (v != null && v.isNotEmpty) keys.add(v);
    }
    return keys;
  }

  static int _createdMillis(Map<String, dynamic> data) {
    final ts = data['createdAt'];
    return ts is Timestamp ? ts.millisecondsSinceEpoch : 0;
  }

  static double? _toDouble(Object? v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  /// 대상 문서의 위도/경도 — **컬렉션마다 필드 이름이 다르다.**
  /// 플레이스(events)는 `latitude`/`longitude`, 공간대여(places)는 `lat`/`lng`로
  /// 저장한다(등록 화면이 서로 다른 시기에 만들어졌다). 이미 쌓인 문서가 많아
  /// 필드를 통일하는 대신 **읽는 쪽에서 두 이름을 모두 받아준다** — 안 그러면
  /// 공간대여에 연결한 파티의 좌표가 0,0이 되어 지도에서 사라진다.
  static double? placeLatOf(Map<String, dynamic> place) =>
      _toDouble(place['latitude'] ?? place['lat']);

  static double? placeLngOf(Map<String, dynamic> place) =>
      _toDouble(place['longitude'] ?? place['lng']);

  /// 대상 문서의 대표 이미지 — 좌표와 같은 이유로 이름이 갈린다.
  static String _mainImageOf(Map<String, dynamic> place) {
    for (final key in ['mainImageUrl', 'coverImageUrl']) {
      final v = place[key];
      if (v is String && v.isNotEmpty) return v;
    }
    final list = place['imageUrls'];
    if (list is List) {
      for (final v in list) {
        if (v is String && v.isNotEmpty) return v;
      }
    }
    return '';
  }

  static double _distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return 2 * r * atan2(sqrt(a), sqrt(1 - a));
  }
}
