import 'package:flutter/material.dart';

import 'package:party_app/models/mobile_place_schedule.dart';
import 'package:party_app/models/place_weekly_hours.dart';
import 'package:party_app/models/public_event.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/widgets/place_card_widget.dart';
import 'package:party_app/widgets/public_event_card.dart';

/// 통합 지도에 함께 올라가는 콘텐츠 종류.
///
/// 라벨·이모지는 **메인 화면 상단 탭과 같은 것**을 쓴다(파티츄 / 📍 플레이스 /
/// 🏠 장소대여) — 지도에서 새 기호를 만들어내면 같은 콘텐츠가 화면마다 다른
/// 얼굴을 갖게 된다. 색도 앱에 이미 있는 값이다: 파티는 기존 지도 마커 핑크,
/// 플레이스는 앱 전역에서 '장소/주소'에 쓰는 보라, 장소대여는 정원·잔여 표시에
/// 쓰는 초록이다.
enum MapListingKind {
  party(label: '파티', emoji: '🎉', color: Color(0xFFFF4FA3), icon: Icons.pets),
  place(
    label: '플레이스',
    emoji: '📍',
    color: Color(0xFF9B5CFF),
    icon: Icons.storefront_rounded,
  ),
  rental(
    label: '장소대여',
    emoji: '🏠',
    color: Color(0xFF1F9E77),
    icon: Icons.home_rounded,
  ),

  /// 🎊 공공 축제 — 한국관광공사 TourAPI(publicEvents). 파티츄 호스트 문서가
  /// 아니라 [MapListing.publicEvent]를 들고 선다. 색은 이벤트 피드의 공공
  /// 축제 배지와 같은 청록이다(파티츄 콘텐츠 셋과 한눈에 갈린다).
  ///
  /// **지도 홈 전용**이다 — 하단 목록 시트가 있는 지도 화면의 종류 칩
  /// ([listingKinds])에는 들어가지 않는다.
  festival(
    label: '공공 축제',
    emoji: '🎊',
    color: Color(0xFF16867A),
    icon: Icons.celebration_rounded,
  );

  const MapListingKind({
    required this.label,
    required this.emoji,
    required this.color,
    required this.icon,
  });

  /// 칩·목록 머리말에 쓰는 이름.
  final String label;

  /// 탭 라벨과 같은 이모지 — 칩에 붙인다.
  final String emoji;

  /// 마커 테두리·핀 줄기·점 마커 색. 세 종류가 한눈에 갈린다.
  final Color color;

  /// 썸네일이 없을 때 대신 그리는 글리프이자, 마커에 붙는 종류 배지.
  final IconData icon;

  /// 플레이스/장소대여 카드가 스키마를 가르는 데 쓰는 값. 파티·공공 축제는
  /// 해당 없음.
  PlaceCardSource? get cardSource => switch (this) {
    MapListingKind.party => null,
    MapListingKind.place => PlaceCardSource.place,
    MapListingKind.rental => PlaceCardSource.rental,
    MapListingKind.festival => null,
  };

  /// 파티츄 콘텐츠 세 종류 — 지도 화면 종류 칩([MapKindFilterBar])이 고르는
  /// 범위이자 그 '전체'다. 공공 축제는 지도 홈 카테고리로만 켠다.
  static const List<MapListingKind> listingKinds = [party, place, rental];
}

/// 지도가 다루는 항목 하나 — 어느 컬렉션에서 왔든 같은 모양으로 본다.
///
/// 원본 문서([data])를 그대로 들고 다닌다. 카드/상세화면이 기존과 똑같은
/// 필드를 읽어야 하기 때문이다(지도 전용 스키마를 만들지 않는다).
@immutable
class MapListing {
  final MapListingKind kind;
  final String docId;
  final Map<String, dynamic> data;
  final double lat;
  final double lng;

  /// 🎊 공공 축제일 때만 — 목록이 받은 객체 그대로(상세로 넘길 때 다시 읽지
  /// 않는다). 나머지 종류는 null.
  final PublicEvent? publicEvent;

  /// 🚚 이동형 플레이스일 때만 — 이 핀이 **어느 영업 자리인지**([atStop]).
  ///
  /// 고정형은 언제나 null이고, 그때 이 클래스의 동작은 예전과 한 글자도
  /// 다르지 않다. 한 업체가 하루에 여러 곳에서 영업하면 문서 하나에서
  /// 자리마다 사본이 하나씩 나오는데, 그 사본을 가리는 것이 이 값이다.
  final PlaceOpening? opening;

  const MapListing({
    required this.kind,
    required this.docId,
    required this.data,
    required this.lat,
    required this.lng,
    this.publicEvent,
    this.opening,
  });

