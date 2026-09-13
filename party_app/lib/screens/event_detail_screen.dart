import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/models/place_party_index.dart';
import 'package:party_app/services/place_party_link_service.dart';
import 'package:party_app/models/place_area.dart';
import 'package:party_app/models/listing_inquiry.dart';
import 'package:party_app/widgets/guest_inquiry_button.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/place_taxonomy.dart';
import 'package:party_app/widgets/place_product/place_menu_list_section.dart';
import 'package:party_app/widgets/place_product/place_product_list_section.dart';
import 'package:party_app/models/custom_amenity.dart';
import 'package:party_app/models/place_facility_options.dart';
import 'package:party_app/models/place_menu.dart';
import 'package:party_app/services/place_menu_service.dart';
import 'package:party_app/models/place_visit_reservation.dart';
import 'package:party_app/screens/event_edit_screen.dart';
import 'package:party_app/screens/place_visit_reservation_screen.dart';
import 'package:party_app/utils/favorites_service.dart';
import 'package:party_app/models/report_reason.dart';
import 'package:party_app/widgets/user_safety_actions.dart';
import 'package:party_app/utils/place_owner.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/utils/party_utils.dart';
import 'package:party_app/widgets/favorite_star_button.dart';
import 'package:party_app/widgets/media_gallery.dart';
import 'package:party_app/widgets/partychu_perk.dart';
import 'package:party_app/widgets/partychu_ui.dart';
import 'package:party_app/widgets/place_address_row.dart';
import 'package:party_app/widgets/custom_amenity_view.dart';
import 'package:party_app/widgets/place_attributes_view.dart';
import 'package:party_app/widgets/place_facility_options_view.dart';
import 'package:party_app/widgets/place_offering_board.dart';
import 'package:party_app/widgets/web_frame.dart';

// ══════════════════════════════════════════════════════════════════
// 플레이스 상세 — 혼술바/이벤트/핫플 등 매장·장소를 안내만 하는 순수
// 정보 화면(파티샵과 달리 구매/예약 로직 없음). party_shop_detail_screen.dart의
// 헤더(이미지 캐러셀 + 이름/배지/위치/설명) 패턴을 그대로 따른다.
// ══════════════════════════════════════════════════════════════════
class EventDetailScreen extends StatefulWidget {
  final String eventId;
  final Map<String, dynamic> eventData;

  const EventDetailScreen({
    super.key,
    required this.eventId,
    required this.eventData,
  });

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  /// 화면에 그릴 플레이스 데이터 — 넘겨받은 스냅샷으로 시작하고, 소유자가
  /// 수정 화면에서 돌아오면 여기만 새로 읽어 교체한다(호출부의 맵은 그대로).
  late Map<String, dynamic> _data = Map<String, dynamic>.from(widget.eventData);

  /// 이 플레이스를 수정할 수 있는 사용자인지 — 첫 프레임 전에 확정해두고
  /// true일 때만 앱바에 수정 버튼을 그린다(확인 전 노출 방지).
  late bool _canEdit = canEditPlace(_data);

  bool _isRefreshing = false;

  /// 🎉 With파티 — 지금 노출 가능한 파티가 이 플레이스에 걸려 있는지.
  ///
  /// 목록에서 'With파티'로 걸러 들어온 사람이 **왜 이 곳이 나왔는지**를 맨 위
  /// 배지 한 줄로 알 수 있게 한다. 아래 '🎉 이곳에서 열리는 파티' 목록과
  /// 같은 정본(`parties.linkedEventId`)·같은 노출 판정을 쓰므로, 배지만 뜨고
  /// 목록은 비는 일이 없다.
  bool _hasLiveLinkedParty = false;

  @override
  void initState() {
    super.initState();
    _linkedPartiesFuture = _queryLinkedParties();
    _loadLinkedPartyBadge();
  }

