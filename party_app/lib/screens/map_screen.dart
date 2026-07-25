import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:party_app/screens/party_detail_screen.dart';
import 'package:party_app/screens/party_register_screen.dart';
import 'package:party_app/widgets/party_thumbnail_widget.dart';
import 'package:party_app/utils/feed_video_manager.dart';
import 'package:party_app/utils/party_utils.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/models/party_filter.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/utils/early_bird.dart';
import 'package:party_app/utils/party_eligibility.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/detail_search_sheet.dart';
import 'package:party_app/widgets/web_frame.dart';

// 줌 단계별 마커 표시 방식 — 멀리서는 점, 중간부터 원형 썸네일, 가까이는
// 기존 핀+카드 썸네일로 자연스럽게 전환된다.
enum _MarkerTier { dot, circle, card }

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
  bool _mapInitialized = false;  // 최초 onCameraIdle 무시용
  bool _mapMoved = false;        // "이 지도에서 파티 보기" 버튼 표시 여부
  bool _pendingAreaSearch = false; // 현재 위치 이동 후 자동 영역 검색 트리거
  double _currentZoom = 12.0;   // 현재 줌 레벨
  // 줌 3단계 전환 — 멀리서는 점 마커, 중간 줌부터 작은 원형 썸네일,
  // 확대하면 기존 핀+카드 썸네일. 기존엔 15 하나뿐이라 꽤 확대해야만
  // 썸네일이 보였는데, 원형 단계를 앞당겨(13) 더 낮은 줌에서도 파티 위치를
  // 한눈에 파악할 수 있게 했다.
  static const double _circleThumbZoomThreshold = 13.0;
  static const double _cardThumbZoomThreshold = 16.0;
  final Map<String, ui.Image> _imageCache = {}; // 마커 썸네일 디코딩된 이미지 캐시

  // ── 상세검색 필터 ─────────────────────────────────────────────────
  PartyFilter _filter = PartyFilter();
  Set<DateTime> _partyDates = {};

  // ── 파티 데이터 ────────────────────────────────────────────────────
  List<Map<String, dynamic>> _parties = [];           // Firestore 전체 파티
  List<Map<String, dynamic>> _displayedParties = [];  // 하단 목록에 표시할 파티
  bool _isAreaSearch = false;                          // 영역 검색 중 여부
  NLatLngBounds? _lastSearchBounds;                    // 마지막 영역 검색 bounds

  final Map<String, NMarker> _partyMarkers = {};
  late final StreamSubscription<QuerySnapshot> _partiesSubscription;

  Map<String, dynamic>? _tappedParty;
  String? _tappedDocId;

  // 하단 파티 목록 시트 — 사용자가 드래그해 접어둔 채로 "이 지도에서 파티
  // 보기"를 누르면(예: minChildSize=0.15까지 내려간 상태) 헤더(제목/개수)는
  // 보이지만 그 아래 Expanded 안의 ListView가 표시될 공간이 거의 남지 않아
  // "개수는 맞는데 카드가 안 보이는" 것처럼 보였다. 새로 영역 검색을 하면
  // 시트를 충분한 높이로 펼쳐 목록이 항상 눈에 보이도록 이 컨트롤러로 제어한다.
  final _sheetController = DraggableScrollableController();
  static const double _sheetExpandedSize = 0.5;

  @override
  void initState() {
    super.initState();
    // 지도 화면은 들어올 때마다 항상 음소거로 시작한다(마커 카드가 한 화면에
    // 여러 개 걸릴 수 있어 소리가 켜진 채 진입하면 시끄럽다) — 사용자가 직접
    // 스피커 버튼으로 켜면 그 뒤로는 다른 화면과 동일하게 전역 설정을 따른다.
    FeedVideoManager.instance.setMuted(true);
    _partiesSubscription = FirebaseFirestore.instance
        .collection('parties')
        .snapshots()
        .listen(_onPartiesUpdated);
  }

  @override
  void dispose() {
    _partiesSubscription.cancel();
    _sheetController.dispose();
    super.dispose();
  }

  // ── Firestore 파티 업데이트 ──────────────────────────────────────
  void _onPartiesUpdated(QuerySnapshot snapshot) {
    final parties = snapshot.docs
        .map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {'_docId': doc.id, ...data};
        })
        .where(PartyCard.isVisibleInList)
        .toList();

    // 달력 점 표시용 날짜 집합 갱신
    final dates = snapshot.docs
        .map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final dt = PartyCard.parsePartyDateTime(data);
          return dt != null ? DateTime(dt.year, dt.month, dt.day) : null;
        })
        .whereType<DateTime>()
        .toSet();

    setState(() {
      _parties = parties;
      _partyDates = dates;
      final bounded = _isAreaSearch && _lastSearchBounds != null
          ? _filterByBounds(parties, _lastSearchBounds!)
          : parties;
      _displayedParties = _applyDetailFilter(bounded);
    });

    if (_mapController != null) {
      _syncPartyMarkers(parties);
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
  Future<void> _syncPartyMarkers(List<Map<String, dynamic>> parties) async {
    if (_mapController == null) return;

    for (final marker in _partyMarkers.values) {
      await _mapController!.deleteOverlay(marker.info);
    }
    _partyMarkers.clear();

    if (parties.isEmpty || !mounted) return;

    switch (_tierForZoom(_currentZoom)) {
      case _MarkerTier.card:
        await _syncThumbMarkers(parties);
        break;
      case _MarkerTier.circle:
        await _syncCircleThumbMarkers(parties);
        break;
      case _MarkerTier.dot:
        await _syncDotMarkers(parties);
        break;
    }
  }

  // ── 핑크 점 마커 (줌 < 15) ──────────────────────────────────────
  Future<void> _syncDotMarkers(List<Map<String, dynamic>> parties) async {
    const dotSize = Size(10, 10);
    final dotIcon = await NOverlayImage.fromWidget(
      widget: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: const Color(0xFFFF4FA3),
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(color: Color(0x55000000), blurRadius: 3, offset: Offset(0, 1)),
          ],
        ),
      ),
      size: dotSize,
      context: context,
    );
    if (!mounted) return;

    for (final party in parties) {
      final docId = party['_docId'] as String;
      final lat = (party['latitude'] as num?)?.toDouble() ?? 0;
      final lng = (party['longitude'] as num?)?.toDouble() ?? 0;
      if (lat == 0 || lng == 0) continue;

      final marker = NMarker(id: docId, position: NLatLng(lat, lng));
      marker.setIcon(dotIcon);
      marker.setSize(dotSize);
      marker.setAnchor(const NPoint(0.5, 0.5));
      marker.setOnTapListener((_) => _onMarkerTap(party, docId, lat, lng));

      await _mapController?.addOverlay(marker);
      _partyMarkers[docId] = marker;
    }
  }

  // ── 썸네일 카드 마커 (줌 >= 15) ─────────────────────────────────
  // 대표 미디어가 동영상인 게시물도 getPartyCoverMedia()가 신규
  // (coverMediaType/coverThumbnailUrl/coverVideoUrl) 필드와 기존
  // (videoThumbnailUrl 등) 필드를 모두 확인해 정지 썸네일 URL을 골라준다 —
  // 동영상 URL 자체를 Image로 그리지 않고 항상 정지 썸네일만 사용한다.
  Future<void> _syncThumbMarkers(List<Map<String, dynamic>> parties) async {
    for (final party in parties) {
      if (!mounted) return;
      final docId = party['_docId'] as String;
      final lat = (party['latitude'] as num?)?.toDouble() ?? 0;
      final lng = (party['longitude'] as num?)?.toDouble() ?? 0;
      if (lat == 0 || lng == 0) continue;

      final cover = getPartyCoverMedia(party, tag: 'MapMarker');
      final isVideo = cover?.isVideo ?? false;
      final thumbUrl = cover?.thumbnailUrl;
      ui.Image? uiImage;
      if (thumbUrl != null && thumbUrl.isNotEmpty) {
        uiImage = await _fetchDecodedImage(thumbUrl);
      }
      if (!mounted) return;

      // 썸네일 URL이 없거나 디코딩에 실패해도 마커 자체는 반드시 그린다 —
      // 이미지 대신 동영상/일반 placeholder 아이콘으로 대체할 뿐 continue하지 않는다.
      const markerSize = Size(68, 82);
      final icon = await NOverlayImage.fromWidget(
        widget: _buildThumbMarkerWidget(uiImage, isVideo: isVideo),
        size: markerSize,
        context: context,
      );
      if (!mounted) return;

      final marker = NMarker(id: docId, position: NLatLng(lat, lng));
      marker.setIcon(icon);
      marker.setSize(markerSize);
      marker.setAnchor(const NPoint(0.5, 1.0));
      marker.setOnTapListener((_) => _onMarkerTap(party, docId, lat, lng));

      await _mapController?.addOverlay(marker);
      _partyMarkers[docId] = marker;
    }
  }

  // ── 원형 썸네일 마커 (중간 줌) ───────────────────────────────────
  // 카드형 썸네일보다 낮은 줌부터 보여주는 중간 단계 — 핀 줄기 없이 작은
  // 원형 아바타로만 표시해 화면이 덜 복잡하고 렌더링도 가볍다. 대표 미디어
  // 판정 로직(getPartyCoverMedia)은 카드형과 완전히 동일하게 재사용한다.
  Future<void> _syncCircleThumbMarkers(List<Map<String, dynamic>> parties) async {
    for (final party in parties) {
      if (!mounted) return;
      final docId = party['_docId'] as String;
      final lat = (party['latitude'] as num?)?.toDouble() ?? 0;
      final lng = (party['longitude'] as num?)?.toDouble() ?? 0;
      if (lat == 0 || lng == 0) continue;

      final cover = getPartyCoverMedia(party, tag: 'MapMarkerCircle');
      final isVideo = cover?.isVideo ?? false;
      final thumbUrl = cover?.thumbnailUrl;
      ui.Image? uiImage;
      if (thumbUrl != null && thumbUrl.isNotEmpty) {
        uiImage = await _fetchDecodedImage(thumbUrl);
      }
      if (!mounted) return;

      const markerSize = Size(40, 40);
      final icon = await NOverlayImage.fromWidget(
        widget: _buildCircleThumbMarkerWidget(uiImage, isVideo: isVideo),
        size: markerSize,
        context: context,
      );
      if (!mounted) return;

      final marker = NMarker(id: docId, position: NLatLng(lat, lng));
      marker.setIcon(icon);
      marker.setSize(markerSize);
      marker.setAnchor(const NPoint(0.5, 0.5));
      marker.setOnTapListener((_) => _onMarkerTap(party, docId, lat, lng));

      await _mapController?.addOverlay(marker);
      _partyMarkers[docId] = marker;
    }
  }

  // 원형 썸네일 위젯 — 핀 줄기가 없는 작은 원형 아바타.
  static Widget _buildCircleThumbMarkerWidget(ui.Image? image, {bool isVideo = false}) {
    const size = 40.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
      child: ClipOval(
        child: image != null
            ? RawImage(image: image, fit: BoxFit.cover)
            : Container(
                color: isVideo ? const Color(0xFF1A1A2E) : const Color(0xFFFFEAF1),
                child: Icon(
                  isVideo ? Icons.videocam_outlined : Icons.celebration_outlined,
                  color: const Color(0xFFFF6FA0),
                  size: 18,
                ),
              ),
      ),
    );
  }

  void _onMarkerTap(Map<String, dynamic> party, String docId, double lat, double lng) {
    setState(() {
      _tappedParty = party;
      _tappedDocId = docId;
    });
    _mapController?.updateCamera(
      NCameraUpdate.withParams(target: NLatLng(lat, lng)),
    );
  }

  // ── 이미지 다운로드 후 ui.Image로 디코딩 (캐시 우선) ────────────
  Future<ui.Image?> _fetchDecodedImage(String url) async {
    if (_imageCache.containsKey(url)) return _imageCache[url];
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final codec  = await ui.instantiateImageCodec(res.bodyBytes);
        final frame  = await codec.getNextFrame();
        _imageCache[url] = frame.image;
        return frame.image;
      }
    } catch (e) {
      debugPrint('[MapMarker] image fetch/decode error: $e  url=$url');
    }
    return null;
  }

  // ── 썸네일 마커 위젯 (RawImage로 동기 렌더링) ────────────────────
  // 썸네일 이미지가 없을 때: 동영상 대표 게시물은 동영상 아이콘 placeholder,
  // 그 외에는 기존 축하 아이콘 placeholder — 어느 쪽이든 마커 자체는 그려진다.
  static Widget _buildThumbMarkerWidget(ui.Image? image, {bool isVideo = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(color: Color(0x55000000), blurRadius: 8, offset: Offset(0, 3)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: image != null
                ? RawImage(image: image, fit: BoxFit.cover)
                : Container(
                    color: isVideo
                        ? const Color(0xFF1A1A2E)
                        : const Color(0xFFFFEAF1),
                    child: Icon(
                      isVideo
                          ? Icons.videocam_outlined
                          : Icons.celebration_outlined,
                      color: const Color(0xFFFF6FA0),
                      size: 26,
                    ),
                  ),
          ),
        ),
        // 핀 줄기
        Container(
          width: 2.5,
          height: 12,
          color: const Color(0xFFFF4FA3),
        ),
        // 핀 끝 점
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFFF4FA3),
          ),
        ),
      ],
    );
  }

  void _dismissTappedCard() {
    if (_tappedParty != null) {
      setState(() {
        _tappedParty = null;
        _tappedDocId = null;
      });
    }
  }

  // ── 카메라 idle 감지 ───────────────────────────────────────────────
  Future<void> _onCameraIdle() async {
    if (!_mapInitialized) return;

    // 줌 레벨 확인 → 3단계(점/원형/카드) 중 다른 단계로 넘어갔을 때만 재빌드
    final pos = await _mapController?.getCameraPosition();
    if (!mounted) return;
    final newZoom = pos?.zoom ?? _currentZoom;
    final wasTier = _tierForZoom(_currentZoom);
    final isTier  = _tierForZoom(newZoom);
    _currentZoom = newZoom;
    if (wasTier != isTier) {
      _syncPartyMarkers(_parties);
    }

    if (_pendingAreaSearch) {
      _pendingAreaSearch = false;
      _searchThisArea();
    } else {
      setState(() => _mapMoved = true);
    }
  }

  // ── 지도 영역 기준 파티 필터 ──────────────────────────────────────
  List<Map<String, dynamic>> _filterByBounds(
      List<Map<String, dynamic>> parties, NLatLngBounds bounds) {
    final sw = bounds.southWest;
    final ne = bounds.northEast;
    return parties.where((party) {
      final lat = (party['latitude'] as num?)?.toDouble();
      final lng = (party['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null || lat == 0 || lng == 0) return false;
      return lat >= sw.latitude &&
          lat <= ne.latitude &&
          lng >= sw.longitude &&
          lng <= ne.longitude;
    }).toList();
  }

  // ── 상세검색 필터 적용 ────────────────────────────────────────────
  List<Map<String, dynamic>> _applyDetailFilter(List<Map<String, dynamic>> parties) {
    if (!_filter.isActive) return parties;
    return parties.where((p) => _matchesDetailFilter(p)).toList();
  }

  /// 선택된 구/시/군(district) 중 하나라도 일치하면 통과.
  /// district 필드가 없는 기존 데이터는 region(시/도) 기준으로 하위호환 매칭한다.
  bool _matchesDistrictFilter(Map<String, dynamic> p, Set<String> selectedDistricts) {
    final district = p['district'] as String?;
    if (district != null && district.isNotEmpty) {
      return selectedDistricts.contains(district);
    }
    final region = p['region'] as String? ?? '';
    if (region.isEmpty) return false;
    final legacyRegions = selectedDistricts.expand(RegionData.regionsOfDistrict);
    return legacyRegions.contains(region);
  }

  // 연령대(10년 단위) 선택값 중 하나라도 파티의 연령 제한 범위와 겹치면 통과.
  // 파티에 연령 제한이 없으면(ageRestrictionEnabled=false) 모든 연령대에
  // 열려 있는 것으로 간주한다.
  bool _matchesAgeGroups(Map<String, dynamic> p, Set<String> groups) {
    final ageRestrictionEnabled = p['ageRestrictionEnabled'] as bool? ?? false;
    if (!ageRestrictionEnabled) return true;
    final partyMin = (p['minBirthYear'] as num?)?.toInt() ?? -100000000;
    final partyMax = (p['maxBirthYear'] as num?)?.toInt() ?? 100000000;
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
        case '40대 이상':
          groupMin = nowYear - 150;
          groupMax = nowYear - 40;
          break;
        default:
          continue;
      }
      if (partyMin <= groupMax && partyMax >= groupMin) return true;
    }
    return false;
  }

  bool _matchesDetailFilter(Map<String, dynamic> p) {
    if (_filter.districts.isNotEmpty) {
      if (!_matchesDistrictFilter(p, _filter.districts)) return false;
    }
    if (_filter.genderConditions.isNotEmpty) {
      final gl  = p['genderLimit'] as String? ?? 'all';
      final gcm = p['genderCapacityMode'] as String? ?? 'unlimited';
      final gm  = p['genderMode'] as String? ?? '';
      final label = gl == 'male' ? '남자만'
          : gl == 'female' ? '여자만'
          : (gm == 'balanced' || gcm == 'separate') ? '성비 맞춤'
          : '남녀무관';
      if (!_filter.genderConditions.contains(label)) return false;
    }
    if (_filter.feeRanges.isNotEmpty) {
      final maleFee    = (p['maleFee'] as num?)?.toInt();
      final femaleFee  = (p['femaleFee'] as num?)?.toInt();
      final legacyFee  = (p['fee'] as num?)?.toInt() ?? 0;
      final fee = [maleFee, femaleFee].whereType<int>().fold(
          legacyFee, (a, b) => a == 0 ? b : (b < a ? b : a));
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
      if (PartyCard.effectiveStatus(p) != '모집중') return false;
      final elig = checkPartyEligibility(
        p,
        UserSession.gender,
        UserSession.birthYear,
      );
      if (elig != PartyEligibility.eligible) return false;
    }
    if (_filter.earlyBirdOnly && !EarlyBird.isActive(p)) return false;
    if (_filter.dateOptions.isNotEmpty) {
      final dt = PartyCard.parsePartyDateTime(p);
      if (dt == null) return false;
      final now = DateTime.now();
      if (!_filter.dateOptions.any((opt) => _matchesDateOption(dt, opt, now))) return false;
    }
    // 날짜 직접 선택 + 시간 범위 필터
    if (_filter.selectedDate != null) {
      final dt = PartyCard.parsePartyDateTime(p);
      if (dt == null) return false;
      final partyDay = DateTime(dt.year, dt.month, dt.day);
      final selDay   = DateTime(_filter.selectedDate!.year,
          _filter.selectedDate!.month, _filter.selectedDate!.day);
      if (partyDay != selDay) return false;
      final partyMins = dt.hour * 60 + dt.minute;
      if (_filter.startTime != null) {
        final startMins =
            _filter.startTime!.hour * 60 + _filter.startTime!.minute;
        if (partyMins < startMins) return false;
      }
      if (_filter.endTime != null) {
        final endMins =
            _filter.endTime!.hour * 60 + _filter.endTime!.minute;
        if (partyMins > endMins) return false;
      }
    }
    return true;
  }

  static bool _matchesFeeRange(int fee, String range) {
    switch (range) {
      case '무료':       return fee <= 0;
      case '1만원 이하':  return fee > 0 && fee <= 10000;
      case '1~3만원':   return fee > 10000 && fee <= 30000;
      case '3~5만원':   return fee > 30000 && fee <= 50000;
      case '5~10만원':  return fee > 50000 && fee <= 100000;
      case '10~20만원': return fee > 100000 && fee <= 200000;
      case '20만원 이상': return fee > 200000;
      default:          return true;
    }
  }

  static bool _matchesDateOption(DateTime dt, String option, DateTime now) {
    final today    = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    switch (option) {
      case '오늘':    return dt.isAfter(today.subtract(const Duration(seconds: 1)))
                         && dt.isBefore(tomorrow);
      case '내일':    return dt.isAfter(tomorrow.subtract(const Duration(seconds: 1)))
                         && dt.isBefore(tomorrow.add(const Duration(days: 1)));
      case '이번주':
        final monday  = today.subtract(Duration(days: now.weekday - 1));
        final sunday  = monday.add(const Duration(days: 7));
        return dt.isAfter(monday.subtract(const Duration(seconds: 1))) && dt.isBefore(sunday);
      case '이번주말':
        final monday   = today.subtract(Duration(days: now.weekday - 1));
        final saturday = monday.add(const Duration(days: 5));
        final sunday   = monday.add(const Duration(days: 7));
        return dt.isAfter(saturday.subtract(const Duration(seconds: 1))) && dt.isBefore(sunday);
      default: return true;
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
            initialFilter: _filter, partyDates: _partyDates),
    );
    if (result != null) {
      setState(() {
        _filter = result;
        _displayedParties = _applyDetailFilter(
          _isAreaSearch && _lastSearchBounds != null
              ? _filterByBounds(_parties, _lastSearchBounds!)
              : _parties,
        );
      });
    }
  }

  Future<void> _searchThisArea() async {
    if (_mapController == null) return;
    final bounds = await _mapController!.getContentBounds();
    setState(() {
      _lastSearchBounds = bounds;
      _displayedParties = _applyDetailFilter(_filterByBounds(_parties, bounds));
      _mapMoved = false;
      _isAreaSearch = true;
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('위치 권한이 필요합니다')),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
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
      _currentLocationMarker =
          NMarker(id: 'my_location', position: latLng);
      await _mapController?.addOverlay(_currentLocationMarker!);
    } catch (e) {
      _pendingAreaSearch = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('위치를 가져올 수 없습니다: $e')),
        );
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
          NaverMap(
            options: const NaverMapViewOptions(
              initialCameraPosition: NCameraPosition(
                target: NLatLng(37.5665, 126.9780),
                zoom: 12,
              ),
            ),
            onMapReady: (controller) {
              _mapController = controller;
              if (_parties.isNotEmpty) {
                _syncPartyMarkers(_parties);
              }
              // 초기 onCameraIdle 무시를 위해 한 프레임 후 초기화 완료 표시
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _mapInitialized = true);
              });
            },
            onMapTapped: (point, coord) => _dismissTappedCard(),
            onCameraIdle: () { _onCameraIdle(); },
          ),

          // ── "이 지도에서 파티 보기" 버튼 (지도 상단 중앙) ─────────
          if (_mapMoved)
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _searchThisArea,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
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
                        Icon(Icons.refresh_rounded,
                            size: 16, color: Color(0xFFFF6FA0)),
                        SizedBox(width: 7),
                        Text(
                          '이 지도에서 파티 보기',
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
                  onPressed:
                      _isLoadingLocation ? null : _goToCurrentLocation,
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

          // ── 파티 목록 바텀 시트 ─────────────────────────────────
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: sheetSize,
            minChildSize: 0.15,
            maxChildSize: 0.85,
            builder: (context, scrollController) {
              final count = _displayedParties.length;
              final headerText = _isAreaSearch
                  ? '이 지역 파티 ($count)'
                  : '이 근처 파티 ($count)';

              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF4F8),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 12,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
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
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            headerText,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          GestureDetector(
                            onTap: _openDetailSearch,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: _filter.isActive
                                    ? const Color(0xFFFF6FA0)
                                    : const Color(0xFFFFF0F5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.tune,
                                size: 20,
                                color: _filter.isActive
                                    ? Colors.white
                                    : const Color(0xFFFF6FA0),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _displayedParties.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.all(16),
                              itemCount: _displayedParties.length,
                              itemBuilder: (context, index) =>
                                  _buildPartyListCard(
                                      _displayedParties[index]),
                            ),
                    ),
                  ],
                ),
              );
            },
          ),

          // ── 마커 탭 시 파티 정보 카드 ────────────────────────────
          if (_tappedParty != null)
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
                  child: _buildTappedPartyCard(),
                );
              },
            ),
        ],
      ),
    );
  }

  // ── 빈 결과 화면 ───────────────────────────────────────────────────
  Widget _buildEmptyState() {
    if (_isAreaSearch) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.search_off_rounded,
                  size: 52, color: Colors.black26),
              const SizedBox(height: 14),
              const Text(
                '이 지도 영역에는 아직 파티가 없어요.',
                style: TextStyle(
                    fontSize: 15,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                '직접 파티를 등록해보세요!',
                style: TextStyle(fontSize: 13, color: Colors.black38),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    webFramedRoute((_) => const PartyRegisterScreen()),
                  );
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('파티 등록하기',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6FA0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return const Center(
      child: Text(
        '등록된 파티가 없습니다',
        style: TextStyle(color: Colors.black45),
      ),
    );
  }

  // ── 마커 탭 카드 ────────────────────────────────────────────────────
  Widget _buildTappedPartyCard() {
    final party = _tappedParty!;
    final docId = _tappedDocId!;
    final title = party['title'] as String? ?? '';
    // 마커 탭 카드는 상세주소 없이 "구+동"만 — 상세페이지에서만 전체 주소를 보여준다.
    final address = RegionData.formatCardLocation(party);
    final cover = getPartyCoverMedia(party, tag: 'MapInfoCard');
    final thumbnailUrl = cover?.thumbnailUrl;

    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                          child: Icon(Icons.videocam_outlined,
                              size: 24, color: Color(0xFFFF6FA0)),
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 13, color: Colors.black38),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            address,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54),
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
                setState(() {
                  _tappedParty = null;
                  _tappedDocId = null;
                });
                Navigator.push(
                  context,
                  webFramedRoute((_) => PartyDetailScreen(docId: docId),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
              ),
              child:
                  const Text('상세보기', style: TextStyle(fontSize: 13)),
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

  // ── 파티 목록 카드 ──────────────────────────────────────────────────
  Widget _buildPartyListCard(Map<String, dynamic> party) {
    final docId = party['_docId'] as String;
    return PartyCard(party: party, docId: docId);
  }
}
