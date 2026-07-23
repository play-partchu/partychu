import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:party_app/screens/register_type_screen.dart';
import 'package:party_app/screens/map_screen.dart';
import 'package:party_app/screens/my_page_screen.dart';
import 'package:party_app/screens/place_detail_screen.dart';
import 'package:party_app/screens/party_shop_detail_screen.dart';
import 'package:party_app/screens/party_detail_screen.dart';
import 'package:party_app/screens/event_detail_screen.dart';
import 'package:party_app/screens/event_register_screen.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/screens/party_video_feed_screen.dart';
import 'package:party_app/utils/favorites_service.dart';
import 'package:party_app/utils/feed_video_manager.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/utils/party_eligibility.dart';
import 'package:party_app/utils/party_utils.dart';
import 'package:party_app/utils/register_return_signal.dart';
import 'package:party_app/widgets/favorite_star_button.dart';
import 'package:party_app/screens/chat_list_screen.dart';
import 'package:party_app/login.dart';
import 'package:party_app/screens/identity_verification_screen.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/utils/responsive.dart';
import 'package:party_app/models/party_filter.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/utils/early_bird.dart';
import 'package:party_app/models/place_filter.dart';
import 'package:party_app/models/shop_filter.dart';
import 'package:party_app/models/crew_filter.dart';
import 'package:party_app/widgets/auth_rebuilder.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/widgets/detail_search_sheet.dart';
import 'package:party_app/widgets/place_detail_search_sheet.dart';
import 'package:party_app/widgets/shop_detail_search_sheet.dart';
import 'package:party_app/widgets/crew_detail_search_sheet.dart';
import 'package:party_app/utils/party_view_mode.dart';
import 'package:party_app/widgets/party_view_mode_sheet.dart';
import 'package:party_app/widgets/video_mute_button.dart';
import 'package:party_app/widgets/main/main_top_bar.dart';
import 'package:party_app/widgets/place_category_nav_bar.dart';
import 'package:party_app/widgets/main/main_filter_panel.dart';
import 'package:party_app/widgets/main/main_preview_panel.dart';
import 'package:party_app/screens/party_register_screen.dart';
import 'package:party_app/screens/place_register_screen.dart';
import 'package:party_app/screens/party_market_register_screen.dart';
import 'package:party_app/screens/crew_register_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  // 디자인할 예정이라 지금은 그대로 두고, 밤 버전만 header_logo_night/
  // header_half_night로 교체해 보여준다. _headerCollapsed(스크롤 축소)와는
  // 독립적인 별개의 상태 — 두 축이 곱해져 4가지 이미지 중 하나가 보인다.
  bool _isNightMode = false;

  // 영상 크게 보기는 더 이상 목록 화면 안에서 인라인으로 그려지지 않고
  // 항상 별도의 전체화면(PartyVideoFeedScreen)으로만 진입한다. 앱을 마지막에
  // 영상 모드로 종료했다가 다시 켰을 때는 목록 자체는 기본 카드로 그린 채
  // 파티 문서가 로드되는 즉시 한 번만 자동으로 전체화면을 띄운다.
  bool _pendingAutoOpenVideoFeed = false;

  // ── 파티 목록 정렬 ────────────────────────────────────────────────
  // 정렬 모드 자체는 이제 상세검색 시트의 "정렬" 아코디언에서 고르므로
  // _filter.sortMode를 그대로 쓴다. 거리순만 위치 권한/좌표가 필요해
  // _currentPosition은 화면 상태로 별도 보관한다(필터 값이 아니라 기기
  // 상태이므로 PartyFilter에는 넣지 않음).
  Position? _currentPosition; // 거리순 정렬용

  // ── 파티 목록 보기 방식(작은 카드/기본 카드/영상 크게 보기) ─────────
  // 기기에 저장되어 앱을 다시 실행해도 유지된다(PartyViewMode.load()).
  PartyViewMode _viewMode = PartyViewMode.standard;

  // ── 파티 탭 전용 상태 ─────────────────────────────────────────────
  final Stream<QuerySnapshot> _partyStream = FirebaseFirestore.instance
      .collection('parties')
      .snapshots();

  static const String _kAllCategoryTab = '전체';
  static const List<String> _categoryTabs = [
    _kAllCategoryTab,
    '오늘',
    '내일',
    '이번 주',
    '이번 주말',
  ];

  // 날짜 카테고리는 '전체'만 예외적으로 배타 선택이고(다른 넷과 동시에
  // 켜질 수 없음), 나머지 넷(오늘/내일/이번 주/이번 주말)은 중복 선택이
  // 가능하다. '전체'는 이 Set에 절대 담기지 않는다 — "전체 선택됨" 상태는
  // 이 Set이 비어 있는지로만 판단한다(_isAllCategorySelected). 하나 이상
  // 담기면 그 중 하나라도 맞는 파티를 보여준다(OR 매칭, _matchesCategoryTabs).
  final Set<String> _selectedCategories = {};
  bool get _isAllCategorySelected => _selectedCategories.isEmpty;
  // 날짜 탭별 손그림 낙서 애니메이션 컨트롤러 — 탭이 선택될 때 낙서가
  // 천천히 그려지는 모션(정방향)과 해제될 때 지워지는 모션(역방향)을
  // 담당한다. _categoryTabs는 5개로 고정이라 initState에서 한 번만 만든다.
  final Map<String, AnimationController> _categoryRingCtrls = {};
  PartyFilter _filter = PartyFilter();

  // ── 장소대여/파티샵/파트너 탭 전용 상세검색 필터 (파티와 완전히 분리) ─
  PlaceFilter _placeFilter = PlaceFilter();
  ShopFilter _shopFilter = ShopFilter();
  CrewFilter _crewFilter = CrewFilter();
  // 플레이스 탭은 별도 상세검색 시트 없이 상단 특징(테마) 태그 칩만으로
  // 필터링한다(비어 있으면 전체) — 여러 개를 동시에 켤 수 있고, 태그 중
  // 하나라도 포함되면 매칭된다.
  final Set<String> _eventThemeFilter = {};
  // 플레이스 탭 상단 카테고리 칩의 "파티샵"은 events가 아니라 완전히 별도인
  // partyShops 컬렉션을 보여주므로, 테마 태그(_eventThemeFilter)와는 분리된
  // 전용 상태로 다른 4개 칩과 배타적으로 전환한다(둘 다 켜질 수 없음).
  bool _placeShowShopCategory = false;

  Set<DateTime> _partyDates = {};
  late final StreamSubscription<QuerySnapshot> _partyDatesSub;

  // ── 검색 ──────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  // ── 장소대여 지역 필터 ─────────────────────────────────────────────
  // 형식: "{시/도} {구/시/군}"  예) "서울 강남구", "경기 성남시"
  final Set<String> _placeFilterDistricts = {};

  // 지역 데이터는 lib/models/region_data.dart(RegionData)에서 공유 관리.

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

  // ── 수명주기 ──────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _topTabController = TabController(length: 4, vsync: this);
    // 탭을 바꾸면 이전 탭에서 선택했던 미리보기(데스크톱 전용)는 더 이상
    // 유효하지 않으므로 함께 초기화한다.
    _topTabController.addListener(() => setState(_clearPreview));
    for (final tab in _categoryTabs) {
      _categoryRingCtrls[tab] = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
      );
    }
    // 처음 진입 시 아무 날짜도 선택돼 있지 않아 "전체"가 기본으로 활성 —
    // 이건 사용자가 막 탭한 게 아니므로 그려지는 모션 없이 바로 켜둔다.
    _categoryRingCtrls[_kAllCategoryTab]?.value = 1.0;
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkVerificationOnStart(),
    );

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

    _partyScrollCtrl.addListener(_onPartyScroll);
    // 달력 점 표시용 파티 날짜 수집
    _partyDatesSub = FirebaseFirestore.instance
        .collection('parties')
        .snapshots()
        .listen((snapshot) {
          final dates = snapshot.docs
              .map((doc) {
                final data = doc.data();
                final dt = PartyCard.parsePartyDateTime(data);
                return dt != null ? DateTime(dt.year, dt.month, dt.day) : null;
              })
              .whereType<DateTime>()
              .toSet();
          if (mounted) setState(() => _partyDates = dates);
        });
  }

  @override
  void dispose() {
    pendingTopTabAfterRegister.removeListener(_onPendingTopTabAfterRegister);
    _topTabController.dispose();
    _coachMarkCtrl.dispose();
    for (final ctrl in _categoryRingCtrls.values) {
      ctrl.dispose();
    }
    _partyScrollCtrl.dispose();
    _partyDatesSub.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
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

  // ── 앱 시작 시 본인확인 미완료 사용자 → 인증 화면으로 이동 ──────────────
  Future<void> _checkVerificationOnStart() async {
    if (!mounted) return;
    if (UserSession.userId.isNotEmpty && !UserSession.identityVerified) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const IdentityVerificationScreen()),
      );
      if (mounted) setState(() {});
    }
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
  Future<void> _goToRegisterScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterTypeScreen()),
    );
  }

  Future<bool> _requireVerification() async {
    // Step 1: 로그인 확인
    if (UserSession.userId.isEmpty) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => LoginPage()),
      );
      if (!mounted) return false;
      if (UserSession.userId.isEmpty) return false;
    }

    // Step 2: NICE 본인확인 확인
    if (!UserSession.identityVerified) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const IdentityVerificationScreen()),
      );
      if (!mounted) return false;
      if (!UserSession.identityVerified) return false;
    }

    return true;
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
        MaterialPageRoute(builder: (_) => const MapScreen()),
      ).then((_) => setState(() => _currentIndex = 0));
    } else if (index == 2) {
      final ok = await _requireVerification();
      if (!mounted) return;
      setState(() => _currentIndex = 0);
      if (ok) {
        _goToRegisterScreen().then((_) => setState(() => _currentIndex = 0));
      }
    } else if (index == 3) {
      final ok = await _requireVerification();
      if (!mounted) return;
      setState(() => _currentIndex = 0);
      if (ok) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ChatListScreen()),
        ).then((_) => setState(() => _currentIndex = 0));
      }
    } else if (index == 4) {
      final ok = await _requireVerification();
      if (!mounted) return;
      setState(() => _currentIndex = 0);
      if (ok) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyPageScreen()),
        ).then((_) => setState(() => _currentIndex = 0));
      }
    }
  }

  // ── 보기 방식(작은 카드/기본 카드/영상 크게 보기) ──────────────────
  // 영상 크게 보기를 고르면 목록에 인라인으로 그리지 않고 곧바로 전체화면
  // 피드(PartyVideoFeedScreen)로 진입한다 — 그래서 이 목록 화면의 _viewMode는
  // 절대 video가 되지 않는다(항상 작은/기본 카드 중 하나).
  Future<void> _showViewModeSheet(List<QueryDocumentSnapshot> docs) async {
    final selected = await showModalBottomSheet<PartyViewMode>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PartyViewModeSheet(current: _viewMode),
    );
    if (selected == null || !mounted) return;
    unawaited(selected.save());
    if (selected == PartyViewMode.video) {
      if (docs.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('표시할 파티가 없어요.')));
        return;
      }
      _openVideoFullscreen(docs, 0);
      return;
    }
    setState(() => _applyViewMode(selected));
  }

  void _applyViewMode(PartyViewMode mode) {
    _viewMode = mode;
  }

  // 헤더의 트리거 아이콘과 BottomSheet의 아이콘이 어긋나지 않도록 같은
  // 매핑(partyViewModeIcon)을 공유한다.
  static IconData _viewModeIcon(PartyViewMode mode) => partyViewModeIcon(mode);

  // "파티 목록" 옆 돋보기 버튼 — 검색창을 화면에 항상 띄워두는 대신 필요할
  // 때만 팝업(BottomSheet)으로 연다. 새 검색 로직을 만들지 않고 기존
  // 검색창(_searchController/_searchQuery)과 검색 로직(_matchesSearch 등)을
  // 팝업 안에서 그대로 재사용한다.
  Future<void> _openSearchPopup() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            20,
            16,
            MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '파티 검색',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildSearchBar(
                    onSubmitted: () => Navigator.pop(sheetContext),
                    onChangedExtra: () => setModalState(() {}),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6FA0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('검색'),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  // ── 정렬 ─────────────────────────────────────────────────────────
  // 정렬 선택 UI는 상세검색 시트("정렬" 아코디언)로 옮겨갔다 — 여기서는
  // 시트가 돌려준 필터의 sortMode가 거리순이면 위치 권한/좌표만 확보한다
  // (권한이 없거나 실패하면 _openPartyDetailSearch에서 기본순으로 되돌린다).
  Future<bool> _resolveDistanceSort() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (!mounted) return false;
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('위치 권한이 없어 기본순을 유지합니다.')));
      return false;
    }
    try {
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return false;
      _currentPosition = pos;
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('위치를 가져올 수 없어 기본순을 유지합니다.')));
      }
      return false;
    }
  }

  List<QueryDocumentSnapshot> _applySortMode(List<QueryDocumentSnapshot> docs) {
    switch (_filter.sortMode) {
      case PartySortMode.defaultOrder:
        return docs;
      case PartySortMode.distance:
        if (_currentPosition == null) return docs;
        final pos = _currentPosition!;
        return List.of(docs)..sort((a, b) {
          final aD = a.data() as Map<String, dynamic>;
          final bD = b.data() as Map<String, dynamic>;
          return _dist(
            pos.latitude,
            pos.longitude,
            (aD['latitude'] as num?)?.toDouble() ?? 0,
            (aD['longitude'] as num?)?.toDouble() ?? 0,
          ).compareTo(
            _dist(
              pos.latitude,
              pos.longitude,
              (bD['latitude'] as num?)?.toDouble() ?? 0,
              (bD['longitude'] as num?)?.toDouble() ?? 0,
            ),
          );
        });
      case PartySortMode.deadlineSoon:
        return List.of(docs)..sort((a, b) {
          final ad = a.data() as Map<String, dynamic>;
          final bd = b.data() as Map<String, dynamic>;
          final aDl = (ad['recruitDeadlineAt'] as Timestamp?)?.toDate();
          final bDl = (bd['recruitDeadlineAt'] as Timestamp?)?.toDate();
          final now = DateTime.now();
          // 마감된 것은 맨 뒤
          final aExpired = aDl != null && aDl.isBefore(now);
          final bExpired = bDl != null && bDl.isBefore(now);
          if (aExpired != bExpired) return aExpired ? 1 : -1;
          // 마감 시간 없는 것은 맨 뒤
          if (aDl == null && bDl == null) return 0;
          if (aDl == null) return 1;
          if (bDl == null) return -1;
          return aDl.compareTo(bDl);
        });
      case PartySortMode.feeLow:
        return List.of(docs)..sort(
          (a, b) => _minFee(
            a.data() as Map<String, dynamic>,
          ).compareTo(_minFee(b.data() as Map<String, dynamic>)),
        );
      case PartySortMode.feeHigh:
        return List.of(docs)..sort(
          (a, b) => _maxFee(
            b.data() as Map<String, dynamic>,
          ).compareTo(_maxFee(a.data() as Map<String, dynamic>)),
        );
      case PartySortMode.capacityLow:
        return List.of(docs)..sort(
          (a, b) => _capacity(
            a.data() as Map<String, dynamic>,
          ).compareTo(_capacity(b.data() as Map<String, dynamic>)),
        );
      case PartySortMode.capacityHigh:
        return List.of(docs)..sort(
          (a, b) => _capacity(
            b.data() as Map<String, dynamic>,
          ).compareTo(_capacity(a.data() as Map<String, dynamic>)),
        );
    }
  }

  static double _dist(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return 2 * r * atan2(sqrt(a), sqrt(1 - a));
  }

  static int _minFee(Map<String, dynamic> p) {
    final vals = [
      (p['maleFee'] as num?)?.toInt(),
      (p['femaleFee'] as num?)?.toInt(),
      (p['fee'] as num?)?.toInt(),
    ].whereType<int>().where((f) => f >= 0);
    return vals.isEmpty ? 0 : vals.reduce(min);
  }

  static int _maxFee(Map<String, dynamic> p) {
    final vals = [
      (p['maleFee'] as num?)?.toInt(),
      (p['femaleFee'] as num?)?.toInt(),
      (p['fee'] as num?)?.toInt(),
    ].whereType<int>();
    return vals.isEmpty ? 0 : vals.reduce(max);
  }

  static int _capacity(Map<String, dynamic> p) =>
      (p['maxParticipants'] as num?)?.toInt() ??
      (p['maxCapacity'] as num?)?.toInt() ??
      0;

  // 탭별 상세검색 진입점 — 파티는 기존 구조 그대로, 나머지는 서비스 전용 화면으로 분리.
  // 플레이스(index 1)는 페이지 상단 카테고리 칩만으로 필터링해서 별도 시트가 없다.
  Future<void> _openDetailSearch() async {
    // 상세검색 시트가 열려 있는 동안 뒤에서 동영상 소리가 계속 새어나오지
    // 않도록, 시트를 열기 전에 재생 중인 동영상을 즉시 일시정지한다.
    FeedVideoManager.instance.pauseActive();
    switch (_topTabController.index) {
      case 1:
        // 플레이스 탭 안의 "파티샵" 카테고리에서만 상세검색 시트가 있다.
        if (_placeShowShopCategory) await _openShopDetailSearch();
        return;
      case 2:
        await _openPlaceDetailSearch();
        return;
      case 3:
        await _openCrewDetailSearch();
        return;
      default:
        await _openPartyDetailSearch();
        return;
    }
  }

  Future<void> _openPartyDetailSearch() async {
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
    if (result == null) return;
    // "정렬" 아코디언에서 거리순을 골랐으면 여기서 위치 권한/좌표를 확보한다
    // — 실패하면(권한 거부 등) 기본순으로 되돌려 필터에 반영한다.
    if (result.sortMode == PartySortMode.distance) {
      final ok = await _resolveDistanceSort();
      if (!ok) result.sortMode = PartySortMode.defaultOrder;
    } else {
      _currentPosition = null;
    }
    if (!mounted) return;
    setState(() => _filter = result);
  }

  Future<void> _openPlaceDetailSearch() async {
    final result = await showModalBottomSheet<PlaceFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PlaceDetailSearchSheet(initialFilter: _placeFilter),
    );
    if (result != null) setState(() => _placeFilter = result);
  }

  Future<void> _openShopDetailSearch() async {
    final result = await showModalBottomSheet<ShopFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ShopDetailSearchSheet(initialFilter: _shopFilter),
    );
    if (result != null) setState(() => _shopFilter = result);
  }

  Future<void> _openCrewDetailSearch() async {
    final result = await showModalBottomSheet<CrewFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CrewDetailSearchSheet(initialFilter: _crewFilter),
    );
    if (result != null) setState(() => _crewFilter = result);
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
  static const _kTabLabels = ['파티츄', '플레이스', '장소대여', '파트너'];

  Future<void> _handleLoginOrMyPageTap() async {
    if (UserSession.userId.isEmpty) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => LoginPage()),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MyPageScreen()),
      );
    }
    if (mounted) setState(() {});
  }

  // 데스크톱 상단바의 "등록하기"는 선택된 카테고리에 맞는 등록화면으로 바로
  // 이동한다(모바일 하단내비 "등록"은 기존처럼 RegisterTypeScreen을 그대로 거친다 — 변경 없음).
  Future<void> _handleCategoryAwareRegisterTap() async {
    final ok = await _requireVerification();
    if (!mounted || !ok) return;
    final Widget target = switch (_topTabController.index) {
      1 => _placeShowShopCategory
          ? const PartyMarketRegisterScreen()
          : const EventRegisterScreen(),
      2 => const PlaceRegisterScreen(),
      3 => const CrewRegisterScreen(),
      _ => const PartyRegisterScreen(),
    };
    await Navigator.push(context, MaterialPageRoute(builder: (_) => target));
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
    );
  }

  // 파티 탭 전용 좌측 패널 콘텐츠 — _buildCategorySection()은 가로 한 줄
  // Row라 좁은 패널 폭에서 넘칠 수 있어 재사용하지 않고, 같은 상태
  // (_selectedCategories/_categoryTabs)를 그대로 쓰는 Wrap 기반으로 새로 구성한다.
  // 활성 필터 칩(_buildActiveFilterChips)은 원래도 Wrap 기반이라 그대로 재사용.
  Widget _buildPartyQuickFiltersForPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _categoryTabs.map((tab) {
            final selected = tab == _kAllCategoryTab
                ? _isAllCategorySelected
                : _selectedCategories.contains(tab);
            return GestureDetector(
              onTap: () => _toggleCategoryTab(tab),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFFFF6FA0) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: selected
                      ? null
                      : Border.all(color: const Color(0xFFFFE1EC)),
                ),
                child: Text(
                  tab,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            );
          }).toList(),
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
        // 플레이스는 페이지 상단과 동일한 카테고리 칩만으로 필터링하므로
        // 별도 상세검색 버튼이 없다(onOpenDetailSearch: null → 버튼 자체가 숨겨짐).
        // "파티샵" 카테고리가 선택된 동안만 예외적으로 파티샵 전용
        // 상세검색(_shopFilter)을 그대로 노출한다.
        return MainFilterPanel(
          title: _placeShowShopCategory ? '파티샵 필터' : '플레이스 필터',
          quickFilters: _buildEventCategoryChips(),
          onOpenDetailSearch:
              _placeShowShopCategory ? _openShopDetailSearch : null,
          detailFilterActive:
              _placeShowShopCategory ? _shopFilter.isActive : false,
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
        return MainFilterPanel(
          title: '파티 필터',
          quickFilters: _buildPartyQuickFiltersForPanel(),
          onOpenDetailSearch: _openPartyDetailSearch,
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
        return _buildPlaceListContent(
          onCardTap: withPreviewCallback
              ? (data, id) => _selectPreview('place', id, data)
              : null,
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
                _buildPartyCardsColumn(
                  docs,
                  onCardTap: withPreviewCallback
                      ? (data, id) => _selectPreview('party', id, data)
                      : null,
                ),
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
            MaterialPageRoute(builder: (_) => PartyDetailScreen(docId: docId)),
          ),
        );
      case 'place':
        return MainPreviewItem(
          type: type,
          card: _placeGridCard(docId, data),
          onOpenDetail: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PlaceDetailScreen(placeId: docId, data: data),
            ),
          ),
        );
      case 'shop':
        return MainPreviewItem(
          type: type,
          card: _shopCard(docId, data),
          onOpenDetail: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  PartyShopDetailScreen(shopId: docId, shopData: data),
            ),
          ),
        );
      default:
        return null;
    }
  }

  // 태블릿: 좌측 필터 + 가운데 목록 2단. 지도는 아직 넣지 않는다.
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
        ? 'assets/images/header_logo_night.png'
        : 'assets/images/header_logo_last.png';
    final halfAsset = _isNightMode
        ? 'assets/images/header_half_night.png'
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
          // 낮/밤 헤더 배너 토글 — 접기/펼치기 버튼 바로 옆에 위치.
          _buildDayNightToggleButton(),
        ],
      ),
      // 플레이스 탭(index 1)은 상세검색 시트가 없고 페이지 상단 카테고리 칩만으로
      // 필터링하므로, 눌러도 아무 일이 없는 버튼을 보여주지 않는다 — 다만
      // 그 안의 "파티샵" 카테고리에서는 파티샵 전용 상세검색이 있어 예외.
      // 파티 탭(index 0)은 이제 검은 카테고리 바 오른쪽 끝의 튠 버튼이
      // 상세검색 입구 역할을 하므로, 우하단 FAB는 중복이라 숨긴다.
      floatingActionButton:
          (_topTabController.index == 0 ||
              (_topTabController.index == 1 && !_placeShowShopCategory))
          ? null
          : FloatingActionButton.small(
              heroTag: 'fab_filter',
              onPressed: _openDetailSearch,
              backgroundColor: const Color(0xFFFF6FA0),
              elevation: 4,
              child: const Icon(Icons.tune, color: Colors.white, size: 20),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onBottomNavTap,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFFF6FA0),
        unselectedItemColor: Colors.black45,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: '지도'),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_box_outlined),
            label: '등록',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: '채팅',
          ),
          BottomNavigationBarItem(
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
                : (_partyScrollCtrl.hasClients &&
                    _partyScrollCtrl.offset > 8);
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
  Widget _buildDayNightToggleButton() {
    final topInset = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: topInset + 8,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _isNightMode = !_isNightMode),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _isNightMode ? const Color(0xFF1A1A2E) : Colors.white,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              _isNightMode ? Icons.nightlight_round : Icons.wb_sunny_rounded,
              size: 18,
              color: _isNightMode
                  ? const Color(0xFFFFD54F)
                  : const Color(0xFFFF6FA0),
            ),
          ),
        ),
      ),
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
        labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
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
                Text('파티츄'),
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

  // ── 검색창 ───────────────────────────────────────────────────────
  // 검색 팝업(_openSearchPopup) 안에서만 쓰인다. onSubmitted/onChangedExtra는
  // 팝업이 자기 자신(StatefulBuilder)을 다시 그리고, 엔터 입력 시 팝업을
  // 닫을 수 있도록 넘기는 선택적 훅이다 — 검색어 상태(_searchQuery)와 실제
  // 검색 로직은 기존 그대로 이 메서드 안에서 처리한다.
  Widget _buildSearchBar({
    VoidCallback? onSubmitted,
    VoidCallback? onChangedExtra,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1AFF6FA0),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: (val) {
          setState(() => _searchQuery = val.trim());
          onChangedExtra?.call();
        },
        onSubmitted: (_) => onSubmitted?.call(),
        decoration: InputDecoration(
          icon: const Icon(Icons.search, color: Color(0xFFFF6FA0)),
          hintText: '파티 제목, 장소, 키워드 검색',
          border: InputBorder.none,
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.clear,
                    size: 18,
                    color: Colors.black38,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                    onChangedExtra?.call();
                  },
                )
              : null,
        ),
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
          // "파티 목록" 제목 + 검색·보기방식·정렬·전체숨김 — "전체 숨김"이
          // 켜지면 이 줄 자체가 부드럽게 접힌다.
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _headerFullyHidden
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: _buildPartyListHeaderRow(docs),
                  ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _partyScrollCtrl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 날짜 필터 + 상세검색 + 활성 필터 칩 — "전체 숨김"이면
                  // 통째로 접혀 카드 목록이 그만큼 위로 올라온다.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: _headerFullyHidden
                        ? const SizedBox(width: double.infinity)
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  4,
                                ),
                                child: _buildCategorySection(),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: _buildActiveFilterChips(),
                              ),
                            ],
                          ),
                  ),
                  // 파티 목록
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: _buildPartyCardsColumn(docs),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  // "파티 목록" 제목 + 전역 음소거 + 검색 아이콘 + 보기 방식 아이콘 — 세 가지
  // 보기 방식 렌더링 분기(_buildPartyPage, _buildListPanelForCurrentTab)
  // 모두에서 공유한다. 정렬은 더 이상 여기 버튼이 아니라 상세검색 시트의
  // "정렬" 아코디언에서 고른다. 검색창을 상시 노출하지
  // 않으므로, 돋보기 버튼을 눌러야 검색 팝업이 열린다(_openSearchPopup).
  // 헤더 접기/펼치기는 _buildHeaderToggleButton(화면 좌상단 고정)로만
  // 제어하므로 여기엔 없다. 음소거 버튼은 기본/작은 카드(이 화면)에만 두고,
  // 큰 카드·지도는 별도로 배치한다(전역 오버레이는 쓰지 않기로 함).
  Widget _buildPartyListHeaderRow(List<QueryDocumentSnapshot> docs) {
    // 왼쪽(제목 그룹)과 오른쪽(버튼 그룹)을 spaceBetween으로 양 끝에
    // 붙인다 — 예전처럼 Spacer로 오른쪽 버튼들을 어중간하게 띄우지 않고,
    // 두 버튼을 오른쪽 SafeArea 끝에 딱 붙여 iOS/토스 스타일로 정렬한다.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Flexible(
                child: Text(
                  '파티 목록',
                  style: TextStyle(
                    fontFamily: 'SeoulHangang',
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    shadows: [
                      Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                      Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                      Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                      Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
            _PartyListHeaderIconButton(
              icon: _viewModeIcon(_viewMode),
              tooltip: '보기 방식',
              onTap: () => _showViewModeSheet(docs),
            ),
            const SizedBox(width: 8),
            _PartyListHeaderIconButton(
              icon: Icons.search_rounded,
              tooltip: '검색',
              onTap: _openSearchPopup,
            ),
          ],
        ),
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
        final docs = _searchQuery.isNotEmpty
            ? _applySearchSort(filtered)
            : _applySortMode(filtered);
        debugPrint(
          '[MainList] 필터/정렬 후 문서 수: ${docs.length} '
          '(카테고리: ${_selectedCategories.isEmpty ? '전체' : _selectedCategories.join(', ')}, '
          '정렬: ${_filter.sortMode.label})',
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
      MaterialPageRoute(
        builder: (_) => PartyVideoFeedScreen(
          docs: docs,
          initialIndex: index,
          filter: _filter,
          partyDates: _partyDates,
        ),
      ),
    );
    if (result == null || !mounted) return;
    // 전체화면 안에서 상세검색으로 필터를 바꾼 경우 — 필터를 반영하고, 다음
    // 목록 갱신 때 새로 걸러진 문서로 전체화면을 자동으로 다시 띄운다
    // (앱을 영상 모드로 종료했다가 재실행할 때와 동일한 경로 재사용).
    if (result.filter != null) {
      setState(() {
        _filter = result.filter!;
        _pendingAutoOpenVideoFeed = true;
      });
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

  // 검색/필터 결과 0건 안내 — 상단 헤더·검색창·카테고리·필터칩은 그대로 둔
  // 채(_buildPartyStreamResolved가 더 이상 이 자리에서 화면을 통째로 대체하지
  // 않는다) 목록이 놓일 자리에만 이 위젯을 보여준다. 활성 조건이 하나라도
  // 있으면 한 번에 초기화할 수 있는 버튼을 함께 제공해 "화면에 갇힌" 느낌을
  // 없앤다.
  Widget _buildEmptyFilterResult() {
    final hasActiveQuery =
        _searchQuery.isNotEmpty ||
        _selectedCategories.isNotEmpty ||
        _filter.isActive;
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
      for (final t in _selectedCategories) {
        _categoryRingCtrls[t]?.reverse();
      }
      _selectedCategories.clear();
      _categoryRingCtrls[_kAllCategoryTab]?.forward(from: 0);
      _filter = PartyFilter();
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
            child: TabBar(
              labelColor: const Color(0xFFFF6FA0),
              unselectedLabelColor: Colors.black45,
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              indicatorColor: const Color(0xFFFF6FA0),
              indicatorWeight: 2.5,
              dividerColor: const Color(0xFFFFE4ED),
              tabs: const [
                Tab(text: '구인'),
                Tab(text: '구직'),
              ],
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
            final aTime = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            final bTime = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
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
        final docs = _applyCrewFilter(allDocs);
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
    final recruitType = d['recruitType'] as String? ?? '항시';
    final title = d['title'] as String? ?? '';
    final role = d['role'] as String? ?? '';
    final hostName = d['hostName'] as String? ?? '';
    // regions(List) 우선, 구버전 region(String) 폴백
    final regionsRaw = d['regions'];
    final region = (regionsRaw is List && regionsRaw.isNotEmpty)
        ? regionsRaw.cast<String>().join(' · ')
        : (d['region'] as String? ?? '');
    final payType = d['payType'] as String? ?? '협의';
    final payAmount = (d['payAmount'] as num?)?.toInt() ?? 0;
    final startTime = d['startTime'] as String?;
    final endTime = d['endTime'] as String?;
    final isHiring = crewType == '구인';

    // 모집 기간 라벨
    String periodLabel;
    if (recruitType == '날짜지정') {
      final start = (d['startDate'] as Timestamp?)?.toDate();
      final end = (d['endDate'] as Timestamp?)?.toDate();
      String fmtDt(DateTime dt) =>
          '${dt.month}.${dt.day.toString().padLeft(2, '0')}';
      if (start != null && end != null) {
        periodLabel = '${fmtDt(start)} ~ ${fmtDt(end)}';
      } else if (start != null) {
        periodLabel = '${fmtDt(start)} ~';
      } else {
        periodLabel = '날짜 지정';
      }
    } else {
      periodLabel = '항시 ${isHiring ? '모집' : '구직'}';
    }

    // 시간 라벨 (HH:MM → 오전/오후 표시)
    String fmtTimeStr(String t) {
      final parts = t.split(':');
      if (parts.length != 2) return t;
      final h = int.tryParse(parts[0]) ?? 0;
      final m = parts[1];
      if (h == 0) return '오전 12:$m';
      if (h < 12) return '오전 $h:$m';
      if (h == 12) return '오후 12:$m';
      return '오후 ${h - 12}:$m';
    }

    final hasTime = startTime != null;
    final timeLabel = hasTime
        ? (endTime != null
              ? '${fmtTimeStr(startTime)} ~ ${fmtTimeStr(endTime)}'
              : fmtTimeStr(startTime))
        : null;

    // 급여 라벨
    String payLabel;
    if (payType == '협의') {
      payLabel = '급여 협의';
    } else {
      payLabel = payAmount > 0 ? '$payType ${formatAmount(payAmount)}' : payType;
    }

    return Container(
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
      child: Column(
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
              const Spacer(),
              Text(
                hostName,
                style: const TextStyle(fontSize: 11, color: Colors.black38),
              ),
              // 파티크루는 별도 상세화면이 없어 카드 자체에 찜 버튼을 둔다.
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
        final docs = _applyShopFilter(allDocs);
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
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            return _shopCard(
              doc.id,
              data,
              onTap: onCardTap != null ? () => onCardTap(data, doc.id) : null,
            );
          },
        );
      },
    );
  }

  Widget _shopCard(
    String shopId,
    Map<String, dynamic> d, {
    VoidCallback? onTap,
  }) {
    final name = d['name'] as String? ?? '';
    final rawLocation = d['location'] as String? ?? '';
    final location = rawLocation.isEmpty
        ? ''
        : RegionData.shortDistrictDong(rawLocation);
    final hasCoupon = d['hasCoupon'] as bool? ?? false;
    final deliveryOpts = (d['deliveryOptions'] as List?)?.cast<String>() ?? [];
    final mainImgUrl = d['mainImageUrl'] as String? ?? '';

    return GestureDetector(
      onTap:
          onTap ??
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  PartyShopDetailScreen(shopId: shopId, shopData: d),
            ),
          ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 대표 이미지
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: mainImgUrl.isNotEmpty
                      ? Image.network(
                          mainImgUrl,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, e, st) => Container(
                            height: 160,
                            color: const Color(0xFFFFE0EE),
                          ),
                        )
                      : Container(
                          height: 120,
                          color: const Color(0xFFFFE0EE),
                          child: const Center(
                            child: Icon(
                              Icons.store_outlined,
                              size: 48,
                              color: Color(0xFFFF6FA0),
                            ),
                          ),
                        ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: FavoriteStarButton(
                    itemType: FavoriteType.shop,
                    itemId: shopId,
                    size: 20,
                    dense: true,
                    unfavoritedColor: Colors.white,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 뱃지 행
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      // 앱결제 뱃지
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F0FE),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.credit_card_outlined,
                              size: 10,
                              color: Color(0xFF1A73E8),
                            ),
                            SizedBox(width: 3),
                            Text(
                              '앱결제',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A73E8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (deliveryOpts.contains('sameDay'))
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.flash_on,
                                size: 10,
                                color: Color(0xFFE06B00),
                              ),
                              SizedBox(width: 2),
                              Text(
                                '당일 퀵',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFE06B00),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (hasCoupon)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF9E6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.local_offer_outlined,
                                size: 11,
                                color: Color(0xFFE89200),
                              ),
                              SizedBox(width: 3),
                              Text(
                                '방문쿠폰',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFE89200),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 샵 이름
                  Text(
                    name,
                    style: const TextStyle(
                      fontFamily: 'SeoulHangang',
                      fontSize: 16,
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
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 13,
                          color: Colors.black38,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            location,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black45,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  // 배송 옵션 칩
                  if (deliveryOpts.isNotEmpty)
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: deliveryOpts.map((k) {
                        const labels = {
                          'sameDay': '당일퀵',
                          'pickup': '방문수령',
                          'delivery': '택배',
                          'scheduled': '지정일',
                        };
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF0F5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            labels[k] ?? k,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFF6FA0),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 플레이스 탭 ────────────────────────────────────────────────────────
  // 상세검색 시트 없이 상단 카테고리 칩만으로 필터링한다(_eventCategoryFilter).
  Widget _buildEventPage() {
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
      stream: FirebaseFirestore.instance
          .collection('events')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .snapshots(),
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
        final allDocs = snap.data?.docs ?? [];
        final docs = _eventThemeFilter.isEmpty
            ? allDocs
            : allDocs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                final tags = _placeThemeTags(data);
                return _eventThemeFilter.any(tags.contains);
              }).toList();

        if (allDocs.isEmpty) {
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
        if (docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                '선택한 카테고리의 플레이스가 없어요.',
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
            return _eventCard(doc.id, data);
          },
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

  // 파티샵 카테고리를 가리키는 값 — placeThemeTags(핫플/이벤트/알바생
  // 훈남훈녀/혼술바)와 절대 겹치지 않는 전용 식별자다.
  static const String _shopCategoryValue = '__party_shop_category__';

  // 게임 UI/네온 스타일 커스텀 탭바(PlaceCategoryNavBar)로 렌더링만
  // 위임하고, 선택 판정과 탭 시 상태 변경(다중 선택 OR 매칭, 파티샵과의
  // 배타 선택)은 기존 로직 그대로 여기서 처리한다.
  Widget _buildEventCategoryChips() {
    final items = <PlaceCategoryNavItem>[
      const PlaceCategoryNavItem(label: '전체'),
      for (final c in ListingConstants.placeThemeTags)
        PlaceCategoryNavItem(
          value: c,
          emoji: ListingConstants.placeThemeTagEmojis[c],
          label: c,
        ),
      const PlaceCategoryNavItem(
        value: _shopCategoryValue,
        emoji: '🛍️',
        label: '파티샵',
      ),
    ];
    return PlaceCategoryNavBar(
      items: items,
      isSelected: (item) {
        if (item.value == _shopCategoryValue) return _placeShowShopCategory;
        if (_placeShowShopCategory) return false;
        return item.value == null
            ? _eventThemeFilter.isEmpty
            : _eventThemeFilter.contains(item.value);
      },
      onSelect: (item) => setState(() {
        if (item.value == _shopCategoryValue) {
          _placeShowShopCategory = true;
          _eventThemeFilter.clear();
          return;
        }
        _placeShowShopCategory = false;
        if (item.value == null) {
          _eventThemeFilter.clear();
        } else if (_eventThemeFilter.contains(item.value)) {
          _eventThemeFilter.remove(item.value);
        } else {
          _eventThemeFilter.add(item.value!);
        }
      }),
    );
  }

  // "HH:mm" 저장 문자열 → "오전/오후 h:mm ~ 오전/오후 h:mm" 표시용
  String? _eventTimeRangeLabel(Map<String, dynamic> d) {
    if (d['hasTimeRange'] != true) return null;
    final start = d['startTime'] as String?;
    final end = d['endTime'] as String?;
    if (start == null || end == null) return null;
    String fmt(String hhmm) {
      final p = hhmm.split(':');
      final h = int.tryParse(p[0]) ?? 0;
      final m = p.length > 1 ? p[1] : '00';
      if (h == 0) return '오전 12:$m';
      if (h < 12) return '오전 $h:$m';
      if (h == 12) return '오후 12:$m';
      return '오후 ${h - 12}:$m';
    }
    return '${fmt(start)} ~ ${fmt(end)}';
  }

  Widget _eventCard(String eventId, Map<String, dynamic> d) {
    final name = d['name'] as String? ?? '';
    final rawLocation = d['location'] as String? ?? '';
    final location = rawLocation.isEmpty
        ? ''
        : RegionData.shortDistrictDong(rawLocation);
    final themeTags = _placeThemeTags(d);
    final mainImgUrl = d['mainImageUrl'] as String? ?? '';
    final isOngoing = d['isOngoing'] as bool? ?? true;
    final timeRangeLabel = _eventTimeRangeLabel(d);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EventDetailScreen(eventId: eventId, eventData: d),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Color(0x0FFF6FA0), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: mainImgUrl.isNotEmpty
                      ? Image.network(
                          mainImgUrl,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, e, st) =>
                              Container(height: 160, color: const Color(0xFFFFE0EE)),
                        )
                      : Container(
                          height: 120,
                          color: const Color(0xFFFFE0EE),
                          child: const Center(
                            child: Icon(Icons.celebration_outlined,
                                size: 48, color: Color(0xFFFF6FA0)),
                          ),
                        ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: FavoriteStarButton(
                    itemType: FavoriteType.event,
                    itemId: eventId,
                    size: 20,
                    dense: true,
                    unfavoritedColor: Colors.white,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final tag in themeTags)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF0F5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${ListingConstants.placeThemeTagEmojis[tag] ?? ''} $tag',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFFF6FA0),
                            ),
                          ),
                        ),
                      if (isOngoing)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            '상시 진행',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    name,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 13, color: Colors.black38),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            location,
                            style: const TextStyle(fontSize: 12, color: Colors.black45),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (timeRangeLabel != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.access_time_outlined,
                            size: 13, color: Colors.black38),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            timeRangeLabel,
                            style: const TextStyle(fontSize: 12, color: Colors.black45),
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
          ],
        ),
      ),
    );
  }

  // ── 장소대여 탭 ──────────────────────────────────────────────────────
  Widget _buildPlacePage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 지역 필터 (고정 상단)
        _buildPlaceFilter(),
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
      stream: FirebaseFirestore.instance.collection('places').snapshots(),
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
        final visibleDocs = (snap.data?.docs ?? [])
            .where((d) => (d.data() as Map<String, dynamic>)['isActive'] != false)
            .toList()
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
        final allDocs = visibleDocs;
        final docs = _applyPlaceFilter(allDocs);

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

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text('🔍', style: TextStyle(fontSize: 48)),
                  SizedBox(height: 16),
                  Text(
                    '선택한 지역에 등록된 장소가 없어요.',
                    style: TextStyle(fontSize: 14, color: Colors.black45),
                  ),
                ],
              ),
            ),
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
                    child: _placeGridCard(
                      leftDoc.id,
                      leftData,
                      onTap: onCardTap != null
                          ? () => onCardTap(leftData, leftDoc.id)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: rightDoc != null
                        ? _placeGridCard(
                            rightDoc.id,
                            rightData!,
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

  // ── 장소 지역 필터 UI (단일 버튼 → 바텀시트) ─────────────────────
  // 장소대여 지역 필터 — 시/도 하나를 통째로 고를 수 있는 "전체"까지 포함해
  // 최대 5개까지 중복 선택 가능하다.
  static const _kMaxPlaceDistricts = 5;

  // "서울 강남구" → "강남구", "전체"로 고른 시/도 하나만 있는 값(예: "서울")은
  // 그대로 두면 구/군 이름과 헷갈리니 "서울 전체"처럼 보여준다.
  String _placeDistrictLabel(String d) {
    final parts = d.split(' ');
    return parts.length == 2 ? parts[1] : '$d 전체';
  }

  Widget _placeRegionChip(String label, bool sel, bool maxed) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: sel
            ? const Color(0xFFFF6FA0)
            : maxed
            ? const Color(0xFFF5F5F7)
            : const Color(0xFFFFF0F5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: sel
              ? const Color(0xFFFF6FA0)
              : maxed
              ? const Color(0xFFE8EBF2)
              : const Color(0xFFFFD6E4),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: sel
              ? Colors.white
              : maxed
              ? Colors.black26
              : const Color(0xFFFF6FA0),
        ),
      ),
    );
  }

  Widget _buildPlaceFilter() {
    final hasFilter = _placeFilterDistricts.isNotEmpty;

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(
              children: [
                // 지역선택 버튼
                GestureDetector(
                  onTap: _showPlaceRegionSheet,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
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
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: hasFilter ? Colors.white : Colors.black54,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          hasFilter
                              ? '지역선택 (${_placeFilterDistricts.length})'
                              : '지역선택',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: hasFilter ? Colors.white : Colors.black54,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: hasFilter ? Colors.white : Colors.black45,
                        ),
                      ],
                    ),
                  ),
                ),
                // 선택된 지역 칩 (가로 스크롤)
                if (hasFilter) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 34,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: _placeFilterDistricts.map((d) {
                          final label = _placeDistrictLabel(d);
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: GestureDetector(
                              onTap: () => setState(
                                () => _placeFilterDistricts.remove(d),
                              ),
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
                                    Text(
                                      label,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFFF6FA0),
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
                  // 초기화
                  GestureDetector(
                    onTap: () => setState(() => _placeFilterDistricts.clear()),
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
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
        ],
      ),
    );
  }

  // ── 전국 지역 선택 바텀시트 ──────────────────────────────────────
  void _showPlaceRegionSheet() {
    String sheetCity = RegionData.regionDistricts.keys.first;
    final tempSelected = Set<String>.from(_placeFilterDistricts);

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
                          Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                          Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                          Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
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
                    '중복 $_kMaxPlaceDistricts개까지 가능',
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
                const Divider(height: 1, color: Color(0xFFF0F0F0)),
              ],
              // 시/도 탭 (가로 스크롤)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: RegionData.regionDistricts.keys.map((city) {
                    final isActive = sheetCity == city;
                    final hasInCity = tempSelected.any(
                      (s) => s.startsWith('$city '),
                    );
                    return GestureDetector(
                      onTap: () => setSheet(() => sheetCity = city),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFFFF6FA0)
                              : hasInCity
                              ? const Color(0xFFFFE8F2)
                              : const Color(0xFFF5F5F7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          city,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isActive
                                ? Colors.white
                                : hasInCity
                                ? const Color(0xFFFF6FA0)
                                : Colors.black54,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFF0F0F0)),
              // 구/시/군 칩 목록 — 맨 앞의 "전체" 칩으로 시/도 하나를 통째로
              // 고를 수 있다. "전체"를 고르면 같은 시/도의 개별 구/군 선택은
              // 자동으로 정리되고, 반대로 개별 구/군을 고르면 그 시/도의
              // "전체"는 해제된다 — 같은 시/도 안에 "전체"와 개별 선택이
              // 동시에 남아 있는 어색한 상태를 막기 위함이다.
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Builder(
                        builder: (_) {
                          final sel = tempSelected.contains(sheetCity);
                          final maxed =
                              !sel && tempSelected.length >= _kMaxPlaceDistricts;
                          return GestureDetector(
                            onTap: maxed
                                ? null
                                : () => setSheet(() {
                                    if (sel) {
                                      tempSelected.remove(sheetCity);
                                    } else {
                                      tempSelected.removeWhere(
                                        (s) => s.startsWith('$sheetCity '),
                                      );
                                      tempSelected.add(sheetCity);
                                    }
                                  }),
                            child: _placeRegionChip('전체', sel, maxed),
                          );
                        },
                      ),
                      ...(RegionData.regionDistricts[sheetCity] ?? []).map(
                        (d) {
                          final key = '$sheetCity $d';
                          final sel = tempSelected.contains(key);
                          final maxed =
                              !sel && tempSelected.length >= _kMaxPlaceDistricts;
                          return GestureDetector(
                            onTap: maxed
                                ? null
                                : () => setSheet(() {
                                    if (sel) {
                                      tempSelected.remove(key);
                                    } else {
                                      tempSelected.remove(sheetCity);
                                      tempSelected.add(key);
                                    }
                                  }),
                            child: _placeRegionChip(d, sel, maxed),
                          );
                        },
                      ),
                    ],
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
                          _placeFilterDistricts.clear();
                          _placeFilterDistricts.addAll(tempSelected);
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
                        tempSelected.isEmpty
                            ? '지역 선택 안 함'
                            : '${tempSelected.length}개 지역 보기',
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

  // ── 지역(구/시/군) 빠른 필터 + 장소대여 상세검색 필터 적용 ─────────
  List<QueryDocumentSnapshot> _applyPlaceFilter(
    List<QueryDocumentSnapshot> docs,
  ) {
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

      // 상단 퀵 지역(구/시/군) 필터
      if (_placeFilterDistricts.isNotEmpty) {
        final address = (data['address'] as String? ?? '').toLowerCase();
        // 선택값 형식: "서울 강남구" → 구/시/군 부분만 주소에서 검색
        final matched = _placeFilterDistricts.any((selection) {
          final parts = selection.split(' ');
          final district = parts.length == 2 ? parts[1] : selection;
          return address.contains(district.toLowerCase());
        });
        if (!matched) return false;
      }

      return _matchesPlaceDetailFilter(data, _placeFilter);
    }).toList();
  }

  bool _matchesPlaceDetailFilter(
    Map<String, dynamic> data,
    PlaceFilter filter,
  ) {
    if (filter.regions.isNotEmpty) {
      final address = (data['address'] as String? ?? '');
      if (!filter.regions.any((r) => address.contains(r))) return false;
    }
    if (filter.placeTypes.isNotEmpty) {
      final type = data['type'] as String? ?? '';
      if (!filter.placeTypes.contains(type)) return false;
    }
    if (filter.facilities.isNotEmpty) {
      final facilities =
          (data['commonFacilities'] as List?)?.cast<String>() ?? [];
      if (!filter.facilities.any((f) => facilities.contains(f))) return false;
    }
    if (filter.priceRanges.isNotEmpty) {
      final price = (data['pricePerHour'] as num?)?.toInt() ?? 0;
      if (!filter.priceRanges.any((r) => _matchesPlacePriceRange(price, r)))
        return false;
    }
    if (filter.capacityRanges.isNotEmpty) {
      final capacity = (data['capacityMax'] as num?)?.toInt() ?? 0;
      if (!filter.capacityRanges.any(
        (r) => _matchesPlaceCapacityRange(capacity, r),
      ))
        return false;
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
    if (!_shopFilter.isActive) return docs;
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

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
    if (!_crewFilter.isActive) return docs;
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

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

  // ── 장소 그리드 카드 (2열) ────────────────────────────────────────
  Widget _placeGridCard(
    String id,
    Map<String, dynamic> data, {
    VoidCallback? onTap,
  }) {
    // 대표 미디어 — 등록자가 직접 고른 사진/동영상(coverMediaType)을 최우선으로
    // 쓰고, 없으면(과거 데이터) imageUrls.first로 하위호환 폴백한다. 동영상이
    // 대표면 다른 카드와 동일한 VideoThumbnail로 재생한다(2열 그리드라 작은
    // 카드처럼 화면에 보이는 것만으로 자동재생하지 않고 탭했을 때만 재생).
    final cover = getPartyCoverMedia(data, tag: 'PlaceGridCard');
    final thumbnailUrl = cover?.thumbnailUrl;
    final isVideoOnly = cover?.isVideo ?? false;
    final videoUrl = cover?.videoUrl;
    final pricePerHour = (data['pricePerHour'] as num?)?.toInt() ?? 0;
    // 파티 기본카드(PartyStandardCard)와 동일하게 목록 카드에는 12자까지만
    // 노출 — 전체 이름은 상세페이지에서 확인한다.
    final name = truncatePartyTitleForCard(data['name'] as String? ?? '장소');
    final address = data['address'] as String? ?? '';
    final type = data['type'] as String? ?? '';

    // 목록 카드는 상세주소 없이 "구+동"만 — 상세페이지에서만 전체 주소를 보여준다.
    final shortAddress = address.isEmpty
        ? ''
        : RegionData.shortDistrictDong(address);

    return GestureDetector(
      onTap:
          onTap ??
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PlaceDetailScreen(placeId: id, data: data),
            ),
          ),
      child: Container(
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 사진/동영상
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: SizedBox(
                height: 130,
                width: double.infinity,
                child: (isVideoOnly && videoUrl != null && videoUrl.isNotEmpty)
                    ? VideoThumbnail(
                        videoUrl: videoUrl,
                        thumbnailUrl: thumbnailUrl,
                        autoplayOnVisible: false,
                        cropX: cover?.videoCropX ?? 0.5,
                        cropY: cover?.videoCropY ?? 0.5,
                        cropScale: cover?.videoCropScale ?? 1.0,
                      )
                    : thumbnailUrl != null && thumbnailUrl.isNotEmpty
                    ? Image.network(
                        thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, e, st) =>
                            Container(color: const Color(0xFFFFE0EE)),
                      )
                    : Container(
                        color: const Color(0xFFFFE0EE),
                        child: const Center(
                          child: Icon(
                            Icons.home_outlined,
                            size: 36,
                            color: Color(0xFFFF6FA0),
                          ),
                        ),
                      ),
              ),
            ),
            // 정보
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 유형 뱃지 (+ 숙박+파티 콤보 배지)
                  if (type.isNotEmpty || data['isCombo'] == true) ...[
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (type.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0F5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              type,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFF6FA0),
                              ),
                            ),
                          ),
                        if (data['isCombo'] == true) PartyCard.comboBadge(),
                      ],
                    ),
                    const SizedBox(height: 5),
                  ],
                  // 장소명
                  Text(
                    name,
                    style: const TextStyle(
                      fontFamily: 'SeoulHangang',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      shadows: [
                        Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                        Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                        Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                        Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // 주소
                  if (shortAddress.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      shortAddress,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black45,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  // 가격 — 파티 참가비와 동일하게 로그인해야만 노출한다.
                  Text(
                    UserSession.isLoggedIn
                        ? '${formatPrice(pricePerHour)} / 시간'
                        : '🔒 로그인 필요',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF6FA0),
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

  // ── 파티 탭: 카테고리 / 필터 / 카드 ──────────────────────────────
  // 블랙 네온 바 스타일 — 동그란 핑크/화이트 필터 버튼들을 하나의 긴
  // 다크 글래스 바로 통합했다. 날짜 탭은 중복 선택 가능(_selectedCategories,
  // OR 매칭)하고, 선택된 항목마다 버튼을 감싸지 않는 작은 손그림 낙서
  // 스티커(_HandDrawnDoodlePainter)가 모서리 바깥에 붙는다. 탭 시 상태
  // 변경과 상세검색 진입(_openDetailSearch)은 기존 로직 그대로이고
  // 겉모습만 바뀐다.
  static const Color _kNeonBarPink = Color(0xFFFF5FA8);

  Widget _buildCategorySection() {
    const barHeight = 42.0;
    final children = <Widget>[];
    for (int i = 0; i < _categoryTabs.length; i++) {
      final tab = _categoryTabs[i];
      if (i > 0) children.add(_buildNeonBarDivider());
      children.add(Expanded(child: _buildDateCategoryTab(tab)));
    }
    children.add(_buildNeonBarDivider());
    children.add(
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openDetailSearch,
        child: SizedBox(
          width: 38,
          height: barHeight,
          child: Icon(
            // 돋보기(텍스트 검색) 아이콘이 아니라, 상세검색 진입점임을
            // 나타내는 튠(필터) 아이콘 — 하단 FAB와 같은 아이콘 언어로
            // 통일한다(파티 탭은 이제 이 자리 하나만 상세검색 입구).
            Icons.tune_rounded,
            size: 18,
            color: _filter.isActive
                ? _kNeonBarPink
                : Colors.white.withValues(alpha: 0.65),
          ),
        ),
      ),
    );

    return Container(
      height: barHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(barHeight / 2),
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
  }

  // 날짜 탭(오늘/내일/이번 주/이번 주말)은 서로 독립적으로 중복 선택되고,
  // '전체'만 예외적으로 배타 선택이다 — '전체'를 누르면 나머지가 전부
  // 꺼지고, 나머지 중 하나라도 켜져 있으면 '전체'는 자동으로 꺼진다(반대로
  // 나머지를 전부 꺼서 Set이 비면 '전체'가 다시 자동으로 켜진다). 이 배타
  // 관계 계산은 여기 한 곳에서만 하고, 모바일 바/데스크톱 패널이 모두
  // 이 메서드를 공유한다.
  void _toggleCategoryTab(String tab) {
    setState(() {
      if (tab == _kAllCategoryTab) {
        if (_selectedCategories.isEmpty) return;
        for (final t in _selectedCategories) {
          _categoryRingCtrls[t]?.reverse();
        }
        _selectedCategories.clear();
        _categoryRingCtrls[_kAllCategoryTab]?.forward(from: 0);
        return;
      }
      final wasAllSelected = _selectedCategories.isEmpty;
      if (_selectedCategories.contains(tab)) {
        _selectedCategories.remove(tab);
        _categoryRingCtrls[tab]?.reverse();
        if (_selectedCategories.isEmpty) {
          _categoryRingCtrls[_kAllCategoryTab]?.forward(from: 0);
        }
      } else {
        if (wasAllSelected) {
          _categoryRingCtrls[_kAllCategoryTab]?.reverse();
        }
        _selectedCategories.add(tab);
        _categoryRingCtrls[tab]?.forward(from: 0);
      }
    });
  }

  // 날짜 탭 하나 — 탭하면 _toggleCategoryTab이 선택 상태를 바꾸고, 텍스트를
  // 감싸는 부드러운 손그림 원(_HandDrawnCirclePainter, 크게 삐뚤지 않고
  // 번짐 없이 또렷한 선)과 모서리 바깥의 작은 낙서 포인트가 함께 그려지는/
  // 지워지는 모션으로 나타났다 사라진다.
  Widget _buildDateCategoryTab(String tab) {
    final ctrl = _categoryRingCtrls[tab]!;
    final kind = _doodleKindForTab(tab);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleCategoryTab(tab),
      child: Center(
        child: AnimatedBuilder(
          animation: ctrl,
          builder: (context, _) {
            final selected = tab == _kAllCategoryTab
                ? _isAllCategorySelected
                : _selectedCategories.contains(tab);
            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  painter: ctrl.value > 0
                      ? _HandDrawnCirclePainter(
                          progress: ctrl.value,
                          seed: tab.hashCode,
                        )
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 9,
                    ),
                    // '이번 주말'처럼 긴 라벨이 좁은 셀 폭에서 두 줄로
                    // 줄바꿈되던 문제 — FittedBox로 한 줄을 유지한 채
                    // 필요할 때만 살짝 축소해서 항상 한 줄로 보이게 한다.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        tab,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.55),
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                if (ctrl.value > 0)
                  _buildCategoryDoodleOverlay(kind, ctrl.value, tab.hashCode),
              ],
            );
          },
        ),
      ),
    );
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
            onPressed: () => setState(() => _filter = PartyFilter()),
          ),
        ],
      ),
    );
  }

  // ── 검색 로직 ─────────────────────────────────────────────────────
  // title·description·partyTypes·vibes·tags 모두 검색 대상
  bool _matchesSearch(Map<String, dynamic> data, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase().replaceFirst('#', '');
    if ((data['title'] as String? ?? '').toLowerCase().contains(q)) return true;
    if ((data['description'] as String? ?? '').toLowerCase().contains(q))
      return true;
    final types = (data['partyTypes'] as List?)?.cast<String>() ?? [];
    if (types.any((t) => t.toLowerCase().contains(q))) return true;
    final vibes = (data['vibes'] as List?)?.cast<String>() ?? [];
    if (vibes.any((v) => v.toLowerCase().contains(q))) return true;
    final tags = (data['tags'] as List?)?.cast<String>() ?? [];
    if (tags.any((t) => t.toLowerCase().contains(q))) return true;
    return false;
  }

  // 검색 중일 때: 제목(0) → 유형/분위기(1) → 태그/설명(2) 우선순위 정렬
  List<QueryDocumentSnapshot> _applySearchSort(
    List<QueryDocumentSnapshot> docs,
  ) {
    if (_searchQuery.isEmpty) return docs;
    final q = _searchQuery.toLowerCase().replaceFirst('#', '');
    return List.of(docs)..sort(
      (a, b) => _searchPriority(
        a.data() as Map<String, dynamic>,
        q,
      ).compareTo(_searchPriority(b.data() as Map<String, dynamic>, q)),
    );
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
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime? _parsePartyDateTime(Map<String, dynamic> data) {
    final ts = data['partyDateTime'];
    if (ts is Timestamp) return ts.toDate().toLocal();
    final sdt = data['startDateTime'];
    if (sdt is Timestamp) return sdt.toDate().toLocal();
    if (sdt is String && sdt.isNotEmpty)
      return DateTime.tryParse(sdt)?.toLocal();
    final dateStr = data['date'] as String?;
    if (dateStr != null && dateStr.isNotEmpty)
      return DateTime.tryParse(dateStr)?.toLocal();
    return null;
  }

  // 날짜 카테고리는 복수 선택이 가능하다 — 아무것도 선택하지 않았으면
  // "전체"(모든 파티 통과), 하나 이상 선택했으면 그 중 하나라도 맞으면
  // 통과시키는 OR 매칭이다.
  bool _matchesCategoryTabs(Map<String, dynamic> data, Set<String> tabs) {
    if (tabs.isEmpty) return true;
    return tabs.any((tab) => _matchesSingleCategoryTab(data, tab));
  }

  bool _matchesSingleCategoryTab(Map<String, dynamic> data, String tab) {
    final partyDateTime = _parsePartyDateTime(data);
    if (partyDateTime == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: now.weekday - 1));
    final partyDay = DateTime(
      partyDateTime.year,
      partyDateTime.month,
      partyDateTime.day,
    );
    final saturday = monday.add(const Duration(days: 5));
    final sunday = monday.add(const Duration(days: 6));
    switch (tab) {
      case '오늘':
        return partyDay == today;
      case '내일':
        final tomorrow = today.add(const Duration(days: 1));
        return partyDay == tomorrow;
      case '이번 주':
        // 오늘부터 이번 주 일요일까지
        return !partyDay.isBefore(today) && !partyDay.isAfter(sunday);
      case '이번 주말':
        // 이번 주 토요일 00:00 ~ 일요일 23:59
        return !partyDay.isBefore(saturday) && !partyDay.isAfter(sunday);
      default:
        return true;
    }
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

  bool _matchesDateOption(DateTime partyDateTime, String option, DateTime now) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    switch (option) {
      case '오늘':
        return _isSameDay(partyDateTime, now);
      case '내일':
        return _isSameDay(partyDateTime, now.add(const Duration(days: 1)));
      case '이번주':
        final weekStart = startOfToday.subtract(
          Duration(days: now.weekday - 1),
        );
        final weekEnd = weekStart.add(
          const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
        );
        return !partyDateTime.isBefore(weekStart) &&
            !partyDateTime.isAfter(weekEnd);
      case '이번주말':
        final weekStart = startOfToday.subtract(
          Duration(days: now.weekday - 1),
        );
        final saturday = weekStart.add(const Duration(days: 5));
        final weekendEnd = weekStart.add(
          const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
        );
        return !partyDateTime.isBefore(saturday) &&
            !partyDateTime.isAfter(weekendEnd);
      default:
        return true;
    }
  }

  /// 선택된 구/시/군(district) 중 하나라도 파티의 district와 일치하면 통과.
  /// district 필드가 없는 기존 데이터는 region(시/도) 기준으로 하위호환 매칭한다.
  bool _matchesDistrictFilter(
    Map<String, dynamic> data,
    Set<String> selectedDistricts,
  ) {
    final district = data['district'] as String?;
    if (district != null && district.isNotEmpty) {
      return selectedDistricts.contains(district);
    }
    final region = data['region'] as String? ?? '';
    if (region.isEmpty) return false;
    final legacyRegions = selectedDistricts.expand(
      RegionData.regionsOfDistrict,
    );
    return legacyRegions.contains(region);
  }

  // 연령대(10년 단위) 선택값 중 하나라도 파티의 연령 제한 범위와 겹치면 통과.
  // 파티에 연령 제한이 없으면(ageRestrictionEnabled=false) 모든 연령대에
  // 열려 있는 것으로 간주한다.
  bool _matchesAgeGroups(Map<String, dynamic> data, Set<String> groups) {
    final ageRestrictionEnabled = data['ageRestrictionEnabled'] as bool? ?? false;
    if (!ageRestrictionEnabled) return true;
    final partyMin = (data['minBirthYear'] as num?)?.toInt() ?? -100000000;
    final partyMax = (data['maxBirthYear'] as num?)?.toInt() ?? 100000000;
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

  bool _matchesDetailFilter(Map<String, dynamic> data, PartyFilter filter) {
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
      final maleFee = (data['maleFee'] as num?)?.toInt();
      final femaleFee = (data['femaleFee'] as num?)?.toInt();
      final legacyFee = (data['fee'] as num?)?.toInt() ?? 0;
      final fee = [maleFee, femaleFee].whereType<int>().fold(
        legacyFee,
        (a, b) => a == 0 ? b : (b < a ? b : a),
      );
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
      if (PartyCard.effectiveStatus(data) != '모집중') return false;
      final elig = checkPartyEligibility(
        data,
        UserSession.gender,
        UserSession.birthYear,
      );
      if (elig != PartyEligibility.eligible) return false;
    }
    if (filter.earlyBirdOnly && !EarlyBird.isActive(data)) return false;
    if (filter.dateOptions.isNotEmpty) {
      final partyDateTime = _parsePartyDateTime(data);
      if (partyDateTime == null) return false;
      final now = DateTime.now();
      if (!filter.dateOptions.any(
        (opt) => _matchesDateOption(partyDateTime, opt, now),
      )) {
        return false;
      }
    }
    // 날짜 직접 선택 + 시간 범위 필터
    if (filter.selectedDate != null) {
      final dt = _parsePartyDateTime(data);
      if (dt == null) return false;
      final partyDay = DateTime(dt.year, dt.month, dt.day);
      final selDay = DateTime(
        filter.selectedDate!.year,
        filter.selectedDate!.month,
        filter.selectedDate!.day,
      );
      if (partyDay != selDay) return false;
      final partyMins = dt.hour * 60 + dt.minute;
      if (filter.startTime != null) {
        final startMins =
            filter.startTime!.hour * 60 + filter.startTime!.minute;
        if (partyMins < startMins) return false;
      }
      if (filter.endTime != null) {
        final endMins = filter.endTime!.hour * 60 + filter.endTime!.minute;
        if (partyMins > endMins) return false;
      }
    }
    // "파티 시작 시간" — 날짜와 무관하게 시간대(00:00~23:59)만 비교한다.
    // Firestore는 Timestamp에서 "시간대만" 뽑아 범위 쿼리할 수 없어(날짜별로
    // 값이 전부 다름) 클라이언트에서 처리한다.
    if (filter.timeOfDayStart != null || filter.timeOfDayEnd != null) {
      final dt = _parsePartyDateTime(data);
      if (dt == null) return false;
      if (!_matchesTimeOfDayRange(
        dt.hour * 60 + dt.minute,
        filter.timeOfDayStart,
        filter.timeOfDayEnd,
      )) {
        return false;
      }
    }
    return true;
  }

  // 시작(있으면)~종료(있으면) 시간대 범위에 partyMins(0~1439)가 포함되는지 확인.
  // "오후 10:00~오전 12:00"처럼 자정을 넘어가는 범위(종료 <= 시작)도 지원한다
  // — 이 경우 종료를 다음날로 간주(+24시간)하고, 파티 시각도 같은 방식으로
  // 다음날 값을 함께 검사해 자정을 걸친 구간을 올바르게 매칭한다.
  bool _matchesTimeOfDayRange(int partyMins, TimeOfDay? start, TimeOfDay? end) {
    if (start == null && end == null) return true;
    final startMins = start != null ? start.hour * 60 + start.minute : 0;
    var endMins = end != null ? end.hour * 60 + end.minute : 1439;
    if (endMins <= startMins) endMins += 1440; // 자정을 넘어가는 범위
    return (partyMins >= startMins && partyMins <= endMins) ||
        (partyMins + 1440 >= startMins && partyMins + 1440 <= endMins);
  }

  List<QueryDocumentSnapshot> _applyFilters(List<QueryDocumentSnapshot> docs) {
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      if (!PartyCard.isVisibleInList(data)) {
        debugPrint(
          '[MainList] ❌ isVisibleInList=false title="${data['title']}" '
          'isDeleted=${data['isDeleted']} '
          'partyDateTime=${data['partyDateTime']} startDateTime=${data['startDateTime']} date=${data['date']}',
        );
        return false;
      }
      final searchOk = _matchesSearch(data, _searchQuery);
      final categoryOk = _matchesCategoryTabs(data, _selectedCategories);
      final detailOk = _matchesDetailFilter(data, _filter);
      if (!searchOk || !categoryOk || !detailOk) {
        debugPrint(
          '[MainList] ❌ title="${data['title']}" searchOk=$searchOk '
          'categoryOk=$categoryOk detailOk=$detailOk',
        );
      }
      return searchOk && categoryOk && detailOk;
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

// "파티 목록" 헤더 줄 오른쪽의 보기방식/검색 버튼 — 두 버튼의 크기·테두리·
// 배경·아이콘 색을 완전히 동일하게 맞추기 위해 하나의 위젯으로 통일한다.
class _PartyListHeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _PartyListHeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 큰 원형 흰 배경/테두리 없이 아이콘만 보이는 단순한 버튼 — 아이콘
    // 자체는 20px로 다른 헤더 요소들과 비율이 맞는 작은 크기를 쓰고,
    // 터치 영역만 40px로 확보한다(배경 없는 기본 핑크 아이콘 스타일 유지).
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      icon: Icon(icon, size: 20, color: const Color(0xFFFF6FA0)),
    );
  }
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

