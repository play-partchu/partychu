import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:party_app/screens/event_detail_screen.dart';
import 'package:party_app/screens/party_detail_screen.dart';
import 'package:party_app/screens/party_register_entry_choice_screen.dart';
import 'package:party_app/screens/place_detail_screen.dart';
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
import 'package:party_app/models/map_listing.dart';
import 'package:party_app/models/party_pricing.dart';
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
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  NaverMapController? _mapController;
  NMarker? _currentLocationMarker;
  bool _isLoadingLocation = false;

  // ── 지도 이동 감지 ────────────────────────────────────────────────
  bool _mapInitialized = false; // 최초 onCameraIdle 무시용
  bool _mapMoved = false; // "이 지도에서 파티 보기" 버튼 표시 여부
  bool _pendingAreaSearch = false; // 현재 위치 이동 후 자동 영역 검색 트리거
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
  Set<DateTime> _partyDates = {};

  // ── 종류 선택 ─────────────────────────────────────────────────────
  //
  // 처음 들어오면 세 종류가 모두 켜져 있다(= 상단 칩의 '전체'). 이 집합은
  // 상세검색 필터([_filter])와 **완전히 독립**이다 — 종류를 바꿔도 지역·날짜
  // 조건은 그대로 남고, 두 조건은 AND로 함께 걸린다([_matchesFilter]).
  Set<MapListingKind> _kinds = MapListingKind.values.toSet();

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

  @override
  void initState() {
    super.initState();
    // 지도 화면은 들어올 때마다 항상 음소거로 시작한다(마커 카드가 한 화면에
    // 여러 개 걸릴 수 있어 소리가 켜진 채 진입하면 시끄럽다) — 사용자가 직접
    // 스피커 버튼으로 켜면 그 뒤로는 다른 화면과 동일하게 전역 설정을 따른다.
    FeedVideoManager.instance.setMuted(true);
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
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _placeEventSub?.cancel();
    _sheetController.dispose();
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

  /// 🎪 이벤트 칸이 켜져 있는 동안에만 `placePromotions`를 구독한다.
  ///
  /// 조건이 바뀌는 입구는 여럿이지만 전부 [_recomputeVisible]로 끝나므로,
  /// 거기서 한 번 맞춰 두면 어느 입구로 켜도 구독이 새지 않는다.
  ///
  /// 스트림은 하나지만 색인은 **컬렉션마다 하나씩** 만든다 — 플레이스 마커는
  /// 매장 이벤트를, 장소대여 마커는 공간 이벤트를 본다. 한 집합에 담으면 id가
  /// 우연히 겹칠 때 남의 종류가 새어 들어온다([PlaceEventIndex] 상단 주석).
  void _syncPlaceEventIndexSub() {
    final want = _placeDiscovery.eventOnly;
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
    final tapped = _tapped;
    if (tapped != null && !_mapItems.any((i) => i.key == tapped.key)) {
      _tapped = null;
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

    for (final marker in _markers.values) {
      await _mapController!.deleteOverlay(marker.info);
    }
    _markers.clear();
    if (!mounted || generation != _syncGeneration) return;

    final tier = _tierForZoom(_currentZoom);
    _syncedZoomStep = _currentZoom.floor();
    final groups = _clusterListings(_mapItems, tier);
    final pending = <String, NMarker>{};

    Future<void> rollback() async {
      for (final marker in pending.values) {
        await _mapController?.deleteOverlay(marker.info);
      }
    }

    for (final group in groups) {
      if (!mounted || generation != _syncGeneration) return rollback();
      final built = await _buildMarkerIcon(group, tier);
      if (built == null) return rollback();
      if (!mounted || generation != _syncGeneration) return rollback();

      final marker = NMarker(
        id: group.id,
        position: NLatLng(group.lat, group.lng),
      );
      marker.setIcon(built.icon);
      marker.setSize(built.size);
      marker.setAnchor(built.anchor);
      marker.setOnTapListener((_) => _onMarkerTap(group));
      await _mapController?.addOverlay(marker);
      pending[group.id] = marker;
    }
    if (!mounted || generation != _syncGeneration) return rollback();
    _markers.addAll(pending);
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
    final cover = getPartyCoverMedia(item.data, tag: 'MapMarker');
    final isVideo = cover?.isVideo ?? false;
    final thumbUrl = cover?.thumbnailUrl;
    ui.Image? image;
    if (thumbUrl != null && thumbUrl.isNotEmpty) {
      image = await _fetchDecodedImage(thumbUrl);
    }
    if (!mounted) return null;

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
  // 일이 없어야 하기 때문이다.
  void _onMarkerTap(_MarkerGroup group) {
    _mapController?.updateCamera(
      NCameraUpdate.withParams(target: NLatLng(group.lat, group.lng)),
    );
    if (group.items.length == 1) {
      setState(() => _tapped = group.first);
      return;
    }
    setState(() => _tapped = null);
    _openGroupSheet(group);
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
    if (wasTier != isTier || newZoom.floor() != _syncedZoomStep) {
      _syncMarkers();
    }

    if (_pendingAreaSearch) {
      _pendingAreaSearch = false;
      _searchThisArea();
    } else {
      setState(() => _mapMoved = true);
    }
  }

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
    if (_filter.feeRanges.isNotEmpty) {
      // 목록과 동일하게 최소 참가비 기준(PartyPricing이 옛 필드도 흡수한다).
      final fee = PartyPricing.fromMap(p).displayPrice;
      if (!_filter.feeRanges.any((r) => _matchesFeeRange(fee, r))) return false;
    }
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

  static bool _matchesFeeRange(int fee, String range) {
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
      builder: (_) =>
          DetailSearchSheet(initialFilter: _filter, partyDates: _partyDates),
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

  Future<void> _searchThisArea() async {
    if (_mapController == null) return;
    final bounds = await _mapController!.getContentBounds();
    setState(() {
      _lastSearchBounds = bounds;
      _isAreaSearch = true;
      _recomputeVisible();
      _mapMoved = false;
    });
    _ensureSheetExpanded();
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
  Future<void> _goToCurrentLocation() async {
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

      // onCameraIdle 발생 시 자동 영역 검색 실행
      _pendingAreaSearch = true;

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
          if (kIsWeb)
            const _WebMapUnavailable()
          else
            NaverMap(
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
              },
              onMapTapped: (point, coord) => _dismissTappedCard(),
              onCameraIdle: () {
                _onCameraIdle();
              },
            ),

          // (종류 선택 칩은 지도 위에 없다 — 아래 목록 시트의 머리줄 한 곳에서만
          //  고른다. 같은 선택이 두 곳에 있으면 어느 쪽이 정본인지 알 수 없고,
          //  지도가 그만큼 좁아진다. MapKindFilterBar 주석 참고.)

          // ── "이 지도에서 보기" 버튼 (지도 상단 중앙) ──────────────
          // 칩이 있던 자리를 이 버튼이 물려받는다 — 지도 위에 떠 있는 것이
          // 이것뿐이라 더 내려 둘 이유가 없다.
          if (_mapMoved)
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _searchThisArea,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.refresh_rounded,
                          size: 16,
                          color: Color(0xFFFF6FA0),
                        ),
                        SizedBox(width: 7),
                        Text(
                          // 파티만 보던 화면이 아니다 — 지금 켜 둔 종류
                          // 전부를 이 영역에서 다시 찾는다.
                          '이 지도에서 다시 찾기',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

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

  /// 목록 머리말에 쓰는 종류 이름 — 셋 다 켜져 있으면 '전체', 아니면 켜 둔
  /// 것들을 이어 붙인다('파티·플레이스'). 지금 무엇을 세고 있는 개수인지가
  /// 숫자 옆에서 바로 읽혀야 한다.
  String _kindsLabel() {
    if (_kinds.length == MapListingKind.values.length) return '전체';
    return MapListingKind.values
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
  const _WebMapUnavailable();

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFF2F3F7),
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 28),
    child: const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.map_outlined, size: 40, color: Color(0xFFB9BECC)),
        SizedBox(height: 12),
        Text(
          '지도는 파티츄 앱에서 볼 수 있어요',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6B7280),
          ),
        ),
        SizedBox(height: 6),
        Text(
          '아래 목록에서 파티·플레이스를 그대로 둘러볼 수 있어요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: Color(0xFF9AA1AE)),
        ),
      ],
    ),
  );
}
