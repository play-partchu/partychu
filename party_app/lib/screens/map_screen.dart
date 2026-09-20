import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:party_app/screens/event_detail_screen.dart';
import 'package:party_app/screens/party_detail_screen.dart';
import 'package:party_app/screens/party_register_entry_choice_screen.dart';
import 'package:party_app/screens/place_detail_screen.dart';
import 'package:party_app/screens/public_event_detail_screen.dart';
import 'package:party_app/models/event_feed.dart';
import 'package:party_app/models/public_event.dart';
import 'package:party_app/services/public_event_service.dart';
import 'package:party_app/widgets/public_event_card.dart';
import 'package:party_app/models/listing_price_match.dart';
import 'package:party_app/models/map_quick_filter_row.dart';
import 'package:party_app/models/place_filter.dart';
import 'package:party_app/widgets/map_price_filter_sheet.dart';
import 'package:party_app/widgets/map_quick_filter_button.dart';
import 'package:party_app/models/date_time_filter_label.dart';
import 'package:party_app/models/korean_holidays.dart';
import 'package:party_app/widgets/main/korean_calendar_sheet.dart';
import 'package:party_app/widgets/main/quick_date_pane.dart';
import 'package:party_app/widgets/main/visit_time_picker_sheet.dart';
import 'package:party_app/services/listing_sources.dart';
import 'package:party_app/models/place_party_index.dart';
import 'package:party_app/models/place_event_index.dart';
import 'package:party_app/models/place_event_taxonomy.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/services/place_promotion_service.dart';
import 'package:party_app/widgets/main/place_quick_feature_bar.dart';
import 'package:party_app/widgets/map_kind_filter_bar.dart';
import 'package:party_app/widgets/main/place_category_explorer.dart';
import 'package:party_app/widgets/party_thumbnail_widget.dart';
import 'package:party_app/widgets/place_card_widget.dart';
import 'package:party_app/utils/feed_video_manager.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/party_utils.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/models/party_age_restriction.dart';
import 'package:party_app/models/listing_text_search.dart';
import 'package:party_app/models/map_auto_search.dart';
import 'package:party_app/models/map_home_category.dart';
import 'package:party_app/models/map_listing.dart';
import 'package:party_app/models/map_marker_tap.dart';
import 'package:party_app/models/party_search.dart';
import 'package:party_app/widgets/main/search_entry_sheet.dart';
import 'package:party_app/models/party_date_focus.dart';
import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/party_filter.dart';
import 'package:party_app/models/place_feature.dart';
import 'package:party_app/models/party_series.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/utils/early_bird.dart';
import 'package:party_app/utils/party_eligibility.dart';
import 'package:party_app/utils/party_scale_filter.dart';
import 'package:party_app/models/party_time_filter.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/detail_search_sheet.dart';
import 'package:party_app/widgets/web_frame.dart';

// 줌 단계별 마커 표시 방식 — 멀리서는 점, 중간부터 원형 썸네일, 가까이는
// 기존 핀+카드 썸네일로 자연스럽게 전환된다.
enum _MarkerTier { dot, circle, card }

/// 같은 자리(또는 화면에서 겹칠 만큼 가까운 자리)에 모인 항목 묶음.
///
/// 예전 지도는 마커를 문서마다 하나씩 그냥 얹었다 — 파티가 그 플레이스에서
/// 열리는 흔한 경우 좌표가 **완전히 같아서** 나중에 얹힌 마커가 앞의 것을 덮고,
/// 덮인 쪽은 누를 방법 자체가 없었다(파티만 있던 시절에도 같은 게시글의 다른
/// 날짜 문서가 이렇게 겹쳤고, 그건 [PartySeries]로 접어서 피해 왔다).
/// 세 종류를 함께 올리면 서로 다른 컬렉션끼리 겹치므로 접는 것으로는 해결되지
/// 않는다 — 그래서 겹치는 것들을 하나의 마커로 묶고, 누르면 그 자리의 목록을
/// 펼친다.
class _MarkerGroup {
  final double lat;
  final double lng;
  final List<MapListing> items;

  _MarkerGroup({required this.lat, required this.lng, required this.items});

  MapListing get first => items.first;

  /// 마커 id — 묶음의 대표 항목 키를 쓴다. 한 항목은 한 묶음에만 들어가므로
  /// 같은 동기화 안에서 절대 겹치지 않는다.
  String get id => 'grp_${first.key}';

  /// 이 자리에 섞여 있는 종류들(마커에 배지로 붙인다).
  List<MapListingKind> get kinds => [
    for (final k in MapListingKind.values)
      if (items.any((i) => i.kind == k)) k,
  ];
}

class MapScreen extends StatefulWidget {
  /// 앱 **홈**(하단 네비 첫 칸)으로 쓰일 때 true.
  ///
  /// 지도가 화면 대부분을 차지한다 — 아래 목록 시트가 없고, 위에는 검색창과
  /// 가로 카테고리 한 줄만 떠 있다. 마커를 누르면 그 콘텐츠 하나의 작은
  /// 미리보기 카드만 뜬다. 데이터·필터·마커·상세 이동은 지도 화면과
  /// **같은 코드**를 그대로 쓴다(그리는 껍데기만 다르다).
  final bool home;

  /// 홈 모드에서 지도를 쓸 수 없는 웹의 '목록으로 보기' — 목록 탭으로 보낸다.
  final VoidCallback? onOpenList;

  const MapScreen({super.key, this.home = false, this.onOpenList});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  NaverMapController? _mapController;
  NMarker? _currentLocationMarker;
  bool _isLoadingLocation = false;

  // ── 지도 이동 감지 ────────────────────────────────────────────────
  //
  // 예전에는 움직이면 재검색 버튼이 떴고, 그것을 눌러야 이 영역으로 좁혀졌다.
  // 지금은 카메라가 멈추면 앱이 알아서 한다([_scheduleAutoSearch]).
  bool _mapInitialized = false; // 최초 onCameraIdle 무시용
  bool _pendingAreaSearch = false; // 현재 위치 이동 후 자동 영역 검색 트리거

  /// 카메라가 멈춘 뒤 기다리는 타이머. 이어서 움직이면 다시 건다 —
  /// 마지막 위치에서 한 번만 돌게 하려는 것이다.
  Timer? _autoSearchTimer;

  /// 영역 조회 세대. bounds를 읽어 오는 사이에 지도가 또 움직이면 먼저
  /// 시작한 조회가 뒤늦게 옛 영역을 얹을 수 있어, 자기 번호가 밀렸으면
  /// 아무것도 하지 않고 물러난다.
  int _areaSearchGeneration = 0;

  double _currentZoom = 12.0; // 현재 줌 레벨
  // 줌 3단계 전환 — 멀리서는 점 마커, 중간 줌부터 작은 원형 썸네일,
  // 확대하면 기존 핀+카드 썸네일. 기존엔 15 하나뿐이라 꽤 확대해야만
  // 썸네일이 보였는데, 원형 단계를 앞당겨(13) 더 낮은 줌에서도 파티 위치를
  // 한눈에 파악할 수 있게 했다.
  static const double _circleThumbZoomThreshold = 13.0;
  static const double _cardThumbZoomThreshold = 16.0;
  final Map<String, ui.Image> _imageCache = {}; // 마커 썸네일 디코딩된 이미지 캐시

  // ── 상세검색 필터 ─────────────────────────────────────────────────
  PartyFilter _filter = PartyFilter();

  /// 플레이스 전용 탐색 조건(대분류·특징·속성).
  ///
  /// [_filter]와 **완전히 독립**이고, 판정도 **플레이스 항목에만** 건다.
  /// 파티·장소대여에는 대분류라는 개념 자체가 없어서, 걸면 '클럽'을 켜는
  /// 순간 파티가 통째로 사라진다 — 그건 AND가 아니라 '다른 종류 끄기'다
  /// (기존 [_matchesSharedFilter]가 참가비·성별을 장소 계열에 걸지 않는
  /// 것과 같은 이유).
  final EventFilter _placeDiscovery = EventFilter();

  /// 🏠 장소대여 가격 칸 — 목록 탭과 **같은 모델**([PlaceFilter])의 priceRanges
  /// 하나만 쓴다. 지도에는 장소대여 상세검색이 없어 이 칸만 들고 있는다.
  final PlaceFilter _rentalDiscovery = PlaceFilter();
  Set<DateTime> _partyDates = {};

  // ── 종류 선택 ─────────────────────────────────────────────────────
  //
  // 처음 들어오면 세 종류가 모두 켜져 있다(= 상단 칩의 '전체'). 이 집합은
  // 상세검색 필터([_filter])와 **완전히 독립**이다 — 종류를 바꿔도 지역·날짜
  // 조건은 그대로 남고, 두 조건은 AND로 함께 걸린다([_matchesFilter]).
  // 홈은 '전체'(🎊 공공 축제 포함)로, 지도 화면은 파티츄 세 종류로 시작한다.
  late Set<MapListingKind> _kinds = mapInitialKinds(home: widget.home);

  // ── 데이터 ────────────────────────────────────────────────────────
  //
  // 종류별로 따로 담는다 — 컬렉션이 셋이라 스트림도 셋이고, 한 스트림이
  // 갱신돼도 나머지 둘을 다시 읽을 필요가 없다. 여기 담기는 것은 이미
  // **목록과 같은 노출 판정**([ListingSources])을 통과한 것들뿐이다.
  final Map<MapListingKind, List<MapListing>> _byKind = {
    for (final k in MapListingKind.values) k: <MapListing>[],
  };

  /// 지도에 마커로 올릴 항목 — 종류 선택 + 상세검색 조건까지 적용된 결과다
  /// (영역 검색은 빼고. 그건 "이 지도에서 보기"가 아래 목록을 좁히는 것이라
  /// 마커까지 지우면 지도가 텅 비어 버린다).
  List<MapListing> _mapItems = [];

  /// 하단 목록에 표시할 항목 — [_mapItems]에 영역 검색 범위까지 적용한 것.
  List<MapListing> _displayed = [];

  /// 종류 칩에 붙는 개수 — 종류 선택만 빼고 나머지 조건을 건 결과의 크기다
  /// ([_recomputeVisible]에서 함께 계산한다).
  Map<MapListingKind, int> _countByKind = const {};

  bool _isAreaSearch = false; // 영역 검색 중 여부
  NLatLngBounds? _lastSearchBounds; // 마지막 영역 검색 bounds

  final Map<String, NMarker> _markers = {};

  /// 지도에 올라가 있는 마커의 '지금 모양'([_markerSignature]). 다시 그릴 때
  /// 이것과 견줘 **달라진 것만** 건드린다 — 전부 지웠다 그리면 지도를 움직일
  /// 때마다 마커가 깜빡인다.
  final Map<String, String> _markerSignatures = {};
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _subscriptions = [];

  /// 마커 동기화는 비동기(아이콘을 위젯에서 굽는다)라 여러 번이 겹쳐 돌 수
  /// 있다. 세대 번호가 어긋나면 뒤늦게 끝난 예전 동기화가 새 마커를 덮어쓰지
  /// 않도록 그 자리에서 멈춘다.
  int _syncGeneration = 0;

  /// 마지막으로 마커를 그린 줌 한 칸(내림). 겹침 묶음의 크기가 줌에 매여
  /// 있어서, 단계(점/원형/카드)가 그대로여도 한 칸이 바뀌면 다시 그려야 한다.
  int _syncedZoomStep = -1000;

  /// 마커 하나만 눌렀을 때 지도 위에 뜨는 미리보기 카드.
  MapListing? _tapped;

  // ── 홈 모드 전용 ──────────────────────────────────────────────────
  bool get _home => widget.home;

  /// 검색창의 검색어 — 목록 탭과 **같은 매칭**을 쓴다(파티는
  /// [partySearchMatches], 장소 계열은 [listingTextMatches]).
  String _query = '';
  final _queryCtrl = TextEditingController();

  /// 지금 고른 가로 카테고리([mapHomeCategories]의 번호).
  ///
  /// 멀티선택이다 — [mapHomeCategories]에서 켜 둔 **개별 카테고리 번호**
  /// (파티·이벤트·플레이스·장소대여)의 집합. **비어 있으면 '전체'** 다.
  /// '전체'를 따로 저장하지 않으므로 '전체'와 개별 칸이 동시에 켜진
  /// 상태는 만들어질 수 없고, 마지막 하나를 끄면 저절로 '전체'가 된다.
  Set<int> _homeSelected = {};

  /// 선택해서 강조 중인 마커의 항목 키([MapListing.key]).
  String? _selectedKey;

  /// 마커 id → 그 마커가 대표하는 묶음(선택 강조 때 아이콘만 다시 굽는다).
  final Map<String, _MarkerGroup> _groupsById = {};

  /// 마지막으로 확인한 내 위치 — 미리보기 카드의 거리 표시에 쓴다.
  NLatLng? _myLatLng;

  /// 앱이 카메라를 옮긴 직후의 idle 한 번은 "사용자가 지도를 움직였다"가
  /// 아니다(자동 재조회를 걸지 않는다).
  bool _ignoreNextIdle = false;

  /// 📅 날짜·시간 알약을 눌러 그 아래 빠른선택 판이 펼쳐져 있는가.
  bool _dateTimePaneOpen = false;

  // 하단 파티 목록 시트 — 사용자가 드래그해 접어둔 채로 "이 지도에서 파티
  // 보기"를 누르면(예: minChildSize=0.15까지 내려간 상태) 헤더(제목/개수)는
  // 보이지만 그 아래 Expanded 안의 ListView가 표시될 공간이 거의 남지 않아
  // "개수는 맞는데 카드가 안 보이는" 것처럼 보였다. 새로 영역 검색을 하면
  // 시트를 충분한 높이로 펼쳐 목록이 항상 눈에 보이도록 이 컨트롤러로 제어한다.
  final _sheetController = DraggableScrollableController();
  static const double _sheetExpandedSize = 0.5;

  /// 같은 게시글(seriesId)의 날짜 문서를 접고 '일정 N개' 배지를 세는 색인 —
  /// 목록 화면과 같은 규칙을 쓴다(PartySeries).
  PartySeries _partySeries = PartySeries.index(const []);

  /// 🎉 With파티 색인 — 파티 스냅샷이 올 때마다 다시 만든다.
  /// 목록 화면과 같은 [PlacePartyIndex.fromSnapshot]을 쓰므로 두 화면의
  /// With파티 결과가 갈릴 수 없다.
  PlacePartyIndex _withPartyIndex = PlacePartyIndex.empty;

  /// 🎪 이벤트 색인 — 지금 보여줄 이벤트가 있는 매장 id 집합
  /// ([PlaceEventIndex]). 목록 화면과 **같은 정본**(`placePromotions`)을 보고
  /// 같은 함수로 만드므로, 이벤트 칸을 켰을 때 지도와 목록에 남는 매장이
  /// 갈릴 수 없다.
  ///
  /// 파티와 달리 지도가 이미 받고 있는 스냅샷으로는 만들 수 없어(프로모션은
  /// 별도 컬렉션이다) 구독을 하나 더 건다 — 그래서 **이벤트 칸이 켜져 있는
  /// 동안에만** 건다([_syncPlaceEventIndexSub]). null이면 아직 못 읽었다는
  /// 뜻이라 예전 미러 판정이 그대로 답한다.
  PlaceEventIndex? _placeEventIndex;

