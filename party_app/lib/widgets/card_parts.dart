import 'package:flutter/material.dart';

import 'package:party_app/widgets/favorite_star_button.dart';
import 'package:party_app/widgets/party_card_widget.dart' show feedInfoOverlayBox;

// ─────────────────────────────────────────────────────────────────────────────
// 목록 카드 "조각" 공용 정본 — 껍데기(ListCardShell/GridCardShell)가 카드의
// 크기·여백을 맡는다면, 여기 있는 것들은 그 안에 들어가는 **한 조각**의
// 모양이다: 알약 배지 하나, 제목 한 줄, 아이콘+텍스트 한 줄, 사진 위 찜 버튼,
// 그리고 큰 카드의 하단 오버레이 전체.
//
// ── 왜 모으는가 ──────────────────────────────────────────────────────────────
// 파티·플레이스·장소대여·파티샵이 같은 보기 방식(작은/기본/큰)을 갖는데,
// 각 탭이 같은 값(글자 크기 14, 배지 padding 7×2, 찜 right/top 8 …)을 자기
// 파일에 따로 적어두면 한쪽만 조금씩 어긋난다 — 실제로 파티샵 카드가 그렇게
// 갈라져 있었다(제목에 외곽선이 없고, 찜은 4/4, 지역 글자만 11.5).
//
// 셸이 "카드가 얼마만 한가"를 고정하듯, 여기서는 "그 안의 글씨·배지가 어떻게
// 생겼는가"를 고정한다. 값을 고치면 네 탭이 함께 바뀐다.
// ─────────────────────────────────────────────────────────────────────────────

/// 유형·테마·혜택 같은 작은 알약 배지 — 작은/기본/큰 카드가 모두 이 모양이다.
Widget cardMiniBadge(
  String label, {
  Color background = const Color(0xFFFFF0F5),
  Color foreground = const Color(0xFFFF6FA0),
}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
  decoration: BoxDecoration(
    color: background,
    borderRadius: BorderRadius.circular(20),
  ),
  child: Text(
    label,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: foreground,
    ),
  ),
);

/// 카드 제목(파티 제목 / 장소명 / 샵 이름) — 같은 서체·크기·외곽선.
///
/// [maxLines]는 이벤트 카드만 2로 쓴다 — 거기서는 이 자리가 장소명이 아니라
/// **이벤트 제목**이라 한 줄로 자르면 앞 몇 글자만 남는다. 장소·샵 카드는 한
/// 줄이다(카드 높이가 문서마다 들쭉날쭉해지지 않게).
Widget cardTitleText(String name, {int maxLines = 1}) => Text(
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
  maxLines: maxLines,
  overflow: TextOverflow.ellipsis,
);

