import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';

// ═════════════════════════════════════════════════════════════════════════
// 파티샵 판매자 판정 — "이 사용자가 **실제로 등록해 보유 중인** 파티샵이
// 있는가" 하나만 답한다.
//
// 파티·플레이스·장소대여 호스트라거나 사업자 인증을 마쳤다는 사실로는 절대
// 판정하지 않는다. 파티샵은 다른 카테고리와 컬렉션(`partyShops`)도 주문 축도
// 완전히 별개라, 파티 호스트에게 "판매 내역"을 보여주면 영원히 빈 화면이다.
//
// ── 삭제·폐점을 어떻게 보는가 ──────────────────────────────────────────
//   · 삭제 — 파티샵 삭제는 서버가 문서 자체를 지우는 하드 삭제다
//     (functions/contentCleanup.js의 cleanupContentDoc → docRef.delete()).
//     그래서 지운 순간 이 쿼리 결과에서도 사라지고 판매자 메뉴도 함께
//     사라진다. 혹시 남아 있을 수 있는 soft-delete 흔적(isDeleted/status)은
//     내 파티 목록과 같은 기준으로 한 번 더 걸러 낸다.
//   · 폐점(운영 중지, `isActive == false`) — **보유 중으로 본다**. 문서는
//     그대로 있고 [MyShopHubScreen]의 '내 파티샵' 탭에 '운영 중지'로 남아
//     다시 운영 중으로 되돌릴 수 있어야 한다. 여기서 메뉴를 숨겨 버리면
//     재개할 진입로가 사라진다. 지난 판매 내역도 계속 볼 수 있어야 한다.
// ═════════════════════════════════════════════════════════════════════════

class PartyShopOwnershipService {
  PartyShopOwnershipService._();

  /// 소프트 삭제 흔적까지 감안해 넉넉히 훑는 상한. 한 사람이 이보다 많은
  /// 파티샵을 갖더라도 "하나라도 있는가"라는 판정에는 영향이 없다.
  static const int _probeLimit = 20;

  /// uid별 마지막 판정값 — 화면을 다시 열 때 첫 스냅샷이 도착하기 전까지
  /// 탭이 없다가 뒤늦게 붙어 깜빡이는 것을 막는 용도로만 쓴다.
  static final Map<String, bool> _lastKnown = <String, bool>{};

  /// 알고 있는 직전 판정값(모르면 null). 화면은 이 값을 initialData로만 쓰고
  /// 판정 자체는 항상 [watch]의 스냅샷으로 갱신한다.
  static bool? cached() => _lastKnown[UserSession.userId];

  /// 문서 묶음으로 판매자 여부를 판정한다 — 쿼리와 분리해 둔 **규칙 본체**.
  ///
  /// 하나라도 살아 있는 파티샵이 있으면 판매자다. 어디서 읽어 왔는지와
  /// 무관하게 같은 규칙을 쓰도록 여기 하나만 둔다.
  static bool hasLiveShop(Iterable<Map<String, dynamic>> shops) =>
      shops.any(_isLive);

  /// 마이페이지·파티샵 허브가 구독할 판매자 여부.
  ///
  /// 읽기에 실패하면(권한/네트워크) 값을 내리지 않는다 — StreamBuilder는
  /// 직전 값(없으면 false)을 유지하므로, 판매자가 아닌 사람에게 판매 메뉴가
  /// 잘못 열리는 일은 생기지 않는다.
  static Stream<bool> watch() {
    final uid = UserSession.userId;
    if (uid.isEmpty) return Stream<bool>.value(false);
    return FirebaseFirestore.instance
        .collection('partyShops')
        .where('hostId', isEqualTo: uid)
        .limit(_probeLimit)
        .snapshots()
        .map((snap) {
          final has = hasLiveShop(snap.docs.map((d) => d.data()));
          _lastKnown[uid] = has;
          return has;
        })
        .handleError(
          (Object e, StackTrace st) =>
              logFirestoreStreamError('PartyShopOwnershipService.watch', e, st),
        );
  }

  /// 살아 있는 샵인가 — 운영 중지(isActive == false)는 살아 있는 것으로 본다.
  static bool _isLive(Map<String, dynamic> d) =>
      d['isDeleted'] != true && d['status'] != 'deleted';
}
