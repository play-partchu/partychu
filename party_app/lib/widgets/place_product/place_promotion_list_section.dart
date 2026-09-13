import 'package:flutter/material.dart';

import 'package:party_app/models/host_offering.dart';
import 'package:party_app/models/place_event_time.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/screens/party_register_screen.dart';
import 'package:party_app/services/party_create_eligibility.dart';
import 'package:party_app/services/place_event_entry.dart';
import 'package:party_app/services/place_party_link_service.dart';
import 'package:party_app/services/place_promotion_service.dart';
import 'package:party_app/utils/card_media_frame.dart';
import 'package:party_app/utils/party_utils.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/offering_card_shell.dart';
import 'package:party_app/widgets/partychu_ui.dart';
import 'package:party_app/widgets/place_product/place_promotion_detail_sheet.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 플레이스/숙박 상세의 "🎪 매장 이벤트" 영역.
///
/// 여기 뜨는 것은 **매장이 주체가 되어 여는 행사·프로모션·혜택**이다
/// ([HostOffering]) — 참가자를 모집하는 🎉 파티는 같은 상세의 '연결 파티'
/// 영역이 따로 보여준다.
///
/// 상품 영역([PlaceProductListSection])과 **분리해서** 보여준다 — 결제가 없는
/// 홍보이므로 가격·남은 수량·구매 버튼이 없고, 결제가 필요한 내용은 상세
/// 시트에서 연결된 상품으로 넘어간다.
///
/// 카드를 눌러도 **다른 게시글로 이동하지 않는다** — 지금 화면 위에 바텀시트
/// ([showPlacePromotionDetailSheet])를 띄우고, 닫으면 원래 상세 그대로다.
///
/// 이벤트가 하나도 없으면 영역 자체를 그리지 않는다(기존 장소의 상세 화면이
/// 지금과 똑같이 보이도록). 단 **호스트 본인**에게는 비어 있어도 이벤트를
/// 추가할 수 있는 진입점을 보여준다.
///
/// 호스트 진입점은 두 버튼 한 줄이다 — "파티 추가"와 "이벤트 · 혜택 추가".
/// 둘 다 이 장소에 무언가를 더하는 같은 급의 행동이라 1:1로 나란히 둔다.
/// 파티 추가는 **연결 관리 화면의 '새 파티 만들기'와 완전히 같은 흐름**이다 —
/// 정본 등록 화면([PartyRegisterScreen.forLink])을 열고 지금 보고 있는
/// 플레이스·공간대여를 연결 대상으로 넘길 뿐, 등록/연결 로직은 하나도 새로
/// 만들지 않는다.
class PlacePromotionListSection extends StatelessWidget {
  const PlacePromotionListSection({
    super.key,
    required this.placeId,
    required this.accent,
    // 🎪 이 영역이 보여주는 것은 **매장 이벤트**다([HostOffering.placeEvent]) —
    // 매장이 여는 행사·프로모션·혜택. 참가자를 모집하는 파티는 이 아래 '연결
    // 파티' 영역이 따로 보여준다.
    this.title = kPlaceEventLabel,
    this.placeCollection,
    this.hostId,
    this.placeName,
    this.placeData,
    this.onPartyLinked,
  });

  final String placeId;
  final Color accent;
  final String title;

  /// 'events'(플레이스) 또는 'places'(장소대여·숙박).
  /// 호스트 진입점을 그리려면 필요하다 — 없으면 손님 화면만 그린다.
  final String? placeCollection;
  final String? hostId;
  final String? placeName;

  /// 이 장소의 문서 데이터 — "파티 추가"가 연결 대상으로 그대로 넘긴다
  /// (주소·좌표·대표이미지 복사와 소유자 검사에 필요하다).
  /// null이면 "파티 추가" 없이 기존과 같은 이벤트 진입점만 그린다.
  final Map<String, dynamic>? placeData;

  /// 새 파티가 이 장소에 연결된 뒤 — 상세 화면이 연결 파티 목록을 다시 읽는다.
  final VoidCallback? onPartyLinked;

