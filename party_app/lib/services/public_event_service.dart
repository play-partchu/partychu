import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:party_app/models/public_event.dart';

/// 공공 축제·행사(publicEvents)의 **읽기 전용** 창구.
///
/// 문서는 서버(syncTourFestivals)만 쓴다 — 규칙이 클라이언트 쓰기를 전부
/// 막으므로 여기에도 쓰기 메서드를 두지 않는다.
///
/// 조회는 `isVisible == true` 하나뿐이다. 같음 조건 하나라 복합 색인이
/// 필요 없다. 끝난 행사 거르기와 정렬은 앱에서 한다([openSorted]) — 서버가
/// 매일 04:30(KST)에 끝난 행사를 숨기므로, 그 사이(어제 끝난 행사가 새벽까지
/// 남는 구간)만 여기서 걸러 내면 된다. 전국 축제가 수백 건이라 전부 받아도
/// 부담이 없다.
class PublicEventService {
  PublicEventService._();

  static const String collection = 'publicEvents';

  static FirebaseFirestore get _fs => FirebaseFirestore.instance;

  static Query<Map<String, dynamic>> _visible() =>
      _fs.collection(collection).where('isVisible', isEqualTo: true);

  /// 지금 볼 수 있는 행사(진행 중·예정) — 정렬까지 마친 목록.
  static Stream<List<PublicEvent>> watchOpen() => _visible()
      .snapshots()
      .map((s) => openSorted(_map(s), now: DateTime.now()));

  static Future<List<PublicEvent>> listOpen() async =>
      openSorted(_map(await _visible().get()), now: DateTime.now());

  /// 끝나지 않은 것만 남기고 "곧 볼 수 있는 것"부터 세운다.
  ///
  /// 기준은 이벤트 피드([EventFeed])와 같다 — 정렬 시각은
  /// max(시작, 지금)이라 이미 진행 중인 행사는 모두 '지금'으로 앞에 서고,
  /// 예정 행사는 시작이 가까운 순으로 뒤따른다. 같은 시각끼리는 곧 끝나는
  /// 것부터(놓치기 쉬운 것을 앞에), 그래도 같으면 문서 id로 갈라 스냅샷이
  /// 새로 와도 순서가 까닭 없이 바뀌지 않는다.
  static List<PublicEvent> openSorted(
    Iterable<PublicEvent> events, {
    required DateTime now,
  }) {
    final open = events.where((e) => e.isVisible && e.isOpenAt(now)).toList();
    DateTime sortAt(PublicEvent e) => e.startAt.isBefore(now) ? now : e.startAt;
    open.sort((a, b) {
      final c = sortAt(a).compareTo(sortAt(b));
      if (c != 0) return c;
      final e = a.endAt.compareTo(b.endAt);
      return e != 0 ? e : a.id.compareTo(b.id);
    });
    return open;
  }

  static List<PublicEvent> _map(QuerySnapshot<Map<String, dynamic>> s) => [
    for (final d in s.docs) ?PublicEvent.tryFromMap(d.id, d.data()),
  ];
}
