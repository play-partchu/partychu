import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:party_app/models/place_menu.dart';

/// 매장 메뉴의 읽기/쓰기 창구.
///
/// 프로모션([PlacePromotionService])과 **같은 구조**다 — 결제·재고·주문이 없어
/// 서버 함수가 필요 없고, 사장님이 firestore.rules 아래에서 직접 쓰고 손님은
/// 읽기만 한다.
class PlaceMenuService {
  PlaceMenuService._();

  static const String collection = 'placeMenus';

  static FirebaseFirestore get _fs => FirebaseFirestore.instance;

  static Query<Map<String, dynamic>> _q(String placeId) => _fs
      .collection(collection)
      .where('placeId', isEqualTo: placeId)
      .orderBy('sortOrder');

  /// 이 플레이스의 메뉴 전체(사장님 관리용) — 숨긴 메뉴도 포함한다.
  static Stream<List<PlaceMenu>> watchForPlace(String placeId) =>
      _q(placeId).snapshots().map(_map);

  static Future<List<PlaceMenu>> listForPlace(String placeId) async =>
      _map(await _q(placeId).get());

  /// 손님에게 보여줄 메뉴 — 숨긴 것만 뺀다. 프로모션과 달리 기간 개념이
  /// 없으므로 시각에 따라 달라지는 판정도 없다.
  static Stream<List<PlaceMenu>> watchPublicForPlace(String placeId) =>
      watchForPlace(
        placeId,
      ).map((all) => all.where((m) => m.isVisible && m.isFilled).toList());

  static List<PlaceMenu> _map(QuerySnapshot<Map<String, dynamic>> s) =>
      s.docs.map((d) => PlaceMenu.fromMap(d.id, d.data())).toList();

  /// 등록/수정 화면의 목록을 Firestore에 그대로 맞춘다.
  ///
  /// 프로모션과 같은 정책이다 — 목록에서 빠진 메뉴는 그냥 지운다(발급된
  /// 이용권 같은 참조가 없다). 이름이 비어 있는 항목은 "쓰다 만 줄"로 보고
  /// 저장하지 않는다. 화면에 보이는 순서가 곧 [PlaceMenu.sortOrder]가 된다.
  static Future<void> syncForPlace({
    required String placeId,
    required String placeCollection,
    required String hostId,
    required List<PlaceMenu> menus,
  }) async {
    final existing = await listForPlace(placeId);
    final existingIds = {for (final m in existing) m.id};
    final keptIds = <String>{};

    for (var i = 0; i < menus.length; i++) {
      final draft = menus[i].copyWith(sortOrder: i);
      if (!draft.isFilled) continue;

      final prepared = PlaceMenu.fromMap(draft.id, {
        ...draft.toMap(),
        'placeId': placeId,
        'placeCollection': placeCollection,
        'hostId': hostId,
      });

      if (draft.id.isNotEmpty && existingIds.contains(draft.id)) {
        keptIds.add(draft.id);
        await _fs.collection(collection).doc(draft.id).update({
          ...prepared.toMap()..remove('hostId'),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final ref = _fs.collection(collection).doc();
        await ref.set({
          ...prepared.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        keptIds.add(ref.id);
        // 발급된 id를 호출한 화면의 목록에 되돌려 넣는다([menus]는 화면이 들고
        // 있는 리스트 그 자체다) — 안 그러면 화면을 벗어나지 않고 다시 저장할
        // 때 같은 메뉴가 새 문서로 또 만들어진다.
        menus[i] = draft.copyWith(id: ref.id);
      }
    }

    for (final old in existing) {
      if (keptIds.contains(old.id)) continue;
      await _fs.collection(collection).doc(old.id).delete();
    }
  }
}