  /// 🎪 **공간 이벤트** 색인 — 장소대여 마커가 보는 쪽
  /// ([PlaceEventIndex.rentalCollection]).
  ///
  /// 위 [_placeEventIndex]와 **같은 스트림 한 개**에서 컬렉션만 갈라 만든다 —
  /// 구독을 두 번 걸지 않고, 매장 이벤트가 장소대여 마커를 남길 수도 없다.
  /// 장소대여 목록([PlaceFilter.matchesEvent])이 쓰는 것과 같은 색인·같은
  /// 판정이라 목록과 지도가 갈릴 수 없다.
  PlaceEventIndex? _rentalEventIndex;
  StreamSubscription<List<PlacePromotion>>? _placeEventSub;

  /// 🎊 공공 축제(publicEvents) 구독 — **지도 홈에서 공공 축제를 올리는
  /// 카테고리(전체·이벤트)가 켜진 동안에만** 건다([_syncPublicEventSub]).
  /// 받은 것 중 좌표가 있는 것만 [_byKind]의 공공 축제 칸에 담긴다.
  StreamSubscription<List<PublicEvent>>? _publicEventSub;

  /// 공공 축제 마커를 만든 **넓힌 화면 영역** — 화면이 이 상자를 벗어날 때만
  /// 마커를 다시 그린다([_onCameraIdle]). 공공 축제가 마커 후보에 없으면 null.
  ({double south, double west, double north, double east})? _festivalSyncBox;

  /// 공공 축제 마커를 만들 때 화면 영역을 사방으로 넓히는 비율 — 조금씩
  /// 움직일 때마다 마커를 다시 그리지 않게 한다.
  static const double _festivalBoxMargin = 0.5;

  @override
  void initState() {
    super.initState();
    // 지도 화면은 들어올 때마다 항상 음소거로 시작한다(마커 카드가 한 화면에
    // 여러 개 걸릴 수 있어 소리가 켜진 채 진입하면 시끄럽다) — 사용자가 직접
    // 스피커 버튼으로 켜면 그 뒤로는 다른 화면과 동일하게 전역 설정을 따른다.
    //
    // 홈 모드는 앱을 켜자마자 만들어지는 화면이라 여기서 전역 음소거를 바꾸면
    // 목록 탭의 소리 설정까지 덮어쓴다 — 홈에는 동영상이 없으므로 건드리지
    // 않는다.
    if (!widget.home) FeedVideoManager.instance.setMuted(true);
    // 웹 홈은 지도 대신 안내만 그린다 — 올릴 마커가 없으니 읽지도 않는다
    // (목록 탭이 같은 데이터를 이미 읽고 있다).
    if (widget.home && kIsWeb) return;
    // 세 컬렉션을 각각 구독한다 — 지도 전용 사본을 만들지 않고 목록 화면과
    // **같은 쿼리**([ListingSources])를 그대로 쓴다.
    _subscriptions.addAll([
      ListingSources.parties().snapshots().listen(
        _onPartiesUpdated,
        onError: (Object e, StackTrace s) =>
            logFirestoreStreamError('MapParties', e, s),
      ),
      ListingSources.events().snapshots().listen(
        (snap) => _onPlaceLikeUpdated(
          MapListingKind.place,
          snap,
          ListingSources.isEventVisible,
        ),
        onError: (Object e, StackTrace s) =>
            logFirestoreStreamError('MapEvents', e, s),
      ),
      ListingSources.places().snapshots().listen(
        (snap) => _onPlaceLikeUpdated(
          MapListingKind.rental,
          snap,
          ListingSources.isRentalVisible,
        ),
        onError: (Object e, StackTrace s) =>
            logFirestoreStreamError('MapPlaces', e, s),
      ),
    ]);
  }

  @override
  void dispose() {
    _autoSearchTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _placeEventSub?.cancel();
    _publicEventSub?.cancel();
    _sheetController.dispose();
    _queryCtrl.dispose();
    super.dispose();
  }