  /// 컬렉션이 달라도 겹치지 않는 키 — 마커 id와 중복 제거에 쓴다.
  ///
  /// 이동형은 **날짜까지** 키에 넣는다. 사용자가 날짜를 여럿 고르면 한 업체가
  /// 날짜마다 핀을 하나씩 갖는데, 날짜가 키에 없으면 마커 id가 겹쳐 **하나만
  /// 남는다**. 고정형([opening]이 null)은 예전 형식 그대로다.
  String get key {
    final date = openingDate;
    final base = '${kind.name}:$docId';
    return date == null
        ? base
        : '$base@${ScheduleException.dateKeyOf(date)}';
  }

  /// 🚚 이 핀이 선 **영업 날짜**(자정을 넘기는 영업은 시작한 날). 고정형은 null.
  DateTime? get openingDate {
    final start = opening?.start;
    return start == null
        ? null
        : DateTime(start.year, start.month, start.day);
  }

  /// 카드가 읽을 데이터 — 고정형은 [data] 그대로, 이동형은 **그 날 자리**로
  /// 바꾼 사본.
  ///
  /// ⚠️ **원본 [data]를 변형하지 않는다.** 얕은 사본을 새로 만들어 돌려주므로
  ///    상세 화면·다른 카드가 보는 문서는 그대로다(Firestore 스냅샷의 맵을
  ///    고치면 그 문서를 보는 모든 화면이 함께 바뀐다).
  ///
  /// 왜 필요한가: 지도 하단 '이 근처' 카드는 공용
  /// [PlaceCompactCard]를 쓰고 그 위젯은 `address`·`openTime`을 문서에서
  /// 직접 읽는다. 이동형에 원본을 그대로 주면 **핀은 홍대에 서 있는데 카드는
  /// '서울 중구'와 등록 운영시간**을 보여 준다.
  /// [now]는 '오늘' 표기를 가리는 기준이다. 비우면 실제 시각을 쓴다 —
  /// 테스트가 날짜에 따라 깨지지 않도록 넣을 수 있게 열어 둔다.
  Map<String, dynamic> cardData({DateTime? now}) {
    final stop = opening?.stop;
    if (stop == null) return data;
    final fullAddress = stop.roadAddress.isNotEmpty
        ? stop.roadAddress
        : stop.address;
    final where = stop.placeName.isNotEmpty ? stop.placeName : fullAddress;
    return {
      ...data,
      // **날짜 + 장소명.** 날짜를 여럿 고르면 같은 업체의 카드가 여러 장
      // 뜨므로, 어느 날 것인지가 카드에서 바로 읽혀야 한다.
      'address': '${_dateLabel(now)} · $where',
      'location': fullAddress,
      // 영업시간도 그 날 것으로 — 등록 운영시간을 보여 주면 핀·상세와 어긋난다.
      'openTime': _hhmm(opening!.start),
      'closeTime': _hhmm(opening!.end),
      'isOpen24Hours': false,
    };
  }