// 날짜 필터 탭이 선택됐을 때 텍스트를 감싸는, 손으로 그렸지만 심하게
// 삐뚤지는 않은 부드러운 원. 완벽한 정원은 아니되 지터를 아주 약하게만
// 줘서(예전 버전보다 훨씬 매끈하게) 젤리처럼 찌그러져 보이지 않게 하고,
// 번짐(블러) 없이 크리스프한 선으로만 그린다.
//
// CustomPaint(child: paddedText)로 쓰여 캔버스 크기가 곧 텍스트 박스
// 크기이므로, 텍스트를 딱 맞게 감싸는 원이 된다. [progress] 0~1은
// _HandDrawnDoodlePainter와 같은 규칙 — 0~0.72에서 그려지고, 0.85 부근에서
// 반짝임이 한 번 튄 뒤 낮은 세기로 유지된다.
class _HandDrawnCirclePainter extends CustomPainter {
  _HandDrawnCirclePainter({required this.progress, required this.seed});

  final double progress;
  final int seed;

  static const Color _neonPink = Color(0xFFFF5FA8);
  static const Color _neonPurple = Color(0xFFB14EFF);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final rng = Random(seed);
    final cx = size.width / 2, cy = size.height / 2;
    final rx = size.width / 2 + 3;
    final ry = size.height / 2 + 4;
    const pointCount = 10;
    final points = <Offset>[];
    for (int i = 0; i <= pointCount; i++) {
      // 1.05바퀴 — 시작점보다 살짝만 더 돌아 자연스럽게 이어지되 거의
      // 완전히 닫힌 원에 가깝다.
      final angle = (i / pointCount) * pi * 2 * 1.05 - pi / 2;
      final jitterR = 0.95 + rng.nextDouble() * 0.08;
      final wobble = angle + (rng.nextDouble() - 0.5) * 0.05;
      points.add(
        Offset(cx + rx * jitterR * cos(wobble), cy + ry * jitterR * sin(wobble)),
      );
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i == 0 ? 0 : i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[i + 2 < points.length ? i + 2 : points.length - 1];
      final cp1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final cp2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }

