import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/screens/party_detail_screen.dart';
import 'package:party_app/utils/favorites_service.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/widgets/favorite_star_button.dart';
import 'package:party_app/widgets/media_gallery.dart';
import 'package:party_app/widgets/party_card_widget.dart';

// ══════════════════════════════════════════════════════════════════
// 플레이스 상세 — 혼술바/이벤트/핫플 등 매장·장소를 안내만 하는 순수
// 정보 화면(파티샵과 달리 구매/예약 로직 없음). party_shop_detail_screen.dart의
// 헤더(이미지 캐러셀 + 이름/배지/위치/설명) 패턴을 그대로 따른다.
// ══════════════════════════════════════════════════════════════════
class EventDetailScreen extends StatelessWidget {
  final String eventId;
  final Map<String, dynamic> eventData;

  const EventDetailScreen({
    super.key,
    required this.eventId,
    required this.eventData,
  });

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
    if (eventData['hasTimeRange'] != true) return null;
    final start = eventData['startTime'] as String?;
    final end = eventData['endTime'] as String?;
    if (start == null || end == null) return null;
    return '${_fmtTimeLabel(start)} ~ ${_fmtTimeLabel(end)}';
  }

  ({String label, Color fg, Color bg}) _periodBadge() {
    final isOngoing = eventData['isOngoing'] as bool? ?? true;
    if (isOngoing) {
      return (label: '상시 진행', fg: const Color(0xFF2E7D32), bg: const Color(0xFFE8F5E9));
    }
    final start = (eventData['startDate'] as Timestamp?)?.toDate();
    final end = (eventData['endDate'] as Timestamp?)?.toDate();
    if (start == null || end == null) {
      return (label: '진행중', fg: const Color(0xFF2E7D32), bg: const Color(0xFFE8F5E9));
    }
    final now = DateTime.now();
    final ended = now.isAfter(DateTime(end.year, end.month, end.day, 23, 59, 59));
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
    final name = eventData['name'] as String? ?? '';
    final location = eventData['location'] as String? ?? '';
    final desc = eventData['description'] as String? ?? '';
    // 새 데이터는 'themeTags'(다중 선택) 배열을 쓰고, 예전에 단일 'category'로
    // 등록된 문서는 그 값을 태그 하나짜리 목록으로 취급해 하위호환한다.
    final themeTagsRaw = (eventData['themeTags'] as List?)?.cast<String>();
    final themeTags = themeTagsRaw != null && themeTagsRaw.isNotEmpty
        ? themeTagsRaw
        : ((eventData['category'] as String?)?.isNotEmpty == true
            ? [eventData['category'] as String]
            : const <String>[]);
    final mainUrl = eventData['mainImageUrl'] as String? ?? '';
    final introUrls = (eventData['introImageUrls'] as List?)?.cast<String>() ?? [];
    final allImgUrls = [
      if (mainUrl.isNotEmpty) mainUrl,
      ...introUrls,
    ];
    final videoUrl = eventData['videoUrl'] as String?;
    final videoThumbnailUrl = eventData['videoThumbnailUrl'] as String?;
    final hasVideo = videoUrl != null && videoUrl.isNotEmpty;
    final period = _periodBadge();
    final timeRangeLabel = _timeRangeLabel();

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: (allImgUrls.isNotEmpty || hasVideo) ? 260 : 120,
            pinned: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FavoriteStarButton(
                  itemType: FavoriteType.event,
                  itemId: eventId,
                  unfavoritedColor: Colors.white,
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: (allImgUrls.isNotEmpty || hasVideo)
                  ? _ImageCarousel(
                      imageUrls: allImgUrls,
                      videoUrl: videoUrl,
                      videoThumbnailUrl: videoThumbnailUrl,
                    )
                  : Container(
                      color: const Color(0xFFFFE0EE),
                      child: const Center(
                        child: Icon(Icons.celebration_outlined,
                            size: 64, color: Color(0xFFFF6FA0)),
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
                  Row(children: [
                    Expanded(
                      child: Text(name,
                          style: const TextStyle(
                              fontFamily: 'SeoulHangang',
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                              shadows: [
                                Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                                Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                                Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                                Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
                              ])),
                    ),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: period.bg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        period.label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: period.fg),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in themeTags)
                        _badge(
                          '${ListingConstants.placeThemeTagEmojis[tag] ?? ''} $tag',
                          textColor: const Color(0xFFFF6FA0),
                          bgColor: const Color(0xFFFFF0F5),
                        ),
                    ],
                  ),
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      const Icon(Icons.location_on_outlined,
                          size: 14, color: Colors.black38),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(location,
                            style: const TextStyle(
                                fontSize: 13, color: Colors.black54)),
                      ),
                    ]),
                  ],
                  if (timeRangeLabel != null) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.access_time_outlined,
                          size: 14, color: Colors.black38),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(timeRangeLabel,
                            style: const TextStyle(
                                fontSize: 13, color: Colors.black54)),
                      ),
                    ]),
                  ],
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                    Text(desc,
                        style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                            height: 1.6)),
                  ],
                  _linkedPartyInfo(context, eventData),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "플레이스+파티" 콤보로 등록된 플레이스(`linkedPartyId` 있음)에서만
  /// 렌더링되는 "파티 정보 함께보기" 카드 — 연결된 `parties/{id}` 문서를
  /// 1회 조회해 날짜/참가비/모집상태를 보여주고, 파티 상세로 이동하는
  /// 버튼을 제공한다. 필드가 없는(일반) 플레이스는 아무것도 그리지 않는다.
  Widget _linkedPartyInfo(BuildContext context, Map<String, dynamic> data) {
    final linkedPartyId = data['linkedPartyId'] as String?;
    if (linkedPartyId == null || linkedPartyId.isEmpty) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('parties')
          .doc(linkedPartyId)
          .get(),
      builder: (context, snapshot) {
        final partyData = snapshot.data?.data();
        if (partyData == null) return const SizedBox.shrink();
        final status = PartyCard.effectiveStatus(partyData);
        final date = PartyCard.formatDate(partyData);
        final maleFee = (partyData['maleFee'] as num?)?.toInt();
        final femaleFee = (partyData['femaleFee'] as num?)?.toInt();
        final fee = maleFee ?? femaleFee ?? 0;
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF3EFFA),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE1D6F5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '🎉 파티 정보 함께보기',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    PartyCard.statusChip(status),
                  ],
                ),
                const SizedBox(height: 10),
                if (date.isNotEmpty)
                  Text('일정 : $date',
                      style: const TextStyle(fontSize: 13, color: Colors.black87)),
                if (fee > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('참가비 : ${formatPrice(fee)}',
                        style: const TextStyle(fontSize: 13, color: Colors.black87)),
                  ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PartyDetailScreen(docId: linkedPartyId),
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: const Color(0xFF7C5CBF),
                  ),
                  child: const Text('파티 상세 보기 →',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _badge(String text, {required Color textColor, required Color bgColor}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: textColor)),
      );
}