  /// 카드에 붙는 날짜 — 오늘이면 '오늘', 아니면 `10/13 (화)`.
  ///
  /// 짧게 두는 이유는 카드의 주소 한 줄에 장소명과 함께 들어가기 때문이다
  /// (좁은 화면에서 줄이 끊기지 않게).
  String _dateLabel(DateTime? now) {
    final date = openingDate!;
    final base = now ?? DateTime.now();
    if (date == DateTime(base.year, base.month, base.day)) return '오늘';
    return '${date.month}/${date.day} '
        '(${PlaceWeeklyHours.weekdays[date.weekday - 1]})';
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  /// 같은 문서를 **다른 자리**에 올린 사본 — 이동형 전용.
  ///
  /// [docId]와 [data]는 그대로 둔다. 마커를 눌러 들어가는 상세 화면이 그
  /// 두 값만 쓰므로([MapScreen._openDetail]), 위치가 바뀌어도 업체 ID·사진·
  /// 리뷰·채팅이 전부 같은 곳으로 이어진다.
  MapListing atStop(PlaceOpening stop) => MapListing(
    kind: kind,
    docId: docId,
    data: data,
    lat: stop.stop.latitude,
    lng: stop.stop.longitude,
    publicEvent: publicEvent,
    opening: stop,
  );

  /// 좌표가 없는(0,0) 문서는 지도에 올릴 수 없다.
  static MapListing? from(
    MapListingKind kind,
    String docId,
    Map<String, dynamic> data,
  ) {
    final lat = (data['latitude'] as num?)?.toDouble() ?? 0;
    final lng = (data['longitude'] as num?)?.toDouble() ?? 0;
    if (lat == 0 || lng == 0) return null;
    return MapListing(kind: kind, docId: docId, data: data, lat: lat, lng: lng);
  }

  /// 🎊 공공 축제 → 지도 항목. **좌표가 있는 것만** 올린다(없으면 null).
  ///
  /// [data]에는 검색어 매칭([listingTextMatches])과 지역 필터가 읽는 필드만
  /// 원본 이름 그대로 담는다 — 호스트 문서 모양으로 옮겨 적지 않는다.
  static MapListing? fromPublicEvent(PublicEvent e) {
    final lat = e.lat;
    final lng = e.lng;
    if (lat == null || lng == null || lat == 0 || lng == 0) return null;
    return MapListing(
      kind: MapListingKind.festival,
      docId: e.id,
      data: {
        'title': e.title,
        'address': ?e.address,
        'location': ?e.addressDetail,
      },
      lat: lat,
      lng: lng,
      publicEvent: e,
    );
  }

  /// 마커 탭 카드에 쓰는 제목 — 파티·공공 축제는 `title`, 장소 계열은 `name`.
  String get title =>
      (kind == MapListingKind.party || kind == MapListingKind.festival
          ? data['title'] as String?
          : data['name'] as String?) ??
      '';

  /// 마커 탭 카드의 지역 한 줄. 파티는 목록 카드와 같은 "구+동" 표기를 쓰고,
  /// 장소 계열은 카드가 쓰는 것과 같은 주소 필드에서 뽑는다.
  String get shortAddress {
    if (kind == MapListingKind.party)
      return RegionData.formatCardLocation(data);
    // 공공 축제는 전국이라 시/도까지 — 이벤트 피드 카드와 같은 표기.
    if (kind == MapListingKind.festival) {
      return publicEventAreaLabel(publicEvent?.address);
    }
    // 🚚 이동형은 **그 핀의 영업 자리**를 쓴다. 문서의 주소는 업체가 등록할
    // 때 적은 기준 주소라, 오늘 한강공원에 있는 트럭의 핀 카드에 '서울 중구'가
    // 뜨는 일이 생긴다(핀과 글이 어긋나면 글이 틀린 것이 된다).
    final stop = opening?.stop;
    if (stop != null) {
      final stopAddress = stop.roadAddress.isNotEmpty
          ? stop.roadAddress
          : stop.address;
      if (stop.placeName.isNotEmpty) return stop.placeName;
      if (stopAddress.isNotEmpty) {
        return RegionData.shortDistrictDong(stopAddress);
      }
    }
    final address =
        (data['address'] as String?) ?? (data['location'] as String?) ?? '';
    return address.isEmpty ? '' : RegionData.shortDistrictDong(address);
  }

  /// 지역 필터에 대조할 주소 문자열(장소 계열 전용).
  String get addressText =>
      (data['address'] as String?) ??
      (data['roadAddress'] as String?) ??
      (data['location'] as String?) ??
      '';
}

/// 지도 화면 영역(남·서·북·동)을 사방으로 [ratio]만큼 넓힌 상자.
///
/// 공공 축제 마커를 **화면 근처 것만** 만들 때 쓴다. 보이는 영역 딱 그만큼만
/// 만들면 조금만 움직여도 마커를 다시 그려야 하므로, 넉넉히 넓힌 상자로
/// 만들고 화면이 그 상자를 벗어날 때만 다시 그린다([boxContains]).
({double south, double west, double north, double east}) expandBox(
  ({double south, double west, double north, double east}) box,
  double ratio,
) {
  final dLat = (box.north - box.south) * ratio;
  final dLng = (box.east - box.west) * ratio;
  return (
    south: box.south - dLat,
    west: box.west - dLng,
    north: box.north + dLat,
    east: box.east + dLng,
  );
}

/// [outer]가 [inner]를 통째로 품는가.
bool boxContains(
  ({double south, double west, double north, double east}) outer,
  ({double south, double west, double north, double east}) inner,
) =>
    inner.south >= outer.south &&
    inner.north <= outer.north &&
    inner.west >= outer.west &&
    inner.east <= outer.east;

/// 장소 계열(플레이스/장소대여)이 특정 **날짜**에 문을 여는지.
///
/// 지도의 날짜 조건을 파티에만 걸면 "오늘 + 파티 + 플레이스"를 골랐을 때
/// 플레이스가 조건과 무관하게 전부 남아, 날짜가 AND로 걸리지 않은 것처럼
/// 보인다. 장소 계열에서 날짜에 해당하는 뜻은 "그날 이용할 수 있는가"이므로
/// 요일별 정기 휴무([PlaceWeeklyHours])로 판정한다.
///
/// 시간표가 아예 없는 문서는 **거르지 않는다** — 정보가 없는 것을 "닫혀
/// 있다"로 읽으면 옛 문서가 통째로 지도에서 사라진다.
bool isPlaceOpenOnDate(Map<String, dynamic> data, DateTime date) {
  final raw =
      (data['placeWeeklyHours'] as Map?) ??
      (data['weeklyOperatingHours'] as Map?);
  if (raw == null || raw.isEmpty) return true;
  final weekly = PlaceWeeklyHours.fromMap(Map<String, dynamic>.from(raw));
  final day = weekly.get(PlaceWeeklyHours.weekdayKeyOf(date));
  return day == null || !day.isClosed;
}