    final metric = path.computeMetrics().first;
    final totalLen = metric.length;
    const drawEnd = 0.72;
    final drawT = progress >= drawEnd
        ? 1.0
        : Curves.easeOutCubic.transform((progress / drawEnd).clamp(0.0, 1.0));
    final drawPath = metric.extractPath(0, totalLen * drawT);

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _neonPink.withValues(alpha: 0.4);
    canvas.drawPath(drawPath, outline);

    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Color.lerp(_neonPink, _neonPurple, 0.2)!.withValues(alpha: 1.0);
    canvas.drawPath(drawPath, core);

    final peak = (1 - ((progress - 0.85).abs() / 0.15)).clamp(0.0, 1.0);
    final steady = progress >= 0.97 ? 0.5 : 0.0;
    final sparkOpacity = max(peak, steady);
    if (sparkOpacity > 0) {
      final tangent = metric.getTangentForOffset(totalLen * 0.06);
      if (tangent != null) {
        _drawSpark(canvas, tangent.position, sparkOpacity, rng.nextDouble() * pi);
      }
    }
  }

  void _drawSpark(Canvas canvas, Offset center, double opacity, double rotation) {
    final r = 3.0;
    final path = Path();
    for (int i = 0; i < 4; i++) {
      final a = rotation + i * pi / 2;
      final outer = Offset(center.dx + r * cos(a), center.dy + r * sin(a));
      final a2 = a + pi / 4;
      final inner = Offset(
        center.dx + (r * 0.35) * cos(a2),
        center.dy + (r * 0.35) * sin(a2),
      );
      if (i == 0) {
        path.moveTo(outer.dx, outer.dy);
      } else {
        path.lineTo(outer.dx, outer.dy);
      }
      path.lineTo(inner.dx, inner.dy);
    }
    path.close();
    final paint = Paint()
      ..color = Color.lerp(_neonPink, Colors.white, 0.2)!.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HandDrawnCirclePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.seed != seed;
}

