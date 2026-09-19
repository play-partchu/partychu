import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:party_app/models/combo_place_type.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/place_facility_options.dart';
import 'package:party_app/models/place_feature.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/models/place_taxonomy.dart';
import 'package:party_app/models/pet_policy.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/models/room_price_type.dart';
import 'package:party_app/screens/event_detail_screen.dart';
import 'package:party_app/screens/place_detail_screen.dart';
import 'package:party_app/utils/favorites_service.dart';
import 'package:party_app/utils/feed_video_manager.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/utils/party_utils.dart';
import 'package:party_app/utils/place_owner.dart' show isMyPlace;
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/card_parts.dart';
import 'package:party_app/widgets/favorite_star_button.dart';
import 'package:party_app/widgets/list_card_shell.dart';
import 'package:party_app/widgets/partychu_perk.dart';
import 'package:party_app/widgets/partychu_perk_plaque.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/widgets/feed_photo_story.dart';
import 'package:party_app/widgets/video_seek_bar.dart';
import 'package:party_app/widgets/web_frame.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 플레이스(장소대여) 목록 카드 — 파티 카드와 "완전히 같은 껍데기"를 쓰고
// 내용만 플레이스 데이터로 바꾼 것이다.
//
//  · PlaceCompactCard  = ListCardShell  (지도 '이 근처 파티' 카드와 동일)
//  · PlaceStandardCard = GridCardShell  (파티 목록 기본 카드와 동일)
//
// 파티 항목 → 플레이스 항목 대응:
//   파티 날짜/시간   → 운영시간
//   모집 인원        → 최대 수용 인원
//   참가비           → 이용요금(시간당 대표 가격)
//   파티 유형        → 플레이스 유형
//   지역/찜/대표 이미지는 그대로.
//
// 사진은 두 셸이 쓰는 기존 표시 방식을 그대로 따른다 — 작은 카드는 정사각
// 썸네일 안에서 BoxFit.cover(지도 카드와 동일), 기본 카드는 등록 화면에서
// 지정한 기본 카드 전용 초점/배율을 반영하는 gridCardPhoto(파티 기본 카드와
// 동일). 그래서 세로/가로/정사각 원본 어느 쪽도 비율이 깨지지 않고, 초점이
// 지정된 사진은 과하게 잘리지도 않는다.
// ─────────────────────────────────────────────────────────────────────────────

/// 카드가 어떤 컬렉션의 문서를 그리는지 — 스키마가 서로 달라서 읽는 필드와
/// 상세화면/찜 종류가 갈린다. 카드 레이아웃은 두 경우가 완전히 동일하다.
enum PlaceCardSource {
  /// "플레이스" 탭 (events 컬렉션) — 테마 태그·영업시간이 있고, 수용 인원·
  /// 이용요금 필드는 애초에 없다.
  place,

  /// "장소대여" 탭 (places 컬렉션) — 장소 유형·운영시간·최대 수용 인원·
  /// 시간당 이용요금이 모두 있다.
  rental,
}

/// 플레이스/장소 문서 하나에서 카드가 보여줄 값만 뽑아낸 뷰 모델.
/// 두 카드가 같은 규칙(필드 폴백 포함)으로 읽도록 한 곳에 모아 둔다.
class PlaceCardInfo {
  final String name;

  /// 플레이스 유형 — 장소대여는 장소 유형(`type`), 플레이스는 대표 테마 태그.
  final String type;

  /// 유형 배지 옆에 함께 붙일 보조 배지(대표 태그를 뺀 나머지 테마 태그).
  final List<String> extraTags;

  final String shortAddress;

  /// 운영시간 — "24시간 운영" / "오전 9:00 ~ 오후 10:00". 없으면 빈 문자열.
  final String hoursLabel;

  /// 최대 수용 인원(명). 0이면 표시하지 않는다.
  final int capacityMax;

  /// 대표 가격. null이면 그 스키마에 가격 개념이 없다는 뜻이라 요금 줄 자체를
  /// 그리지 않는다(0은 "무료"로 표시되는 것과 구분된다).
  final int? pricePerHour;

  /// 위 대표 가격의 단위 — 'hour'(시간당) 또는 'night'(1박). 숙박만 받는
  /// 장소는 시간당 요금이 없어서 1박 최저가를 대표로 쓴다.
  final String priceUnit;

  final String? petBadgeLabel;

  /// "🏨 숙박+파티" 배지를 붙일지 — **장소대여([PlaceCardSource.rental])이면서
  /// 숙박 콤보로 등록된** 문서에만 true다. 플레이스(술집·바·카페) 카드에서는
  /// 항상 false다([PlaceCardInfo.from] 참고).
  final bool isStayPartyCombo;

  /// 파티츄 전용 혜택이 등록돼 있는지 — 목록에는 배지만 띄우므로 내용은 담지 않는다.
  final bool hasPartychuPerk;

  /// 좌석·공간/편의 옵션 대표 요약(전체는 상세페이지).
  final String facilitySummary;

  final PartyCoverMedia? cover;

  /// 대표가가 없고 **가격 문의** 룸만 있는 장소대여인지 — 요금 줄을 '무료'가
  /// 아니라 '가격 문의'로 적는다([RoomPriceType]).
  final bool priceInquiry;

  PlaceCardInfo._({
    required this.name,
    required this.type,
    required this.extraTags,
    required this.shortAddress,
    required this.hoursLabel,
    required this.capacityMax,
    required this.pricePerHour,
    required this.priceUnit,
    required this.petBadgeLabel,
    required this.isStayPartyCombo,
    required this.hasPartychuPerk,
    required this.facilitySummary,
    required this.cover,
    this.priceInquiry = false,
  });