class _ImageCarousel extends StatefulWidget {
  final List<String> imageUrls;

  /// non-null이면 사진 뒤에 동영상 페이지를 하나 더 붙인다(대표 캐러셀
  /// 전용 — 상품 이미지 캐러셀 등 다른 용도로 쓸 때는 넘기지 않는다).
  final String? videoUrl;
  final String? videoThumbnailUrl;

  const _ImageCarousel({
    required this.imageUrls,
    this.videoUrl,
    this.videoThumbnailUrl,
  });

  bool get _hasVideo => videoUrl != null && videoUrl!.isNotEmpty;

  @override
  State<_ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<_ImageCarousel> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo = widget._hasVideo;
    final totalCount = widget.imageUrls.length + (hasVideo ? 1 : 0);
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: totalCount,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) {
            if (hasVideo && i == widget.imageUrls.length) {
              return GalleryVideoItem(
                videoUrl: widget.videoUrl!,
                thumbnailUrl: widget.videoThumbnailUrl,
              );
            }
            return Image.network(
              widget.imageUrls[i],
              fit: BoxFit.cover,
              errorBuilder: (_, e, st) => Container(
                color: const Color(0xFFFFE0EE),
                child: const Icon(Icons.broken_image_outlined,
                    size: 48, color: Color(0xFFFF6FA0)),
              ),
            );
          },
        ),
        if (totalCount > 1)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                totalCount,
                (i) => Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _index
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