// 날짜 필터 탭이 선택됐을 때 버튼을 감싸지 않고, 버튼 모서리 바깥에 작게
// 붙는 손그림 낙서(스티커) 종류. "도형을 만드는 것"이 아니라 하트/별/
// 반짝이/초승달/꽃처럼 이미 익숙한 아주 단순한 낙서만 쓰고, 탭마다 억지로
// 다른 큰 도형을 새로 만들지 않는다 — 크기·선 두께·네온 강도는 전부
// _HandDrawnDoodlePainter 안에서 공통 상수로 통일한다.
enum _DoodleKind { heart, moon, stars, flower, sparkle }

_DoodleKind _doodleKindForTab(String tab) {
  switch (tab) {
    case '오늘':
      return _DoodleKind.heart;
    case '내일':
      return _DoodleKind.moon;
    case '이번 주':
      return _DoodleKind.stars;
    case '이번 주말':
      // 리본(고리 두 개)은 작은 크기에서 안경/무한대처럼 보여 완전히
      // 빼고, 같은 계열의 단순한 낙서인 작은 꽃으로 바꿨다.
      return _DoodleKind.flower;
    default: // '전체'
      return _DoodleKind.sparkle;
  }
}

// 낙서마다 버튼 기준 어디에, 얼마나 튀어나오게 붙일지. Positioned로 배치해
// (Stack 크기 계산에서 제외되므로) 버튼 셀 크기 자체는 전혀 영향받지 않는다.
// 모든 낙서가 같은 세트처럼 보이도록 튀어나오는 정도(대부분 -2~-6)와
// 크기(대략 14~20px 안쪽)를 서로 비슷하게 맞췄다.
Widget _buildCategoryDoodleOverlay(_DoodleKind kind, double progress, int seed) {
  Widget sized(double w, double h) => SizedBox(
    width: w,
    height: h,
    child: CustomPaint(
      painter: _HandDrawnDoodlePainter(kind: kind, progress: progress, seed: seed),
    ),
  );
  switch (kind) {
    case _DoodleKind.heart:
      return Positioned(right: -1, bottom: -3, child: sized(15, 14));
    case _DoodleKind.moon:
      return Positioned(
        bottom: -5,
        left: 0,
        right: 0,
        child: Center(child: sized(26, 12)),
      );
    case _DoodleKind.stars:
      // 별 두 개 — 하나의 큰 도형이 아니라 작은 반짝이 두 개를 살짝
      // 떨어뜨려 놓는다.
      return Positioned(top: -6, right: -4, child: sized(28, 18));
    case _DoodleKind.flower:
      return Positioned(top: -4, left: -3, child: sized(18, 18));
    case _DoodleKind.sparkle:
      return Positioned(right: -1, bottom: -2, child: sized(14, 14));
  }
}