  /// 이 플레이스에 연결된 파티 조회 — **이 화면에서 파티를 읽는 유일한 길**.
  ///
  /// 조회 기준은 언제나 `parties.linkedEventId`다(플레이스 문서의
  /// `linkedPartyIds` 보조 배열이 아니라). 그래서 "플레이스+파티" 콤보로
  /// 한 번에 등록된 파티와, 나중에 호스트가 직접 연결한 기존 파티가 같은
  /// 목록에 함께 나온다.
  ///
  /// 미래를 화면이 들고 있어야 With파티 배지와 🎉 파티 탭이 **같은 한 번의
  /// 조회**를 나눠 쓴다 — 예전에는 배지가 initState에서 한 번, 파티 목록이
  /// 빌드마다 한 번씩 따로 읽었다.
  late Future<QuerySnapshot<Map<String, dynamic>>> _linkedPartiesFuture;

  Future<QuerySnapshot<Map<String, dynamic>>> _queryLinkedParties() =>
      FirebaseFirestore.instance
          .collection('parties')
          .where(PlacePartyLink.linkedEventIdField, isEqualTo: widget.eventId)
          .get();

  /// 새 파티가 이 플레이스에 붙은 뒤 — 목록과 배지를 함께 다시 읽는다.
  void _reloadLinkedParties() {
    if (!mounted) return;
    setState(() => _linkedPartiesFuture = _queryLinkedParties());
    _loadLinkedPartyBadge();
  }

  Future<void> _loadLinkedPartyBadge() async {
    try {
      final snap = await _linkedPartiesFuture;
      if (!mounted) return;
      // 목록·지도가 쓰는 색인과 **같은 함수**로 판정한다 — 삭제됨·지난 파티·
      // 남은 회차 없는 정기 파티는 여기서도 똑같이 빠진다.
      final index = PlacePartyIndex.fromSnapshot(snap.docs);
      final has = index.has(widget.eventId);
      if (has != _hasLiveLinkedParty) {
        setState(() => _hasLiveLinkedParty = has);
      }
    } catch (e) {
      debugPrint('[EventDetail] With파티 배지 조회 실패: $e');
    }
  }

