import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:party_app/models/event_feed.dart';
import 'package:party_app/models/public_event.dart';
import 'package:party_app/widgets/media_gallery.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 🎊 공공 축제 상세 — 한국관광공사 TourAPI(publicEvents) 한 건.
//
// ── 왜 따로 있는가 ───────────────────────────────────────────────────────────
// 플레이스·장소대여·파티 상세는 **파티츄 호스트가 올린 문서**를 그린다 —
// 호스트 정보, 찜, 신고, 예약·신청·문의, 수정 버튼이 전부 그 전제 위에 있다.
// 공공 축제는 호스트가 없는 공공 데이터라 그 화면에 끼워 넣지 않고, 같은 톤
// (고정 흰 앱바 + 원본 비율 미디어 + 흰 정보 판)만 맞춘 읽기 전용 화면을 둔다.
// 신청·문의하기·찜 같은 파티츄 기능은 붙이지 않는다.
//
// ── 읽는 것 ──────────────────────────────────────────────────────────────────
// 목록이 이미 들고 있는 [PublicEvent]를 그대로 받는다 — 들어올 때 Firestore를
// 다시 읽지 않는다. 운영 문서에 실제로 있는 필드만 쓰고, 값이 없는 줄·섹션은
// 자리째 빠진다(빈 줄·'-' 같은 자리표시를 남기지 않는다).
//
// 서버의 상세 보강(소개·프로그램·사진·홈페이지·주최 등)은 매일 호출 예산
// 안에서 차례로 들어가서 **보강 전 문서가 섞여 있을 수 있다.** 보강 전 문서는 그 필드들이 전부
// 비어 있으므로 예전 상세(대표 사진 + 기간·주소·전화)와 똑같이 보인다.
//
// 사진은 원본 그대로 보여준다 — 공공누리 제3유형(변경금지)이라 글자·워터마크를
// 얹지 않고, 출처(한국관광공사)는 화면 아래에 따로 적는다.
//
// 보강 구성 2·3(관람연령·소요시간·예매·할인·부대행사·위치안내·주관 전화·
// 등급·출연진·추가 정보)도 같은 원칙이다 — 값이 있을 때만 줄·섹션이 생긴다.
// 예매는 글자만 있으면 글자만, 안전한 링크가 있을 때만 「예매하기」 버튼이다.
//
// ── 아직 없는 것 ─────────────────────────────────────────────────────────────
// 지도 미리보기·마커·길찾기는 붙이지 않았다(좌표 lat/lng는 모델에 있다). 동영상은
// 원본에 데이터가 없어 만들지 않는다. SNS는 홈페이지 칸에 섞여 오므로 버튼
// 문구만 바꾼다([publicEventHomepageLabel]).
// ─────────────────────────────────────────────────────────────────────────────

const Color _kBg = Color(0xFFFFF4F8);
const Color _kBadgeBg = Color(0xFFE6F6F4);
const Color _kBadgeFg = Color(0xFF16867A);
const Color _kAccent = Color(0xFFFF6FA0);

const TextStyle _kOutlinedTitle = TextStyle(
  fontFamily: 'SeoulHangang',
  fontWeight: FontWeight.w500,
  shadows: [
    Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
    Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
    Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
    Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
  ],
);

const TextStyle _kBody = TextStyle(
  fontSize: 14,
  color: Colors.black87,
  height: 1.5,
);

/// 외부 브라우저로 주소를 연다. 열었으면 true.
typedef PublicEventUrlOpener = Future<bool> Function(Uri uri);

Future<bool> _openExternal(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('[PublicEventDetail] 홈페이지 열기 실패 ($uri): $e');
    return false;
  }
}

class PublicEventDetailScreen extends StatelessWidget {
  const PublicEventDetailScreen({
    super.key,
    required this.event,
    this.openUrl = _openExternal,
  });

  final PublicEvent event;

  /// 홈페이지 열기 — 기본은 외부 브라우저. 테스트가 바꿔 끼운다.
  final PublicEventUrlOpener openUrl;