  /// 이벤트 문의 채팅방에 걸릴 호스트 표시 이름 — 판정은
  /// [placeEventHostNameOf] 하나다(탭 영역도 같은 함수를 쓴다).
  String get _hostName => placeEventHostNameOf(placeData);

  bool get _isHost => PlaceOfferingHostActions.isHostOf(
    hostId: hostId,
    placeCollection: placeCollection,
  );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PlacePromotion>>(
      stream: PlacePromotionService.watchPublicForPlace(placeId),
      builder: (context, snap) {
        // 로딩/오류 때는 영역을 감춘다 — 상세의 다른 정보를 가리지 않는 게
        // 더 중요하고, 이벤트는 부가 정보다(상품 영역과 같은 방침).
        final promotions = snap.data ?? const <PlacePromotion>[];
        final hostActions = PlaceOfferingHostActions(
          placeId: placeId,
          accent: accent,
          placeCollection: placeCollection,
          hostId: hostId,
          placeName: placeName,
          placeData: placeData,
          onPartyLinked: onPartyLinked,
        );
        if (promotions.isEmpty) {
          // 손님에게는 빈 영역을 보여주지 않는다. 호스트에게만 진입점.
          return _isHost ? hostActions : const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(kPlaceEventEmoji, style: TextStyle(fontSize: 17)),
                const SizedBox(width: 7),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  '${promotions.length}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const Spacer(),
                if (_isHost)
                  PlaceEventManageButton(
                    placeId: placeId,
                    placeCollection: placeCollection!,
                    hostId: hostId!,
                    placeName: placeName,
                    accent: accent,
                  ),
              ],
            ),
            // 이 영역이 답하는 질문 — 게스트에게 매장 이벤트가 무엇인지
            // 설명하는 가장 짧은 방법이다([HostOffering.guestQuestion]).
            // 참가 신청을 받는 모임은 아래 '연결 파티'가 답한다.
            const SizedBox(height: 3),
            Text(
              HostOffering.placeEvent.guestQuestion,
              style: const TextStyle(fontSize: 11.5, color: Colors.black38),
            ),
            const SizedBox(height: 12),
            PlacePromotionCardList(
              promotions: promotions,
              accent: accent,
              hostName: _hostName,
            ),
            // 이벤트가 이미 있는 장소에서도 호스트는 같은 자리에서 파티를
            // 더할 수 있어야 한다 — 목록 아래에 같은 줄을 그대로 둔다.
            if (_isHost) ...[const SizedBox(height: 12), hostActions],
          ],
        );
      },
    );
  }
}

/// ✨ 매장 이벤트 카드 목록 — **카드를 어떻게 늘어놓는지**만 아는 부품.
///
/// 목록을 읽어 오는 일(스트림)도, 제목·개수 줄도 여기에는 없다. 그래서
/// 기존 [PlacePromotionListSection](제목 + 목록)과, 파티와 한 영역으로 묶인
/// 2열 영역([PlaceOfferingBoard] — 제목 자리를 열 머리가 대신한다)이 **같은
/// 카드**를 쓰면서도 머리 부분만 다르게 그릴 수 있다. 카드를 복제하지 않는다.
class PlacePromotionCardList extends StatelessWidget {
  const PlacePromotionCardList({
    super.key,
    required this.promotions,
    required this.accent,
    required this.hostName,
    this.axis = Axis.horizontal,
  });

  final List<PlacePromotion> promotions;
  final Color accent;

  /// 상세 시트에서 문의 채팅방에 걸릴 호스트 표시 이름
  /// ([placeEventHostNameOf]로 만든 값).
  final String hostName;