  /// [withParty] — 🎉 With파티 배지를 붙일지. 이 값은 **문서에서 읽지 않는다**.
  /// 연결은 파티 쪽(`parties.linkedEventId`)에 있고 파티의 생사에 따라 매
  /// 순간 달라지므로, 목록·지도가 만든 색인([PlacePartyIndex])이 넘겨준다.
  /// 문서의 `linkedPartyIds` 보조 배열을 읽으면 파티가 지워진 뒤에도 배지가
  /// 남아 "파티 있다더니 없는" 카드가 된다.
  factory PlaceCardInfo.from(
    Map<String, dynamic> data, {
    required PlaceCardSource source,
    required String tag,
    bool withParty = false,
  }) {
    final petPolicy = data['petPolicy'] is Map
        ? PetPolicy.fromMap(Map<String, dynamic>.from(data['petPolicy'] as Map))
        : PetPolicy.empty();
    final facilities = data['facilityOptions'] is Map
        ? PlaceFacilityOptions.fromMap(
            Map<String, dynamic>.from(data['facilityOptions'] as Map),
          )
        : PlaceFacilityOptions.empty();
    // 장소대여는 `address`, 플레이스는 `location`에 주소가 들어간다.
    final address =
        (data['address'] as String?) ?? (data['location'] as String?) ?? '';
    final themeTags = placeThemeTags(data);

    return PlaceCardInfo._(
      // 파티 카드와 동일하게 목록에서는 제목을 12자까지만 노출한다.
      name: truncatePartyTitleForCard(data['name'] as String? ?? '플레이스'),
      // 플레이스의 대표 배지는 **대분류**다 — '무슨 가게인가'가 카드에서
      // 가장 먼저 읽혀야 한다. 대분류를 고르지도 유추하지도 못하는 옛
      // 문서는 예전처럼 대표 특징 태그를 그대로 쓴다(배지가 비지 않는다).
      type: source == PlaceCardSource.rental
          ? (data['type'] as String? ?? '')
          : (PlaceTaxonomy.categoryOf(data) != null
                ? PlaceTaxonomy.displayOf(PlaceTaxonomy.categoryOf(data)!)
                : themeTags.isNotEmpty
                ? _themeTagLabel(themeTags.first)
                : ''),
      extraTags: [
        // 🎉 With파티가 맨 앞 — 이 조건으로 걸러 들어온 사람이 카드 한 장씩
        // 확인하지 않아도 목록 전체가 왜 이렇게 나왔는지 읽힌다.
        if (withParty) '🎉 With파티',
        if (source == PlaceCardSource.place) ...[
          // 소분류가 먼저 — '클럽'보다 '힙합클럽'이 훨씬 많은 것을 말한다.
          ...PlaceTaxonomy.subcategoriesOf(data).take(2),
        ],
        if (source == PlaceCardSource.place)
          // 업종·분위기 태그만 남긴다. "상시 진행" 배지는 뺐다 — 플레이스는
          // 기간이 정해진 모집글이 아니라 상시 운영되는 장소라, 거의 모든
          // 카드에 똑같이 붙어서 알려주는 것이 없고 정작 중요한 업종·분위기
          // 배지의 자리만 밀어냈다. (파티 카드의 모집중·마감임박 같은 상태
          // 배지는 실제로 카드마다 달라지므로 그대로 둔다.)
          ...themeTags.skip(1).map(_themeTagLabel),
      ],
      shortAddress: address.isEmpty
          ? ''
          : RegionData.shortDistrictDong(address),
      hoursLabel: placeHoursLabel(data),
      // 룸 스키마: capacityMax, 구 스키마: capacity / maxCapacity
      // (place_detail_screen의 판정 순서와 동일하게 맞춘다.)
      // 플레이스(events)에는 이 필드가 없어 자연스럽게 0이 되고 표시되지 않는다.
      capacityMax:
          (data['capacityMax'] as num?)?.toInt() ??
          (data['capacity'] as num?)?.toInt() ??
          (data['maxCapacity'] as num?)?.toInt() ??
          0,
      // 장소대여만 시간당 요금이 있다 — 플레이스(events)는 가격 필드 자체가
      // 없으므로 null로 두고 요금 줄을 그리지 않는다(0원="무료"와 구분).
      pricePerHour: source == PlaceCardSource.rental
          ? placeRentalPrice(data)
          : (data['pricePerHour'] as num?)?.toInt(),
      // 구 데이터에는 priceUnit이 없다 — 그때는 전부 시간당 요금이었다.
      // 정렬이 단위를 가르는 판정과 **같은 함수**를 쓴다.
      priceUnit: placeRentalPriceUnit(data),
      petBadgeLabel: petPolicy.status == PetPolicyStatus.possible
          ? '🐶 애견동반 가능'
          : petPolicy.status == PetPolicyStatus.conditional
          ? '🐶 애견동반 조건부'
          : null,
      // "숙박+파티" 배지는 **장소대여(places) 카드에서만** 의미가 있다.
      // `isCombo`는 플레이스+파티 콤보(events)도 true라서, 그것만 보면 혼술바
      // 같은 매장 카드에까지 숙박 배지가 붙는다(예전 버그). 플레이스일 때는
      // 유형 판정 자체를 아예 하지 않고, 장소대여일 때만 숙박 콤보인지 본다.
      isStayPartyCombo:
          source == PlaceCardSource.rental &&
          // `comboPlaceType`이 없는 예전 `places` 콤보 문서는 전부 숙박 콤보다
          // (매장 콤보는 `events`에만 쓴다) — 그래서 폴백이 stay다.
          ComboPlaceType.ofDoc(data, fallback: ComboPlaceType.stay) ==
              ComboPlaceType.stay,
      hasPartychuPerk: partychuPerkFrom(data) != null,
      // 카드 요약 한 줄 — 플레이스는 **특징**을 쓴다.
      //
      // 지도 핀 카드에서 주소보다 먼저 읽혀야 하는 것은 '어디인가'가
      // 아니라 '왜 가볼 만한가'다(🎧 DJ · 🌙 심야영업 · 🚬 흡연실). 특징이
      // 하나도 유도되지 않는 플레이스는 예전처럼 좌석·공간 요약을 쓴다 —
      // 요약 줄이 통째로 비어 카드가 한 줄 줄어드는 일이 없다.
      facilitySummary: source == PlaceCardSource.place
          ? (() {
              // 특징 이름이 아니라 **값**으로 적는다 — '♾ 무제한'만으로는 무엇이
              // 무제한인지 모른다('♾ 하이볼 무제한', '♾ 노래방 시간 무제한').
              final features = PlaceFeatures.highlightLabelsOf(
                data,
                max: 3,
              ).join(' · ');
              return features.isEmpty ? facilities.summaryText() : features;
            })()
          : facilities.summaryText(),
      cover: getPartyCoverMedia(data, tag: tag),
      priceInquiry:
          source == PlaceCardSource.rental &&
          RoomPriceType.of(data) == RoomPriceType.inquiry,
    );
  }

  /// 이용요금 — 파티 참가비와 동일하게 로그인해야만 금액을 노출한다.
  /// 가격 개념이 없는 데이터(플레이스)는 null이라 호출부가 줄을 생략한다.
  String? get priceLabel {
    // 문의로 받는 가격은 금액이 아니라 숨길 것도 없다 — 로그인 전에도 그대로.
    if (priceInquiry) return kInquiryPriceLabel;
    final price = pricePerHour;
    if (price == null) return null;
    if (!UserSession.isLoggedIn) return '🔒 로그인 필요';
    if (price <= 0) return '무료';
    return '${formatPrice(price)} / ${priceUnit == 'night' ? '박' : '시간'}';
  }
}

