import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, setEquals;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:party_app/screens/register_type_screen.dart';
import 'package:party_app/screens/map_screen.dart';
import 'package:party_app/utils/web_launch_url.dart';
import 'package:party_app/screens/my_page_screen.dart';
import 'package:party_app/screens/place_detail_screen.dart';
import 'package:party_app/screens/party_shop_detail_screen.dart';
import 'package:party_app/screens/party_detail_screen.dart';
import 'package:party_app/models/combo_place_type.dart';
import 'package:party_app/models/custom_amenity.dart';
import 'package:party_app/models/custom_play_item.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/screens/party_video_feed_screen.dart';
import 'package:party_app/screens/place_feed_screen.dart';
import 'package:party_app/utils/favorites_service.dart';
import 'package:party_app/utils/geo_distance.dart';
import 'package:party_app/utils/feed_video_manager.dart';
import 'package:party_app/utils/partychu_perk_ranking.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/services/block_service.dart';
import 'package:party_app/services/chat_service.dart';
import 'package:party_app/services/notification_service.dart';
import 'package:party_app/screens/notifications_screen.dart';
import 'package:party_app/utils/party_eligibility.dart';
import 'package:party_app/utils/party_scale_filter.dart';
import 'package:party_app/models/party_time_filter.dart';
import 'package:party_app/models/korean_holidays.dart';
import 'package:party_app/utils/register_return_signal.dart';
import 'package:party_app/widgets/favorite_star_button.dart';
import 'package:party_app/screens/chat_target_list_screen.dart';
import 'package:party_app/login.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/utils/root_gate.dart' show identityRequirementMet;
import 'package:party_app/utils/responsive.dart';
import 'package:party_app/models/party_age_restriction.dart';
import 'package:party_app/models/party_date_focus.dart';
import 'package:party_app/models/party_filter.dart';
import 'package:party_app/models/party_search.dart';
import 'package:party_app/models/party_open_state.dart';
import 'package:party_app/models/party_pricing.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/models/party_series.dart';
import 'package:party_app/models/place_availability.dart';
import 'package:party_app/models/reservation_modes.dart';
import 'package:party_app/models/room_price_type.dart';
import 'package:party_app/models/place_facility_options.dart';
import 'package:party_app/services/listing_sources.dart';
import 'package:party_app/services/place_availability_service.dart';
import 'package:party_app/services/place_create_eligibility.dart';
import 'package:party_app/services/registration_limits.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/models/region_selection.dart';
import 'package:party_app/widgets/region_grid_selector.dart';
import 'package:party_app/utils/early_bird.dart';
import 'package:party_app/models/capacity_filter.dart';
import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/place_filter.dart';
import 'package:party_app/models/place_taxonomy.dart';
import 'package:party_app/models/place_weekly_hours.dart';
import 'package:party_app/widgets/partychu_perk.dart' show partychuPerkFrom;
import 'package:party_app/models/pet_policy.dart';
import 'package:party_app/models/shop_filter.dart';
import 'package:party_app/models/crew_area.dart';
import 'package:party_app/models/crew_filter.dart';
import 'package:party_app/widgets/auth_rebuilder.dart';
import 'package:party_app/widgets/host_register_invite_sheet.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/widgets/detail_search_sheet.dart';
import 'package:party_app/widgets/event_detail_search_sheet.dart';
import 'package:party_app/widgets/place_detail_search_sheet.dart';
import 'package:party_app/widgets/shop_detail_search_sheet.dart';
import 'package:party_app/widgets/crew_detail_search_sheet.dart';
import 'package:party_app/utils/party_view_mode.dart';
import 'package:party_app/widgets/party_view_mode_sheet.dart';
import 'package:party_app/widgets/view_mode_switch.dart';
import 'package:party_app/widgets/party_sort_sheet.dart';
import 'package:party_app/models/place_sort_mode.dart';
import 'package:party_app/widgets/place_sort_sheet.dart';
import 'package:party_app/widgets/main/sort_entry_button.dart';
import 'package:party_app/utils/place_view_mode.dart';
import 'package:party_app/widgets/place_card_widget.dart';
import 'package:party_app/widgets/shop_card_widget.dart';
// 🎪 파티츄/이벤트 탭의 이벤트 구획 — 매장 이벤트와 공간 이벤트를 함께 그린다.
import 'package:party_app/models/event_feed.dart';
import 'package:party_app/widgets/main/event_feed_section.dart';
import 'package:party_app/widgets/video_mute_button.dart';
import 'package:party_app/widgets/main/main_top_bar.dart';
import 'package:party_app/widgets/main/main_filter_panel.dart';
import 'package:party_app/widgets/main/main_preview_panel.dart';
import 'package:party_app/widgets/main/capacity_picker_sheet.dart';
import 'package:party_app/widgets/main/place_rental_type_sheet.dart';
import 'package:party_app/widgets/main/place_category_explorer.dart';
import 'package:party_app/models/place_party_index.dart';
import 'package:party_app/models/place_event_index.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/services/place_promotion_service.dart';
import 'package:party_app/widgets/main/place_quick_feature_bar.dart';
import 'package:party_app/widgets/main/place_quick_time_bar.dart';
import 'package:party_app/widgets/main/korean_calendar_sheet.dart';
import 'package:party_app/widgets/main/party_scale_picker_sheet.dart';
import 'package:party_app/widgets/main/quick_date_pane.dart';
import 'package:party_app/widgets/main/quick_filter_icon_button.dart';
import 'package:party_app/widgets/main/region_filter_fit.dart';
import 'package:party_app/widgets/main/visit_time_picker_sheet.dart';
import 'package:party_app/widgets/main/search_entry_sheet.dart';
import 'package:party_app/screens/party_register_entry_choice_screen.dart';
import 'package:party_app/screens/place_entry_register_screen.dart';
import 'package:party_app/screens/party_market_register_screen.dart';
import 'package:party_app/screens/crew_register_screen.dart';
import 'package:party_app/screens/crew_detail_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/widgets/web_frame.dart';
import 'package:party_app/widgets/pre_registration_notice.dart';
import 'package:party_app/services/pre_registration_visibility.dart';

// ── 낮/밤 전환 버튼의 아이콘·문구 ─────────────────────────────────────────
//
// 이 버튼은 **지금 무슨 모드인지**가 아니라 **누르면 무엇이 되는지**를 보여준다.
// 홈 상단에 아이콘 하나뿐인 버튼이라, 그림이 곧 그 버튼의 뜻이다 — 지금 모드를
// 그리면 "이미 그런 상태"를 다시 알려줄 뿐이고, 눌렀을 때 무엇이 일어나는지는
// 아무 데도 없다. 그래서 낮에는 🌙(→ 밤으로), 밤에는 ☀️(→ 낮으로)를 그린다.
//
// 배경색은 반대로 **지금 모드**를 따른다(버튼이 앉은 헤더가 낮이냐 밤이냐로
// 대비가 정해진다). 전환 로직·저장 구조는 이 파일 어디에서도 바뀌지 않는다.

/// 낮/밤 전환 버튼에 그릴 아이콘 — 누르면 될 모드 쪽이다.
IconData dayNightToggleIcon(bool isNightMode) =>
    isNightMode ? Icons.wb_sunny_rounded : Icons.nightlight_round;