  /// 여러 건을 **어느 쪽으로 늘어놓을지**.
  ///
  ///  · [Axis.horizontal] (기본) — 한 줄 전체 폭을 쓰는 영역
  ///    ([PlacePromotionListSection])에서 가로 스크롤. 세로로 길게 쌓여 상세의
  ///    나머지 정보를 아래로 밀어내지 않는다.
  ///  · [Axis.vertical] — 파티와 나란한 **반 폭 열**
  ///    ([PlaceOfferingBoard])에서. 좁은 칸에서 가로로 밀면 카드가 칸 밖으로
  ///    나가므로 그 자리에서는 세로로 쌓는다.
  ///
  /// 카드 자체는 어느 쪽이든 같은 [_PromotionCard] 하나다.
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    if (promotions.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    if (axis == Axis.vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < promotions.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _card(context, promotions[i], now),
          ],
        ],
      );
    }
    if (promotions.length == 1) {
      return _card(context, promotions.first, now);
    }
    // 높이는 **가장 큰 카드가 정한다**([IntrinsicHeight]).
    //
    // 예전에는 214로 못 박혀 있었다. 제목이 두 줄로 접히거나 혜택 문구가
    // 붙은 카드는 그 높이를 넘겨 아래가 잘렸다(BOTTOM OVERFLOWED BY …).
    // 숫자를 키우는 것은 같은 함정을 다음 글자 수까지만 미루는 일이라 고정
    // 높이 자체를 없앤다 — 카드는 자기 내용만큼 자라고, 한 줄에 선 카드들은
    // 그중 가장 큰 높이로 나란히 선다(stretch).
    final cardWidth = MediaQuery.of(context).size.width * 0.72;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < promotions.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              SizedBox(
                width: cardWidth,
                child: _card(context, promotions[i], now, width: cardWidth),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context,
    PlacePromotion p,
    DateTime now, {
    double? width,
  }) => _PromotionCard(
    promotion: p,
    accent: accent,
    width: width,
    status: p.statusAt(now),
    now: now,
    onTap: () => showPlacePromotionDetailSheet(
      context,
      promotion: p,
      accent: accent,
      hostName: hostName,
    ),
  );
}

/// 이벤트 문의 채팅방에 걸릴 호스트 표시 이름.
///
/// placePromotions 문서에는 hostName이 없어서, 서버는 앱이 보낸 값을
/// 폴백으로 쓴다(없으면 그냥 '호스트'). 플레이스·장소대여 상세가 이미
/// 쓰는 것과 **같은 출처**(원본 장소 문서의 hostName)를 그대로 넘겨,
/// 같은 호스트가 경로에 따라 다른 이름으로 보이지 않게 한다.
String placeEventHostNameOf(Map<String, dynamic>? placeData) =>
    (placeData?['hostName'] as String?)?.trim().isNotEmpty == true
    ? placeData!['hostName'] as String
    : '호스트';

/// 매장 이벤트 관리 화면을 여는 유일한 길 — 목록 머리의 '매장 이벤트 관리'
/// 버튼과 호스트 진입점의 '✨ 매장 이벤트 추가' 버튼이 이 함수를 함께 쓴다.
void openPlaceEventManage(
  BuildContext context, {
  required String placeId,
  required String placeCollection,
  required String hostId,
  String? placeName,
}) {
  // 이벤트 화면을 여는 길은 등록 화면·마이페이지와 함께 [PlaceEventEntry]
  // 하나로 모은다(강조색도 공간 유형 정본에서 온다 — 이 위젯을 쓰는 두
  // 상세 화면이 넘기던 색과 같은 값이다).
  PlaceEventEntry.openManage(
    context,
    EventPlaceTarget(
      placeId: placeId,
      placeCollection: placeCollection,
      hostId: hostId,
      placeName: placeName ?? '내 장소',
    ),
  );
}

/// **호스트에게만** 보이는 '매장 이벤트 관리' 텍스트 버튼.
class PlaceEventManageButton extends StatelessWidget {
  const PlaceEventManageButton({
    super.key,
    required this.placeId,
    required this.placeCollection,
    required this.hostId,
    required this.accent,
    this.placeName,
  });

  final String placeId;
  final String placeCollection;
  final String hostId;
  final Color accent;
  final String? placeName;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => openPlaceEventManage(
      context,
      placeId: placeId,
      placeCollection: placeCollection,
      hostId: hostId,
      placeName: placeName,
    ),
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: accent,
    ),
    child: const Text(
      '매장 이벤트 관리',
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}

