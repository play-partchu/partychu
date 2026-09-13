import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';

/// 오픈 알림 받기 — 오픈예정 파티가 실제 모집을 시작하면 한 번 알려준다.
///
/// 저장 구조는 찜([FavoritesService])과 같다: `partyOpenAlerts` 컬렉션에
/// 문서 id를 "{userId}_{partyId}"로 고정한 문서 하나. 덕분에
///  · 같은 사람이 같은 파티에 두 번 신청하는 일이 구조적으로 생기지 않고,
///  · 취소가 문서 삭제 한 번으로 끝나며,
///  · 신청 여부를 문서 존재만으로 즉시 알 수 있다.
///
/// 실제 발송은 `openPartyRecruiting`(Cloud Functions)이 이 컬렉션을 partyId로
/// 조회해 기존 `notifications` 문서를 만드는 방식이다 — 새 알림 시스템을
/// 만들지 않았고, partyId를 실어 보내므로 기존 딥링크가 그대로 동작한다.
class PartyOpenAlertService {
  PartyOpenAlertService._();

  static const _region = 'asia-northeast3';

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('partyOpenAlerts');

  static String _docId(String partyId) => '${UserSession.userId}_$partyId';

  /// 버튼이 실시간으로 눌림 상태를 반영하도록 문서 하나만 구독한다.
  static Stream<bool> watchSubscribed(String partyId) {
    if (UserSession.userId.isEmpty || partyId.isEmpty) {
      return Stream.value(false);
    }
    return _col
        .doc(_docId(partyId))
        .snapshots()
        .map((s) => s.exists)
        .handleError(
          (e, st) => logFirestoreStreamError(
            'PartyOpenAlertService.watchSubscribed',
            e,
            st,
          ),
        );
  }

  static Future<bool> isSubscribed(String partyId) async {
    if (UserSession.userId.isEmpty || partyId.isEmpty) return false;
    try {
      final snap = await _col.doc(_docId(partyId)).get();
      return snap.exists;
    } catch (e, st) {
      logFirestoreStreamError('PartyOpenAlertService.isSubscribed', e, st);
      rethrow;
    }
  }

  /// 알림 신청/취소 토글. 반환값은 토글 후 상태(true=신청됨).
  ///
  /// ⚠️ 찜과 똑같이 트랜잭션을 쓰지 않는다 — 이 프로젝트의 Firestore에서는
  /// 일반 로그인 사용자로 readWrite 트랜잭션을 시작하면 항상
  /// PERMISSION_DENIED가 난다(favorites_service.dart의 긴 주석 참고).
  static Future<bool> toggle(String partyId) async {
    if (UserSession.userId.isEmpty) {
      throw StateError('로그인이 필요합니다');
    }
    if (partyId.isEmpty) {
      throw ArgumentError('partyId가 비어 있습니다');
    }
    final ref = _col.doc(_docId(partyId));
    try {
      final snap = await ref.get();
      if (snap.exists) {
        await ref.delete();
        return false;
      }
      await ref.set({
        'userId': UserSession.userId,
        'partyId': partyId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e, st) {
      logFirestoreStreamError('PartyOpenAlertService.toggle', e, st);
      rethrow;
    }
  }

  /// 호스트가 "모집 오픈"을 눌렀을 때. 정책값·사업자 인증·필수정보 검사는
  /// 전부 서버에서 다시 하므로, 여기서 막지 못한 요청도 서버가 거절한다.
  ///
  /// 반환값은 알림이 나간 인원수. 실패 시
  /// [FirebaseFunctionsException]을 그대로 던진다(서버가 한국어 안내 문구로
  /// 던지므로 화면은 message를 그대로 보여주면 된다).
  static Future<int> openRecruiting(String partyId) async {
    final callable = FirebaseFunctions.instanceFor(
      region: _region,
    ).httpsCallable('openPartyRecruiting');
    final res = await callable.call<Map<String, dynamic>>({'partyId': partyId});
    final notified = res.data['notified'];
    return notified is int ? notified : 0;
  }
}