  // ── Firestore 파티 업데이트 ──────────────────────────────────────
  void _onPartiesUpdated(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (!mounted) return;
    // 같은 게시글(seriesId)의 날짜 문서들을 하나로 접는다 — 형제 문서는 좌표가
    // 모두 같아서, 접지 않으면 핀과 목록 카드가 날짜 수만큼 겹쳐 쌓인다.
    // 대표는 목록과 같은 규칙(가장 가까운 다음 일정)이다.
    _partySeries = PartySeries.index(snapshot.docs);
    // 🎉 With파티 색인 — 목록 화면과 **같은 함수**로 만든다
    // ([PlacePartyIndex]). 파티를 여기서 이미 받고 있으므로 새 구독이 없다.
    _withPartyIndex = PlacePartyIndex.fromSnapshot(snapshot.docs);
    final visibleDocs = snapshot.docs
        .where(
          (doc) =>
              ListingSources.isPartyVisible({'_docId': doc.id, ...doc.data()}),
        )
        .toList();
    final parties = _partySeries
        .collapse(visibleDocs)
        .map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return MapListing.from(MapListingKind.party, doc.id, {
            '_docId': doc.id,
            ...data,
          });
        })
        .whereType<MapListing>()
        .toList();

    // 달력 점 표시용 날짜 집합 갱신 — 상세검색 시트의 달력에 찍는 점이라
    // 파티에서만 모은다(장소 계열에는 "열리는 날"이라는 개념이 없다).
    final dates = snapshot.docs
        .map((doc) {
          final dt = PartyCard.parsePartyDateTime(doc.data());
          return dt != null ? DateTime(dt.year, dt.month, dt.day) : null;
        })
        .whereType<DateTime>()
        .toSet();

    setState(() {
      _byKind[MapListingKind.party] = parties;
      _partyDates = dates;
      _recomputeVisible();
    });
    _syncMarkers();
  }

  // ── Firestore 플레이스(events)·장소대여(places) 업데이트 ─────────
  //
  // 두 컬렉션은 스키마가 달라도 지도가 쓰는 부분(좌표·이름·주소·대표 미디어)이
  // 같은 자리에 있어서 한 핸들러로 받는다. 노출 판정만 종류별로 다르므로
  // 호출부가 [ListingSources]의 판정 함수를 넘긴다.
  void _onPlaceLikeUpdated(
    MapListingKind kind,
    QuerySnapshot<Map<String, dynamic>> snapshot,
    bool Function(Map<String, dynamic>) isVisible,
  ) {
    if (!mounted) return;
    final items = snapshot.docs
        .where((doc) => isVisible(doc.data()))
        .map((doc) => MapListing.from(kind, doc.id, doc.data()))
        .whereType<MapListing>()
        .toList();
    setState(() {
      _byKind[kind] = items;
      _recomputeVisible();
    });
    _syncMarkers();
  }

  /// 🎊 공공 축제를 올리는 칸(전체·이벤트)이 지도 홈에서 켜진 동안에만
  /// `publicEvents`를 구독한다. 지도 화면(하단 목록 시트)은 공공 축제를
  /// 다루지 않는다 — 종류 칩이 파티츄 세 종류뿐이다([MapListingKind.listingKinds]).
  ///
  /// 조회·끝난 행사 거르기는 이벤트 피드와 같은 [PublicEventService.watchOpen]
  /// 이고, 여기서는 **좌표가 있는 것만** 지도 후보로 남긴다.
  void _syncPublicEventSub() {
    final want =
        _home && !kIsWeb && _kinds.contains(MapListingKind.festival);
    if (want == (_publicEventSub != null)) return;
    if (!want) {
      _publicEventSub?.cancel();
      _publicEventSub = null;
      _byKind[MapListingKind.festival] = <MapListing>[];
      return;
    }
    _publicEventSub = PublicEventService.watchOpen().listen(
      (events) {
        if (!mounted) return;
        setState(() {
          _byKind[MapListingKind.festival] = [
            for (final e in events) ?MapListing.fromPublicEvent(e),
          ];
          _recomputeVisible();
        });
        _syncMarkers();
      },
      onError: (Object e, StackTrace s) =>
          logFirestoreStreamError('MapPublicEvents', e, s),
    );
  }

  /// 🎪 이벤트 칸이 켜져 있는 동안에만 `placePromotions`를 구독한다.
  ///
  /// 조건이 바뀌는 입구는 여럿이지만 전부 [_recomputeVisible]로 끝나므로,
  /// 거기서 한 번 맞춰 두면 어느 입구로 켜도 구독이 새지 않는다.
  ///
  /// 스트림은 하나지만 색인은 **컬렉션마다 하나씩** 만든다 — 플레이스 마커는
  /// 매장 이벤트를, 장소대여 마커는 공간 이벤트를 본다. 한 집합에 담으면 id가
  /// 우연히 겹칠 때 남의 종류가 새어 들어온다([PlaceEventIndex] 상단 주석).
  void _syncPlaceEventIndexSub() {
    final want = _placeDiscovery.eventOnly || _homeWantsEvents;
    if (want == (_placeEventSub != null)) return;

    if (!want) {
      _placeEventSub?.cancel();
      _placeEventSub = null;
      // 색인도 함께 버린다 — 다시 켰을 때 낡은 집합으로 잘못 걸러 놓고
      // 시작하지 않게 한다(null이면 플레이스는 예전 미러 판정이 답하고,
      // 장소대여는 아무것도 남기지 않는다 — 목록과 같은 규칙이다).
      _placeEventIndex = null;
      _rentalEventIndex = null;
      return;
    }

    _placeEventSub = PlacePromotionService.watchPublicAll().listen(
      (promotions) {
        if (!mounted) return;
        final next = PlaceEventIndex.fromPromotions(promotions);
        final nextRental = PlaceEventIndex.fromPromotions(
          promotions,
          collection: PlaceEventIndex.rentalCollection,
        );
        // 둘 다 그대로면 다시 그리지 않는다 — 한쪽만 바뀌어도 다시 센다.
        if ((_placeEventIndex?.sameAs(next) ?? false) &&
            (_rentalEventIndex?.sameAs(nextRental) ?? false)) {
          return;
        }
        setState(() {
          _placeEventIndex = next;
          _rentalEventIndex = nextRental;
          _recomputeVisible();
        });
        // 이벤트 색인이 바뀌면 이벤트 조건에 걸린 마커도 다시 그린다.
        _syncMarkers();
      },
      onError: (Object e, StackTrace s) =>
          logFirestoreStreamError('MapPlaceEventIndex', e, s),
    );
  }

  /// 종류 선택 + 상세검색 조건 + 영역 검색을 한 번에 다시 계산한다.
  /// **setState 안에서만** 부른다(이 함수 자체는 상태를 알릴 책임이 없다).
  void _recomputeVisible() {
    // 🎪 이벤트를 켠 동안에만 이벤트 정본을 구독한다(위 주석).
    _syncPlaceEventIndexSub();
    // 🎊 공공 축제도 그 칸이 켜진 동안에만.
    _syncPublicEventSub();
    _mapItems = [
      for (final kind in MapListingKind.values)
        if (_kinds.contains(kind)) ..._byKind[kind]!.where(_matchesFilter),
    ];
    _displayed = _isAreaSearch && _lastSearchBounds != null
        ? _filterByBounds(_mapItems, _lastSearchBounds!)
        : _mapItems;

    // 칩에 붙는 종류별 개수 — **종류 선택은 빼고** 나머지 조건(상세검색·영역)만
    // 걸어서 센다. 꺼 둔 종류의 칩에도 "켜면 몇 개가 나오는지"가 보여야 고를
    // 이유가 생기기 때문이다. 켜 둔 종류의 숫자는 지금 목록에 보이는 개수와
    // 정확히 같고, 켜 둔 것들의 합이 곧 '전체' 칩의 숫자다.
    //
    // 시트는 드래그할 때마다 다시 그려지므로 여기서 한 번만 세고 들고 있는다.
    _countByKind = {
      for (final kind in MapListingKind.values)
        kind:
            (_isAreaSearch && _lastSearchBounds != null
                    ? _filterByBounds(
                        _byKind[kind]!.where(_matchesFilter).toList(),
                        _lastSearchBounds!,
                      )
                    : _byKind[kind]!.where(_matchesFilter).toList())
                .length,
    };

    // 지금 미리보기 중인 항목이 조건에서 빠졌으면 카드도 함께 내린다.
    // (홈은 마커 자체가 영역 검색 결과를 따르므로 그 목록으로 본다.)
    final tapped = _tapped;
    final pool = _home ? _displayed : _mapItems;
    if (tapped != null && !pool.any((i) => i.key == tapped.key)) {
      _tapped = null;
      _selectedKey = null;
    }
  }

  // 줌 값 하나를 3단계 중 하나로 분류 — 마커 동기화·전환 감지가 모두 이
  // 하나의 기준만 보고 판단하게 해서 두 곳의 임계값이 어긋나지 않게 한다.
  _MarkerTier _tierForZoom(double zoom) {
    if (zoom >= _cardThumbZoomThreshold) return _MarkerTier.card;
    if (zoom >= _circleThumbZoomThreshold) return _MarkerTier.circle;
    return _MarkerTier.dot;
  }

  // ── 마커 동기화 ───────────────────────────────────────────────────
  //
  // 마커가 보는 것은 [_mapItems] 하나뿐이다 — 종류 선택과 상세검색 조건이 이미
  // 반영된 목록이라, 칩을 끄면 그 종류의 마커도 함께 사라진다.
  //
  // 아이콘을 위젯에서 굽는 비동기 작업이라 여러 동기화가 겹칠 수 있다.
  // 세대 번호([_syncGeneration])가 어긋난 순간, 뒤늦게 도는 예전 동기화는
  // **자기가 얹은 마커를 스스로 걷어내고** 물러난다(그냥 return하면 아무도
  // 지우지 않는 유령 마커가 남는다).
  Future<void> _syncMarkers() async {
    if (_mapController == null) return;
    final generation = ++_syncGeneration;

    // 홈에는 아래 목록이 없다 — 영역 조회가 좁힌 결과를 마커가
    // 그대로 보여준다(영역 검색 전에는 [_mapItems]와 같다).
    var pool = _home ? _displayed : _mapItems;
    // 🎊 공공 축제는 전국 수백 건이라 **화면 근처 것만** 마커 후보로 만든다.
    // 걸러 내는 함수는 영역 검색과 같은 [_filterByBounds]이고, 영역은 지금
    // 화면을 사방으로 넓힌 상자다([_festivalBoxMargin]). 파티츄 콘텐츠 셋은
    // 예전 그대로 전부 후보다.
    if (pool.any((i) => i.kind == MapListingKind.festival)) {
      final view = await _mapController!.getContentBounds();
      if (!mounted || generation != _syncGeneration) return;
      final box = expandBox(_boxOf(view), _festivalBoxMargin);
      _festivalSyncBox = box;
      final nearby = _filterByBounds(
        [
          for (final i in pool)
            if (i.kind == MapListingKind.festival) i,
        ],
        NLatLngBounds(
          southWest: NLatLng(box.south, box.west),
          northEast: NLatLng(box.north, box.east),
        ),
      );
      pool = [
        for (final i in pool)
          if (i.kind != MapListingKind.festival) i,
        ...nearby,
      ];
    } else {
      _festivalSyncBox = null;
    }

    final tier = _markerTierForZoom(_currentZoom);
    _syncedZoomStep = _currentZoom.floor();
    final groups = _clusterListings(pool, tier);
    _groupsById
      ..clear()
      ..addEntries(groups.map((g) => MapEntry(g.id, g)));

    // ── 달라진 것만 건드린다 ────────────────────────────────────────
    //
    // 예전에는 여기서 마커를 **전부 지우고 처음부터 다시 그렸다.** 사용자가
    // 버튼을 눌렀을 때만 돌던 시절에는 티가 안 났는데, 지도를 멈출 때마다
    // 자동으로 도는 지금은 움직일 때마다 마커가 사라졌다 나타난다.
    //
    // 그래서 묶음마다 '그림에 영향을 주는 것 전부'를 한 줄로 만들어
    // ([_markerSignature]) 지난번과 견준다. 같으면 그대로 두고, 사라진 것만
    // 지우고, 새로 생기거나 모양이 달라진 것만 다시 굽는다. 화면에 남아 있는
    // 마커는 손대지 않으므로 깜빡임이 없다.
    final desired = {for (final g in groups) g.id: g};
    final removed = [
      for (final entry in _markers.entries)
        if (!desired.containsKey(entry.key) ||
            _markerSignatures[entry.key] !=
                _markerSignature(desired[entry.key]!, tier))
          entry.key,
    ];
    for (final id in removed) {
      if (!mounted || generation != _syncGeneration) return;
      final marker = _markers.remove(id);
      _markerSignatures.remove(id);
      if (marker != null) await _mapController?.deleteOverlay(marker.info);
    }

    final pending = <String, NMarker>{};

    Future<void> rollback() async {
      for (final marker in pending.values) {
        await _mapController?.deleteOverlay(marker.info);
      }
      for (final id in pending.keys) {
        _markers.remove(id);
        _markerSignatures.remove(id);
      }
    }

    for (final group in groups) {
      if (!mounted || generation != _syncGeneration) return rollback();
      final signature = _markerSignature(group, tier);
      // 그대로인 마커는 지우지도 다시 굽지도 않았다 — 건너뛴다.
      if (_markerSignatures[group.id] == signature) continue;

      final selected = _isSelectedGroup(group);
      final built = selected
          ? await _buildSelectedMarkerIcon(group.first)
          : await _buildMarkerIcon(group, tier);
      if (built == null) return rollback();
      if (!mounted || generation != _syncGeneration) return rollback();

      final marker = NMarker(
        id: group.id,
        position: NLatLng(group.lat, group.lng),
      );
      marker.setIcon(built.icon);
      marker.setSize(built.size);
      marker.setAnchor(built.anchor);
      if (selected) marker.setZIndex(1000);
      marker.setOnTapListener((_) => _onMarkerTap(group));
      await _mapController?.addOverlay(marker);
      pending[group.id] = marker;
      _markers[group.id] = marker;
      _markerSignatures[group.id] = signature;
    }
    if (!mounted || generation != _syncGeneration) return rollback();
  }

  /// 이 묶음의 마커 그림을 정하는 것 전부 — 하나라도 다르면 다시 구워야 한다.
  ///
  /// 묶음 id는 대표 항목([_MarkerGroup.id])으로만 정해져서, 같은 자리에 다른
  /// 것이 하나 더 들어오거나 빠져도 id는 그대로다. 그래서 개수·섞인 종류·줌
  /// 단계·선택 여부까지 함께 본다.
  String _markerSignature(_MarkerGroup group, _MarkerTier tier) {
    final kinds = group.kinds.map((k) => k.index).join(',');
    final selected = _isSelectedGroup(group) ? '1' : '0';
    return '${tier.index}|${group.items.length}|$kinds|$selected'
        '|${group.lat.toStringAsFixed(6)},${group.lng.toStringAsFixed(6)}';
  }

  // ── 겹침 처리(클러스터링) ─────────────────────────────────────────
  //
  // 마커 하나가 화면에서 차지하는 **픽셀 폭**을 지금 줌에서의 좌표 폭으로
  // 환산해, 그만큼 가까운 것들을 한 묶음으로 만든다. 그래서 줌을 당기면
  // 묶음이 저절로 풀리고(각자 보일 만큼 멀어지므로), 밀면 다시 묶인다.
  //
  // 격자에 그대로 나눠 담지 않고 이웃 칸까지 훑어 가까운 묶음에 붙이는
  // 이유는, 칸 경계에 딱 걸친 두 점이 바로 옆인데도 갈라지는 일을 막기
  // 위해서다.
  static const Map<_MarkerTier, double> _markerPixelSpan = {
    _MarkerTier.dot: 16,
    _MarkerTier.circle: 48,
    _MarkerTier.card: 70,
  };

  /// 좌표 환산에 쓰는 기준 위도(한국 중앙 언저리). 웹 메르카토르에서 위도별
  /// 축척 차이는 국내 범위에서 무시할 만해 상수 하나로 충분하다.
  static final double _cosReferenceLat = math.cos(36.5 * math.pi / 180);

  List<_MarkerGroup> _clusterListings(
    List<MapListing> items,
    _MarkerTier tier,
  ) {
    if (items.isEmpty) return const [];
    final span = _markerPixelSpan[tier]!;
    // 웹 메르카토르: 1픽셀 = 156543.03392·cos(위도)/2^zoom 미터.
    // 경도 폭은 cos(위도)가 약분돼 위도와 무관하고, 위도 폭만 cos를 곱한다.
    final lngCell = math.max(
      span * 156543.03392 / (111320 * math.pow(2, _currentZoom)),
      1e-7,
    );
    final latCell = math.max(lngCell * _cosReferenceLat, 1e-7);

    final buckets = <String, List<_MarkerGroup>>{};
    final groups = <_MarkerGroup>[];

    for (final item in items) {
      final ci = (item.lat / latCell).floor();
      final cj = (item.lng / lngCell).floor();
      _MarkerGroup? target;
      outer:
      for (var di = -1; di <= 1; di++) {
        for (var dj = -1; dj <= 1; dj++) {
          final neighbours = buckets['${ci + di}:${cj + dj}'];
          if (neighbours == null) continue;
          for (final group in neighbours) {
            if ((group.lat - item.lat).abs() <= latCell &&
                (group.lng - item.lng).abs() <= lngCell) {
              target = group;
              break outer;
            }
          }
        }
      }
      if (target != null) {
        target.items.add(item);
        continue;
      }
      final group = _MarkerGroup(lat: item.lat, lng: item.lng, items: [item]);
      groups.add(group);
      (buckets['$ci:$cj'] ??= []).add(group);
    }
    // 묶음 안의 순서는 종류 순서(파티 → 플레이스 → 장소대여)로 고정한다 —
    // 대표 항목(= 마커 id)이 스트림 도착 순서에 따라 흔들리지 않게.
    for (final group in groups) {
      group.items.sort(
        (a, b) => a.kind.index != b.kind.index
            ? a.kind.index - b.kind.index
            : a.docId.compareTo(b.docId),
      );
    }
    return groups;
  }

  // ── 마커 아이콘 ───────────────────────────────────────────────────
  //
  // 줌 3단계(점 / 원형 썸네일 / 핀+카드 썸네일)는 예전 그대로다. 달라진 것은
  // 종류마다 색과 글리프가 다르다는 것, 그리고 겹친 자리는 개수를 단 묶음
  // 마커 하나로 바뀐다는 것뿐이다.
  Future<({NOverlayImage icon, Size size, NPoint anchor})?> _buildMarkerIcon(
    _MarkerGroup group,
    _MarkerTier tier,
  ) async {
    if (!mounted) return null;

    if (group.items.length > 1) {
      final size = switch (tier) {
        _MarkerTier.dot => const Size(48, 24),
        _MarkerTier.circle => const Size(60, 30),
        _MarkerTier.card => const Size(68, 34),
      };
      final icon = await NOverlayImage.fromWidget(
        widget: _buildClusterMarkerWidget(group, size),
        size: size,
        context: context,
      );
      return (icon: icon, size: size, anchor: const NPoint(0.5, 0.5));
    }

    final item = group.first;
    if (tier == _MarkerTier.dot) {
      const size = Size(12, 12);
      final icon = await NOverlayImage.fromWidget(
        widget: _buildDotMarkerWidget(item.kind),
        size: size,
        context: context,
      );
      return (icon: icon, size: size, anchor: const NPoint(0.5, 0.5));
    }

    // 대표 미디어 판정은 세 종류가 같은 함수를 쓴다 — 동영상이 대표인
    // 게시물도 정지 썸네일 URL만 골라 준다(동영상 URL을 Image로 그리지 않음).
    // 🎊 공공 축제는 호스트 문서가 아니라 자기 작은 이미지를 쓴다.
    final festival = item.publicEvent;
    final cover = festival == null
        ? getPartyCoverMedia(item.data, tag: 'MapMarker')
        : null;
    final isVideo = cover?.isVideo ?? false;
    final thumbUrl = festival == null
        ? cover?.thumbnailUrl
        : (festival.thumbnailUrl ?? festival.imageUrl);
    ui.Image? image;
    if (thumbUrl != null && thumbUrl.isNotEmpty) {
      image = await _fetchDecodedImage(thumbUrl);
    }
    if (!mounted) return null;

    if (tier == _MarkerTier.circle && festival != null) {
      const size = Size(46, 46);
      final icon = await NOverlayImage.fromWidget(
        widget: _buildFestivalCircleMarkerWidget(image),
        size: size,
        context: context,
      );
      return (icon: icon, size: size, anchor: const NPoint(0.5, 0.5));
    }

    if (tier == _MarkerTier.circle) {
      const size = Size(46, 46);
      final icon = await NOverlayImage.fromWidget(
        widget: _buildCircleThumbMarkerWidget(
          item.kind,
          image,
          isVideo: isVideo,
        ),
        size: size,
        context: context,
      );
      return (icon: icon, size: size, anchor: const NPoint(0.5, 0.5));
    }

    const size = Size(70, 86);
    final icon = await NOverlayImage.fromWidget(
      widget: _buildThumbMarkerWidget(item.kind, image, isVideo: isVideo),
      size: size,
      context: context,
    );
    return (icon: icon, size: size, anchor: const NPoint(0.5, 1.0));
  }

  // 점 마커(줌이 낮을 때) — 종류 색 그대로라 멀리서도 색만으로 갈린다.
  static Widget _buildDotMarkerWidget(MapListingKind kind) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      color: kind.color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 1.5),
      boxShadow: const [
        BoxShadow(
          color: Color(0x55000000),
          blurRadius: 3,
          offset: Offset(0, 1),
        ),
      ],
    ),
  );

  // 원형 썸네일 위젯 — 핀 줄기가 없는 작은 원형 아바타. 테두리 색이 곧 종류다.
  static Widget _buildCircleThumbMarkerWidget(
    MapListingKind kind,
    ui.Image? image, {
    bool isVideo = false,
  }) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: kind.color, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: image != null
            ? RawImage(image: image, fit: BoxFit.cover)
            : Container(
                color: isVideo
                    ? const Color(0xFF1A1A2E)
                    : kind.color.withValues(alpha: 0.14),
                child: Icon(
                  isVideo ? Icons.videocam_outlined : kind.icon,
                  color: kind.color,
                  size: 18,
                ),
              ),
      ),
    );
  }

  // 🎊 공공 축제 원형 마커 — 파티츄 원형 썸네일([_buildCircleThumbMarkerWidget])과
  // 크기·모양은 같고, 청록 테두리에 오른쪽 아래 🎊 배지가 붙는다. 사진이
  // 무엇이든 "공공 축제"가 먼저 읽히게 하려는 것이다. 파티츄 마커 위젯은
  // 건드리지 않고 따로 둔다.
  static Widget _buildFestivalCircleMarkerWidget(ui.Image? image) {
    const kind = MapListingKind.festival;
    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: kind.color, width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 5,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: image != null
                    ? RawImage(image: image, fit: BoxFit.cover)
                    : Container(
                        color: kind.color.withValues(alpha: 0.14),
                        child: Icon(kind.icon, color: kind.color, size: 18),
                      ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 17,
              height: 17,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: kind.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                kind.emoji,
                style: const TextStyle(fontSize: 8.5, height: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 썸네일 마커 위젯 (RawImage로 동기 렌더링) ────────────────────
  // 썸네일 이미지가 없을 때: 동영상 대표 게시물은 동영상 아이콘 placeholder,
  // 그 외에는 종류 글리프 placeholder — 어느 쪽이든 마커 자체는 그려진다.
  //
  // 사진이 무엇이든 종류가 먼저 읽히도록, 썸네일 위 왼쪽 모서리에 종류 글리프
  // 배지를 얹고 핀 줄기·끝점도 종류 색으로 그린다.
  static Widget _buildThumbMarkerWidget(
    MapListingKind kind,
    ui.Image? image, {
    bool isVideo = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: kind.color, width: 2.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: image != null
                      ? RawImage(image: image, fit: BoxFit.cover)
                      : Container(
                          color: isVideo
                              ? const Color(0xFF1A1A2E)
                              : kind.color.withValues(alpha: 0.14),
                          child: Icon(
                            isVideo ? Icons.videocam_outlined : kind.icon,
                            color: kind.color,
                            size: 26,
                          ),
                        ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(3, 2, 4, 3),
                  decoration: BoxDecoration(
                    color: kind.color,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      bottomRight: Radius.circular(9),
                    ),
                  ),
                  child: Icon(kind.icon, size: 10, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        // 핀 줄기
        Container(width: 2.5, height: 12, color: kind.color),
        // 핀 끝 점
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: kind.color),
        ),
      ],
    );
  }

  // 겹친 자리를 대표하는 묶음 마커 — 섞여 있는 종류의 글리프와 개수를 함께
  // 보여준다. 눌러야 안을 볼 수 있다는 것이 모양으로 드러나야 해서, 단일
  // 마커(사진/점)와 일부러 다른 알약 모양을 쓴다.
  static Widget _buildClusterMarkerWidget(_MarkerGroup group, Size size) {
    final kinds = group.kinds;
    return Container(
      width: size.width,
      height: size.height,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size.height / 2),
        border: Border.all(
          // 한 종류만 겹쳤으면 그 종류 색, 여러 종류가 섞였으면 중립색.
          color: kinds.length == 1
              ? kinds.first.color
              : const Color(0xFF3A2E39),
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final kind in kinds)
              Padding(
                padding: const EdgeInsets.only(right: 1),
                child: Icon(
                  kind.icon,
                  size: size.height * 0.44,
                  color: kind.color,
                ),
              ),
            const SizedBox(width: 3),
            Text(
              '${group.items.length}',
              style: TextStyle(
                fontSize: size.height * 0.46,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF3A2E39),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 마커 탭 ───────────────────────────────────────────────────────
  //
  // 하나짜리 마커는 예전처럼 지도 위 미리보기 카드를 띄우고, 겹친 자리는
  // **그 자리의 목록을 통째로 펼친다** — 어느 것도 다른 것에 가려 못 고르는
  // 일이 없어야 하기 때문이다. 무엇을 열지·카메라를 옮길지는
  // [mapMarkerTapPlan] 하나가 정한다(묶음은 줌과 무관하게 바로 목록, 카메라
  // 이동 없음).
  void _onMarkerTap(_MarkerGroup group) {
    if (_home) {
      _onHomeMarkerTap(group);
      return;
    }
    final plan = mapMarkerTapPlan(group.items);
    if (plan.action == MapMarkerTapAction.openGroupList) {
      setState(() => _tapped = null);
      _openGroupSheet(group);
      return;
    }
    if (plan.centerCamera) {
      _mapController?.updateCamera(
        NCameraUpdate.withParams(target: NLatLng(group.lat, group.lng)),
      );
    }
    if (plan.action == MapMarkerTapAction.openFestivalDetail) {
      _openDetail(group.first);
      return;
    }
    setState(() => _tapped = group.first);
  }

  /// 같은 자리에 겹친 항목들을 고르는 시트 — 카드는 하단 목록과 **같은 것**을
  /// 쓴다(파티는 [PartyCard], 장소 계열은 [PlaceCompactCard]). 누르면 각 카드가
  /// 원래 가던 상세 화면으로 그대로 이어진다.
  Future<void> _openGroupSheet(_MarkerGroup group) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFFFFF4F8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                child: Text(
                  '이 위치의 콘텐츠 ${group.items.length}개',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (group.first.shortAddress.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    group.first.shortAddress,
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final item in group.items)
                      _buildListCard(
                        item,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _openDetail(item);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 이미지 다운로드 후 ui.Image로 디코딩 (캐시 우선) ────────────
  Future<ui.Image?> _fetchDecodedImage(String url) async {
    if (_imageCache.containsKey(url)) return _imageCache[url];
    try {
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final codec = await ui.instantiateImageCodec(res.bodyBytes);
        final frame = await codec.getNextFrame();
        _imageCache[url] = frame.image;
        return frame.image;
      }
    } catch (e) {
      debugPrint('[MapMarker] image fetch/decode error: $e  url=$url');
    }
    return null;
  }

  void _dismissTappedCard() {
    if (_home) {
      if (_dateTimePaneOpen) setState(() => _dateTimePaneOpen = false);
      _selectHomeItem(null);
      return;
    }
    if (_tapped != null) {
      setState(() => _tapped = null);
    }
  }

  // ── 카메라 idle 감지 ───────────────────────────────────────────────
  Future<void> _onCameraIdle() async {
    if (!_mapInitialized) return;

    final pos = await _mapController?.getCameraPosition();
    if (!mounted) return;
    final newZoom = pos?.zoom ?? _currentZoom;
    final wasTier = _tierForZoom(_currentZoom);
    final isTier = _tierForZoom(newZoom);
    _currentZoom = newZoom;
    // 3단계(점/원형/카드) 전환뿐 아니라 **줌 한 칸**이 바뀌어도 다시 그린다 —
    // 겹침 묶음의 크기가 줌에 따라 정해지므로(마커 픽셀 폭 → 좌표 폭),
    // 단계 안에서 확대만 해도 묶여 있던 것이 풀려야 한다.
    // (홈은 선택하지 않은 마커를 원형 썸네일까지만 키운다 — [_markerTierForZoom].)
    if (wasTier != isTier || newZoom.floor() != _syncedZoomStep) {
      _syncMarkers();
    } else if (_festivalSyncBox != null) {
      // 🎊 공공 축제는 화면 근처 것만 마커로 만들어 두었다 — 화면이 그 넓힌
      // 상자를 벗어났을 때만 다시 그린다(조금 움직이는 것으로는 그리지 않는다).
      final view = await _mapController?.getContentBounds();
      if (!mounted) return;
      if (view != null && !boxContains(_festivalSyncBox!, _boxOf(view))) {
        _syncMarkers();
      }
    }

    if (_pendingAreaSearch) {
      // '현재 위치'로 옮긴 직후 — 기다릴 이유가 없다(사용자가 방금 누른
      // 버튼의 결과다). 조금만 움직였더라도 그 자리를 조회한다.
      _pendingAreaSearch = false;
      _ignoreNextIdle = false;
      _autoSearchTimer?.cancel();
      _runAreaSearch(force: true, expandSheet: true);
    } else if (_ignoreNextIdle) {
      // 앱이 옮긴 카메라(마커 가운데 맞춤·검색 결과로 이동)다 — 사용자가
      // 지도를 움직인 것이 아니므로 다시 찾지 않는다.
      _ignoreNextIdle = false;
    } else {
      _scheduleAutoSearch();
    }
  }

  /// 카메라가 멈췄다 — 조금 기다렸다가 이 영역으로 다시 찾는다.
  ///
  /// 이어서 또 움직이면 타이머를 다시 걸므로, 드래그 → 확대 → 드래그를
  /// 빠르게 해도 **마지막 자리에서 한 번만** 돈다.
  void _scheduleAutoSearch() {
    _autoSearchTimer?.cancel();
    _autoSearchTimer = Timer(kMapAutoSearchDebounce, () {
      if (!mounted) return;
      _runAreaSearch();
    });
  }

  /// 지금 화면 영역으로 목록·마커를 좁힌다.
  ///
  /// [force]가 아니면 지난번 조회한 영역과 견줘 **의미 있게 움직였을 때만**
  /// 돈다([mapViewChangedEnough]) — 손가락이 스친 정도로는 돌지 않는다.
  Future<void> _runAreaSearch({
    bool force = false,
    bool expandSheet = false,
  }) async {
    final controller = _mapController;
    if (controller == null) return;
    // bounds를 읽는 사이에 지도가 또 움직일 수 있다 — 번호가 밀리면 물러난다.
    final generation = ++_areaSearchGeneration;
    final bounds = await controller.getContentBounds();
    if (!mounted || generation != _areaSearchGeneration) return;

    if (!force) {
      final last = _lastSearchBounds;
      final changed = mapViewChangedEnough(
        last == null ? null : _boxOf(last),
        _boxOf(bounds),
      );
      if (!changed) return;
    }

    setState(() {
      _lastSearchBounds = bounds;
      _isAreaSearch = true;
      _recomputeVisible();
    });
    // 홈은 마커가 곧 결과다 — 좁힌 영역으로 마커를 다시 맞춘다.
    // ([_syncMarkers]는 달라진 마커만 건드린다 — 전부 지웠다 그리지 않는다.)
    if (_home) _syncMarkers();
    // 시트는 사용자가 누른 동작일 때만 펼친다. 지도를 훑을 때마다 시트가
    // 올라오면 지도를 가려 훑을 수가 없다.
    if (expandSheet) _ensureSheetExpanded();
  }

  static ({double south, double west, double north, double east}) _boxOf(
    NLatLngBounds b,
  ) => (
    south: b.southWest.latitude,
    west: b.southWest.longitude,
    north: b.northEast.latitude,
    east: b.northEast.longitude,
  );

  // ── 지도 영역 기준 필터 ───────────────────────────────────────────
  List<MapListing> _filterByBounds(
    List<MapListing> items,
    NLatLngBounds bounds,
  ) {
    final sw = bounds.southWest;
    final ne = bounds.northEast;
    return items
        .where(
          (item) =>
              item.lat >= sw.latitude &&
              item.lat <= ne.latitude &&
              item.lng >= sw.longitude &&
              item.lng <= ne.longitude,
        )
        .toList();
  }

  // ── 상세검색 필터 적용 ────────────────────────────────────────────
  //
  // 종류 선택과 상세검색은 **AND**로 걸린다. 다만 상세검색 시트는 파티 조건을
  // 묻는 시트라, 조건마다 다른 종류에 걸 수 있는 뜻이 있는지가 갈린다.
  //
  //  · 지역·날짜 → 세 종류 모두에 건다. 장소 계열에서 "그 날짜"의 뜻은
  //    "그날 문을 여는가"이므로 요일별 정기 휴무로 판정한다([isPlaceOpenOnDate]).
  //  · 참가비·성별·연령·태그·얼리버드·신청 가능 → **파티에만** 건다. 장소
  //    계열에는 대응하는 값 자체가 없어서, 걸면 조건을 켜는 순간 플레이스와
  //    장소대여가 통째로 사라진다(조건에 맞지 않아서가 아니라 물어볼 수가
  //    없어서). 그건 AND가 아니라 "다른 종류 끄기"다.
  /// 빠른 필터 '더보기' — 지도에는 플레이스 전용 상세검색이 없으므로
  /// 특징 전체를 한 장에 담은 가벼운 시트를 띄운다. 값은 같은
  /// [_placeDiscovery]를 그대로 고치므로 바와 어긋날 수 없다.
  Future<void> _openPlaceFeatureSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '플레이스 특징',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setSheetState(
                        () => setState(() {
                          _placeDiscovery.clearDiscovery();
                          _recomputeVisible();
                        }),
                      ),
                      child: const Text(
                        '초기화',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFF6FA0),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in PlaceFeatures.selectable)
                      GestureDetector(
                        onTap: () => setSheetState(
                          () => setState(() {
                            _placeDiscovery.toggleFeature(f.key);
                            _recomputeVisible();
                          }),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _placeDiscovery.isFeatureOn(f.key)
                                ? const Color(0xFFFF6FA0)
                                : const Color(0xFFF6F6F8),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            f.display,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _placeDiscovery.isFeatureOn(f.key)
                                  ? Colors.white
                                  : const Color(0xFF4A4A55),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _matchesFilter(MapListing item) {
    // 홈 카테고리(멀티선택) — 켜 둔 칸 중 **하나라도** 받아 주면 남는다.
    if (!_homeCategoryAccepts(item)) return false;
    // 🎊 공공 축제는 자기 판정 하나로 끝난다(아래 파티츄 조건은 그 값이 없다).
    if (item.kind == MapListingKind.festival) return _matchesFestival(item);
    // 검색어(홈 검색창) — 목록 탭과 같은 매칭 함수다.
    if (_query.isNotEmpty) {
      final hit = item.kind == MapListingKind.party
          ? partySearchMatches(item.data, _query)
          : listingTextMatches(item.data, _query);
      if (!hit) return false;
    }
    // 플레이스 조건은 플레이스에만. 목록 화면과 **같은 함수**를 부르므로
    // 지도와 플레이스 탭의 결과가 갈릴 수 없다.
    if (item.kind == MapListingKind.place &&
        !_placeDiscovery.matchesDiscovery(
          item.data,
          // 🎉 With파티는 문서 id로 파티 연결을 되짚는다.
          docId: item.docId,
          partyIndex: _withPartyIndex,
          // 🎪 이벤트도 같다 — 판정은 `placePromotions` 쪽에 있다.
          eventIndex: _placeEventIndex,
        )) {
      return false;
    }
    // 💳 플레이스 가격대 — 목록 탭과 같은 라벨 비교([eventPriceMatches]).
    if (item.kind == MapListingKind.place &&
        !eventPriceMatches(item.data, _placeDiscovery.priceRanges)) {
      return false;
    }
    // 💳 장소대여 시간당 요금 — 목록 탭과 같은 판정. 가격 문의 공간은 금액을
    // 모르므로 조건을 켜면 빠진다([rentalPriceMatches]).
    if (item.kind == MapListingKind.rental &&
        !rentalPriceMatches(item.data, _rentalDiscovery.priceRanges)) {
      return false;
    }
    // 🎪 이벤트는 **장소대여에도** 걸린다 — 조건을 켜면 이벤트를 하는 곳만
    // 남는다는 뜻이 종류마다 달라질 이유가 없다. 예전에는 이 조건이 플레이스
    // 마커에만 걸려서, 같은 조건인데 장소대여는 목록에서만 걸러지고 지도에는
    // 전부 남았다.
    //
    // 나머지 플레이스 조건(업종·특징·속성)은 여기 걸지 않는다 — 장소대여에는
    // 그 값 자체가 없어서 걸면 조건을 켜는 순간 통째로 사라진다(위 주석과 같은
    // 이유). 이벤트만은 두 컬렉션 모두에 실제로 있는 축이다.
    //
    // 판정은 장소대여 목록과 **같은 함수·같은 컬렉션의 색인**이다
    // ([PlaceFilter.matchesEvent]도 이 함수를 부른다).
    if (item.kind == MapListingKind.rental &&
        !PlaceEventIndex.allows(
          eventOnly: _placeDiscovery.eventOnly,
          docId: item.docId,
          index: _rentalEventIndex,
          // 📅🕐 도 함께 넘긴다 — 이벤트 탭·플레이스 목록과 **같은 함수에
          // 같은 조건**이라 세 화면의 답이 갈릴 수 없다. 문서는 영업중(전시간)
          // 이벤트의 영업시간을 읽는 데 쓰인다.
          doc: item.data,
          dates: _placeDiscovery.visitDates,
          start: _placeDiscovery.startTime,
          end: _placeDiscovery.endTime,
        )) {
      return false;
    }
    if (!_filter.isActive) return true;
    if (item.kind == MapListingKind.party) {
      return _matchesDetailFilter(item.data);
    }
    return _matchesSharedFilter(item);
  }

  /// 🎊 공공 축제에 걸 수 있는 조건만 — 검색어·지역·날짜.
  ///
  /// 날짜는 **행사 기간이 그날과 겹치면** 통과다([PublicEvent.overlapsDay]:
  /// 시작 ≤ 그날 끝 && 종료 ≥ 그날 시작). 여러 날은 OR(하루라도 겹치면)이다.
  /// 🕐 시간 조건·참가비·성별·플레이스 특징은 걸지 않는다 — 공공 축제에는 그
  /// 값이 없어서, 걸면 조건을 켜는 순간 통째로 사라진다([_matchesSharedFilter]
  /// 주석과 같은 이유).
  bool _matchesFestival(MapListing item) {
    final e = item.publicEvent;
    if (e == null) return false;
    if (_query.isNotEmpty && !listingTextMatches(item.data, _query)) {
      return false;
    }
    if (_filter.districts.isNotEmpty &&
        !RegionData.addressMatchesDistrictFilter(
          item.addressText,
          _filter.districts,
        )) {
      return false;
    }
    if (_filter.dateOptions.isNotEmpty) {
      final now = DateTime.now();
      final days = _filter.dateOptions.expand((o) => _daysOfDateOption(o, now));
      if (!days.any(e.overlapsDay)) return false;
    }
    if (_filter.selectedDates.isNotEmpty &&
        !_filter.selectedDates.any(e.overlapsDay)) {
      return false;
    }
    if (_placeDiscovery.visitDates.isNotEmpty &&
        !_placeDiscovery.visitDates.any(e.overlapsDay)) {
      return false;
    }
    return true;
  }

  /// 장소 계열(플레이스/장소대여)에 걸 수 있는 조건만 추린 판정.
  bool _matchesSharedFilter(MapListing item) {
    if (_filter.districts.isNotEmpty) {
      // 파티는 `district` 필드를 갖지만 장소 계열은 주소 문자열뿐이다 —
      // 목록 화면(플레이스·장소대여 탭)도 주소 대조로 지역을 거른다.
      // '서울 (전체)' 같은 선택값은 주소 맨 앞의 시/도로만 판정한다 — 그 지역의
      // 구 이름이 들어 있는지로 보면 '중구'처럼 여러 시/도에 같은 이름이 있는
      // 구 때문에 엉뚱한 지역이 걸린다(RegionData 주석 참고).
      if (!RegionData.addressMatchesDistrictFilter(
        item.addressText,
        _filter.districts,
      )) {
        return false;
      }
    }

    final now = DateTime.now();
    if (_filter.dateOptions.isNotEmpty) {
      final days = _filter.dateOptions.expand((o) => _daysOfDateOption(o, now));
      // 고른 기간 중 **하루라도** 여는 곳이면 통과(파티의 날짜 조건도 OR다).
      if (!days.any((d) => isPlaceOpenOnDate(item.data, d))) return false;
    }
    if (_filter.selectedDates.isNotEmpty) {
      if (!_filter.selectedDates.any((d) => isPlaceOpenOnDate(item.data, d))) {
        return false;
      }
    }
    return true;
  }

  /// '오늘'/'내일'/'이번주'/'이번주말'이 가리키는 날짜들.
  /// 파티 쪽 판정([_matchesDateOption])과 **같은 구간**을 날짜 단위로 편 것이다.
  static List<DateTime> _daysOfDateOption(String option, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: now.weekday - 1));
    return switch (option) {
      '오늘' => [today],
      '내일' => [today.add(const Duration(days: 1))],
      '이번주' => [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))],
      '이번주말' => [
        monday.add(const Duration(days: 5)),
        monday.add(const Duration(days: 6)),
      ],
      _ => const [],
    };
  }

  /// 선택된 구/시/군(district) 중 하나라도 일치하면 통과.
  /// district 필드가 없는 기존 데이터는 region(시/도) 기준으로 하위호환 매칭한다.
  // 목록 화면과 **같은 판정**을 쓴다 — 규칙이 갈리면 같은 파티가 목록에만
  // 보이거나 지도에만 보인다(RegionData.matchesDistrictFilter).
  bool _matchesDistrictFilter(
    Map<String, dynamic> p,
    Set<String> selectedDistricts,
  ) => RegionData.matchesDistrictFilter(p, selectedDistricts);

  // 연령대(10년 단위) 선택값 중 하나라도 파티의 연령 제한 범위와 겹치면 통과.
  // 연령 제한은 **성별별**이므로 모집하는 성별 중 하나라도 겹치면 열려 있는
  // 것으로 본다(PartyAgeRestriction.opensToBirthYearRange). 이 필터는 "이
  // 파티가 그 연령대를 받는가"를 묻는 것이고, "내가 신청할 수 있는가"는
  // 아래 eligibleOnly(checkPartyEligibility)가 자기 성별 기준으로 판정한다.
  // 파티에 연령 제한이 없으면(ageRestrictionEnabled=false) 모든 연령대에
  // 열려 있는 것으로 간주한다.
  bool _matchesAgeGroups(Map<String, dynamic> p, Set<String> groups) {
    final age = PartyAgeRestriction.fromMap(p);
    final genderLimit = p['genderLimit'] as String? ?? 'all';
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
        // 목록(main_screen)과 지도가 같은 표를 써야 결과가 갈리지 않는다.
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

  bool _matchesDetailFilter(Map<String, dynamic> p) {
    if (_filter.districts.isNotEmpty) {
      if (!_matchesDistrictFilter(p, _filter.districts)) return false;
    }
    if (_filter.genderConditions.isNotEmpty) {
      final gl = p['genderLimit'] as String? ?? 'all';
      final gcm = p['genderCapacityMode'] as String? ?? 'unlimited';
      final gm = p['genderMode'] as String? ?? '';
      final label = gl == 'male'
          ? '남자만'
          : gl == 'female'
          ? '여자만'
          : (gm == 'balanced' || gcm == 'separate')
          ? '성비 맞춤'
          : '남녀무관';
      if (!_filter.genderConditions.contains(label)) return false;
    }
    // 목록과 **같은 함수**로 판정한다(최소 참가비 기준, [partyFeeMatches]).
    if (!partyFeeMatches(p, _filter.feeRanges)) return false;
    if (_filter.ageGroups.isNotEmpty) {
      if (!_matchesAgeGroups(p, _filter.ageGroups)) return false;
    }
    if (_filter.tagKeywords.isNotEmpty) {
      final tags = (p['tags'] as List?)?.cast<String>() ?? [];
      final lowerTags = tags.map((t) => t.toLowerCase()).toList();
      final matched = _filter.tagKeywords.any((kw) {
        final k = kw.toLowerCase();
        return lowerTags.any((t) => t.contains(k));
      });
      if (!matched) return false;
    }
    if (_filter.eligibleOnly) {
      // 단순 모집 상태가 아니라, 로그인한 사용자가 실제로 신청 가능한
      // 파티인지(성별/연령 조건 + 정원 + 모집 마감 여부)까지 확인한다.
      // 모집 상태는 **내 성별 기준**이다(목록 화면과 같은 판정) —
      // 호스트가 남/여 모집을 따로 닫아 둘 수 있다(PartyGenderRecruit).
      if (PartyCard.effectiveStatusFor(p, UserSession.gender) != '모집중') {
        return false;
      }
      final elig = checkPartyEligibility(
        p,
        UserSession.gender,
        UserSession.birthYear,
      );
      if (elig != PartyEligibility.eligible) return false;
    }
    // 파티 규모 — 목록 화면과 같은 판정(PartyScaleFilter).
    if (!PartyScaleFilter.matches(p, _filter.partyScale)) return false;
    if (_filter.earlyBirdOnly && !EarlyBird.isActive(p)) return false;
    if (_filter.dateOptions.isNotEmpty) {
      final dt = PartyCard.parsePartyDateTime(p);
      if (dt == null) return false;
      final now = DateTime.now();
      if (!_filter.dateOptions.any((opt) => _matchesDateOption(dt, opt, now))) {
        return false;
      }
    }
    // 날짜 직접 선택 + 시간 범위 필터 — 고른 날짜 중 하루라도 맞으면 통과(OR).
    if (_filter.selectedDates.isNotEmpty) {
      final dt = PartyCard.parsePartyDateTime(p);
      if (dt == null) return false;
      final partyDay = DateTime(dt.year, dt.month, dt.day);
      if (!_filter.selectedDates.any(
        (d) => partyDay == DateTime(d.year, d.month, d.day),
      )) {
        return false;
      }
      final partyMins = dt.hour * 60 + dt.minute;
      if (_filter.startTime != null) {
        final startMins =
            _filter.startTime!.hour * 60 + _filter.startTime!.minute;
        if (partyMins < startMins) return false;
      }
      if (_filter.endTime != null) {
        final endMins = _filter.endTime!.hour * 60 + _filter.endTime!.minute;
        if (partyMins > endMins) return false;
      }
    }
    // 시간 조건(지정 시간 / 지정 구간) — 목록 화면과 **같은 판정**
    // ([PartyTimeFilter]). 지도와 목록이 같은 [PartyFilter]를 쓰므로 같은
    // 조건에서 다른 결과가 나오면 안 된다.
    if (PartyTimeFilter.isActive(
      _filter.timeOfDayStart,
      _filter.timeOfDayEnd,
    )) {
      final intervals = PartyTimeFilter.intervalsOf(
        p,
        onDays: _filter.selectedDates,
      );
      if (!PartyTimeFilter.matches(
        intervals,
        _filter.timeOfDayStart,
        _filter.timeOfDayEnd,
      )) {
        return false;
      }
    }
    return true;
  }


  static bool _matchesDateOption(DateTime dt, String option, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    switch (option) {
      case '오늘':
        return dt.isAfter(today.subtract(const Duration(seconds: 1))) &&
            dt.isBefore(tomorrow);
      case '내일':
        return dt.isAfter(tomorrow.subtract(const Duration(seconds: 1))) &&
            dt.isBefore(tomorrow.add(const Duration(days: 1)));
      case '이번주':
        final monday = today.subtract(Duration(days: now.weekday - 1));
        final sunday = monday.add(const Duration(days: 7));
        return dt.isAfter(monday.subtract(const Duration(seconds: 1))) &&
            dt.isBefore(sunday);
      case '이번주말':
        final monday = today.subtract(Duration(days: now.weekday - 1));
        final saturday = monday.add(const Duration(days: 5));
        final sunday = monday.add(const Duration(days: 7));
        return dt.isAfter(saturday.subtract(const Duration(seconds: 1))) &&
            dt.isBefore(sunday);
      default:
        return true;
    }
  }

  // ── 상세검색 시트 열기 ────────────────────────────────────────────
  Future<void> _openDetailSearch() async {
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
        // 홈은 검색창과 상세필터가 한 시트다(목록 탭의 검색 시트와 같은 구성).
        search: _home
            ? SearchEntryConfig(
                title: '검색',
                hintText: '파티·플레이스·장소 이름, 지역, 키워드',
                controller: _queryCtrl,
                onQueryChanged: _onQueryChanged,
              )
            : null,
      ),
    );
    if (result != null) {
      setState(() {
        _filter = result;
        _recomputeVisible();
      });
      // 상세검색 조건은 마커에도 걸린다 — 목록만 좁아지고 지도는 그대로면
      // 두 곳이 다른 이야기를 하게 된다.
      _syncMarkers();
    }
  }

  /// 종류 칩이 바뀌었을 때 — **상세검색 조건은 건드리지 않는다.** 지역·날짜로
  /// 좁혀 둔 것이 종류를 켜고 끌 때마다 풀리면 조건을 다시 걸어야 한다.
  void _onKindsChanged(Set<MapListingKind> kinds) {
    final placeTurnedOn =
        kinds.contains(MapListingKind.place) &&
        !_kinds.contains(MapListingKind.place);
    setState(() {
      _kinds = kinds;
      _recomputeVisible();
    });
    _syncMarkers();
    // 플레이스를 켜면 머리에 대분류·빠른필터 두 줄이 새로 붙는다. 시트가 접혀
    // 있으면 그것들이 접힌 선 아래에 생겨 "눌렀는데 아무 일도 안 난" 것처럼
    // 보이므로, 목록이 보일 만큼 펼쳐 준다(영역 검색과 같은 처리).
    // 이미 그보다 크게 열어 둔 상태면 줄이지 않는다.
    if (placeTurnedOn) _ensureSheetExpanded();
  }

  // 시트가 사용자에 의해 접혀 있으면(예: minChildSize까지 드래그) 새로
  // 조회된 목록이 보이도록 충분한 높이로 펼친다. 이미 그보다 더 펼쳐져
  // 있으면(사용자가 크게 열어둔 상태) 굳이 줄이지 않는다.
  void _ensureSheetExpanded() {
    if (!_sheetController.isAttached) return;
    if (_sheetController.size < _sheetExpandedSize) {
      _sheetController.animateTo(
        _sheetExpandedSize,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // ── 현재 위치 이동 ─────────────────────────────────────────────────
  /// [areaSearch]가 false면 카메라만 옮긴다(홈 첫 진입의 자동 이동).
  Future<void> _goToCurrentLocation({bool areaSearch = true}) async {
    setState(() => _isLoadingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('위치 권한이 필요합니다')));
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final latLng = NLatLng(position.latitude, position.longitude);
      _myLatLng = latLng;

      // onCameraIdle 발생 시 자동 영역 검색 실행
      _pendingAreaSearch = areaSearch;
      _ignoreNextIdle = !areaSearch;

      await _mapController?.updateCamera(
        NCameraUpdate.withParams(target: latLng, zoom: 15),
      );

      if (_currentLocationMarker != null) {
        await _mapController?.deleteOverlay(_currentLocationMarker!.info);
      }
      _currentLocationMarker = NMarker(id: 'my_location', position: latLng);
      await _mapController?.addOverlay(_currentLocationMarker!);
    } catch (e) {
      _pendingAreaSearch = false;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('위치를 가져올 수 없습니다: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  // ── build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_home) return _buildHome(context);
    final screenHeight = MediaQuery.of(context).size.height;
    const sheetSize = 0.35;

    return Scaffold(
      backgroundColor: const Color(0xFFEEF8FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '지도',
          style: TextStyle(
            color: Colors.black,
            fontFamily: 'SeoulHangang',
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(color: Colors.black, offset: Offset(0.3, 0)),
              Shadow(color: Colors.black, offset: Offset(-0.3, 0)),
              Shadow(color: Colors.black, offset: Offset(0, 0.3)),
              Shadow(color: Colors.black, offset: Offset(0, -0.3)),
            ],
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // ── 네이버 지도 ─────────────────────────────────────────
          //
          // flutter_naver_map에는 웹 구현이 없고, main.dart도 웹에서는 SDK
          // init을 건너뛴다. 그 상태로 NaverMap을 그리면 이 화면이 통째로
          // 예외로 죽는다 — 웹에서는 지도 자리만 안내로 대신한다. 아래 목록
          // 시트(플레이스·파티 카드)는 지도 없이도 그대로 동작한다.
          if (kIsWeb) const _WebMapUnavailable() else _buildNaverMap(),

          // (종류 선택 칩은 지도 위에 없다 — 아래 목록 시트의 머리줄 한 곳에서만
          //  고른다. 같은 선택이 두 곳에 있으면 어느 쪽이 정본인지 알 수 없고,
          //  지도가 그만큼 좁아진다. MapKindFilterBar 주석 참고.)


          // ── 현재 위치 버튼 ── 시트를 드래그하거나 _ensureSheetExpanded로
          // 펼쳐도 항상 시트 바로 위에 떠 있도록 실제 현재 높이를 따라간다.
          AnimatedBuilder(
            animation: _sheetController,
            builder: (context, _) {
              final extent = _sheetController.isAttached
                  ? _sheetController.size
                  : sheetSize;
              return Positioned(
                right: 16,
                bottom: screenHeight * extent + 16,
                child: FloatingActionButton(
                  heroTag: 'map_location_fab',
                  onPressed: _isLoadingLocation ? null : _goToCurrentLocation,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  elevation: 4,
                  child: _isLoadingLocation
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                ),
              );
            },
          ),

          // ── 목록 바텀 시트 ──────────────────────────────────────
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: sheetSize,
            minChildSize: 0.15,
            maxChildSize: 0.85,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF4F8),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 12,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                // ⚠️ 시트 안은 **통째로 하나의 스크롤**이다. 예전에는
                // `Column(손잡이 · 머리줄 · 필터 …, Expanded(ListView))`였는데
                // 두 가지가 동시에 깨졌다.
                //
                //  ① 오버플로 — 시트 높이는 `화면높이 × extent`다. 접힌 상태
                //     (minChildSize 0.15 ≈ 120px)에서 고정 머리 부분이
                //     플레이스 필터까지 더해 230px을 넘어가면, Expanded는 0
                //     아래로 못 줄어드니 그대로 밖으로 넘쳤다
                //     ("BOTTOM OVERFLOWED BY 151 PIXELS"). 플레이스를 켰을
                //     때만 터진 이유가 이것이다.
                //
                //  ② 드래그 불가 — DraggableScrollableSheet는 builder가 준
                //     [scrollController]가 **붙은 스크롤 위젯** 위에서만 끌린다.
                //     그 컨트롤러는 Expanded 안 ListView에만 달려 있었으므로
                //     ⑴ 손잡이·머리줄·필터를 잡고 끌면 아무 일도 없었고,
                //     ⑵ 오버플로로 ListView 높이가 0이 되면 잡을 곳 자체가
                //        사라져 시트가 전혀 안 움직였다(빈 목록도 마찬가지 —
                //        빈 화면에는 컨트롤러를 달지 않았다).
                //
                // 그래서 손잡이부터 목록까지 **전부 슬리버 하나의 스크롤**에
                // 넣는다. Column/Expanded가 없으니 내용이 아무리 길어져도
                // RenderFlex 오버플로가 구조적으로 불가능하고, 시트 어디를
                // 잡아도 끌린다(위로 끌면 펼쳐지고, 끝까지 펼친 뒤에는 목록이
                // 이어서 스크롤된다). 필터 높이가 대분류(2줄)↔드릴다운(1줄)로
                // 바뀌어도 다시 계산할 고정 높이가 없다.
                //
                // 머리를 SliverPersistentHeader로 고정하지 않는 이유도 같다 —
                // 그건 min/max 높이를 숫자로 박아야 하는데, 그 숫자가 어긋난
                // 것이 애초에 이 버그였다.
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverToBoxAdapter(child: _buildSheetHeader()),
                    if (_displayed.isEmpty)
                      // hasScrollBody: false — 남은 공간을 채우되, 내용이 그보다
                      // 크면 그만큼 늘어난다(잘리지 않는다).
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyState(),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.all(16),
                        sliver: SliverList.builder(
                          itemCount: _displayed.length,
                          itemBuilder: (context, index) =>
                              _buildListCard(_displayed[index]),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),

          // ── 마커 탭 시 정보 카드 ────────────────────────────────
          if (_tapped != null)
            AnimatedBuilder(
              animation: _sheetController,
              builder: (context, _) {
                final extent = _sheetController.isAttached
                    ? _sheetController.size
                    : sheetSize;
                return Positioned(
                  left: 12,
                  right: 12,
                  bottom: screenHeight * extent + 8,
                  child: _buildTappedCard(_tapped!),
                );
              },
            ),
        ],
      ),
    );
  }

  // ── 네이버 지도 본체 — 지도 화면과 홈이 같은 위젯을 쓴다 ─────────────
  Widget _buildNaverMap() => NaverMap(
    options: const NaverMapViewOptions(
      initialCameraPosition: NCameraPosition(
        target: NLatLng(37.5665, 126.9780),
        zoom: 12,
      ),
    ),
    onMapReady: (controller) {
      _mapController = controller;
      if (_mapItems.isNotEmpty) {
        _syncMarkers();
      }
      // 초기 onCameraIdle 무시를 위해 한 프레임 후 초기화 완료 표시
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _mapInitialized = true);
      });
      // 홈은 "열자마자 내 주변"이다 — 위치 권한이 **이미 있을 때만** 조용히
      // 내 위치로 옮긴다(앱을 켜자마자 권한 팝업을 띄우지 않는다).
      if (_home) _locateIfPermitted();
    },
    onMapTapped: (point, coord) => _dismissTappedCard(),
    onCameraIdle: () {
      _onCameraIdle();
    },
  );

  // ══════════════════════════════════════════════════════════════════
  // 홈 모드 — 지도 중심 탐색
  // ══════════════════════════════════════════════════════════════════

  /// 마커를 그릴 단계 — 홈은 **선택하지 않은 마커**를 원형 썸네일까지만
  /// 키운다(모든 콘텐츠의 큰 사진 핀이 지도를 덮지 않게). 선택한 마커만
  /// 사진 핀으로 강조한다([_buildSelectedMarkerIcon]).
  _MarkerTier _markerTierForZoom(double zoom) {
    final tier = _tierForZoom(zoom);
    if (_home && tier == _MarkerTier.card) return _MarkerTier.circle;
    return tier;
  }

  bool _isSelectedGroup(_MarkerGroup group) =>
      _home && group.items.length == 1 && group.first.key == _selectedKey;

  /// 선택한 마커 — 대표 사진을 담은 핀(지도 화면의 확대 단계 핀과 같은 모양).
  Future<({NOverlayImage icon, Size size, NPoint anchor})?>
  _buildSelectedMarkerIcon(MapListing item) async {
    if (!mounted) return null;
    final cover = getPartyCoverMedia(item.data, tag: 'MapHomeSelected');
    final isVideo = cover?.isVideo ?? false;
    final thumbUrl = cover?.thumbnailUrl;
    ui.Image? image;
    if (thumbUrl != null && thumbUrl.isNotEmpty) {
      image = await _fetchDecodedImage(thumbUrl);
    }
    if (!mounted) return null;
    const size = Size(70, 86);
    final icon = await NOverlayImage.fromWidget(
      widget: _buildThumbMarkerWidget(item.kind, image, isVideo: isVideo),
      size: size,
      context: context,
    );
    return (icon: icon, size: size, anchor: const NPoint(0.5, 1.0));
  }

  /// 마커 하나의 아이콘만 다시 굽는다 — 선택이 바뀔 때 전체 마커를 지웠다
  /// 다시 올리지 않는다(깜빡임 없이 그 두 개만 바뀐다).
  Future<void> _refreshMarker(String? key) async {
    if (key == null) return;
    final id = 'grp_$key';
    final marker = _markers[id];
    final group = _groupsById[id];
    if (marker == null || group == null || group.items.length != 1) return;
    final selected = _isSelectedGroup(group);
    final built = selected
        ? await _buildSelectedMarkerIcon(group.first)
        : await _buildMarkerIcon(group, _markerTierForZoom(_currentZoom));
    if (built == null || !mounted || _markers[id] != marker) return;
    marker
      ..setIcon(built.icon)
      ..setSize(built.size)
      ..setAnchor(built.anchor)
      ..setZIndex(selected ? 1000 : 0);
    // 선택 여부는 마커 모양의 일부다 — 여기서 갱신해 두지 않으면 다음
    // 동기화가 "모양이 달라졌다"고 보고 이 마커만 지웠다 다시 올린다.
    _markerSignatures[id] = _markerSignature(
      group,
      _markerTierForZoom(_currentZoom),
    );
  }

  /// 미리보기 카드와 강조 마커를 함께 바꾼다(null이면 둘 다 내린다).
  void _selectHomeItem(MapListing? item) {
    final previous = _selectedKey;
    if (previous == item?.key && _tapped?.key == item?.key) return;
    setState(() {
      _tapped = item;
      _selectedKey = item?.key;
    });
    if (previous != item?.key) {
      _refreshMarker(previous);
      _refreshMarker(item?.key);
    }
  }

  /// 앱이 카메라를 옮긴다 — 그 뒤의 idle 한 번은 자동 재조회를 걸지 않는다.
  /// 제자리라 idle이 오지 않는 경우에 대비해 잠시 뒤 스스로 풀린다.
  void _moveCameraQuietly(NCameraUpdate update) {
    _ignoreNextIdle = true;
    _mapController?.updateCamera(update);
    Future.delayed(const Duration(milliseconds: 1500), () {
      _ignoreNextIdle = false;
    });
  }

  /// 홈의 마커 탭 — 하나짜리는 그 콘텐츠의 작은 미리보기 카드만 띄운다.
  /// 겹친 묶음은 **한 번에** 그 자리의 목록을 연다(지도 화면과 같은 시트) —
  /// 확대도 카메라 이동도 하지 않는다. 예전에는 줌 17 전까지 누를 때마다
  /// 두 칸씩 확대만 해서, 묶음을 풀려면 여러 번 눌러야 했다.
  void _onHomeMarkerTap(_MarkerGroup group) {
    final plan = mapMarkerTapPlan(group.items);
    switch (plan.action) {
      case MapMarkerTapAction.openGroupList:
        _selectHomeItem(null);
        _openGroupSheet(group);
      case MapMarkerTapAction.openFestivalDetail:
        // 🎊 공공 축제 하나짜리는 미리보기 카드 없이 곧장 공공 축제 상세로
        // 간다(들고 있는 [PublicEvent]를 그대로 넘긴다 — 다시 읽지 않는다).
        _selectHomeItem(null);
        _openDetail(group.first);
      case MapMarkerTapAction.previewSingle:
        if (plan.centerCamera) {
          _moveCameraQuietly(
            NCameraUpdate.withParams(target: NLatLng(group.lat, group.lng)),
          );
        }
        _selectHomeItem(group.first);
    }
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value.trim();
      _recomputeVisible();
    });
    _syncMarkers();
  }

  /// 홈 카테고리 칸을 눌렀다.
  ///
  ///   · '전체'(0) → 개별 선택을 모두 푼다(= 전체).
  ///   · 개별 칸 → 켜고 끄는 토글. 전체 상태에서 누르면 그 칸만 켜지고,
  ///     마지막 하나를 끄면 빈 집합 = 다시 '전체'.
  void _selectHomeCategory(int index) {
    final next = index == 0
        ? <int>{}
        : (_homeSelected.contains(index)
              ? ({..._homeSelected}..remove(index))
              : {..._homeSelected, index});
    if (setEquals(next, _homeSelected)) return;
    setState(() {
      _homeSelected = next;
      // 올릴 종류는 켜 둔 칸들의 합집합이다. 칸 안의 세부 조건(이벤트 하는
      // 곳만)은 [_homeCategoryAccepts]가 항목마다 본다 — 전역 🎪 조건
      // ([EventFilter.eventOnly])으로 걸면 '파티 + 이벤트'에서 플레이스·
      // 장소대여 전체가 아니라 이벤트 하는 곳만 남기는 것을 표현할 수 없다.
      _kinds = mapHomeKindsFor(_homeSelected);
      _recomputeVisible();
    });
    _syncMarkers();
  }

  /// '이벤트' 칸이 켜져 있어 🎪 이벤트 정본을 읽어야 하는가.
  bool get _homeWantsEvents =>
      _home && _homeSelected.any((i) => mapHomeCategories[i].eventOnly);

  /// 켜 둔 홈 카테고리 중 하나라도 이 항목을 받아 주는가('전체'면 항상).
  bool _homeCategoryAccepts(MapListing item) {
    if (!_home || _homeSelected.isEmpty) return true;
    for (final i in _homeSelected) {
      final category = mapHomeCategories[i];
      if (!category.kinds.contains(item.kind)) continue;
      if (!category.eventOnly || _hasRunningEvent(item)) return true;
    }
    return false;
  }

  /// 🎪 지금 보여줄 이벤트가 있는가 — 목록 탭·기존 지도와 **같은 판정**이다
  /// (플레이스는 [EventFilter.matchesDiscovery]의 이벤트 갈래, 장소대여는
  /// [PlaceEventIndex.allows]). 방문 날짜·시간 조건도 그대로 함께 넘긴다.
  bool _hasRunningEvent(MapListing item) {
    final index = switch (item.kind) {
      MapListingKind.place => _placeEventIndex,
      MapListingKind.rental => _rentalEventIndex,
      MapListingKind.party => null,
      MapListingKind.festival => null,
    };
    if (item.kind == MapListingKind.party) return false;
    // 🎊 공공 축제는 그 자체가 행사다(끝난 것은 조회 단계에서 빠진다).
    if (item.kind == MapListingKind.festival) return true;
    // 플레이스는 색인을 아직 못 읽었으면 본체 미러로 본다(기존 규칙).
    if (index == null && item.kind == MapListingKind.place) {
      return PlaceEventTaxonomy.isRunningAt(item.data, DateTime.now());
    }
    return PlaceEventIndex.allows(
      eventOnly: true,
      docId: item.docId,
      index: index,
      doc: item.data,
      dates: _placeDiscovery.visitDates,
      start: _placeDiscovery.startTime,
      end: _placeDiscovery.endTime,
    );
  }

  Future<void> _locateIfPermitted() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (!mounted) return;
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        await _goToCurrentLocation(areaSearch: false);
      }
    } catch (e) {
      debugPrint('[MapHome] 현재 위치 자동 이동 건너뜀: $e');
    }
  }

  Widget _buildHome(BuildContext context) {
    final bottomGap = _tapped != null ? 128.0 : 16.0;
    return Scaffold(
      backgroundColor: const Color(0xFFEEF8FF),
      body: Stack(
        children: [
          if (kIsWeb)
            Positioned.fill(
              child: _WebMapUnavailable(onOpenList: widget.onOpenList),
            )
          else
            _buildNaverMap(),

          // ── 위: 검색창 + 가로 카테고리(지도 위에 얇게 떠 있다) ──────
          // (웹은 지도가 없어 검색·카테고리가 걸 대상이 없다 — 안내만 둔다.)
          if (!kIsWeb)
            Positioned(top: 0, left: 0, right: 0, child: _buildHomeTopBar()),

          // ── 이 영역에 아무것도 없을 때 ─────────────────────────────
          // (재검색 버튼이 있던 자리다 — 지도를 멈추면 앱이
          //  알아서 다시 찾으므로 누를 것이 없어졌다.)
          if (_isAreaSearch && _displayed.isEmpty && !kIsWeb)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomGap,
              child: Center(
                child: _homePill(
                  child: Text(
                    '이 지역에는 아직 ${_kindsLabel()}가 없어요',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ),
            ),

          // ── 현재 위치 ──────────────────────────────────────────────
          if (!kIsWeb)
            Positioned(
              right: 14,
              bottom: bottomGap,
              child: FloatingActionButton.small(
                heroTag: 'map_home_location_fab',
                onPressed: _isLoadingLocation ? null : _goToCurrentLocation,
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                elevation: 3,
                child: _isLoadingLocation
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location, size: 20),
              ),
            ),

          // ── 선택한 콘텐츠 하나의 미리보기 ──────────────────────────
          if (_tapped != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: _buildHomePreviewCard(_tapped!),
            ),
        ],
      ),
    );
  }

  /// 흰 알약 — 지도 위에 뜨는 작은 요소들이 같은 모양을 쓴다.
  Widget _homePill({required Widget child, EdgeInsetsGeometry? padding}) =>
      Container(
        padding:
            padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: child,
      );

  Widget _buildHomeTopBar() {
    final top = MediaQuery.paddingOf(context).top;
    const pink = Color(0xFFFF6FA0);
    final filterOn = _filter.isActive;
    return Padding(
      padding: EdgeInsets.only(top: top + 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _openDetailSearch,
                    child: _homePill(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: pink,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _query.isEmpty ? '지금, 어디서 놀까요?' : _query,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: _query.isEmpty
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                                color: _query.isEmpty
                                    ? Colors.black45
                                    : Colors.black87,
                              ),
                            ),
                          ),
                          if (_query.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _queryCtrl.clear();
                                _onQueryChanged('');
                              },
                              child: const Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Colors.black38,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 세부 필터 — 지도를 가리지 않도록 버튼을 눌렀을 때만 열린다.
                GestureDetector(
                  onTap: _openDetailSearch,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: filterOn ? pink : Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x26000000),
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.tune_rounded,
                      size: 20,
                      color: filterOn ? Colors.white : pink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildHomeCategoryRow(),
          // 🕐 날짜·시간 판 — 빠른 필터 줄의 🕐 버튼을 누르면 그 아래로
          // 펼쳐진다. 이 줄은 지도 위 겹침층(Stack의 Positioned) 안이라
          // 카테고리 줄도 지도도 밀어내지 않고, 판 밖의 빈 자리는 누름을
          // 받지 않아 지도 조작이 그대로 지나간다.
          if (_dateTimePaneOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: _buildHomeDateTimePane(),
              ),
            ),
        ],
      ),
    );
  }

  // ── 📅 날짜·시간 ─────────────────────────────────────────────────
  //
  // 새 필터가 아니다 — 목록 탭 빠른필터와 **같은 칸**([PartyFilter]의
  // selectedDates · timeOfDayStart/End)을 **같은 위젯**으로 고친다:
  // 날짜 빠른선택 줄([QuickDatePane]) · 한국식 달력([showKoreanCalendarSheet])
  // · 시간 휠([showVisitTimePicker]). 판정도 지도가 이미 이 칸들로 하던 그대로다
  // (파티는 회차 일정, 플레이스·장소대여는 그날 영업, 공공 축제는 기간 겹침).

  /// 버튼 아래 펼쳐지는 판 — 날짜 빠른선택 줄 + 시간 한 줄.
  Widget _buildHomeDateTimePane() {
    final timeLabel = dateTimeFilterLabel(
      PartyFilter()
        ..timeOfDayStart = _filter.timeOfDayStart
        ..timeOfDayEnd = _filter.timeOfDayEnd,
    );
    final timeOn = timeLabel != null;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            QuickDatePane(
              selected: _filter.selectedDates,
              onToggleDate: _toggleHomeDate,
              onPickCalendar: _pickHomeDate,
              onClear: _clearHomeDates,
              alignment: WrapAlignment.end,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                QuickFilterChip(
                  label: timeLabel ?? '시간 선택',
                  icon: Icons.schedule_rounded,
                  selected: timeOn,
                  onTap: _pickHomeTime,
                ),
                if (timeOn)
                  QuickFilterChip(
                    label: '초기화',
                    icon: Icons.close_rounded,
                    selected: false,
                    onTap: () => _changeHomeFilter(() {
                      _filter.timeOfDayStart = null;
                      _filter.timeOfDayEnd = null;
                    }),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 날짜·시간 칸을 고치고 목록·마커를 함께 다시 센다(상세검색 적용과 같은 길).
  void _changeHomeFilter(VoidCallback change) {
    setState(() {
      change();
      _recomputeVisible();
    });
    _syncMarkers();
  }

  /// 목록 탭과 같은 규칙 — 최대 개수를 넘기면 바꾸지 않고 안내한다.
  void _toggleHomeDate(DateTime date) {
    var changed = false;
    _changeHomeFilter(() => changed = _filter.toggleDate(date));
    if (changed) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            '날짜는 최대 ${PartyFilter.maxSelectedDates}일까지 고를 수 있어요.',
          ),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// '초기화' — 날짜만 비운다. 날짜에 딸린 시간 범위도 함께(목록 탭과 같은 규칙).
  void _clearHomeDates() => _changeHomeFilter(() {
    _filter.selectedDates.clear();
    _filter.startTime = null;
    _filter.endTime = null;
  });

  /// '날짜 선택' — 목록 탭과 같은 한국식 달력.
  Future<void> _pickHomeDate() async {
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
    _changeHomeFilter(() {
      _filter.selectedDates = {...picked};
      if (_filter.selectedDates.isEmpty) {
        _filter.startTime = null;
        _filter.endTime = null;
      }
    });
  }

  /// 시간 — 목록 탭과 같은 30분 휠 시트(지정 시간 / 지정 구간).
  Future<void> _pickHomeTime() async {
    final picked = await showVisitTimePicker(
      context,
      start: _filter.timeOfDayStart,
      end: _filter.timeOfDayEnd,
    );
    if (picked == null || !mounted) return;
    _changeHomeFilter(() {
      _filter.timeOfDayStart = picked.start;
      _filter.timeOfDayEnd = picked.end;
    });
  }

  // ── 가로 카테고리 줄 ─────────────────────────────────────────────
  //
  // [전체][✨특징][파티][이벤트][플레이스][장소대여][🕐][₩] 여덟 칸이 **한
  // 줄**에 선다. 칸은 자기 글자에 필요한 최소 폭만 가진다 — 남는 폭을 나눠
  // 갖지 않는다(그래야 오른쪽 두 버튼 자리가 난다). 폭 계산은
  // [quickRowLayout]이 하고, 어떤 기기 폭도 숫자로 박지 않는다.
  // 치수는 [map_quick_filter_row.dart]에 있다 — 폭 계산과 테스트가 같은 값을 본다.
  static const double _chipHeight = kQuickChipHeight;
  static const double _chipFontSize = kQuickChipFontSize;
  static const double _chipGap = kQuickChipGap;
  static const double _chipSidePad = kQuickRowSidePad;
  static const double _chipBasePad = kQuickChipBasePad;
  static const double _chipMinPad = kQuickChipMinPad;
  static const double _chipIconSize = kQuickChipIconSize;
  static const double _chipIconGap = kQuickChipIconGap;
  static const double _quickLabelGap = kQuickLabelGap;

  static const TextStyle _chipTextStyle = TextStyle(
    fontSize: _chipFontSize,
    fontWeight: FontWeight.w700,
  );

  Widget _buildHomeCategoryRow() {
    final featureOn = _placeDiscovery.features.isNotEmpty;
    final dateLabel = dateTimeFilterLabel(_filter);
    final priceSelection = _priceSelection;
    final priceLabel = mapPriceFilterLabel(priceSelection);
    // (라벨, 아이콘, 선택됨, 누르면) — 앞 여섯은 글자 칩, 뒤 둘은 아이콘 버튼.
    final chips =
        <({String label, IconData? icon, bool selected, VoidCallback onTap})>[
          (
            label: mapHomeCategories[0].label,
            icon: null,
            selected: _homeSelected.isEmpty,
            onTap: () => _selectHomeCategory(0),
          ),
          // 특징 — 종류 선택이 아니라 **추가 필터**다. 어떤 칸을 골랐든 항상
          // 두 번째에 있고, 기존 특징 시트를 연다. 조건은 특징 값을 실제로
          // 갖는 플레이스에만 걸리고(다른 종류에는 없는 값이라 걸지 않는다 —
          // [_matchesFilter]), 조건이 하나라도 있으면 활성으로 보인다.
          (
            label: '특징',
            icon: Icons.auto_awesome_outlined,
            selected: featureOn,
            onTap: () async {
              await _openPlaceFeatureSheet();
              if (mounted) _syncMarkers();
            },
          ),
          for (var i = 1; i < mapHomeCategories.length; i++)
            (
              label: mapHomeCategories[i].label,
              icon: null,
              selected: _homeSelected.contains(i),
              onTap: () => _selectHomeCategory(i),
            ),
        ];

    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double textWidth(String? text, TextStyle style) {
      if (text == null || text.isEmpty) return 0;
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      // 반올림 오차로 글자가 잘리지 않게 1px 여유.
      return width + 1;
    }

    const quickLabelStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w700);
    final chipTexts = [for (final c in chips) textWidth(c.label, _chipTextStyle)];
    final chipIcons = [
      for (final c in chips)
        c.icon == null ? 0.0 : scaler.scale(_chipIconSize) + _chipIconGap,
    ];
    final quickIcon = scaler.scale(MapQuickFilterButton.iconSize);
    final dateTextWidth = textWidth(dateLabel, quickLabelStyle) + _quickLabelGap;
    final priceTextWidth = textWidth(priceLabel, quickLabelStyle) + _quickLabelGap;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 실제 가용 폭에서 줄 좌우 여백과 칸 사이 간격을 뺀 만큼을 여덟 칸이
        // 나눠 쓴다. 기기 폭을 숫자로 박지 않는다.
        const count = 8;
        final available =
            constraints.maxWidth -
            _chipSidePad * 2 -
            _chipGap * (count - 1);

        // 🕐·₩의 짧은 값은 **자리가 남을 때만** 붙인다. 값을 붙여 글자를
        // 줄여야 하거나 가로로 넘겨야 하면 값을 떼고 아이콘만 분홍으로 둔다.
        QuickRowLayout layoutFor({required bool withLabels}) => quickRowLayout(
          texts: [
            ...chipTexts,
            withLabels ? dateTextWidth : 0,
            withLabels ? priceTextWidth : 0,
          ],
          icons: [...chipIcons, quickIcon, quickIcon],
          available: available,
          basePad: _chipBasePad,
          minPad: _chipMinPad,
        );

        final wantLabels = dateLabel != null || priceLabel != null;
        var layout = wantLabels ? layoutFor(withLabels: true) : layoutFor(withLabels: false);
        var showLabels = wantLabels;
        if (wantLabels && (layout.scale < 1 || layout.scroll)) {
          showLabels = false;
          layout = layoutFor(withLabels: false);
        }
        final widths = layout.widths;
        final chipStyle = _chipTextStyle.copyWith(
          fontSize: _chipFontSize * layout.scale,
        );

        final row = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: _chipGap),
              SizedBox(
                width: widths[i],
                height: _chipHeight,
                child: _homeChip(
                  chips[i].label,
                  icon: chips[i].icon,
                  selected: chips[i].selected,
                  onTap: chips[i].onTap,
                  style: chipStyle,
                ),
              ),
            ],
            const SizedBox(width: _chipGap),
            SizedBox(
              width: widths[chips.length],
              child: MapQuickFilterButton(
                key: const ValueKey('mapHomeDateTimeButton'),
                icon: Icons.schedule_rounded,
                semanticLabel: '날짜·시간 필터',
                active: dateLabel != null,
                label: showLabels ? dateLabel : null,
                textScale: layout.scale,
                height: _chipHeight,
                onTap: () =>
                    setState(() => _dateTimePaneOpen = !_dateTimePaneOpen),
              ),
            ),
            const SizedBox(width: _chipGap),
            SizedBox(
              width: widths[chips.length + 1],
              child: MapQuickFilterButton(
                key: const ValueKey('mapHomePriceButton'),
                icon: Icons.payments_outlined,
                glyph: '₩',
                semanticLabel: '가격 필터',
                active: priceSelection.isActive,
                label: showLabels ? priceLabel : null,
                textScale: layout.scale,
                height: _chipHeight,
                onTap: _openPriceFilter,
              ),
            ),
          ],
        );
        const padding = EdgeInsets.symmetric(horizontal: _chipSidePad);
        return SizedBox(
          height: _chipHeight + 6, // 그림자 자리
          child: layout.scroll
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: padding,
                  child: row,
                )
              : Padding(padding: padding, child: row),
        );
      },
    );
  }

  /// 💳 지금 걸린 가격 칸 — 종류마다 쓰던 칸을 그대로 모아 본다.
  MapPriceSelection get _priceSelection => MapPriceSelection(
    partyFees: _filter.feeRanges,
    placeRanges: _placeDiscovery.priceRanges,
    rentalRanges: _rentalDiscovery.priceRanges,
  );

  /// ₩ 버튼 — 기존 가격 칸·칩 위젯을 그대로 쓰는 시트를 연다. 적용하면 목록과
  /// 마커를 함께 다시 센다(상세검색 적용과 같은 길).
  Future<void> _openPriceFilter() async {
    final picked = await showMapPriceFilterSheet(
      context,
      initial: _priceSelection,
      kinds: _kinds,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _filter.feeRanges
        ..clear()
        ..addAll(picked.partyFees);
      _placeDiscovery.priceRanges
        ..clear()
        ..addAll(picked.placeRanges);
      _rentalDiscovery.priceRanges
        ..clear()
        ..addAll(picked.rentalRanges);
      _recomputeVisible();
    });
    _syncMarkers();
  }

  Widget _homeChip(
    String label, {
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    TextStyle? style,
  }) {
    const pink = Color(0xFFFF6FA0);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? pink : Colors.white,
          borderRadius: BorderRadius.circular(_chipHeight / 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: _chipIconSize,
                color: selected ? Colors.white : pink,
              ),
              const SizedBox(width: _chipIconGap),
            ],
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: (style ?? _chipTextStyle).copyWith(
                color: selected ? Colors.white : const Color(0xFF3A2E39),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 내 위치에서의 거리('300m', '1.2km') — 위치를 모르면 null.
  String? _distanceLabel(MapListing item) {
    final me = _myLatLng;
    if (me == null) return null;
    final meters = Geolocator.distanceBetween(
      me.latitude,
      me.longitude,
      item.lat,
      item.lng,
    );
    if (meters < 1000) return '${(meters / 10).round() * 10}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  /// 일정 한 줄 — 파티는 다음 회차 날짜·시간, 장소 계열은 영업시간.
  /// 카드들이 쓰는 **같은 계산**을 그대로 빌린다.
  String _homeScheduleLabel(MapListing item) {
    final festival = item.publicEvent;
    if (festival != null) return publicEventPeriodLabel(festival);
    if (item.kind == MapListingKind.party) {
      final date = PartyCard.formatDateOnly(item.data);
      final time = PartyCard.formatTimeOnly(item.data);
      return [date, time].where((s) => s.isNotEmpty).join(' ');
    }
    return PlaceCardInfo.from(
      item.data,
      source: item.kind.cardSource!,
      tag: 'MapHomePreview',
    ).hoursLabel;
  }

  /// 핵심 상태 한 가지 — 파티는 모집 상태, 장소대여는 요금(가격 문의 포함).
  String? _homeStatusLabel(MapListing item) {
    switch (item.kind) {
      case MapListingKind.party:
        final status = PartyCard.effectiveStatusFor(
          item.data,
          UserSession.gender,
        );
        return status.isEmpty ? null : status;
      case MapListingKind.place:
        return null;
      case MapListingKind.rental:
        return PlaceCardInfo.from(
          item.data,
          source: PlaceCardSource.rental,
          tag: 'MapHomePreview',
        ).priceLabel;
      case MapListingKind.festival:
        return null;
    }
  }

  /// 선택한 콘텐츠 하나의 작은 카드 — 사진 · 이름 · 일정 · 거리/지역 · 상태.
  /// 누르면 기존 상세 화면으로 간다(지도는 그대로 남는다).
  Widget _buildHomePreviewCard(MapListing item) {
    final cover = getPartyCoverMedia(item.data, tag: 'MapHomePreview');
    final schedule = _homeScheduleLabel(item);
    final status = _homeStatusLabel(item);
    final where = [
      ?_distanceLabel(item),
      if (item.shortAddress.isNotEmpty) item.shortAddress,
    ].join(' · ');
    const muted = TextStyle(fontSize: 12.5, color: Colors.black54);

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          _openDetail(item);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: PartyThumbnailWidget(
                  imageUrl: cover?.thumbnailUrl,
                  borderRadius: BorderRadius.circular(12),
                  placeholder: ColoredBox(
                    color: item.kind.color.withValues(alpha: 0.14),
                    child: Center(
                      child: Icon(
                        (cover?.isVideo ?? false)
                            ? Icons.videocam_outlined
                            : item.kind.icon,
                        size: 24,
                        color: item.kind.color,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _kindBadge(item.kind),
                        if (status != null) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFFF4F8B),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (schedule.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        schedule,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ],
                    if (where.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        where,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: _dismissTappedCard,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18, color: Colors.black38),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 목록 머리말에 쓰는 종류 이름 — 셋 다 켜져 있으면 '전체', 아니면 켜 둔
  /// 것들을 이어 붙인다('파티·플레이스'). 지금 무엇을 세고 있는 개수인지가
  /// 숫자 옆에서 바로 읽혀야 한다.
  String _kindsLabel() {
    if (MapListingKind.listingKinds.every(_kinds.contains)) return '전체';
    return MapListingKind.listingKinds
        .where(_kinds.contains)
        .map((k) => k.label)
        .join('·');
  }

  // ── 빈 결과 화면 ───────────────────────────────────────────────────
  /// 시트 머리 — 손잡이 · 종류 선택 · (플레이스일 때) 대분류/빠른필터.
  ///
  /// 목록과 **같은 스크롤 안에 든 슬리버 하나**라, 높이를 미리 알 필요가 없다.
  /// 대분류(2줄 격자 ~117px)에서 드릴다운(1줄 ~34px)으로 바뀌어도 여기서
  /// 다시 계산할 숫자가 없고, 시트가 아무리 접혀 있어도 넘치지 않는다
  /// (넘칠 자리가 없으면 그냥 스크롤 밖으로 나갈 뿐이다).
  Widget _buildSheetHeader() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        Container(
          width: 44,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        const SizedBox(height: 12),
        // ── 머리줄: 종류 선택 + 상세필터 ──────────────────
        // 예전에는 '이 근처 전체 (6)' 제목이 있던 자리다. 제목이
        // 알려주던 것(무엇을 · 몇 개 보고 있는지)은 칩이 그대로
        // 들고 있으므로 — 켜진 종류에 불이 들어오고 개수가 칩에
        // 붙는다 — 같은 말을 두 번 하지 않는다.
        // 머리줄 좌우 여백은 목록 카드(16)보다 좁은 12다 — 네 칩이
        // 나눠 가질 폭이 그만큼 늘어난다. 아래 목록과 왼쪽 선이
        // 4px 어긋나지만, 칩이 눌려 찌그러지는 쪽이 더 눈에 띈다.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // 남는 폭을 칩 줄이 다 받아 4등분한다. 상세필터
              // 버튼은 오른쪽에 고정 — 폭을 나눠 갖지 않는다.
              Expanded(
                child: MapKindFilterBar(
                  selected: _kinds,
                  onChanged: _onKindsChanged,
                  counts: _countByKind,
                  // 바깥 Padding이 좌우를 이미 줬다 — 여기서는
                  // 상세필터 버튼과 붙지 않을 만큼만.
                  padding: const EdgeInsets.only(right: 6),
                ),
              ),
              GestureDetector(
                onTap: _openDetailSearch,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: _filter.isActive
                        ? const Color(0xFFFF6FA0)
                        : const Color(0xFFFFF0F5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.tune,
                    size: 19,
                    color: _filter.isActive
                        ? Colors.white
                        : const Color(0xFFFF6FA0),
                  ),
                ),
              ),
            ],
          ),
        ),
        // ── 플레이스 탐색 2단 ────────────────────────────
        // 플레이스를 보고 있을 때만 나타난다 — 파티·장소대여만
        // 켠 상태에서 '클럽·콜키지 가능'을 물어봐야 답할 것이
        // 없다. 값은 [_placeDiscovery] 하나이므로 종류를 껐다
        // 켜도 고른 조건은 그대로 남는다.
        //
        // 가로스크롤(빠른필터·드릴다운)은 세로 시트 드래그와 부딪히지
        // 않는다 — 축이 달라 제스처 경합에서 각자 자기 방향만 가져간다.
        if (_kinds.contains(MapListingKind.place)) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            // 목록 화면과 **같은 위젯**이다 — 대분류 한 층,
            // 고르면 같은 자리에서 소분류 한 층. 지도에는 파티샵이
            // 없으므로(별도 컬렉션) 그 칸만 두지 않는다.
            child: PlaceCategoryExplorer(
              filter: _placeDiscovery,
              night: false,
              onChanged: () => setState(_recomputeVisible),
            ),
          ),
          PlaceQuickFeatureBar(
            filter: _placeDiscovery,
            night: false,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            onChanged: () => setState(_recomputeVisible),
            // 지도에는 플레이스 전용 상세검색 시트가 없다 —
            // 더보기는 빠른 필터 전체를 담은 시트를 띄운다.
            onOpenMore: _openPlaceFeatureSheet,
          ),
        ]
        // 🎪 이벤트만은 플레이스 전용 조건이 아니다 — 장소대여 마커에도
        // 걸린다([_matchesFilter]). 그래서 플레이스를 끄면 위 격자가 사라져도
        // 이 조건은 **끄러 갈 곳이 남아 있어야** 한다. 격자가 보일 때는
        // 그 안의 🎪 칸이 같은 값을 맡으므로 여기서는 그리지 않는다(컨트롤
        // 하나에 값 하나).
        else if (_showsStandaloneEventChip) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildEventOnlyChip(),
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  /// 격자 밖에서 🎪 칩을 따로 보여야 하는가.
  ///
  ///   · 장소대여를 보고 있으면 — 이 조건이 실제로 걸리는 종류라 켜고 끌 수
  ///     있어야 한다.
  ///   · 아무 데도 안 걸리는 상태(파티만)라도 **이미 켜져 있으면** 보여준다 —
  ///     켜 둔 조건을 끌 수 없는 화면을 만들지 않기 위함이다. 꺼져 있으면
  ///     물어볼 것이 없으므로 두지 않는다.
  ///
  /// 종류를 바꿀 때 값을 건드리지 않는다는 이 화면의 규칙은 그대로다
  /// ([_onKindsChanged]) — 보이고 안 보이고만 정한다.
  bool get _showsStandaloneEventChip =>
      _kinds.contains(MapListingKind.rental) || _placeDiscovery.eventOnly;

  /// 🎪 이벤트 칩 — 격자 안 🎪 칸과 **같은 값·같은 토글**이다
  /// ([EventFilter.selectEvent]). 판정은 건드리지 않는다.
  Widget _buildEventOnlyChip() {
    final on = _placeDiscovery.eventOnly;
    // 파티만 켜 둔 상태에서는 이 조건이 걸릴 대상이 없다 — 끌 수는 있어야
    // 하므로 그리되, 지금 아무 데도 걸리지 않는다는 것을 한 줄로 알린다.
    final applies =
        _kinds.contains(MapListingKind.place) ||
        _kinds.contains(MapListingKind.rental);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() {
            _placeDiscovery.selectEvent(!on);
            _recomputeVisible();
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: on ? const Color(0xFFFF6FA0) : const Color(0xFFF6F6F8),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              '${PlaceEventTaxonomy.categoryEmoji} 이벤트 하는 곳만',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: on ? Colors.white : const Color(0xFF4A4A55),
              ),
            ),
          ),
        ),
        if (on && !applies) ...[
          const SizedBox(width: 8),
          const Flexible(
            child: Text(
              '지금 보고 있는 종류에는 걸리지 않아요',
              style: TextStyle(fontSize: 11.5, color: Colors.black45),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
    // '파티 등록하기' 버튼은 파티를 보고 있을 때만 뜻이 있다 — 장소대여만
    // 켜 둔 사람에게 파티 등록을 권하면 화면이 딴소리를 하는 셈이다.
    final showRegister = _kinds.contains(MapListingKind.party);
    if (_isAreaSearch) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.search_off_rounded,
                size: 52,
                color: Colors.black26,
              ),
              const SizedBox(height: 14),
              Text(
                '이 지도 영역에는 아직 ${_kindsLabel()}가 없어요.',
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              if (showRegister) ...[
                const SizedBox(height: 6),
                const Text(
                  '직접 파티를 등록해보세요!',
                  style: TextStyle(fontSize: 13, color: Colors.black38),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  // 등록 탭과 같은 창구를 쓴다 — 여기서만 곧장 폼을 열면
                  // 내 공간을 가진 호스트가 진입 경로에 따라 다른 화면을
                  // 만나게 된다.
                  onPressed: () => openPartyRegisterEntry(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(
                    '파티 등록하기',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6FA0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Center(
      child: Text(
        '등록된 ${_kindsLabel()}가 없습니다',
        style: const TextStyle(color: Colors.black45),
      ),
    );
  }

  // ── 마커 탭 카드 ────────────────────────────────────────────────────
  //
  // 세 종류가 같은 껍데기를 쓴다 — 지도 위에 뜨는 미리보기라 어느 종류든
  // "사진 · 이름 · 지역 · 상세보기" 넉 줄이면 충분하고, 자세한 내용은 각자의
  // 상세 화면이 맡는다. 종류는 왼쪽 위 색 배지(글리프 + 이름)로 알린다.
  Widget _buildTappedCard(MapListing item) {
    // 마커 탭 카드는 상세주소 없이 "구+동"만 — 상세페이지에서만 전체 주소를 보여준다.
    final address = item.shortAddress;
    final cover = getPartyCoverMedia(item.data, tag: 'MapInfoCard');
    final thumbnailUrl = cover?.thumbnailUrl;

    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: PartyThumbnailWidget(
                imageUrl: thumbnailUrl,
                borderRadius: BorderRadius.circular(12),
                placeholder: (cover?.isVideo ?? false)
                    ? const ColoredBox(
                        color: Color(0xFF1A1A2E),
                        child: Center(
                          child: Icon(
                            Icons.videocam_outlined,
                            size: 24,
                            color: Color(0xFFFF6FA0),
                          ),
                        ),
                      )
                    : ColoredBox(
                        color: item.kind.color.withValues(alpha: 0.14),
                        child: Center(
                          child: Icon(
                            item.kind.icon,
                            size: 24,
                            color: item.kind.color,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _kindBadge(item.kind),
                  const SizedBox(height: 4),
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 13,
                          color: Colors.black38,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            address,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () {
                setState(() => _tapped = null);
                _openDetail(item);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
              child: const Text('상세보기', style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _dismissTappedCard,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 18, color: Colors.black38),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 종류 알약 — 마커 색과 같은 색이라 "누른 마커가 이것"이 바로 이어진다.
  static Widget _kindBadge(MapListingKind kind) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: kind.color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(kind.icon, size: 10, color: kind.color),
        const SizedBox(width: 3),
        Text(
          kind.label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: kind.color,
          ),
        ),
      ],
    ),
  );

  /// 종류에 맞는 **기존** 상세 화면으로 — 지도 전용 상세는 만들지 않는다.
  void _openDetail(MapListing item) {
    Navigator.push(
      context,
      webFramedRoute(
        (_) => switch (item.kind) {
          MapListingKind.party => PartyDetailScreen(docId: item.docId),
          MapListingKind.place => EventDetailScreen(
            eventId: item.docId,
            eventData: item.data,
          ),
          MapListingKind.rental => PlaceDetailScreen(
            placeId: item.docId,
            data: item.data,
          ),
          // 🎊 공공 축제 — 전용 상세. 지도가 들고 있는 객체를 그대로 넘긴다.
          MapListingKind.festival => PublicEventDetailScreen(
            event: item.publicEvent!,
          ),
        },
      ),
    );
  }

  // ── 목록 카드 ───────────────────────────────────────────────────────
  //
  // 각 탭의 **작은 카드**를 그대로 쓴다 — 파티는 [PartyCard], 플레이스와
  // 장소대여는 [PlaceCompactCard]("지도 '이 근처' 카드와 같은 셸"로 만들어진
  // 카드다). 카드를 누르면 각자가 원래 가던 상세 화면으로 그대로 이어지므로
  // 지도가 따로 이동을 가로챌 일이 없다.
  /// [onTap]은 겹침 시트에서만 넘긴다 — 시트를 닫고 나서 상세로 가야 해서다.
  /// 넘기지 않으면 카드가 **원래 하던 대로** 자기 상세 화면을 연다.
  Widget _buildListCard(MapListing item, {VoidCallback? onTap}) {
    // 🎊 공공 축제 — 이벤트 피드와 같은 카드. 누르면 공공 축제 상세.
    final festival = item.publicEvent;
    if (festival != null) {
      return PublicEventCompactCard(
        event: festival,
        badge: EventFeedKind.publicFestival.badge,
        onTap: onTap,
      );
    }
    if (item.kind == MapListingKind.party) {
      return PartyCard(
        party: item.data,
        docId: item.docId,
        onTap: onTap,
        // 지도에는 날짜 탭이 없고 상세검색 조건만 있다 — 그 조건이 곧 카드 날짜의
        // 기준이 된다(조건이 없으면 예전처럼 다음 회차).
        dateFocus: PartyDateFocus.of(
          dateOptions: _filter.dateOptions,
          selectedDates: _filter.selectedDates,
        ),
      );
    }
    return PlaceCompactCard(
      place: item.data,
      placeId: item.docId,
      source: item.kind.cardSource!,
      onTap: onTap,
      // 🎉 With파티 배지는 플레이스(events)에만. 장소대여는 파티를 다른
      // 필드(`linkedPlaceId`)로 잇고 이 색인이 그쪽을 담지 않는다.
      withParty:
          item.kind == MapListingKind.place && _withPartyIndex.has(item.docId),
    );
  }
}

/// 웹에서 지도 자리에 대신 들어가는 안내판.
///
/// 지도 자체를 웹에 구현하지 않기로 한 결정의 결과다(등록·목록 어느 경로도
/// 지도를 필요로 하지 않는다). 여기 없으면 웹에서 이 화면이 예외로 죽는다.
class _WebMapUnavailable extends StatelessWidget {
  /// 홈 모드에서만 — 지도 대신 목록 탭으로 보내는 버튼.
  final VoidCallback? onOpenList;

  const _WebMapUnavailable({this.onOpenList});

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFF2F3F7),
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.map_outlined, size: 40, color: Color(0xFFB9BECC)),
        const SizedBox(height: 12),
        const Text(
          '지도는 파티츄 앱에서 볼 수 있어요',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          onOpenList == null
              ? '아래 목록에서 파티·플레이스를 그대로 둘러볼 수 있어요.'
              : '목록에서 파티·플레이스를 그대로 둘러볼 수 있어요.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF9AA1AE)),
        ),
        if (onOpenList != null) ...[
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onOpenList,
            icon: const Icon(Icons.view_agenda_outlined, size: 18),
            label: const Text('목록으로 보기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6FA0),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