/// **호스트에게만** 보이는 진입점 한 줄 — 파티 추가 / 매장 이벤트 추가.
///
/// 두 버튼은 [_hostActionButton] 하나로 그려서 높이·테두리·라운드·글자
/// 크기·색이 정확히 같다. 폭은 [Expanded]로 1:1이고, 글자는 좁은 화면에서
/// 잘리는 대신 줄어든다(FittedBox) — 320dp 폭에서도 넘치지 않는다.
///
/// [placeData]가 없으면(호출부가 아직 안 넘긴 화면) 예전처럼 이벤트 버튼
/// 하나만 가로로 꽉 채운다.
///
/// 이벤트 목록([PlacePromotionListSection])과 파티·이벤트 2열 영역
/// ([PlaceOfferingBoard])이 **같은 줄**을 쓴다 — 호스트가 보는 진입점이
/// 화면 구조에 따라 달라지지 않게.
class PlaceOfferingHostActions extends StatelessWidget {
  const PlaceOfferingHostActions({
    super.key,
    required this.placeId,
    required this.accent,
    this.placeCollection,
    this.hostId,
    this.placeName,
    this.placeData,
    this.onPartyLinked,
  });

  final String placeId;
  final Color accent;
  final String? placeCollection;
  final String? hostId;
  final String? placeName;
  final Map<String, dynamic>? placeData;
  final VoidCallback? onPartyLinked;

  /// 지금 보는 사람이 이 장소의 호스트인지 — 진입점을 그릴지 판정하는 정본.
  /// 컬렉션 이름을 모르면(호출부가 안 넘긴 화면) 관리 화면을 열 수 없으므로
  /// 호스트로 보지 않는다.
  static bool isHostOf({
    required String? hostId,
    required String? placeCollection,
  }) =>
      hostId != null &&
      hostId.isNotEmpty &&
      placeCollection != null &&
      UserSession.userId.isNotEmpty &&
      UserSession.userId == hostId;

  /// 파티를 붙일 대상 종류 — 컬렉션 이름이 곧 종류다(연결 필드도 여기서
  /// 갈린다: events → linkedEventId, places → linkedPlaceId).
  PartyLinkTarget get _linkTarget => placeCollection == 'places'
      ? PartyLinkTarget.rental
      : PartyLinkTarget.place;