// 낙서 하나를 그리는 페인터 — 버튼을 감싸는 굵은 링이 아니라, 형광펜으로
// 슥 그은 듯한 얇은 선 하나(하트/스마일 곡선/리본)나 작게 톡톡 팝인되는
// 반짝이(별)로만 표현한다.
//
// [progress] 0~1은 선택 애니메이션 진행도다. 0~0.72 구간에서 선이
// 천천히 그려지고(획 하나짜리 낙서), 0.85 부근에서 반짝임이 한 번 튀어
// 오른 뒤 낮은 세기로 자리를 지킨다(애니메이션이 끝나도 계속 반짝이지
// 않음). 역재생(선택 해제)되면 그린 순서 그대로 지워지는 것처럼 보인다.
class _HandDrawnDoodlePainter extends CustomPainter {
  _HandDrawnDoodlePainter({
    required this.kind,
    required this.progress,
    required this.seed,
  });

  final _DoodleKind kind;
  final double progress;
  final int seed;

  static const Color _neonPink = Color(0xFFFF5FA8);
  static const Color _neonPurple = Color(0xFFB14EFF);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final rng = Random(seed);
    switch (kind) {
      case _DoodleKind.heart:
        _paintStroke(canvas, _heartPath(size, rng));
        break;
      case _DoodleKind.moon:
        _paintStroke(canvas, _moonPath(size, rng));
        break;
      case _DoodleKind.flower:
        _paintStroke(canvas, _flowerPath(size, rng));
        break;
      case _DoodleKind.sparkle:
        _paintPoppingStars(canvas, [Offset(size.width / 2, size.height / 2)], [
          0.0,
        ], rng);
        break;
      case _DoodleKind.stars:
        // 별 두 개만 — 하나의 큰 도형이 아니라 작은 반짝이 두 개를
        // 자연스럽게 떨어뜨려 놓는다(3개는 좁은 공간에서 서로 겹쳐 얼룩져
        // 보였다).
        _paintPoppingStars(
          canvas,
          [
            Offset(size.width * 0.18, size.height * 0.7),
            Offset(size.width * 0.78, size.height * 0.25),
          ],
          const [0.0, 0.3],
          rng,
        );
        break;
    }
  }

  // 손으로 슥 그은 한 획짜리 낙서(하트/스마일/꽃) — 얇은 형광펜 선 하나로
  // 천천히 그려지고, 다 그려지면 끝점 근처에서 작은 반짝임이 한 번 튄다.
  // 선 두께/네온 강도는 _HandDrawnCirclePainter와 동일하게 맞춰 하나의
  // 세트처럼 보이게 한다.
  void _paintStroke(Canvas canvas, Path path) {
    final metric = path.computeMetrics().first;
    final totalLen = metric.length;
    const drawEnd = 0.72;
    final drawT = progress >= drawEnd
        ? 1.0
        : Curves.easeOutCubic.transform((progress / drawEnd).clamp(0.0, 1.0));
    final drawPath = metric.extractPath(0, totalLen * drawT);

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _neonPink.withValues(alpha: 0.4);
    canvas.drawPath(drawPath, outline);

    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Color.lerp(_neonPink, _neonPurple, 0.2)!.withValues(alpha: 1.0);
    canvas.drawPath(drawPath, core);

    final sparkOpacity = _sparkOpacityFor(progress);
    if (sparkOpacity > 0) {
      final tangent = metric.getTangentForOffset(totalLen * 0.5);
      if (tangent != null) {
        _drawTinyStar(canvas, tangent.position, 1, sparkOpacity, seed * 0.7);
      }
    }
  }

  // 이번 주(별 2~3개)/전체(반짝이 1개) — 별이 하나씩 통통 튀듯 팝인된다.
  void _paintPoppingStars(
    Canvas canvas,
    List<Offset> positions,
    List<double> startAt,
    Random rng,
  ) {
    const popSpan = 0.4;
    for (int i = 0; i < positions.length; i++) {
      final localT = ((progress - startAt[i]) / popSpan).clamp(0.0, 1.0);
      if (localT <= 0) continue;
      final scale = Curves.easeOutBack.transform(localT);
      _drawTinyStar(
        canvas,
        positions[i],
        scale,
        localT,
        rng.nextDouble() * pi + i,
      );
    }
  }

  double _sparkOpacityFor(double progress) {
    final peak = (1 - ((progress - 0.85).abs() / 0.15)).clamp(0.0, 1.0);
    final steady = progress >= 0.97 ? 0.55 : 0.0;
    return max(peak, steady);
  }

  void _drawTinyStar(
    Canvas canvas,
    Offset center,
    double scale,
    double opacity,
    double rotation,
  ) {
    if (scale <= 0 || opacity <= 0) return;
    final r = 4.0 * scale;
    final path = Path();
    for (int i = 0; i < 4; i++) {
      final a = rotation + i * pi / 2;
      final outer = Offset(center.dx + r * cos(a), center.dy + r * sin(a));
      final a2 = a + pi / 4;
      final inner = Offset(
        center.dx + (r * 0.35) * cos(a2),
        center.dy + (r * 0.35) * sin(a2),
      );
      if (i == 0) {
        path.moveTo(outer.dx, outer.dy);
      } else {
        path.lineTo(outer.dx, outer.dy);
      }
      path.lineTo(inner.dx, inner.dy);
    }
    path.close();

    // 번짐 없이 또렷한 채움 — 네온 핑크를 화이트와 살짝 섞어 밝기만 준다.
    final paint = Paint()
      ..color = Color.lerp(_neonPink, Colors.white, 0.2)!.withValues(
        alpha: opacity.clamp(0.0, 1.0),
      )
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  // 작고 살짝 기울어진 하트 — 좌우 비율은 원래 하트 모양 그대로 유지해
  // "하트로 보이는 것"은 안 깨뜨리면서, 크기를 줄이고 손으로 톡 찍어
  // 그린 듯 살짝 기울여서 손하트 느낌의 캐주얼한 낙서로 만든다.
  Path _heartPath(Size s, Random rng) {
    final w = s.width, h = s.height;
    double j(double v, double amt) => v + (rng.nextDouble() - 0.5) * amt;
    // 실제 그려지는 하트는 박스의 80%만 차지하도록 살짝 줄여서 더
    // 아담해 보이게 한다.
    const scale = 0.8;
    final cx = w * 0.5, cy = h * 0.5;
    Offset p(double x, double y) =>
        Offset(cx + (x - w * 0.5) * scale, cy + (y - h * 0.5) * scale);
    final bottom = p(w * 0.5, h * 0.92);
    final path = Path()..moveTo(bottom.dx, bottom.dy);
    final c1 = p(j(-w * 0.05, w * 0.06), j(h * 0.55, h * 0.06));
    final c2 = p(j(w * 0.08, w * 0.06), j(h * 0.02, h * 0.05));
    final top = p(w * 0.5, h * 0.2);
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, top.dx, top.dy);
    final c3 = p(j(w * 0.92, w * 0.06), j(h * 0.02, h * 0.05));
    final c4 = p(j(w * 1.05, w * 0.06), j(h * 0.55, h * 0.06));
    path.cubicTo(c3.dx, c3.dy, c4.dx, c4.dy, bottom.dx, bottom.dy);
    // 손으로 톡 찍은 듯 살짝 기울인다.
    final matrix =
        Matrix4.translationValues(cx, cy, 0) *
        Matrix4.rotationZ(-0.18) *
        Matrix4.translationValues(-cx, -cy, 0);
    return path.transform(matrix.storage);
  }

  // 스마일/초승달 곡선 — 살짝 휘어진 선 하나.
  Path _moonPath(Size s, Random rng) {
    final w = s.width, h = s.height;
    final dip = h * (1.0 + (rng.nextDouble() - 0.5) * 0.2);
    return Path()
      ..moveTo(w * 0.05, h * 0.3)
      ..quadraticBezierTo(w * 0.5, dip, w * 0.95, h * 0.3);
  }

  // 작은 꽃 — 가운데 한 점에서 짧은 꽃잎 다섯 개를 하나씩 뻗었다가
  // 돌아오는 한 획짜리 낙서(리본처럼 큰 도형을 짜맞추지 않고, 하트/별과
  // 같은 성격의 아주 단순한 스크리블).
  Path _flowerPath(Size s, Random rng) {
    final w = s.width, h = s.height;
    final cx = w * 0.5, cy = h * 0.58;
    const petals = 5;
    final petalLen = (w < h ? w : h) * 0.42;
    final path = Path()..moveTo(cx, cy);
    for (int i = 0; i < petals; i++) {
      final angle =
          (i / petals) * pi * 2 - pi / 2 + (rng.nextDouble() - 0.5) * 0.2;
      final len = petalLen * (0.9 + rng.nextDouble() * 0.2);
      final tip = Offset(cx + len * cos(angle), cy + len * sin(angle));
      const spread = 0.4;
      final out = Offset(
        cx + len * 0.55 * cos(angle - spread),
        cy + len * 0.55 * sin(angle - spread),
      );
      final back = Offset(
        cx + len * 0.55 * cos(angle + spread),
        cy + len * 0.55 * sin(angle + spread),
      );
      path.quadraticBezierTo(out.dx, out.dy, tip.dx, tip.dy);
      path.quadraticBezierTo(back.dx, back.dy, cx, cy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _HandDrawnDoodlePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.seed != seed ||
      oldDelegate.kind != kind;
}
