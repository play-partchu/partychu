import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:party_app/widgets/partychu_perk.dart';

/// 콤보(플레이스+파티 / 숙박+파티)로 등록한 게시글은 문서가 2개 이상이다 —
/// 플레이스 문서(`events` 또는 `places`) 1개 + 파티 문서(`parties`) 1개 이상이
/// 같은 `bundleId`로 묶여 있고, 파티·플레이스 상세가 각자 자기 문서의
/// `partychuPerk`를 읽는다.
///
/// 그래서 어느 수정 화면에서 혜택을 고치든 **묶음 전체에 같은 값**이 들어가야
/// 한쪽 상세에서는 옛 혜택이, 다른 쪽에서는 새 혜택이 보이는 일이 없다.
/// 콤보 전용 수정 화면이 따로 없기 때문에(파티 수정 / 플레이스 수정 /
/// 장소 수정이 각자 자기 문서만 고친다) 이 동기화가 필요하다.
///
/// [bundleId]가 없으면(= 콤보가 아닌 일반 게시글) 아무것도 하지 않는다.
/// 실패해도 예외를 던지지 않는다 — 사용자가 누른 "수정"은 자기 문서 저장까지
/// 이미 성공한 상태라, 묶음 갱신 실패로 저장 자체를 실패 처리하면 안 된다.
Future<void> syncPartychuPerkAcrossBundle({
  required String? bundleId,
  required String perk,

  /// 이미 갱신한 자기 문서 — 중복 쓰기를 피하려고 제외한다.
  required String selfDocId,
}) async {
  if (bundleId == null || bundleId.isEmpty) return;

  final db = FirebaseFirestore.instance;
  final batch = db.batch();
  var pending = 0;

  for (final collection in const ['parties', 'events', 'places']) {
    try {
      // bundleId 단일 필드 동등 조건이라 Firestore 자동 색인만으로 동작한다
      // (복합 인덱스 불필요).
      final snap = await db
          .collection(collection)
          .where('bundleId', isEqualTo: bundleId)
          .get();
      for (final doc in snap.docs) {
        if (doc.id == selfDocId) continue;
        batch.update(doc.reference, {kPartychuPerkField: perk});
        pending++;
      }
    } catch (e) {
      // 한 컬렉션 조회가 실패해도 나머지는 계속 시도한다.
      debugPrint('[perk-sync] $collection 조회 실패(무시): $e');
    }
  }

  if (pending == 0) return;
  try {
    await batch.commit();
    debugPrint('[perk-sync] bundle=$bundleId 문서 $pending개 혜택 동기화 완료');
  } catch (e) {
    debugPrint('[perk-sync] 묶음 갱신 실패(무시): $e');
  }
}
