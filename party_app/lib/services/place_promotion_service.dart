import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/services/party_event_source.dart';

/// 매장 이벤트·프로모션의 읽기/쓰기 창구.
///
/// 상품([PlaceProductService])과 달리 결제·재고·주문이 없어 서버 함수가 필요
/// 없다 — 사장님이 firestore.rules 아래에서 직접 쓰고 손님은 읽기만 한다.
class PlacePromotionService {
  PlacePromotionService._();

  static const String collection = 'placePromotions';

  static FirebaseFirestore get _fs => FirebaseFirestore.instance;

  static Query<Map<String, dynamic>> _q(String placeId) => _fs
      .collection(collection)
      .where('placeId', isEqualTo: placeId)
      .orderBy('sortOrder');

  /// 이 플레이스의 프로모션 전체(사장님 관리용) — 숨김·종료도 포함한다.
  static Stream<List<PlacePromotion>> watchForPlace(String placeId) =>
      _q(placeId).snapshots().map(_map);

  static Future<List<PlacePromotion>> listForPlace(String placeId) async =>
      _map(await _q(placeId).get());

  /// 이 장소에 **속한** 이벤트만 남긴다 — 플레이스(events)와 공간대여(places)를
  /// 가른다.
  ///
  /// 조회는 `placeId` 하나로만 한다(위 [_q]). 문서 id는 Firestore가 만든
  /// 값이라 두 컬렉션 사이에서 겹칠 일이 사실상 없지만, "플레이스 카드에는
  /// 그 플레이스의 이벤트만"이라는 규칙을 화면이 아니라 여기서 지킨다 —
  /// 소속은 문서가 이미 갖고 있는 [PlacePromotion.placeCollection]으로 본다
  /// (새 필드를 만들지 않는다).
  static List<PlacePromotion> belongingTo(
    Iterable<PlacePromotion> all, {
    required String placeCollection,
  }) => all.where((p) => p.placeCollection == placeCollection).toList();

  /// 호스트 카드의 `✨ 연결 이벤트 N개`가 쓰는 경량 조회.
  ///
  /// 세는 범위는 **관리 화면과 같다** — 숨김·종료도 포함한 전부
  /// ([watchForPlace]가 관리 목록에 그리는 것과 같은 집합). 이벤트에는 소프트
  /// 삭제가 없어(삭제는 문서 자체를 지운다) 지워진 건은 애초에 잡히지 않는다.
  ///
  /// 🎉 연결 파티 개수([PlacePartyLink.countLinkedParties] — 삭제되지 않은
  /// 연결 전부, 지난 회차도 포함)와 **의미가 같은 자리**다: 둘 다 "이 장소를
  /// 관리하면 보게 되는 것의 개수"이지 "지금 손님에게 보이는 개수"가 아니다.
  /// 그래서 여기서 [PlacePromotion.statusAt]으로 거르지 않는다.
  static Future<int> countForPlace({
    required String placeId,
    required String placeCollection,
  }) async {
    if (placeId.isEmpty) return 0;
    final all = await listForPlace(placeId);
    return belongingTo(all, placeCollection: placeCollection).length;
  }

  /// 손님에게 보여줄 프로모션 — 숨김·종료를 제외한다.
  ///
  /// 상태를 서버 쿼리로 거르지 않는 이유는 상품과 같다 — 상태는 시각에 따라
  /// 달라지는 계산값이라 `statusMirror`로 걸면 낡은 미러 때문에 잘못 사라진다.
  static Stream<List<PlacePromotion>> watchPublicForPlace(String placeId) =>
      watchForPlace(placeId).map((all) {
        final now = DateTime.now();
        return all.where((p) => p.statusAt(now).isPublic).toList();
      });