/// 같은 버튼의 툴팁이자 접근성 문구 — 아이콘과 **같은 방향**(= 그 행동)을
/// 가리킨다. 둘이 어긋나면 화면을 읽어 주는 쪽에서만 반대로 안내된다.
String dayNightToggleTooltip(bool isNightMode) =>
    isNightMode ? '낮 모드로 전환' : '밤 모드로 전환';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  // ── 상단 탭 (4개 카테고리) ─────────────────────────────────────────
  late final TabController _topTabController;
  final _tabBarKey = GlobalKey();

  // ── 코치마크 (첫 진입 스와이프 안내) ─────────────────────────────
  bool _showCoachMark = false;
  late final AnimationController _coachMarkCtrl;
  late final Animation<double> _coachMarkAnim;

  // ── 하단 내비게이션 ───────────────────────────────────────────────
  int _currentIndex = 0;

  // ── 헤더 축소 상태 (스크롤 연동 — 로고 배너만 축소) ────────────────
  bool _headerCollapsed = false;
  final ScrollController _partyScrollCtrl = ScrollController();

  // ── 헤더 전체 숨김(수동 토글) ────────────────────────────────────
  // 위 _headerCollapsed(스크롤에 따라 로고 배너만 자동 크로스페이드)와는
  // 별개로, 사용자가 "전체 숨김" 버튼을 눌러 로고/탭바/"파티 목록" 제목
  // 줄(검색·보기방식·정렬 포함)·날짜 카테고리·상세검색까지 한 번에 접고
  // 펼 수 있게 한다. 파티 탭에서만 의미가 있는 컨트롤이라 버튼 자체도
  // _buildPartyListHeaderRow(모바일 파티 탭)에서만 노출한다.
  bool _headerFullyHidden = false;

  // ── 헤더 배너 낮/밤 버전 토글 ──────────────────────────────────────
  // 낮 버전 이미지(header_logo_last/header_half)는 나중에 별도로 다시
  // 디자인할 예정이라 지금은 그대로 두고, 밤 버전만 header_logo_night1/
  // header_half_night1로 교체해 보여준다. _headerCollapsed(스크롤 축소)와는
  // 독립적인 별개의 상태 — 두 축이 곱해져 4가지 이미지 중 하나가 보인다.
  bool _isNightMode = false;

  // 영상 크게 보기는 더 이상 목록 화면 안에서 인라인으로 그려지지 않고
  // 항상 별도의 전체화면(PartyVideoFeedScreen)으로만 진입한다. 앱을 마지막에
  // 영상 모드로 종료했다가 다시 켰을 때는 목록 자체는 기본 카드로 그린 채
  // 파티 문서가 로드되는 즉시 한 번만 자동으로 전체화면을 띄운다.
  bool _pendingAutoOpenVideoFeed = false;

  // ── 파티 목록 정렬 ────────────────────────────────────────────────
  // 정렬 입구는 날짜 필터 바의 정렬 버튼(_openSortSheet) **하나뿐**이다 —
  // 예전에는 상세검색 시트에도 같은 아코디언이 있어 "검색 조건"과 "목록 정렬"이
  // 뒤섞여 보였다. 거리순만 위치 권한/좌표가 필요해
  // _currentPosition은 화면 상태로 별도 보관한다(필터 값이 아니라 기기
  // 상태이므로 PartyFilter에는 넣지 않음).
  Position? _currentPosition; // 거리순 정렬용

  // ── 파티츄/이벤트 탭이 무엇을 보이는가 ──────────────────────────────
  //
  // [ 전체 | 🎉 파티 | 🎪 이벤트 ] — 이 탭 하나에서 세 종류(파티·매장 이벤트·
  // 공간 이벤트)를 모두 발견한다. **필터일 뿐 데이터가 아니다**: 파티는 예전
  // 그대로 `parties`에서, 이벤트는 각자의 정본에서 읽고 여기서는 무엇을 그릴지만
  // 정한다([EventFeedFilter] / [EventFeed]).
  //
  // 날짜·시간·인원·정렬·검색은 파티에만 뜻이 있는 조건이라 이벤트 칸에서는
  // 줄 자체를 감춘다 — 걸리지 않는 조건을 켜 두면 목록이 이상하게 움직인다.
  EventFeedFilter _feedFilter = EventFeedFilter.all;

  // ── 파티 목록 보기 방식(작은 카드/기본 카드/영상 크게 보기) ─────────
  // 기기에 저장되어 앱을 다시 실행해도 유지된다(PartyViewMode.load()).
  PartyViewMode _viewMode = PartyViewMode.standard;

  // ── 장소대여 목록 보기 방식(작은 화면/기본 화면) ────────────────────
  // 파티와 완전히 별개로 저장한다(PlaceViewMode.load()) — 두 탭의 카드가
  // 서로 다른 목적이라 한쪽을 바꿨다고 다른 쪽까지 바뀌면 곤란하다.
  //
  // 파티의 영상 크게 보기와 마찬가지로, 큰 카드는 목록에 인라인으로 그리지
  // 않고 항상 전체화면(PlaceFeedScreen)으로만 진입한다 — 그래서 이 값은
  // 절대 large가 되지 않는다.
  PlaceViewMode _placeViewMode = PlaceViewMode.standard;

  // ── 🛍️ 파티샵 목록 보기 방식 ──────────────────────────────────────
  //
  // 플레이스와 **같은 칸 셋·같은 컨트롤**을 쓴다([PlaceViewMode] /
  // [ViewModeMenuButton]) — 파티샵만 다른 아이콘이나 다른 버튼을 만들지 않는다.
  // 저장 자리만 따로다([ShopViewModePrefs]).
  //
  // 플레이스와 **다른 점 하나**: 큰 카드를 전체화면으로 열지 않고 목록 안에서
  // 그대로 크게 그린다. 파티샵에는 전체화면 피드가 없고(플레이스의
  // [PlaceFeedScreen] 같은 화면), 그것을 새로 만드는 것은 "보기 방식 하나
  // 추가"가 아니라 화면 하나를 새로 만드는 일이다. 그래서 이 값은 셋 다 될 수
  // 있고, 세 방식 모두 목록이 그 자리에서 바뀐다.
  PlaceViewMode _shopViewMode = PlaceViewMode.standard;

  // ── 장소대여 탭 **전용** 보기 방식 입구 ───────────────────────────
  //
  // 보기 방식 버튼은 세 칸짜리 세그먼트가 아니라 아이콘 하나짜리 버튼이고,
  // 누르면 그 자리에 붙는 메뉴가 세 가지를 한 번에 보여준다
  // ([_placeViewModeButton]). **플레이스 탭도 같은 버튼을 쓴다** — 두 탭이
  // [_placeViewMode] 하나를 함께 보므로 입구가 갈릴 이유가 없다.
  //
  // 별도 상태를 두지 않는다: 지금 보기 방식은 언제나 [_placeViewMode] 하나뿐
  // 이고, 버튼 아이콘과 시트의 선택 표시가 그 값 하나를 함께 본다. (예전에는
  // 누를 때마다 다음 칸으로 넘어가는 순환이라 "방금 고른 칸이 큰 카드였는지"를
  // 따로 기억해야 했지만, 직접 고르는 방식에는 다음 칸이라는 개념이 없다.)

  // ── 장소대여 목록 정렬 ────────────────────────────────────────────
  // 정렬은 **거르는 조건이 아니라 순서**라 [_placeFilter]에 넣지 않았다 —
  // 검색 시트의 "전체 초기화"가 필터를 새로 만들어도 보고 있던 정렬은 그대로
  // 남고, 상세검색 조건 개수(isActive)에도 섞이지 않는다(파티도 같은 뜻으로
  // 정렬 입구를 조건 시트 밖에 둔다).
  PlaceSortMode _placeSortMode = PlaceSortMode.defaultOrder;

  // 거리순 기준점 — 파티 거리순의 [_currentPosition]과 **따로** 둔다.
  // 파티에서 거리순을 껐다고 장소대여의 기준점까지 사라지면 안 된다.
  Position? _placeSortPosition;

  // 앱을 마지막에 큰 카드 모드로 종료했다가 다시 켰을 때, 문서가 로드되는
  // 즉시 한 번만 전체화면 피드를 자동으로 띄우기 위한 플래그
  // (_pendingAutoOpenVideoFeed의 플레이스판).
  bool _pendingAutoOpenPlaceFeed = false;

  // 보기 방식 토글은 StreamBuilder "밖"에 고정돼 있어 그 자리에서는 목록
  // 문서를 알 수 없다. 그래서 목록이 그려질 때마다 마지막 문서 목록을 여기
  // 담아 두고, 토글에서 큰 카드를 고르면 이 값으로 전체화면을 연다.
  List<QueryDocumentSnapshot> _lastPlaceDocs = const [];

  /// ✨ 기타 편의 서비스 목록을 만들 **현재 검색 범위**.
  ///
  /// 기타를 뺀 나머지 조건(검색어·지역·업종·특징…)까지 모두 통과한 문서다.
  /// 목록을 그릴 때마다 갱신되므로 시트를 열 때 추가 조회가 필요 없고
  /// ([ListingSources]가 컬렉션을 통째로 읽어 클라이언트에서 거르는 구조),
  /// 개수도 "지금 보고 있는 범위의 개수"가 된다. 0건 항목은 애초에
  /// 만들어지지 않는다.
  List<Map<String, dynamic>> _eventAmenityScope = const [];

  /// 장소대여 탭의 같은 것 — 기타를 뺀 나머지 조건까지 통과한 문서.
  List<Map<String, dynamic>> _placeAmenityScope = const [];
  PlaceCardSource _lastPlaceSource = PlaceCardSource.rental;

  // 전체화면 피드가 이미 떠 있는지 — 자동 진입과 토글 탭이 겹쳐 두 겹으로
  // 쌓이는 것을 막는다.
  bool _placeFeedOpen = false;

  // ── 파티 탭 전용 상태 ─────────────────────────────────────────────
  // 쿼리는 [ListingSources]에만 있다 — 통합 지도가 같은 문서 집합을 봐야
  // 목록에서 빠진 파티가 지도에만 남는 일이 생기지 않는다.
  final Stream<QuerySnapshot> _partyStream = ListingSources.parties()
      .snapshots();

  /// 🎉 With파티 색인 — 지금 파티가 걸려 있는 플레이스 id 집합.
  ///
  /// 플레이스 탭은 `events`만 스트림으로 읽으므로, 이 조건 하나 때문에 파티
  /// 쪽을 따로 구독한다. 위 [_partyStream]과 **같은 쿼리**라 Firestore SDK가
  /// 리스너를 합쳐 주고, 지도도 자기가 이미 받는 파티 스냅샷으로 같은 색인을
  /// 만든다([PlacePartyIndex]) — 두 화면의 With파티 결과가 갈릴 수 없다.
  PlacePartyIndex _withPartyIndex = PlacePartyIndex.empty;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _withPartySub;

  /// 🎉 이벤트 색인 — 지금 보여줄 이벤트가 있는 매장 id 집합
  /// ([PlaceEventIndex]). 이벤트 칸을 켰을 때 목록을 좁히는 정본이다.
  ///
  /// **이벤트 칸이 켜져 있는 동안에만 구독한다**([_syncPlaceEventIndexSub]).
  /// 이벤트를 보지 않는 사람에게까지 `placePromotions` 전체를 상시로 내려받게
  /// 하면, 목록을 보러 온 화면에 쓰지도 않는 읽기가 계속 붙는다.
  ///
  /// 아직 못 읽었으면 null이다 — 그동안은 판정을 넘기지 않아 예전 미러 판정이
  /// 그대로 답한다([EventFilter.matchesDiscovery]). 목록이 잠깐 통째로 비는
  /// 것보다 낫다.
  PlaceEventIndex? _placeEventIndex;
  StreamSubscription<List<PlacePromotion>>? _placeEventSub;

  /// 🎪 **장소대여** 이벤트 색인 — 위와 같은 것을 공간대여·숙박(`places`)에
  /// 대해 만든다([PlaceEventIndex.rentalCollection]).
  ///
  /// 둘을 한 색인으로 합치지 않는 이유는 하나다 — 플레이스 탭에는 매장
  /// 이벤트만, 장소대여 탭에는 공간 이벤트만 보여야 하고, id가 우연히 겹치면
  /// 한 집합으로는 그것을 갈라낼 수 없다. 구독을 따로 거는 대신 조건이 켜진
  /// 탭만 읽는 규칙은 그대로다([_syncRentalEventIndexSub]).
  PlaceEventIndex? _rentalEventIndex;
  StreamSubscription<List<PlacePromotion>>? _rentalEventSub;

  /// 같은 게시글(seriesId)의 날짜 문서들을 카드 한 장으로 접는 데 쓰는 색인.
  /// 목록을 그릴 때마다 최신 스냅샷으로 다시 만든다(카드가 "일정 N개" 배지를
  /// 물어볼 때 쓰므로 필드로 들고 있는다).
  PartySeries _partySeries = PartySeries.index(const []);

  PartyFilter _filter = PartyFilter();

  // ── 장소대여/파티샵/파트너 탭 전용 상세검색 필터 (파티와 완전히 분리) ─
  PlaceFilter _placeFilter = PlaceFilter();
  ShopFilter _shopFilter = ShopFilter();
  CrewFilter _crewFilter = CrewFilter();
  // 플레이스 탭 상세검색 필터 — 상단 특징(테마) 태그 칩도 이 안의
  // [EventFilter.themeTags]를 켜고 끈다. 칩과 시트가 **같은 값 하나**를 보므로
  // 어느 쪽에서 고르든 결과가 갈리지 않는다.
  EventFilter _eventFilter = EventFilter();
  Set<String> get _eventThemeFilter => _eventFilter.themeTags;
  // 플레이스 탭 상단 카테고리 칩의 "파티샵"은 events가 아니라 완전히 별도인
  // partyShops 컬렉션을 보여주므로, 테마 태그(_eventThemeFilter)와는 분리된
  // 전용 상태로 다른 4개 칩과 배타적으로 전환한다(둘 다 켜질 수 없음).
  bool _placeShowShopCategory = false;

  Set<DateTime> _partyDates = {};
  late final StreamSubscription<QuerySnapshot> _partyDatesSub;

  // ── 검색 ──────────────────────────────────────────────────────────
  // 네 탭 모두 상단의 돋보기 하나로만 검색에 들어가고(_openSearchSheet →
  // [SearchEntrySheet]), 그 시트 안에서 "검색어 + 상세검색"을 함께 쓴다.
  // 검색어는 **탭마다 따로** 들고 있어서 탭을 옮겨도 서로 걸러지지 않는다.
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  /// 파티 외 탭의 검색어 — 파티의 [_searchController]/[_searchQuery] 한 쌍과
  /// 같은 역할이고, 탭 수만큼 필드를 늘어놓지 않으려고 묶어둔 것뿐이다.
  final _TabSearch _eventSearch = _TabSearch();
  final _TabSearch _placeSearch = _TabSearch();
  final _TabSearch _shopSearch = _TabSearch();
  final _TabSearch _crewSearch = _TabSearch();

  // ── 장소대여 지역 필터 ─────────────────────────────────────────────
  // 선택값의 **정본은 [_placeFilter].regions 하나뿐**이다. 상단 퀵 지역
  // 버튼과 상세검색 시트는 입구가 둘일 뿐 같은 Set을 고친다 — 예전에는
  // 퀵 필터가 별도 Set을 들고 있어서 "상단 서울 강남구 + 상세검색 경기
  // 성남시"가 AND로 걸려 결과가 통째로 비어버렸다.
  //
  // 값 형식과 최대 개수·'전체'와 개별 선택의 배타 규칙은 RegionSelection이
  // 담당한다. 형식: "{시/도}"(= 시/도 전체) 또는 "{시/도} {구/시/군}".
  // 지역 데이터는 lib/models/region_data.dart(RegionData)에서 공유 관리.
  Set<String> get _placeRegions => _placeFilter.regions;

  // ── 데스크톱 3단 레이아웃 전용: 우측 미리보기 패널 선택 상태 ──────────
  // 모바일/태블릿에서는 전혀 참조되지 않는다(카드 클릭 시 바로 상세화면으로 이동).
  String? _previewType; // 'party' | 'place' | 'shop'
  String? _previewDocId;
  Map<String, dynamic>? _previewData;

  void _selectPreview(String type, String docId, Map<String, dynamic> data) {
    setState(() {
      _previewType = type;
      _previewDocId = docId;
      _previewData = data;
    });
  }

  void _clearPreview() {
    _previewType = null;
    _previewDocId = null;
    _previewData = null;
  }

  // 웹에서 랜딩페이지(website/index.html)의 "파티 찾기"/"공간 등록" 버튼이
  // /app/?tab=place 처럼 쿼리스트링으로 원하는 탭을 지정해 진입할 수 있게
  // 한다 — 앱 자체의 라우팅 구조를 새로 만들지 않고, 시작 시 한 번만 초기
  // 탭 인덱스를 정하는 데만 쓴다(DeepLinkService의 파티 상세 딥링크와 같은
  // "웹 시작 시 Uri.base 한 번만 확인" 패턴).
  int _initialTopTabIndexFromWebUrl() {
    if (!kIsWeb) return 0;
    // Uri.base가 아니라 **앱이 처음 열린 주소**를 본다 — 이 시점의 Uri.base는
    // Flutter가 이미 `/app/`로 덮어써서 쿼리가 비어 있다([WebLaunchUrl]).
    switch (WebLaunchUrl.param('tab')) {
      // 'party'는 어차피 기본값이지만 **명시적으로 둔다** — 홈페이지의 "파티
      // 찾기"가 /app/?tab=party 로 들어오는데, 이름이 여기 없으면 나중에
      // 기본값을 바꿀 때 그 링크가 조용히 딴 데로 간다.
      case 'party':
        return 0;
      case 'venue':
        return 1;
      case 'place':
        return 2;
      case 'crew':
        return 3;
      default:
        return 0;
    }
  }

  /// 랜딩페이지(website/index.html)의 "등록하기"가 `/app/?register=1`로
  /// 들어왔는가.
  ///
  /// 여기서 하는 일은 **하단탭 '등록'을 대신 눌러주는 것뿐**이다 — 로그인
  /// 확인 → 호스트 안내 시트 → 등록 종류 선택으로 이어지는 경로는 앱과 완전히
  /// 같다. 웹 전용 등록 흐름을 따로 만들지 않는다는 뜻이다.
  bool get _webWantsRegister {
    if (!kIsWeb) return false;
    return WebLaunchUrl.param('register') == '1' ||
        WebLaunchUrl.param('tab') == 'register';
  }

  /// 홈페이지의 "마이페이지"가 `/app/?mypage=1`(= `?tab=mypage`)로 들어왔는가.
  ///
  /// [_webWantsRegister]와 완전히 같은 방식이다 — 하단탭 '마이'를 대신
  /// 눌러줄 뿐이라, 로그인 확인·본인확인 게이트·화면 전환이 앱과 한 글자도
  /// 다르지 않다. 웹 전용 마이페이지 경로를 따로 만들지 않는다.
  bool get _webWantsMyPage {
    if (!kIsWeb) return false;
    return WebLaunchUrl.param('mypage') == '1' ||
        WebLaunchUrl.param('tab') == 'mypage';
  }

  /// 홈페이지의 "로그인"이 `/app/?login=1`(= `?tab=login`)로 들어왔는가.
  ///
  /// 홈페이지는 정적 HTML이라 **지금 로그인돼 있는지 알 수 없다.** 그래서
  /// 버튼 하나로 두 경우를 다 받는다 — 비로그인이면 로그인 화면이 먼저 뜨고,
  /// 이미 로그인한 회원에게는 곧바로 마이페이지가 열린다. 로그인한 사람에게
  /// 로그인 화면을 다시 보여주는 막다른 길을 만들지 않으려는 것이다.
  bool get _webWantsLogin {
    if (!kIsWeb) return false;
    return WebLaunchUrl.param('login') == '1' ||
        WebLaunchUrl.param('tab') == 'login';
  }

  /// `?register=1` · `?mypage=1` · `?login=1`로 들어온 진입을 실제 화면으로
  /// 이어준다.
  ///
  /// 셋 다 결국 [_onBottomNavTap]을 부른다 — 홈페이지에서 들어온 사람과 앱에서
  /// 하단탭을 누른 사람이 **완전히 같은 코드**를 지나게 하려는 것이다. 로그인
  /// 요구도, 본인확인 게이트도, 등록 안내 시트도 여기서 다시 만들지 않는다.
  Future<void> _openWebLaunchTarget() {
    if (_webWantsRegister) return _onBottomNavTap(2);
    // 로그인·마이페이지가 같은 자리로 간다: 하단탭 '마이'는 비로그인이면
    // 로그인 화면부터 띄우고(_requireLogin), 로그인 상태면 마이페이지를 연다.
    if (_webWantsMyPage || _webWantsLogin) return _onBottomNavTap(4);
    return Future<void>.value();
  }

  // ── 수명주기 ──────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    // 🎉 With파티 색인 — 파티가 붙었다 떨어졌다 하는 것을 실시간으로 따라간다.
    // 집합이 실제로 달라졌을 때만 다시 그린다(파티 문서는 신청·조회수 등으로
    // 자주 바뀌는데, 그때마다 플레이스 목록을 다시 그릴 이유가 없다).
    _withPartySub = ListingSources.parties().snapshots().listen(
      (snap) {
        if (!mounted) return;
        final next = PlacePartyIndex.fromSnapshot(snap.docs);
        if (next.sameAs(_withPartyIndex)) return;
        setState(() => _withPartyIndex = next);
      },
      onError: (Object e, StackTrace s) =>
          logFirestoreStreamError('WithPartyIndex', e, s),
    );
    _topTabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: _initialTopTabIndexFromWebUrl(),
    );
    // 탭을 바꾸면 이전 탭에서 선택했던 미리보기(데스크톱 전용)는 더 이상
    // 유효하지 않으므로 함께 초기화한다.
    _topTabController.addListener(() => setState(_clearPreview));
    // 파티/장소대여/파티샵/파티크루 등록 화면이 등록을 완료하고 이 화면
    // 루트까지 돌아왔을 때, 방금 등록한 종류의 탭으로 바로 전환한다.
    pendingTopTabAfterRegister.addListener(_onPendingTopTabAfterRegister);

    _coachMarkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _coachMarkAnim = CurvedAnimation(
      parent: _coachMarkCtrl,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _checkFirstVisit();

    // 사전등록 기간 안내 — 업데이트 안내가 끝난 뒤, 실행당 한 번, '오늘은
    // 그만 보기'면 그날은 건너뛴다(조건은 PreRegistrationNotice 안에 있다).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(PreRegistrationNotice.maybeShow(context));
    });

    // 랜딩페이지에서 "등록하기"로 들어온 경우 — 첫 프레임 뒤에 하단탭 '등록'과
    // 같은 경로를 태운다(트리가 만들어지기 전에는 Navigator를 쓸 수 없다).
    if (_webWantsRegister || _webWantsMyPage || _webWantsLogin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openWebLaunchTarget());
      });
    }
    // 이 화면은 본인확인을 확인하지 않는다 — **이미 지나온 관문**이기 때문이다.
    //
    // 로그인한 사용자가 여기 서 있다는 것 자체가 본인확인을 마쳤다는 뜻이다
    // (미인증 계정에게는 루트 게이트가 MainScreen을 만들지 않는다 —
    // utils/root_gate.dart). 비로그인 사용자에게는 예전처럼 홈과 콘텐츠 탐색이
    // 열려 있고, 회원 기능을 누르면 [_requireLogin]이 로그인을 요구한다.
    //
    // (예전 주석은 "미인증 사용자에게도 홈이 열려 있어야 한다"였다. 그 정책은
    //  비로그인 사용자에게만 남았다 — 로그인한 회원은 본인확인이 전제다.)

    PartyViewMode.load().then((mode) {
      if (!mounted) return;
      if (mode == PartyViewMode.video) {
        // 영상 모드는 목록에 인라인으로 그리지 않으므로, 목록 자체는 기본
        // 카드로 두고 파티 문서가 로드되는 즉시 전체화면을 한 번만 띄운다.
        setState(() {
          _applyViewMode(PartyViewMode.standard);
          _pendingAutoOpenVideoFeed = true;
        });
      } else {
        setState(() => _applyViewMode(mode));
      }
    });

    PlaceViewMode.load().then((mode) {
      if (!mounted) return;
      if (mode == PlaceViewMode.large) {
        // 파티 영상 모드와 동일 — 큰 카드는 목록에 인라인으로 그리지 않으므로
        // 목록 자체는 기본 카드로 두고, 문서가 로드되는 즉시 전체화면을
        // 한 번만 띄운다.
        setState(() {
          _placeViewMode = PlaceViewMode.standard;
          _pendingAutoOpenPlaceFeed = true;
        });
      } else {
        setState(() => _setPlaceViewMode(mode));
      }
    });

    // 파티샵은 큰 카드도 목록 안에서 그리므로 값을 그대로 되살린다.
    ShopViewModePrefs.loadForShop().then((mode) {
      if (!mounted) return;
      setState(() => _shopViewMode = mode);
    });

    _partyScrollCtrl.addListener(_onPartyScroll);
    // 달력 점 표시용 파티 날짜 수집
    _partyDatesSub = FirebaseFirestore.instance
        .collection('parties')
        .snapshots()
        .listen((snapshot) {
          // 정기 파티는 한 게시글이 여러 날짜에 점을 찍는다(앞으로 약 4개월치).
          // 날짜 미정으로 사전등록된 오픈예정 파티는 찍을 날짜가 없으므로
          // 달력에서 제외한다.
          final dates = snapshot.docs
              .where((doc) => !PartyOpenState.isDateTbd(doc.data()))
              // 사전등록 비공개 콘텐츠는 날짜 점도 찍지 않는다.
              .where((doc) => !PreRegistrationVisibility.isHidden(doc.data()))
              .expand((doc) => PartySchedule.occurrenceDays(doc.data()))
              .toSet();
          if (mounted) setState(() => _partyDates = dates);
        });
  }

  @override
  void dispose() {
    pendingTopTabAfterRegister.removeListener(_onPendingTopTabAfterRegister);
    _topTabController.dispose();
    _coachMarkCtrl.dispose();
    _partyScrollCtrl.dispose();
    _partyDatesSub.cancel();
    _withPartySub?.cancel();
    _placeEventSub?.cancel();
    _rentalEventSub?.cancel();
    _searchController.dispose();
    _eventSearch.dispose();
    _placeSearch.dispose();
    _shopSearch.dispose();
    _crewSearch.dispose();
    super.dispose();
  }

  // 등록 화면이 "이 탭으로 돌아가줘"라고 남긴 신호를 소비해 상단 탭(파티/
  // 장소대여/파티크루)과 하단 네비게이션(홈)을 함께 전환한다. 파티샵은
  // 더 이상 별도 탭이 아니라 플레이스 탭(인덱스 1) 안의 카테고리라서,
  // pendingPlaceShopCategoryAfterRegister가 함께 켜져 있으면 파티샵
  // 카테고리 상태로도 같이 전환한다.
  void _onPendingTopTabAfterRegister() {
    final tabIndex = pendingTopTabAfterRegister.value;
    if (tabIndex == null) return;
    pendingTopTabAfterRegister.value = null; // 한 번만 소비
    final showShopCategory = pendingPlaceShopCategoryAfterRegister.value;
    pendingPlaceShopCategoryAfterRegister.value = false; // 한 번만 소비
    if (!mounted) return;
    setState(() {
      _currentIndex = 0;
      _placeShowShopCategory = tabIndex == 1 && showShopCategory;
      _topTabController.animateTo(tabIndex);
    });
  }

  // ── 코치마크: 첫 진입 여부 확인 ──────────────────────────────────
  Future<void> _checkFirstVisit() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('swipe_coach_dismissed') ?? false) return;
    if (!mounted) return;
    setState(() => _showCoachMark = true);
    _coachMarkCtrl.forward();
  }

  Future<void> _dismissCoachMark({bool permanent = false}) async {
    if (!_showCoachMark) return;
    await _coachMarkCtrl.reverse();
    if (!mounted) return;
    setState(() => _showCoachMark = false);
    if (permanent) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('swipe_coach_dismissed', true);
    }
  }

  void _onPartyScroll() {
    final collapsed = _partyScrollCtrl.offset > 8;
    if (collapsed != _headerCollapsed) {
      setState(() => _headerCollapsed = collapsed);
    }
  }

  // ── 내비게이션 ────────────────────────────────────────────────────
  /// 하단 '등록' 탭 — 등록 유형 화면으로 가기 **전에** 호스트 안내를 한 번
  /// 보여준다([HostRegisterInviteSheet]).
  ///
  /// 이 안내가 뜨는 자리는 여기 하나뿐이다. 등록 유형 화면·이벤트/파티 선택·
  /// 플레이스 등록·수정 화면은 각자 Navigator.push로 들어가므로 이 함수를
  /// 거치지 않는다 — 이미 등록 과정 안에 있는 사람에게 같은 안내가 다시 뜨지
  /// 않는다.
  ///
  /// 시트를 그냥 닫으면 아무 데도 가지 않는다. 시트는 묻기만 하고, 그 뒤 등록
  /// 흐름은 예전과 **한 줄도 다르지 않다**.
  Future<void> _goToRegisterScreen() async {
    final start = await HostRegisterInviteSheet.show(context);
    if (!start || !mounted) return;
    await Navigator.push(
      context,
      webFramedRoute((_) => const RegisterTypeScreen()),
    );
  }

  /// 회원 전용 기능(등록·채팅·마이) 진입 조건 — **로그인 하나뿐**이다.
  ///
  /// 본인확인 화면을 여기서 띄우지 않는 이유: 이 화면(MainScreen)에 서 있는
  /// 로그인 사용자는 이미 본인확인을 마친 사람뿐이다. 미인증 계정에게는 루트
  /// 게이트가 MainScreen 자체를 만들어 주지 않는다(utils/root_gate.dart).
  /// 그러니 버튼마다 확인을 한 번 더 붙이면 정상 사용자에게 이유 없는 화면을
  /// 하나 더 보여주는 일이 된다.
  ///
  /// 다만 **로그인 직후**는 예외적인 한순간이다 — 방금 로그인한 계정이
  /// 미인증이면 루트 게이트가 바로 화면을 갈아끼운다. 그 위로 등록 화면을
  /// 밀어 넣지 않도록, 로그인 뒤에는 세션 상태까지 확인하고 넘긴다(여기서
  /// 새 화면을 띄우지는 않는다 — 게이트가 이미 띄웠다).
  Future<bool> _requireLogin() async {
    if (UserSession.userId.isEmpty) {
      await Navigator.push(context, webFramedRoute((_) => LoginPage()));
      if (!mounted) return false;
      if (UserSession.userId.isEmpty) return false;
    }
    // 루트 게이트와 같은 기준 — 소셜 로그인 테스트 모드(Android Debug)에서는
    // 미인증 계정도 마이 탭(로그아웃)에 들어갈 수 있어야 한다(root_gate.dart).
    return identityRequirementMet(UserSession.identityStatus);
  }

  Future<void> _onBottomNavTap(int index) async {
    setState(() => _currentIndex = index);
    if (index == 1) {
      // 지도 화면은 MainScreen 위에 새 라우트로 쌓일 뿐 이 화면은 dispose되지
      // 않는다 — 화면 전환 중엔 카드의 VisibilityDetector가 곧바로 "화면 밖"을
      // 감지하지 못해 재생 중이던 동영상 소리가 새어나갈 수 있으므로, 이동
      // 직전에 명시적으로 일시정지한다. 지도 화면 자체는 별도 동영상이 없어
      // 이걸로 "지도에서는 소리 없음"까지 함께 보장된다. 메인으로 돌아오면
      // 기존 가시성 기반 자동재생이 다시 감지해 이어서 재생한다.
      FeedVideoManager.instance.pauseActive();
      Navigator.push(
        context,
        webFramedRoute((_) => const MapScreen()),
      ).then((_) => setState(() => _currentIndex = 0));
    } else if (index == 2) {
      final ok = await _requireLogin();
      if (!mounted) return;
      setState(() => _currentIndex = 0);
      if (ok) {
        _goToRegisterScreen().then((_) => setState(() => _currentIndex = 0));
      }
    } else if (index == 3) {
      final ok = await _requireLogin();
      if (!mounted) return;
      setState(() => _currentIndex = 0);
      if (ok) {
        // 대화 목록이 아니라 **진행 중인 신청·예약 목록**이 먼저다 —
        // 방이 아직 없는 사람도 여기서 호스트에게 말을 걸 수 있어야 한다
        // (chat_target_list_screen.dart 상단 주석 참고).
        Navigator.push(
          context,
          webFramedRoute((_) => const ChatTargetListScreen()),
        ).then((_) => setState(() => _currentIndex = 0));
      }
    } else if (index == 4) {
      final ok = await _requireLogin();
      if (!mounted) return;
      setState(() => _currentIndex = 0);
      if (ok) {
        Navigator.push(
          context,
          webFramedRoute((_) => const MyPageScreen()),
        ).then((_) => setState(() => _currentIndex = 0));
      }
    }
  }

  // ── 보기 방식(작은 카드/기본 카드/영상 크게 보기) ──────────────────
  // 영상 크게 보기를 고르면 목록에 인라인으로 그리지 않고 곧바로 전체화면
  // 피드(PartyVideoFeedScreen)로 진입한다 — 그래서 이 목록 화면의 _viewMode는
  // 절대 video가 되지 않는다(항상 작은/기본 카드 중 하나).
  //
  // 예전에는 헤더 아이콘 하나로 시트를 열어 고르게 했지만, 플레이스처럼 세
  // 방식을 **헤더에 그대로 펼쳐** 한 번에 고르게 바꿨다(고르는 로직은 그대로).
  void _selectPartyViewMode(
    PartyViewMode mode,
    List<QueryDocumentSnapshot> docs,
  ) {
    if (mode == _viewMode) return;
    unawaited(mode.save());
    if (mode == PartyViewMode.video) {
      if (docs.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('표시할 파티가 없어요.')));
        return;
      }
      _openVideoFullscreen(docs, 0);
      return;
    }
    setState(() => _applyViewMode(mode));
  }

  void _applyViewMode(PartyViewMode mode) {
    _viewMode = mode;
  }

  // 헤더의 트리거 아이콘과 BottomSheet의 아이콘이 어긋나지 않도록 같은
  // 매핑(partyViewModeIcon)을 공유한다.
  static IconData _viewModeIcon(PartyViewMode mode) => partyViewModeIcon(mode);

  // ── 검색 진입(네 탭 공통) ────────────────────────────────────────────
  // 목록 위에는 돋보기 하나만 두고, 그 돋보기가 여는 시트도 **하나뿐**이다.
  // 검색어 입력창과 그 탭의 상세검색 항목(지역·날짜·업종·가격 …)이 같은
  // 시트 안에 위아래로 놓인다 — 예전처럼 "상세검색 >"를 눌러 시트를 한 번 더
  // 띄우지 않는다(팝업 위에 팝업이라 뒤로가기가 두 번 필요했다).
  //
  // 그래서 이 함수는 "검색어 설정([SearchEntryConfig])을 얹어" 각 탭이
  // 예전부터 쓰던 상세검색 시트를 여는 것이 전부다(_openDetailSearch). 새
  // 검색/필터 로직은 하나도 만들지 않는다 — 조건 UI도, 검색어 상태와 목록을
  // 거르는 로직(_matchesSearch/_matchesTextQuery, _applyXxxFilter)도 전부 기존
  // 것이다.
  Future<void> _openSearchSheet() {
    switch (_topTabController.index) {
      case 1:
        // 플레이스 탭 안의 "파티샵" 카테고리는 다른 컬렉션이라 검색어도
        // 상세검색도 파티샵 전용 상태를 쓴다(_openDetailSearch와 같은 분기).
        if (_placeShowShopCategory) {
          return _openDetailSearch(
            search: _tabSearchConfig(
              title: '파티샵 검색',
              hintText: '샵 이름, 카테고리, 키워드 검색',
              tabSearch: _shopSearch,
            ),
          );
        }
        return _openDetailSearch(
          search: _tabSearchConfig(
            title: '플레이스 검색',
            hintText: '가게 이름, 지역, 키워드 검색',
            tabSearch: _eventSearch,
          ),
        );
      case 2:
        return _openDetailSearch(
          search: _tabSearchConfig(
            title: '장소대여 검색',
            hintText: '장소 이름, 지역, 키워드 검색',
            tabSearch: _placeSearch,
          ),
        );
      case 3:
        return _openDetailSearch(
          search: _tabSearchConfig(
            title: '파트너 검색',
            hintText: '제목, 역할, 지역 검색',
            tabSearch: _crewSearch,
          ),
        );
      default:
        return _openDetailSearch(
          search: SearchEntryConfig(
            title: '파티 검색',
            // 태그도 이 한 칸에서 함께 찾는다(상세검색의 '태그' 카드를
            // 없애고 여기로 합쳤다) — 찾을 수 있는 것을 힌트에 밝힌다.
            hintText: '파티 제목, 장소, 태그, 키워드 검색',
            controller: _searchController,
            onQueryChanged: (v) => setState(() => _searchQuery = v),
          ),
        );
    }
  }

  /// 파티 외 탭 — 검색어 상태만 [_TabSearch]로 묶여 있을 뿐, 넘기는 값의
  /// 모양은 파티와 완전히 같다.
  SearchEntryConfig _tabSearchConfig({
    required String title,
    required String hintText,
    required _TabSearch tabSearch,
  }) {
    return SearchEntryConfig(
      title: title,
      hintText: hintText,
      controller: tabSearch.controller,
      onQueryChanged: (v) => setState(() => tabSearch.query = v),
    );
  }

  /// 큰 카드 전체화면 피드의 돋보기 — 목록과 **같은 검색 시트**를 열고,
  /// 검색어나 상세검색 조건이 실제로 바뀌었으면 true를 돌려준다. 전체화면은
  /// 그 값을 보고 자기를 닫고, 목록 화면이 새로 걸러진 목록으로 전체화면을
  /// 다시 띄운다(_pendingAutoOpen…). 전체화면 전용 검색 UI는 없다.
  Future<bool> _openSearchSheetFromFeed() async {
    final beforeQuery = _currentTabQuery;
    final beforeFilter = _currentTabFilter;
    await _openSearchSheet();
    if (!mounted) return false;
    return _currentTabQuery != beforeQuery ||
        !identical(_currentTabFilter, beforeFilter);
  }

  /// 지금 탭의 검색어와 상세검색 필터 — 전체화면에서 "바뀌었는지" 판정에만
  /// 쓴다. 필터는 적용할 때마다 새 객체로 갈아끼우므로 참조 비교로 충분하다.
  String get _currentTabQuery => switch (_topTabController.index) {
    1 => _placeShowShopCategory ? _shopSearch.query : _eventSearch.query,
    2 => _placeSearch.query,
    3 => _crewSearch.query,
    _ => _searchQuery,
  };

  Object get _currentTabFilter => switch (_topTabController.index) {
    1 => _placeShowShopCategory ? _shopFilter : _eventFilter,
    2 => _placeFilter,
    3 => _crewFilter,
    _ => _filter,
  };

  /// 지금 탭에 검색어나 상세검색 조건이 걸려 있는지 — 돋보기 아이콘에 작은
  /// 점을 찍을지 판단한다(상세검색 아이콘이 사라진 뒤에도 "조건이 걸려
  /// 있다"는 사실이 헤더에서 그대로 보이게 하기 위함).
  bool get _partySearchActive => _searchQuery.isNotEmpty || _filter.isActive;
  bool get _eventSearchActive =>
      _eventSearch.query.isNotEmpty || _eventFilter.isActive;
  bool get _shopSearchActive =>
      _shopSearch.query.isNotEmpty || _shopFilter.isActive;
  bool get _placeSearchActive =>
      _placeSearch.query.isNotEmpty || _placeFilter.isActive;
  bool get _crewSearchActive =>
      _crewSearch.query.isNotEmpty || _crewFilter.isActive;

  // ── 정렬 ─────────────────────────────────────────────────────────
  // 정렬 선택 UI는 날짜 필터 바의 정렬 버튼(_openSortSheet) 하나이고, 여기서는
  // 고른 sortMode가 거리순이면 위치 권한/좌표만 확보한다(실패하면 호출부가
  // 기본순으로 되돌린다).
  Future<bool> _resolveDistanceSort() async {
    final pos = await _requestCurrentPosition();
    if (pos == null) return false;
    _currentPosition = pos;
    return true;
  }

  /// 현재 위치 한 번 얻기 — 권한 요청과 실패 안내까지. 못 얻으면 null이고,
  /// 부른 쪽은 기본순으로 되돌린다.
  ///
  /// 파티 거리순([_resolveDistanceSort])과 장소대여 거리순
  /// ([_resolvePlaceDistanceSort])이 **같은 절차·같은 안내 문구**를 쓰도록
  /// 한 곳에 모아 둔다. 담아 두는 자리만 서로 다르다(한쪽 정렬을 껐다고
  /// 다른 쪽 기준점이 사라지면 안 되기 때문).
  Future<Position?> _requestCurrentPosition() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (!mounted) return null;
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('위치 권한이 없어 기본순을 유지합니다.')));
      return null;
    }
    try {
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return null;
      return pos;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('위치를 가져올 수 없어 기본순을 유지합니다.')),
        );
      }
      return null;
    }
  }

  Future<bool> _resolvePlaceDistanceSort() async {
    final pos = await _requestCurrentPosition();
    if (pos == null) return false;
    _placeSortPosition = pos;
    return true;
  }

  /// 혜택 가중치를 줄 수 있는 파티인지 — **아직 모집 중인 것만** 앞으로
  /// 당긴다. 이미 마감/종료된 파티는 혜택이 있어도 순위가 올라가지 않는다
  /// (기존 "마감 여부·참여 가능 여부" 순서를 그대로 지키기 위함).
  static bool _perkBoostable(Map<String, dynamic> d) =>
      PartyCard.effectiveStatusFor(d, UserSession.gender) == '모집중';

  List<QueryDocumentSnapshot> _applySortMode(List<QueryDocumentSnapshot> docs) {
    // 정렬 모드가 무엇이든 "같은 노출 그룹 안에서만" 혜택 게시물을 앞으로
    // 당긴다(PartychuPerkRanking 참고). 그룹이 다르면 기존 정렬이 그대로
    // 이기므로 날짜순·요금순 같은 큰 구조는 바뀌지 않는다.
    Map<String, dynamic> d(QueryDocumentSnapshot s) =>
        s.data() as Map<String, dynamic>;

    switch (_filter.sortMode) {
      case PartySortMode.defaultOrder:
        // 예전에는 위에서 createdAt 최신순으로 정렬된 목록을 그대로 돌려줬다.
        // 이제 같은 "등록 날짜" 안에서만 혜택 게시물이 앞선다.
        return List.of(docs)..sort(
          (a, b) => PartychuPerkRanking.compareNewestFirst(
            d(a),
            d(b),
            boostable: _perkBoostable,
          ),
        );
      case PartySortMode.distance:
        if (_currentPosition == null) return docs;
        final pos = _currentPosition!;
        double distOf(Map<String, dynamic> m) => _dist(
          pos.latitude,
          pos.longitude,
          (m['latitude'] as num?)?.toDouble() ?? 0,
          (m['longitude'] as num?)?.toDouble() ?? 0,
        );
        return List.of(docs)..sort(
          (a, b) => PartychuPerkRanking.compare(
            d(a),
            d(b),
            // 같은 거리대(1km 단위) 안에서만 혜택이 앞선다.
            group: (x, y) => PartychuPerkRanking.distanceBucket(
              distOf(x),
            ).compareTo(PartychuPerkRanking.distanceBucket(distOf(y))),
            within: (x, y) => distOf(x).compareTo(distOf(y)),
            boostable: _perkBoostable,
          ),
        );
      case PartySortMode.deadlineSoon:
        final now = DateTime.now();
        return List.of(docs)..sort((a, b) {
          final ad = d(a);
          final bd = d(b);
          // 정기 파티는 저장된 고정 마감이 없다 — 다음 회차의 마감으로 센다.
          final aDl = PartyCard.recruitDeadlineAt(ad);
          final bDl = PartyCard.recruitDeadlineAt(bd);
          // 마감된 것은 맨 뒤 — 혜택보다 먼저 판정해서 순서를 지킨다.
          final aExpired = aDl != null && aDl.isBefore(now);
          final bExpired = bDl != null && bDl.isBefore(now);
          if (aExpired != bExpired) return aExpired ? 1 : -1;
          // 마감 시간 없는 것은 맨 뒤
          if (aDl == null && bDl == null) {
            return PartychuPerkRanking.rank(ad, boostable: _perkBoostable) -
                PartychuPerkRanking.rank(bd, boostable: _perkBoostable);
          }
          if (aDl == null) return 1;
          if (bDl == null) return -1;
          // 같은 "마감 날짜" 안에서만 혜택이 앞선다 — 마감일이 다르면
          // 임박한 쪽이 언제나 먼저다.
          final dayDiff = PartychuPerkRanking.dayKeyOf(
            aDl,
          ).compareTo(PartychuPerkRanking.dayKeyOf(bDl));
          if (dayDiff != 0) return dayDiff;
          final perkDiff =
              PartychuPerkRanking.rank(ad, boostable: _perkBoostable) -
              PartychuPerkRanking.rank(bd, boostable: _perkBoostable);
          if (perkDiff != 0) return perkDiff;
          return aDl.compareTo(bDl);
        });
      case PartySortMode.feeLow:
        return List.of(docs)..sort(
          (a, b) => PartychuPerkRanking.compare(
            d(a),
            d(b),
            // 같은 참가비 금액 안에서만 혜택이 앞선다.
            group: (x, y) => _minFee(x).compareTo(_minFee(y)),
            boostable: _perkBoostable,
          ),
        );
      case PartySortMode.feeHigh:
        return List.of(docs)..sort(
          (a, b) => PartychuPerkRanking.compare(
            d(a),
            d(b),
            group: (x, y) => _maxFee(y).compareTo(_maxFee(x)),
            boostable: _perkBoostable,
          ),
        );
      case PartySortMode.capacityLow:
        return List.of(docs)..sort(
          (a, b) => PartychuPerkRanking.compare(
            d(a),
            d(b),
            group: (x, y) => _capacity(x).compareTo(_capacity(y)),
            boostable: _perkBoostable,
          ),
        );
      case PartySortMode.capacityHigh:
        return List.of(docs)..sort(
          (a, b) => PartychuPerkRanking.compare(
            d(a),
            d(b),
            group: (x, y) => _capacity(y).compareTo(_capacity(x)),
            boostable: _perkBoostable,
          ),
        );
    }
  }

  // 직선거리는 공용 유틸 하나만 쓴다 — 상세 화면의 "내 위치에서 N km"와 같은
  // 계산이라 여기에 따로 두면 두 수치가 어긋날 수 있다.
  static double _dist(double lat1, double lng1, double lat2, double lng2) =>
      distanceMetersBetween(lat1, lng1, lat2, lng2);

  // 참가비는 pricingType(무료/같은 금액/남녀 다름)을 아는 공통 모델로 읽는다 —
  // 예전 문서의 maleFee/femaleFee/fee/price도 같은 모델이 흡수한다.
  static int _minFee(Map<String, dynamic> p) =>
      PartyPricing.fromMap(p).displayPrice;

  static int _maxFee(Map<String, dynamic> p) =>
      PartyPricing.fromMap(p).maxPrice;

  static int _capacity(Map<String, dynamic> p) =>
      (p['maxParticipants'] as num?)?.toInt() ??
      (p['maxCapacity'] as num?)?.toInt() ??
      0;

  // 탭별 상세검색 진입점 — 파티는 기존 구조 그대로, 나머지는 서비스 전용 화면으로 분리.
  //
  // [search]가 주어지면(= 목록 헤더의 돋보기로 들어온 경우) 같은 시트가 검색어
  // 입력창까지 얹은 **검색 시트**로 열린다. 지도 화면과 태블릿 좌측 필터
  // 패널은 예전처럼 상세검색만 열므로 null이다 — 어느 쪽이든 조건 UI와 필터
  // 로직은 완전히 같은 시트 하나를 쓴다.
  //
  // "검색"(=적용)을 눌러 조건이 반영됐으면 true를 돌려준다. 큰 카드 전체화면이
  // 이 값을 보고 자기를 닫고 새로 걸러진 목록으로 다시 연다.
  Future<bool> _openDetailSearch({SearchEntryConfig? search}) async {
    // 시트가 열려 있는 동안 뒤에서 동영상 소리가 계속 새어나오지 않도록,
    // 시트를 열기 전에 재생 중인 동영상을 즉시 일시정지한다.
    FeedVideoManager.instance.pauseActive();
    switch (_topTabController.index) {
      case 1:
        // 플레이스 탭 안의 "파티샵" 카테고리는 파티샵 전용 시트를 쓰고,
        // 그 밖에는 플레이스 전용 상세검색을 연다.
        return _placeShowShopCategory
            ? _openShopDetailSearch(search: search)
            : _openEventDetailSearch(search: search);
      case 2:
        return _openPlaceDetailSearch(search: search);
      case 3:
        return _openCrewDetailSearch(search: search);
      default:
        return _openPartyDetailSearch(search: search);
    }
  }

  Future<bool> _openPartyDetailSearch({SearchEntryConfig? search}) async {
    final result = await showModalBottomSheet<PartyFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DetailSearchSheet(
        initialFilter: _filter,
        partyDates: _partyDates,
        search: search,
        // 검색 시트의 "전체 초기화"는 검색어와 함께 이미 적용된 조건까지
        // 그 자리에서 푼다 — 시트가 만든 빈 필터를 "검색"으로 받을 때와
        // 똑같은 자리에 꽂기만 한다.
        onFilterReset: search == null
            ? null
            : (reset) => setState(() => _filter = reset),
      ),
    );
    if (result == null) return false;
    // 정렬은 이 시트에서 다루지 않는다(정렬 버튼 하나로 통일) — 시트가 돌려준
    // 필터의 sortMode는 열 때 넘겨준 값 그대로라, 거리순 위치 권한 처리도
    // 여기서 다시 할 일이 없다.
    if (!mounted) return false;
    setState(() => _filter = result);
    return true;
  }

  // 날짜 필터 바 오른쪽 끝의 정렬 버튼 — 목록 정렬을 고르는 **유일한**
  // 입구다(검색 조건이 아니라 목록 정렬이라 검색 시트로 옮기지 않았다).
  // 거리순은 위치 권한을 먼저 확보하고, 실패하면 기본순으로 되돌린다.
  Future<void> _openSortSheet() async {
    final result = await showModalBottomSheet<PartySortMode>(
      context: context,
      // 옵션이 많아 기본 높이(화면의 9/16)로는 마지막 줄이 잘린다 —
      // 높이는 시트가 스스로 잡고([ListSortSheet]) 넘치면 그 안에서
      // 스크롤된다.
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PartySortSheet(current: _filter.sortMode),
    );
    if (result == null || !mounted) return;
    var mode = result;
    if (mode == PartySortMode.distance) {
      final ok = await _resolveDistanceSort();
      if (!ok) mode = PartySortMode.defaultOrder;
    } else {
      _currentPosition = null;
    }
    if (!mounted) return;
    setState(() => _filter.sortMode = mode);
  }

  /// 장소대여 목록 헤더의 정렬 버튼 — 파티와 **같은 시트 위젯**
  /// ([ListSortSheet])을 열고, 거리순이면 위치 권한을 먼저 확보한 뒤
  /// 실패하면 기본순으로 되돌린다(파티 [_openSortSheet]와 같은 흐름).
  ///
  /// 금액순 네 가지만 예외적으로 **대상까지 한정한다** — ₩/박과 ₩/시간은
  /// 비교할 수 없어 고른 단위의 장소만 남긴다([_applyPlaceSort]). 그 밖의
  /// 정렬은 이미 걸러진 목록의 순서만 바꾼다.
  Future<void> _openPlaceSortSheet() async {
    final result = await showModalBottomSheet<PlaceSortMode>(
      context: context,
      // 단위별 금액순까지 더해져 옵션이 아홉 줄이다 — 기본 높이로는
      // 마지막 줄이 잘려 'BOTTOM OVERFLOWED'가 났다.
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PlaceSortSheet(current: _placeSortMode),
    );
    if (result == null || !mounted) return;
    var mode = result;
    if (mode == PlaceSortMode.distance) {
      final ok = await _resolvePlaceDistanceSort();
      if (!ok) mode = PlaceSortMode.defaultOrder;
    } else {
      _placeSortPosition = null;
    }
    if (!mounted) return;
    setState(() => _placeSortMode = mode);
  }

  /// 걸러진 장소 목록에 고른 정렬을 입힌다.
  ///
  /// 들어오는 목록은 이미 앱의 기존 기본 순서(등록 최신순 + 같은 날짜 안에서
  /// 파티츄 혜택 우선)로 정렬돼 있다. 그래서 기본순은 비교자가 null이고
  /// 목록을 **그대로** 돌려준다 — 정렬 기능이 붙기 전과 완전히 같은 순서다.
  ///
  /// **금액순 네 가지만 대상을 한정한다**([placeSortIncludes]) — ₩/박과
  /// ₩/시간은 환산할 수 없는 값이라, 고른 단위의 장소만 남기고 다른 단위를
  /// 숫자로 섞어 뒤에 붙이지 않는다. 상세검색 조건과는 **AND**다: 숙박형만
  /// 걸러 둔 상태에서 시간당 정렬을 고르면 결과가 0개일 수 있고, 그때도
  /// 걸어 둔 필터를 여기서 몰래 풀지 않는다(빈 목록 문구가 이유를 밝힌다).
  List<QueryDocumentSnapshot> _applyPlaceSort(
    List<QueryDocumentSnapshot> docs,
  ) {
    final mode = _placeSortMode;
    final scoped = mode.limitsToUnit
        ? docs
              .where(
                (d) =>
                    placeSortIncludes(mode, d.data() as Map<String, dynamic>),
              )
              .toList()
        : docs;
    final pos = _placeSortPosition;
    final compare = placeSortComparator(
      mode,
      origin: pos == null ? null : (lat: pos.latitude, lng: pos.longitude),
    );
    if (compare == null) return scoped;
    return List.of(scoped)..sort(
      (a, b) => compare(
        a.data() as Map<String, dynamic>,
        b.data() as Map<String, dynamic>,
      ),
    );
  }

  Future<bool> _openPlaceDetailSearch({SearchEntryConfig? search}) async {
    final result = await showModalBottomSheet<PlaceFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PlaceDetailSearchSheet(
        initialFilter: _placeFilter,
        customAmenityEntries: CustomAmenities.catalogOf(_placeAmenityScope),
        search: search,
        onFilterReset: search == null
            ? null
            : (reset) => setState(() => _placeFilter = reset),
      ),
    );
    if (result == null || !mounted) return false;
    setState(() => _placeFilter = result);
    return true;
  }

  // ── 큰 카드 전체화면의 "상세검색" 진입점 ────────────────────────────────
  // 전체화면([PlaceFeedScreen])은 파티와 같은 자리에 버튼만 얹고, 실제로 여는
  // 시트는 그 탭이 목록에서 이미 쓰던 것 그대로다. 조건이 바뀌었으면 true를
  // 돌려주고, 그러면 전체화면이 닫히면서 새로 걸러진 목록으로 다시 열린다
  // (그 판정을 이제 _openXxxDetailSearch가 직접 돌려준다).

  /// 플레이스 탭 전용 상세검색 — 장소대여의 [_openPlaceDetailSearch]와 같은
  /// 방식으로 열고 같은 방식으로 반영한다(시트 안의 항목만 다르다).
  Future<bool> _openEventDetailSearch({SearchEntryConfig? search}) async {
    final result = await showModalBottomSheet<EventFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => EventDetailSearchSheet(
        initialFilter: _eventFilter,
        customAmenityEntries: _customAmenityEntries,
        customPlayItemEntries: _customPlayItemEntries,
        search: search,
        onFilterReset: search == null
            ? null
            : (reset) => setState(() => _eventFilter = reset),
      ),
    );
    if (result == null || !mounted) return false;
    setState(() {
      _eventFilter = result;
      // 상세검색으로 조건을 걸면 "파티샵"만 보던 상태는 풀어 준다 — 파티샵은
      // events가 아니라 별도 컬렉션이라 이 조건들이 걸리지 않는다.
      if (_eventFilter.isActive) _placeShowShopCategory = false;
    });
    return true;
  }

  Future<bool> _openShopDetailSearch({SearchEntryConfig? search}) async {
    final result = await showModalBottomSheet<ShopFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ShopDetailSearchSheet(
        initialFilter: _shopFilter,
        search: search,
        onFilterReset: search == null
            ? null
            : (reset) => setState(() => _shopFilter = reset),
      ),
    );
    if (result == null || !mounted) return false;
    setState(() => _shopFilter = result);
    return true;
  }

  Future<bool> _openCrewDetailSearch({SearchEntryConfig? search}) async {
    final result = await showModalBottomSheet<CrewFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CrewDetailSearchSheet(
        initialFilter: _crewFilter,
        search: search,
        onFilterReset: search == null
            ? null
            : (reset) => setState(() => _crewFilter = reset),
      ),
    );
    if (result == null || !mounted) return false;
    setState(() => _crewFilter = result);
    return true;
  }

  // ── build ─────────────────────────────────────────────────────────
  // 모바일은 기존 화면 구조(_buildMainScaffold)를 절대 바꾸지 않고 그대로 쓴다.
  // 태블릿/데스크톱만 반응형 레이아웃으로 새로 분기한다.
  @override
  Widget build(BuildContext context) {
    if (Responsive.isDesktop(context)) return _buildDesktopLayout();
    if (Responsive.isTablet(context)) return _buildTabletLayout();
    return Stack(
      children: [_buildMainScaffold(), if (_showCoachMark) _buildCoachMark()],
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // 태블릿(2단)/데스크톱(3단) 반응형 레이아웃
  // ══════════════════════════════════════════════════════════════════

  // 첫 번째 라벨은 검정 발자국 이모지(🐾) 없이 순수 텍스트만 두고,
  // MainTopBar가 index 0에 한해 파스텔 핑크 고양이 발바닥 아이콘을 직접
  // 그린다(모바일 TabBar와 동일한 처리).
  // "파티샵"은 더 이상 독립 탭이 아니라 '플레이스' 탭 안의 카테고리 칩으로
  // 이동했다(_placeShowShopCategory). 등록/수정/상세화면 등 파티샵 자체
  // 기능은 그대로이고, 이 탭바 목록에서만 빠졌다.
  static const _kTabLabels = ['파티츄 / 이벤트', '플레이스', '장소대여', '파트너'];

  Future<void> _handleLoginOrMyPageTap() async {
    if (UserSession.userId.isEmpty) {
      await Navigator.push(context, webFramedRoute((_) => LoginPage()));
    } else {
      await Navigator.push(
        context,
        webFramedRoute((_) => const MyPageScreen()),
      );
    }
    if (mounted) setState(() {});
  }

  // 데스크톱 상단바의 "등록하기"는 선택된 카테고리에 맞는 등록화면으로 바로
  // 이동한다(모바일 하단내비 "등록"은 기존처럼 RegisterTypeScreen을 그대로 거친다 — 변경 없음).
  Future<void> _handleCategoryAwareRegisterTap() async {
    final ok = await _requireLogin();
    if (!mounted || !ok) return;
    // 파티는 등록 진입이 갈릴 수 있어(내 공간과 연결할지) 화면 하나로
    // 정해지지 않는다 — 그 판단은 전용 창구가 맡는다.
    if (_topTabController.index != 1 &&
        _topTabController.index != 2 &&
        _topTabController.index != 3) {
      await openPartyRegisterEntry(context);
      return;
    }
    // 플레이스(1)·장소대여(2) 탭은 이제 **같은 등록 화면**으로 간다 —
    // 지금 보고 있는 탭에 맞는 공간 유형이 이미 선택된 채로 열릴 뿐이다
    // (그 자리에서 다른 유형으로 바꿀 수도 있다).
    final Widget target = switch (_topTabController.index) {
      1 =>
        _placeShowShopCategory
            ? const PartyMarketRegisterScreen()
            : const PlaceEntryRegisterScreen(initialType: ComboPlaceType.venue),
      2 => const PlaceEntryRegisterScreen(initialType: ComboPlaceType.stay),
      // 파티 탭은 위에서 이미 돌아갔다 — 여기 남은 갈래는 1·2·3뿐이다.
      _ => const CrewRegisterScreen(),
    };
    // 플레이스·장소대여는 **새 플레이스를 만드는 길**이라 등록 유형 화면과
    // 같은 관문을 지난다 — 여기가 열려 있으면 상단바 "등록하기"가 그대로
    // 우회로가 된다. 파티샵·크루는 플레이스가 아니라 그대로 지나간다.
    if (target is PlaceEntryRegisterScreen) {
      // 지금 보고 있는 탭이 곧 만들려는 유형이라 등록 개수도 함께 본다
      // (플레이스와 장소대여는 각각 10개다). 폼 안에서 유형을 바꾸면 저장
      // 직전 검사가 바뀐 유형으로 다시 센다.
      if (!await PlaceCreateEligibility.ensure(
        context,
        kind: target.initialType == ComboPlaceType.stay
            ? RegistrationKind.rentalListing
            : RegistrationKind.placeListing,
      )) {
        return;
      }
      if (!mounted) return;
    }
    await Navigator.push(context, webFramedRoute((_) => target));
  }

  Widget _buildResponsiveTopBar() {
    return MainTopBar(
      tabs: _kTabLabels,
      selectedIndex: _topTabController.index,
      onTabSelected: (i) => _topTabController.animateTo(i),
      searchController: _searchController,
      onSearchChanged: (val) => setState(() => _searchQuery = val.trim()),
      isLoggedIn: UserSession.userId.isNotEmpty,
      onLoginOrMyPageTap: _handleLoginOrMyPageTap,
      onRegisterTap: _handleCategoryAwareRegisterTap,
      // 지도는 넓은 화면에서도 하단 네비의 '지도'(index 1)와 **같은 경로**로
      // 들어간다 — 동영상 일시정지·MapScreen 라우트가 한 곳(_onBottomNavTap)에만
      // 있어야 모바일과 태블릿의 지도 진입이 갈라지지 않는다.
      onMapTap: () => _onBottomNavTap(1),
    );
  }

  // 파티 탭 전용 좌측 패널 콘텐츠 — 목록 위 줄과 **같은 세 버튼**(날짜·시간·
  // 인원)을 쓴다. 가로 한 줄 Row는 좁은 패널에서 넘칠 수 있어 Wrap으로만
  // 바꿔 담고, 정렬은 이 패널에 두지 않는다(가운데 목록 헤더에 있다).
  // 활성 필터 칩(_buildActiveFilterChips)은 원래도 Wrap 기반이라 그대로 재사용.
  Widget _buildPartyQuickFiltersForPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            QuickFilterIconButton(
              icon: Icons.calendar_today_rounded,
              badge: _filter.selectedDates.isEmpty
                  ? null
                  : '${_filter.selectedDates.length}',
              label: _partyDateLabel(),
              active: _filter.selectedDates.isNotEmpty,
              onTap: _pickPartyDate,
            ),
            QuickFilterIconButton(
              icon: Icons.schedule_rounded,
              label: _partyTimeLabel(),
              active: PartyTimeFilter.isActive(
                _filter.timeOfDayStart,
                _filter.timeOfDayEnd,
              ),
              onTap: _pickPartyTime,
            ),
            QuickFilterIconButton(
              icon: Icons.groups_rounded,
              label: _filter.partyScale == null
                  ? null
                  : PartyScaleFilter.label(_filter.partyScale!),
              active: _filter.partyScale != null,
              onTap: _pickPartyScale,
            ),
          ],
        ),
        _buildActiveFilterChips(),
      ],
    );
  }

  // 좌측 필터 패널 — 탭에 따라 내용만 바꾸고, 각 탭의 기존 필터 상태/로직
  // (_placeFilter/_shopFilter/_crewFilter/_filter, _openXxxDetailSearch)을 그대로 재사용한다.
  Widget _buildFilterPanelForCurrentTab() {
    switch (_topTabController.index) {
      case 1:
        // 플레이스는 상단 카테고리 칩(빠른 필터) + 전용 상세검색 시트를 함께
        // 쓴다 — 칩은 분위기만 켜고 끄고, 나머지 조건(지역·방문 시간·업종·
        // 가격대 …)은 상세검색에서 고른다. "파티샵" 카테고리가 선택된 동안만
        // 예외적으로 파티샵 전용 상세검색(_shopFilter)을 대신 노출한다.
        return MainFilterPanel(
          title: _placeShowShopCategory ? '파티샵 필터' : '플레이스 필터',
          // 카테고리 칩 아래에 빠른 방문시간까지 — 좁은 화면(_buildEventPage)과
          // 같은 필터를 같은 순서로 둔다.
          quickFilters: _placeShowShopCategory
              ? _buildEventCategoryChips()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildEventCategoryChips(),
                    _buildEventQuickFeatureBar(inPanel: true),
                    _buildEventQuickTimeBar(inPanel: true),
                  ],
                ),
          onOpenDetailSearch: _placeShowShopCategory
              ? _openShopDetailSearch
              : _openEventDetailSearch,
          detailFilterActive: _placeShowShopCategory
              ? _shopFilter.isActive
              : _eventFilter.isActive,
        );
      case 2:
        return MainFilterPanel(
          title: '장소대여 필터',
          quickFilters: _buildPlaceFilter(),
          onOpenDetailSearch: _openPlaceDetailSearch,
          detailFilterActive: _placeFilter.isActive,
        );
      case 3:
        return MainFilterPanel(
          title: '파티크루 필터',
          onOpenDetailSearch: _openCrewDetailSearch,
          detailFilterActive: _crewFilter.isActive,
        );
      default:
        // 날짜·시간·인원과 상세검색은 **파티에만** 뜻이 있는 조건이라,
        // 이벤트만 보는 칸에서는 좁은 화면처럼 통째로 감춘다(_buildPartyPage).
        final forParties = _feedFilter.showsParties;
        return MainFilterPanel(
          title: forParties ? '파티 필터' : '이벤트',
          quickFilters: forParties ? _buildPartyQuickFiltersForPanel() : null,
          onOpenDetailSearch: forParties ? _openPartyDetailSearch : null,
          detailFilterActive: _filter.isActive,
        );
    }
  }

  // 가운데 목록 패널 — onCardTap이 주어지면(데스크톱) 카드 클릭 시 상세화면
  // 대신 그 콜백을 호출한다(우측 미리보기 갱신). 태블릿은 onCardTap을 넘기지
  // 않아 카드의 기존 기본 동작(상세화면 이동)이 그대로 유지된다.
  Widget _buildListPanelForCurrentTab({bool withPreviewCallback = false}) {
    switch (_topTabController.index) {
      case 1:
        // 플레이스도 상세검색 시트가 없는 파티크루와 마찬가지로 미리보기 연동 없이
        // 기존 페이지를 그대로 재사용한다.
        return _buildEventPage();
      case 2:
        // 데스크톱 가운데 패널도 같은 보기 방식 토글을 그대로 공유한다.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPlaceViewModeToggle(),
            Expanded(
              child: _buildPlaceListContent(
                onCardTap: withPreviewCallback
                    ? (data, id) => _selectPreview('place', id, data)
                    : null,
              ),
            ),
          ],
        );
      case 3:
        // 파티크루는 상세화면 자체가 없어(모바일도 동일) 미리보기 연동 없이
        // 기존 페이지를 그대로 재사용한다.
        return _buildCrewPage();
      default:
        // 중요: StreamBuilder를 뷰모드 분기 "바깥"에서 딱 한 번만 만든다.
        // 예전엔 뷰모드별로 StreamBuilder를 따로따로 만들었는데, 그러면 보기
        // 방식을 바꿀 때마다 트리 모양이 통째로 바뀌면서 기존 StreamBuilder가
        // 통째로 dispose되고 새 StreamBuilder가 "처음부터" 다시 구독하면서
        // 화면이 계속 로딩 상태로 보이는 버그가 있었다. 구독은 한 번만 하고,
        // 뷰모드는 이미 받아온 docs를 "어떻게 그릴지"만 바꾸도록 고쳤다.
        // 영상 크게 보기는 목록에 인라인으로 그리지 않고 항상 전체화면으로만
        // 진입하므로(_viewMode는 절대 video가 되지 않음) 여기는 분기가 없다.
        return _buildPartyStreamResolved((context, docs) {
          _maybeAutoOpenVideoFeed(docs);
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                _buildPartyListHeaderRow(docs),
                const SizedBox(height: 12),
                // [ 전체 | 🎉 파티 | 🎪 이벤트 ] — 좁은 화면과 **같은 값**
                // ([_feedFilter])을 쓴다. 넓은 화면에만 이벤트 구획이 없으면
                // 같은 탭이 기기에 따라 다른 것을 보여주게 된다.
                _buildFeedFilterBar(),
                const SizedBox(height: 12),
                if (_feedFilter.showsParties)
                  _buildPartyCardsColumn(
                    docs,
                    onCardTap: withPreviewCallback
                        ? (data, id) => _selectPreview('party', id, data)
                        : null,
                  ),
                // 🎪 이벤트 구획 — 좁은 화면과 같은 위젯·같은 정본이다
                // ([EventFeedSection]). 여기서는 카드를 눌러도 미리보기가
                // 아니라 각 원본의 기존 상세로 가는데, 미리보기 패널은 파티
                // 문서를 그리도록 만들어져 있어서 그 편이 맞다.
                if (_feedFilter.showsEvents) ...[
                  const SizedBox(height: 12),
                  EventFeedSection(
                    // 칸이 정하는 것은 머리글뿐이다 — 카드는 전체 칸이든
                    // ✨ 칸이든 같은 이벤트 카드 하나다(아래 좁은 화면과
                    // 같은 규칙 — 기기에 따라 카드가 달라지면 안 된다).
                    showHeader: _feedFilter.showsParties,
                    dates: _filter.selectedDates,
                    timeStart: _filter.timeOfDayStart,
                    timeEnd: _filter.timeOfDayEnd,
                  ),
                ],
              ],
            ),
          );
        });
    }
  }

  // 앱을 마지막에 영상 모드로 종료했다가 다시 켰을 때, 파티 문서가 로드되는
  // 즉시 한 번만 전체화면 영상 피드를 자동으로 띄운다.
  void _maybeAutoOpenVideoFeed(List<QueryDocumentSnapshot> docs) {
    if (!_pendingAutoOpenVideoFeed) return;
    if (docs.isEmpty) return; // 조건에 맞는 파티가 아직 없으면 다음 갱신을 기다린다.
    _pendingAutoOpenVideoFeed = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openVideoFullscreen(docs, 0);
    });
  }

  /// 목록이 그려질 때마다 호출한다 — 지금 보이는 문서를 기억해 두고(보기
  /// 방식 토글이 쓴다), 앱을 마지막에 큰 카드 모드로 종료했다가 다시 켠
  /// 경우라면 문서가 로드되는 즉시 한 번만 전체화면 피드를 띄운다
  /// (파티의 [_maybeAutoOpenVideoFeed]와 같은 역할).
  void _trackPlaceDocs(
    List<QueryDocumentSnapshot> docs,
    PlaceCardSource source,
  ) {
    // TabBarView는 인접 탭까지 미리 만든다 — 플레이스(1번)와 장소대여(2번)는
    // 서로 이웃이라, 보고 있지 않은 쪽이 목록을 그리는 순간에 값을 덮어쓰면
    // 토글이나 자동 진입이 **엉뚱한 탭의 피드**를 연다. 지금 보고 있는 탭이
    // 그린 것만 받는다.
    final ownerTabIndex = source == PlaceCardSource.place ? 1 : 2;
    if (_topTabController.index != ownerTabIndex) return;

    _lastPlaceDocs = docs;
    _lastPlaceSource = source;

    if (!_pendingAutoOpenPlaceFeed) return;
    if (docs.isEmpty) return; // 조건에 맞는 문서가 아직 없으면 다음 갱신을 기다린다.
    _pendingAutoOpenPlaceFeed = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openPlaceFullscreen(docs, 0, source);
    });
  }

  /// 플레이스/장소대여 큰 카드 전체화면 — 파티의 [_openVideoFullscreen]과
  /// 같은 구조다. 전체화면에서 작은/기본 카드를 고르면 그 결과가 pop 값으로
  /// 돌아오고, 즉시 목록 화면의 보기 방식에 반영한다.
  Future<void> _openPlaceFullscreen(
    List<QueryDocumentSnapshot> docs,
    int index,
    PlaceCardSource source,
  ) async {
    // 이중 진입 방지 — 자동 진입(postFrame)과 토글 탭이 같은 프레임에 겹치면
    // 전체화면이 두 겹으로 쌓여서, 뒤로가기를 두 번 눌러야 목록으로 돌아오고
    // 그 사이 화면이 검게 보인다.
    if (_placeFeedOpen) return;
    _placeFeedOpen = true;
    try {
      await _pushPlaceFullscreen(docs, index, source);
    } finally {
      _placeFeedOpen = false;
    }
  }

  Future<void> _pushPlaceFullscreen(
    List<QueryDocumentSnapshot> docs,
    int index,
    PlaceCardSource source,
  ) async {
    final isRental = source == PlaceCardSource.rental;
    final result = await Navigator.push<PlaceFeedExitResult>(
      context,
      webFramedRoute(
        (_) => PlaceFeedScreen(
          docs: docs,
          initialIndex: index,
          source: source,
          // 검색 입구는 목록과 같은 돋보기 하나뿐이고, 여는 시트도 지금 탭이
          // 목록에서 쓰던 그 시트 그대로다(_openSearchSheet) — 전체화면은
          // 버튼만 얹는다.
          searchActive: isRental ? _placeSearchActive : _eventSearchActive,
          onOpenSearch: _openSearchSheetFromFeed,
        ),
      ),
    );
    if (result == null || !mounted) return;
    // 전체화면 안에서 검색어/상세검색 조건을 바꾼 경우 — 다음 목록 갱신 때 새로
    // 걸러진 문서로 전체화면을 자동으로 다시 띄운다(파티의
    // [_openVideoFullscreen]과 완전히 같은 경로).
    if (result.searchChanged) {
      setState(() => _pendingAutoOpenPlaceFeed = true);
      return;
    }
    final mode = result.viewMode;
    if (mode != null && mode != PlaceViewMode.large) {
      setState(() => _setPlaceViewMode(mode));
    }
  }

  MainPreviewItem? _buildPreviewItem() {
    final type = _previewType;
    final docId = _previewDocId;
    final data = _previewData;
    if (type == null || docId == null || data == null) return null;

    switch (type) {
      case 'party':
        return MainPreviewItem(
          type: type,
          card: _buildPartyCard(data, docId),
          onOpenDetail: () => Navigator.push(
            context,
            webFramedRoute((_) => PartyDetailScreen(docId: docId)),
          ),
        );
      case 'place':
        return MainPreviewItem(
          type: type,
          card: PlaceStandardCard(
            place: data,
            placeId: docId,
            source: PlaceCardSource.rental,
          ),
          onOpenDetail: () => Navigator.push(
            context,
            webFramedRoute(
              (_) => PlaceDetailScreen(placeId: docId, data: data),
            ),
          ),
        );
      case 'shop':
        return MainPreviewItem(
          type: type,
          card: ShopStandardCard(shop: data, shopId: docId),
          onOpenDetail: () => Navigator.push(
            context,
            webFramedRoute(
              (_) => PartyShopDetailScreen(shopId: docId, shopData: data),
            ),
          ),
        );
      default:
        return null;
    }
  }

  // 태블릿: 좌측 필터 + 가운데 목록 2단. 지도 '패널'은 아직 넣지 않는다
  // (지도 진입은 상단 바의 '지도' 버튼 — 모바일 하단 네비와 같은 화면).
  Widget _buildTabletLayout() {
    return Scaffold(
      backgroundColor: _isNightMode ? Colors.black : const Color(0xFFFFF4F8),
      body: SafeArea(
        child: Column(
          children: [
            _buildResponsiveTopBar(),
            const Divider(height: 1, color: Color(0xFFFFE4ED)),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 260, child: _buildFilterPanelForCurrentTab()),
                  const VerticalDivider(width: 1, color: Color(0xFFFFE4ED)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildListPanelForCurrentTab(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 데스크톱: 좌측 필터 / 가운데 목록 / 우측 미리보기 3단.
  // PC에서 콘텐츠가 지나치게 넓어지지 않도록 전체 폭에 maxWidth를 둔다.
  Widget _buildDesktopLayout() {
    return Scaffold(
      backgroundColor: _isNightMode ? Colors.black : const Color(0xFFFFF4F8),
      body: SafeArea(
        child: Column(
          children: [
            _buildResponsiveTopBar(),
            const Divider(height: 1, color: Color(0xFFFFE4ED)),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 280,
                        child: _buildFilterPanelForCurrentTab(),
                      ),
                      const VerticalDivider(width: 1, color: Color(0xFFFFE4ED)),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: _buildListPanelForCurrentTab(
                            withPreviewCallback: true,
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 1, color: Color(0xFFFFE4ED)),
                      SizedBox(
                        width: 360,
                        child: MainPreviewPanel(item: _buildPreviewItem()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 헤더 배너 — 스크롤에 따라 큰 로고 배너 ↔ 축소형 배너로 크로스페이드된다.
  // 영상 크게 보기는 더 이상 이 화면 안에 인라인으로 그려지지 않으므로
  // (항상 별도 전체화면으로 진입) 여기는 뷰모드 분기가 없다.
  Widget _buildHeaderBanner() {
    // 낮 버전은 아직 이 두 파일(header_logo_last/header_half) 그대로 —
    // 나중에 별도로 다시 디자인할 예정이라 지금은 손대지 않는다.
    final fullAsset = _isNightMode
        ? 'assets/images/header_logo_night1.png'
        : 'assets/images/header_logo_last.png';
    final halfAsset = _isNightMode
        ? 'assets/images/header_half_night1.png'
        : 'assets/images/header_half.jpg';
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 220),
      crossFadeState: _headerCollapsed
          ? CrossFadeState.showSecond
          : CrossFadeState.showFirst,
      firstChild: Image.asset(
        fullAsset,
        width: double.infinity,
        fit: BoxFit.fitWidth,
      ),
      secondChild: Image.asset(
        halfAsset,
        width: double.infinity,
        fit: BoxFit.fitWidth,
      ),
    );
  }

  Widget _buildMainScaffold() {
    return Scaffold(
      backgroundColor: _isNightMode ? Colors.black : const Color(0xFFFFF4F8),
      body: Stack(
        children: [
          Column(
            children: [
              // head-up(토끼 로고 배너) — "전체 숨김"과 무관하게 항상 남아있는다.
              // 스크롤에 따라 축소된 상태(_headerCollapsed)로 크로스페이드되는
              // 동작은 그대로 유지되고, 그 축소 여부와 상관없이 배너 자체는
              // 절대 사라지지 않는다.
              _buildHeaderBanner(),
              // 상단 탭바 — "전체 숨김"이 켜지면 이 부분만 높이 0으로 접힌다
              // (파티 목록 헤더/필터는 _buildPartyPage 안에서 같은
              // _headerFullyHidden을 보고 따로 접힌다).
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: _headerFullyHidden
                    ? const SizedBox(width: double.infinity)
                    : _buildTopTabBar(),
              ),
              // 콘텐츠 영역 (탭에 따라 전환)
              Expanded(
                child: TabBarView(
                  controller: _topTabController,
                  children: [
                    // 파티 상세화면 등에서 로그인하고 뒤로가기만 눌러 돌아와도
                    // (탭을 다시 누르지 않아도) 참가비 "로그인 필요" 표시가
                    // 즉시 로그인 상태로 갱신되도록 AuthRebuilder로 감싼다 —
                    // 다른 화면들과 동일한 패턴([UserSession.revision] 구독).
                    AuthRebuilder(builder: (_) => _buildPartyPage()),
                    _buildEventPage(),
                    _buildPlacePage(),
                    _buildCrewPage(),
                  ],
                ),
              ),
            ],
          ),
          // 헤더 접기/펼치기 버튼 — 상태와 무관하게 항상 화면 좌상단에
          // 떠 있는다(문구만 상태에 따라 바뀜).
          _buildHeaderToggleButton(),
          // 우상단 액션들 — 낮/밤 토글 + 알림함. 한 Row에 묶어 오른쪽 끝에
          // 고정하므로 버튼이 늘어나도 간격이 어긋나거나 겹치지 않는다.
          _buildTopRightActions(),
        ],
      ),
      // 상세검색 전용 FAB(튠 아이콘)는 없앴다 — 네 탭 모두 목록 헤더의 돋보기
      // 하나로만 들어가고, 상세검색은 그 안(_openSearchSheet)에 있다.
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onBottomNavTap,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFFF6FA0),
        unselectedItemColor: Colors.black45,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: '홈',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            label: '지도',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.add_box_outlined),
            label: '등록',
          ),
          BottomNavigationBarItem(icon: _buildChatTabIcon(), label: '채팅'),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: '마이',
          ),
        ],
      ),
    );
  }

  // 헤더 접기/펼치기 버튼 — 상태(_headerFullyHidden)와 무관하게 항상 화면
  // 좌상단의 같은 자리에 떠 있는다(스크롤되는 목록 바깥, Scaffold body의
  // Stack 최상단에 얹어서 스크롤 중에도 항상 보이고, 위치가 절대 바뀌지
  // 않는다 — 이전엔 펼침 버튼만 가운데에 조건부로 나타나고 접기 버튼은
  // 헤더 안(다른 위치)에 있어 상태가 바뀔 때마다 버튼이 나타났다 사라지며
  // 자리가 바뀌었는데, 이제 버튼 하나가 문구만 바꾸며 항상 같은 자리에 있다).
  Widget _buildHeaderToggleButton() {
    final topInset = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: topInset + 8,
      left: 12,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() {
            _headerFullyHidden = !_headerFullyHidden;
            // 탭바를 접을 때는 로고 배너도 스크롤을 기다리지 않고 즉시
            // 축소형(half) 이미지로 바뀌게 한다. 펼칠 때는 실제 스크롤
            // 위치를 기준으로 다시 판단한다(맨 위면 큰 로고로 복귀).
            _headerCollapsed = _headerFullyHidden
                ? true
                : (_partyScrollCtrl.hasClients && _partyScrollCtrl.offset > 8);
          }),
          child: Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              _headerFullyHidden
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_up_rounded,
              size: 18,
              color: const Color(0xFFFF6FA0),
            ),
          ),
        ),
      ),
    );
  }

  // 낮/밤 헤더 배너 토글 버튼 — 접기/펼치기 버튼(_buildHeaderToggleButton)
  // 바로 옆에 같은 크기·스타일로 떠 있는다. 버튼에 표시되는 아이콘은
  // "누르면 바뀔 모드"가 아니라 항상 "지금 모드"를 보여준다(해=낮,
  // 달=밤) — 눌러서 반대쪽으로 전환한다.
  /// 화면 우상단에 떠 있는 액션 묶음 — [낮/밤 토글] [알림 종].
  ///
  /// 예전에는 낮/밤 토글 하나만 `right: 12`로 직접 고정했는데, 버튼이 늘면
  /// 각자 다른 right 값을 손으로 계산해야 해서 하나만 바뀌어도 간격이
  /// 어긋나거나 겹친다. 오른쪽 끝에 붙는 Row 하나로 묶어 두면 순서와 간격이
  /// 한 곳에서 정해지고, 버튼 크기(36)와 좌상단 접기 버튼과의 균형도 그대로
  /// 유지된다.
  Widget _buildTopRightActions() {
    final topInset = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: topInset + 8,
      right: 12,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDayNightToggleButton(),
          const SizedBox(width: 8),
          _buildNotificationBellButton(),
        ],
      ),
    );
  }

  /// 상단 떠 있는 원형 버튼의 공통 껍데기 — 크기(36)·터치 영역·그림자·모양을
  /// 한 곳에서 정해 좌상단 접기 버튼과 완전히 같은 규격으로 맞춘다.
  Widget _buildTopActionButton({
    required Widget child,
    required VoidCallback onTap,
    required Color background,
    String? tooltip,
  }) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: background,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }

  // 낮/밤 헤더 배너 토글 버튼.
  //
  // 아이콘은 **지금 모드가 아니라 "누르면 될 모드"**를 가리킨다
  // ([dayNightToggleIcon] 주석 참고). 채움색은 그 아이콘 쪽에 맞춘다 —
  // 낮에는 검게, 밤에는 희게 채워 버튼이 "이제 저쪽으로 간다"는 쪽을
  // 같이 가리킨다. 아이콘 색만은 채움과 무관하게 파티츄 핑크로 고정한다 —
  // 해든 달든 같은 핑크라 브랜드 색이 두 모드에서 끊기지 않는다.
  Widget _buildDayNightToggleButton() {
    return _buildTopActionButton(
      onTap: () => setState(() => _isNightMode = !_isNightMode),
      background: _isNightMode ? Colors.white : const Color(0xFF1A1A2E),
      tooltip: dayNightToggleTooltip(_isNightMode),
      child: Icon(
        dayNightToggleIcon(_isNightMode),
        size: 18,
        color: const Color(0xFFFF6FA0),
      ),
    );
  }

  /// 하단 '채팅' 탭 아이콘 — 안 읽은 **대화방 수**가 숫자로 붙는다.
  ///
  /// 정본은 Firestore의 chatRooms다 — **푸시를 받았는지와 무관하다.** 푸시는
  /// 기기에 토큰이 없거나(로그인 직후·권한 거부) 실패할 수 있지만, 배지는
  /// 방 문서만 보고 정해지므로 그 영향을 받지 않는다.
  ///
  /// 개수는 채팅 목록이 이미 구독하는 스트림([ChatService.unreadRoomCountStream]
  /// → roomsStream)에서 그대로 나온다 — participants array-contains 하나라
  /// 호스트로 받은 문의·게스트로 건 문의·예약 후 대화가 전부 같은 셈에 들어가고,
  /// 조회가 늘지 않는다.
  ///
  /// AuthRebuilder로 감싸는 이유는 **로그아웃한 순간 이전 계정의 숫자가 남지
  /// 않게** 하기 위해서다 — uid가 바뀌면 스트림이 통째로 갈리고, 빈 uid에는
  /// 0이 흘러 배지가 사라진다.
  Widget _buildChatTabIcon() {
    return AuthRebuilder(
      builder: (_) => StreamBuilder<int>(
        stream: ChatService.unreadRoomCountStream(UserSession.userId),
        builder: (context, snapshot) {
          // 못 읽었을 때 0으로 떨어뜨리면 **"안 읽은 대화가 없다"는 거짓 정보**가
          // 된다(배지가 사라지므로). 알림 종과 같은 태도로 표시는 남기되 숫자는
          // 비운다 — 눌러서 목록에서 확인하게 한다.
          final failed = snapshot.hasError;
          if (failed) {
            logFirestoreStreamError(
              'ChatUnreadRoomCount',
              snapshot.error,
              snapshot.stackTrace,
            );
          }
          final count = snapshot.data ?? 0;
          if (!failed && count <= 0) {
            return const Icon(Icons.chat_bubble_outline);
          }
          // 두 자리부터는 '9+' — 좁은 탭에서 숫자가 아이콘을 밀어내지 않는다.
          final label = failed ? '' : (count > 9 ? '9+' : '$count');
          return Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.chat_bubble_outline),
              Positioned(
                top: -5,
                right: -8,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: label.isEmpty ? 0 : 4,
                  ),
                  constraints: BoxConstraints(
                    minWidth: label.isEmpty ? 9 : 16,
                    minHeight: label.isEmpty ? 9 : 16,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6FA0),
                    borderRadius: BorderRadius.circular(9),
                    // 아이콘 선 위에 얹혀도 뭉개지지 않게 흰 테두리로 끊는다.
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                  child: label.isEmpty
                      ? null
                      : Text(
                          label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 10,
                            height: 1.2,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 알림함 진입 종 아이콘 — 안 읽은 알림이 있으면 우상단에 핑크 점이 붙는다.
  ///
  /// 안 읽음 판정의 **정본은 `notifications` 컬렉션의 `read` 필드**이고, 이
  /// 버튼은 마이페이지 종과 **같은 스트림**([NotificationService.watchUnreadCount])을
  /// 그대로 구독한다 — 홈 전용 알림 상태를 따로 두지 않는다. 스냅샷 스트림이라
  /// 알림함에서 읽음 처리(markAllRead)가 나가는 즉시 점이 사라지고, 홈으로
  /// 돌아오기 전에 이미 갱신돼 있다.
  ///
  /// 로그인 전에는 uid가 비어 스트림이 0을 돌려주므로 점이 붙지 않는다. 버튼
  /// 자체는 항상 그려서 상단 레이아웃이 로그인 여부에 따라 흔들리지 않게 한다.
  Widget _buildNotificationBellButton() {
    return AuthRebuilder(
      builder: (_) => StreamBuilder<int>(
        stream: NotificationService.watchUnreadCount(UserSession.userId),
        builder: (context, snapshot) {
          // 개수를 못 읽었을 때 0으로 떨어뜨리면 **"안 읽은 알림이 없다"는 거짓
          // 정보**가 된다(점이 사라지므로). 마이페이지 종과 같은 태도로,
          // 원인은 로그로 남기고 점은 붙여 둔 채 눌러서 확인하게 한다 —
          // 알림함이 오류와 '다시 시도'를 제대로 보여준다.
          final failed = snapshot.hasError;
          if (failed) {
            logFirestoreStreamError(
              'HomeNotificationUnreadCount',
              snapshot.error,
              snapshot.stackTrace,
            );
          }
          final hasUnread = failed || (snapshot.data ?? 0) > 0;
          return _buildTopActionButton(
            tooltip: failed ? '알림 상태를 불러오지 못했어요' : '알림',
            background: Colors.white,
            onTap: _openNotifications,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  size: 18,
                  color: Color(0xFFFF6FA0),
                ),
                // 숫자 배지가 아니라 점 하나 — "뭔가 왔다"만 알린다.
                if (hasUnread)
                  Positioned(
                    top: 7,
                    right: 7,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6FA0),
                        shape: BoxShape.circle,
                        // 종 아이콘 선 위에 얹혀도 점이 뭉개지지 않도록
                        // 흰 테두리로 한 번 끊어준다.
                        border: Border.all(color: Colors.white, width: 1.2),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 기존 알림함 화면을 그대로 연다 — 홈 전용 알림 화면을 새로 만들지 않는다.
  Future<void> _openNotifications() async {
    if (!await _requireLogin()) return;
    if (!mounted) return;
    await Navigator.push(
      context,
      webFramedRoute((_) => const NotificationsScreen()),
    );
  }

  // ── 상단 탭바 ─────────────────────────────────────────────────────
  Widget _buildTopTabBar() {
    return Material(
      key: _tabBarKey,
      color: Colors.white,
      child: TabBar(
        controller: _topTabController,
        // 탭 4개(파티/플레이스/장소대여/파티크루)가 좌우로 넘쳐 드래그해야
        // 보이던 것을 없애고, 한 화면 너비에 고정 배분해 전부 한 번에 보이게 한다.
        // "파티샵"은 더 이상 별도 탭이 아니라 플레이스 탭 안의 카테고리 칩이다.
        isScrollable: false,
        labelColor: const Color(0xFFFF6FA0),
        unselectedLabelColor: Colors.black45,
        labelStyle: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        indicatorColor: const Color(0xFFFF6FA0),
        indicatorWeight: 2.5,
        dividerColor: const Color(0xFFFFE4ED),
        // 첫 탭("파티츄")만 검정 발자국 이모지(🐾) 대신 파스텔 핑크 고양이
        // 발바닥 아이콘을 직접 그린다 — 탭 선택 색상은 Tab의 기본
        // IconTheme/DefaultTextStyle 애니메이션을 타지 않도록 아이콘 색을
        // 고정해 항상 같은 파스텔 톤으로 보이게 한다.
        tabs: const [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.pets, size: 14, color: Color(0xFFFFACD2)),
                SizedBox(width: 4),
                // 이 탭이 보여주는 것은 파티만이 아니다 — 매장 이벤트와 공간
                // 이벤트도 여기서 함께 발견한다([EventFeedFilter]).
                Text('파티츄 / 이벤트'),
              ],
            ),
          ),
          Tab(text: '📍 플레이스'),
          Tab(text: '🏠 장소대여'),
          Tab(text: '🤝 파티크루'),
        ],
      ),
    );
  }

  // ── 파티 페이지 ───────────────────────────────────────────────────
  // 버그 수정: StreamBuilder를 뷰모드 분기 "바깥"에서 한 번만 만든다.
  // 예전에는 뷰모드마다 별도 StreamBuilder(_buildPartyListContent와
  // _buildPartyVideoFeed)를 각각 만들었는데, 보기 방식을 바꾸면 최상위 위젯
  // 모양이 통째로 바뀌어(Column ↔ PageView가 담긴 Column) 기존 StreamBuilder가
  // dispose되고 새 StreamBuilder가 처음부터 다시 구독하면서, Firestore 재조회
  // 자체는 곧 끝나더라도 그 사이 화면이 계속 로딩 상태로 보였다(보기에 따라
  // 간헐적으로 아예 멈춰 보이기도 함). 지금은 구독을 한 번만 하고, 뷰모드는
  // 이미 받아온 docs를 "어떻게 그릴지"만 바꾼다 — 데이터 재조회 없음.
  Widget _buildPartyPage() {
    return _buildPartyStreamResolved((context, docs) {
      _maybeAutoOpenVideoFeed(docs);
      // 영상 크게 보기는 목록에 인라인으로 그리지 않고 항상 전체화면으로만
      // 진입하므로(_viewMode는 절대 video가 되지 않음) 여기는 분기가 없다 —
      // "파티 목록" 줄(제목+검색+보기방식+정렬)과 목록은 항상 이 형태로 보인다.
      // 검색창은 화면에 상시 노출하지 않고, 옆의 돋보기 버튼을 눌렀을 때만
      // 팝업으로 연다(_openSearchPopup) — 세로 공간을 아끼기 위함.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "파티 목록" 제목 + 음소거 + 보기방식 + 검색.
          //
          // 헤더를 접어도 **이 줄은 사라지지 않는다** — 플레이스 탭과 같다.
          // 접기는 위쪽 헤더(로고 배너 아래 탭바)와 이 줄의 **제목 글씨**만
          // 접고([_buildPartyListHeaderRow]), 검색·보기방식·정렬과 아래
          // 날짜/시간/인원 줄은 그대로 남는다. 예전에는 이 줄과 필터 줄을
          // 통째로 접어, 접는 순간 상단 메뉴가 함께 사라졌다.
          //
          // 아래 여백은 0이다 — 이 줄과 바로 아래 날짜/시간/인원 줄은 "하나의 상단
          // 툴바"로 읽혀야 한다. 두 줄 사이에 보이는 간격은 여백을 따로 주지
          // 않아도 두 줄이 이미 각자 안에 갖고 있다 — 이 줄은 높이 40인
          // 보기방식·검색 버튼에 맞춰지고 그 한가운데에 20짜리 제목이 앉으며,
          // 아래 줄은 바 안에 낮은 버튼이 앉아 위로 ~5px이 남는다. 예전처럼
          // 여기에 8, 저기에 4를 더 주면 그 둘이 그대로 더해져 23px짜리 빈 띠가
          // 생겼다.
          //
          // 위 여백은 4다(예전 8). 줄 안이 **가운데 맞춤**으로 바뀌면서 40짜리
          // 줄 위쪽에 10px이 이미 비어 있으므로, 예전만큼 위에서 또 밀면 탭바와
          // 제목 사이가 그만큼 벌어진다. 4는 보기방식 알약의 분홍 테두리가
          // 탭바 구분선에 붙지 않을 만큼만 남긴 값이다.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: _buildPartyListHeaderRow(docs),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _partyScrollCtrl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 날짜·시간·인원 + 정렬 + 활성 필터 칩 — 헤더를 접어도
                  // 그대로 남는다(플레이스 탭의 조건 줄과 같은 규칙).
                  // 고른 값도 접기와 상관없이 [_filter] 하나에 그대로 있다.
                  // [ 전체 | 🎉 파티 | 🎪 이벤트 ] — 이 탭이 무엇을 보일지.
                  // 아래 날짜·정렬 줄보다 **위**에 둔다: 그 줄은 파티에만
                  // 걸리는 조건이라, 무엇을 보는지부터 정하고 그 다음에
                  // 좁히는 순서로 읽혀야 한다.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: _buildFeedFilterBar(),
                  ),
                  // 날짜·시간(·인원)·정렬과 걸어 둔 조건 칩.
                  //
                  // 예전에는 이 줄 전체를 `showsParties`로 감쌌다 — 이벤트만
                  // 보는 칸으로 넘어가면 날짜·시간 필터가 통째로 사라져,
                  // "이벤트를 날짜로 찾는" 길이 아예 없었다. 이제는 줄을
                  // 그대로 두고 **인원 버튼만** 뺀다: 이벤트에는 모집 인원이
                  // 없지만 날짜·시간은 파티와 똑같이 뜻이 있기 때문이다.
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 위 여백 0 — 위 헤더 줄에 그대로 붙여 한 덩어리 툴바로
                      // 보이게 한다. 아래 8은 예전 4에, 바가 낮아지며(42→36)
                      // 아래쪽에서 사라진 3px을 되돌려 준 값이다 — 이번에
                      // 줄이는 것은 제목과 이 줄 사이지, 이 줄과 첫 카드
                      // 사이가 아니다.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: _buildCategorySection(
                          withCapacity: _feedFilter.showsParties,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildActiveFilterChips(),
                      ),
                    ],
                  ),
                  // 파티 목록
                  // 위 6 — 필터 줄 아래 4와 바 자체의 ~5px에 더해 ~15px. 예전 8이면
                  // 필터 줄까지 통째로 아래로 밀려 보였다.
                  if (_feedFilter.showsParties)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                      child: _buildPartyCardsColumn(docs),
                    ),
                  // 🎪 이벤트 구획 — 매장 이벤트 + 공간 이벤트. 파티와 섞지
                  // 않고 이어 붙인다([EventFeedSection] 상단 주석).
                  if (_feedFilter.showsEvents)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                      child: EventFeedSection(
                        // 파티 목록과 함께 보일 때만 어디부터 이벤트인지
                        // 알려주는 머리글이 필요하다. 이 구획이 칸마다 달리
                        // 하는 일은 이것뿐이다 — 이벤트 카드는 전체 칸에서도
                        // ✨ 칸에서도 같은 것 하나다.
                        showHeader: _feedFilter.showsParties,
                        // 📅🕐 는 파티와 **같은 필터 하나**를 나눠 쓴다 —
                        // 값이 하나뿐이라 파티/이벤트를 오가도 고른 조건이
                        // 그대로 남는다. 판정만 각자 자기 데이터로 한다
                        // (파티는 회차 일정, 이벤트는 [PlaceEventTime]).
                        dates: _filter.selectedDates,
                        timeStart: _filter.timeOfDayStart,
                        timeEnd: _filter.timeOfDayEnd,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  /// [ 전체 | 🎉 파티 | 🎪 이벤트 ] — 파티츄/이벤트 탭이 무엇을 보일지 고른다.
  ///
  /// 고르는 것은 **화면에 그릴 것**뿐이다([_feedFilter]) — 파티는 예전 그대로
  /// `parties` 스트림에서, 이벤트는 각자의 정본에서 읽는다. 데이터를 합치거나
  /// 옮겨 적지 않는다.
  Widget _buildFeedFilterBar() {
    final night = _isNightMode;
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          for (final f in EventFeedFilter.values) ...[
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_feedFilter == f) return;
                  setState(() => _feedFilter = f);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _feedFilter == f
                        ? const Color(0xFFFF6FA0)
                        : night
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: _feedFilter == f
                          ? const Color(0xFFFF6FA0)
                          : night
                          ? Colors.white.withValues(alpha: 0.14)
                          : const Color(0xFFF0E2E9),
                    ),
                  ),
                  child: Text(
                    f.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _feedFilter == f
                          ? Colors.white
                          : night
                          ? Colors.white70
                          : Colors.black54,
                    ),
                  ),
                ),
              ),
            ),
            if (f != EventFeedFilter.values.last) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  // "파티 목록" 제목 + 전역 음소거 + 검색 아이콘 + 보기 방식 아이콘 — 세 가지
  // 보기 방식 렌더링 분기(_buildPartyPage, _buildListPanelForCurrentTab)
  // 모두에서 공유한다. 정렬 버튼은 이 줄이 아니라 아래 날짜 필터 바의
  // 오른쪽 끝에 있다(_buildCategorySection). 검색창을 상시 노출하지 않으므로,
  // 돋보기 버튼을 눌러야 검색 시트가 열리고, 상세검색도 그 안에 있다
  // (_openSearchSheet — 네 탭 공통).
  // 헤더 접기/펼치기는 _buildHeaderToggleButton(화면 좌상단 고정)로만
  // 제어하므로 여기엔 없다. 음소거 버튼은 기본/작은 카드(이 화면)에만 두고,
  // 큰 카드·지도는 별도로 배치한다(전역 오버레이는 쓰지 않기로 함).
  Widget _buildPartyListHeaderRow(List<QueryDocumentSnapshot> docs) {
    // 왼쪽(제목 그룹)과 오른쪽(버튼 그룹)을 spaceBetween으로 양 끝에
    // 붙인다 — 예전처럼 Spacer로 오른쪽 버튼들을 어중간하게 띄우지 않고,
    // 두 버튼을 오른쪽 SafeArea 끝에 딱 붙여 iOS/토스 스타일로 정렬한다.
    //
    // 세로는 **가운데 맞춤**이다 — 네 요소('파티 목록' · 스피커 · 보기방식 ·
    // 돋보기)가 한 줄의 세로 중앙에 나란히 선다.
    //
    // 예전에는 바닥 맞춤이었다. 줄 높이를 정하는 것은 오른쪽 버튼들(40)인데
    // 제목 글씨는 20이라, 바닥에 붙이면 제목만 10px 아래로 내려앉아 **같은
    // 줄인데 왼쪽이 오른쪽보다 낮아 보였다**. 스피커(37)는 또 그 중간에
    // 걸려서, 셋이 제각각 다른 높이에 있었다.
    //
    // 가운데 맞춤이면 셋의 중심이 모두 줄의 중심(20)에 온다 — 스피커는 21짜리
    // 아이콘이 대칭 여백 8 안에 들어 있어 상자 중심 = 아이콘 중심이고, 제목은
    // 아래 [StrutStyle]로 줄 상자를 글자 크기에 맞춰 두었으므로 글꼴 여분
    // 줄높이에 밀려 내려가지 않는다.
    //
    // 이렇게 생기는 제목 위아래 10px은 바깥 여백에서 되받는다 — 위 여백을
    // 8에서 4로 줄여 헤더 덩어리 자체가 48에서 44로 낮아진다(호출부 주석).
    // 좌표를 직접 밀지 않는 이유도 같다: 여백·정렬로 맞으면 글꼴이나 아이콘
    // 크기가 바뀌어도 다시 어긋나지 않는다.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 접기가 접는 것은 **제목 글씨뿐**이다 — 옆의 음소거와 오른쪽
              // 보기방식·검색은 그대로 남는다(접었다고 상단 메뉴가 사라지면
              // 안 된다). 접힘/펼침은 값을 건드리지 않으므로 검색·정렬·필터
              // 상태도 그대로다.
              Flexible(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeInOut,
                  alignment: Alignment.centerLeft,
                  child: _headerFullyHidden
                      ? const SizedBox.shrink()
                      : Text(
                          // 지금 보고 있는 것을 그대로 적는다 — 이벤트만
                          // 보는 칸에서 '파티 목록'이라고 적혀 있으면 위
                          // 세그먼트가 무엇을 바꿨는지 알 수 없다.
                          switch (_feedFilter) {
                            EventFeedFilter.all => '파티 · 이벤트',
                            EventFeedFilter.party => '파티 목록',
                            EventFeedFilter.event => '이벤트',
                          },
                          // 글자 크기(20)는 그대로 두고 **줄 상자만** 글자
                          // 크기에 맞춘다 — 글꼴이 기본으로 얹는 여분 줄높이
                          // (20px 글자에 ~28px 상자)는 글자 위아래로 고르게
                          // 붙지 않아서, 그대로 두면 가운데 맞춤을 해도 글자가
                          // 줄 중심보다 아래에 앉는다. 상자를 20으로 조여야
                          // 상자 중심과 글자 중심이 같아져 오른쪽 버튼들과
                          // 정확히 같은 높이가 된다.
                          strutStyle: const StrutStyle(
                            fontFamily: 'SeoulHangang',
                            fontSize: 20,
                            height: 1,
                            forceStrutHeight: true,
                          ),
                          // 밤 모드에선 배경이 검정이라 기본(회색) 글자색이
                          // 묻힌다 — 이때만 흰색으로 올리고, 낮 모드는 기존
                          // 상속색 그대로.
                          style: TextStyle(
                            fontFamily: 'SeoulHangang',
                            fontSize: 20,
                            height: 1,
                            fontWeight: FontWeight.w500,
                            color: _isNightMode ? Colors.white : null,
                            shadows: const [
                              Shadow(
                                color: Colors.black87,
                                offset: Offset(0.3, 0),
                              ),
                              Shadow(
                                color: Colors.black87,
                                offset: Offset(-0.3, 0),
                              ),
                              Shadow(
                                color: Colors.black87,
                                offset: Offset(0, 0.3),
                              ),
                              Shadow(
                                color: Colors.black87,
                                offset: Offset(0, -0.3),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              ),
              const VideoMuteIconButton(),
            ],
          ),
        ),
        // 오른쪽 버튼 그룹 — 바깥 Padding(16)만으로 화면 오른쪽 끝에 바로
        // 붙인다(예전처럼 추가 여백을 더 주지 않음).
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ⚠️ 여기에 🎪 이벤트로 건너가는 버튼을 두지 않는다 — 이벤트는
            // 이 탭 **안**에 있다([_feedFilter] 세그먼트). 다른 탭으로
            // 보내는 버튼과 같은 자리에서 고르는 세그먼트가 함께 있으면
            // "이벤트"가 두 곳을 가리키게 된다.
            //
            // 보기 방식 — 장소대여 목록과 **같은 위젯**([ViewModeMenuButton])
            // 이다. 예전에는 칸 셋을 그대로 펼쳤는데, 같은 성격의 컨트롤이
            // 탭마다 다르게 보이지 않도록 "아이콘 하나 + 눌러서 붙는 메뉴"로
            // 맞췄다. 무엇을 고르면 무슨 일이 일어나는지(_selectPartyViewMode)
            // 는 예전 그대로다.
            ViewModeMenuButton(
              currentIcon: _viewModeIcon(_viewMode),
              label: '보기 방식 · ${_viewMode.label}',
              options: [
                for (final mode in PartyViewMode.values)
                  ViewModeOption(
                    icon: _viewModeIcon(mode),
                    label: mode.label,
                    selected: _viewMode == mode,
                    onTap: () => _selectPartyViewMode(mode, docs),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            // 네 탭이 공유하는 단 하나의 검색 입구 — 상세검색도 이 안에 있다.
            SearchEntryIconButton(
              onTap: _openSearchSheet,
              active: _partySearchActive,
            ),
          ],
        ),
      ],
    );
  }

  /// 목록 헤더 줄 오른쪽 끝에 붙는 공용 컨트롤 묶음 —
  /// [ 보기 방식 ][ 돋보기 ]( [ 정렬 ] ).
  /// 파티 탭 헤더([_buildPartyListHeaderRow])와 같은 순서·같은 간격이라,
  /// 세 탭의 오른쪽 끝 모습이 완전히 같다.
  ///
  /// [sortButton]은 **장소대여 탭에만** 넘긴다 — 정렬을 갖춘 탭이 거기뿐이라
  /// 나머지 탭에는 빈 자리조차 만들지 않는다(넘기지 않으면 줄이 예전 그대로다).
  Widget _listHeaderTrailing({
    required Widget viewModeSwitch,
    required bool searchActive,
    Widget? sortButton,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        viewModeSwitch,
        const SizedBox(width: 8),
        SearchEntryIconButton(onTap: _openSearchSheet, active: searchActive),
        if (sortButton != null) sortButton,
      ],
    );
  }

  // Firestore 조회 + 필터 + 정렬까지 마친 문서 리스트를 넘겨주는 공용
  // 스트림 래퍼 — 작은 카드/기본 카드/영상 모드가 모두 이 로직을 그대로 공유한다.
  // (에러/로딩/빈 목록 처리, 정렬·검색 로직은 전부 기존 그대로.)
  Widget _buildPartyStreamResolved(
    Widget Function(BuildContext context, List<QueryDocumentSnapshot> docs)
    builder,
  ) {
    return StreamBuilder<QuerySnapshot>(
      stream: _partyStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('[MainList] 🔴 Firestore 오류: ${snapshot.error}');
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                '목록 오류: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final rawDocs = snapshot.data!.docs;
        debugPrint('[MainList] ✅ Firestore 원본 문서 수: ${rawDocs.length}');
        for (final doc in rawDocs) {
          final d = doc.data() as Map<String, dynamic>;
          debugPrint(
            '[MainList] doc=${doc.id} title="${d['title']}" '
            'mainImageUrl=${d['mainImageUrl']} '
            'imageUrls=${d['imageUrls']} images=${d['images']}',
          );
        }

        final allDocs = List<QueryDocumentSnapshot>.from(rawDocs)
          ..sort((a, b) {
            final aTime =
                (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            final bTime =
                (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });

        if (allDocs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                '아직 등록된 파티가 없어요.\n첫 번째 파티를 열어보세요!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black45),
              ),
            ),
          );
        }

        final filtered = _applyFilters(allDocs);
        final sorted = _searchQuery.isNotEmpty
            ? _applySearchSort(filtered)
            : _applySortMode(filtered);
        // 같은 게시글(= 같은 seriesId)의 날짜 문서들을 카드 한 장으로 접는다 —
        // 대표는 가장 가까운 다음 일정이다. 카드에 **적히는** 날짜는 대표가
        // 아니라 지금 켜진 날짜 필터 기준으로 다시 고른다(_cardDateFocus).
        //
        // 접기는 정렬 **뒤에** 한다: 정렬 결과의 등장 순서를 그대로 지키므로
        // 사용자가 고른 정렬이 무너지지 않는다.
        _partySeries = PartySeries.index(allDocs);
        final docs = _partySeries.collapse(sorted);
        debugPrint(
          '[MainList] 필터/정렬 후 문서 수: ${docs.length} '
          '(정렬: ${_filter.sortMode.label})',
        );

        // 검색/필터 결과가 0건이어도 builder를 그대로 호출한다 — 예전엔 여기서
        // "해당 조건의 파티가 없어요" 텍스트만 반환해버려서 그 위를 감싸던
        // 헤더(제목/검색/보기방식/정렬)·검색창·카테고리·필터칩까지 통째로
        // 사라졌었다. 이제 그 상단 UI는 항상 그대로 두고, 목록이 놓일 자리에만
        // 결과 없음 안내 + 필터 초기화 버튼을 보여준다(_buildPartyCardsColumn).
        return builder(context, docs);
      },
    );
  }

  // "파티 목록" 옆 보기방식 아이콘에서 영상 크게 보기를 고르거나, 앱을 영상
  // 모드로 종료했다가 다시 켰을 때 전체화면 카드 피드로 진입한다.
  // 전체화면에서 작은/기본 카드를 고르면 그 결과가 pop 값으로 돌아오는데,
  // 그 즉시 목록 화면의 보기 방식을 갱신해 바로 반영한다(영상 크게 보기를
  // 다시 고른 경우엔 전체화면이 닫히지 않으므로 여기까지 오지 않는다).
  Future<void> _openVideoFullscreen(
    List<QueryDocumentSnapshot> docs,
    int index,
  ) async {
    final result = await Navigator.push<VideoFeedExitResult>(
      context,
      webFramedRoute(
        (_) => PartyVideoFeedScreen(
          docs: docs,
          initialIndex: index,
          // 플레이스 전체화면과 **같은 배선** — 목록의 돋보기가 여는 그 검색
          // 시트를 그대로 열고, 조건이 바뀌면 새로 걸러 다시 띄운다.
          searchActive: _partySearchActive,
          onOpenSearch: _openSearchSheetFromFeed,
        ),
      ),
    );
    if (result == null || !mounted) return;
    // 전체화면 안에서 검색어/상세검색 조건을 바꾼 경우 — 값은 검색 시트가 이미
    // 목록 화면 상태에 반영했으므로, 다음 목록 갱신 때 새로 걸러진 문서로
    // 전체화면을 자동으로 다시 띄우기만 하면 된다(앱을 영상 모드로 종료했다가
    // 재실행할 때와 동일한 경로 재사용).
    if (result.searchChanged) {
      setState(() => _pendingAutoOpenVideoFeed = true);
      return;
    }
    if (result.viewMode != null && result.viewMode != PartyViewMode.video) {
      setState(() => _applyViewMode(result.viewMode!));
    }
  }

  // 작은 카드/기본 카드 목록 — 마찬가지로 순수 렌더링 함수(스트림 구독 없음).
  // onCardTap을 넘기면(데스크톱) 카드 클릭 시 상세화면 대신 그 콜백이 호출된다.
  // 기본 카드는 장소대여 목록(_buildPlaceListContent)과 동일하게 2열 그리드로
  // 배치한다 — 카드 크기뿐 아니라 목록 배치 구조까지 그대로 맞추기 위함.
  Widget _buildPartyCardsColumn(
    List<QueryDocumentSnapshot> docs, {
    void Function(Map<String, dynamic> party, String docId)? onCardTap,
  }) {
    if (docs.isEmpty) return _buildEmptyFilterResult();

    // 카드에 적을 날짜의 기준 — 지금 켜져 있는 날짜 조건 그대로다. 목록을 한 번
    // 그릴 때 한 번만 만들고 모든 카드가 공유한다.
    final dateFocus = _cardDateFocus();

    if (_viewMode == PartyViewMode.compact) {
      return Column(
        children: docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final tapCallback = onCardTap != null
              ? () => onCardTap(data, doc.id)
              : null;
          return PartyCompactCard(
            key: ValueKey(doc.id),
            party: data,
            docId: doc.id,
            onTap: tapCallback,
            dateFocus: dateFocus,
          );
        }).toList(),
      );
    }

    // 기본 카드 — 장소대여 카드(_placeGridCard)와 동일한 2열 Row 쌍 그리드,
    // 열 간격 10 / 행 간격 12로 동일하게 맞췄다.
    final rows = <Widget>[];
    for (var i = 0; i < docs.length; i += 2) {
      final leftDoc = docs[i];
      final rightDoc = i + 1 < docs.length ? docs[i + 1] : null;
      final leftData = leftDoc.data() as Map<String, dynamic>;
      final rightData = rightDoc?.data() as Map<String, dynamic>?;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: PartyStandardCard(
                  key: ValueKey(leftDoc.id),
                  party: leftData,
                  docId: leftDoc.id,
                  onTap: onCardTap != null
                      ? () => onCardTap(leftData, leftDoc.id)
                      : null,
                  dateFocus: dateFocus,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: rightDoc != null
                    ? PartyStandardCard(
                        key: ValueKey(rightDoc.id),
                        party: rightData!,
                        docId: rightDoc.id,
                        onTap: onCardTap != null
                            ? () => onCardTap(rightData, rightDoc.id)
                            : null,
                        dateFocus: dateFocus,
                      )
                    : const SizedBox(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  /// 카드가 "어느 날짜의 회차를 보여줄지" 정하는 기준.
  ///
  /// 상세검색의 날짜 조건(오늘/내일/이번주)과 달력으로 직접 고른 날짜를 함께
  /// 본다 — 목록을 거르는 조건과 같은 것을 보므로, 걸러져 남은 파티는
  /// 그 범위 안에 반드시 회차가 있다. 아무 조건도 없으면(전체) 빈 기준을 주고
  /// 카드는 예전처럼 다음 회차를 보여준다.
  PartyDateFocus _cardDateFocus() => PartyDateFocus.of(
    dateOptions: _filter.dateOptions,
    selectedDates: _filter.selectedDates,
  );

  // 검색/필터 결과 0건 안내 — 상단 헤더·검색창·카테고리·필터칩은 그대로 둔
  // 채(_buildPartyStreamResolved가 더 이상 이 자리에서 화면을 통째로 대체하지
  // 않는다) 목록이 놓일 자리에만 이 위젯을 보여준다. 활성 조건이 하나라도
  // 있으면 한 번에 초기화할 수 있는 버튼을 함께 제공해 "화면에 갇힌" 느낌을
  // 없앤다.
  Widget _buildEmptyFilterResult() {
    final hasActiveQuery = _searchQuery.isNotEmpty || _filter.isActive;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '해당 조건의 파티가 없어요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '다른 조건으로 다시 찾아보세요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black38),
            ),
            if (hasActiveQuery) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _resetPartySearch,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('검색 조건 다시 설정'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6FA0),
                  side: const BorderSide(color: Color(0xFFFF6FA0)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 검색어·카테고리 탭·상세검색 필터를 한 번에 초기화한다.
  void _resetPartySearch() {
    setState(() {
      _searchQuery = '';
      _searchController.clear();
      // 정렬은 검색 조건이 아니다 — 조건만 비우고 보고 있던 정렬은 지킨다.
      _filter = PartyFilter(sortMode: _filter.sortMode);
    });
  }

  // ── 준비 중 페이지 ────────────────────────────────────────────────
  // ── 파티크루 탭 ──────────────────────────────────────────────────────
  Widget _buildCrewPage() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Colors.white,
            // 구인/구직 탭 줄 오른쪽 끝에 다른 탭과 같은 돋보기 하나 —
            // 이 탭도 검색·상세검색 입구가 여기 하나뿐이다. 탭바 아래 밑줄은
            // 돋보기 밑까지 이어져야 하므로 탭바 자체의 divider 대신 이
            // Container의 아래 테두리로 그린다.
            child: Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFFFE4ED))),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: TabBar(
                      labelColor: Color(0xFFFF6FA0),
                      unselectedLabelColor: Colors.black45,
                      labelStyle: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      unselectedLabelStyle: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      indicatorColor: Color(0xFFFF6FA0),
                      indicatorWeight: 2.5,
                      dividerColor: Colors.transparent,
                      tabs: [
                        Tab(text: '구인'),
                        Tab(text: '구직'),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: SearchEntryIconButton(
                      onTap: _openSearchSheet,
                      active: _crewSearchActive,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            // 상단 메인 탭(파티/플레이스/장소대여/파티샵/파티크루)도 좌우
            // 드래그로 전환되는 TabBarView라, 이 안쪽 구인/구직 탭까지
            // 드래그로 넘어가게 두면 같은 가로 방향 제스처를 두 TabBarView가
            // 동시에 잡으려고 경합해 안쪽이 이겨버린다 — 그러면 파티크루
            // 탭에서는 옆으로 드래그해도 상위 탭(예: 파티샵)으로 못 돌아간다.
            // 구인/구직은 탭(클릭)으로만 전환되게 하고 드래그는 막아서,
            // 좌우 드래그는 항상 상위 메인 탭 전용으로 남긴다.
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [_buildCrewList('구인'), _buildCrewList('구직')],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCrewList(String crewType) {
    return StreamBuilder<QuerySnapshot>(
      // ⚠️ orderBy('createdAt')를 where 2개(crewType/isActive)와 함께 쓰면
      // 복합 색인이 필요한데 없어서 항상 FAILED_PRECONDITION 에러로 끝났다
      // ("파티크루 목록을 불러오지 못했어요") — 정렬은 서버가 아니라 받은
      // 데이터를 클라이언트에서 직접 해 복합 색인 자체가 필요 없게 한다
      // (파티/장소 목록과 동일한 패턴).
      stream: FirebaseFirestore.instance
          .collection('crews')
          .where('crewType', isEqualTo: crewType)
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF6FA0)),
          );
        }
        // Firestore 쿼리 오류(예: 복합 색인 누락)를 조용히 삼키면 실제로는
        // 등록된 파티크루가 있는데도 목록이 비어 보인다 — 반드시 구분해서 보여준다.
        if (snap.hasError) {
          logFirestoreStreamError('PartyCrewList', snap.error, snap.stackTrace);
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.error_outline, size: 48, color: Colors.black26),
                  SizedBox(height: 16),
                  Text(
                    '파티크루 목록을 불러오지 못했어요.\n잠시 후 다시 시도해주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.black45),
                  ),
                ],
              ),
            ),
          );
        }
        final allDocs = List<QueryDocumentSnapshot>.from(snap.data?.docs ?? [])
          ..sort((a, b) {
            final aTime =
                (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            final bTime =
                (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });
        if (allDocs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🎤', style: TextStyle(fontSize: 56)),
                  const SizedBox(height: 20),
                  Text(
                    crewType == '구인' ? '등록된 구인 글이 없습니다' : '등록된 구직 글이 없습니다',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    crewType == '구인'
                        ? '파티크루를 구인하고 싶다면\n글을 등록해보세요!'
                        : '파티크루로 활동하고 싶다면\n구직 글을 등록해보세요!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black38,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final docs = _applyCrewFilter(
          PreRegistrationVisibility.withoutHidden(
            BlockService.withoutBlocked(allDocs),
          ),
        );
        if (docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                '선택한 조건에 맞는 글이 없어요.',
                style: TextStyle(fontSize: 14, color: Colors.black45),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            return _crewCard(doc.id, data);
          },
        );
      },
    );
  }

  Widget _crewCard(String docId, Map<String, dynamic> d) {
    final crewType = d['crewType'] as String? ?? '';
    final title = d['title'] as String? ?? '';
    final role = d['role'] as String? ?? '';
    final hostName = d['hostName'] as String? ?? '';
    // 구직 글에만 저장되는 프로필 사진 — 있을 때만 카드 왼쪽에 원형으로 붙인다.
    final profileUrl = d['profileImageUrl'] as String? ?? '';
    // "서울 강남구 · 부산 전체" — 광역만 저장돼 있던 옛 글은 "서울 전체"로 읽힌다.
    final region = CrewArea.labelOfCrewData(d);
    final isHiring = crewType == '구인';

    // 기간·시간·급여 라벨은 상세 화면과 같은 규칙을 써야 하므로
    // crew_detail_screen.dart의 공용 함수를 그대로 부른다.
    final periodLabel = crewPeriodLabel(d);
    final timeLabel = crewTimeLabel(d);
    final payLabel = crewPayLabel(d);

    // ── 배지/제목/세부정보 열 ──
    // 프로필 사진이 있으면 이 열이 사진 오른쪽으로 들어가므로 Row 안에서
    // Expanded로 감싸 쓴다.
    final infoColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 배지 행 ──
        Row(
          children: [
            _crewBadge(
              crewType,
              isHiring ? const Color(0xFFFF6FA0) : const Color(0xFF7C5CBF),
              isHiring ? const Color(0xFFFFF0F5) : const Color(0xFFF3EFFA),
            ),
            const SizedBox(width: 6),
            _crewBadge(periodLabel, Colors.black45, const Color(0xFFF7F7FA)),
            const SizedBox(width: 8),
            // 프로필 사진이 붙으면 이 줄의 폭이 그만큼 줄어든다 — 남는 폭을
            // 이름이 전부 가져가고(오른쪽 정렬), 모자라면 이름만 줄여서
            // 배지·찜 버튼이 밀려 넘치지 않게 한다(예전 Spacer 자리).
            Expanded(
              child: Text(
                hostName,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11, color: Colors.black38),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            // 찜은 카드 탭(상세 이동)과 별개로 동작해야 한다 — 버튼 자신이
            // GestureDetector(HitTestBehavior.opaque)라 안쪽이 제스처 경쟁에서
            // 이기고, 바깥 카드 탭은 발생하지 않는다.
            FavoriteStarButton(
              itemType: FavoriteType.crew,
              itemId: docId,
              size: 20,
              dense: true,
            ),
          ],
        ),
        const SizedBox(height: 10),
        // ── 제목 ──
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'SeoulHangang',
            fontSize: 15,
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
              Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        // ── 세부 정보 ──
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            if (role.isNotEmpty) _infoChip(Icons.work_outline, role),
            if (timeLabel != null) _infoChip(Icons.access_time, timeLabel),
            if (region.isNotEmpty)
              _infoChip(Icons.location_on_outlined, region),
            _infoChip(
              Icons.payments_outlined,
              payLabel,
              color: const Color(0xFFFF6FA0),
            ),
          ],
        ),
      ],
    );

    return GestureDetector(
      // 카드 전체가 상세 진입 — 여백(빈 곳)을 눌러도 열리도록 opaque.
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        webFramedRoute((_) => CrewDetailScreen(docId: docId, initialData: d)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0FFF6FA0),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: profileUrl.isEmpty
            // 사진이 없으면 기존 레이아웃 그대로 — 빈 아바타 자리를 만들지 않는다.
            ? infoColumn
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  crewProfileAvatar(profileUrl, size: 48),
                  const SizedBox(width: 12),
                  Expanded(child: infoColumn),
                ],
              ),
      ),
    );
  }

  Widget _crewBadge(String label, Color textColor, Color bgColor) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
    ),
  );

  Widget _infoChip(
    IconData icon,
    String label, {
    Color color = Colors.black45,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(fontSize: 12, color: color)),
    ],
  );

  // ── 파티샵 탭 ─────────────────────────────────────────────────────────
  // onCardTap을 넘기면(데스크톱) 카드 클릭 시 상세화면 대신 그 콜백이 호출된다.
  // 이 페이지는 원래도 검색창/카테고리 같은 별도 chrome 없이 목록 자체였으므로
  // 데스크톱 가운데 패널에서도 그대로 재사용한다.
  Widget _buildShopPage({
    void Function(Map<String, dynamic> shop, String shopId)? onCardTap,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('partyShops')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF6FA0)),
          );
        }
        // Firestore 쿼리 오류(예: 복합 색인 누락)를 조용히 삼키면 실제로는
        // 등록된 파티샵이 있는데도 목록이 비어 보인다 — 반드시 구분해서 보여준다.
        if (snap.hasError) {
          logFirestoreStreamError('PartyShopList', snap.error, snap.stackTrace);
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.error_outline, size: 48, color: Colors.black26),
                  SizedBox(height: 16),
                  Text(
                    '파티샵 목록을 불러오지 못했어요.\n잠시 후 다시 시도해주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.black45),
                  ),
                ],
              ),
            ),
          );
        }
        final allDocs = snap.data?.docs ?? [];
        if (allDocs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text('🎈', style: TextStyle(fontSize: 56)),
                  SizedBox(height: 20),
                  Text(
                    '등록된 파티샵이 없습니다',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '케이크, 풍선, 파티 소품 등\n다양한 샵을 등록해보세요!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black38,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final docs = _applyShopFilter(
          PreRegistrationVisibility.withoutHidden(
            BlockService.withoutBlocked(allDocs),
          ),
        );
        if (docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                '선택한 조건에 맞는 샵이 없어요.',
                style: TextStyle(fontSize: 14, color: Colors.black45),
              ),
            ),
          );
        }
        // 보기 방식 셋 — 거르고 정렬된 목록(docs)과 상세 이동은 **셋이 그대로
        // 공유한다**. 바뀌는 것은 카드 껍데기와 배치뿐이고, 대표 미디어 규칙은
        // 세 방식 모두 [getPartyCoverMedia] 하나다.
        //
        // 배치까지 **플레이스 목록과 같은 값**이다 — 작은 카드는 가로형 1열,
        // 기본 카드는 2열 Row 쌍 그리드(열 간격 10 / 행 간격 12, 바깥 여백
        // 14/6/14), 큰 카드는 화면 한 장을 통째로 쓰는 1열이다. 예전에는 셋 다
        // 세로형 1열이었고 큰 카드는 대표 이미지 높이만 240으로 늘린 것이라,
        // 같은 이름의 보기 방식인데도 두 탭이 전혀 다르게 보였다.
        VoidCallback? tapOf(QueryDocumentSnapshot doc) => onCardTap == null
            ? null
            : () => onCardTap(doc.data() as Map<String, dynamic>, doc.id);

        if (_shopViewMode == PlaceViewMode.compact) {
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final doc = docs[i];
              return ShopCompactCard(
                key: ValueKey(doc.id),
                shop: doc.data() as Map<String, dynamic>,
                shopId: doc.id,
                onTap: tapOf(doc),
              );
            },
          );
        }

        if (_shopViewMode == PlaceViewMode.large) {
          // 큰 카드 — 플레이스는 이 카드를 전체화면 피드로 열지만 파티샵은
          // 목록 안에 둔다. 화면 한 장이 곧 카드 한 장이 되도록 목록
          // 뷰포트 높이를 그대로 카드 높이로 주므로, 두 탭의 큰 카드가 같은
          // 비율·같은 정보 배치로 보인다.
          return LayoutBuilder(
            builder: (context, constraints) => ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: docs.length,
              itemBuilder: (_, i) {
                final doc = docs[i];
                return SizedBox(
                  height: constraints.maxHeight,
                  child: ShopLargeCard(
                    key: ValueKey(doc.id),
                    shop: doc.data() as Map<String, dynamic>,
                    shopId: doc.id,
                    onTap: tapOf(doc),
                  ),
                );
              },
            ),
          );
        }

        // 기본 카드(기본값) — 플레이스/파티 목록과 **같은 2열 그리드**.
        final rowCount = (docs.length / 2).ceil();
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
          itemCount: rowCount,
          itemBuilder: (_, rowIdx) {
            final leftDoc = docs[rowIdx * 2];
            final rightDoc = rowIdx * 2 + 1 < docs.length
                ? docs[rowIdx * 2 + 1]
                : null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ShopStandardCard(
                      key: ValueKey(leftDoc.id),
                      shop: leftDoc.data() as Map<String, dynamic>,
                      shopId: leftDoc.id,
                      onTap: tapOf(leftDoc),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: rightDoc != null
                        ? ShopStandardCard(
                            key: ValueKey(rightDoc.id),
                            shop: rightDoc.data() as Map<String, dynamic>,
                            shopId: rightDoc.id,
                            onTap: tapOf(rightDoc),
                          )
                        : const SizedBox(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── 🎉 이벤트 색인 구독 ─────────────────────────────────────────────────

  /// 🎉 이벤트 칸이 켜져 있는 동안에만 `placePromotions`를 구독한다.
  ///
  /// 조건이 바뀌는 입구는 여럿이지만(격자 칸·상세검색·빠른 필터) 전부
  /// setState로 끝나므로, 그린 뒤가 아니라 **그리기 직전**인 여기 한 곳에서
  /// 맞춰 두면 어느 입구로 켜도 새지 않는다. 구독을 걸고 푸는 일뿐이라
  /// build 중에 불려도 화면 상태를 건드리지 않는다.
  void _syncPlaceEventIndexSub() {
    final want = _eventFilter.eventOnly && !_placeShowShopCategory;
    if (want == (_placeEventSub != null)) return;

    if (!want) {
      _placeEventSub?.cancel();
      _placeEventSub = null;
      // 색인 자체도 버린다 — 다음에 다시 켰을 때 낡은 집합으로 잠깐 잘못
      // 걸러 놓고 시작하지 않게 한다(null이면 예전 미러 판정이 답한다).
      _placeEventIndex = null;
      return;
    }

    _placeEventSub = PlacePromotionService.watchPublicAll().listen(
      (promotions) {
        if (!mounted) return;
        final next = PlaceEventIndex.fromPromotions(promotions);
        if (_placeEventIndex?.sameAs(next) ?? false) return;
        setState(() => _placeEventIndex = next);
      },
      onError: (Object e, StackTrace s) =>
          logFirestoreStreamError('PlaceEventIndex', e, s),
    );
  }

  /// 🎪 장소대여 이벤트 칸이 켜져 있는 동안에만 구독한다 — 위와 같은 규칙,
  /// 다른 컬렉션([PlaceEventIndex.rentalCollection]).
  ///
  /// 색인을 컬렉션으로 좁히므로 여기 담기는 것은 공간 이벤트뿐이다. 매장
  /// 이벤트는 이 집합에 들어올 수 없고, 그래서 장소대여 목록에 매장이 섞일
  /// 길이 없다.
  void _syncRentalEventIndexSub() {
    final want = _placeFilter.eventOnly;
    if (want == (_rentalEventSub != null)) return;

    if (!want) {
      _rentalEventSub?.cancel();
      _rentalEventSub = null;
      _rentalEventIndex = null;
      return;
    }

    _rentalEventSub = PlacePromotionService.watchPublicAll().listen(
      (promotions) {
        if (!mounted) return;
        final next = PlaceEventIndex.fromPromotions(
          promotions,
          collection: PlaceEventIndex.rentalCollection,
        );
        if (_rentalEventIndex?.sameAs(next) ?? false) return;
        setState(() => _rentalEventIndex = next);
      },
      onError: (Object e, StackTrace s) =>
          logFirestoreStreamError('RentalEventIndex', e, s),
    );
  }

  // ── 플레이스 탭 ────────────────────────────────────────────────────────
  // 상단 카테고리 칩·빠른 방문 조건은 목록 위에 그대로 두고, 검색어와
  // 상세검색은 줄 오른쪽 끝 돋보기 하나로만 들어간다(파티·장소대여와 동일).
  Widget _buildEventPage() {
    // 🎉 이벤트를 켠 동안에만 이벤트 정본을 구독한다(위 주석).
    _syncPlaceEventIndexSub();
    // "파티샵" 카테고리가 선택된 상태면 events가 아니라 완전히 별도인
    // partyShops 데이터를 보여준다 — 등록/수정/상세화면 등 파티샵 자체
    // 로직은 전혀 건드리지 않고, 이 탭 안에서 보여주는 위치만 바꾼다.
    //
    // 카테고리 칩은 events 목록이 로딩 중이든, 에러가 났든, 비어 있든
    // 상관없이 항상 눈에 보여야 한다("가게가 하나도 없어도 5개 카테고리는
    // 보이게") — 그래서 StreamBuilder "안"이 아니라 밖에 고정해두고,
    // 아래 콘텐츠 영역만 상태에 따라 바뀌게 한다.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: _buildEventCategoryChips(),
        ),
        // ⚠️ 여기에 🎉 이벤트 전용 진입 카드를 두지 않는다. 이벤트는 위
        // 격자의 한 칸이고([PlaceCategoryExplorer.eventValue]), 누르면 이
        // 아래 목록이 이벤트 중인 매장만 남긴다 — 별도 화면으로 갈아타면
        // 카드도 상세도 두 벌이 된다.
        //
        // ── 상단 컨트롤은 **한 줄**이다 ─────────────────────────────────
        //
        //   [📅 🕐 👥]  [✨ 편의·서비스 ▾]        [보기 방식] [🔍]
        //
        // 예전에는 여기가 두 줄이었다 — 가로스크롤 빠른필터 줄이 하나,
        // 방문 조건 + 보기 방식 줄이 하나. 위 카테고리 격자가 이미 큰데 그
        // 아래로 두 줄이 더 붙으니 정작 플레이스 카드가 화면 밖으로 밀렸다.
        //
        // · 방문 조건 — 날짜·시간·인원 셋을 버튼 하나로 묶었다. 누르면 셋이
        //   함께 아래로 펼쳐진다([PlaceQuickTimeBar]). 상세검색과 같은
        //   _eventFilter를 고치므로 두 입구의 값이 항상 같다.
        // · 편의·서비스 — 가로스크롤 줄이 하던 일을 버튼 하나가 받는다
        //   ([PlaceAmenityButton]). '＋ 조건' 칸은 없앴다 — 상세검색은 같은
        //   줄 맨 오른쪽 돋보기 하나로 들어간다.
        // · 보기 방식 — 아이콘 셋을 늘어놓지 않고 **버튼 하나 + 메뉴**다
        //   ([_placeViewModeButton]) — 지금 쓰는 보기 방식이 버튼에 그대로
        //   앉고, 누르면 작은/기본/큰 셋이 한 번에 열린다.
        if (!_placeShowShopCategory)
          _buildEventQuickTimeBar(
            middle: PlaceAmenityButton(
              filter: _eventFilter,
              night: _isNightMode,
              onChanged: () => setState(() {}),
            ),
            trailing: _listHeaderTrailing(
              viewModeSwitch: _placeViewModeButton(),
              searchActive: _eventSearchActive,
            ),
          )
        else
          // 파티샵 카테고리는 events 조건(방문 조건·편의·서비스)이 걸리지
          // 않으므로 왼쪽 둘은 없지만, **보기 방식과 검색 입구**는 다른 탭과
          // 같은 자리(줄 오른쪽 끝)에 같은 위젯으로 둔다.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _listHeaderTrailing(
                  viewModeSwitch: _shopViewModeButton(),
                  searchActive: _shopSearchActive,
                ),
              ],
            ),
          ),
        // ⚠️ 여기에 "고른 조건 × 칩"을 쌓지 않는다. 대분류는 위 카테고리
        // 영역에, 빠른 조건은 그 버튼 자체에 이미 켜져 있어서 같은 말을 두 번
        // 하는 것이 되고, 조건을 켤수록 플레이스 카드가 아래로 밀려난다.
        // 지우는 것(전체 초기화 포함)은 상세검색 시트 안에서 한다.
        Expanded(
          child: _placeShowShopCategory
              ? _buildShopPage()
              : _buildEventListContent(),
        ),
      ],
    );
  }

  Widget _buildEventListContent() {
    return StreamBuilder<QuerySnapshot>(
      // 쿼리는 [ListingSources]에만 있다 — 통합 지도도 이 쿼리를 그대로 쓴다.
      // isActive 서버 필터의 "필드가 없는 문서는 제외" 같은 미묘한 성질까지
      // 두 화면이 같아야 목록/지도의 노출이 어긋나지 않는다.
      stream: ListingSources.events().snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF6FA0)),
          );
        }
        if (snap.hasError) {
          logFirestoreStreamError('EventList', snap.error, snap.stackTrace);
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.error_outline, size: 48, color: Colors.black26),
                  SizedBox(height: 16),
                  Text(
                    '플레이스 목록을 불러오지 못했어요.\n잠시 후 다시 시도해주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.black45),
                  ),
                ],
              ),
            ),
          );
        }
        // Firestore가 createdAt 최신순으로 내려주지만, 같은 "등록 날짜"
        // 안에서는 파티츄 전용 혜택이 있는 플레이스를 앞으로 당긴다
        // (플레이스는 모집 상태 개념이 없어 boostable 조건이 없다).
        final allDocs =
            (snap.data?.docs ?? [])
                .where(
                  (d) => ListingSources.isEventVisible(
                    d.data() as Map<String, dynamic>,
                  ),
                )
                .toList()
              ..sort(
                (a, b) => PartychuPerkRanking.compareNewestFirst(
                  a.data() as Map<String, dynamic>,
                  b.data() as Map<String, dynamic>,
                ),
              );
        final docs = _applyEventFilter(allDocs);

        // "전체"(조건을 하나도 안 건 상태)에서는 플레이스 목록 뒤에
        // 파티샵을 이어 붙인다. 카테고리 칩에서 "파티샵"을 직접 고르면
        // 예전 그대로 파티샵만 단독으로 본다(_buildShopPage) — 두 목록은
        // 카드 구조가 완전히 달라 섞지 않고 구획을 나눠 잇는다.
        // 검색어도 "조건"이다 — 검색 중에는 조건과 무관한 파티샵을 뒤에
        // 이어 붙이지 않는다(상세검색을 걸었을 때와 같은 취급).
        final withShops = !_eventFilter.isActive && _eventSearch.query.isEmpty;

        if (allDocs.isEmpty) {
          // 플레이스가 하나도 없으면 파티샵만 이어 보여준다 — 파티샵까지
          // 없을 때만 예전과 똑같은 큰 빈 화면을 띄운다.
          if (!withShops) return _eventEmptyState();
          return SingleChildScrollView(
            child: _buildEventShopSection(
              hasPlacesAbove: false,
              whenNoShops: _eventEmptyState(),
            ),
          );
        }
        if (docs.isEmpty && !withShops) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '선택한 조건의 플레이스가 없어요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.black45),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    // 검색어도 함께 비운다 — 검색어만으로 0건일 때 상세검색
                    // 조건만 비워서는 목록이 돌아오지 않기 때문이다.
                    onPressed: () => setState(() {
                      _eventFilter = EventFilter();
                      _eventSearch.controller.clear();
                      _eventSearch.query = '';
                    }),
                    child: const Text('조건 초기화'),
                  ),
                ],
              ),
            ),
          );
        }

        // 보기 방식은 목록 위 토글에서 고른다 — "작은 카드"는 지도 '이 근처
        // 파티'와 같은 가로형 카드 1열, "기본 카드"는 파티 기본 카드와 같은
        // 2열 그리드다. "큰 카드"는 파티 영상 크게 보기와 마찬가지로 목록에
        // 그리지 않고 전체화면(PlaceFeedScreen)으로만 진입하므로 여기 분기가
        // 없다(_placeViewMode는 절대 large가 되지 않는다).
        // 카테고리 필터(docs)와 상세 이동은 세 방식이 그대로 공유한다.
        // 여기까지 왔다면 docs는 비어 있지 않다 — 빈 경우는 위에서 모두
        // 갈라져 나갔다("전체"면 withShops라 docs == allDocs).
        _trackPlaceDocs(docs, PlaceCardSource.place);
        final Widget eventsSliver;
        if (_placeViewMode == PlaceViewMode.compact) {
          eventsSliver = SliverList.builder(
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final doc = docs[i];
              final data = doc.data() as Map<String, dynamic>;
              return PlaceCompactCard(
                key: ValueKey(doc.id),
                place: data,
                placeId: doc.id,
                source: PlaceCardSource.place,
                withParty: _withPartyIndex.has(doc.id),
              );
            },
          );
        } else {
          // 기본 화면 — 파티 기본 카드와 같은 2열 그리드(Row 쌍).
          final rowCount = (docs.length / 2).ceil();
          eventsSliver = SliverList.builder(
            itemCount: rowCount,
            itemBuilder: (_, rowIdx) {
              final leftDoc = docs[rowIdx * 2];
              final rightDoc = rowIdx * 2 + 1 < docs.length
                  ? docs[rowIdx * 2 + 1]
                  : null;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: PlaceStandardCard(
                        key: ValueKey(leftDoc.id),
                        place: leftDoc.data() as Map<String, dynamic>,
                        placeId: leftDoc.id,
                        source: PlaceCardSource.place,
                        withParty: _withPartyIndex.has(leftDoc.id),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: rightDoc != null
                          ? PlaceStandardCard(
                              key: ValueKey(rightDoc.id),
                              place: rightDoc.data() as Map<String, dynamic>,
                              placeId: rightDoc.id,
                              source: PlaceCardSource.place,
                              withParty: _withPartyIndex.has(rightDoc.id),
                            )
                          : const SizedBox(),
                    ),
                  ],
                ),
              );
            },
          );
        }

        return CustomScrollView(
          slivers: [
            SliverPadding(
              // 위 여백은 필터 줄과 카드가 붙지 않을 만큼만 — 카드가 화면
              // 아래로 밀리지 않게 한다.
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              sliver: eventsSliver,
            ),
            if (withShops)
              SliverToBoxAdapter(
                child: _buildEventShopSection(hasPlacesAbove: true),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
        );
      },
    );
  }

  /// 플레이스 탭 "전체"에서 등록된 플레이스가 하나도 없을 때의 빈 화면.
  Widget _eventEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text('📍', style: TextStyle(fontSize: 56)),
            SizedBox(height: 20),
            Text(
              '등록된 플레이스가 없습니다',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '혼술하기 좋은 바, 이벤트, 핫플레이스를\n플레이스로 등록해보세요!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.black38,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "전체" 카테고리에서 플레이스 목록 뒤에 잇는 파티샵 구획.
  ///
  /// 파티샵은 `events`가 아니라 별도의 `partyShops` 컬렉션이고 카드 구조도
  /// 달라서, 한 목록에 섞지 않고 구분 헤더를 둔 별도 구획으로 잇는다.
  /// 등록된 파티샵이 없으면 구획 자체를 그리지 않아 예전 화면과 똑같다.
  ///
  /// 여기서는 파티샵 전용 상세검색(_shopFilter)을 적용하지 않는다 — 그 필터를
  /// 여는 입구("파티샵" 카테고리)가 이 화면에는 없어서, 안 보이는 조건으로
  /// 목록이 조용히 줄어드는 걸 막는다.
  Widget _buildEventShopSection({
    required bool hasPlacesAbove,
    Widget? whenNoShops,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('partyShops')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          // 플레이스 목록은 이미 잘 떠 있으므로, 파티샵 쪽 오류로 화면 전체를
          // 망치지 않고 이 구획만 조용히 접는다(로그는 남긴다).
          logFirestoreStreamError('EventTabShops', snap.error, snap.stackTrace);
          return whenNoShops ?? const SizedBox.shrink();
        }
        if (snap.connectionState == ConnectionState.waiting &&
            whenNoShops != null) {
          // 플레이스가 하나도 없어 이 구획이 화면의 전부인 경우 —
          // 빈 화면을 잠깐 보여줬다 목록으로 바뀌며 깜빡이지 않게 기다린다.
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: CircularProgressIndicator(color: Color(0xFFFF6FA0)),
            ),
          );
        }
        final docs = PreRegistrationVisibility.withoutHidden(
          snap.data?.docs ?? const <QueryDocumentSnapshot>[],
        );
        if (docs.isEmpty) return whenNoShops ?? const SizedBox.shrink();

        final labelColor = _isNightMode ? Colors.white : Colors.black87;
        return Padding(
          padding: EdgeInsets.fromLTRB(14, hasPlacesAbove ? 8 : 0, 14, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('🛍️', style: TextStyle(fontSize: 17)),
                  const SizedBox(width: 6),
                  Text(
                    '파티샵',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: labelColor,
                    ),
                  ),
                  const Spacer(),
                  // 파티샵만 모아 보려면 카테고리 칩과 같은 단독 화면으로 —
                  // 거기서는 파티샵 전용 상세검색도 쓸 수 있다.
                  TextButton(
                    onPressed: () => setState(() {
                      _placeShowShopCategory = true;
                      _eventThemeFilter.clear();
                    }),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFF6FA0),
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text(
                      '모두 보기',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 카드 배치는 **바로 위 플레이스 목록과 같은 보기 방식**을 따른다 —
              // 작은 카드면 가로형 1열, 기본 카드면 2열 그리드다. 한 화면에서
              // 위아래로 이어 붙는 두 구획의 카드 밀도가 어긋나면 파티샵 구획만
              // 다른 서비스처럼 읽힌다.
              if (_placeViewMode == PlaceViewMode.compact)
                for (final doc in docs)
                  ShopCompactCard(
                    key: ValueKey(doc.id),
                    shop: doc.data() as Map<String, dynamic>,
                    shopId: doc.id,
                  )
              else
                for (var i = 0; i < docs.length; i += 2)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ShopStandardCard(
                            key: ValueKey(docs[i].id),
                            shop: docs[i].data() as Map<String, dynamic>,
                            shopId: docs[i].id,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: i + 1 < docs.length
                              ? ShopStandardCard(
                                  key: ValueKey(docs[i + 1].id),
                                  shop:
                                      docs[i + 1].data()
                                          as Map<String, dynamic>,
                                  shopId: docs[i + 1].id,
                                )
                              : const SizedBox(),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  // 플레이스 문서의 특징(테마) 태그 목록 — 새 데이터는 'themeTags'(다중
  // 선택) 배열을 쓰고, 예전에 단일 'category'로 등록된 문서는 그 값을
  // 태그 하나짜리 목록으로 취급해 하위호환한다.
  List<String> _placeThemeTags(Map<String, dynamic> data) {
    final tags = (data['themeTags'] as List?)?.cast<String>();
    if (tags != null && tags.isNotEmpty) return tags;
    final legacy = data['category'] as String?;
    return legacy != null && legacy.isNotEmpty ? [legacy] : const [];
  }

  /// 2단 빠른 필터 — 카테고리 영역 바로 아래 한 줄. 값은 1단·상세검색과
  /// 같은 [_eventFilter] 하나를 본다.
  Widget _buildEventQuickFeatureBar({bool inPanel = false}) =>
      PlaceQuickFeatureBar(
        filter: _eventFilter,
        night: _isNightMode,
        padding: inPanel
            ? const EdgeInsets.fromLTRB(0, 6, 0, 2)
            : const EdgeInsets.fromLTRB(16, 6, 16, 0),
        onChanged: () => setState(() {}),
        onOpenMore: _openEventDetailSearch,
      );

  /// 1단 카테고리 영역 — **대분류 한 층**과 **그 아래 소분류 한 층**이 같은
  /// 자리를 번갈아 쓴다([PlaceCategoryExplorer]).
  ///
  /// 대분류는 한 번에 하나만 켜지고(음식 → 클럽을 누르면 음식이 꺼진다),
  /// 고른 대분류는 이 영역에 그대로 보이므로 아래에 '× 칩'으로 다시 쌓지
  /// 않는다. 선택 판정·상태 변경은 전부 [_eventFilter] 하나를 고치는 것이라
  /// 필터 로직은 예전 그대로다.
  Widget _buildEventCategoryChips() {
    return PlaceCategoryExplorer(
      filter: _eventFilter,
      // 사선 타일 형태는 그대로 두고 재질만 바꾼다 — 밤은 다크 글래스,
      // 낮은 화이트 글래스(파티 탭의 알약 필터와 같은 낮 팔레트).
      night: _isNightMode,
      shopSelected: _placeShowShopCategory,
      onSelectShop: () => setState(() {
        _placeShowShopCategory = true;
        // 파티샵은 events가 아니라 별도 컬렉션이라, 플레이스 탐색
        // 조건(대분류·특징·속성)을 들고 갈 곳이 없다.
        _eventFilter.clearDiscovery();
        _eventThemeFilter.clear();
      }),
      onChanged: () => setState(() => _placeShowShopCategory = false),
    );
  }

  /// 플레이스 목록 위의 빠른 방문시간 필터 — 상세검색 시트와 **같은
  /// [_eventFilter]**를 직접 고친다. 그래서 여기서 '오늘 22:00'을 고른 뒤
  /// 상세검색을 열면 이미 그 값이 들어 있고, 시트에서 시간을 바꾸면 이 바에도
  /// 곧바로 나타난다(상태가 하나뿐이라 어긋날 수가 없다).
  /// [inPanel] — 좌측 필터 패널(흰 배경, 이미 여백이 있음) 안에 넣을 때.
  /// [trailing] — 같은 줄 오른쪽 끝에 함께 앉힐 위젯(보기 방식 선택기).
  Widget _buildEventQuickTimeBar({
    bool inPanel = false,
    Widget? middle,
    Widget? trailing,
  }) {
    return PlaceQuickTimeBar(
      filter: _eventFilter,
      night: inPanel ? false : _isNightMode,
      horizontalPadding: inPanel ? 0 : 16,
      middle: middle,
      trailing: trailing,
      onChanged: () => setState(() {}),
    );
  }

  // ── 장소대여 탭 ──────────────────────────────────────────────────────
  Widget _buildPlacePage() {
    // 🎪 이벤트를 켠 동안에만 공간 이벤트 정본을 구독한다(플레이스 탭과 같은
    // 규칙 — 그리기 직전 한 곳에서 맞춰 두면 어느 입구로 켜도 새지 않는다).
    _syncRentalEventIndexSub();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 지역 필터 + 보기 방식 + 돋보기 + 정렬 — 파티 탭 헤더·플레이스 탭
        // 퀵타임바와 같이 **한 줄**이다(왼쪽 필터, 오른쪽 끝은 공통 컨트롤 묶음).
        // 정렬 버튼은 장소대여에만 있다 — 정렬을 갖춘 목록이 여기뿐이다.
        _buildPlaceFilter(
          trailing: _listHeaderTrailing(
            viewModeSwitch: _placeViewModeButton(),
            searchActive: _placeSearchActive,
            sortButton: _placeSortButton(),
          ),
        ),
        // 장소 목록
        Expanded(child: _buildPlaceListContent()),
      ],
    );
  }

  // 장소 목록 부분만 분리 — 모바일(_buildPlacePage)과 데스크톱 가운데 패널이
  // 동일한 StreamBuilder/필터 로직을 그대로 공유한다. 지역 필터 UI(_buildPlaceFilter)는
  // 데스크톱에서는 좌측 패널로 옮겨가므로 이 메서드에는 포함하지 않는다.
  Widget _buildPlaceListContent({
    void Function(Map<String, dynamic> place, String placeId)? onCardTap,
  }) {
    return StreamBuilder<QuerySnapshot>(
      // isActive == false(숨김)로 바꾼 장소는 공개 목록/지도에서 보이면 안
      // 된다. ⚠️ 예전엔 여기서 .where('isActive', isEqualTo: true)로
      // Firestore 쪽에서 걸렀는데, Firestore의 등호 필터는 필드가 아예 없는
      // 문서를 무조건 제외한다 — isActive 필드가 없는(과거 데이터 등)
      // "실제로는 활성인" 장소까지 통째로 안 보이는 버그가 있었다("내 장소"
      // 화면은 hostId만으로 걸러 받아온 뒤 `!= false`로 판정해 이 문제가
      // 없었기 때문에 두 화면의 개수가 달라 보였다). 그래서 Firestore
      // 쿼리에서는 조건 없이 전부 받고, "내 장소"와 동일한 규칙(명시적으로
      // false인 것만 숨김)으로 클라이언트에서 걸러 정확히 일치시킨다.
      // 쿼리·판정 모두 [ListingSources]에만 있다 — 통합 지도도 같은 것을 쓴다.
      stream: ListingSources.places().snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF6FA0)),
          );
        }
        // Firestore 쿼리 오류를 조용히 삼키면 실제로는 등록된 장소가 있는데도
        // "등록된 장소가 없습니다"로 잘못 보인다 — 반드시 구분해서 보여준다.
        if (snap.hasError) {
          logFirestoreStreamError('PlaceList', snap.error, snap.stackTrace);
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.error_outline, size: 48, color: Colors.black26),
                  SizedBox(height: 16),
                  Text(
                    '장소 목록을 불러오지 못했어요.\n잠시 후 다시 시도해주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.black45),
                  ),
                ],
              ),
            ),
          );
        }
        // isActive가 명시적으로 false인 것만 숨김 — "내 장소" 화면(_MyPlaceList)의
        // 진행중/숨김 판정 규칙과 정확히 동일해야 두 화면의 개수가 일치한다.
        // 등록 최신순 — 같은 "등록 날짜" 안에서는 파티츄 전용 혜택이 있는
        // 장소를 앞으로 당긴다(장소대여는 모집 상태 개념이 없다).
        final visibleDocs =
            (snap.data?.docs ?? [])
                .where(
                  (d) => ListingSources.isRentalVisible(
                    d.data() as Map<String, dynamic>,
                  ),
                )
                .toList()
              ..sort(
                (a, b) => PartychuPerkRanking.compareNewestFirst(
                  a.data() as Map<String, dynamic>,
                  b.data() as Map<String, dynamic>,
                ),
              );
        final allDocs = visibleDocs;
        // 검색·지역·인원·상세검색 조건으로 먼저 거르고(기존 그대로),
        // 그 결과의 **순서만** 고른 정렬로 바꾼다.
        final docs = _applyPlaceSort(_applyPlaceFilter(allDocs));

        if (allDocs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text('🏠', style: TextStyle(fontSize: 56)),
                  SizedBox(height: 20),
                  Text(
                    '등록된 장소가 없습니다',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '파티룸, 루프탑, 바베큐장 등\n다양한 장소를 등록해보세요!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black38,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // 이용 날짜/시간 조건은 예약 현황을 읽어와야 판정할 수 있어서 결과가
        // 한 박자 늦게 온다 — 그동안 "없음"으로 보이지 않게 확인 중임을 알린다.
        if (docs.isEmpty && (_placeAvailabilityLoading || _placeModesLoading)) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Color(0xFFFF6FA0)),
                SizedBox(height: 16),
                Text(
                  '이용 가능한 장소를 확인하고 있어요...',
                  style: TextStyle(fontSize: 13, color: Colors.black45),
                ),
              ],
            ),
          );
        }

        if (docs.isEmpty) {
          final schedule = _placeFilter.availabilityRequest;
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🔍', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 16),
                  Text(
                    // 금액순은 고른 단위(₩/박·₩/시간)의 장소만 남기므로 0건의
                    // 이유가 검색어도 지역도 아닐 수 있다 — 먼저 알려주지
                    // 않으면 "검색이 고장 났나"로 읽힌다. 그렇다고 정렬이나
                    // 조건을 여기서 자동으로 되돌리지는 않는다(AND 유지).
                    _placeSortMode.limitsToUnit
                        ? '${_placeSortMode.unit!.label}당 요금을 받는 장소가 없어요.\n'
                              '다른 정렬을 고르거나 조건을 넓혀보세요.'
                        // 검색어가 걸려 있으면 그것이 0건의 가장 큰 이유다 —
                        // 지역/날짜 문구보다 먼저 알려준다.
                        : _placeSearch.query.isNotEmpty
                        ? '\'${_placeSearch.query}\' 검색 결과가 없어요.'
                        : schedule == null
                        ? '선택한 지역에 등록된 장소가 없어요.'
                        : '${PlaceFilter.formatDate(_placeFilter.useDate!)}'
                              '${_placeFilter.hasTimeRange ? ' ${_placeFilter.timeRangeLabel}' : ''}'
                              '에 이용할 수 있는 장소가 없어요.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: Colors.black45),
                  ),
                ],
              ),
            ),
          );
        }

        // 보기 방식은 목록 위 토글에서 고른다 — "작은 카드"는 지도 '이 근처
        // 파티'와 같은 가로형 카드 1열, "기본 카드"는 파티 기본 카드와 같은
        // 2열 그리드다. "큰 카드"는 파티 영상 크게 보기와 마찬가지로 전체화면
        // (PlaceFeedScreen)으로만 진입하므로 여기 분기가 없다.
        // 필터/정렬(docs)과 카드 탭 동작은 세 방식이 그대로 공유한다.
        _trackPlaceDocs(docs, PlaceCardSource.rental);
        if (_placeViewMode == PlaceViewMode.compact) {
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
            itemCount: docs.length,
            itemBuilder: (_, idx) {
              final doc = docs[idx];
              final data = doc.data() as Map<String, dynamic>;
              return PlaceCompactCard(
                key: ValueKey(doc.id),
                place: data,
                placeId: doc.id,
                source: PlaceCardSource.rental,
                availabilityLabel: _placeAvailabilityLabel(doc.id),
                onTap: onCardTap != null ? () => onCardTap(data, doc.id) : null,
              );
            },
          );
        }

        // 2열 그리드 (Row 쌍으로 구성)
        final rowCount = (docs.length / 2).ceil();
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
          itemCount: rowCount,
          itemBuilder: (_, rowIdx) {
            final leftDoc = docs[rowIdx * 2];
            final rightDoc = rowIdx * 2 + 1 < docs.length
                ? docs[rowIdx * 2 + 1]
                : null;
            final leftData = leftDoc.data() as Map<String, dynamic>;
            final rightData = rightDoc?.data() as Map<String, dynamic>?;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PlaceStandardCard(
                      key: ValueKey(leftDoc.id),
                      place: leftData,
                      placeId: leftDoc.id,
                      source: PlaceCardSource.rental,
                      availabilityLabel: _placeAvailabilityLabel(leftDoc.id),
                      onTap: onCardTap != null
                          ? () => onCardTap(leftData, leftDoc.id)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: rightDoc != null
                        ? PlaceStandardCard(
                            key: ValueKey(rightDoc.id),
                            place: rightData!,
                            placeId: rightDoc.id,
                            source: PlaceCardSource.rental,
                            availabilityLabel: _placeAvailabilityLabel(
                              rightDoc.id,
                            ),
                            onTap: onCardTap != null
                                ? () => onCardTap(rightData, rightDoc.id)
                                : null,
                          )
                        : const SizedBox(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // 플레이스·장소대여 목록 상단의 보기 방식 토글 — 작은/기본/큰 카드 3종.
  //
  // 예전에는 알약마다 "작은 화면/기본 화면" 글씨가 붙어 있었는데, 보기가 3개로
  /// **장소대여 데스크톱 가운데 패널 전용** 보기 방식 + 정렬 줄.
  ///
  /// 모바일은 지역 필터와 같은 줄에 넣는다([_buildPlaceFilter]의 trailing).
  /// 데스크톱은 지역 필터가 좌측 패널로 빠져 두 컨트롤이 붙어 있을 수 없어서,
  /// 목록 위에 이 줄 하나만 따로 얹는다(파티 탭 데스크톱도 같은 구조다).
  /// 장소대여 전용이므로 모바일과 같은 순환 버튼을 쓴다.
  Widget _buildPlaceViewModeToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [_placeViewModeButton(), _placeSortButton()],
      ),
    );
  }

  /// 장소대여 정렬 버튼 — 돋보기 바로 오른쪽. 기본순이 아니면 분홍 점이
  /// 찍히고, 툴팁에 지금 무엇으로 정렬돼 있는지 적힌다.
  Widget _placeSortButton() {
    return SortEntryIconButton(
      onTap: _openPlaceSortSheet,
      active: _placeSortMode != PlaceSortMode.defaultOrder,
      tooltip: '정렬 · ${_placeSortMode.label}',
    );
  }

  /// 파티 정렬 버튼 — 위 [_placeSortButton]과 **같은 위젯·같은 규칙**이다.
  /// 자리만 다르다(파티는 날짜 필터 바 오른쪽 끝, 장소대여는 돋보기 옆).
  Widget _partySortButton() {
    return SortEntryIconButton(
      onTap: _openSortSheet,
      active: _filter.sortMode != PartySortMode.defaultOrder,
      tooltip: '정렬 · ${_filter.sortMode.label}',
    );
  }

  /// 🛍️ 파티샵 목록의 보기 방식 **버튼 하나 + 메뉴** — 플레이스·장소대여·
  /// 파티와 **같은 위젯**([ViewModeMenuButton])이다. 다른 점은 큰 카드가
  /// 전체화면으로 가지 않고 목록 안에서 그려진다는 것 하나뿐이라, 여기에는
  /// 전체화면 분기가 없다.
  Widget _shopViewModeButton() {
    return ViewModeMenuButton(
      currentIcon: _shopViewMode.icon,
      label: '보기 방식 · ${_shopViewMode.label}',
      options: [
        for (final mode in PlaceViewMode.values)
          ViewModeOption(
            icon: mode.icon,
            label: mode.label,
            selected: _shopViewMode == mode,
            onTap: () {
              if (_shopViewMode == mode) return;
              mode.saveForShop();
              setState(() => _shopViewMode = mode);
            },
          ),
      ],
    );
  }

  /// 목록이 실제로 쓰는 보기 방식을 바꾼다 — **어디서 바꾸든 여기를 지난다**
  /// (보기 방식 메뉴 · 전체화면에서 고르고 나온 값 · 앱 시작 시 불러온 값).
  /// **setState 안에서만** 부른다.
  void _setPlaceViewMode(PlaceViewMode mode) {
    _placeViewMode = mode;
  }

  /// **플레이스·장소대여 탭**의 보기 방식 버튼 — 아이콘 하나, 누르면 그 자리에
  /// 붙는 메뉴에서 작은/기본/큰 셋 중 **직접 고른다**.
  ///
  /// ## 칸 셋이 아니라 버튼 하나인 이유
  ///
  /// 목록 위 한 줄에는 방문 조건·편의·서비스·돋보기(장소대여는 지역·정렬)까지
  /// 함께 앉는다. 세 칸 세그먼트가 그중 폭을 가장 많이 먹어서, 조건을 두어 개만
  /// 켜도 줄이 밀렸다. 그래서 줄에는 **지금 쓰는 보기 방식 아이콘 하나만** 둔다.
  ///
  /// ## 순환도 시트도 아니고 **버튼에 붙는 메뉴**인 이유
  ///
  /// 예전에는 누를 때마다 작은 → 기본 → 큰 → 작은으로 넘어가서 원하는 보기까지
  /// 두세 번을 눌러야 했고, 그 다음에는 화면 아래에서 시트가 올라왔는데 고작
  /// 셋 중 하나를 고르려고 화면 전체가 움직였다. 이제 누른 자리에 메뉴가
  /// 붙어서 셋이 한 번에 열리고, 하나를 고르면 곧바로 닫힌다
  /// ([ViewModeMenuButton] — 파티·파티샵 목록도 같은 위젯을 쓴다).
  ///
  /// 보기 방식 셋과 각각의 렌더링은 예전 그대로다 — 바뀐 것은 "고르는 방법"
  /// 뿐이고, 고르면 무슨 일이 일어나는지도 예전 경로 그대로다
  /// ([_selectPlaceViewMode]).
  Widget _placeViewModeButton() {
    // 버튼에 그리는 아이콘은 **지금 목록이 실제로 쓰는** 보기 방식이다.
    // 큰 카드는 전체화면으로 빠졌다가 닫히면 목록이 이전 모양으로 돌아오므로,
    // 이 값이 언제나 화면과 맞는다.
    final shown = _placeViewMode;
    return ViewModeMenuButton(
      currentIcon: shown.icon,
      label: '보기 방식 · ${shown.label}',
      options: [
        for (final mode in PlaceViewMode.values)
          ViewModeOption(
            icon: mode.icon,
            label: mode.label,
            selected: _placeViewMode == mode,
            onTap: () => _selectPlaceViewMode(mode),
          ),
      ],
    );
  }

  /// 메뉴에서 고른 보기 방식을 적용한다 — 판단은 예전 시트가 하던 것 그대로다.
  ///
  /// 큰 카드는 목록에 인라인으로 그리지 않고 곧바로 전체화면 피드로 진입한다
  /// (파티 영상 크게 보기와 동일) — 그래서 [_placeViewMode]는 large가 되지
  /// 않고, 버튼 아이콘도 큰 카드로 바뀌지 않는다.
  void _selectPlaceViewMode(PlaceViewMode mode) {
    if (mode == PlaceViewMode.large) {
      if (_lastPlaceDocs.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('표시할 목록이 없어요.')));
        return;
      }
      mode.save();
      _openPlaceFullscreen(_lastPlaceDocs, 0, _lastPlaceSource);
      return;
    }
    if (mode == _placeViewMode) return; // 이미 쓰고 있는 보기 — 그릴 것도 없다.
    mode.save();
    setState(() => _setPlaceViewMode(mode));
  }

  // ── 장소 지역 필터 UI (단일 버튼 → 바텀시트) ─────────────────────
  // 장소대여 지역 필터 — 시/도 하나를 통째로 고를 수 있는 "전체"까지 포함해
  // 최대 [RegionSelection.maxCount]개까지 중복 선택 가능하다. 선택값 규격과
  // 한도·토글 규칙은 상세검색 지역 필터와 같은 RegionSelection을 쓴다.
  static const _kMaxPlaceDistricts = RegionSelection.maxCount;

  // "서울 강남구" → "강남구", "전체"로 고른 시/도 하나만 있는 값(예: "서울")은
  // 그대로 두면 구/군 이름과 헷갈리니 "서울 전체"처럼 보여준다.
  String _placeDistrictLabel(String d) => RegionSelection.shortLabel(d);

  /// 장소대여 상단 필터 줄.
  ///
  /// [trailing]은 줄 **오른쪽 끝**에 붙는다 — 파티 탭 헤더·플레이스 탭
  /// 퀵타임바([_buildEventQuickTimeBar])와 같은 자리이고, 세 탭 모두 여기에
  /// 보기 방식 버튼([ViewModeMenuButton])을 넣는다. 예전에는 장소대여만
  /// 보기 방식이 지역선택 **아래 별도 줄**에 있어 이 탭만 한 줄 더 길었다.
  ///
  /// 데스크톱은 지역 필터가 좌측 패널로 빠지고 목록은 가운데 패널에 그려져
  /// 두 컨트롤이 붙어 있을 수 없다 — 그래서 그쪽은 trailing 없이 부르고,
  /// 보기 방식은 가운데 패널이 따로 얹는다([_buildPlaceViewModeToggle]).
  /// 장소대여 **대여유형** 빠른 선택 — 어떻게 빌리는지(전체/⏱ 시간제/🛏 숙박)와
  /// 어떤 곳인지(파티룸·펜션·…)를 한 시트에서 고른다.
  ///
  /// 새 상태를 만들지 않는다: 상세검색의 '예약 방식'·'장소 유형'과 **같은 두
  /// 칸**([PlaceFilter.reservationMode] / [PlaceFilter.placeTypes])을 고친다.
  /// 그래서 여기서 고른 것이 상세검색에도 그대로 보이고, 상세검색에서 바꾸면 이
  /// 버튼의 글자도 곧바로 따라간다. 목록을 거르는 판정도 예전 그대로
  /// [_applyPlaceFilter] 한 곳이다 — 대여 방식은 룸 문서가 정본인
  /// [placeReservationModes](시간제와 숙박을 모두 받는 장소는 어느 쪽을 골라도
  /// 남는다), 장소 유형은 [PlaceFilter.matchesPlaceTypes](고른 것 중 하나라도
  /// 해당하면 남는다). 두 축은 서로 AND로 걸린다.
  Future<void> _pickPlaceRentalType() async {
    final before = _placeRentalTypeSelection;
    final picked = await showPlaceRentalTypeSheet(context, selected: before);
    if (!mounted) return;
    if (picked.mode == before.mode &&
        setEquals(picked.placeTypes, before.placeTypes)) {
      return;
    }
    setState(() {
      _placeFilter.reservationMode = picked.mode;
      _placeFilter.placeTypes
        ..clear()
        ..addAll(picked.placeTypes);
    });
  }

  /// 지금 대여유형 버튼이 말하는 조건 — 정본은 언제나 [_placeFilter]다.
  PlaceRentalTypeSelection get _placeRentalTypeSelection =>
      PlaceRentalTypeSelection(
        mode: _placeFilter.reservationMode,
        placeTypes: _placeFilter.placeTypes,
      );

  /// 대여유형 버튼에 그리는 아이콘 — 시트/칩의 이모지(⏱ 🛏)와 같은 뜻을
  /// 아이콘 버튼 재질로 옮긴 것. 대여 방식을 고르지 않았으면 상세검색의
  /// '예약 방식' 항목과 같은 아이콘을 쓴다(장소 유형만 골랐을 때도 마찬가지 —
  /// 아이콘은 대여 방식의 것이고, 장소 유형은 버튼 글자가 말한다).
  IconData _placeReservationModeIcon(ReservationMode? mode) => switch (mode) {
    ReservationMode.hourly => Icons.schedule_rounded,
    ReservationMode.stay => Icons.hotel_rounded,
    _ => Icons.event_available_rounded,
  };

  /// 장소대여 인원 선택 — 플레이스 탭 퀵바와 **같은 시트·같은 판정**이다.
  Future<void> _pickPlaceCapacity() async {
    final picked = await showCapacityPickerSheet(
      context,
      selected: _placeFilter.minCapacity,
    );
    if (!mounted || picked == _placeFilter.minCapacity) return;
    setState(() => _placeFilter.minCapacity = picked);
  }

  Widget _buildPlaceFilter({Widget? trailing}) {
    // 상세검색에서 고른 지역도 같은 Set이라 여기에 그대로 나타난다.
    final hasFilter = _placeRegions.isNotEmpty;

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            // 좌우 16 — 파티 탭 헤더(fromLTRB(16, 8, 16, 8))·플레이스 탭
            // 퀵타임바(horizontalPadding: 16)와 같은 화면 여백.
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: LayoutBuilder(
              builder: (context, rowConstraints) {
                final width = rowConstraints.maxWidth;
                return _buildPlaceFilterRow(
                  hasFilter: hasFilter,
                  trailing: trailing,
                  modeLabel: _placeModeButtonLabel(width),
                  tight: width < _kPlaceRowTight,
                  ultraTight: width < _kPlaceRowUltraTight,
                );
              },
            ),
          ),
          // 🎪 이벤트 — 위 줄에 끼우지 않고 **자기 줄**을 쓴다. 위 줄은
          // 지역·대여유형·인원·보기방식·돋보기·정렬이 폭을 나눠 갖도록 값이
          // 맞춰져 있어(아래 _kPlaceRowFixed 주석), 칸을 하나 더 넣으면 좁은
          // 폰에서 그 예산이 깨진다.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                QuickFilterIconButton(
                  icon: Icons.celebration_rounded,
                  label: '이벤트',
                  active: _placeFilter.eventOnly,
                  onTap: () => setState(
                    () => _placeFilter.eventOnly = !_placeFilter.eventOnly,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
        ],
      ),
    );
  }

  // ── 장소대여 상단 줄의 폭 예산 ─────────────────────────────────────
  //
  // 이 줄에는 지역선택 + 대여유형 + 인원 + 보기방식 + 돋보기 + 정렬이 모두
  // 앉는다. 아래 수치는 **실제로 렌더링해 잰 값**이다(테스트 폰트 기준):
  //
  //   인원 38 · 보기방식 54 · 돋보기 48 · 정렬 48 · 사이 간격 8×4 = 32  → 220
  //   대여유형(글씨 있음) 87 · (아이콘만) 38
  //   지역선택(핀·글씨·화살표까지 다 보임) 118
  //
  // 지역선택 버튼은 남는 자리를 받는데(Expanded), 그 자리가 좁아져도 **글씨를
  // 자르지 않는다.** 예전에는 말줄임으로 욱여넣어 좁은 폰에서 '지…'가 됐다 —
  // 무슨 필터인지 읽을 수 없으면 그 칸은 없는 것과 같다. 지금은 핀 → 좌우여백
  // → 화살표 순으로 곁가지를 떼고, 그래도 모자라면 이름을 '지역선택' →
  // '지역'으로 통째로 바꾼다([RegionFilterFit]). 글자 폭은 하드코딩하지 않고
  // 그릴 때 쓰는 스타일 그대로 재므로, 기기 글꼴이 달라도 어긋나지 않는다.
  static const double _kPlaceRowFixed = 220;

  /// 지역선택 버튼에 남겨 둘 최소 폭 — 아이콘 + 글자 두어 자.
  static const double _kRegionButtonMin = 60;

  /// 이보다 좁은 줄은 **빠듯한 줄** — 버튼 사이 간격을 8 → 4로 줄인다.
  /// 흔한 360dp 폰(줄 폭 328)이 여기 든다: 지역 칩과 인원 값이 함께 떠 있으면
  /// 간격 8로는 2px이 넘쳤다(실제로 재 본 값).
  static const double _kPlaceRowTight = 340;

  /// 이보다 좁은 줄은 **아주 빠듯한 줄** — 인원 버튼의 값 글씨까지 접는다.
  /// 320~340dp짜리 작은 폰(줄 폭 288~308)이 여기 든다: 간격을 줄이는 것만으로는
  /// 7~27px이 모자라고, 인원 값 글씨(약 40)를 접어야 넘치지 않는다.
  ///
  /// 흔한 360dp 폰(줄 폭 328)은 여기 들지 않아 **예전 그대로 '5명'이 보인다** —
  /// 실제로 줄을 세워 폭을 320부터 768까지 훑어 확인한 경계다.
  static const double _kPlaceRowUltraTight = 320;

  /// 대여유형 버튼에 적을 글자 — 지역 버튼에 [_kRegionButtonMin]을 남기고
  /// 남는 폭에 **실제로 들어가는** 후보를 고른다(안 들어가면 null = 아이콘만).
  ///
  /// 예전에는 '대여유형' 한 가지 폭(87)을 상수로 박아 두고 들어가는지만 봤다.
  /// 이제 이 버튼의 글자는 고른 조건에 따라 길어지므로(장소 유형까지 요약한다),
  /// 그릴 글자를 그대로 재지 않으면 계산이 뜻을 잃는다.
  String? _placeModeButtonLabel(double rowWidth) => placeRentalTypeButtonLabel(
    selection: _placeRentalTypeSelection,
    maxWidth: rowWidth - _kPlaceRowFixed - _kRegionButtonMin,
  );

  /// [_buildPlaceFilter]의 줄 알맹이 — 줄 폭에 따라 달라지는 것은
  /// [modeLabel]과 [tight] 둘뿐이다.
  Widget _buildPlaceFilterRow({
    required bool hasFilter,
    required Widget? trailing,
    required String? modeLabel,
    required bool tight,
    required bool ultraTight,
  }) {
    final gap = tight ? 4.0 : 8.0;
    return Row(
      children: [
        // 왼쪽 그룹(지역선택 + 선택 칩 + 초기화)이 **남는 자리를 전부**
        // 차지한다. 오른쪽 trailing(보기 방식)은 이 Expanded 바깥의
        // 고정 폭 자식이라, 자리가 부족해도 먼저 자기 폭을 확보하고
        // 줄어들거나 밀려나지 않는다 — 부족분은 이 그룹 안에서만
        // 흡수된다(칩 목록이 가로 스크롤로 잘린다).
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 지역선택 버튼은 **고정**이다 — Flexible로 두면 칩
              // 목록(Expanded)과 남는 자리를 반씩 나눠 갖는 바람에,
              // 자리가 넉넉해도 라벨이 먼저 잘린다.
              //
              // 대신 "칩을 0으로 줄여도 모자란" 경우에만 버튼이 줄도록
              // 상한을 직접 계산해 건다. 이 상한이 없으면 좁은 화면
              // (5개 선택 시 약 359px 필요)에서 RenderFlex overflow가
              // 난다. 상한에 걸릴 때는 라벨이 말줄임될 뿐, 버튼이
              // 사라지거나 줄이 두 줄로 내려가지는 않는다.
              // 지역 버튼이 **먼저** 자리를 가져간다 — 필터명이 읽히지 않으면
              // 그 줄은 아무 의미가 없기 때문이다. 버튼 안의 것들을 단계로
              // 덜어내 남은 폭에 맞추고([RegionFilterFit]), 글자는 어떤
              // 단계에서도 말줄임하지 않는다.
              final fit = RegionFilterFit.resolve(
                maxWidth: constraints.maxWidth,
                count: hasFilter ? _placeRegions.length : 0,
              );
              final showRegionIcon = fit.showIcon;
              // 버튼이 쓰고 남은 자리 — 칩과 초기화가 여기서만 산다.
              final restRoom = constraints.maxWidth - fit.width;
              // 초기화(18 + 좌여백 6)와 칩 사이 간격(8)이 들어갈 때만 그린다.
              // 자리가 없으면 칩·초기화가 빠질 뿐, 줄이 넘치지는 않는다
              // (지역은 버튼을 다시 눌러 시트에서 지울 수 있다).
              final showReset = hasFilter && restRoom >= 24;
              final showChips = hasFilter && restRoom >= 24 + 8 + 8;
              return Row(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                    child: GestureDetector(
                      onTap: _showPlaceRegionSheet,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        // 좌우 여백도 줄어드는 단계에 들어 있다 — 글자를
                        // 자르기 전에 먼저 내주는 자리다.
                        padding: EdgeInsets.symmetric(
                          horizontal: fit.hPadding,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: hasFilter
                              ? const Color(0xFFFF6FA0)
                              : const Color(0xFFF5F5F7),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: hasFilter
                                ? const Color(0xFFFF6FA0)
                                : const Color(0xFFE0E0E0),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showRegionIcon) ...[
                              Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: hasFilter
                                    ? Colors.white
                                    : Colors.black54,
                              ),
                              const SizedBox(width: 4),
                            ],
                            // 필터명은 **절대 말줄임하지 않는다.** Flexible로
                            // 감싸 두면 자리가 모자랄 때 '지…'가 되는데,
                            // 그러면 무슨 필터인지 읽을 수 없다. 대신 폭에
                            // 맞춰 '지역선택 (2)' → '지역 (2)' → '지역'으로
                            // **덜어낸 뒤 통째로** 그린다([_regionButtonFit]).
                            Text(
                              fit.label,
                              maxLines: 1,
                              overflow: TextOverflow.visible,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: hasFilter
                                    ? Colors.white
                                    : Colors.black54,
                              ),
                            ),
                            if (fit.showChevron) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 16,
                                color: hasFilter
                                    ? Colors.white
                                    : Colors.black45,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 선택된 지역 칩 — 자리가 모자랄 때 **여기만** 줄어든다
                  // (Expanded + 가로 스크롤이라 폭이 0이 돼도 넘치지 않는다).
                  if (showChips) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 34,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: _placeRegions.map((d) {
                            final label = _placeDistrictLabel(d);
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: GestureDetector(
                                // 칩 삭제도 정본 Set을 고친다 — 상세검색을
                                // 다시 열면 지워진 상태 그대로 보인다.
                                onTap: () =>
                                    setState(() => _placeRegions.remove(d)),
                                child: Container(
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFE8F2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // 줄임은 **여기서만** 한다 — 필터명이
                                      // 아니라 고른 지역명이 길 때. 긴 이름
                                      // 하나가 줄을 다 먹지 않게 상한을 둔다.
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 84,
                                        ),
                                        child: Text(
                                          label,
                                          maxLines: 1,
                                          softWrap: false,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFFFF6FA0),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      const Icon(
                                        Icons.close,
                                        size: 12,
                                        color: Color(0xFFFF6FA0),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                  // 초기화 — 칩이 빠진 아주 좁은 줄에서도 **이것만은** 남긴다
                  // (지역이 걸려 있다는 표시이자 푸는 길).
                  if (showReset)
                    GestureDetector(
                      // 지역만 비운다 — 상세검색의 다른 조건(가격·인원 등)은
                      // 건드리지 않는다.
                      onTap: () => setState(() => _placeRegions.clear()),
                      child: const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.refresh,
                          size: 18,
                          color: Color(0xFFFF6FA0),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        // 🛏/⏱ 대여 유형 — 상세검색의 '예약 방식'과 **같은 한 칸**을
        // 고치는 지름길이다(_pickPlaceReservationMode). 셋을 나란히
        // 늘어놓지 않고 지금 값만 적힌 알약 하나로 두는 이유는 이 줄에
        // 지역·인원·보기방식·검색·정렬이 이미 함께 앉기 때문이다.
        SizedBox(width: gap),
        QuickFilterIconButton(
          icon: _placeReservationModeIcon(_placeFilter.reservationMode),
          // 고르지 않았을 때도 무엇을 고르는 버튼인지 적어 둔다 —
          // 아이콘만으로는 옆의 인원 버튼과 구별되지 않는다. 자리가 좁아지면
          // 글자를 자르는 대신 곁가지부터 뗀다('숙박 · 파티룸 외 2개' →
          // '숙박 · 파티룸' → '숙박' → '대여유형' → 아이콘만,
          // [placeRentalTypeButtonLabel]). 마지막 단계에서도 조건이 걸려 있으면
          // 버튼이 핑크로 채워져 그 사실은 남는다.
          label: modeLabel,
          active:
              _placeFilter.reservationMode != null ||
              _placeFilter.placeTypes.isNotEmpty,
          onTap: _pickPlaceRentalType,
        ),
        // 👥 인원 — 플레이스 탭 퀵바의 인원 버튼과 **같은 위젯·같은
        // 시트·같은 판정**이다. 보기 방식과 마찬가지로 Expanded 바깥의
        // 고정 폭 자식이라 지역 칩이 늘어나도 밀려나지 않는다.
        SizedBox(width: gap),
        QuickFilterIconButton(
          icon: Icons.people_alt_rounded,
          // 값 글씨는 **아주 빠듯한 줄에서만** 접는다(320dp 폰) — 대여유형과
          // 같은 규칙이고, 조건이 걸려 있다는 사실은 핑크로 채워진 것으로
          // 남는다. 흔한 폰에서는 예전 그대로 '5명'이 보인다.
          label: _placeFilter.minCapacity == null || ultraTight
              ? null
              : CapacityFilter.label(_placeFilter.minCapacity!),
          active: _placeFilter.minCapacity != null,
          onTap: _pickPlaceCapacity,
        ),
        // 보기 방식 — Expanded 바깥의 **고정 폭** 자식이라 지역을 몇 개
        // 고르든 오른쪽 끝에 그대로 붙어 있고 줄어들지 않는다.
        if (trailing != null) ...[SizedBox(width: gap), trailing],
      ],
    );
  }

  // ── 전국 지역 선택 바텀시트 ──────────────────────────────────────
  void _showPlaceRegionSheet() {
    // 시트 안에서는 임시 사본을 고치고, "확인"을 눌렀을 때만 정본에 반영한다
    // (닫기로 나가면 원래 선택이 그대로 남는다).
    final tempSelected = Set<String>.from(_placeRegions);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          height: MediaQuery.of(context).size.height * 0.78,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // 핸들
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 헤더
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 16, 4),
                child: Row(
                  children: [
                    const Text(
                      '지역 선택',
                      style: TextStyle(
                        fontFamily: 'SeoulHangang',
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        shadows: [
                          Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                          Shadow(
                            color: Colors.black87,
                            offset: Offset(-0.3, 0),
                          ),
                          Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                          Shadow(
                            color: Colors.black87,
                            offset: Offset(0, -0.3),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (tempSelected.isNotEmpty)
                      GestureDetector(
                        onTap: () => setSheet(() => tempSelected.clear()),
                        child: const Text(
                          '초기화',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFFFF6FA0),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    // 접힌 시/도에 골라둔 것까지 포함한 현재 선택 개수.
                    '지역 ${tempSelected.length}/$_kMaxPlaceDistricts · 중복 선택 가능',
                    style: const TextStyle(fontSize: 12, color: Colors.black38),
                  ),
                ),
              ),
              // 선택된 지역 칩
              if (tempSelected.isNotEmpty) ...[
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: tempSelected.map((d) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () => setSheet(() => tempSelected.remove(d)),
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6FA0),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _placeDistrictLabel(d),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.close,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const Divider(height: 1, color: Color(0xFFF0F0F0)),
              // 전국 시/도 4열 그리드 — 시/도를 누르면 같은 자리가 그 시/도의
              // 구·시·군 그리드로 바뀌고, ←로 돌아온다. 머리줄의 "전체"로
              // 시/도를 통째로 고를 수 있고, 같은 시/도 안에서 "전체"와 개별
              // 구/군이 겹치지 않게 정리하는 규칙까지 상세검색과 같은 위젯·같은
              // 로직을 쓴다.
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: RegionGridSelector(
                    selected: tempSelected,
                    maxCount: _kMaxPlaceDistricts,
                    onChanged: (_) => setSheet(() {}),
                  ),
                ),
              ),
              // 확인 버튼
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _placeRegions
                            ..clear()
                            ..addAll(tempSelected);
                        });
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6FA0),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        elevation: 0,
                      ),
                      child: Text(
                        // 지금 무엇이 적용되는지 버튼이 그대로 말해준다.
                        tempSelected.isEmpty
                            ? '지역 선택 안 함'
                            : '${tempSelected.length}개 지역 적용',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 플레이스 상세검색 필터 적용 ─────────────────────────────────────
  // 장소대여(_applyPlaceFilter)와 달리 비동기 조회가 전혀 없다 — 플레이스는
  // 예약이 아니라 **영업시간**을 묻는 것이고, 영업시간은 문서 안
  // (placeWeeklyHours)에 이미 들어 있어서 그 자리에서 판정할 수 있다.
  List<QueryDocumentSnapshot> _applyEventFilter(
    List<QueryDocumentSnapshot> docs,
  ) {
    // 검색어와 상세검색 조건은 AND — 파티 탭이 검색어·카테고리·상세검색을
    // 겹쳐 거는 방식과 같다.
    final query = _eventSearch.query;
    final now = DateTime.now();
    // 기타 두 축(편의 서비스·놀거리)을 뺀 조건 — 이 범위가 그 시트들의
    // 목록과 개수가 된다. 두 시트가 같은 범위를 쓰므로 "이 목록에서 골랐는데
    // 결과가 0건"이 되지 않는다.
    final withoutCustom = _eventFilter.copy()
      ..customAmenities.clear()
      ..customPlayItems.clear();
    final scope = <Map<String, dynamic>>[];
    final result = <QueryDocumentSnapshot>[];
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (!_matchesTextQuery(data, query)) continue;
      // 🎉 With파티는 문서 id로 파티 연결을 되짚으므로 id를 함께 넘긴다.
      if (withoutCustom.isActive &&
          !_matchesEventFilter(
            data,
            now,
            docId: doc.id,
            filter: withoutCustom,
          )) {
        continue;
      }
      scope.add(data);
      // 🎲 기타 놀거리도 같은 범위에서 고른 값이라 바로 옆에서 건다.
      if (!CustomPlayItems.matchesAny(data, _eventFilter.customPlayItems)) {
        continue;
      }
      if (!CustomAmenities.matchesAll(data, _eventFilter.customAmenities)) {
        continue;
      }
      result.add(doc);
    }
    _eventAmenityScope = scope;
    return result;
  }

  /// 지금 검색 범위의 기타 편의 서비스 목록(개수 포함).
  List<CustomAmenityEntry> get _customAmenityEntries =>
      CustomAmenities.catalogOf(_eventAmenityScope);

  /// 지금 검색 범위의 기타 놀거리 목록(개수 포함) — 같은 범위에서 만든다.
  List<CustomPlayItemEntry> get _customPlayItemEntries =>
      CustomPlayItems.catalogOf(_eventAmenityScope);

  /// [filter]를 주면 그 조건으로 판정한다 — 기타 목록을 만들 때 "기타만 뺀"
  /// 필터를 넘기는 용도다. 안 주면 지금 걸린 조건 그대로.
  bool _matchesEventFilter(
    Map<String, dynamic> data,
    DateTime now, {
    String? docId,
    EventFilter? filter,
  }) {
    final f = filter ?? _eventFilter;

    if (f.regions.isNotEmpty) {
      // '서울'(시/도 전체)과 '서울 강남구'(구까지) 두 형식을 모두 받는다 —
      // 장소대여와 같은 판정 함수라 두 탭의 지역 조건이 어긋나지 않는다.
      final address = (data['address'] as String?)?.isNotEmpty == true
          ? data['address'] as String
          : (data['roadAddress'] as String? ??
                data['location'] as String? ??
                '');
      if (!RegionSelection.matchesAnyAddress(address, f.regions)) return false;
    }

    // 대분류 · 소분류 · 빠른 특징 · 세부 속성 — 판정은 [EventFilter]가
    // 한 곳에서 한다. 목록·지도·상세검색이 같은 함수를 부르므로 화면마다
    // 조건이 갈릴 수 없다. 새 필드가 없는 옛 문서도 businessTypes·
    // themeTags·petPolicy·영업시간에서 값을 유도하므로 그대로 걸린다.
    if (!f.matchesDiscovery(
      data,
      docId: docId,
      partyIndex: _withPartyIndex,
      // 🎉 이벤트를 켠 동안에만 색인이 있다 — 없으면(아직 못 읽었으면)
      // 예전 미러 판정 그대로다([EventFilter.matchesDiscovery]).
      eventIndex: _placeEventIndex,
    )) {
      return false;
    }

    if (f.businessTypes.isNotEmpty) {
      final types = _eventBusinessTypes(data);
      if (!types.any(f.businessTypes.contains)) return false;
    }

    if (f.themeTags.isNotEmpty) {
      final tags = _placeThemeTags(data);
      if (!f.themeTags.any(tags.contains)) return false;
    }

    if (f.priceRanges.isNotEmpty) {
      final range = (data['priceRange'] as String?) ?? '';
      if (!f.priceRanges.contains(range)) return false;
    }

    // 인원 — 장소대여와 **같은 함수**로 판정한다. 인원을 입력하지 않은 곳은
    // 걸러지지 않는다(0 = "0명 수용"이 아니라 "모름").
    if (!CapacityFilter.matches(data, f.minCapacity)) return false;

    if (f.partychuPerkOnly && partychuPerkFrom(data) == null) return false;

    if (f.openNowOnly) {
      final hours = _eventWeeklyHours(data);
      if (hours == null) return false;
      if (data['isOpen24Hours'] != true &&
          hours.statusAt(now) != PlaceHoursStatus.open) {
        return false;
      }
    }

    // 방문 날짜/시간 — 서로 독립된 조건이다.
    // · 날짜만        → 그날 여는 곳
    // · 시간만        → 요일과 상관없이 그 시각(또는 시간대)에 여는 곳
    // · 날짜 + 시간   → 그 날짜의 그 시각(또는 시간대)에 여는 곳
    // · 둘 다 없음    → 이 조건 자체를 건너뛴다
    //
    // 날짜는 여러 날(최대 EventFilter.maxVisitDates)을 고를 수 있고, 그때는
    // **하루라도** 조건을 만족하면 통과다("금·토 중 아무 날이나 갈 수 있는 곳").
    final dates = f.visitDates;
    if (dates.isNotEmpty) {
      if (!dates.any((d) => _opensOn(data, d, f))) return false;
    } else if (f.hasTimeCondition && !_opensAtTimeAnyDay(data, f, now)) {
      return false;
    }

    return true;
  }

  /// 날짜 없이 시각·시간대만 고른 경우 — 플레이스는 예약이 아니라 **영업시간
  /// 패턴**을 묻는 것이라 요일을 특정하지 않는다. 한 주(오늘부터 7일)의 요일을
  /// 하나씩 대입해서 **하루라도** 그때 영업하면 통과다("밤 10시~새벽 3시에
  /// 여는 가게"를 찾는 용도). 판정 자체는 날짜를 고른 경우와 같은
  /// [_opensOn]을 그대로 쓰므로 두 경로의 기준이 갈라지지 않는다.
  bool _opensAtTimeAnyDay(
    Map<String, dynamic> data,
    EventFilter f,
    DateTime now,
  ) {
    if (data['isOpen24Hours'] == true) return true;
    final today = DateTime(now.year, now.month, now.day);
    for (var i = 0; i < DateTime.daysPerWeek; i++) {
      if (_opensOn(data, today.add(Duration(days: i)), f)) return true;
    }
    return false;
  }

  /// 그 날짜(그리고 골랐다면 그 시간대)에 문을 여는 곳인지.
  bool _opensOn(Map<String, dynamic> data, DateTime date, EventFilter f) {
    // 24시간 영업은 어떤 날짜·시간 조건에도 항상 걸린다.
    if (data['isOpen24Hours'] == true) return true;

    final hours = _eventWeeklyHours(data);
    // 운영시간을 아예 등록하지 않은 문서는 판정할 수 없다 — 날짜 조건을 건
    // 사용자에게는 "여는지 알 수 없는 곳"이므로 결과에서 뺀다.
    if (hours == null) return false;

    // 고른 시간을 이 날짜 위에 얹는다 — 날짜를 안 고른 검색에서는 호출부가
    // 요일을 바꿔가며 부르므로 f.visitWindow가 아니라 date 기준으로 만든다.
    final window = f.windowOn(date);
    final moment = f.momentOn(date);
    if (window == null && moment == null) {
      // 날짜만 고른 경우 — 그날 영업하기만 하면 된다.
      return hours.get(PlaceWeeklyHours.weekdayKeyOf(date))?.isClosed == false;
    }

    // 시간까지 고른 경우 — 자정을 넘길 수 있으므로 그날과 앞뒤 날의 영업
    // 구간을 모두 모아 겹침을 본다(22:00에 열어 다음 날 02:00에 닫는 가게가
    // "익일 01:00" 조건에 걸려야 한다). 자정에서 맞닿은 구간을 잇는 것까지
    // **정본 한 곳**이 한다 — 매장 이벤트의 영업중(전시간) 판정도 같은 함수를
    // 쓰므로([PlaceEventTime.intervalsOf]) 여기 복사본을 두면 두 판정이 갈라진다.
    final merged = hours.openSegmentsAround(date);
    if (merged.isEmpty) return false;

    // 시각 하나만 고른 경우(메인 화면 빠른 방문시간) — 그 순간 문이 열려 있으면
    // 통과다. 자정을 넘겨 영업하는 가게는 전날 구간이 새벽 시각을 덮으므로,
    // 위에서 앞뒤 날(-1/0/+1)을 함께 모아둔 것이 그대로 답이 된다.
    if (moment != null) {
      return merged.any(
        (s) => !s.start.isAfter(moment) && s.end.isAfter(moment),
      );
    }

    if (f.openMode == PlaceAvailabilityMode.partial) {
      // 일부라도 겹치면 통과.
      return merged.any(
        (s) => s.start.isBefore(window!.end) && s.end.isAfter(window.start),
      );
    }
    // 전체 시간 영업 — 고른 구간이 영업 구간 하나 안에 통째로 들어가야 한다
    // (구간이 끊겨 있으면 그 사이에 문을 닫는다는 뜻이라 통과시키지 않는다).
    return merged.any(
      (s) => !s.start.isAfter(window!.start) && !s.end.isBefore(window.end),
    );
  }

  /// 플레이스 문서의 업종 목록 — 다중 선택 'businessTypes', 단일
  /// 'businessType' 두 형식을 모두 받는다.
  List<String> _eventBusinessTypes(Map<String, dynamic> data) {
    final list = (data['businessTypes'] as List?)?.cast<String>();
    if (list != null && list.isNotEmpty) return list;
    final single = data['businessType'] as String?;
    return single != null && single.isNotEmpty ? [single] : const [];
  }

  /// 정본은 [PlaceWeeklyHours.fromPlaceDoc]다 — 이벤트 필터도 같은 함수로
  /// 영업시간을 읽으므로, 두 이름 중 하나만 읽는 자리가 생기지 않는다.
  PlaceWeeklyHours? _eventWeeklyHours(Map<String, dynamic> data) =>
      PlaceWeeklyHours.fromPlaceDoc(data);

  // ── 장소대여 필터 적용 ────────────────────────────────────────────
  // 지역은 상단 퀵 필터와 상세검색이 같은 [_placeFilter].regions를 쓰므로
  // 여기서 한 번만 걸린다 — 예전처럼 두 벌을 AND로 겹치지 않는다.
  List<QueryDocumentSnapshot> _applyPlaceFilter(
    List<QueryDocumentSnapshot> docs,
  ) {
    // 검색어를 먼저 걸러 두면 아래 이용 가능 여부 조회(예약 현황 읽기)도
    // 그만큼만 하게 된다 — 조건은 상세검색과 AND다.
    final query = _placeSearch.query;
    // 기타를 뺀 조건 — 이 범위가 기타 시트의 목록과 개수가 된다(0건 항목이
    // 자연히 빠진다). 플레이스 탭과 같은 방식이다.
    final withoutAmenities = _placeFilter.copy()..customAmenities.clear();
    final scope = <Map<String, dynamic>>[];
    final candidates = <QueryDocumentSnapshot>[];
    // 🎪 이벤트 조건 — 지금 보여줄 **공간 이벤트**가 있는 장소만 남긴다.
    // 규칙(색인이 정본, 못 읽었으면 아무것도 남기지 않음)은 판정 쪽에 있다
    // ([PlaceFilter.matchesEvent]) — 화면이 규칙을 따로 갖고 있지 않아야
    // 목록·테스트가 같은 답을 낸다.
    final eventIndex = _placeFilter.eventOnly ? _rentalEventIndex : null;
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      // 문서를 함께 넘긴다 — 영업중(전시간) 이벤트의 적용 시간이 그 장소의
      // 영업시간이라, 판정이 문서를 봐야 한다([PlaceEventIndex.allows]).
      if (!_placeFilter.matchesEvent(doc.id, eventIndex, doc: data)) continue;
      if (!_matchesTextQuery(data, query)) continue;
      if (!_matchesPlaceDetailFilter(data, withoutAmenities)) continue;
      scope.add(data);
      if (!CustomAmenities.matchesAll(data, _placeFilter.customAmenities)) {
        continue;
      }
      candidates.add(doc);
    }
    _placeAmenityScope = scope;

    // 예약 방식(시간제/숙박)도 장소 문서만 보고는 알 수 없다 — 정본이 룸
    // 문서라 이용 가능 판정과 **같은 룸 캐시**를 읽어 좁힌다. 조건을 고르지
    // 않았으면 조회 자체를 하지 않는다.
    final wanted = _placeFilter.reservationMode;
    var narrowed = candidates;
    if (wanted == null) {
      _placeModesKey = null;
      _placeModes = null;
      _placeModesLoading = false;
    } else {
      _ensurePlaceReservationModes(candidates);
      final modes = _placeModes;
      if (modes == null) return const [];
      // 판정은 공용 [placeMatchesReservationMode] 한 줄이다 — 룸을 아직 못
      // 읽은 장소(집합 없음)는 남기지 않는다.
      narrowed = candidates
          .where(
            (d) => placeMatchesReservationMode(modes[d.id] ?? const {}, wanted),
          )
          .toList();
    }

    // 이용 날짜/시간 조건은 "예약이 없는 것"을 묻는 조건이라 Firestore 쿼리로
    // 표현할 수 없다 — 다른 조건으로 좁힌 후보에 대해서만 룸·예약 슬롯을 읽어
    // 판정한다(PlaceAvailabilityService). 조회가 비동기라 결과가 올 때까지는
    // 목록 대신 "확인 중"을 보여준다(_placeAvailabilityLoading).
    final request = _placeFilter.availabilityRequest;
    if (request == null) {
      // 날짜 조건을 뺐으면 판정 상태도 함께 비운다 — 남겨두면 다음에 같은
      // 조건을 다시 골랐을 때 옛 결과가 잠깐 보이거나, 결과가 없을 때 "확인
      // 중" 화면이 잘못 뜬다.
      _placeAvailabilityKey = null;
      _placeAvailability = null;
      _placeAvailabilityLoading = false;
      return narrowed;
    }

    _ensurePlaceAvailability(request, narrowed);
    final matches = _placeAvailability;
    if (matches == null) return const [];
    return narrowed.where((d) => matches.containsKey(d.id)).toList();
  }

  /// 카드에 띄울 "고른 시간 중 실제 이용 가능한 시간" 문구. 날짜/시간 조건을
  /// 안 걸었거나 시간을 안 고른 경우에는 null이라 카드에서 줄이 빠진다.
  String? _placeAvailabilityLabel(String placeId) =>
      _placeAvailability?[placeId]?.label;

  // ── 이용 날짜/시간 판정 캐시 ──────────────────────────────────────────
  // 판정 자체는 PlaceAvailability(공용 모델)가 하고, 여기서는 "지금 화면의
  // 후보 + 지금 고른 날짜/시간/이용 조건"에 대한 결과를 들고 있기만 한다.

  /// 이용 가능으로 판정된 장소의 id → 판정 결과(이용 가능 구간 포함).
  /// null이면 아직 판정 전(조회 중).
  Map<String, PlaceAvailabilityMatch>? _placeAvailability;

  /// 마지막으로 판정한 조건 서명 — 후보 목록이나 날짜/시간이 바뀌면 다시 판정한다.
  String? _placeAvailabilityKey;

  bool _placeAvailabilityLoading = false;

  // ── 예약 방식 판정 캐시 ────────────────────────────────────────────
  // 이용 가능 판정과 같은 구조다 — 판정은 공용 [placeReservationModes]가
  // 하고, 여기서는 "지금 화면의 후보"에 대한 결과만 들고 있는다.

  /// placeId → 그 장소가 받는 예약 방식. null이면 아직 조회 중.
  Map<String, Set<ReservationMode>>? _placeModes;

  /// 마지막으로 조회한 후보 서명 — 후보가 바뀌면 다시 읽는다.
  String? _placeModesKey;

  bool _placeModesLoading = false;

  void _ensurePlaceReservationModes(List<QueryDocumentSnapshot> candidates) {
    final ids = candidates.map((d) => d.id).toList()..sort();
    final key = ids.join(',');
    if (key == _placeModesKey) return;

    _placeModesKey = key;
    _placeModes = null;
    _placeModesLoading = true;

    final places = [
      for (final doc in candidates)
        (id: doc.id, data: doc.data() as Map<String, dynamic>),
    ];
    // build 도중이므로 setState는 프레임이 끝난 뒤에 부른다.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final result = await PlaceAvailabilityService.reservationModesOf(places);
      if (!mounted || _placeModesKey != key) return;
      setState(() {
        _placeModes = result;
        _placeModesLoading = false;
      });
    });
  }

  void _ensurePlaceAvailability(
    PlaceAvailabilityRequest request,
    List<QueryDocumentSnapshot> candidates,
  ) {
    final ids = candidates.map((d) => d.id).toList()..sort();
    final key = '${request.signature}|${ids.join(',')}';
    if (key == _placeAvailabilityKey) return;

    _placeAvailabilityKey = key;
    _placeAvailability = null;
    _placeAvailabilityLoading = true;

    final places = [
      for (final doc in candidates)
        (id: doc.id, data: doc.data() as Map<String, dynamic>),
    ];
    // build 도중이므로 setState는 프레임이 끝난 뒤에 부른다.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final result = await PlaceAvailabilityService.availablePlaces(
        places: places,
        request: request,
      );
      if (!mounted || _placeAvailabilityKey != key) return;
      setState(() {
        _placeAvailability = result;
        _placeAvailabilityLoading = false;
      });
    });
  }

  bool _matchesPlaceDetailFilter(
    Map<String, dynamic> data,
    PlaceFilter filter,
  ) {
    if (filter.regions.isNotEmpty) {
      final address = (data['address'] as String? ?? '');
      // '서울'(시/도 전체)과 '서울 강남구'(구까지 지정) 두 형식을 모두 받는다.
      if (!RegionSelection.matchesAnyAddress(address, filter.regions)) {
        return false;
      }
    }
    // 🏠 장소 유형 — 고른 것 중 하나라도 가지면 통과(OR). 규칙과 저장 필드
    // 해석(`types` 정본 / 옛 `type` 하위호환)은 판정 쪽에 있다
    // ([PlaceFilter.matchesPlaceTypes]) — 목록 위 대여유형 시트와 상세검색이
    // 같은 한 칸을 고치므로, 규칙도 한 곳에만 있어야 갈리지 않는다.
    if (!filter.matchesPlaceTypes(data)) return false;
    if (filter.facilities.isNotEmpty) {
      final facilities =
          (data['commonFacilities'] as List?)?.cast<String>() ?? [];
      // 정식 편의시설은 예전 그대로 OR — 하나라도 있으면 걸린다.
      if (!filter.facilities.any((f) => facilities.contains(f))) return false;
    }
    // 기타 편의 서비스는 **별도 축**이다. 필드도 규칙도 위와 섞지 않는다 —
    // 판정은 플레이스 탭과 **같은 함수**를 써서 두 탭의 결합 규칙(AND)이
    // 갈릴 수 없게 한다.
    if (!CustomAmenities.matchesAll(data, filter.customAmenities)) {
      return false;
    }
    if (filter.petFriendlyOnly) {
      final pet = data['petPolicy'] is Map
          ? PetPolicy.fromMap(
              Map<String, dynamic>.from(data['petPolicy'] as Map),
            )
          : PetPolicy.empty();
      if (!pet.isAllowed) return false;
    }
    if (filter.outsideFoodOnly) {
      // 등록 화면이 facilityOptions의 outsideFood 그룹에 저장한 값을 본다.
      // 라벨은 카탈로그 상수를 그대로 쓰므로 문구가 갈려 매칭이 끊길 일이 없다.
      final options = data['facilityOptions'] is Map
          ? PlaceFacilityOptions.fromMap(
              Map<String, dynamic>.from(data['facilityOptions'] as Map),
            )
          : PlaceFacilityOptions.empty();
      if (!options.isSelected(
        PlaceFacilityCatalog.outsideFood.key,
        PlaceFacilityCatalog.outsideFoodAllowedLabel,
      )) {
        return false;
      }
    }
    if (filter.priceRanges.isNotEmpty) {
      // 가격 문의 공간은 금액을 모른다 — 어느 가격대에도 넣지 않는다
      // (0원으로 읽혀 최저 가격대에 걸리면 안 된다).
      if (RoomPriceType.of(data) == RoomPriceType.inquiry) return false;
      final price = (data['pricePerHour'] as num?)?.toInt() ?? 0;
      if (!filter.priceRanges.any((r) => _matchesPlacePriceRange(price, r))) {
        return false;
      }
    }
    // 인원 — 플레이스 탭과 같은 함수. 아래 capacityRanges("10~20명" 구간)와는
    // 묻는 것이 달라 둘 다 걸리면 AND로 함께 좁힌다.
    if (!CapacityFilter.matches(data, filter.minCapacity)) return false;
    if (filter.capacityRanges.isNotEmpty) {
      final capacity = (data['capacityMax'] as num?)?.toInt() ?? 0;
      if (!filter.capacityRanges.any(
        (r) => _matchesPlaceCapacityRange(capacity, r),
      )) {
        return false;
      }
    }
    return true;
  }

  bool _matchesPlacePriceRange(int price, String range) {
    switch (range) {
      case '3만원 이하':
        return price > 0 && price <= 30000;
      case '3~5만원':
        return price > 30000 && price <= 50000;
      case '5~10만원':
        return price > 50000 && price <= 100000;
      case '10~20만원':
        return price > 100000 && price <= 200000;
      case '20만원 이상':
        return price > 200000;
      default:
        return true;
    }
  }

  bool _matchesPlaceCapacityRange(int capacity, String range) {
    switch (range) {
      case '10명 이하':
        return capacity > 0 && capacity <= 10;
      case '10~20명':
        return capacity > 10 && capacity <= 20;
      case '20~50명':
        return capacity > 20 && capacity <= 50;
      case '50~100명':
        return capacity > 50 && capacity <= 100;
      case '100명 이상':
        return capacity > 100;
      default:
        return true;
    }
  }

  // ── 파티샵 상세검색 필터 적용 ───────────────────────────────────────
  List<QueryDocumentSnapshot> _applyShopFilter(
    List<QueryDocumentSnapshot> docs,
  ) {
    final query = _shopSearch.query;
    if (!_shopFilter.isActive && query.isEmpty) return docs;
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      if (!_matchesTextQuery(data, query)) return false;
      if (!_shopFilter.isActive) return true;

      if (_shopFilter.regions.isNotEmpty) {
        final location =
            (data['location'] as String? ?? '') +
            (data['address'] as String? ?? '');
        if (!_shopFilter.regions.any((r) => location.contains(r))) return false;
      }
      if (_shopFilter.categories.isNotEmpty) {
        final categories = (data['categories'] as List?)?.cast<String>() ?? [];
        if (!_shopFilter.categories.any((c) => categories.contains(c)))
          return false;
      }
      if (_shopFilter.priceRanges.isNotEmpty) {
        final priceFrom = (data['priceFrom'] as num?)?.toInt() ?? 0;
        if (!_shopFilter.priceRanges.any(
          (r) => _matchesShopPriceRange(priceFrom, r),
        )) {
          return false;
        }
      }
      if (_shopFilter.deliveryAvailable) {
        final opts = (data['deliveryOptions'] as List?)?.cast<String>() ?? [];
        if (!opts.contains('delivery')) return false;
      }
      if (_shopFilter.pickupAvailable) {
        final opts = (data['deliveryOptions'] as List?)?.cast<String>() ?? [];
        if (!opts.contains('pickup')) return false;
      }
      if (_shopFilter.discountOnly) {
        if (data['hasDiscount'] != true) return false;
      }
      if (_shopFilter.couponOnly) {
        if (data['hasCoupon'] != true) return false;
      }
      if (_shopFilter.inStockOnly) {
        if (data['hasStock'] != true) return false;
      }
      return true;
    }).toList();
  }

  bool _matchesShopPriceRange(int price, String range) {
    switch (range) {
      case '1만원 이하':
        return price > 0 && price <= 10000;
      case '1~3만원':
        return price > 10000 && price <= 30000;
      case '3~5만원':
        return price > 30000 && price <= 50000;
      case '5~10만원':
        return price > 50000 && price <= 100000;
      case '10만원 이상':
        return price > 100000;
      default:
        return true;
    }
  }

  // ── 파트너(파티크루) 상세검색 필터 적용 ───────────────────────────
  List<QueryDocumentSnapshot> _applyCrewFilter(
    List<QueryDocumentSnapshot> docs,
  ) {
    final query = _crewSearch.query;
    if (!_crewFilter.isActive && query.isEmpty) return docs;
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      if (!_matchesTextQuery(data, query)) return false;
      if (!_crewFilter.isActive) return true;

      if (_crewFilter.regions.isNotEmpty) {
        final regionsRaw = data['regions'];
        final regions = (regionsRaw is List && regionsRaw.isNotEmpty)
            ? regionsRaw.cast<String>()
            : [
                if ((data['region'] as String? ?? '').isNotEmpty)
                  data['region'] as String,
              ];
        if (!_crewFilter.regions.any((r) => regions.contains(r))) return false;
      }
      if (_crewFilter.roles.isNotEmpty) {
        final rolesRaw = data['roles'];
        final roles = (rolesRaw is List && rolesRaw.isNotEmpty)
            ? rolesRaw.cast<String>()
            : [
                if ((data['role'] as String? ?? '').isNotEmpty)
                  data['role'] as String,
              ];
        if (!_crewFilter.roles.any(
          (r) => roles.any((role) => role.contains(r)),
        )) {
          return false;
        }
      }
      if (_crewFilter.payTypes.isNotEmpty) {
        final payType = data['payType'] as String? ?? '협의';
        final bucket = payType == '협의'
            ? '협의'
            : payType == '무료'
            ? '무료'
            : '유료';
        if (!_crewFilter.payTypes.contains(bucket)) return false;
      }
      if (_crewFilter.recruitCounts.isNotEmpty) {
        final count = (data['recruitCount'] as num?)?.toInt() ?? 0;
        if (!_crewFilter.recruitCounts.any(
          (r) => _matchesRecruitCount(count, r),
        )) {
          return false;
        }
      }
      if (_crewFilter.beginnerFriendly) {
        if (data['beginnerFriendly'] != true) return false;
      }
      if (_crewFilter.experiencedPreferred) {
        if (data['experiencedPreferred'] != true) return false;
      }
      return true;
    }).toList();
  }

  bool _matchesRecruitCount(int count, String range) {
    switch (range) {
      case '1명':
        return count == 1;
      case '2~3명':
        return count >= 2 && count <= 3;
      case '4~5명':
        return count >= 4 && count <= 5;
      case '6명 이상':
        return count >= 6;
      default:
        return true;
    }
  }

  // ── 파티 탭: 빠른 필터 / 카드 ────────────────────────────────────
  //
  // 목록 위 한 줄은 **날짜 · 시간 · 인원** 세 버튼이 전부다(그 오른쪽 끝은
  // 정렬). 예전에는 여기에 전체/오늘/내일/이번 주/이번 주말 날짜 탭이
  // 늘어서 있었는데, 날짜밖에 못 고르면서 줄을 통째로 차지했고 상세검색과
  // 다른 상태를 따로 들고 있었다.
  //
  // 세 버튼은 플레이스 탭의 빠른 조건 줄([PlaceQuickTimeBar])과 **같은
  // 위젯**([QuickFilterIconButton])이고, 고르는 시트도 그쪽이 쓰던 것을
  // 그대로 쓴다(달력·시간·규모). 상태는 상세검색과 같은 [_filter] 하나다 —
  // 여기서 고른 값이 상세검색에 그대로 보이고, 반대도 마찬가지다.
  //
  // 밤 모드는 같은 버튼을 다크 글래스 재질로만 바꿔(night: true) 검정 네온
  // 바 안에 앉힌다. 낮 모드는 배경 없이 버튼만 떠 있다.
  //
  // 📅를 누르면 달력이 바로 뜨지 않는다 — 버튼 바로 밑에 **날짜 빠른선택
  // 줄**([QuickDatePane])이 그 자리에서 펼쳐지고(오늘/내일/모레 · 날짜 선택),
  // '날짜 선택'을 눌렀을 때만 달력 바텀시트가 열린다. 플레이스 탭이 쓰던 줄을
  // 그대로 쓰므로 두 탭의 날짜 입구가 같은 모양·같은 순서다.
  Widget _buildCategorySection({bool withCapacity = true}) {
    final children = _partyQuickFilterChildren(withCapacity: withCapacity);
    final bar = !_isNightMode
        ? SizedBox(
            height: _kPartyQuickBarHeight,
            child: Row(children: children),
          )
        : Container(
            height: _kPartyQuickBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_kPartyQuickBarHeight / 2),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A1A1A), Color(0xFF111111)],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(children: children),
          );
    if (!_partyDatePaneOpen) return bar;
    // 펼쳐진 줄은 팝업이 아니라 바 바로 밑에 붙는 인라인 영역이고, 접으면
    // 위젯 자체가 사라져 높이가 그대로 돌아온다(플레이스 탭과 같은 여백).
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar,
        Padding(
          padding: const EdgeInsets.only(top: 7, bottom: 1),
          child: QuickDatePane(
            selected: _filter.selectedDates,
            onToggleDate: _togglePartyDate,
            onPickCalendar: _pickPartyDate,
            onClear: _clearPartyDates,
            night: _isNightMode,
          ),
        ),
      ],
    );
  }

  /// 📅를 눌렀을 때 날짜 빠른선택 줄이 펼쳐져 있는가 — 한 번 더 누르면 접힌다.
  bool _partyDatePaneOpen = false;

  /// 검정 네온 바(밤)와 파스텔 줄(낮)이 같은 높이를 쓰도록 — 두 모드를 오갈 때
  /// 상단 레이아웃이 흔들리지 않는다.
  ///
  /// **버튼(32)보다 위아래 2px씩만 큰 36**이다. 예전 42는 버튼 둘레에 5px씩을
  /// 남겼고, 그 윗쪽 5px이 제목과 버튼 사이의 빈 띠에 그대로 더해졌다.
  /// 버튼 크기는 그대로다(32) — 줄어든 것은 바가 남기던 여백뿐이다.
  static const double _kPartyQuickBarHeight = 36.0;

  /// [ 날짜 ][ 시간 ][ 인원 ] … [ 정렬 ] — 낮/밤이 같은 순서를 공유한다.
  /// [ 날짜 ][ 시간 ]([ 인원 ]) … [ 정렬 ]
  ///
  /// [withCapacity]가 false면 👥 인원만 빠진다 — 이벤트에는 모집 인원이라는
  /// 개념 자체가 없기 때문이다(날짜·시간은 뜻이 그대로 있다). 위젯도 시트도
  /// 파티가 쓰던 것을 그대로 쓰므로 두 칸의 UX가 갈라지지 않는다.
  List<Widget> _partyQuickFilterChildren({bool withCapacity = true}) {
    final night = _isNightMode;
    return [
      QuickFilterIconButton(
        icon: Icons.calendar_today_rounded,
        // 고른 날 수를 배지로 — 3일을 고르면 📅에 작은 3이 붙는다
        // (플레이스 탭과 같은 규칙).
        badge: _filter.selectedDates.isEmpty
            ? null
            : '${_filter.selectedDates.length}',
        label: _partyDateLabel(),
        active: _filter.selectedDates.isNotEmpty,
        opened: _partyDatePaneOpen,
        night: night,
        // 달력이 아니라 빠른선택 줄을 펼친다(달력은 그 줄의 '날짜 선택').
        onTap: () => setState(() => _partyDatePaneOpen = !_partyDatePaneOpen),
      ),
      const SizedBox(width: 6),
      QuickFilterIconButton(
        icon: Icons.schedule_rounded,
        label: _partyTimeLabel(),
        active: PartyTimeFilter.isActive(
          _filter.timeOfDayStart,
          _filter.timeOfDayEnd,
        ),
        night: night,
        onTap: _pickPartyTime,
      ),
      if (withCapacity) ...[
        const SizedBox(width: 6),
        QuickFilterIconButton(
          icon: Icons.groups_rounded,
          label: _filter.partyScale == null
              ? null
              : PartyScaleFilter.label(_filter.partyScale!),
          active: _filter.partyScale != null,
          night: night,
          onTap: _pickPartyScale,
        ),
      ],
      const Spacer(),
      if (night) _buildNeonBarDivider(),
      SizedBox(height: _kPartyQuickBarHeight, child: _partySortButton()),
    ];
  }

  /// 날짜 버튼에 적는 값 — '8/30', 여러 날이면 첫 날 하나만(개수는 배지가
  /// 말한다). 고른 날짜가 없으면 글씨 없이 아이콘만.
  String? _partyDateLabel() {
    final days = _filter.selectedDatesSorted;
    if (days.isEmpty) return null;
    final d = days.first;
    return '${d.month}/${d.day}';
  }

  /// 시간 버튼에 적는 값 — 지정 시간은 '19:00', 지정 구간은 '18:00–22:00'.
  String? _partyTimeLabel() {
    final s = _filter.timeOfDayStart;
    final e = _filter.timeOfDayEnd;
    String hhmm(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    if (s != null && e == null) return hhmm(s);
    if (s == null && e != null) return '~${hhmm(e)}';
    if (s != null && e != null) return '${hhmm(s)}–${hhmm(e)}';
    return null;
  }

  /// 빠른선택 줄에서 날짜 하나를 켜고 끈다 — 여러 날을 고르는 중이므로 여기서는
  /// 줄을 접지 않는다(플레이스 탭과 같은 규칙). 이미 최대 개수를 골랐으면
  /// [PartyFilter.toggleDate]가 아무것도 바꾸지 않고 false를 주므로, 그때만
  /// 안내를 띄운다.
  void _togglePartyDate(DateTime date) {
    var changed = false;
    setState(() => changed = _filter.toggleDate(date));
    if (changed) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text(
            '날짜는 최대 ${PartyFilter.maxSelectedDates}일까지 고를 수 있어요.',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
  }

  /// '초기화' — 날짜 조건만 비우고 줄을 접는다. 마지막 날짜가 사라지므로 그
  /// 날짜에 딸려 있던 시간 범위도 함께 지운다([PartyFilter.toggleDate]와 같은
  /// 규칙).
  void _clearPartyDates() {
    setState(() {
      _filter.selectedDates.clear();
      _filter.startTime = null;
      _filter.endTime = null;
      _partyDatePaneOpen = false;
    });
  }

  /// 날짜 — 플레이스 탭과 **같은 한국식 달력**(일요일·공휴일 빨강, 토요일
  /// 파랑)이다. 빠른선택 줄의 '날짜 선택'에서만 열린다. 고른 날짜는 상세검색이
  /// 쓰는 [PartyFilter.selectedDates] 그대로 들어가므로 날짜 판정은 예전과
  /// 완전히 같다.
  Future<void> _pickPartyDate() async {
    final today = PartyFilter.dateOnly(DateTime.now());
    final picked = await showKoreanCalendarSheet(
      context,
      selected: _filter.selectedDates,
      firstDate: today,
      lastDate: KoreanHolidays.clampToSupported(
        DateTime(today.year + 1, today.month, today.day),
        notBefore: today,
      ),
      maxCount: PartyFilter.maxSelectedDates,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _filter.selectedDates = {...picked};
      // 마지막 날짜를 지우면 그 날짜에 딸려 있던 시간 범위도 함께 사라진다
      // (PartyFilter.toggleDate와 같은 규칙).
      if (_filter.selectedDates.isEmpty) {
        _filter.startTime = null;
        _filter.endTime = null;
      }
      // 달력에서 확인을 누르면 고르기가 끝난 것이므로 줄도 함께 접는다.
      _partyDatePaneOpen = false;
    });
  }

  /// 시간 — 플레이스 탭과 **같은 시트**([showVisitTimePicker])다. 시트 안에서
  /// '지정 시간'과 '지정 구간' 중 하나를 고르고, 30분 단위 휠로 시각을 돌린다.
  ///
  /// 돌아온 값은 상세검색과 같은 칸([PartyFilter.timeOfDayStart]/[timeOfDayEnd])
  /// 에 담기고, 끝이 없으면 지정 시간·있으면 지정 구간이 된다
  /// ([PartyTimeFilter]가 그 규약으로 판정한다).
  Future<void> _pickPartyTime() async {
    final picked = await showVisitTimePicker(
      context,
      start: _filter.timeOfDayStart,
      end: _filter.timeOfDayEnd,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _filter.timeOfDayStart = picked.start;
      _filter.timeOfDayEnd = picked.end;
    });
  }

  /// 인원 — **파티가 모으는 총 정원** 구간이다(내가 신청할 인원이 아니다).
  /// 상세검색의 '파티 규모'와 같은 칸([PartyFilter.partyScale])을 고친다.
  Future<void> _pickPartyScale() async {
    final picked = await showPartyScalePickerSheet(
      context,
      selected: _filter.partyScale,
    );
    if (!mounted || picked == _filter.partyScale) return;
    setState(() => _filter.partyScale = picked);
  }

  Widget _buildNeonBarDivider() {
    return Container(
      width: 1,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: Colors.white.withValues(alpha: 0.14),
    );
  }

  Widget _buildActiveFilterChips() {
    if (!_filter.isActive) return const SizedBox.shrink();
    final entries = _filter.selectedEntries;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ...entries.map(
            (e) => Chip(
              label: Text(e.value, style: const TextStyle(fontSize: 12)),
              backgroundColor: const Color(0xFFFFE4ED),
              deleteIcon: const Icon(Icons.close, size: 14),
              onDeleted: () =>
                  setState(() => _filter.removeValue(e.key, e.value)),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          ActionChip(
            label: const Text(
              '전체 초기화',
              style: TextStyle(fontSize: 12, color: Colors.red),
            ),
            backgroundColor: Colors.white,
            side: const BorderSide(color: Colors.red),
            onPressed: () => setState(
              () => _filter = PartyFilter(sortMode: _filter.sortMode),
            ),
          ),
        ],
      ),
    );
  }

  // ── 검색 로직 ─────────────────────────────────────────────────────
  //
  // 파티 검색어 매칭의 정본은 [partySearchMatches] 하나다 — 화면 없이
  // 시험할 수 있도록 모델로 뺐다(`test/party_search_test.dart`).
  // 검색창 하나가 제목·장소·키워드·**태그**를 함께 찾는다.
  bool _matchesSearch(Map<String, dynamic> data, String query) =>
      partySearchMatches(data, query);

  /// 파티 외 탭(플레이스/장소대여/파티샵/파트너)의 검색어 매칭.
  ///
  /// 판정 규칙은 파티의 [_matchesSearch]와 같다(대소문자 무시, 앞의 '#' 제거,
  /// 부분 일치). 다만 컬렉션마다 제목·주소 필드 이름이 제각각(name/title,
  /// address/roadAddress/location …)이라, 탭마다 함수를 따로 두는 대신
  /// **후보 필드를 전부 훑는** 한 벌로 네 탭이 공유한다.
  static bool _matchesTextQuery(Map<String, dynamic> data, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase().replaceFirst('#', '');
    const textFields = [
      'name',
      'title',
      'description',
      'intro',
      'address',
      'roadAddress',
      'location',
      'region',
      'type',
      'category',
      'role',
      'hostName',
    ];
    for (final field in textFields) {
      final value = data[field];
      if (value is String && value.toLowerCase().contains(q)) return true;
    }
    const listFields = [
      'themeTags',
      'tags',
      'categories',
      'businessTypes',
      'placeTypes',
      'facilities',
      // 장소대여 등록 화면이 실제로 쓰는 필드 — 옛 'facilities'만 훑고 있어
      // '주차'·'수영장'처럼 화면에 적힌 시설명으로 검색해도 안 나왔다.
      'commonFacilities',
      'regions',
      'roles',
    ];
    for (final field in listFields) {
      final value = data[field];
      if (value is List &&
          value.any((e) => e is String && e.toLowerCase().contains(q))) {
        return true;
      }
    }
    // 특징 태그는 **화면 표기로도** 찾을 수 있어야 한다 — 저장값은 '이벤트'인데
    // 사용자가 보는 문구는 '이벤트 진행중'이라, 위 루프(저장값 대조)만으로는
    // 화면에 적힌 그대로 검색했을 때 아무것도 안 나온다.
    final themeTags = (data['themeTags'] as List?)?.cast<String>();
    if (themeTags != null &&
        themeTags.any(
          (t) =>
              ListingConstants.placeThemeTagLabel(t).toLowerCase().contains(q),
        )) {
      return true;
    }
    // 대분류도 **화면에 적힌 그대로** 찾을 수 있어야 한다 — 저장값과 부르는
    // 이름이 다른 칸이 있다('체험·클래스' → '체험/클래스', '맛집' → '푸드').
    // 저장값·화면 이름·짧은 표기·옛 이름을 한 줄로 훑는다.
    final category = PlaceTaxonomy.categoryOf(data);
    if (category != null) {
      final c = PlaceTaxonomy.byLabel(category);
      final names = <String>[
        category,
        if (c != null) ...[c.displayName, c.shortLabel, ...c.aliases],
      ];
      if (names.any((n) => n.toLowerCase().contains(q))) return true;
    }
    // 이벤트 소분류도 검색 대상 — 상세에 보이는 문구다(없는 문서는 건너뛴다).
    final subtype = data['eventSubtype'];
    if (subtype is String && subtype.toLowerCase().contains(q)) return true;
    return false;
  }

  // 검색 중일 때: 제목(0) → 유형/분위기(1) → 태그/설명(2) 우선순위 정렬
  List<QueryDocumentSnapshot> _applySearchSort(
    List<QueryDocumentSnapshot> docs,
  ) {
    if (_searchQuery.isEmpty) return docs;
    final q = _searchQuery.toLowerCase().replaceFirst('#', '');
    return List.of(docs)..sort((a, b) {
      final ad = a.data() as Map<String, dynamic>;
      final bd = b.data() as Map<String, dynamic>;
      return PartychuPerkRanking.compare(
        ad,
        bd,
        // 검색 관련도 등급이 같을 때만 혜택 게시물이 앞선다 — 관련도가
        // 다르면 언제나 더 잘 맞는 결과가 위다.
        group: (x, y) => _searchPriority(x, q).compareTo(_searchPriority(y, q)),
        boostable: _perkBoostable,
      );
    });
  }

  int _searchPriority(Map<String, dynamic> d, String q) {
    if ((d['title'] as String? ?? '').toLowerCase().contains(q)) return 0;
    final types = (d['partyTypes'] as List?)?.cast<String>() ?? [];
    final vibes = (d['vibes'] as List?)?.cast<String>() ?? [];
    if (types.any((t) => t.toLowerCase().contains(q)) ||
        vibes.any((v) => v.toLowerCase().contains(q))) {
      return 1;
    }
    return 2;
  }

  // ── 필터 로직 ─────────────────────────────────────────────────────
  // 정기 파티는 "다음 회차"가 이 파티의 날짜다 — 카드/목록과 같은 규칙을
  // 쓰도록 PartyCard의 파서에 그대로 위임한다.
  DateTime? _parsePartyDateTime(Map<String, dynamic> data) =>
      PartyCard.parsePartyDateTime(data);

  /// [fromDay]~[toDay](날짜 단위, 양끝 포함) 사이에 이 파티의 회차가 하루라도
  /// 열리는지. 정기 파티는 그 기간의 모든 요일을 검사하므로 "매주 월~금"
  /// 게시글이 오늘·내일 탭 양쪽에 모두 걸린다(일회성은 그 하루만 걸린다).
  bool _occursInDayRange(
    Map<String, dynamic> data,
    DateTime fromDay,
    DateTime toDay,
  ) {
    var cursor = DateTime(fromDay.year, fromDay.month, fromDay.day);
    final last = DateTime(toDay.year, toDay.month, toDay.day);
    while (!cursor.isAfter(last)) {
      if (PartySchedule.occursOnDay(data, cursor)) return true;
      cursor = cursor.add(const Duration(days: 1));
    }
    return false;
  }

  bool _matchesFeeRange(int fee, String range) {
    switch (range) {
      case '무료':
        return fee <= 0;
      case '1만원 이하':
        return fee > 0 && fee <= 10000;
      case '1~3만원':
        return fee > 10000 && fee <= 30000;
      case '3~5만원':
        return fee > 30000 && fee <= 50000;
      case '5~10만원':
        return fee > 50000 && fee <= 100000;
      case '10~20만원':
        return fee > 100000 && fee <= 200000;
      case '20만원 이상':
        return fee > 200000;
      default:
        return true;
    }
  }

  bool _matchesDateOption(
    Map<String, dynamic> data,
    String option,
    DateTime now,
  ) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    final weekStart = startOfToday.subtract(Duration(days: now.weekday - 1));
    switch (option) {
      case '오늘':
        return _occursInDayRange(data, startOfToday, startOfToday);
      case '내일':
        final tomorrow = startOfToday.add(const Duration(days: 1));
        return _occursInDayRange(data, tomorrow, tomorrow);
      case '이번주':
        return _occursInDayRange(
          data,
          weekStart.isBefore(startOfToday) ? startOfToday : weekStart,
          weekStart.add(const Duration(days: 6)),
        );
      case '이번주말':
        final saturday = weekStart.add(const Duration(days: 5));
        return _occursInDayRange(
          data,
          saturday.isBefore(startOfToday) ? startOfToday : saturday,
          weekStart.add(const Duration(days: 6)),
        );
      default:
        return true;
    }
  }

  /// 선택된 구/시/군(district) 중 하나라도 파티의 district와 일치하면 통과.
  /// district 필드가 없는 기존 데이터는 region(시/도) 기준으로 하위호환 매칭한다.
  // 지역 판정은 목록·지도가 **같은 규칙**을 쓴다(RegionData.matchesDistrictFilter).
  // 예전에는 두 화면에 같은 코드가 복사돼 있어서, '(전체)' 같은 선택값을 한쪽에만
  // 더하면 같은 파티가 목록에는 보이는데 지도에는 안 보이는 상태가 됐다.
  bool _matchesDistrictFilter(
    Map<String, dynamic> data,
    Set<String> selectedDistricts,
  ) => RegionData.matchesDistrictFilter(data, selectedDistricts);

  // 연령대(10년 단위) 선택값 중 하나라도 파티의 연령 제한 범위와 겹치면 통과.
  // 연령 제한은 **성별별**이므로 모집하는 성별 중 하나라도 겹치면 열려 있는
  // 것으로 본다(PartyAgeRestriction.opensToBirthYearRange). 이 필터는 "이
  // 파티가 그 연령대를 받는가"를 묻는 것이고, "내가 신청할 수 있는가"는
  // 아래 eligibleOnly(checkPartyEligibility)가 자기 성별 기준으로 판정한다.
  // 파티에 연령 제한이 없으면(ageRestrictionEnabled=false) 모든 연령대에
  // 열려 있는 것으로 간주한다.
  bool _matchesAgeGroups(Map<String, dynamic> data, Set<String> groups) {
    final age = PartyAgeRestriction.fromMap(data);
    final genderLimit = data['genderLimit'] as String? ?? 'all';
    final nowYear = DateTime.now().year;
    for (final g in groups) {
      int groupMin;
      int groupMax;
      switch (g) {
        case '20대':
          groupMin = nowYear - 29;
          groupMax = nowYear - 20;
          break;
        case '30대':
          groupMin = nowYear - 39;
          groupMax = nowYear - 30;
          break;
        case '40대':
          groupMin = nowYear - 49;
          groupMax = nowYear - 40;
          break;
        case '50대+':
          groupMin = nowYear - 150;
          groupMax = nowYear - 50;
          break;
        // 고르는 자리에서는 빠졌지만(_ageGroups) 판정은 계속 받는다 —
        // 예전에 걸어 둔 조건이 조용히 무시되면 결과만 달라진다.
        case '40대 이상':
          groupMin = nowYear - 150;
          groupMax = nowYear - 40;
          break;
        default:
          continue;
      }
      if (age.opensToBirthYearRange(
        groupMin,
        groupMax,
        genderLimit: genderLimit,
      )) {
        return true;
      }
    }
    return false;
  }

  bool _matchesDetailFilter(Map<String, dynamic> data, PartyFilter filter) {
    // 날짜 미정으로 사전등록된 오픈예정 파티는 날짜·시간 기반 조건이 하나라도
    // 켜져 있으면 결과에서 뺀다 — '오늘'을 고른 사람에게 날짜가 없는 파티를
    // 섞어 보여주면 그 필터의 뜻이 깨진다. 조건이 전부 꺼져 있으면(기본
    // 목록) 그대로 노출된다.
    if (PartyOpenState.isDateTbd(data) &&
        (filter.dateOptions.isNotEmpty ||
            filter.selectedDates.isNotEmpty ||
            filter.timeOfDayStart != null ||
            filter.timeOfDayEnd != null ||
            filter.startTime != null ||
            filter.endTime != null)) {
      return false;
    }
    if (filter.partyTypes.isNotEmpty) {
      final types = (data['partyTypes'] as List?)?.cast<String>() ?? [];
      if (!filter.partyTypes.any((t) => types.contains(t))) return false;
    }
    if (filter.vibes.isNotEmpty) {
      final vibes = (data['vibes'] as List?)?.cast<String>() ?? [];
      if (!filter.vibes.any((v) => vibes.contains(v))) return false;
    }
    if (filter.districts.isNotEmpty) {
      if (!_matchesDistrictFilter(data, filter.districts)) return false;
    }
    if (filter.genderConditions.isNotEmpty) {
      final label = _genderLabel(data);
      if (!filter.genderConditions.contains(label)) return false;
    }
    if (filter.feeRanges.isNotEmpty) {
      // 남녀 금액이 다르면 낮은 쪽(최소 참가비) 기준으로 필터링한다.
      final fee = PartyPricing.fromMap(data).displayPrice;
      if (!filter.feeRanges.any((r) => _matchesFeeRange(fee, r))) {
        return false;
      }
    }
    if (filter.ageGroups.isNotEmpty) {
      if (!_matchesAgeGroups(data, filter.ageGroups)) return false;
    }
    if (filter.tagKeywords.isNotEmpty) {
      final tags = (data['tags'] as List?)?.cast<String>() ?? [];
      final lowerTags = tags.map((t) => t.toLowerCase()).toList();
      final matched = filter.tagKeywords.any((kw) {
        final k = kw.toLowerCase();
        return lowerTags.any((t) => t.contains(k));
      });
      if (!matched) return false;
    }
    if (filter.eligibleOnly) {
      // 단순 모집 상태가 아니라, 로그인한 사용자가 실제로 신청 가능한
      // 파티인지(성별/연령 조건 + 정원 + 모집 마감 여부)까지 확인한다.
      // 모집 상태는 **내 성별 기준**이다 — 호스트가 남/여 모집을 따로 닫아
      // 둘 수 있어서(PartyGenderRecruit) 같은 파티가 남성에게는 마감,
      // 여성에게는 모집중일 수 있다.
      if (PartyCard.effectiveStatusFor(data, UserSession.gender) != '모집중') {
        return false;
      }
      final elig = checkPartyEligibility(
        data,
        UserSession.gender,
        UserSession.birthYear,
      );
      if (elig != PartyEligibility.eligible) return false;
    }
    // 파티 규모 — **최대 모집 인원 하나만** 본다. 남은 자리·현재 신청자 수·
    // 모집 마감은 보지 않는다(그건 '내가 참여 가능한 파티만'이 위에서 맡는
    // 다른 축이다). 두 조건을 섞으면 규모로 훑어보는 일 자체가 안 된다.
    if (!PartyScaleFilter.matches(data, filter.partyScale)) return false;
    if (filter.earlyBirdOnly && !EarlyBird.isActive(data)) return false;
    if (filter.dateOptions.isNotEmpty) {
      final now = DateTime.now();
      if (!filter.dateOptions.any(
        (opt) => _matchesDateOption(data, opt, now),
      )) {
        return false;
      }
    }
    // 날짜 직접 선택 + 시간 범위 필터 — 고른 날짜 중 **하루라도** 열리면
    // 통과한다(OR). '오늘+내일'처럼 여러 날을 한 번에 보는 것이 목적이라,
    // 모든 날짜에 다 열리는 파티만 남기면 결과가 거의 비어 버린다.
    if (filter.selectedDates.isNotEmpty) {
      if (!filter.selectedDates.any(
        (day) => _matchesSelectedDay(data, day, filter),
      )) {
        return false;
      }
    }
    // 시간 조건 — 지정 시간(그 시각에 진행 중) 또는 지정 구간(진행 시간이
    // 겹침). 판정은 공용 [PartyTimeFilter]가 하고, 날짜를 함께 골랐으면 그
    // 날짜의 회차만 본다(= 날짜 ∧ 시간). Firestore는 Timestamp에서 "시간대만"
    // 뽑아 범위 쿼리할 수 없어(날짜별로 값이 전부 다름) 클라이언트에서 건다.
    if (PartyTimeFilter.isActive(filter.timeOfDayStart, filter.timeOfDayEnd)) {
      final intervals = PartyTimeFilter.intervalsOf(
        data,
        onDays: filter.selectedDates,
      );
      if (!PartyTimeFilter.matches(
        intervals,
        filter.timeOfDayStart,
        filter.timeOfDayEnd,
      )) {
        return false;
      }
    }
    return true;
  }

  /// 고른 날짜 하루([day])에 이 파티가 열리고, 그 회차가 시간 범위 안인지.
  ///
  /// 정기 파티는 그 날짜에 해당 요일 회차가 있으면 통과하고, 시간 비교도 그 날
  /// 회차의 시작 시각으로 한다(문서에 저장된 첫 회차 시각이 아니다).
  bool _matchesSelectedDay(
    Map<String, dynamic> data,
    DateTime day,
    PartyFilter filter,
  ) {
    final selDay = DateTime(day.year, day.month, day.day);
    if (!PartySchedule.occursOnDay(data, selDay)) return false;
    final dt = PartySchedule.isRecurring(data)
        ? PartySchedule.recurringOf(data)?.occurrenceOn(selDay)?.start
        : _parsePartyDateTime(data);
    if (dt == null) return false;
    final partyMins = dt.hour * 60 + dt.minute;
    if (filter.startTime != null) {
      final startMins = filter.startTime!.hour * 60 + filter.startTime!.minute;
      if (partyMins < startMins) return false;
    }
    if (filter.endTime != null) {
      final endMins = filter.endTime!.hour * 60 + filter.endTime!.minute;
      if (partyMins > endMins) return false;
    }
    return true;
  }

  List<QueryDocumentSnapshot> _applyFilters(List<QueryDocumentSnapshot> docs) {
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      // 지도와 같은 판정을 쓴다([ListingSources]) — 목록에서 내려간 파티가
      // 지도에만 남는 일이 없도록.
      if (!ListingSources.isPartyVisible(data)) {
        debugPrint(
          '[MainList] ❌ isVisibleInList=false title="${data['title']}" '
          'isDeleted=${data['isDeleted']} '
          'partyDateTime=${data['partyDateTime']} startDateTime=${data['startDateTime']} date=${data['date']}',
        );
        return false;
      }
      final searchOk = _matchesSearch(data, _searchQuery);
      // 날짜·시간·인원은 상단 빠른 필터와 상세검색이 **같은 [_filter]**를 쓰므로
      // 판정도 여기 한 번뿐이다(예전 날짜 탭은 화면 전용 상태를 따로 들고
      // 있었다).
      final detailOk = _matchesDetailFilter(data, _filter);
      if (!searchOk || !detailOk) {
        debugPrint(
          '[MainList] ❌ title="${data['title']}" searchOk=$searchOk '
          'detailOk=$detailOk',
        );
      }
      return searchOk && detailOk;
    }).toList();
  }

  // ── 코치마크 오버레이 ──────────────────────────────────────────────
  Widget _buildCoachMark() {
    // 탭바의 화면 좌표를 가져와 스포트라이트 위치 계산
    final box = _tabBarKey.currentContext?.findRenderObject() as RenderBox?;
    final screenSize = MediaQuery.of(context).size;
    final fallback = Rect.fromLTWH(0, 100, screenSize.width, 48);
    final tabBarRect = (box != null && box.hasSize)
        ? box.localToGlobal(Offset.zero) & box.size
        : fallback;
    final spotRect = tabBarRect.inflate(3);

    // 진단용 로그 — 이 줄이 콘솔에 찍히는 순간에 화면이 빨갛게 깨진다면
    // 코치마크 자체가 원인이고, 이 로그 없이도(코치마크가 뜨기 전부터) 깨져
    // 있다면 이 화면의 다른 요소가 원인이라는 뜻이다.
    debugPrint(
      '[CoachMark] build 호출 — spotRect=$spotRect screenSize=$screenSize',
    );

    // 스포트라이트를 CustomPainter(Path+evenOdd)로 "구멍을 뚫는" 대신,
    // 탭바 영역만 비운 4방향(위/아래/왼쪽/오른쪽) 반투명 검정 사각형으로
    // 구현한다. 각 사각형은 배경색만 칠하는 단순 ColoredBox라 캔버스
    // 블렌드 모드·Path 합성이 전혀 없다 — CustomPaint를 아예 쓰지 않는다.
    final spotlight = RepaintBoundary(
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: spotRect.top,
            child: const ColoredBox(color: Color(0xB0000000)),
          ),
          Positioned(
            top: spotRect.bottom,
            left: 0,
            right: 0,
            bottom: 0,
            child: const ColoredBox(color: Color(0xB0000000)),
          ),
          Positioned(
            top: spotRect.top,
            bottom: screenSize.height - spotRect.bottom,
            left: 0,
            width: spotRect.left,
            child: const ColoredBox(color: Color(0xB0000000)),
          ),
          Positioned(
            top: spotRect.top,
            bottom: screenSize.height - spotRect.bottom,
            left: spotRect.right,
            right: 0,
            child: const ColoredBox(color: Color(0xB0000000)),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: () => _dismissCoachMark(),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── 스포트라이트 (탭바 구멍 뚫린 어두운 배경) ──
          spotlight,
          // ── 말풍선 (탭바 바로 아래) — 스포트라이트와 별도 RepaintBoundary ──
          Positioned(
            top: tabBarRect.bottom + 14,
            left: 20,
            right: 20,
            child: RepaintBoundary(
              child: GestureDetector(
                // 말풍선 내부 탭은 dismiss되지 않도록 흡수
                onTap: () {},
                // 애니메이션(스케일 인/아웃)은 Transform.scale에만 국한한다 —
                // Opacity/FadeTransition은 완전히 제거했고(saveLayer 합성
                // 없음), 매 프레임 다시 빌드되는 범위도 이 Transform.scale
                // 하나로 최소화한다(정적인 말풍선 내용은 child로 한 번만 빌드).
                child: AnimatedBuilder(
                  animation: _coachMarkAnim,
                  builder: (ctx, bubble) => Transform.scale(
                    scale: 0.88 + 0.12 * _coachMarkAnim.value,
                    alignment: Alignment.topCenter,
                    child: bubble,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 위쪽 화살표 (탭바를 가리킴)
                      CustomPaint(
                        size: const Size(22, 11),
                        painter: _UpArrowPainter(),
                      ),
                      // 말풍선 본문 — BoxShadow(블러) 제거, 얇은 테두리로
                      // 대체(블러는 saveLayer 합성을 유발할 수 있어 진단
                      // 목적으로 뺐다).
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0x1F000000)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 아이콘
                            const Icon(
                              Icons.swipe_rounded,
                              size: 38,
                              color: Color(0xFFFF6FA0),
                            ),
                            const SizedBox(height: 14),
                            // 안내 텍스트
                            const Text(
                              '좌우로 슬라이드하면\n파티 · 파티마켓 화면으로\n이동할 수 있어요.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF1A1A1A),
                                height: 1.65,
                              ),
                            ),
                            const SizedBox(height: 10),
                            // 탭 이름 행
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(
                                  Icons.arrow_back_ios_rounded,
                                  size: 12,
                                  color: Color(0xFFFF6FA0),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '장소대여',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFFF6FA0),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  '파티',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFFF6FA0),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 12,
                                  color: Color(0xFFFF6FA0),
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),
                            // 버튼 행
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () =>
                                        _dismissCoachMark(permanent: true),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.black45,
                                      side: const BorderSide(
                                        color: Color(0xFFDDDDDD),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 13,
                                      ),
                                    ),
                                    child: const Text(
                                      '다시 보지 않기',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => _dismissCoachMark(),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFF6FA0),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 13,
                                      ),
                                    ),
                                    child: const Text(
                                      '확인',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 파티 카드 ─────────────────────────────────────────────────────
  String _genderLabel(Map<String, dynamic> data) {
    final genderLimit = data['genderLimit'] as String? ?? 'all';
    final genderCapacityMode =
        data['genderCapacityMode'] as String? ?? 'unlimited';
    final genderMode = data['genderMode'] as String? ?? '';
    if (genderLimit == 'male') return '남자만';
    if (genderLimit == 'female') return '여자만';
    if (genderMode == 'balanced' || genderCapacityMode == 'separate') {
      return '성비 맞춤';
    }
    return '남녀무관';
  }

  Widget _buildPartyCard(
    Map<String, dynamic> party,
    String docId, {
    VoidCallback? onTap,
  }) => PartyCard(party: party, docId: docId, onTap: onTap);
}

// 탭 하나의 검색어 상태 — 입력 컨트롤러와 확정된 검색어를 한 쌍으로 묶는다.
// (파티 탭은 예전부터 쓰던 _searchController/_searchQuery 한 쌍을 그대로 쓴다.)
class _TabSearch {
  final TextEditingController controller = TextEditingController();
  String query = '';

  void dispose() => controller.dispose();
}

// ══════════════════════════════════════════════════════════════════════
// 코치마크 — 말풍선 위쪽 삼각형 화살표
// ══════════════════════════════════════════════════════════════════════
class _UpArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width / 2, 0) // 꼭짓점 (위)
      ..lineTo(size.width, size.height) // 오른쪽 아래
      ..lineTo(0, size.height) // 왼쪽 아래
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_UpArrowPainter old) => false;
}
