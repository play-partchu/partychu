import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/utils/user_session.dart';

/// 사업적으로 의미 있는 행동/조회 이벤트만 기록하는 얇은 로깅 헬퍼.
///
/// 여기서 직접 기록하는 건 Firestore 쓰기로 자연히 파생되지 않는 "화면을
/// 봤다" 류의 순수 조회 이벤트뿐이다(app_open/party_view/place_view). 신청·
/// 취소·참여·찜·파티등록 같은 행동은 이미 해당 컬렉션(applications/favorites/
/// parties)의 생성·상태변화 자체가 신호라 Cloud Functions 트리거가 통계에
/// 반영한다 — 여기서 중복으로 로그를 남기지 않는다.
///
/// eventType 상수는 관리자 웹 통계 설계에 맞춰 12종을 전부 정의해두지만,
/// 실제로 로그를 남기는 곳은 이 서비스를 호출하는 화면들뿐이다. party_search/
/// party_share는 아직 어느 화면에서도 호출하지 않는다(검색 "실행" 시점이
/// 모호하고, 공유 기능 자체가 아직 없음) — 필요해지면 호출부만 추가하면 된다.
class AnalyticsEventType {
  AnalyticsEventType._();
  static const appOpen = 'app_open';
  static const partyView = 'party_view';
  static const partySearch = 'party_search';
  static const partyFavoriteAdd = 'party_favorite_add';
  static const partyFavoriteRemove = 'party_favorite_remove';
  static const partyApply = 'party_apply';
  static const partyCancel = 'party_cancel';
  static const partyAttended = 'party_attended';
  static const partyCreate = 'party_create';
  static const partyShare = 'party_share';
  static const placeView = 'place_view';
  static const placeReservation = 'place_reservation';
}

class AnalyticsService {
  AnalyticsService._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('analyticsEvents');

  /// 실패해도 화면 동작을 막으면 안 되므로 항상 fire-and-forget으로 호출한다.
  static Future<void> logEvent(
    String eventType, {
    String? partyId,
    String? placeId,
    String? region1,
    String? region2,
    String? source,
    String? viewMode,
  }) async {
    if (UserSession.userId.isEmpty) return;
    try {
      await _col.add({
        'userId': UserSession.userId,
        'eventType': eventType,
        'occurredAt': FieldValue.serverTimestamp(),
        if (partyId != null) 'partyId': partyId,
        if (placeId != null) 'placeId': placeId,
        if (region1 != null) 'region1': region1,
        if (region2 != null) 'region2': region2,
        if (source != null) 'source': source,
        if (viewMode != null) 'viewMode': viewMode,
      });
    } catch (_) {
      // 통계 로깅 실패는 무시 — 사용자 경험에 영향 주지 않는다.
    }
  }
}
