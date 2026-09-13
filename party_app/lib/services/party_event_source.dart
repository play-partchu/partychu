// ─────────────────────────────────────────────────────────────────────────────
// "이 파티를 기반으로 이벤트 등록" — 파티에서 **플레이스 이벤트**로 건너가는 다리.
//
// ── 왜 이 파일이 필요한가 ────────────────────────────────────────────────────
// 예전에는 이 버튼이 파티 등록 화면(재등록 모드)을 열었다. 그러면 만들어지는
// 것은 **또 하나의 파티**라서, 손님이 파티 목록에서 같은 내용을 두 번 보게 되고
// "플레이스 > 이벤트"에는 끝내 뜨지 않았다. 이벤트는 파티가 아니라 **가게가
// 일정 기간 여는 혜택**이므로 사는 곳이 다르다.
//
// ── 이 앱의 이벤트 데이터 모델(조사 결과) ────────────────────────────────────
// 이름이 헷갈리므로 먼저 못 박아 둔다.
//
//   · `events`          = **플레이스 본체** 컬렉션(술집·바·카페). 이벤트가 아니다.
//   · `places`          = 장소대여·숙박 본체 컬렉션.
//   · `placePromotions` = 그 가게가 여는 **이벤트·혜택 한 건**. 기간·혜택·조건이
//                         전부 여기 있다([PlacePromotion]). 이벤트의 본문이다.
//
// 그리고 "플레이스 > 이벤트" 목록에 뜨는 기준은 프로모션 문서가 아니라
// **플레이스 본체 문서의 두 값**이다.
//
//   · `themeTags`에 '이벤트'(화면 표기 '이벤트 진행중')가 들어 있는가
//   · 한 단계 아래 갈래는 `eventSubtype`(지금은 '생일파티 이벤트' 하나)
//
// 그래서 이벤트를 등록하는 일은 **두 곳을 맞추는 일**이다 — 내용은
// placePromotions에 쓰고, 노출은 플레이스 본체에 켠다. 새 컬렉션도, partyEvent
// 같은 새 필드도 만들지 않는다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/place_event_taxonomy.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/services/place_party_link_service.dart';
import 'package:party_app/services/place_promotion_service.dart';

/// 파티에서 뽑아낸, 이벤트 등록 화면이 필요로 하는 값들.
///
/// **파티 문서는 읽기만 한다.** 이벤트는 원본 파티와 별개의 콘텐츠라, 파티가
/// 지워져도 남고 파티를 고쳐도 따라 바뀌지 않는다.
class PartyEventSource {
  const PartyEventSource({
    required this.placeId,
    required this.placeCollection,
    required this.hostId,
    required this.placeName,
    required this.address,
    required this.titleDraft,
    required this.sourcePartyId,
    required this.sourcePartyTitle,
  });

  /// 이벤트가 붙을 가게 문서 id.
  final String placeId;

  /// 'events'(플레이스) 또는 'places'(장소대여·숙박).
  final String placeCollection;

  /// **원본 가게 문서에서 읽은** hostId — 파티에 적힌 값을 쓰지 않는다.
  /// rules도 원본을 다시 읽어 확인하므로(placePromotions의 ownsSourcePlace),
  /// 여기서 다른 값을 넘겨봐야 저장 단계에서 막힌다.
  final String hostId;

  final String placeName;

  /// 가게 주소 — 등록 화면 상단에 "어디서 열리는 이벤트인지" 보여주는 용도.
  final String address;

  /// 제목 초안. 호스트가 그대로 두든 지우든 자유다.
  final String titleDraft;

  final String sourcePartyId;
  final String sourcePartyTitle;

  /// 이 파티에 이벤트를 붙일 곳이 있는가 — 카드에서 버튼을 보일지 정한다.
  ///
  /// 문서를 읽지 않고 파티 문서의 연결 필드만 본다(목록 카드마다 조회를
  /// 날리지 않으려는 것이다). 실제 존재 여부는 [resolve]에서 확인한다.
  static bool hasLinkedPlace(Map<String, dynamic> party) {
    for (final target in PartyLinkTarget.values) {
      final id = (party[target.linkField] as String?)?.trim() ?? '';
      if (id.isNotEmpty) return true;
    }
    return false;
  }