  @override
  Widget build(BuildContext context) {
    final images = publicEventGalleryImages(event);
    final period = publicEventDetailPeriod(event);
    final place = event.eventPlace;
    final address = publicEventFullAddress(event.address, event.addressDetail);
    final homepage = publicEventHomepageUri(event.homepageUrl);
    final booking = publicEventHomepageUri(event.bookingUrl);
    final overview = event.overview;
    final program = event.program;
    final hasInfo =
        event.organizer != null ||
        event.host != null ||
        event.hostTel != null ||
        event.contactName != null ||
        event.tel != null;

    return Scaffold(
      backgroundColor: _kBg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            elevation: 0,
            title: Text(
              event.title,
              overflow: TextOverflow.ellipsis,
              style: _kOutlinedTitle.copyWith(fontSize: 16),
            ),
          ),
          // 사진 — 다른 상세와 같이 화면 폭 전체, 원본 비율. 여러 장이면
          // 좌우로 넘긴다(자동 넘김은 켜지 않는다).
          SliverToBoxAdapter(
            child: images.isNotEmpty
                ? MediaGallery(
                    key: const ValueKey('publicEventGallery'),
                    images: images,
                    counterAccentColor: _kAccent,
                  )
                : Container(
                    key: const ValueKey('publicEventImagePlaceholder'),
                    width: double.infinity,
                    height: 220,
                    color: _kBadgeBg,
                    child: const Center(
                      child: Icon(
                        Icons.celebration_outlined,
                        size: 64,
                        color: _kBadgeFg,
                      ),
                    ),
                  ),
          ),
          // 머리 판 — 배지·제목·기간·장소·시간·연령·요금·예매 + 예매·홈페이지 버튼.
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _badge(EventFeedKind.publicFestival.badge),
                      // 축제 등급(예 '문화관광축제') — 있을 때만.
                      if (event.festivalGrade != null)
                        _gradeTag(event.festivalGrade!),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    event.title,
                    style: _kOutlinedTitle.copyWith(fontSize: 20),
                  ),
                  if (period.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _infoRow(Icons.event, period),
                  ],
                  // 📍 행사 장소 이름이 있으면 굵게, 그 아래 주소(작게).
                  // 장소 이름이 없으면 주소만(예전 상세와 같다).
                  if (place != null || address.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _placeRow(place, address),
                  ],
                  // 장소 상세 안내(placeinfo) — 장소 줄 아래 한 단 들여서.
                  if (event.placeInfo != null) ...[
                    const SizedBox(height: 6),
                    _subNote(
                      key: const ValueKey('publicEventPlaceInfo'),
                      text: event.placeInfo!,
                    ),
                  ],
                  if (event.playTime != null) ...[
                    const SizedBox(height: 10),
                    _infoRow(Icons.schedule_outlined, event.playTime!),
                  ],
                  if (event.spendTime != null) ...[
                    const SizedBox(height: 10),
                    _infoRow(
                      Icons.timer_outlined,
                      event.spendTime!,
                      label: '소요시간',
                    ),
                  ],
                  if (event.ageLimit != null) ...[
                    const SizedBox(height: 10),
                    _infoRow(
                      Icons.person_outline_rounded,
                      event.ageLimit!,
                      label: '관람연령',
                    ),
                  ],
                  if (event.feeText != null) ...[
                    const SizedBox(height: 10),
                    _infoRow(Icons.payments_outlined, event.feeText!),
                  ],
                  // 할인 정보 — 요금 아래 한 단 들여서(요금이 없어도 보인다).
                  if (event.discountInfo != null) ...[
                    const SizedBox(height: 6),
                    _subNote(
                      key: const ValueKey('publicEventDiscount'),
                      label: '할인',
                      text: event.discountInfo!,
                    ),
                  ],
                  // 🎫 예매 정보 — 링크가 없어도 원문 글자는 보여준다.
                  if (event.bookingInfo != null) ...[
                    const SizedBox(height: 10),
                    _infoRow(
                      Icons.confirmation_number_outlined,
                      event.bookingInfo!,
                      label: '예매',
                    ),
                  ],
                  if (booking != null) ...[
                    const SizedBox(height: 18),
                    _linkButton(
                      context,
                      key: const ValueKey('publicEventBookingButton'),
                      uri: booking,
                      label: '예매하기',
                      icon: Icons.confirmation_number_rounded,
                      color: _kAccent,
                      failMessage: '예매 페이지를 열지 못했어요.',
                    ),
                  ],
                  if (homepage != null) ...[
                    SizedBox(height: booking != null ? 10 : 18),
                    _linkButton(
                      context,
                      key: const ValueKey('publicEventHomepageButton'),
                      uri: homepage,
                      label: publicEventHomepageLabel(homepage),
                      icon: Icons.open_in_new_rounded,
                      color: _kBadgeFg,
                      failMessage: '홈페이지를 열지 못했어요.',
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (overview != null)
            _section(
              key: const ValueKey('publicEventOverview'),
              title: '축제 소개',
              child: SelectableText(overview, style: _kBody),
            ),
          // 🎤 출연진 — detailInfo2 '출연' 줄.
          if (event.performers != null)
            _section(
              key: const ValueKey('publicEventPerformers'),
              title: '🎤 출연진',
              child: SelectableText(event.performers!, style: _kBody),
            ),
          if (program != null)
            _section(
              key: const ValueKey('publicEventProgram'),
              title: '프로그램',
              // 원본 줄바꿈(1. 2. / - 항목)을 그대로 보여준다.
              child: SelectableText(program, style: _kBody),
            ),
          if (event.subEvent != null)
            _section(
              key: const ValueKey('publicEventSubEvent'),
              title: '부대행사',
              child: SelectableText(event.subEvent!, style: _kBody),
            ),
          // detailInfo2의 그 밖의 줄 — 원본 제목 그대로 한 섹션씩.
          for (final (i, item) in event.extraInfo.indexed)
            _section(
              key: ValueKey('publicEventExtra$i'),
              title: item.title,
              child: SelectableText(item.text, style: _kBody),
            ),
          if (hasInfo)
            _section(
              key: const ValueKey('publicEventInfo'),
              title: '행사 정보',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (event.organizer != null)
                    _labeled('주최', [event.organizer!]),
                  // 주관 — 이름 + 주관 쪽 전화(있을 때만).
                  if (event.host != null || event.hostTel != null)
                    _labeled('주관', [
                      if (event.host != null) event.host!,
                      if (event.hostTel != null) event.hostTel!,
                    ]),
                  if (event.contactName != null || event.tel != null)
                    _labeled('문의', [
                      if (event.contactName != null) event.contactName!,
                      if (event.tel != null) event.tel!,
                    ]),
                ],
              ),
            ),
          // 출처 — TourAPI 이용 조건(출처 표시). 정보 판과 떨어뜨려 본문이
          // 아니라 표기임을 드러낸다.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
              child: Text(
                '출처: ${event.attribution}',
                style: const TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 외부로 여는 큰 버튼(예매하기·공식 홈페이지). 열지 못하면 안내만 한다.
  Widget _linkButton(
    BuildContext context, {
    required Key key,
    required Uri uri,
    required String label,
    required IconData icon,
    required Color color,
    required String failMessage,
  }) => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      key: key,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
      onPressed: () async {
        final messenger = ScaffoldMessenger.maybeOf(context);
        final opened = await openUrl(uri);
        if (!opened) {
          messenger?.showSnackBar(
            SnackBar(
              content: Text(failMessage),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    ),
  );

  /// 축제 등급 태그 — 배지 옆의 작은 테두리 글자.
  static Widget _gradeTag(String grade) => Container(
    key: const ValueKey('publicEventGrade'),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _kBadgeFg),
    ),
    child: Text(
      grade,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: _kBadgeFg,
      ),
    ),
  );