/// 아이콘 + 텍스트 한 줄 — 날짜/지역/요금 줄이 모두 이 크기·색이다.
///
/// 값이 없어도 **줄 자체는 남는다**(아이콘만 투명해진다). 기본 카드의 정보
/// 열은 값이 있든 없든 줄 수가 같아야 2열 그리드에서 좌우 카드의 아래끝이
/// 어긋나지 않기 때문이다.
Widget cardInfoLine(IconData icon, String text, {bool expand = true}) {
  final label = Text(
    text,
    style: const TextStyle(fontSize: 11, color: Colors.black45),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
  return Row(
    children: [
      Opacity(
        opacity: text.isEmpty ? 0 : 1,
        child: Icon(icon, size: 11, color: const Color(0xFFFF6FA0)),
      ),
      const SizedBox(width: 4),
      if (expand) Expanded(child: label) else label,
    ],
  );
}

/// 미디어 위 오른쪽 위에 얹는 찜 버튼 — 작은 카드·기본 카드가 같은 자리다.
///
/// 찜 종류만 컬렉션에 따라 갈린다(파티/플레이스/장소대여/파티샵) — 기존 찜
/// 목록과 어긋나지 않도록 반드시 그 카드가 원래 쓰던 타입을 그대로 넘긴다.
Widget cardFavoriteOverlay({
  required String itemType,
  required String itemId,
}) => Positioned(
  right: 8,
  top: 8,
  child: FavoriteStarButton(
    itemType: itemType,
    itemId: itemId,
    size: 20,
    dense: true,
    unfavoritedColor: Colors.white,
    glow: false,
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// 큰 카드 — 대표 미디어를 카드 전체에 깔고 아래쪽 그라디언트 위에 정보를
// 얹는 구조. 파티 큰 카드(PartyVideoFeedCard)가 처음 만든 모양을 플레이스
// (PlaceLargeCard)와 파티샵(ShopLargeCard)이 **같은 함수로** 그린다.
//
// 여기 있는 값(여백 18/72/18/22, 배지 간격 6, 제목 20pt, 줄 간격 6/12/14)은
// 세 탭이 공유하는 정본이다 — 한 탭만 고치면 목록을 오갈 때 글씨 위치가
// 미묘하게 튄다.
// ─────────────────────────────────────────────────────────────────────────────

/// 큰 카드 본문 — [media]를 배경으로 깔고 하단 오버레이를 얹는다.
///
/// 크기를 스스로 정하지 않는다: 전체화면 피드에서는 화면 한 장을, 목록 안에
/// 놓일 때는 부르는 쪽이 정한 높이를 그대로 채운다.
Widget largeCardBody({
  required Widget media,
  required List<Widget> badges,
  required String title,
  required Widget info,
  Widget? seekBar,
  required Widget actions,
}) => ColoredBox(
  color: Colors.black,
  child: Stack(
    fit: StackFit.expand,
    children: [
      media,
      // 하단 정보 오버레이 — 이 영역에는 GestureDetector가 없어서(상세보기
      // 버튼 제외) 탭이 그대로 아래 영상으로 전달된다.
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 72, 18, 22),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xCC000000)],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 배지 목록은 작은/기본 카드와 **완전히 같은 것**을 받는다.
              if (badges.isNotEmpty) ...[
                Wrap(spacing: 6, runSpacing: 6, children: badges),
                const SizedBox(height: 10),
              ],
              feedInfoOverlayBox(
                child: Text(
                  title,
                  style: largeCardTitleStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 6),
              feedInfoOverlayBox(child: info),
              // 진행바는 실제 동영상이 재생 중일 때만 — 정보 박스 바깥,
              // 버튼 위에 둔다.
              if (seekBar != null) ...[
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: seekBar),
              ],
              const SizedBox(height: 14),
              actions,
            ],
          ),
        ),
      ),
    ],
  ),
);

/// 큰 카드 제목 — 어두운 배경 위라 색과 크기만 다르고 서체는 카드 제목과 같다.
const TextStyle largeCardTitleStyle = TextStyle(
  fontFamily: 'SeoulHangang',
  fontSize: 20,
  fontWeight: FontWeight.w500,
  color: Colors.white,
  shadows: [
    Shadow(color: Colors.white, offset: Offset(0.3, 0)),
    Shadow(color: Colors.white, offset: Offset(-0.3, 0)),
    Shadow(color: Colors.white, offset: Offset(0, 0.3)),
    Shadow(color: Colors.white, offset: Offset(0, -0.3)),
  ],
);

/// 큰 카드 정보 한 줄 — 작은/기본 카드의 [cardInfoLine]과 같은 구성이지만
/// 어두운 배경 위라 색과 크기만 다르다.
Widget largeCardInfoLine(IconData icon, String text) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Icon(icon, size: 14, color: Colors.white70),
    const SizedBox(width: 4),
    Flexible(
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: Colors.white),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ],
);

/// 큰 카드 오른쪽 열의 강조 숫자(이용요금 / 최저가) — 같은 크기·색.
Widget largeCardPriceText(String label) => Text(
  label,
  style: const TextStyle(
    fontSize: 15,
    color: Color(0xFFFFB6D0),
    fontWeight: FontWeight.w800,
  ),
);

/// 큰 카드 "상세보기" 버튼 — 세 탭이 같은 모양·같은 자리를 쓴다.
Widget largeCardDetailButton({required VoidCallback onPressed}) =>
    OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white70),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      child: const Text(
        '상세보기',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