  /// 파티에 연결된 가게를 찾아 등록 화면에 넘길 값을 만든다. 없으면 null.
  ///
  /// 플레이스(events)를 먼저 본다 — "플레이스 > 이벤트"에 뜨는 것은 그쪽이다
  /// ([PartyLinkTarget]의 선언 순서가 그대로 우선순위다).
  static Future<PartyEventSource?> resolve({
    required String partyId,
    required Map<String, dynamic> party,
  }) async {
    final partyTitle = (party['title'] as String? ?? '').trim();
    for (final target in PartyLinkTarget.values) {
      final id = (party[target.linkField] as String?)?.trim() ?? '';
      if (id.isEmpty) continue;
      final snap = await FirebaseFirestore.instance
          .collection(target.collection)
          .doc(id)
          .get();
      final d = snap.data();
      if (d == null) continue;
      final hostId = (d['hostId'] as String? ?? '').trim();
      if (hostId.isEmpty) continue;
      final name = (d['name'] as String? ?? '').trim();
      return PartyEventSource(
        placeId: id,
        placeCollection: target.collection,
        hostId: hostId,
        placeName: name.isNotEmpty ? name : target.noun,
        address: _addressOf(d),
        titleDraft: partyTitle.isEmpty ? '' : '$partyTitle 이벤트',
        sourcePartyId: partyId,
        sourcePartyTitle: partyTitle,
      );
    }
    return null;
  }