/// 장소대여(`places`) 카드가 보여주는 **대표 가격** — 등록 화면이 룸별
/// 최저가를 집계해 문서 최상단 `pricePerHour`에 넣어 둔 값 그대로다
/// (단위는 `priceUnit`: 시간당 'hour' / 1박 'night', [PlaceCardInfo.priceLabel]).
///
/// 카드와 **정렬·필터가 같은 함수를 부른다** — 카드에 '₩30,000 / 시간'이라고
/// 적힌 장소가 금액순에서 다른 금액으로 취급되면 안 되기 때문이다
/// ([PlaceSortMode]). 값이 없으면 0이고, 카드는 그것을 '무료'로 적는다.
int placeRentalPrice(Map<String, dynamic> data) =>
    (data['pricePerHour'] as num?)?.toInt() ?? 0;

/// 위 대표 가격의 **단위** — 시간당 `'hour'` / 1박 `'night'`.
///
/// 구 데이터에는 `priceUnit`이 없다 — 그때는 전부 시간당 요금이었으므로
/// 'hour'로 읽는다([PlaceCardInfo]의 판정과 같은 폴백이다).
///
/// 금액순 정렬이 이 값을 본다 — ₩/시간과 ₩/박은 서로 다른 축이라 한 줄로
/// 세워 비교하면 '3만원 파티룸'과 '3만원 펜션'이 같은 값으로 읽힌다.
/// 환산하지 않고 **단위별로 묶어서만** 정렬한다([placeRentalPriceIsNightly]).
String placeRentalPriceUnit(Map<String, dynamic> data) =>
    data['priceUnit'] as String? ?? 'hour';

/// 대표 가격이 1박 요금인지 — 카드가 '박'이라고 적는 것과 **같은 판정**
/// (`priceUnit == 'night'`, 그 밖에는 전부 시간당으로 본다).
bool placeRentalPriceIsNightly(Map<String, dynamic> data) =>
    placeRentalPriceUnit(data) == 'night';

/// 테마 태그 목록 — 신규는 `themeTags`, 구 데이터는 `category` 한 개.
/// (main_screen의 카테고리 필터가 쓰는 판정과 동일한 규칙.)
List<String> placeThemeTags(Map<String, dynamic> data) {
  final tags = (data['themeTags'] as List?)?.cast<String>();
  if (tags != null && tags.isNotEmpty) return tags;
  final legacy = data['category'] as String?;
  return legacy != null && legacy.isNotEmpty ? [legacy] : const [];
}

/// 테마 태그 배지 문구 — 목록에서 쓰던 이모지 접두사를 그대로 붙인다.
/// 문구는 저장값이 아니라 [ListingConstants.placeThemeTagLabel]이 정한 표기다.
String _themeTagLabel(String tag) {
  final emoji = ListingConstants.placeThemeTagEmojis[tag];
  final label = ListingConstants.placeThemeTagLabel(tag);
  return emoji == null || emoji.isEmpty ? label : '$emoji $label';
}

/// 플레이스 운영시간 한 줄 라벨 — 24시간 운영이면 그 문구만, 아니면
/// "여는 시각 ~ 닫는 시각". 구 스키마(openHour/closeHour)도 함께 읽는다.
String placeHoursLabel(Map<String, dynamic> d) {
  if (d['isOpen24Hours'] == true) return '24시간 운영';
  final open =
      d['openTime'] as String? ??
      (d['openHour'] != null ? '${d['openHour']}:00' : '');
  final close =
      d['closeTime'] as String? ??
      (d['closeHour'] != null ? '${d['closeHour']}:00' : '');
  if (open.isEmpty || close.isEmpty) return '';
  return '${_fmtHourMinute(open)} ~ ${_fmtHourMinute(close)}';
}

/// "14:00" → "오후 2:00" (place_detail_screen의 표기와 동일).
String _fmtHourMinute(String t) {
  if (t == '24:00') return '자정';
  final parts = t.split(':');
  if (parts.length != 2) return t;
  final h = int.tryParse(parts[0]) ?? 0;
  final m = parts[1];
  if (h == 0) return '오전 12:$m';
  if (h < 12) return '오전 $h:$m';
  if (h == 12) return '오후 12:$m';
  return '오후 ${h - 12}:$m';
}

/// 유형/애견동반 같은 작은 알약 배지 — 모양의 정본은 [cardMiniBadge]다
/// (파티샵 카드와 같은 배지를 쓴다).
Widget _placeMiniBadge(
  String label, {
  Color background = const Color(0xFFFFF0F5),
  Color foreground = const Color(0xFFFF6FA0),
}) => cardMiniBadge(label, background: background, foreground: foreground);

/// 장소명 — 파티/파티샵 카드 제목과 같은 서체·크기·외곽선([cardTitleText]).
///
/// [maxLines]는 이벤트 카드만 2로 쓴다([PlaceEventCompactCard]) — 거기서는
/// 이 자리가 장소명이 아니라 **이벤트 제목**이라, 한 줄로 자르면 긴 제목이
/// 앞 몇 글자만 남는다. 장소 카드는 예전처럼 한 줄이다(카드 높이가 문서마다
/// 들쭉날쭉해지지 않게).
Widget _placeTitle(String name, {int maxLines = 1}) =>
    cardTitleText(name, maxLines: maxLines);

/// 아이콘 + 텍스트 한 줄 — 파티 카드의 날짜/시간/지역 줄과 같은 크기·색
/// ([cardInfoLine]). 값이 비어도 줄 자체는 남아 2열 그리드에서 좌우 카드의
/// 아래끝이 어긋나지 않는다.
Widget _placeInfoLine(IconData icon, String text, {bool expand = true}) =>
    cardInfoLine(icon, text, expand: expand);

/// 미디어 위 오른쪽 위에 얹는 찜 버튼 — 자리·크기의 정본은
/// [cardFavoriteOverlay]다(파티샵 카드와 같은 자리).
/// 찜 종류는 컬렉션에 맞춰 갈린다(플레이스=event, 장소대여=place) — 기존
/// 찜 목록과 어긋나지 않도록 반드시 원래 쓰던 타입을 그대로 쓴다.
Widget _placeFavoriteOverlay(String id, PlaceCardSource source) =>
    cardFavoriteOverlay(
      itemType: source == PlaceCardSource.rental
          ? FavoriteType.place
          : FavoriteType.event,
      itemId: id,
    );