  /// 앱 전체의 **손님에게 보여줄 이벤트** — 🎪 이벤트 색인이 쓴다
  /// ([PlaceEventIndex]. 목록·지도가 이 스트림으로 "이벤트 중인 매장" 집합을
  /// 만든다).
  ///
  /// 매장 하나가 아니라 컬렉션 전체를 본다는 점만 [watchPublicForPlace]와
  /// 다르고, 상태 판정은 똑같이 [PlacePromotion.statusAt]이 한다 — 그래서
  /// 🎪 이벤트로 걸러 들어갔는데 매장 상세에는 볼 이벤트가 없는(또는 그
  /// 반대인) 상태가 생길 수 없다.
  ///
  /// ⚠️ `isVisible`만 **서버에서** 거른다. Firestore의 등호 필터는 필드가 아예
  /// 없는 문서를 제외하므로 보통은 조심해야 하지만(플레이스 목록의 `isActive`
  /// 주석 참고), 이 필드는 쓰기 경로가 전부 [PlacePromotion.toMap]과
  /// [setVisible] 둘뿐이고 양쪽 다 **항상** 적는다 — 그 전제는
  /// place_event_index_test.dart가 지킨다. 기간(시작 전·종료)을 서버에서 걸지
  /// 않는 이유는 위와 같다: 시각에 따라 달라지는 계산값이라 미러로 걸면 낡는다.
  static Stream<List<PlacePromotion>> watchPublicAll() => _fs
      .collection(collection)
      .where('isVisible', isEqualTo: true)
      .snapshots()
      .map((s) {
        final now = DateTime.now();
        return _map(s).where((p) => p.statusAt(now).isPublic).toList();
      });

  static List<PlacePromotion> _map(QuerySnapshot<Map<String, dynamic>> s) =>
      s.docs.map((d) => PlacePromotion.fromMap(d.id, d.data())).toList();

  // ── 개별 문서 CRUD ───────────────────────────────────────────────────────
  //
  // 기존 장소에 **이벤트만 따로** 추가·수정·종료하는 관리 화면이 쓰는 창구다.
  // [syncForPlace]와 달리 목록 전체를 치환하지 않으므로, 다른 곳에서 만든
  // 이벤트를 실수로 지우지 않는다.

  // ── 숨긴 시각(hiddenAt) ──────────────────────────────────────────────────
  //
  // 호스트가 '종료'를 눌러 감춘 이벤트는 **그 순간부터 14일 뒤 자동 삭제**된다
  // (functions/index.js의 deleteExpiredPromotions). 그러려면 "언제 감췄는지"가
  // 필요한데, 이벤트 문서에는 그 시각이 없었다.
  //
  // updatedAt으로 대신 셀 수는 없다 — 마지막 수정은 감추기 훨씬 전일 수도,
  // 감춘 뒤의 사소한 편집일 수도 있어서 "감춘 지 하루 된 이벤트"가 곧바로
  // 삭제되거나 영영 남는다. 그래서 **감춘 시각 전용 필드**를 따로 둔다.
  //
  // 규칙은 장소대여의 hiddenAt과 똑같다(place_register_screen.dart):
  //   · 감출 때  → 서버 시각을 적는다. **이미 있으면 덮지 않는다** — 감춘 뒤
  //                내용을 손봤다고 삭제 기한이 밀리면 안 된다.
  //   · 다시 노출 → 지운다. 그 순간 자동 삭제 대상에서 빠진다.
  static Map<String, dynamic> _hiddenAtField({
    required bool isVisible,
    required bool alreadyHidden,
  }) {
    if (isVisible) return {'hiddenAt': FieldValue.delete()};
    return alreadyHidden
        ? const {}
        : {'hiddenAt': FieldValue.serverTimestamp()};
  }

  /// 저장된 문서에 hiddenAt이 이미 있는가 — 없으면(문서가 없어도) false.
  static Future<bool> _hasHiddenAt(String id) async {
    if (id.isEmpty) return false;
    final snap = await _fs.collection(collection).doc(id).get();
    return snap.data()?['hiddenAt'] != null;
  }