  static String _addressOf(Map<String, dynamic> d) {
    for (final key in ['address', 'roadAddress', 'location', 'jibunAddress']) {
      final v = (d[key] as String? ?? '').trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  // ── 노출 맞추기 ────────────────────────────────────────────────────────────

  /// 이벤트를 저장한 뒤 **플레이스 본체 문서**의 노출 값을 맞춘다.
  ///
  /// 이게 없으면 placePromotions 문서만 생기고 "플레이스 > 이벤트" 목록에는
  /// 끝내 뜨지 않는다 — 그 목록의 정본은 프로모션이 아니라 본체의 `themeTags`다.
  ///
  ///   · `themeTags`의 '이벤트'와 🎉 갈래·종료일 미러를 **한 번에** 다시
  ///     계산해 적는다([eventMirrorUpdate]). 지금 보일 이벤트가 하나도 없으면
  ///     태그도 함께 내려간다 — 예전에는 호스트가 등록 폼에서 손으로 켜고
  ///     꺼야 했다.
  ///   · `eventSubtype`(옛 단일 소분류)이 **비어 있을 때만** 자동 분류 결과를
  ///     넣는다. 이미 값이 있으면 덮지 않는다 — 지금 갈래의 정본은
  ///     [PlaceEventTaxonomy.kindsField]이고, 이 필드는 그 미러가 없던 옛
  ///     문서를 위한 다리로만 남아 있다.
  ///
  /// 갈래는 호스트에게 다시 묻지 않는다 — 이벤트 폼이 이미 받은 유형·상시
  /// 여부·기간·본문에서 떨어진다. 같은 것을 두 번 고르게 하면 두 값이 어긋나는
  /// 순간 어느 쪽이 정본인지 알 수 없어진다.
  ///
  /// **이 가게의 이벤트 전체를 다시 읽어** 계산한다. 방금 저장한 한 건만 보면
  /// 다른 이벤트가 끝났는지·새로 생겼는지를 반영하지 못해 미러가 곧 낡는다.
  /// 그래서 방금 저장한 이벤트가 **숨김이어도 그냥 돌아가지 않는다** — 숨김이
  /// 마지막 한 건이었다면 그 사실이야말로 본체에 반영돼야 한다.
  ///
  /// 장소대여(`places`)에는 '이벤트 진행중' 태그도 갈래도 적지 않는다. 그쪽에도
  /// 🎪 이벤트 축은 있지만(장소대여 탭의 조건과 파티/이벤트 탭의 공간 이벤트)
  /// 둘 다 `placePromotions`를 직접 읽는 색인·피드로만 판정하므로
  /// ([PlaceEventIndex.rentalCollection] / [EventFeed]), 본체 미러를 볼 일이
  /// 없다.
  static Future<void> syncPlaceExposure({
    required String placeId,
    required String placeCollection,
    required PlacePromotion promotion,
  }) async {
    if (placeCollection != 'events') return;
    final now = DateTime.now();

    final ref = FirebaseFirestore.instance.collection('events').doc(placeId);
    final snap = await ref.get();
    final data = snap.data();
    if (data == null) return;

    // 방금 저장한 것까지 포함해 이 가게의 이벤트 전체를 다시 읽는다.
    // (create/update가 이미 커밋된 뒤에 불리므로 목록에 들어 있다. 혹시
    //  읽기가 늦어 빠져 있어도 방금 저장한 건을 더해 계산한다.)
    final all = await PlacePromotionService.listForPlace(placeId);
    final merged = [
      ...all.where((p) => p.id.isEmpty || p.id != promotion.id),
      promotion,
    ];

    final update = <String, dynamic>{...eventMirrorUpdate(merged, now)};

    // 옛 단일 소분류 채우기 — 지금 보일 이벤트일 때만. 숨김·종료된 이벤트로
    // 갈래를 적으면 손님이 눌러 들어와 아무것도 못 보는 상태가 된다.
    final current = (data['eventSubtype'] as String? ?? '').trim();
    if (current.isEmpty && promotion.statusAt(now).isPublic) {
      final auto = ListingConstants.autoEventSubtypeFor(promotion.searchTexts);
      if (auto != null) update['eventSubtype'] = auto;
    }

    update['updatedAt'] = FieldValue.serverTimestamp();
    await ref.update(update);
  }

  /// 플레이스 본체에 적을 🎉 이벤트 미러 — **'이벤트 진행중' 태그**와
  /// 갈래 배열, 종료일.
  ///
  /// 태그(`themeTags`의 '이벤트')도 여기서 함께 정한다. 예전에는 호스트가
  /// 플레이스 등록·수정 폼의 '특징 태그'에서 손으로 켜고 껐지만, 같은 사실을
  /// 두 곳에서 정하니 늘 한쪽이 틀렸다 — 태그만 켜 두면 이벤트가 하나도 없는데
  /// 이벤트 탐색에 걸리고, 이벤트를 올리고 태그를 안 켜면 목록에 뜨지 않았다.
  /// 그래서 태그는 **지금 손님에게 보일 이벤트가 하나라도 있는가**로만
  /// 결정한다([PromotionStatus.isPublic] — 숨김·종료는 빠진다).
  ///
  ///   · 있으면 [FieldValue.arrayUnion] — 다른 태그('핫플' 등)는 건드리지 않는다.
  ///   · 없으면 [FieldValue.arrayRemove] — 마지막 이벤트를 지우거나 종료(숨김)
  ///     하면 이벤트 탐색에서 스스로 빠진다.
  ///
  /// ⚠️ 이 함수는 **이벤트가 바뀔 때만** 불린다(등록/수정/숨김/삭제). 이벤트가
  /// 한 번도 없었던 플레이스 — 예전에 태그만 손으로 켜 둔 문서들 — 은 여기에
  /// 걸리지 않으므로 지금 달린 태그가 그대로 남는다. 일괄 정리는 하지 않는다.
  ///
  /// 갈래·종료일은 값이 비면 **필드를 지운다**([FieldValue.delete]) — 빈 배열이나
  /// null을 남겨 두면 "갈래가 없다"와 "아직 계산한 적 없다"가 구분되지 않는다.
  /// 종료일이 없다는 것은 상시 이벤트가 있거나 종료일 없는 이벤트가 있다는
  /// 뜻이라, 기간으로는 끝나지 않는다는 말과 같다.
  ///
  /// 이벤트 등록 화면(개별 저장)과 등록 폼(목록 치환)이 **같은 함수**를 쓰므로
  /// 두 입구가 서로 다른 미러를 적을 수 없다.
  static Map<String, dynamic> eventMirrorUpdate(
    Iterable<PlacePromotion> promotions,
    DateTime now,
  ) {
    final mirror = PlaceEventTaxonomy.mirrorFrom(promotions, now);
    final hasPublic = promotions.any((p) => p.statusAt(now).isPublic);
    return {
      'themeTags': hasPublic
          ? FieldValue.arrayUnion([ListingConstants.placeEventTag])
          : FieldValue.arrayRemove([ListingConstants.placeEventTag]),
      PlaceEventTaxonomy.kindsField: mirror.kinds.isEmpty
          ? FieldValue.delete()
          : mirror.kinds.toList(),
      PlaceEventTaxonomy.endsAtField: mirror.endsAt == null
          ? FieldValue.delete()
          : Timestamp.fromDate(mirror.endsAt!),
    };
  }
}
