import 'package:flutter/material.dart';

import 'package:party_app/models/public_event.dart';
import 'package:party_app/models/region_data.dart';
import 'package:party_app/screens/public_event_detail_screen.dart';
import 'package:party_app/utils/feed_video_manager.dart';
import 'package:party_app/widgets/card_parts.dart';
import 'package:party_app/widgets/list_card_shell.dart';
import 'package:party_app/widgets/web_frame.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 🎊 공공 축제 카드 — 이벤트 피드에서 [PlaceEventCompactCard] 옆에 서는 카드.
//
// ── 왜 따로 있는가 ───────────────────────────────────────────────────────────
// 매장/공간 이벤트 카드는 **원본 매장/공간 문서**에서 사진·이름·지역·찜·이동을
// 가져온다. 공공 축제에는 그 원본이 없다 — 자기 사진·주소·기간을 직접 갖는다.
// 그래서 [PublicEvent]를 그 카드 모양에 억지로 맞추지 않고, 같은 껍데기
// ([ListCardShell])와 같은 조각([cardMiniBadge]·[cardTitleText]·[cardInfoLine])
// 으로 따로 그린다 — 크기·글씨·여백은 이벤트 카드와 같고, 내용만 다르다.
//
//   대표 사진 : 원본 이미지(없으면 작은 이미지 → 자리표시)
//   배지      : 🎊 공공 축제 — 파티츄 이벤트와 색부터 다르다(분홍이 아닌 청록)
//   큰 제목   : 축제 제목(최대 2줄)
//   📍 줄     : 시/도 약칭 + 시군구(예 '서울 강동구', '경기 고양시 일산동구')
//   📅 줄     : 행사 기간(예 '10.16 ~ 10.18')
//   출처 줄   : '출처: 한국관광공사' — TourAPI 이용 조건(출처 표시)
//
// 찜 버튼은 없다 — 찜은 파티/플레이스/장소대여 문서에 붙는 기능이고, 공공
// 축제용 찜 종류는 아직 없다.
//
// ── 누르면 ───────────────────────────────────────────────────────────────────
// 공공 축제 전용 상세([PublicEventDetailScreen])로 간다. 카드가 들고 있는
// [PublicEvent]를 그대로 넘기므로 들어갈 때 Firestore를 다시 읽지 않는다.
// 매장/공간 상세로는 절대 보내지 않는다 — 원본 장소가 없는 데이터다.
// 이동 방식은 다른 카드와 같다(재생 중 카드 영상 멈춤 → [webFramedRoute] push).
// ─────────────────────────────────────────────────────────────────────────────

/// 공공 축제 배지 색 — 파티츄 이벤트(분홍)와 한눈에 갈리게 청록 계열.
const Color _kPublicBadgeBg = Color(0xFFE6F6F4);
const Color _kPublicBadgeFg = Color(0xFF16867A);

class PublicEventCompactCard extends StatelessWidget {
  const PublicEventCompactCard({
    super.key,
    required this.event,
    required this.badge,
    this.onTap,
  });

  final PublicEvent event;

  /// '🎊 공공 축제' — 정본은 `EventFeedKind.publicFestival.badge`.
  final String badge;

  /// 주지 않으면 공공 축제 상세로 간다([openPublicEventDetail]).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final image = event.imageUrl ?? event.thumbnailUrl;
    final where = publicEventAreaLabel(event.address);
    final when = publicEventPeriodLabel(event);

    return ListCardShell(
      onTap: () {
        FeedVideoManager.instance.pauseActive();
        (onTap ?? () => openPublicEventDetail(context, event))();
      },
      child: ListCardShell.horizontalBody(
        thumbnail: ListCardShell.thumbnailBox(
          child: image == null
              ? const _PublicEventThumbPlaceholder()
              : Image.network(
                  image,
                  fit: BoxFit.cover,
                  // 목록 썸네일(104px)에 원본 해상도 전체를 풀어 둘 필요가
                  // 없다 — 카드가 많아도 메모리가 불지 않게 줄여서 푼다.
                  cacheWidth: 320,
                  errorBuilder: (ctx, e, st) =>
                      const _PublicEventThumbPlaceholder(),
                ),
        ),
        info: ListCardShell.infoColumn([
          ListCardShell.badgeWrap([
            cardMiniBadge(
              badge,
              background: _kPublicBadgeBg,
              foreground: _kPublicBadgeFg,
            ),
          ]),
          cardTitleText(event.title, maxLines: 2),
          if (where.isNotEmpty) cardInfoLine(Icons.location_on, where),
          if (when.isNotEmpty) cardInfoLine(Icons.event, when),
          Text(
            '출처: ${event.attribution}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: Colors.black38),
          ),
        ]),
      ),
    );
  }
}

/// 공공 축제 상세로 — 목록의 [PublicEvent]를 그대로 넘긴다(재조회 없음).
void openPublicEventDetail(BuildContext context, PublicEvent event) {
  Navigator.push(
    context,
    webFramedRoute((_) => PublicEventDetailScreen(event: event)),
  );
}

/// 📍 줄 — 시/도 약칭 + 시군구('서울 강동구', '경기 고양시 일산동구').
///
/// 전국 축제라 시/도를 빼면 '남구'·'중구'처럼 어디인지 모르는 이름이 남는다.
/// 시/도 약칭은 앱의 표기표([RegionData.shortenRegionPrefix])를 그대로 쓴다.
String publicEventAreaLabel(String? address) {
  if (address == null || address.trim().isEmpty) return '';
  final tokens = RegionData.shortenRegionPrefix(
    address.trim(),
  ).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (tokens.length <= 2) return tokens.join(' ');
  // '경기 고양시 일산동구'처럼 시 아래 구가 있으면 구까지.
  final third = tokens[2];
  return third.endsWith('구') ? tokens.take(3).join(' ') : tokens.take(2).join(' ');
}

/// 📅 줄 — 원본 날짜(YYYYMMDD) 그대로 'M.D ~ M.D'. 하루짜리는 'M.D' 하나.
/// 올해가 아닌 해가 끼면 연도를 붙인다('2027.1.3 ~ 1.5').
String publicEventPeriodLabel(PublicEvent e, {DateTime? now}) {
  final start = _ymd(e.startDate);
  final end = _ymd(e.endDate);
  if (start == null) return '';
  final thisYear = (now ?? DateTime.now()).year;
  String fmt((int, int, int) d, {required bool withYear}) =>
      withYear ? '${d.$1}.${d.$2}.${d.$3}' : '${d.$2}.${d.$3}';
  final showYear = start.$1 != thisYear || (end != null && end.$1 != thisYear);
  final head = fmt(start, withYear: showYear);
  if (end == null || end == start) return head;
  final tail = fmt(end, withYear: end.$1 != start.$1);
  return '$head ~ $tail';
}

(int, int, int)? _ymd(String s) {
  if (s.length != 8) return null;
  final y = int.tryParse(s.substring(0, 4));
  final m = int.tryParse(s.substring(4, 6));
  final d = int.tryParse(s.substring(6, 8));
  if (y == null || m == null || d == null) return null;
  return (y, m, d);
}

class _PublicEventThumbPlaceholder extends StatelessWidget {
  const _PublicEventThumbPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
    color: _kPublicBadgeBg,
    child: const Center(
      child: Icon(Icons.celebration_outlined, size: 34, color: _kPublicBadgeFg),
    ),
  );
}
