import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:party_app/models/place_availability.dart';
import 'package:party_app/models/reservation_modes.dart';

/// 장소대여 이용 가능 여부 판정에 필요한 데이터를 Firestore에서 읽어와
/// [PlaceAvailability]에 넘겨 주는 서비스.
///
/// **판정 규칙은 여기 없다** — 규칙은 전부 [PlaceAvailability]에 있고, 이
/// 서비스는 "어떤 문서를 어떻게 읽어오는가"만 책임진다. 목록 상세검색과
/// 예약 화면이 같은 판정을 쓰게 하려는 분리다.
///
/// ## 왜 Firestore 쿼리로 한 번에 못 거르는가
/// "요청한 시간이 통째로 비어 있는 장소"는 예약 슬롯의 **부재**를 묻는 조건이라
/// Firestore 쿼리로 표현할 수 없다(없는 문서는 색인에 없다). 그래서 다른
/// 조건(지역·유형·가격·인원)으로 후보를 먼저 좁힌 뒤, 후보에 대해서만
/// 룸·예약 슬롯을 읽어 클라이언트에서 판정한다. 예약 슬롯은 장소 하위
/// 컬렉션(places/{id}/reservationSlots)이고 이미 누구나 읽을 수 있게 열려
/// 있어서(firestore.rules), **새 인덱스도 규칙 변경도 필요 없다.**
/// 컬렉션 그룹 쿼리로 한 방에 읽는 방법도 있지만 그건 규칙에
/// `/{path=**}/reservationSlots` 매치를 새로 열어야 해서 택하지 않았다.
class PlaceAvailabilityService {
  PlaceAvailabilityService._();

  /// 룸 목록은 자주 바뀌지 않아 세션 동안 재사용한다.
  static final Map<String, List<Map<String, dynamic>>> _roomsCache = {};

  /// 예약 슬롯은 실시간으로 바뀌므로 짧게만 캐시한다(같은 검색 안에서 필터를
  /// 이리저리 바꿀 때 같은 날짜를 반복 조회하지 않기 위한 것).
  static const Duration _slotsTtl = Duration(seconds: 60);
  static final Map<String, ({DateTime at, List<PlaceBookedRange> ranges})>
  _slotsCache = {};

  /// 동시에 던지는 조회 수 — 후보가 많아도 한꺼번에 수백 개를 날리지 않는다.
  static const int _concurrency = 12;

  /// 캐시를 비운다(테스트·강제 새로고침용).
  static void clearCache() {
    _roomsCache.clear();
    _slotsCache.clear();
  }

  /// [places] 중 [request]를 만족하는 장소만 골라 `placeId → 판정 결과`로
  /// 돌려준다. 결과에는 "고른 범위 중 실제로 이용 가능한 구간"이 들어 있어
  /// 카드에 그대로 표시할 수 있다.
  ///
  /// - [PlaceAvailabilityMode.full]: 요청 구간 **전체**가 비어 있어야 통과.
  ///   시작 시각만 걸치는 장소는 포함하지 않는다.
  /// - [PlaceAvailabilityMode.partial]: 요청 구간 안에 실제로 예약할 수 있는
  ///   길이의 빈 구간이 하나라도 있으면 통과.
  static Future<Map<String, PlaceAvailabilityMatch>> availablePlaces({
    required List<({String id, Map<String, dynamic> data})> places,
    required PlaceAvailabilityRequest request,
  }) async {
    if (places.isEmpty) return const {};

    final rooms = await _loadRooms(places.map((p) => p.id).toList());
    final matches = <String, PlaceAvailabilityMatch>{};

    for (var i = 0; i < places.length; i += _concurrency) {
      final chunk = places.skip(i).take(_concurrency).toList();
      final results = await Future.wait(
        chunk.map((place) async {
          final placeRooms = rooms[place.id] ?? const <Map<String, dynamic>>[];
          try {
            final booked = await _loadBooked(
              placeId: place.id,
              request: request,
              rooms: placeRooms,
            );
            return (
              id: place.id,
              match: PlaceAvailability.placeMatch(
                place: place.data,
                rooms: placeRooms,
                booked: booked,
                request: request,
              ),
            );
          } catch (e) {
            // 한 장소의 조회 실패가 검색 전체를 막지 않도록 — 판정할 수 없는
            // 장소는 결과에서 빼되(요청 시간을 쓸 수 있다고 단정할 수 없다),
            // 조용히 넘어가지 말고 로그는 남긴다.
            debugPrint('[PlaceAvailability] ${place.id} 조회 실패: $e');
            return (id: place.id, match: PlaceAvailabilityMatch.none);
          }
        }),
      );
      for (final r in results) {
        if (r.match.available) matches[r.id] = r.match;
      }
    }

    return matches;
  }

