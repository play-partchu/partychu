// 파티 참여 후기 — 읽기는 Firestore에서 직접, 쓰기는 **전부 서버 콜러블**로.
//
// firestore.rules의 partyReviews는 클라이언트 쓰기를 한 줄도 열어 주지 않는다.
// 작성 자격(참여 완료)과 기한(그 게스트가 참여한 회차 종료 + 14일) 판정이 전부
// functions/partyReviews.js 안에 있기 때문이다 — 앱이 무엇을 보내든 자격을
// 만들어낼 수 없다.
//
// 읽기가 공개인 이유는 파티 상세 하단에 그대로 붙기 때문이다. 후기 문서에는
// 닉네임 스냅샷만 있고 실명·uid는 화면에 그리지 않는다(PartyReview 주석 참고).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:party_app/models/party_review.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';

class PartyReviewService {
  PartyReviewService._();

  static const String collection = 'partyReviews';
  static const String _region = 'asia-northeast3';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: _region);

  /// 후기 문서 id — 서버 `reviewDocId`와 **같은 규칙**이다. 한 신청 건당
  /// 하나라는 사실이 문서 id로 보장되므로, 내 후기가 있는지 확인할 때 목록을
  /// 뒤지지 않고 이 id 하나만 읽으면 된다.
  static String docIdFor({
    required String partyId,
    required String applicationId,
  }) => '${partyId}_$applicationId';

  /// 파티 상세 하단 목록 — 최신순.
  ///
  /// 단일 필드(partyId) 등호 하나라 Firestore 자동 색인으로 돌아간다. 정렬은
  /// 메모리에서 한다: `partyId + createdAt` 복합 색인을 새로 배포하지 않으려는
  /// 것으로, 호스트 판매 통계가 기간 필터를 메모리에서 하는 것과 같은 판단이다.
  /// 한 파티의 후기가 수백 건이 되는 일은 구조상 없다(참여자 수가 상한이다).
  static Stream<List<PartyReview>> watchForParty(String partyId) {
    if (partyId.isEmpty) return Stream.value(const []);
    return _db
        .collection(collection)
        .where('partyId', isEqualTo: partyId)
        .snapshots()
        .map((s) {
          final list = s.docs.map(PartyReview.fromDoc).toList()
            ..sort((a, b) {
              final at = a.createdAt;
              final bt = b.createdAt;
              if (at == null && bt == null) return 0;
              if (at == null) return 1;
              if (bt == null) return -1;
              return bt.compareTo(at);
            });
          return list;
        })
        .handleError(
          (Object e, StackTrace st) =>
              logFirestoreStreamError('PartyReviewService.watchForParty', e, st),
        );
  }

  /// 이 참여 건에 내가 쓴 후기 — 없으면 null.
  static Future<PartyReview?> myReviewFor({
    required String partyId,
    required String applicationId,
  }) async {
    if (UserSession.userId.isEmpty || partyId.isEmpty) return null;
    try {
      final snap = await _db
          .collection(collection)
          .doc(docIdFor(partyId: partyId, applicationId: applicationId))
          .get();
      return snap.exists ? PartyReview.fromDoc(snap) : null;
    } catch (e, st) {
      logFirestoreStreamError('PartyReviewService.myReviewFor', e, st);
      return null;
    }
  }

  /// 같은 참여 건을 실시간으로 — 작성/수정 직후 카드가 바로 바뀌게 한다.
  static Stream<PartyReview?> watchMine({
    required String partyId,
    required String applicationId,
  }) {
    if (UserSession.userId.isEmpty || partyId.isEmpty) {
      return Stream.value(null);
    }
    return _db
        .collection(collection)
        .doc(docIdFor(partyId: partyId, applicationId: applicationId))
        .snapshots()
        .map((s) => s.exists ? PartyReview.fromDoc(s) : null)
        .handleError(
          (Object e, StackTrace st) =>
              logFirestoreStreamError('PartyReviewService.watchMine', e, st),
        );
  }

  /// 작성 또는 수정. 같은 참여 건에 다시 부르면 서버가 덮어쓴다.
  ///
  /// **신청 문서 id를 보내지 않는다** — 서버가 `uid + occurrenceId`로 직접
  /// 만든다. 앱이 보낸 id를 그대로 썼다면 남의 신청서를 가리킬 수 있다.
  ///
  /// 자격·기한 위반은 [FirebaseFunctionsException]으로 사유가 돌아온다.
  static Future<void> submit({
    required String partyId,
    String? occurrenceId,
    required String text,
  }) async {
    await _fn.httpsCallable('submitPartyReview').call<Object?>({
      'partyId': partyId,
      if (occurrenceId != null && occurrenceId.isNotEmpty)
        'occurrenceId': occurrenceId,
      'text': text,
    });
  }

  /// 본인 후기 삭제 — 작성 기간 안에서만 된다(서버가 판정).
  static Future<void> remove(String reviewId) async {
    await _fn.httpsCallable('deletePartyReview').call<Object?>({
      'reviewId': reviewId,
    });
  }
}
