import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';

/// 관심(찜) 목록 — 파티/장소/파티샵/파트너(크루) 4종을 한 Firestore 컬렉션
/// (`favorites`)에 문서 하나씩으로 저장한다. 문서 id를 "{userId}_{type}_{itemId}"로
/// 고정해 같은 항목을 중복 찜하지 않고, 존재 여부만으로 찜 상태를 바로 알 수 있다.
class FavoriteType {
  static const party = 'party';
  static const place = 'place';
  static const shop = 'shop';
  static const crew = 'crew';
  static const event = 'event';
}

class FavoritesService {
  FavoritesService._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('favorites');

  static String _docId(String type, String itemId) =>
      '${UserSession.userId}_${type}_$itemId';

  static Future<bool> isFavorited(String type, String itemId) async {
    if (UserSession.userId.isEmpty || type.isEmpty || itemId.isEmpty) return false;
    try {
      final snap = await _col.doc(_docId(type, itemId)).get();
      return snap.exists;
    } catch (e, st) {
      logFirestoreStreamError('FavoritesService.isFavorited($type)', e, st);
      rethrow;
    }
  }

  /// 찜 버튼이 실시간으로 눌림 상태를 반영하도록 문서 하나만 구독한다.
  static Stream<bool> watchFavorited(String type, String itemId) {
    if (UserSession.userId.isEmpty || type.isEmpty || itemId.isEmpty) {
      return Stream.value(false);
    }
    return _col.doc(_docId(type, itemId)).snapshots().map((s) => s.exists).handleError(
      (e, st) => logFirestoreStreamError('FavoritesService.watchFavorited($type)', e, st),
    );
  }

  /// 찜 추가/해제 토글. 반환값은 토글 후 상태(true=찜됨).
  ///
  /// ⚠️ 예전엔 존재 확인(get)과 생성/삭제를 runTransaction()으로 묶었는데,
  /// 이 프로젝트의 Firestore에서 일반 로그인 사용자(Firebase Auth ID 토큰)로
  /// readWrite 트랜잭션을 시작하면(BeginTransaction) 항상 PERMISSION_DENIED로
  /// 거부된다는 게 실측으로 확인됐다 — 같은 계정의 일반 get()/set()/delete()는
  /// 전부 정상 동작하는데 오직 트랜잭션 핸드셰이크만 막혀서, 찜 버튼이 파티/
  /// 이벤트/장소/샵/크루 등 콘텐츠 종류와 무관하게 전부 "아무 반응 없이" 실패하는
  /// 원인이었다(예외가 catch에서 조용히 삼켜지고 스낵바만 뜨는 정도라 눈에 잘
  /// 안 띔). 트랜잭션 없이 get 후 조건부 set/delete로 바꿔 이 문제를 완전히
  /// 피한다 — 같은 버튼을 빠르게 연타하는 경합은 FavoriteStarButton의
  /// _isProcessing 플래그가 이미 막고 있어 트랜잭션 없이도 안전하다.
  static Future<bool> toggleFavorite(String type, String itemId) async {
    if (UserSession.userId.isEmpty) {
      throw StateError('로그인이 필요합니다');
    }
    if (type.isEmpty || itemId.isEmpty) {
      throw ArgumentError('type/itemId가 비어 있습니다');
    }
    final ref = _col.doc(_docId(type, itemId));
    try {
      final snap = await ref.get();
      if (snap.exists) {
        await ref.delete();
        return false;
      }
      await ref.set({
        'userId': UserSession.userId,
        'type': type,
        'itemId': itemId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e, st) {
      logFirestoreStreamError('FavoritesService.toggleFavorite($type)', e, st);
      rethrow;
    }
  }

  /// 마이페이지 "관심 목록" 화면에서 타입별 탭이 구독할 스트림.
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchFavoritesByType(
      String type) {
    if (UserSession.userId.isEmpty) return const Stream.empty();
    return _col
        .where('userId', isEqualTo: UserSession.userId)
        .where('type', isEqualTo: type)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
}