/// 카드 탭 시 열리는 상세화면 — 컬렉션이 다르므로 화면도 갈린다.
void _openPlaceDetail(
  BuildContext context,
  PlaceCardSource source,
  String id,
  Map<String, dynamic> data,
) {
  Navigator.push(
    context,
    webFramedRoute(
      (_) => source == PlaceCardSource.rental
          ? PlaceDetailScreen(placeId: id, data: data)
          : EventDetailScreen(eventId: id, eventData: data),
    ),
  );
}

/// 카드 배지에 붙는 '이벤트 진행중' 상태칩의 **표기 정본**.
/// 저장값과 화면 문구를 갈라 둔 표 하나를 그대로 거친다([ListingConstants]) —
/// 문구를 여기 다시 적어 두면 표기가 바뀔 때 이 판정만 조용히 어긋난다.
String get _placeEventStatusBadge =>
    _themeTagLabel(ListingConstants.placeEventTag);

/// 유형 + 보조 태그 + 애견동반 + 콤보 + 파티츄 전용 혜택 배지 —
/// [PlaceCompactCard]와 [PlaceStandardCard]가 **이 목록 하나**를 같은 순서로
/// 그린다(한쪽에만 배지가 빠지는 일이 없도록).
///
/// [eventSourceBadge]는 ✨ **이벤트 목록**의 카드에서만 온다
/// ('✨ 매장 이벤트' / '✨ 공간 이벤트' — 문구의 정본은 `EventFeedKind.badge`).
/// 그 목록에서는 '✨ 이벤트 진행중' 상태칩이 아무것도 알려주지 않는다 — 목록에
/// 있는 카드가 전부 진행 중인 이벤트다. 그래서 그 칩을 빼고, 어디서 여는
/// 이벤트인지(매장/공간)를 **배지 줄 맨 앞**에 세운다 — 장소 카테고리보다
/// 먼저다.
///
/// 다른 목록(플레이스·장소대여 탭·지도)은 이 인자를 주지 않으므로 상태칩이
/// 예전 그대로 남는다. 태그 저장값도 필터 판정도 어느 쪽이든 건드리지 않는다 —
/// 바뀌는 것은 **이 배지 줄에 무엇을 그리는가** 하나뿐이다.
List<Widget> placeCardBadges(PlaceCardInfo info, {String? eventSourceBadge}) {
  final drop = eventSourceBadge == null ? null : _placeEventStatusBadge;
  return [
    // ① ✨ 이벤트 유형이 **맨 앞**이다 — 이 목록에 들어온 사람이 카드마다
    //    먼저 가려내는 것은 업종이 아니라 "매장이 여는가, 공간이 여는가"다.
    //    목록 순서가 곧 Wrap의 자식 순서라, 좁은 화면에서 배지가 접혀도
    //    첫 줄 첫 칸은 언제나 이 배지다(우연히 앞서는 것이 아니다).
    if (eventSourceBadge != null) _placeMiniBadge(eventSourceBadge),
    // ② 그다음이 장소 카테고리 — '✨ 매장 이벤트 · 🍷 혼술바'로 읽힌다.
    if (info.type.isNotEmpty && info.type != drop) _placeMiniBadge(info.type),
    for (final tag in info.extraTags)
      if (tag != drop) _placeMiniBadge(tag),
    if (info.petBadgeLabel != null)
      _placeMiniBadge(
        info.petBadgeLabel!,
        background: const Color(0xFFEAFBF2),
        foreground: const Color(0xFF1D8F5F),
      ),
    if (info.isStayPartyCombo) PartyCard.stayPartyComboBadge(),
    // 파티츄 전용 혜택은 배지가 아니라 카드 테두리로 알린다
    // (partychuPerkBorderOverlay — 각 카드의 껍데기에서 붙인다).
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// 작은 화면 — 지도 '이 근처 파티' 카드(PartyCard)와 같은 셸.
// ─────────────────────────────────────────────────────────────────────────────

class PlaceCompactCard extends StatelessWidget {
  final Map<String, dynamic> place;
  final String placeId;
  final PlaceCardSource source;
  final VoidCallback? onTap;

  /// 🎉 With파티 배지를 붙일지 — 목록/지도가 만든 색인이 넘겨준다.
  final bool withParty;

  /// 상세검색에서 이용 날짜/시간을 고른 경우, 그 범위 중 **실제로 이용
  /// 가능한 시간**('19:00~21:00 이용 가능'). 조건을 안 걸었으면 null이고 줄
  /// 자체가 빠진다.
  final String? availabilityLabel;

  /// ✨ 이 카드가 **이벤트 목록**에 서 있을 때 붙는 구분 배지
  /// ('✨ 매장 이벤트' / '✨ 공간 이벤트'). 그 목록 밖에서는 null이고, 배지 줄도
  /// 예전 그대로다([placeCardBadges]).
  final String? eventSourceBadge;

  const PlaceCompactCard({
    super.key,
    required this.place,
    required this.placeId,
    required this.source,
    this.onTap,
    this.withParty = false,
    this.eventSourceBadge,
    this.availabilityLabel,
  });

  @override
  Widget build(BuildContext context) {
    final info = PlaceCardInfo.from(
      place,
      source: source,
      tag: 'PlaceCompactCard',
      withParty: withParty,
    );
    final cover = info.cover;
    final isVideo = cover?.isVideo ?? false;
    final videoUrl = cover?.videoUrl;
    final thumbnailUrl = cover?.thumbnailUrl;
    final priceLabel = info.priceLabel;

    // 파티츄 전용 혜택 — 카드 외곽선 위에 얇은 금빛 라인만 덧그린다
    // (레이아웃에 관여하지 않아 일반 카드와 크기·여백이 같다).
    final card = ListCardShell(
      onTap: () {
        FeedVideoManager.instance.pauseActive();
        (onTap ?? () => _openPlaceDetail(context, source, placeId, place))();
      },
      decorationOverlay: info.hasPartychuPerk
          ? partychuPerkPlaqueOverlayCompact()
          : null,
      child: ListCardShell.horizontalBody(
        // 대표 이미지 — 지도 카드·파티 작은 카드와 같은 셸을 쓴다. 폭은 104로
        // 고정하고 높이는 카드를 그대로 채우므로, 배지가 두 줄로 접혀 카드가
        // 길어져도 사진 아래에 빈 공간이 생기지 않는다.
        thumbnail: Stack(
          children: [
            ListCardShell.thumbnailBox(
              child: (isVideo && videoUrl != null && videoUrl.isNotEmpty)
                  ? VideoThumbnail(
                      videoUrl: videoUrl,
                      thumbnailUrl: thumbnailUrl,
                      autoplayOnVisible: false,
                      cropX: cover?.videoCropX ?? 0.5,
                      cropY: cover?.videoCropY ?? 0.5,
                      cropScale: cover?.videoCropScale ?? 1.0,
                    )
                  : (thumbnailUrl != null && thumbnailUrl.isNotEmpty
                        ? Image.network(
                            thumbnailUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, e, st) =>
                                _placeThumbPlaceholder(),
                          )
                        : _placeThumbPlaceholder()),
            ),
            _placeFavoriteOverlay(placeId, source),
          ],
        ),
        // 정보 열 — 파티 카드와 같은 4단 구성(배지 / 이름 / 지역 / 운영시간·요금).
        // 이 열의 높이가 곧 카드 높이이고, 사진이 그 높이를 따라온다.
        info: ListCardShell.infoColumn([
          // ① 배지 줄 — 플레이스 유형(파티 유형 자리) · 테마 · 애견동반 · 콤보.
          // 예전엔 한 줄 Row를 ClipRect로 잘라 "안 보이게"만 했는데,
          // 이제 파티 카드와 같은 Wrap이라 배지가 많으면 실제로 다음
          // 줄로 내려간다(잘려서 사라지지 않는다).
          ListCardShell.badgeWrap(
            placeCardBadges(info, eventSourceBadge: eventSourceBadge),
          ),
          // ② 장소명
          _placeTitle(info.name),
          // ③ 지역 (+ 좌석·공간 요약)
          if (info.shortAddress.isNotEmpty || info.facilitySummary.isNotEmpty)
            _placeInfoLine(
              Icons.location_on,
              [
                // 요약(플레이스는 특징)이 주소보다 앞이다 — 한 줄이 잘릴
                // 때 살아남아야 하는 쪽은 '왜 가볼 만한가'다.
                if (info.facilitySummary.isNotEmpty) info.facilitySummary,
                if (info.shortAddress.isNotEmpty) info.shortAddress,
              ].join(' · '),
            ),
          // ④ 운영시간(파티 날짜 자리) · 이용요금(참가비 자리)
          // 플레이스(events)는 요금 필드가 없어 요금 칸이 빠지고,
          // 운영시간이 그 폭까지 넓게 쓴다.
          if (info.hoursLabel.isNotEmpty || priceLabel != null)
            Row(
              children: [
                if (info.hoursLabel.isNotEmpty)
                  Expanded(
                    child: _placeInfoLine(Icons.schedule, info.hoursLabel),
                  )
                else
                  const Spacer(),
                if (priceLabel != null) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      priceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFF6FA0),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          // ⑤ 고른 시간 중 실제 이용 가능한 시간 — '일부 시간이라도 가능'
          // 으로 찾았을 때 어느 시간이 되는지 카드에서 바로 알 수 있게.
          if (availabilityLabel != null)
            placeAvailabilityLine(availabilityLabel!),
        ]),
        // 최대 수용 인원 — 파티 카드의 참가인원 열과 같은 자리.
        trailing: info.capacityMax > 0
            ? ListCardShell.trailingStat(
                icon: Icons.people_outline,
                value: '${info.capacityMax}',
                unit: '명',
              )
            : null,
      ),
    );
    return card;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ✨ 이벤트 카드 — **✨ 이벤트 필터에서만** 쓰는 [PlaceCompactCard]의 변주.
//
// ── 왜 따로 있는가 ───────────────────────────────────────────────────────────
// 같은 카드에 "이벤트 모드" 스위치를 다는 대신 클래스를 나눈다. 저 카드는
// 플레이스·장소대여 목록과 지도가 함께 쓰는 자리라, 분기가 하나 늘면 이벤트를
// 고치다 지도 카드가 조용히 바뀐다. 껍데기·배지·정보줄·찜·이동은 **같은 함수**를
// 그대로 부르므로 모양이 갈라지지도 않는다.
//
// ── 무엇이 다른가 ────────────────────────────────────────────────────────────
// 우선순위가 뒤집힌다. 이벤트를 탐색하는 사람은 "무슨 이벤트인지"를 먼저 보고
// "어디서 하는지"를 그다음에 본다.
//
//   대표 사진 : 매장/공간 사진 → **그 이벤트의 대표 미디어**
//   큰 제목   : 매장명        → **이벤트 제목**(최대 2줄)
//   📍 줄     : 지역          → **매장명 · 지역**(매장명은 보조로 내려온다)
//   🕒 줄     : 매장 영업시간 → **이벤트 시간**(없으면 영업시간으로 되돌아간다)
//
// 대표 미디어 판정은 새로 만들지 않는다 — 파티·플레이스·이벤트가 다 같이 쓰는
// [getPartyCoverMedia] 하나에 [PlacePromotion.coverMediaMap]을 그대로 넘긴다.
// 그래서 사진을 대표로 고른 이벤트는 사진이, 영상을 고른 이벤트는 영상 썸네일이
// 나오고, 대표 지정이 없던 옛 이벤트는 그 함수의 하위호환 규칙을 탄다.
//
// 이벤트에 미디어가 **하나도 없으면** 원본 매장/공간의 대표로 되돌아간다 —
// 그게 이 카드가 이벤트 중심이 되기 전의 모습이라, 회색 빈칸보다 낫다.
//
// 누르면 가는 곳은 [PlaceCompactCard]와 **똑같다**(매장 상세 / 장소대여 상세).
// 이벤트 상세 시트·신청·문의는 전부 그 안에 이미 있다.
// ─────────────────────────────────────────────────────────────────────────────

class PlaceEventCompactCard extends StatelessWidget {
  const PlaceEventCompactCard({
    super.key,
    required this.place,
    required this.placeId,
    required this.source,
    required this.promotion,
    this.eventSourceBadge,
    this.timeLabel = '',
    this.onTap,
  });

  /// 원본 매장/공간 문서 — 매장명·지역·유형 배지가 여기서 나온다.
  final Map<String, dynamic> place;
  final String placeId;
  final PlaceCardSource source;

  /// 이 카드가 앞세우는 이벤트 **한 건**. 사진과 제목이 반드시 같은 건에서
  /// 나와야 해서 맵 두 개가 아니라 이 객체 하나를 받는다.
  final PlacePromotion promotion;

  /// 🕒 줄에 적을 이벤트 시간. 정본은 [PlaceEventTime.timeLabelOf]이고,
  /// 부르는 쪽이 이미 계산해 두었으면 그 값을 그대로 받는다(같은 값을 두 번
  /// 계산해 문구가 갈리는 일이 없게).
  final String timeLabel;

  /// ✨ 카드 안에 붙는 **어디서 여는 이벤트인지** 배지
  /// ('✨ 매장 이벤트' / '✨ 공간 이벤트' — 정본은 `EventFeedKind.badge`).
  /// 이 자리는 예전에 '✨ 이벤트 진행중' 상태칩이 쓰던 자리다: 이벤트만 모인
  /// 목록에서 그 칩은 모든 카드에 똑같이 붙어 아무것도 가르지 못했다.
  final String? eventSourceBadge;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final info = PlaceCardInfo.from(
      place,
      source: source,
      tag: 'PlaceEventCompactCard',
    );
    // 이벤트의 대표 → 없으면 원본의 대표(예전 모습).
    final cover =
        getPartyCoverMedia(promotion.coverMediaMap, tag: 'EventFeedCard') ??
        info.cover;
    final isVideo = cover?.isVideo ?? false;
    final videoUrl = cover?.videoUrl;
    final thumbnailUrl = cover?.thumbnailUrl;

    // 매장명은 사라지지 않고 📍 줄로 내려온다 — "어디서 하는지"를 잃으면
    // 이벤트 제목만 남아 갈 곳을 알 수 없다.
    final where = [
      if (info.name.isNotEmpty) info.name,
      if (info.shortAddress.isNotEmpty) info.shortAddress,
    ].join(' · ');
    // 시간을 안 정한 이벤트는 매장 영업시간이 곧 이벤트 시간이다.
    final when = timeLabel.isNotEmpty ? timeLabel : info.hoursLabel;

    return ListCardShell(
      onTap: () {
        FeedVideoManager.instance.pauseActive();
        (onTap ?? () => _openPlaceDetail(context, source, placeId, place))();
      },
      decorationOverlay: info.hasPartychuPerk
          ? partychuPerkPlaqueOverlayCompact()
          : null,
      child: ListCardShell.horizontalBody(
        thumbnail: Stack(
          children: [
            ListCardShell.thumbnailBox(
              child: (isVideo && videoUrl != null && videoUrl.isNotEmpty)
                  ? VideoThumbnail(
                      videoUrl: videoUrl,
                      thumbnailUrl: thumbnailUrl,
                      autoplayOnVisible: false,
                      cropX: cover?.videoCropX ?? 0.5,
                      cropY: cover?.videoCropY ?? 0.5,
                      cropScale: cover?.videoCropScale ?? 1.0,
                    )
                  : (thumbnailUrl != null && thumbnailUrl.isNotEmpty
                        ? Image.network(
                            thumbnailUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, e, st) =>
                                _placeThumbPlaceholder(),
                          )
                        : _placeThumbPlaceholder()),
            ),
            // 찜은 여전히 **원본**에 붙는다 — 기존 찜 목록과 어긋나면 안 된다.
            _placeFavoriteOverlay(placeId, source),
          ],
        ),
        info: ListCardShell.infoColumn([
          // ① 유형 배지 — 장소 카드와 같은 목록·같은 순서.
          ListCardShell.badgeWrap(
            placeCardBadges(info, eventSourceBadge: eventSourceBadge),
          ),
          // ② 이벤트 제목 — 카드에서 가장 큰 글자. 두 줄까지 쓴다.
          _placeTitle(promotion.title, maxLines: 2),
          // ③ 📍 매장명 · 지역
          if (where.isNotEmpty) _placeInfoLine(Icons.location_on, where),
          // ④ 🕒 이벤트 시간
          if (when.isNotEmpty) _placeInfoLine(Icons.schedule, when),
        ]),
        // 수용 인원 열은 두지 않는다 — 이벤트 카드에서 그 숫자는 원본의
        // 정보이고, 그 폭이 빠지면 제목 두 줄이 들어갈 자리가 생긴다.
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 기본 화면 — 파티 목록 기본 카드(PartyStandardCard)와 같은 셸.
// ─────────────────────────────────────────────────────────────────────────────

class PlaceStandardCard extends StatelessWidget {
  final Map<String, dynamic> place;
  final String placeId;
  final PlaceCardSource source;
  final VoidCallback? onTap;

  /// 상세검색에서 고른 시간 중 실제로 이용 가능한 시간. [PlaceCompactCard]와
  /// 같은 값이며, 조건을 걸면 목록의 모든 카드가 함께 이 줄을 갖는다 —
  /// 2열 그리드에서 좌우 카드 높이가 어긋나지 않는 이유다.
  final String? availabilityLabel;

  /// 🎉 With파티 배지를 붙일지 — 목록/지도가 만든 색인이 넘겨준다.
  final bool withParty;

  const PlaceStandardCard({
    super.key,
    required this.place,
    required this.placeId,
    required this.source,
    this.onTap,
    this.availabilityLabel,
    this.withParty = false,
  });

  @override
  Widget build(BuildContext context) {
    final info = PlaceCardInfo.from(
      place,
      source: source,
      withParty: withParty,
      tag: 'PlaceStandardCard',
    );
    final cover = info.cover;
    final isVideo = cover?.isVideo ?? false;
    final videoUrl = cover?.videoUrl;
    final thumbnailUrl = cover?.thumbnailUrl;
    final priceLabel = info.priceLabel;

    // 파티츄 전용 혜택 — 카드 외곽선 위에 얇은 금빛 라인만 덧그린다.
    final card = GridCardShell(
      onTap: () {
        FeedVideoManager.instance.pauseActive();
        (onTap ?? () => _openPlaceDetail(context, source, placeId, place))();
      },
      decorationOverlay: info.hasPartychuPerk
          ? partychuPerkPlaqueOverlay()
          : null,
      // 2열 그리드라 작은 카드처럼 화면에 보이는 것만으로 자동재생하지 않고
      // 탭했을 때만 재생한다(기존 장소 카드 동작 그대로).
      media: (isVideo && videoUrl != null && videoUrl.isNotEmpty)
          ? VideoThumbnail(
              videoUrl: videoUrl,
              thumbnailUrl: thumbnailUrl,
              autoplayOnVisible: false,
              cropX: cover?.basicCardVideoFocalX ?? 0.5,
              cropY: cover?.basicCardVideoFocalY ?? 0.5,
              cropScale: cover?.basicCardVideoScale ?? 1.0,
            )
          : (thumbnailUrl != null && thumbnailUrl.isNotEmpty
                ? gridCardPhoto(
                    url: thumbnailUrl,
                    focalX: cover?.basicCardPhotoFocalX ?? 0.5,
                    focalY: cover?.basicCardPhotoFocalY ?? 0.5,
                    scale: cover?.basicCardPhotoScale ?? 1.0,
                  )
                : _placeThumbPlaceholder()),
      mediaOverlays: [
        // 좌상단 — 오른쪽 위는 찜 버튼 자리라 이 배지는 왼쪽에 둔다. 파티츄
        // 혜택 명판도 좌측 상단 모서리에 걸치므로, 명판이 있는 카드에서는
        // 명판이 덮는 높이만큼 아래로 내려 겹치지 않게 한다(파티 기본 카드와
        // 같은 규칙).
        if (info.isStayPartyCombo)
          Positioned(
            left: 10,
            top: info.hasPartychuPerk
                ? PartychuPerkPlaqueSize.standard.overlayBadgeTop
                : 10,
            child: PartyCard.stayPartyComboBadge(),
          ),
        _placeFavoriteOverlay(placeId, source),
      ],
      info: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 유형(파티 유형 자리) · 테마 · 애견동반 배지 — 폭이 넓은 카드라
          // 한 줄에 안 들어가면 Wrap이 다음 줄로 넘긴다.
          if (placeCardBadges(info).isNotEmpty) ...[
            Wrap(spacing: 4, runSpacing: 4, children: placeCardBadges(info)),
            const SizedBox(height: 5),
          ],
          _placeTitle(info.name),
          const SizedBox(height: 4),
          // 왼쪽(운영시간/지역/좌석)·오른쪽(수용인원/이용요금) 2단 — 파티 기본
          // 카드가 날짜·지역과 참가인원·참가비를 나눠 담는 것과 같은 구조.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ★ 파티 기본 카드와 같은 규칙 — 이 열은 **항상 정확히
                    //   3줄**이다. 값이 없어도 줄을 빼지 않는다. 줄 수가
                    //   달라지면 그만큼 카드 세로 길이가 달라져 2열 그리드에서
                    //   좌우 카드의 아래끝이 어긋난다.
                    _placeInfoLine(Icons.schedule, info.hoursLabel),
                    const SizedBox(height: 3),
                    _placeInfoLine(Icons.location_on, info.shortAddress),
                    const SizedBox(height: 3),
                    _placeInfoLine(Icons.chair_outlined, info.facilitySummary),
                  ],
                ),
              ),
              // 수용 인원·이용요금은 그 필드를 가진 스키마(장소대여)에서만
              // 그린다 — 플레이스(events)는 두 줄이 통째로 빠지고 왼쪽 정보가
              // 카드 폭을 다 쓴다.
              if (info.capacityMax > 0 || priceLabel != null) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (info.capacityMax > 0) ...[
                      Text(
                        '최대 ${info.capacityMax}명',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black45,
                        ),
                      ),
                      if (priceLabel != null) const SizedBox(height: 3),
                    ],
                    if (priceLabel != null)
                      Text(
                        priceLabel,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFF6FA0),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
          if (availabilityLabel != null) ...[
            const SizedBox(height: 4),
            placeAvailabilityLine(availabilityLabel!),
          ],
        ],
      ),
    );
    return card;
  }
}

