// ─────────────────────────────────────────────────────────────────────────────
// 매장 이벤트 **신청**의 창구.
//
// ── 쓰기는 전부 서버가 한다 ──────────────────────────────────────────────────
// 신청·취소는 콜러블만 한다(applyToPlaceEvent / cancelPlaceEventApplication).
// firestore.rules는 placeEventApplications의 **클라이언트 쓰기를 전면 차단**
// 하므로, 앱이 직접 쓰려고 해도 permission-denied다. 이 파일이 Firestore에
// 하는 일은 **읽기뿐**이다.
//
// 왜 이렇게 되었나 — 종료된 이벤트 때문이다. "종료된 이벤트에는 신청할 수
// 없다"는 `isAlways`·`endAt`을 "그 날 23:59:59"로 접는 계산이고
// ([PlacePromotion.statusAt]), 이 판정을 rules로 옮겨 적으면 하루의 경계에서
// 앱과 어긋난다. 규칙에 넣지 않으면 변조된 클라이언트가 종료된 이벤트에 그대로
// 신청을 넣는다 — "버튼이 안 보인다"는 방어가 아니다. 그래서 판정을 서버
// 한 곳에 모았다(functions/placeEventApplications.js).
//
// 앱이 보내는 것은 `eventId` 하나뿐이다. hostId·placeId·제목·장소명·일정은
// 서버가 원본 이벤트에서 읽어 적는다 — 위조할 입력 자체가 없다.
//
// ── 읽기 두 갈래 ─────────────────────────────────────────────────────────────
//   · 게스트 — 내 신청 문서를 직접 읽는다(규칙의 `guestId == uid`).
//   · 호스트 — 건수는 Firestore 쿼리로, **이름이 필요한 목록은 콜러블**로.
//     닉네임·실명은 users 문서에 있고 본인·관리자만 읽을 수 있어서 앱이 직접
//     조회할 방법이 없다(파티가 `getApplicants`를 두는 것과 같은 이유).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:party_app/models/place_event_application.dart';
import 'package:party_app/utils/applicant_identity.dart';

/// 호스트 신청자 목록의 한 줄 — 신청 문서 + 서버가 붙여 준 신원.
class PlaceEventApplicant {
  const PlaceEventApplicant({
    required this.applicationId,
    required this.identity,
    required this.status,
    this.appliedAt,
  });

  final String applicationId;

  /// 호스트에게 보여줄 신원(닉네임·실명·본인확인 성별·생년).
  /// **uid는 이 자리에 오지 않는다** — 파티 신청자 화면과 같은 원칙이다.
  final ApplicantIdentity identity;

  final PlaceEventApplicationStatus status;
  final DateTime? appliedAt;

  bool get isApplied => status.countsAsApplicant;

  /// `여성 · 냥냥이(홍길동) · 91년생 (35세)` — 파티 신청자 화면과 같은 표기다.
  String get displayLabel => identity.displayLabel();

  factory PlaceEventApplicant.fromCallable(Map<Object?, Object?> m) {
    final ms = (m['appliedAt'] as num?)?.toInt();
    return PlaceEventApplicant(
      applicationId: m['applicationId'] as String? ?? '',
      identity: ApplicantIdentity.fromMap(
        m['identity'] as Map<Object?, Object?>?,
      ),
      status: PlaceEventApplicationStatus.fromKey(m['status'] as String?),
      appliedAt: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }
}

class PlaceEventApplicationService {
  PlaceEventApplicationService._();

  static const String _region = 'asia-northeast3';

  static FirebaseFirestore get _fs => FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _col =>
      _fs.collection(PlaceEventApplication.collection);

  static HttpsCallable _callable(String name) =>
      FirebaseFunctions.instanceFor(region: _region).httpsCallable(name);

  static DocumentReference<Map<String, dynamic>> docRef({
    required String eventId,
    required String guestId,
  }) => _col.doc(
    PlaceEventApplication.docIdFor(eventId: eventId, guestId: guestId),
  );

  // ── 게스트 ──────────────────────────────────────────────────────────────

  /// **내** 신청 한 건을 지켜본다. 없으면 null.
  ///
  /// 문서 하나만 보므로 목록 쿼리가 아니다 — 규칙의 `guestId == uid()` 하나로
  /// 통과하고, 색인도 필요 없다.
  static Stream<PlaceEventApplication?> watchMine({
    required String eventId,
    required String guestId,
  }) {
    if (eventId.isEmpty || guestId.isEmpty) {
      return Stream<PlaceEventApplication?>.value(null);
    }
    return docRef(eventId: eventId, guestId: guestId).snapshots().map((d) {
      final data = d.data();
      if (data == null) return null;
      return PlaceEventApplication.fromMap(d.id, data);
    });
  }