  static Future<PlacePromotion?> fetch(String id) async {
    final d = await _fs.collection(collection).doc(id).get();
    final data = d.data();
    return data == null ? null : PlacePromotion.fromMap(d.id, data);
  }

  /// 새 이벤트 한 건. 정렬 순서는 기존 목록 뒤에 붙인다.
  ///
  /// [placeId]·[placeCollection]·[hostId]는 **호출부가 아니라 원본 장소에서**
  /// 온 값이어야 한다 — 남의 장소에 붙이는 걸 막는 최종 방어선은 rules지만,
  /// 여기서도 원본과 같은 값만 쓰도록 인자를 강제한다.
  static Future<String> create({
    required String placeId,
    required String placeCollection,
    required String hostId,
    required PlacePromotion promotion,
  }) async {
    final existing = await listForPlace(placeId);
    final prepared = promotion.copyWith(sortOrder: existing.length);
    final ref = _fs.collection(collection).doc();
    await ref.set({
      ...prepared.toMap(),
      'placeId': placeId,
      'placeCollection': placeCollection,
      'hostId': hostId,
      'createdAt': FieldValue.serverTimestamp(),
      // 감춘 채로 만든 이벤트도 보관기간이 그때부터 시작한다.
      if (!prepared.isVisible) 'hiddenAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// 기존 이벤트 수정. 소속(placeId/placeCollection/hostId)은 건드리지 않는다 —
  /// rules에서도 hostId 변경을 막고 있고, 옮겨 붙이기는 허용하지 않는다.
  static Future<void> update(PlacePromotion promotion) async {
    if (promotion.id.isEmpty) {
      throw ArgumentError('id 없는 이벤트는 수정할 수 없다');
    }
    final map = promotion.toMap()
      ..remove('hostId')
      ..remove('placeId')
      ..remove('placeCollection');
    await _fs.collection(collection).doc(promotion.id).update({
      ...map,
      ..._hiddenAtField(
        isVisible: promotion.isVisible,
        alreadyHidden: await _hasHiddenAt(promotion.id),
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 노출 스위치만 토글한다 — "종료" 버튼이 쓰는 경로(문서는 남긴다).
  static Future<void> setVisible(String id, bool visible) async {
    final target = await fetch(id);
    final alreadyHidden = await _hasHiddenAt(id);
    await _fs.collection(collection).doc(id).update({
      'isVisible': visible,
      // 여기가 '종료' 버튼이 지나는 자리다 — 보관기간(14일)의 기준점이 된다.
      ..._hiddenAtField(isVisible: visible, alreadyHidden: alreadyHidden),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _refreshMirrorFor(target);
  }

  static Future<void> deleteById(String id) async {
    final target = await fetch(id);
    await _fs.collection(collection).doc(id).delete();
    await _refreshMirrorFor(target);
  }

  /// 이벤트 하나를 숨기거나 지운 뒤 본체의 🎪 미러를 다시 계산한다.
  ///
  /// 이게 없으면 "종료" 눌러 감춘 이벤트의 갈래가 본체에 남아, 이벤트 탐색에
  /// 걸려 들어왔는데 볼 이벤트가 없는 상태가 된다.
  static Future<void> _refreshMirrorFor(PlacePromotion? target) async {
    if (target == null || target.placeId.isEmpty) return;
    await syncPlaceEventMirror(
      placeId: target.placeId,
      placeCollection: target.placeCollection,
      promotions: await listForPlace(target.placeId),
    );
  }

  /// 등록/수정 화면의 목록을 Firestore에 그대로 맞춘다.
  ///
  /// 프로모션은 발급된 이용권 같은 참조가 없으므로, 목록에서 빠지면 그냥
  /// 지운다(상품처럼 "팔린 건 못 지운다" 제약이 없다). 제목이 비어 있는
  /// 항목은 "쓰다 만 카드"로 보고 저장하지 않는다.
  static Future<void> syncForPlace({
    required String placeId,
    required String placeCollection,
    required String hostId,
    required List<PlacePromotion> promotions,
  }) async {
    final existing = await listForPlace(placeId);
    final existingIds = {for (final p in existing) p.id};
    final keptIds = <String>{};

    for (var i = 0; i < promotions.length; i++) {
      final draft = promotions[i].copyWith(sortOrder: i);
      if (draft.title.trim().isEmpty) continue;

      final prepared = PlacePromotion.fromMap(draft.id, {
        ...draft.toMap(),
        'placeId': placeId,
        'placeCollection': placeCollection,
        'hostId': hostId,
      });

      if (draft.id.isNotEmpty && existingIds.contains(draft.id)) {
        keptIds.add(draft.id);
        // 감춤이 이번 저장에서 **새로 생긴 것일 때만** 시각을 적는다. 저장 전
        // 상태는 이미 읽어 뒀으므로(existing) 문서를 다시 읽지 않는다.
        final before = existing.firstWhere((p) => p.id == draft.id);
        await _fs.collection(collection).doc(draft.id).update({
          ...prepared.toMap()..remove('hostId'),
          ..._hiddenAtField(
            isVisible: prepared.isVisible,
            alreadyHidden: !before.isVisible,
          ),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final ref = _fs.collection(collection).doc();
        await ref.set({
          ...prepared.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
          if (!prepared.isVisible) 'hiddenAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        keptIds.add(ref.id);
        // 발급된 id를 호출한 화면의 목록에 되돌려 넣는다([promotions]는 화면이
        // 들고 있는 리스트 그 자체다) — 안 그러면 화면을 벗어나지 않고 다시
        // 저장할 때 같은 이벤트가 새 문서로 또 만들어진다.
        promotions[i] = draft.copyWith(id: ref.id);
      }
    }

    for (final old in existing) {
      if (keptIds.contains(old.id)) continue;
      await _fs.collection(collection).doc(old.id).delete();
    }

    await syncPlaceEventMirror(
      placeId: placeId,
      placeCollection: placeCollection,
      promotions: promotions,
    );
  }

  /// 플레이스 본체에 🎪 이벤트 **갈래·종료일 미러**를 다시 적는다.
  ///
  /// 목록·지도는 `events` 문서 하나만 읽으므로, 이 미러가 없으면 이벤트
  /// 소분류로는 아무것도 걸러지지 않는다([PlaceEventTaxonomy] 참고).
  /// 계산은 [PartyEventSource.eventMirrorUpdate] 하나가 하므로 이벤트 관리
  /// 화면(개별 CRUD)과 등록 폼(목록 치환)이 다른 값을 적을 수 없다.
  ///
  /// **실패해도 저장을 되돌리지 않는다.** 이벤트 자체는 이미 저장돼 가게
  /// 상세에 떠 있고, 미러는 다음 저장 때 다시 계산된다 — 여기서 예외를 올리면
  /// "저장이 끝난 뒤에 저장 실패라고 말하는" 더 나쁜 상태가 된다.
  ///
  /// 장소대여(`places`)에는 미러를 적지 않는다. 장소대여에도 🎪 이벤트 축은
  /// 있지만([PlaceFilter.matchesEvent]) 그 판정은 **색인 하나만** 본다
  /// ([PlaceEventIndex.rentalCollection]) — 미러로 되짚는 갈래 조건도, 미러로
  /// 버티는 폴백도 플레이스 탭 쪽에만 있다. 여기서 `places` 문서에 태그를
  /// 적으면 아무도 읽지 않는 값이 하나 더 생길 뿐이다.
  static Future<void> syncPlaceEventMirror({
    required String placeId,
    required String placeCollection,
    required List<PlacePromotion> promotions,
  }) async {
    if (placeCollection != 'events') return;
    try {
      await _fs.collection('events').doc(placeId).update({
        ...PartyEventSource.eventMirrorUpdate(promotions, DateTime.now()),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // 삼킨다 — 위 주석 참고.
    }
  }
}