  /// [places]가 받는 **예약 방식** — placeId → 방식 집합.
  ///
  /// 판정은 [placeReservationModes]가 하고 여기서는 룸을 읽어다 줄 뿐이다
  /// (이용 가능 판정과 **같은 룸 캐시**를 쓰므로 조회가 늘지 않는다).
  /// 목록 상세검색의 '예약 방식' 조건이 이 결과로 후보를 좁힌다.
  static Future<Map<String, Set<ReservationMode>>> reservationModesOf(
    List<({String id, Map<String, dynamic> data})> places,
  ) async {
    if (places.isEmpty) return const {};
    final rooms = await _loadRooms(places.map((p) => p.id).toList());
    return {
      for (final place in places)
        place.id: placeReservationModes(
          place.data,
          rooms: rooms[place.id] ?? const [],
        ),
    };
  }

  // ── 룸 로드 ─────────────────────────────────────────────────────────────

  /// placeId → 룸 목록. `whereIn`은 한 번에 30개까지라 나눠서 조회한다.
  /// (isActive는 쿼리에 넣지 않고 코드에서 거른다 — 등호 필터를 하나 더
  /// 걸면 색인 요구가 생기고, isActive 필드가 아예 없는 옛 문서가 통째로
  /// 빠지는 문제도 있다. 활성 여부 판정은 [PlaceAvailability]가 한다.)
  static Future<Map<String, List<Map<String, dynamic>>>> _loadRooms(
    List<String> placeIds,
  ) async {
    final missing = placeIds
        .where((id) => !_roomsCache.containsKey(id))
        .toList();
    for (var i = 0; i < missing.length; i += 30) {
      final batch = missing.skip(i).take(30).toList();
      final snap = await FirebaseFirestore.instance
          .collection('placeRooms')
          .where('placeId', whereIn: batch)
          .get();
      for (final id in batch) {
        _roomsCache[id] = <Map<String, dynamic>>[];
      }
      for (final doc in snap.docs) {
        final data = <String, dynamic>{'id': doc.id, ...doc.data()};
        final placeId = data['placeId'] as String?;
        if (placeId == null) continue;
        _roomsCache.putIfAbsent(placeId, () => []).add(data);
      }
    }
    return {for (final id in placeIds) id: _roomsCache[id] ?? const []};
  }

  // ── 예약 슬롯 로드 ───────────────────────────────────────────────────────

  /// 겹침 판정에 필요한 조회 폭 — 전날 밤에 시작해 넘어오는 예약(올나잇
  /// 패키지 등)까지 보려면 하루 앞에서부터 읽어야 하고, 숙박을 받는 룸은
  /// 예약 하나가 여러 날을 덮으므로 훨씬 넓게 본다(예약 화면 _loadBooked·
  /// 서버 STAY_LOOKBACK_DAYS와 같은 규칙).
  static const int _stayLookbackDays = 31;

  static Future<List<PlaceBookedRange>> _loadBooked({
    required String placeId,
    required PlaceAvailabilityRequest request,
    required List<Map<String, dynamic>> rooms,
  }) async {
    final supportsStay = rooms.isEmpty
        ? false
        : rooms.any(
            (r) => roomReservationModes(r).contains(ReservationMode.stay),
          );
    final lookbackDays = supportsStay ? _stayLookbackDays : 1;
    final horizonDays = request.spanDays + 1;

    // 조회 범위는 날짜와 폭으로만 정해진다 — 시간대나 이용 조건(전체/일부)을
    // 바꿔도 같은 슬롯을 다시 읽지 않도록 날짜 기준으로만 캐시한다.
    final cacheKey = '$placeId|${request.dateKey}|$lookbackDays|$horizonDays';
    final cached = _slotsCache[cacheKey];
    final now = DateTime.now();
    if (cached != null && now.difference(cached.at) < _slotsTtl) {
      return cached.ranges;
    }

    final midnight = request.date;
    final snap = await FirebaseFirestore.instance
        .collection('places')
        .doc(placeId)
        .collection('reservationSlots')
        .where(
          'startAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(
            midnight.subtract(Duration(days: lookbackDays)),
          ),
        )
        .where(
          'startAt',
          isLessThan: Timestamp.fromDate(
            midnight.add(Duration(days: horizonDays)),
          ),
        )
        .get();

    final ranges = <PlaceBookedRange>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      // 취소·만료된 슬롯과 결제 대기 시간이 지난 슬롯은 자리를 잡고 있지
      // 않다 — 서버(roomAvailability.js)·예약 화면과 같은 판정.
      final status = d['status'] as String? ?? 'pending';
      if (status == 'cancelled' || status == 'expired') continue;
      if (status == 'pending') {
        final expiresAt = (d['expiresAt'] as Timestamp?)?.toDate();
        if (expiresAt != null && expiresAt.isBefore(now)) continue;
      }
      final startAt = (d['startAt'] as Timestamp?)?.toDate();
      final endAt = (d['endAt'] as Timestamp?)?.toDate();
      if (startAt == null || endAt == null) continue;
      final startMin = startAt.difference(midnight).inMinutes;
      final endMin = endAt.difference(midnight).inMinutes;
      if (endMin <= startMin) continue;
      ranges.add(
        PlaceBookedRange(
          roomId: d['roomId'] as String?,
          startMinutes: startMin,
          endMinutes: endMin,
        ),
      );
    }

    _slotsCache[cacheKey] = (at: now, ranges: ranges);
    return ranges;
  }
}