  /// 내 신청 **전체** — 게스트 허브의 '🎪 매장 이벤트 신청' 구획이 쓴다.
  ///
  /// 목록에 필요한 값(제목·장소명·일정)은 전부 신청 문서에 서버가 베껴 둔
  /// 스냅샷이라, 이벤트 문서를 N번 되짚지 않는다.
  ///
  /// 정렬은 앱에서 한다 — `where(guestId) + orderBy(createdAt)`은 복합 색인을
  /// 요구하는데, 한 사람의 신청은 색인을 새로 배포할 만큼 많지 않다.
  static Stream<List<PlaceEventApplication>> watchMyApplications(
    String guestId,
  ) {
    if (guestId.isEmpty) {
      return Stream<List<PlaceEventApplication>>.value(const []);
    }
    return _col.where('guestId', isEqualTo: guestId).snapshots().map((snap) {
      final list = snap.docs
          .map((d) => PlaceEventApplication.fromMap(d.id, d.data()))
          .toList();
      list.sort((a, b) {
        final at = a.createdAt;
        final bt = b.createdAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at); // 최근 신청이 위로
      });
      return list;
    });
  }

  static Future<PlaceEventApplication?> fetchMine({
    required String eventId,
    required String guestId,
  }) async {
    if (eventId.isEmpty || guestId.isEmpty) return null;
    final d = await docRef(eventId: eventId, guestId: guestId).get();
    final data = d.data();
    return data == null ? null : PlaceEventApplication.fromMap(d.id, data);
  }

  /// 신청한다(무른 신청을 다시 켜는 것도 같은 호출이다).
  ///
  /// 보내는 것은 eventId 하나뿐이다. 이벤트가 실제로 신청을 받는 상태인지
  /// (존재·노출·applyMode·**종료되지 않음**·내 이벤트가 아님·본인확인)는 전부
  /// 서버가 원본을 읽어 판정한다.
  static Future<void> apply(String eventId) async {
    await _callable('applyToPlaceEvent').call<Map<Object?, Object?>>({
      'eventId': eventId,
    });
  }

  /// 신청을 무른다. 문서는 남고 상태만 바뀐다.
  static Future<void> cancel(String eventId) async {
    await _callable(
      'cancelPlaceEventApplication',
    ).call<Map<Object?, Object?>>({'eventId': eventId});
  }

  // ── 호스트 ──────────────────────────────────────────────────────────────

  /// 이 장소의 이벤트별 **현재 신청자 수**(`{eventId: 건수}`).
  ///
  /// 관리 화면이 이벤트마다 스트림을 하나씩 열면 이벤트 수만큼 리스너가
  /// 붙는다. 장소 단위로 한 번만 듣고 앱에서 나눈다.
  ///
  /// 쿼리에 `hostId == 내 uid`가 **반드시** 들어간다 — 규칙이 호스트 조회를
  /// 그 조건으로만 허용하므로, 빼면 목록 전체가 permission-denied가 된다.
  /// 상태는 서버에서 거르지 않고 여기서 센다(등호 필터를 하나라도 줄여
  /// 색인 없이 도는 쿼리로 남기려는 것 — 취소된 신청도 소수다).
  static Stream<Map<String, int>> watchAppliedCountsForPlace({
    required String placeId,
    required String hostId,
  }) {
    if (placeId.isEmpty || hostId.isEmpty) {
      return Stream<Map<String, int>>.value(const {});
    }
    return _col
        .where('hostId', isEqualTo: hostId)
        .where('placeId', isEqualTo: placeId)
        .snapshots()
        .map((snap) {
          final counts = <String, int>{};
          for (final d in snap.docs) {
            final app = PlaceEventApplication.fromMap(d.id, d.data());
            if (!app.isApplied || app.eventId.isEmpty) continue;
            counts[app.eventId] = (counts[app.eventId] ?? 0) + 1;
          }
          return counts;
        });
  }

  /// 이벤트 하나의 신청자 목록 — **호스트 전용 콜러블**.
  ///
  /// 서버가 이벤트 문서의 hostId를 직접 확인하므로, 남의 이벤트 id를 넣어
  /// 부르면 permission-denied로 돌아온다.
  static Future<List<PlaceEventApplicant>> fetchApplicants(
    String eventId,
  ) async {
    final result = await _callable(
      'getPlaceEventApplicants',
    ).call<Map<Object?, Object?>>({'eventId': eventId});
    final list = (result.data['applicants'] as List<Object?>?) ?? const [];
    return list
        .map((e) => PlaceEventApplicant.fromCallable(e as Map<Object?, Object?>))
        .toList();
  }
}
