import 'package:flutter/material.dart';

import 'package:party_app/models/party_pricing.dart';
import 'package:party_app/screens/party_detail_screen.dart';
import 'package:party_app/utils/card_media_frame.dart';
import 'package:party_app/utils/feed_video_manager.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/widgets/offering_card_shell.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/widgets/partychu_ui.dart';
import 'package:party_app/widgets/web_frame.dart';

/// "이곳에서 열리는 파티" 목록의 카드 한 장 — 대표사진과 파티명/일정/참가비를
/// 요약해 보여주고 파티 상세로 이동한다.
///
/// 플레이스(events) 상세와 공간대여(places) 상세가 **같은 카드**를 쓴다.
/// 두 화면 모두 "이 장소에 연결된 파티"라는 같은 것을 보여주므로, 한쪽만
/// 모양이 달라지지 않도록 위젯을 한 곳에 둔다.
///
/// ## 대표사진은 "기본 카드"와 정확히 같다
///
/// 사진 선택·크롭·동영상 처리는 [partyBasicCardMedia] 하나가 정한다 — 파티
/// 목록의 기본 카드([PartyStandardCard])가 쓰는 바로 그 함수다. 그래서 등록/
/// 수정 화면에서 썸네일 위치를 옮기면 **목록 카드와 이 카드가 같은 자리로**
/// 움직인다. 여기에 별도의 대표사진 필드나 크롭 좌표를 만들지 않는다.
///
/// 사진 상자의 비율도 기본 카드와 같은 [basicCardMediaAspectRatio]다. 크롭
/// 값(`basicCardPhotoCrops` 등)이 그 비율을 전제로 저장돼 있으므로, 다른
/// 비율의 상자에 넣으면 사용자가 맞춘 자리와 다르게 잘린다 — 매장 이벤트
/// 카드가 크롭을 일부러 적용하지 않는 이유와 같은 이야기다.
///
/// 원본 비율대로 늘어나는 갤러리형 표시(MediaGallery)는 쓰지 않는다. 여기는
/// 반 폭 열에 서는 **썸네일 카드**라, 세로로 긴 사진 하나 때문에 카드가
/// 길어지면 옆 열과 완전히 어긋난다.
///
/// ## 모집상태 배지를 그리지 않는 이유
///
/// [PartyCard.effectiveStatus]는 **회차 하나**를 기준으로 상태를 낸다. 매일·
/// 상시 반복 파티는 지금 회차의 모집이 닫혀도 다음 회차가 계속 열리는데,
/// 장소 상세에 '모집마감' 배지가 붙으면 "이 파티는 이제 안 열린다"로 읽힌다.
/// 여기는 장소를 보러 온 사람에게 "이런 파티가 열린다"를 알리는 자리이므로,
/// 회차별 모집 여부는 파티 상세에서 정확한 회차와 함께 보게 한다.
///
/// 판정 로직은 그대로 살아 있다 — 목록·검색 카드와 파티 상세는 예전처럼
/// 배지를 그린다. 여기서만 **렌더링을 하지 않을 뿐**이다.
class LinkedPartyCard extends StatelessWidget {
  final String partyId;
  final Map<String, dynamic> party;

  const LinkedPartyCard({
    super.key,
    required this.partyId,
    required this.party,
  });

  @override
  Widget build(BuildContext context) {
    final title = party['title'] as String? ?? '파티';
    final date = PartyCard.formatDate(party);
    // 대표 참가비(남녀가 다르면 낮은 쪽) — 목록 카드와 동일한 규칙.
    final fee = PartyPricing.fromMap(party).displayPrice;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OfferingCardShell(
        // 외곽선은 **파티츄 핑크 계열**이다([PartyChuColors.border]) — 플레이스
        // 상세에서 이 카드가 ✨ 매장 이벤트 카드(샴페인 골드 선)와 나란히
        // 서므로, 두 열이 각각 무엇인지 테두리 색만으로 갈린다.
        borderColor: PartyChuColors.border,
        background: const Color(0xFFF3EFFA),
        onTap: () => _open(context),
        // 기본 카드와 **같은 함수·같은 비율** — 위 클래스 주석 참고.
        media: partyBasicCardMedia(party, tag: 'LinkedPartyCard'),
        mediaAspectRatio: basicCardMediaAspectRatio(context),
        mediaOverlays: [
          // 숙박+파티 콤보 배지 — 기본 카드와 같은 자리(우상단)·같은 배지다.
          if (PartyCard.isStayPartyCombo(party))
            Positioned(
              right: 8,
              top: 8,
              child: PartyCard.stayPartyComboBadge(),
            ),
        ],
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 제목만 — 오른쪽에 모집상태 배지를 붙이지 않는다
            // (클래스 주석의 '모집상태 배지를 그리지 않는 이유' 참고).
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
              // 반 폭 열에서는 한 줄에 예닐곱 자밖에 들어가지 않아 제목이
              // 거의 남지 않는다. 두 줄까지 허용하고 그 뒤로만 줄인다.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (date.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  '일정 : $date',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
              ),
            if (fee > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '참가비 : ${formatPrice(fee)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
              ),
            const SizedBox(height: 9),
            // 매장 이벤트 카드와 **같은 부품**([OfferingCardMoreLink])이라
            // 두 열의 CTA가 같은 자리에서 같은 모양으로 끝난다. 카드 전체가
            // 탭 영역이라(위 [OfferingCardShell.onTap]) 이 줄이 작아도
            // 실제로 눌리는 면적은 카드 한 장 전체다.
            const OfferingCardMoreLink(color: PartyChuColors.primary),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    // 상세로 넘어가면 카드에서 재생 중이던 동영상을 즉시 정지 — 기본 카드가
    // 쓰는 것과 같은 규칙이다(화면 전환 중 소리가 새어나가지 않게).
    FeedVideoManager.instance.pauseActive();
    Navigator.push(
      context,
      webFramedRoute((_) => PartyDetailScreen(docId: partyId)),
    );
  }
}

/// 연결된 파티로 넘어가는 **주 행동 버튼**.
///
/// 공간대여 상세의 "숙박+파티" 콤보 카드가 쓴다 — 그 카드는 상세 본문 전체
/// 폭을 쓰는 큰 카드라, 반 폭 열의 요약 카드([LinkedPartyCard])와 달리
/// 하단 full-width CTA가 필요하다(예약 버튼과 같은 급의 행동이다).
///
/// 색은 파티츄 메인 포인트 컬러([PartyChuColors.primary])다. 카드 배경이
/// 연보라라 보조 액션은 보라 계열을 쓰는데, 이 버튼만 브랜드 핑크로 채워
/// 카드 안에서 우선순위가 한눈에 갈리게 한다.
class LinkedPartyDetailButton extends StatelessWidget {
  final VoidCallback onPressed;

  const LinkedPartyDetailButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: PartyChuColors.primary,
          foregroundColor: Colors.white,
          // 48은 터치 목표 권장 최소치다 — 예전 텍스트 링크는 실제 터치
          // 영역이 글자 높이뿐이라 자주 빗나갔다.
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        // 좁은 칸에서는 글자와 화살표를 합친 폭이 버튼을 넘는다. 줄바꿈하거나
        // 넘치게 두지 않고 **통째로 조금 줄인다** — 호스트 진입점 버튼이 쓰는
        // 것과 같은 방법이다.
        child: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '파티 상세보기',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