  /// 줄 아래 한 단 들인 작은 글(장소 상세 안내·할인 정보).
  static Widget _subNote({
    required Key key,
    required String text,
    String? label,
  }) => Padding(
    key: key,
    padding: const EdgeInsets.only(left: 22),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
              height: 1.4,
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: SelectableText(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black54,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );

  /// 머리 판 아래 흰 섹션 하나 — 제목 + 내용. 판 사이에 틈을 둬 구분한다.
  static Widget _section({
    required Key key,
    required String title,
    required Widget child,
  }) => SliverToBoxAdapter(
    key: key,
    child: Container(
      margin: const EdgeInsets.only(top: 10),
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    ),
  );

  static Widget _badge(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: _kBadgeBg,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: _kBadgeFg,
      ),
    ),
  );

  /// 아이콘 + 값 한 줄. [label]이 있으면 값 앞에 작은 이름을 붙인다
  /// (`60분`·`전 연령`처럼 값만으로는 무엇인지 모를 때).
  static Widget _infoRow(IconData icon, String text, {String? label}) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(icon, size: 16, color: _kAccent),
      ),
      const SizedBox(width: 6),
      if (label != null) ...[
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.black54,
            height: 1.4,
          ),
        ),
        const SizedBox(width: 8),
      ],
      Expanded(
        child: SelectableText(
          text,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black87,
            height: 1.4,
          ),
        ),
      ),
    ],
  );

  static Widget _placeRow(String? place, String address) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 1),
        child: Icon(Icons.location_on_outlined, size: 16, color: _kAccent),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (place != null)
              SelectableText(
                place,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                  height: 1.4,
                ),
              ),
            if (address.isNotEmpty)
              SelectableText(
                address,
                style: place != null
                    ? const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                        height: 1.4,
                      )
                    : const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        height: 1.4,
                      ),
              ),
          ],
        ),
      ),
    ],
  );

  /// '주최  강동구' 같은 한 줄. 값이 여러 개면(문의: 이름 + 전화) 아래로 잇는다.
  static Widget _labeled(String label, List<String> values) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
              height: 1.4,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final v in values)
                SelectableText(
                  v,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                    height: 1.4,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// 갤러리에 넣을 사진들. 보강된 문서는 [PublicEvent.images](대표 사진이 첫
/// 장), 보강 전 문서는 대표 사진 하나(없으면 썸네일). 빈 값과 중복은 뺀다.
/// 주소는 받은 그대로 쓴다(바꿔 끼워 다른 크기를 만들지 않는다).
List<String> publicEventGalleryImages(PublicEvent e) {
  final fallback = e.imageUrl ?? e.thumbnailUrl;
  final source = e.images.isNotEmpty ? e.images : [?fallback];
  final seen = <String>{};
  final out = <String>[];
  for (final raw in source) {
    final url = raw.trim();
    if (url.isEmpty || !seen.add(url)) continue;
    out.add(url);
  }
  return out;
}

/// 홈페이지 버튼 문구 — 원본의 홈페이지 칸에는 SNS 주소도 섞여 온다
/// (2026-09-20 보강 100건 중 인스타그램 12, 네이버 블로그·카페 1씩).
String publicEventHomepageLabel(Uri uri) {
  final host = uri.host.toLowerCase();
  bool on(String domain) => host == domain || host.endsWith('.$domain');
  if (on('instagram.com') || host == 'instagr.am') return '공식 인스타그램';
  if (on('blog.naver.com')) return '공식 블로그';
  if (on('cafe.naver.com')) return '공식 카페';
  return '공식 홈페이지';
}

/// 외부 링크 주소(공식 홈페이지·예매) — http(s)이고 호스트가 있을 때만.
/// 아니면 null(버튼이 빠진다).
Uri? publicEventHomepageUri(String? raw) {
  final s = raw?.trim() ?? '';
  if (s.isEmpty) return null;
  final uri = Uri.tryParse(s);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  return uri;
}

/// 주소 + 상세주소를 한 줄로. 상세주소가 없거나 이미 주소에 들어 있으면
/// 주소만. 둘 다 없으면 ''(줄이 빠진다).
String publicEventFullAddress(String? address, String? detail) {
  final a = address?.trim() ?? '';
  final d = detail?.trim() ?? '';
  if (a.isEmpty) return d;
  if (d.isEmpty || a.contains(d)) return a;
  return '$a $d';
}

/// 상세의 기간 — '2026년 10월 16일 (금) ~ 10월 18일 (일)'. 하루짜리는 한 날짜,
/// 해가 바뀌면 끝 날짜에도 연도를 붙인다. 원본 날짜(YYYYMMDD)를 그대로 읽어
/// 기기 시간대와 무관하게 원본 날짜가 그대로 보인다.
String publicEventDetailPeriod(PublicEvent e) {
  final start = _parse(e.startDate);
  if (start == null) return '';
  final end = _parse(e.endDate);
  String fmt(DateTime d, {required bool year}) =>
      '${year ? '${d.year}년 ' : ''}${d.month}월 ${d.day}일 (${_weekday(d)})';
  final head = fmt(start, year: true);
  if (end == null || end == start) return head;
  return '$head ~ ${fmt(end, year: end.year != start.year)}';
}

DateTime? _parse(String s) {
  if (s.length != 8) return null;
  final y = int.tryParse(s.substring(0, 4));
  final m = int.tryParse(s.substring(4, 6));
  final d = int.tryParse(s.substring(6, 8));
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

String _weekday(DateTime d) =>
    const ['월', '화', '수', '목', '금', '토', '일'][d.weekday - 1];
