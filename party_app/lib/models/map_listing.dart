import 'package:flutter/material.dart';

import 'package:party_app/models/place_weekly_hours.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/widgets/place_card_widget.dart';

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

  /// 플레이스/장소대여 카드가 스키마를 가르는 데 쓰는 값. 파티는 해당 없음.
  PlaceCardSource? get cardSource => switch (this) {
    MapListingKind.party => null,
    MapListingKind.place => PlaceCardSource.place,
    MapListingKind.rental => PlaceCardSource.rental,
  };
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

  const MapListing({
    required this.kind,
    required this.docId,
    required this.data,
    required this.lat,
    required this.lng,
  });

  /// 컬렉션이 달라도 겹치지 않는 키 — 마커 id와 중복 제거에 쓴다.
  String get key => '${kind.name}:$docId';

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

  /// 마커 탭 카드에 쓰는 제목 — 파티는 `title`, 장소 계열은 `name`.
  String get title =>
      (kind == MapListingKind.party
          ? data['title'] as String?
          : data['name'] as String?) ??
      '';

  /// 마커 탭 카드의 지역 한 줄. 파티는 목록 카드와 같은 "구+동" 표기를 쓰고,
  /// 장소 계열은 카드가 쓰는 것과 같은 주소 필드에서 뽑는다.
  String get shortAddress {
    if (kind == MapListingKind.party)
      return RegionData.formatCardLocation(data);
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