  /// 소유자가 수정 화면에서 돌아오면 문서를 다시 읽어 화면에 반영한다.
  ///
  /// `EventEditScreen`은 저장 성공 여부를 pop 결과로 돌려주지 않으므로,
  /// 복귀 시 한 번만 재조회한다(수정 없이 뒤로 온 경우엔 같은 값이 다시
  /// 그려질 뿐이라 안전하다).
  Future<void> _openEdit() async {
    await Navigator.push(
      context,
      webFramedRoute(
        (_) => EventEditScreen(eventId: widget.eventId, data: _data),
      ),
    );
    if (!mounted) return;
    setState(() => _isRefreshing = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .get();
      final fresh = snap.data();
      if (!mounted) return;
      if (fresh != null) {
        setState(() {
          _data = fresh;
          _canEdit = canEditPlace(fresh);
        });
      }
    } catch (e) {
      debugPrint('[EventDetail] 수정 후 재조회 실패: $e');
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  // "HH:mm" 저장 문자열 → "오전/오후 h:mm" 표시용
  String _fmtTimeLabel(String hhmm) {
    final p = hhmm.split(':');
    final h = int.tryParse(p[0]) ?? 0;
    final m = p.length > 1 ? p[1] : '00';
    if (h == 0) return '오전 12:$m';
    if (h < 12) return '오전 $h:$m';
    if (h == 12) return '오후 12:$m';
    return '오후 ${h - 12}:$m';
  }

  String? _timeRangeLabel() {
    if (_data['hasTimeRange'] != true) return null;
    final start = _data['startTime'] as String?;
    final end = _data['endTime'] as String?;
    if (start == null || end == null) return null;
    return '${_fmtTimeLabel(start)} ~ ${_fmtTimeLabel(end)}';
  }

  /// 하단 고정 CTA — 방문 예약 버튼과 문의 버튼이 함께 들어간다.
  ///
  /// 둘 다 없으면 바 자체를 그리지 않는다(예약을 받지 않고 문의도 닫아 둔
  /// 매장에 빈 흰 띠만 남는 것을 막는다).
  Widget? _bottomCta() {
    final inquiry = _inquiryButton();
    final reserve = _visitReservationBar();
    if (inquiry == null && reserve == null) return null;
    // 예약 바는 안내 문구까지 들고 있는 세로 묶음이라, 문의 버튼은 그 위에
    // 한 줄로 얹는다(가로로 나란히 두면 안내 문구와 높이가 어긋난다).
    if (reserve == null) {
      return Container(
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          10 + MediaQuery.of(context).padding.bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFF0F0F4))),
        ),
        child: SizedBox(height: 52, child: inquiry),
      );
    }
    if (inquiry == null) return reserve;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: SizedBox(height: 48, child: inquiry),
        ),
        reserve,
      ],
    );
  }

  /// 문의 버튼 — 호스트가 열어 뒀고 내 매장이 아닐 때만.
  Widget? _inquiryButton() {
    final hostId = _data['hostId'] as String? ?? '';
    if (!GuestInquiryButton.shouldShow(
      enabled: ListingInquiry.isEnabled(_data),
      hostId: hostId,
    )) {
      return null;
    }
    return GuestInquiryButton(
      enabled: true,
      compact: true,
      target: InquiryTarget.place,
      listingId: widget.eventId,
      hostId: hostId,
      hostName: _data['hostName'] as String? ?? '호스트',
      listingTitle: _data['name'] as String? ?? '플레이스',
      guide: ListingInquiry.guideOf(_data),
    );
  }

  /// 하단 고정 "방문 예약하기" 버튼 — 업주가 예약 받기를 켠 매장에만 뜬다.
  ///
  /// 이 예약은 **무료**다(결제 없음). 결제가 붙는 좌석권은 본문의
  /// "상품·이용권" 목록에서 따로 구매한다 — 두 가지가 헷갈리지 않도록 버튼
  /// 문구와 그 아래 설명에서 성격을 분명히 적는다.
  Widget? _visitReservationBar() {
    final config = PlaceVisitReservationConfig.fromMap(
      _data['visitReservation'] is Map
          ? Map<String, dynamic>.from(_data['visitReservation'] as Map)
          : null,
    );
    if (!config.enabled) return null;
    // 내 매장에는 예약할 수 없다(서버도 같은 이유로 막는다).
    if (_canEdit) return null;

    final auto = config.approvalMode == VisitApprovalMode.auto;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF0F0F4))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            // 예약금이 걸린 매장은 '무료'라고 하면 안 된다 — 얼마를 내야
            // 하는지 버튼 위에서 바로 알려준다.
            '${auto ? '신청하면 바로 확정' : '매장 승인 후 확정'} · '
            '${config.hasDeposit ? '예약금 ${formatPrice(config.depositPerPerson)}/1인' : '무료 방문 예약'}',
            style: const TextStyle(fontSize: 11.5, color: Colors.black45),
          ),
          const SizedBox(height: 8),
          PartyChuPrimaryButton(
            label: '방문 예약하기',
            height: 52,
            showBadge: false,
            onTap: () => Navigator.push(
              context,
              webFramedRoute(
                (_) => PlaceVisitReservationScreen(
                  placeId: widget.eventId,
                  placeData: _data,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 제목 옆 기간 배지 — **기간이 실제로 정해져 있을 때만** 값을 돌려준다.
  ///
  /// 상시 운영(isOngoing)이면 null이라 배지가 아예 그려지지 않는다. 플레이스는
  /// 기간이 정해진 모집글이 아니라 상시 운영되는 장소라, 거의 모든 문서에
  /// 똑같이 "상시 진행"이 붙어서 알려주는 것이 없었다(카드 배지도 같은 이유로
  /// 뺐다 — place_card_widget.dart 참고).
  ({String label, Color fg, Color bg})? _periodBadge() {
    final isOngoing = _data['isOngoing'] as bool? ?? true;
    if (isOngoing) return null;
    final start = (_data['startDate'] as Timestamp?)?.toDate();
    final end = (_data['endDate'] as Timestamp?)?.toDate();
    if (start == null || end == null) {
      return (
        label: '진행중',
        fg: const Color(0xFF2E7D32),
        bg: const Color(0xFFE8F5E9),
      );
    }
    final now = DateTime.now();
    final ended = now.isAfter(
      DateTime(end.year, end.month, end.day, 23, 59, 59),
    );
    if (ended) {
      return (label: '종료', fg: Colors.black38, bg: const Color(0xFFF5F5F5));
    }
    return (
      label: '${_fmtDate(start)} ~ ${_fmtDate(end)}',
      fg: const Color(0xFF2E7D32),
      bg: const Color(0xFFE8F5E9),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _data['name'] as String? ?? '';
    // 표시·복사·길찾기에 모두 쓰는 한 값 — 'location'은 등록 화면이 주소와
    // 상세주소를 이미 합쳐 저장한 값이라, 상세주소가 빠진 예전 문서만
    // joinAddress로 보완한다(중복은 붙지 않는다).
    final location = PlaceAddressRow.joinAddress(
      (_data['location'] as String?)?.isNotEmpty == true
          ? _data['location'] as String
          : _data['roadAddress'] as String? ??
                _data['address'] as String? ??
                '',
      _data['detailAddress'] as String?,
    );
    final desc = _data['description'] as String? ?? '';
    // 새 데이터는 'themeTags'(다중 선택) 배열을 쓰고, 예전에 단일 'category'로
    // 등록된 문서는 그 값을 태그 하나짜리 목록으로 취급해 하위호환한다.
    final themeTagsRaw = (_data['themeTags'] as List?)?.cast<String>();
    final themeTags = themeTagsRaw != null && themeTagsRaw.isNotEmpty
        ? themeTagsRaw
        : ((_data['category'] as String?)?.isNotEmpty == true
              ? [_data['category'] as String]
              : const <String>[]);
    // '이벤트 진행중' 소분류 — 필드가 없던 기존 문서는 null이고, 태그가 꺼져
    // 있으면 값이 남아 있더라도 보여주지 않는다(태그가 정본이다).
    final eventSubtypeRaw = (_data['eventSubtype'] as String?)?.trim();
    final eventSubtype =
        themeTags.contains(ListingConstants.placeEventTag) &&
            eventSubtypeRaw != null &&
            eventSubtypeRaw.isNotEmpty
        ? eventSubtypeRaw
        : null;
    // 대분류·소분류 — 새 필드가 없는 옛 문서는 업종에서 유추한다.
    final placeCategory = PlaceTaxonomy.categoryOf(_data);
    final placeSubcategories = PlaceTaxonomy.subcategoriesOf(_data);
    final facilityOptions = _data['facilityOptions'] is Map
        ? PlaceFacilityOptions.fromMap(
            Map<String, dynamic>.from(_data['facilityOptions'] as Map),
          )
        : PlaceFacilityOptions.empty();
    final mainUrl = _data['mainImageUrl'] as String? ?? '';
    final introUrls = (_data['introImageUrls'] as List?)?.cast<String>() ?? [];
    final allImgUrls = [if (mainUrl.isNotEmpty) mainUrl, ...introUrls];
    final videoUrl = _data['videoUrl'] as String?;
    final videoThumbnailUrl = _data['videoThumbnailUrl'] as String?;
    final hasVideo = videoUrl != null && videoUrl.isNotEmpty;
    // 대표 미디어 — 파티추/장소대여 상세와 동일한 규칙. 대표가 동영상이면
    // 갤러리 맨 앞에 동영상 페이지를 두고, 대표가 사진이면 그 사진을
    // index 0으로 당겨온다(이 화면에서만 재정렬하고 Firestore에는 쓰지 않음).
    final cover = getPartyCoverMedia(_data, tag: 'EventDetailHero');
    final videoIsCover = cover?.isVideo ?? false;
    if (!videoIsCover && cover?.imageUrl != null) {
      final idx = allImgUrls.indexOf(cover!.imageUrl!);
      if (idx > 0) {
        allImgUrls
          ..removeAt(idx)
          ..insert(0, cover.imageUrl!);
      }
    }
    final period = _periodBadge();
    final timeRangeLabel = _timeRangeLabel();
    // 공간 평수 — 필드가 없던 옛 문서는 null이라 줄이 통째로 빠진다.
    final areaLabel = PlaceArea.labelOf(_data);

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      // 방문 예약을 받는 매장에만 하단 고정 버튼이 붙는다. 아래 "상품·이용권"
      // 목록의 유료 좌석권 구매와는 다른 기능이라 자리도 문구도 분리했다.
      bottomNavigationBar: _bottomCta(),
      body: CustomScrollView(
        slivers: [
          // 사진을 고정 높이(260)로 잘라 넣던 접히는 헤더 대신, 파티추
          // 상세와 동일하게 "고정 앱바 + 원본 비율 미디어 갤러리" 구성을
          // 쓴다 — 사진이 잘리거나 축소되지 않고 화면 폭 전체로 보인다.
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            elevation: 0,
            title: Text(
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
            ),
            actions: [
              SafetyMenuButton(
                targetType: ReportTargetType.event,
                targetId: widget.eventId,
                targetUserId: _data['hostId'] as String? ?? '',
                targetUserName: _data['hostName'] as String? ?? '',
                targetTitle: _data['name'] as String? ?? '',
              ),
              // 소유자(또는 관리자)에게만 보이는 수정 진입점. 소유권을 확인한
              // 뒤에만 그려지므로 로딩 중 잠깐 노출되는 일이 없다.
              if (_canEdit)
                IconButton(
                  tooltip: '플레이스 수정',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _isRefreshing ? null : _openEdit,
                ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FavoriteStarButton(
                  itemType: FavoriteType.event,
                  itemId: widget.eventId,
                  glow: false,
                ),
              ),
            ],
          ),
          // ── 미디어 갤러리 (사진 + 동영상 통합) ──────────────────────────
          // 파티추 상세와 완전히 동일한 표시 기준: 화면 폭을 꽉 채우고
          // 높이는 사진 원본 비율대로(좌우 여백 없음), 좌우로 넘겨보기,
          // 동영상도 잘리지 않는 원본 비율(contain)에 남는 여백은 화면
          // 배경색과 같은 톤으로 채운다.
          SliverToBoxAdapter(
            child: (allImgUrls.isNotEmpty || hasVideo)
                ? MediaGallery(
                    images: allImgUrls,
                    videoUrl: videoUrl,
                    videoThumbnailUrl: videoThumbnailUrl,
                    videoFirst: videoIsCover,
                    videoFit: BoxFit.contain,
                    videoBackgroundColor: const Color(0xFFFFF4F8),
                    counterAccentColor: const Color(0xFFFF6FA0),
                  )
                : Container(
                    width: double.infinity,
                    height: 220,
                    color: const Color(0xFFFFE0EE),
                    child: const Center(
                      child: Icon(
                        Icons.celebration_outlined,
                        size: 64,
                        color: Color(0xFFFF6FA0),
                      ),
                    ),
                  ),
          ),
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontFamily: 'SeoulHangang',
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            shadows: [
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
                        ),
                      ),
                      // 기간이 정해진 플레이스에만 붙는다 — 상시 운영이면
                      // _periodBadge()가 null이라 제목이 폭을 다 쓴다.
                      if (period != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: period.bg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            period.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: period.fg,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      // 🎉 With파티 — 목록에서 이 조건으로 걸러 들어온 사람이
                      // "왜 여기가 나왔는지"를 맨 앞에서 바로 읽는다. 파티가
                      // 안 걸린 곳에서는 통째로 빠지므로 예전과 똑같이 보인다.
                      if (_hasLiveLinkedParty)
                        _badge(
                          '🎉 파티츄 파티와 함께하는 곳',
                          textColor: const Color(0xFFC2185B),
                          bgColor: const Color(0xFFFFE3EE),
                        ),
                      // 대분류가 맨 앞 — '무슨 가게인가'가 가장 먼저
                      // 읽혀야 한다. 옛 문서는 업종에서 유추한 값이 뜨고,
                      // 유추도 안 되면 이 배지만 빠진다.
                      if (placeCategory != null)
                        _badge(
                          PlaceTaxonomy.displayOf(placeCategory),
                          textColor: const Color(0xFF7A3FCC),
                          bgColor: const Color(0xFFF2EBFF),
                        ),
                      for (final sub in placeSubcategories)
                        _badge(
                          sub,
                          textColor: const Color(0xFF7A3FCC),
                          bgColor: const Color(0xFFF7F2FF),
                        ),
                      for (final tag in themeTags)
                        _badge(
                          '${ListingConstants.placeThemeTagEmojis[tag] ?? ''} '
                          '${ListingConstants.placeThemeTagLabel(tag)}',
                          textColor: const Color(0xFFFF6FA0),
                          bgColor: const Color(0xFFFFF0F5),
                        ),
                    ],
                  ),
                  // 핵심 특징 — 긴 글을 읽기 전에 '왜 가볼 만한 곳인지'가
                  // 먼저 보여야 한다. 값이 없는 옛 플레이스에서는 통째로
                  // 빠지므로 예전과 똑같이 보인다.
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: PlaceHighlightChips(data: _data),
                  ),
                  // '이벤트 진행중' 바로 아래 줄에 무슨 이벤트인지 —
                  // 태그만으로는 "뭔가 하는 중"까지밖에 읽히지 않는다.
                  // 소분류가 없던 시절의 문서는 이 줄이 통째로 빠진다.
                  if (eventSubtype != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _badge(
                        ListingConstants.placeEventSubtypeLabel(eventSubtype),
                        textColor: const Color(0xFFE2568A),
                        bgColor: const Color(0xFFFFE6EF),
                      ),
                    ),
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    // 주소 + 복사/길찾기 — places 상세와 같은 공용 위젯.
                    PlaceAddressRow(
                      address: location,
                      placeName: name,
                      latitude: (_data['latitude'] as num?)?.toDouble(),
                      longitude: (_data['longitude'] as num?)?.toDouble(),
                    ),
                  ],
                  // 공간 평수 — 이 필드가 없던 옛 플레이스에서는 줄 자체가
                  // 빠지므로 예전과 똑같이 보인다([PlaceArea]). 호스트가 수정
                  // 화면에 한 번 들어와 저장하면 그때부터 이 줄이 생긴다.
                  if (areaLabel != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text(
                          PlaceArea.emoji,
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          areaLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (timeRangeLabel != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time_outlined,
                          size: 14,
                          color: Colors.black38,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            timeRangeLabel,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  // 문의하기는 본문이 아니라 **하단 고정 CTA**에 있다
                  // (_bottomCta) — 방문 예약 버튼과 한자리에 둔다.
                  // 파티츄 전용 혜택 — 있을 때만 그려진다(없으면 빈 위젯).
                  PartychuPerkCard.fromData(
                    _data,
                    margin: const EdgeInsets.only(top: 16),
                  ),
                  // 메뉴 — 술집·바·카페에서 손님이 가장 먼저 찾는 정보라
                  // 따로 볼 수 있는 탭을 준다. 메뉴도 메뉴판 사진도 없는
                  // 기존 플레이스에서는 탭 자체가 나오지 않고, 아래 본문이
                  // 예전과 똑같이 이어진다([_MenuTabs] 주석 참고).
                  _MenuTabs(
                    placeId: widget.eventId,
                    menuBoardImageUrls:
                        (_data['menuBoardImageUrls'] as List?)
                            ?.cast<String>() ??
                        const [],
                    selected: _detailTab,
                    onSelect: (i) => setState(() => _detailTab = i),
                    infoChildren: [
                      // 상품·이용권 — 공간대여·숙박 상세와 완전히 같은 위젯.
                      const SizedBox(height: 16),
                      // 🎉 파티 | ✨ 이벤트 — 이 매장에서 열리는 것을 좌우
                      // 2열로 **함께** 보여준다([PlaceOfferingBoard]). 예전에는
                      // 매장 이벤트가 여기, 연결 파티 목록이 상세 맨 아래로
                      // 갈라져 있어 같은 질문("여기서 뭐 하지?")의 답을 두
                      // 군데서 찾아야 했다. 결제가 없는 홍보라 상품 영역과는
                      // 여전히 분리해 위쪽에 둔다(무엇이 "사는 것"인지
                      // 헷갈리지 않게).
                      //
                      // 데이터는 그대로다 — 파티는 `parties.linkedEventId`,
                      // 이벤트는 `placePromotions`를 각각 읽는다.
                      PlaceOfferingBoard(
                        placeId: widget.eventId,
                        linkedPartiesFuture: _linkedPartiesFuture,
                        accent: const Color(0xFFFF6FA0),
                        // 호스트 본인일 때만 '🎉 파티 추가 / ✨ 매장 이벤트 추가'
                        // 진입점이 붙는다.
                        placeCollection: 'events',
                        hostId: _data['hostId'] as String?,
                        placeName: _data['name'] as String?,
                        // 파티 추가 시 이 플레이스가 연결 대상이 된다.
                        placeData: _data,
                        onPartyLinked: _reloadLinkedParties,
                      ),
                      const SizedBox(height: 16),
                      PlaceProductListSection(
                        placeId: widget.eventId,
                        accent: const Color(0xFFFF6FA0),
                        fallbackImageUrl: _data['mainImageUrl'] as String?,
                      ),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const Divider(height: 1),
                        const SizedBox(height: 14),
                        Text(
                          desc,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                            height: 1.6,
                          ),
                        ),
                      ],
                      // 좌석·공간 + 이용 편의 옵션 — 플레이스 상세와 동일한 위젯.
                      // 대분류에 따라 다른 정보 블록 — 클럽이면 장르·DJ·입장
                      // 정보·흡연정책, 음식점이면 무제한·콜키지·단체석 순서로
                      // 그린다([PlaceDetailBlocks]). 값이 없는 그룹은 빠진다.
                      PlaceAttributesView(data: _data),
                      // 좌석 그룹만 보고 판단한다(facilityOptions에는 외부 음식도
                      // 함께 들어 있어 isNotEmpty로는 빈 제목이 남는다).
                      if (facilityOptions.hasAnyIn(
                        PlaceFacilityCatalog.seatingSection,
                      )) ...[
                        const SizedBox(height: 14),
                        const Divider(height: 1),
                        const SizedBox(height: 14),
                        const Text(
                          '🪑 좌석·공간',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        PlaceFacilityOptionsView(
                          options: facilityOptions,
                          accent: const Color(0xFFFF6FA0),
                        ),
                      ],
                      // 외부 음식 반입 — 좌석·공간과 같은 타일 모양. 고르지 않은
                      // 기존 플레이스에는 아무것도 늘지 않는다.
                      if (facilityOptions.hasAnyIn(
                        PlaceFacilityCatalog.foodSection,
                      )) ...[
                        const SizedBox(height: 14),
                        const Divider(height: 1),
                        const SizedBox(height: 14),
                        const Text(
                          '🍽 외부 음식 반입',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        PlaceFacilityOptionsView(
                          options: facilityOptions,
                          groups: PlaceFacilityCatalog.foodSection,
                          accent: const Color(0xFFFF6FA0),
                        ),
                      ],
                      // 기타 편의 서비스 — 호스트가 적은 항목명을 그대로.
                      // 값이 없으면 이 위젯은 아무것도 그리지 않는다.
                      if (CustomAmenities.of(_data).isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const Divider(height: 1),
                        const SizedBox(height: 14),
                        CustomAmenityView(
                          data: _data,
                          accent: const Color(0xFFFF6FA0),
                        ),
                      ],
                      // "이곳에서 열리는 파티"는 더 이상 여기(맨 아래)에 따로
                      // 있지 않다 — 위쪽 [PlaceOfferingBoard]의 🎉 파티 열이
                      // 같은 목록을 같은 카드로 보여준다. 두 자리에 함께 두면
                      // 같은 파티가 한 화면에 두 번 나온다.
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 상세 본문 탭 — 0: 정보, 1: 메뉴.
  ///
  /// 메뉴가 하나도 없는 플레이스에서는 탭 자체가 그려지지 않으므로 이 값은
  /// 늘 0으로 남는다(기존 화면과 완전히 같아진다).
  int _detailTab = 0;

  Widget _badge(
    String text, {
    required Color textColor,
    required Color bgColor,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
    ),
  );
}

/// 상세 본문의 "정보 | 메뉴" 탭.
///
/// ── 왜 메뉴만 탭으로 뽑았나 ──────────────────────────────────────────────
/// 이 화면에는 원래 탭이 없고 한 번에 쭉 내려 읽는 구조다. 이벤트·상품까지
/// 탭으로 나누면 지금 첫 화면에 보이던 것들이 탭 뒤로 숨어, 메뉴와 무관한
/// 영역의 노출이 바뀐다. 그래서 '정보' 탭은 **예전 화면 그대로**(순서·내용
/// 무변경) 두고, 메뉴만 따로 볼 수 있는 자리를 하나 더 만들었다.
///
/// ── 메뉴가 없는 플레이스 ────────────────────────────────────────────────
/// 탭 줄 자체를 만들지 않는다. 빈 탭을 눌러 "등록된 메뉴가 없어요"를 보게
/// 하는 것보다, 있던 적 없는 것은 보이지 않는 편이 낫다(상품·이벤트 영역이
/// 비었을 때 섹션을 통째로 감추는 것과 같은 방침). 그래서 메뉴를 한 번도
/// 등록하지 않은 기존 플레이스의 화면은 이 변경 전과 완전히 같다.
class _MenuTabs extends StatelessWidget {
  const _MenuTabs({
    required this.placeId,
    required this.menuBoardImageUrls,
    required this.selected,
    required this.onSelect,
    required this.infoChildren,
  });

  final String placeId;

  /// 플레이스 문서의 `menuBoardImageUrls` — 없던 문서면 빈 목록으로 온다.
  final List<String> menuBoardImageUrls;

  /// 0: 정보, 1: 메뉴.
  final int selected;
  final ValueChanged<int> onSelect;

  /// '정보' 탭에 그대로 들어가는 기존 본문.
  final List<Widget> infoChildren;

  static const _accent = Color(0xFFFF6FA0);

  @override
  Widget build(BuildContext context) {
    final boards = menuBoardImageUrls
        .where((u) => u.trim().isNotEmpty)
        .toList();

    return StreamBuilder<List<PlaceMenu>>(
      stream: PlaceMenuService.watchPublicForPlace(placeId),
      builder: (context, snap) {
        final menus = snap.data ?? const <PlaceMenu>[];
        // 개별 메뉴도 메뉴판 사진도 없으면 탭을 만들지 않는다.
        if (menus.isEmpty && boards.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: infoChildren,
          );
        }

        final onMenuTab = selected == 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 18),
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFEDEFF4))),
              ),
              child: Row(
                children: [
                  _tab('정보', !onMenuTab, () => onSelect(0)),
                  _tab('메뉴', onMenuTab, () => onSelect(1)),
                ],
              ),
            ),
            if (onMenuTab)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                // 개별 메뉴와 메뉴판 사진을 함께 그리는 위젯을 그대로 쓴다 —
                // 둘 다 등록돼 있으면 둘 다 나오고, 메뉴판 사진은 눌러서
                // 확대해 볼 수 있다.
                child: PlaceMenuListSection(
                  placeId: placeId,
                  accent: _accent,
                  menuBoardImageUrls: boards,
                ),
              )
            else
              ...infoChildren,
          ],
        );
      },
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap) => Expanded(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? _accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? _accent : Colors.black45,
          ),
        ),
      ),
    ),
  );
}