/// 상세검색에서 고른 시간 중 실제로 이용 가능한 시간을 알려주는 줄 —
/// 작은 카드·기본 카드가 같은 모양으로 쓴다. 판정과 문구는
/// [PlaceAvailabilityMatch]가 만들고, 여기서는 그리기만 한다.
Widget placeAvailabilityLine(String label) => Row(
  children: [
    const Icon(Icons.event_available, size: 12, color: Color(0xFF047857)),
    const SizedBox(width: 3),
    Expanded(
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF047857),
        ),
      ),
    ),
  ],
);

/// 대표 이미지가 없을 때의 자리 표시 — 기존 장소 카드와 동일.
Widget _placeThumbPlaceholder() => Container(
  color: const Color(0xFFFFE0EE),
  child: const Center(
    child: Icon(Icons.home_outlined, size: 36, color: Color(0xFFFF6FA0)),
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// 큰 카드 — 파티 목록 큰 카드(PartyVideoFeedCard)와 **동일한 구조**.
//
//   대표 미디어를 카드 전체에 깔고(동영상이면 화면에 보일 때 자동재생·무음),
//   그 위에 아래쪽 그라디언트 스크림 → 배지 → 제목 → 정보 박스 → 진행바 →
//   "상세보기" 버튼 순으로 얹는다. 정보 박스(feedInfoOverlayBox)와 진행바
//   (VideoSeekBar), 자동재생/단일재생 조율(VideoThumbnail·FeedVideoManager)은
//   파티 큰 카드가 쓰는 것을 그대로 가져다 쓴다 — 로직 중복 없음.
//
// 파티 큰 카드는 전체화면 피드(PartyVideoFeedScreen)에서 한 장씩 넘겨보지만,
// 플레이스/장소대여는 기존 목록 안에서 1열로 이어 붙인다. 그래서 높이만
// 화면 높이에 비례해 정하고(카드 사이 여백 유지), 나머지는 동일하다.
// ─────────────────────────────────────────────────────────────────────────────

class PlaceLargeCard extends StatefulWidget {
  final Map<String, dynamic> place;
  final String placeId;
  final PlaceCardSource source;
  final VoidCallback? onTap;

  const PlaceLargeCard({
    super.key,
    required this.place,
    required this.placeId,
    required this.source,
    this.onTap,
  });

  @override
  State<PlaceLargeCard> createState() => _PlaceLargeCardState();
}

class _PlaceLargeCardState extends State<PlaceLargeCard> {
  // 진행바가 구독하는 컨트롤러 — VideoThumbnail이 재생을 시작/해제할 때마다
  // 콜백으로 알려준다(파티 큰 카드와 동일).
  VideoPlayerController? _seekController;
  bool _seekActive = false;
  Timer? _seekHideTimer;

  void _onControllerChanged(VideoPlayerController? controller) {
    if (!mounted) return;
    setState(() => _seekController = controller);
  }

  void _pulseSeekBar() {
    setState(() => _seekActive = true);
    _seekHideTimer?.cancel();
    _seekHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _seekActive = false);
    });
  }

  @override
  void dispose() {
    _seekHideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = PlaceCardInfo.from(
      widget.place,
      source: widget.source,
      tag: 'PlaceLargeCard',
    );
    final cover = info.cover;
    // 등록자가 사진을 대표로 골랐다면 이 카드가 "크게 보기"여도 그 사진을
    // 그대로 보여준다(동영상이 따로 있어도 재생하지 않음) — 파티 큰 카드와
    // 동일한 판정이다.
    final hasVideo = cover?.isVideo ?? false;
    final videoUrl = cover?.videoUrl;
    final thumbnailUrl = cover?.imageUrl ?? cover?.thumbnailUrl;
    // 사진·영상을 순서대로 자동으로 넘긴다(상세 화면 갤러리와 같은 규칙).
    // 영상 하나뿐이면 예전처럼 그 영상을 반복 재생한다.
    final storyItems = feedMediaItems(widget.place, cover);
    final useStory =
        storyItems.length > 1 ||
        (storyItems.length == 1 && !storyItems.first.isVideo);
    final priceLabel = info.priceLabel;
    final badges = placeCardBadges(info);

    // 파티 큰 카드(PartyVideoFeedCard)와 **완전히 같은 껍데기** — 고정 높이도,
    // 둥근 모서리도, 바깥 여백도 없다. 이 카드는 전체화면 피드
    // (FullscreenCardFeed) 안에서 화면 한 장을 통째로 차지한다.
    //
    // 예전에는 목록 안에 높이 62%짜리 둥근 카드로 인라인 배치돼 있어서,
    // 카드 내용물은 파티와 같은 위젯을 쓰는데도 화면이 전혀 달라 보였다.
    //
    // 껍데기(검은 바탕 · 하단 그라디언트 · 여백 18/72/18/22 · 제목 박스 ·
    // 진행바와 버튼 자리)는 파티샵 큰 카드([ShopLargeCard])와 **같은 함수**
    // 하나가 그린다([largeCardBody]) — 여기서 넘기는 것은 내용뿐이다.
    return largeCardBody(
      // 대표 미디어 — 동영상은 등록 시 지정한 크롭 위치를 그대로 반영하고,
      // 사진은 원본 비율이 잘리지 않게 contain으로 둔다(파티 큰 카드와 동일).
      media: useStory
          ? FeedPhotoStory(
              items: storyItems,
              placeholder: _placeThumbPlaceholder(),
              videoBuilder: (context, item, {
                required onCompleted,
                required onLoadFailed,
                required onControllerChanged,
              }) => VideoThumbnail(
                videoUrl: item.url,
                thumbnailUrl: item.thumbnailUrl,
                // 크롭 위치는 대표 영상에 지정한 값이다.
                cropX: hasVideo ? cover?.videoCropX ?? 0.5 : 0.5,
                cropY: hasVideo ? cover?.videoCropY ?? 0.5 : 0.5,
                cropScale: hasVideo ? cover?.videoCropScale ?? 1.0 : 1.0,
                onTap: _pulseSeekBar,
                onControllerChanged: (c) {
                  onControllerChanged(c);
                  _onControllerChanged(c);
                },
                letterboxLandscape: true,
                loop: false,
                onCompleted: onCompleted,
                onLoadFailed: onLoadFailed,
              ),
            )
          : (hasVideo && videoUrl != null && videoUrl.isNotEmpty)
          ? VideoThumbnail(
              videoUrl: videoUrl,
              thumbnailUrl: cover?.thumbnailUrl,
              cropX: cover?.videoCropX ?? 0.5,
              cropY: cover?.videoCropY ?? 0.5,
              cropScale: cover?.videoCropScale ?? 1.0,
              onTap: _pulseSeekBar,
              onControllerChanged: _onControllerChanged,
              letterboxLandscape: true,
            )
          : (thumbnailUrl != null && thumbnailUrl.isNotEmpty
                ? Image.network(
                    thumbnailUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => _placeThumbPlaceholder(),
                  )
                : _placeThumbPlaceholder()),
      // 유형·테마·애견동반·콤보·파티츄 혜택 배지 — 작은/기본 카드와 완전히
      // 같은 목록(placeCardBadges)을 쓴다.
      badges: badges,
      title: info.name,
      // 파티 큰 카드가 왼쪽에 날짜/시간/지역, 오른쪽에 참가인원/참가비를
      // 쌓는 것과 같은 좌우 구성 — 플레이스는 왼쪽 운영시간/지역/좌석,
      // 오른쪽 수용 인원/이용요금이다(기본 카드의 대응 관계 그대로).
      info: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (info.hoursLabel.isNotEmpty)
                  largeCardInfoLine(Icons.schedule, info.hoursLabel),
                if (info.shortAddress.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  largeCardInfoLine(Icons.location_on, info.shortAddress),
                ],
                if (info.facilitySummary.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  largeCardInfoLine(Icons.chair_outlined, info.facilitySummary),
                ],
              ],
            ),
          ),
          // 수용 인원·이용요금은 그 필드를 가진 스키마(장소대여)에서만
          // 그린다 — 플레이스(events)는 이 열이 통째로 빠진다.
          if (info.capacityMax > 0 || priceLabel != null) ...[
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (info.capacityMax > 0)
                  Text(
                    '최대 ${info.capacityMax}명',
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                if (priceLabel != null) ...[
                  if (info.capacityMax > 0) const SizedBox(height: 6),
                  largeCardPriceText(priceLabel),
                ],
              ],
            ),
          ],
        ],
      ),
      // 진행바는 실제 동영상이 재생 중일 때만 — 자리는 껍데기가 잡는다.
      seekBar: (hasVideo && _seekController != null)
          ? VideoSeekBar(
              controller: _seekController!,
              active: _seekActive,
              onInteract: _pulseSeekBar,
            )
          : null,
      // 상세보기 + 찜 — 찜은 우상단(전체화면 피드의 보기 방식 버튼 자리)이
      // 아니라 여기 둔다. 왼쪽 정렬이라 우하단 음소거 버튼과도 겹치지 않는다.
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          largeCardDetailButton(
            onPressed: () {
              FeedVideoManager.instance.pauseActive();
              (widget.onTap ??
                  () => _openPlaceDetail(
                    context,
                    widget.source,
                    widget.placeId,
                    widget.place,
                  ))();
            },
          ),
          // 내가 등록한 플레이스에는 찜을 띄우지 않는다 — 내 글을 내가
          // 찜하는 건 의미가 없다.
          if (!isMyPlace(widget.place)) ...[
            const SizedBox(width: 10),
            FavoriteStarButton(
              itemType: widget.source == PlaceCardSource.rental
                  ? FavoriteType.place
                  : FavoriteType.event,
              itemId: widget.placeId,
              size: 26,
              unfavoritedColor: Colors.white,
              glow: false,
            ),
          ],
        ],
      ),
    );
  }
}