  /// 호스트가 "파티 추가"를 눌렀을 때 — 연결 대상이 고정된 등록 화면을 연다.
  ///
  /// 등록이 취소되거나 실패하면 아무것도 만들어지지 않고(그때는 pop 값이 null),
  /// 등록만 되고 연결에 실패하면 0이 온다 — 그 경우 안내는 등록 화면이 이미
  /// 했으므로 여기서는 목록만 다시 읽는다.
  Future<void> _openPartyRegister(BuildContext context) async {
    final data = placeData;
    if (data == null) return;
    // 새 파티를 만드는 길이라 등록 화면과 같은 관문을 지난다.
    if (!await PartyCreateEligibility.ensure(context)) return;
    if (!context.mounted) return;
    final linkedCount = await Navigator.push<int>(
      context,
      webFramedRoute(
        (_) => PartyRegisterScreen.forLink(
          target: PartyPrelinkTarget(
            target: _linkTarget,
            targetId: placeId,
            data: data,
          ),
        ),
      ),
    );
    if (linkedCount == null || !context.mounted) return;
    if (linkedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('새 파티를 만들어 이 ${_linkTarget.noun}에 연결했어요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    onPartyLinked?.call();
  }

  @override
  Widget build(BuildContext context) {
    final canAddParty = placeData != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          if (canAddParty) ...[
            Expanded(
              child: _hostActionButton(
                // 두 버튼이 곧 두 개념이다 — 참가자를 모집하면 🎉 파티,
                // 매장이 여는 행사·혜택이면 ✨ 매장 이벤트([HostOffering]).
                label: '${HostOffering.party.emoji} 파티 추가',
                onPressed: () => _openPartyRegister(context),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: _hostActionButton(
              label: '${HostOffering.placeEvent.emoji} 매장 이벤트 추가',
              onPressed: () => openPlaceEventManage(
                context,
                placeId: placeId,
                placeCollection: placeCollection!,
                hostId: hostId!,
                placeName: placeName,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hostActionButton({
    required String label,
    required VoidCallback onPressed,
  }) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.add, size: 18),
    label: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
    ),
    style: OutlinedButton.styleFrom(
      foregroundColor: accent,
      side: BorderSide(color: accent.withValues(alpha: 0.45)),
      minimumSize: const Size(0, 46),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// 이 폭보다 좁으면 카드를 좁은 모양으로 그린다.
///
/// 기준을 잡은 근거: 360dp 화면에서 상세 본문 좌우 여백을 뺀 전체 폭 카드는
/// 320, 가로 스크롤 카드는 259(화면의 0.72), 파티와 나란한 반 폭 열은 155다.
/// 그 사이 어디에 선을 그어도 되지만, 200이면 앞의 둘은 넓은 모양 그대로 두고
/// 반 폭 열만 좁은 모양으로 갈린다.
const double _kNarrowCardWidth = 200;

class _PromotionCard extends StatelessWidget {
  const _PromotionCard({
    required this.promotion,
    required this.accent,
    required this.status,
    required this.now,
    required this.onTap,
    this.width,
  });

  final PlacePromotion promotion;
  final Color accent;
  final PromotionStatus status;

  /// 신청 가능 여부를 [status]와 **같은 기준 시각**으로 판정하기 위해 함께 받는다.
  final DateTime now;

  final VoidCallback onTap;

  /// 목록이 **이미 정해 준 카드 폭**. 넘어오면 [LayoutBuilder] 없이 그 값으로
  /// 모양을 정한다 — 고유 높이를 재는 자리([IntrinsicHeight] 아래의 가로
  /// 스크롤)에서는 LayoutBuilder가 높이를 물어보면 답할 수 없기 때문이다.
  /// 넘어오는 것은 폭 하나뿐이고 좁은 모양인지의 기준은 여전히
  /// [_kNarrowCardWidth] 한 곳이라, 부르는 자리마다 판단이 갈리지 않는다.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final known = width;
    if (known != null) {
      return _body(context, narrow: known < _kNarrowCardWidth);
    }
    // 카드는 **자기 폭을 보고** 모양을 정한다. 한 줄을 혼자 쓰는 자리(가로
    // 스크롤·전체 폭 열)와 파티와 나란한 반 폭 열에서 폭이 두 배 넘게 차이
    // 나는데, 값을 바깥에서 플래그로 받으면 부르는 자리마다 판단이 갈린다.
    // 좁아지면 사진을 21:9 대신 16:9로 세우고(반 폭에서 21:9는 띠처럼 얇다)
    // 안쪽 여백을 한 단계 줄인다.
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < _kNarrowCardWidth;
        return _body(context, narrow: narrow);
      },
    );
  }

  Widget _body(BuildContext context, {required bool narrow}) {
    final p = promotion;
    final images = p.allImageUrls;
    // 카드에는 썸네일 한 장만 — **호스트가 지정한 대표**를 쓴다.
    //
    // 판정은 파티·플레이스 카드와 **같은 함수 하나**를 지난다
    // ([getPartyCoverMedia] + [PlacePromotion.coverMediaMap]). 예전에는 여기만
    // "영상이 있으면 무조건 영상 썸네일, 없으면 첫 사진"이라고 따로 적혀 있어서,
    // 호스트가 사진을 대표로 골라 저장해도(coverMediaType: 'image') 카드에는
    // 영상 썸네일이 계속 나왔다 — 대표 지정이 상세에만 먹고 카드에는 안 먹었다.
    //
    // 대표를 한 번도 안 정한 옛 이벤트는 그 함수의 하위호환 분기가 예전 규칙
    // (사진 먼저 → 없으면 영상 썸네일)을 그대로 태운다.
    //
    // ⚠️ 크롭(basicCardPhotoCrops)은 여기서 적용하지 않는다 — 그 값은 2열
    //    기본 카드 전용 비율에 맞춰 지정된 것이라(card_media_frame.dart) 21:9
    //    /16:9인 이 카드에 그대로 쓰면 사용자가 맞춘 자리와 다르게 잘린다.
    final cover = getPartyCoverMedia(p.coverMediaMap, tag: 'PlaceEventCard');
    final thumb = [
      cover?.thumbnailUrl ?? '',
      cover?.imageUrl ?? '',
      images.isNotEmpty ? images.first : '',
    ].firstWhere((s) => s.isNotEmpty, orElse: () => '');
    final when = [
      if (p.isAlways) '상시 진행',
      if (p.periodLabel != null) p.periodLabel!,
    ].join(' · ');

    // 카드 껍데기(테두리·라운드·사진 자리·안쪽 여백)는 🎉 파티 카드와
    // **같은 부품**([OfferingCardShell])이다 — 두 카드가 나란히 서는 자리라
    // 모서리와 사진 자리가 어긋나면 서로 다른 물건 두 개로 보인다.
    // 색만 다르다: 바깥선 **하나**가 샴페인 골드([PartyChuColors.eventGold])다
    // (등록 화면의 파티츄 오픈혜택 안내와 같은 선 = 혜택·이벤트 계열이라는 표시).
    return OfferingCardShell(
      borderColor: PartyChuColors.eventGold,
      onTap: onTap,
      media: thumb.isEmpty
          ? null
          : Image.network(
              thumb,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  Container(color: const Color(0xFFF3F4F8)),
            ),
      // 반 폭 열에서 21:9는 띠처럼 얇아져 무슨 사진인지 안 읽힌다. 그 자리에서는
      // 옆에 선 🎉 파티 카드와 **같은 비율**(기본 카드 비율)을 쓴다 — 두 열의
      // 사진 높이가 다르면 한 영역 안에서 크기 균형이 깨진다.
      mediaAspectRatio: narrow ? basicCardMediaAspectRatio(context) : 21 / 9,
      mediaOverlays: [
        if (p.hasVideo)
          const Positioned(
            right: 8,
            top: 8,
            child: Icon(
              Icons.play_circle_fill,
              size: 22,
              color: Colors.white70,
            ),
          ),
      ],
      contentPadding: narrow
          ? const EdgeInsets.fromLTRB(10, 9, 10, 10)
          : const EdgeInsets.fromLTRB(13, 11, 13, 12),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (status == PromotionStatus.scheduled) ...[
                _pill('진행 예정', const Color(0xFF3E7BD6)),
                const SizedBox(width: 5),
              ],
              // 신청을 받는 이벤트는 카드에서 바로 알아야 한다 —
              // 상세를 열어 봐야 아는 정보면 목록에서 고를 수 없다.
              // 판정은 상세 CTA와 **같은 함수**를 쓴다(종료·숨김이면
              // 상세에 신청 버튼이 없는데 카드만 "신청 가능"이라고
              // 말하는 일이 없다).
              if (p.showsApplyButtonAt(now)) ...[
                _pill('신청 가능', const Color(0xFF0F9D58)),
                const SizedBox(width: 5),
              ],
              if (when.isNotEmpty)
                Flexible(
                  child: Text(
                    when,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.black45,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.type.emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  p.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          // 시간 문구의 정본은 [PlaceEventTime.timeLabelOf] 하나다 —
          // 시각을 안 정한 이벤트는 빈칸이 아니라 '영업중(전시간)'으로
          // 읽힌다(그것이 그 상태의 뜻이다). 카드·상세·등록이 같은
          // 함수를 쓰므로 자리마다 다른 말로 부르지 않는다.
          ...[
            const SizedBox(height: 5),
            Text(
              [
                if (p.weekdayLabel != null) p.weekdayLabel!,
                PlaceEventTime.timeLabelOf(p),
              ].where((e) => e.isNotEmpty).join(' '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
          if (p.benefit.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              p.benefit,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                color: Colors.black54,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 9),
          // 🎉 파티 카드와 **같은 부품**이라 두 열의 CTA가 같은 자리에서
          // 같은 모양으로 끝난다(색만 각 열의 강조색이다).
          OfferingCardMoreLink(color: accent),
        ],
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
  );
}
