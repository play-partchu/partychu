import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:party_app/models/host_offering.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/services/listing_sources.dart';
import 'package:party_app/services/place_promotion_service.dart';
import 'package:party_app/widgets/linked_party_card.dart';
import 'package:party_app/widgets/offering_card_shell.dart';
import 'package:party_app/widgets/party_card_widget.dart';
import 'package:party_app/widgets/place_product/place_promotion_list_section.dart';

/// 플레이스 상세의 "🎉 파티 | ✨ 이벤트" — **좌우 2열로 함께** 보여주는 영역.
///
/// ```
/// ┌───────────────┬───────────────┐
/// │ 🎉 파티 (2)   │ ✨ 이벤트 (1) │
/// │ [파티1]       │ [이벤트1]     │
/// │ [파티2]       │               │
/// └───────────────┴───────────────┘
/// ```
///
/// ## 왜 탭이 아니라 2열인가
///
/// 이 매장에서 "무슨 일이 벌어지는가"는 손님에게 하나의 질문이다. 탭으로 만들면
/// 한 번에 한쪽만 보이므로 **양쪽이 있다는 사실 자체**를 알려면 눌러 봐야 하고,
/// 파티와 이벤트를 나란히 견줄 수도 없다. 두 열로 함께 세우면 그 두 가지가
/// 한 화면에서 끝난다.
///
/// 폭은 [Expanded] 둘이라 **정확히 반반**이다 — 글자 길이나 카드 높이가 달라도
/// 칸 폭은 변하지 않는다. 두 열의 높이는 서로 묶지 않는다
/// ([CrossAxisAlignment.start]) — 한쪽이 3장이고 다른 쪽이 1장이면 짧은 쪽은
/// 그냥 짧게 끝난다. 빈 카드로 줄을 맞추지 않는다.
///
/// **한쪽만 있어도 폭은 그대로 반반이다** — 그 열은 반 폭에 서고 반대쪽은 빈
/// 자리로 남는다. 개수에 따라 카드가 커졌다 작아졌다 하지 않게([OfferingColumns]).
///
/// ## 데이터는 하나도 합치지 않는다
///
/// 파티는 `parties`(연결 필드 `linkedEventId`/`linkedPlaceId`), 매장 이벤트는
/// `placePromotions`다. 이 위젯은 **두 목록을 각각 그대로 받아** 자리에 놓기만
/// 한다 — 새 컬렉션도, 합친 모델도, 개수 캐시 필드도 만들지 않는다. 열 제목에
/// 붙는 숫자도 지금 그릴 수 있는 목록의 길이 그 자체다.
///
/// ## 카드는 기존 것 그대로
///
/// 파티는 [LinkedPartyCard], 이벤트는 [PlacePromotionCardList] — 상세에서 쓰던
/// 카드를 그대로 재사용한다(카드 복제 없음). 카드를 눌렀을 때의 이동/바텀시트
/// 동작도 예전과 완전히 같다.
///
/// 다만 두 카드 다 **한 줄 전체 폭**을 전제로 만들어져 있었다. 반 폭에서도
/// 깨지지 않도록 카드 쪽을 반응형으로 고쳤다(글자는 좁으면 줄바꿈 대신 한 줄로
/// 줄이거나 말줄임하고, 이벤트 목록은 세로로 쌓는 축을 받는다) — 폭을 억지로
/// 잘라 글자가 넘치게 두지 않는다.
///
/// 두 카드의 껍데기(테두리·라운드·사진 자리·안쪽 여백·CTA 줄)는
/// [OfferingCardShell] 하나를 함께 쓴다 — 나란히 선 두 카드가 서로 다른 물건
/// 두 개로 보이지 않게. 파티 카드의 대표사진은 파티 목록 **기본 카드와 같은
/// 함수·같은 비율**([partyBasicCardMedia])이라, 등록 화면에서 맞춘 썸네일
/// 위치가 두 자리에서 같은 곳으로 보인다.
///
/// ## 열마다 처음엔 두 장까지만
///
/// 한 열이 카드를 몇 장 펼쳐 둘지는 [OfferingColumn]이 정한다 — 처음엔
/// [kOfferingColumnInitialVisible]장, 나머지는 그 열 아래 '이벤트 3개 더보기 >'로
/// 접어 둔다. 이벤트가 다섯 개인 매장에서 다섯 장을 그대로 세우면 반대쪽 파티
/// 열은 텅 빈 채 상세만 길어졌다. 펼침은 **열마다 따로**라 한쪽을 펼쳐도 다른
/// 쪽은 그대로다. 열 머리의 숫자는 접혀 있어도 항상 전체 개수다.
///
/// ## 아무것도 없으면 영역째 사라진다
///
/// 파티도 이벤트도 없는 매장에서는 빈 열을 그리지 않는다. 단 **호스트 본인**
/// 에게는 비어 있어도 추가 진입점([PlaceOfferingHostActions])을 남긴다.
///
/// 🎁 파티츄 전용 혜택은 **행사가 아니라 매장 자체의 혜택**이라 이 영역에
/// 들어오지 않는다 — 상세 위쪽의 자기 자리(PartychuPerkCard)에 그대로 있다.
class PlaceOfferingBoard extends StatefulWidget {
  const PlaceOfferingBoard({
    super.key,
    required this.placeId,
    required this.linkedPartiesFuture,
    required this.accent,
    this.placeCollection,
    this.hostId,
    this.placeName,
    this.placeData,
    this.onPartyLinked,
    this.excludedPartyIds = const <String>{},
  });

  /// 이벤트를 읽어 올 장소 문서 id — `placePromotions`의 조회 기준.
  final String placeId;

  /// 이 장소에 연결된 파티 조회.
  ///
  /// **질의는 호출한 상세 화면이 만든다** — 플레이스는 `linkedEventId`,
  /// 공간대여는 `linkedPlaceId`로 갈리고, 그 규칙의 정본은 각 상세 화면이
  /// 이미 갖고 있다. 여기서 다시 판정하면 규칙이 두 곳으로 갈라진다.
  ///
  /// 미래를 **화면이 들고 있어야** 다시 그릴 때마다 읽지 않는다.
  final Future<QuerySnapshot<Map<String, dynamic>>> linkedPartiesFuture;

  final Color accent;

  /// 'events'(플레이스) 또는 'places'(장소대여·숙박) — 호스트 진입점용.
  final String? placeCollection;
  final String? hostId;
  final String? placeName;
  final Map<String, dynamic>? placeData;
  final VoidCallback? onPartyLinked;

  /// 이 목록에서 뺄 파티.
  ///
  /// 상세가 **다른 자리에서 이미 크게 보여주는** 파티를 여기서 또 세지
  /// 않기 위해서다 — 장소대여의 "숙박+파티" 콤보 대표 파티가 그렇다
  /// (그 카드에는 패키지 예약 버튼이 붙어 있어 목록 카드로 대신할 수 없다).
  /// 비워 두면 연결된 파티가 모두 들어온다(플레이스 상세는 그대로다).
  final Set<String> excludedPartyIds;

  @override
  State<PlaceOfferingBoard> createState() => _PlaceOfferingBoardState();
}

/// 이 영역을 그릴 거리가 있는지 — 손님에게는 둘 다 없으면 영역째 사라진다
/// (호스트에게는 추가 진입점만 남는다).
bool hasAnyOffering({required int partyCount, required int eventCount}) =>
    partyCount > 0 || eventCount > 0;

/// 두 열 사이 간격. 열 폭을 계산하는 자리가 여기 하나뿐이라 값이 갈라지지 않는다.
const double kOfferingColumnGap = 10;

/// 파티 열과 이벤트 열을 좌우로 세우는 뼈대.
///
/// 규칙은 하나다 — **열 폭은 언제나 반반**이다([Expanded] 둘이라 정확히
/// 50:50). 한쪽만 있어도 그 열은 반 폭 그대로 서고, 반대쪽은 그냥 빈 자리로
/// 남는다.
///
/// 예전에는 한쪽만 있을 때 그 열이 전체 폭을 썼다. 그러면 파티가 하나뿐인
/// 매장에서 카드가 두 배로 커지고, 이벤트가 하나 더 등록되는 순간 같은 카드가
/// 절반으로 줄어든다 — **같은 파티가 매장 사정에 따라 다른 크기로** 보인다.
/// 카드 안의 사진 비율·제목 줄 수도 그때마다 달라진다. 이 영역은 "여기서 뭐
/// 하지?"에 답하는 작은 게시판이지 데이터 개수에 따라 모양이 바뀌는 자리가
/// 아니라서, 폭은 개수와 무관하게 고정한다.
///
/// 높이는 서로 묶지 않는다 — 한쪽이 3장이고 다른 쪽이 1장이면 짧은 쪽은 그냥
/// 짧게 끝난다.
///
/// 자리 규칙만 아는 껍데기라 어떤 카드가 들어오는지는 모른다 — 덕분에 실제
/// 카드를 넣은 채로 폭·넘침을 그대로 검증할 수 있다.
class OfferingColumns extends StatelessWidget {
  const OfferingColumns({super.key, this.party, this.event});

  final Widget? party;
  final Widget? event;

  @override
  Widget build(BuildContext context) {
    final p = party;
    final e = event;
    // 둘 다 없으면 영역째 사라진다 — 빈 열 두 개를 세우지 않는다.
    if (p == null && e == null) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 없는 쪽도 [Expanded]로 자리를 잡는다 — 그래야 있는 쪽이 반 폭에
        // 머문다(빈 쪽은 아무것도 그리지 않으므로 높이는 0이다).
        Expanded(child: p ?? const SizedBox.shrink()),
        const SizedBox(width: kOfferingColumnGap),
        Expanded(child: e ?? const SizedBox.shrink()),
      ],
    );
  }
}

/// 한 열이 **처음에 펼쳐 두는 카드 수**.
///
/// 2인 이유: 이 영역은 상세 본문 한복판에 있고 아래로 상품·후기·지도가 이어진다.
/// 이벤트가 다섯 개 등록된 매장에서 다섯 장을 그대로 세우면 반대쪽 파티 열은
/// 텅 빈 채 상세만 길어진다 — 손님이 "여기서 뭐 하지?"를 알기에는 두 장이면
/// 충분하고, 더 궁금하면 그 열에서 바로 펼친다.
const int kOfferingColumnInitialVisible = 2;

/// 열 하나 — 제목 한 줄, 그 아래 카드들, 그리고 **더보기/접기**.
///
/// 제목은 좁은 칸에서도 **한 줄**이어야 한다(두 열의 카드 시작 높이가
/// 어긋나지 않게). 그래서 넘치면 줄바꿈 대신 통째로 조금 줄어든다.
///
/// ## 펼침 상태는 이 열이 혼자 갖는다
///
/// 파티 열과 이벤트 열은 각각 자기 [State]를 가진 **서로 다른 위젯**이라,
/// 한쪽을 펼쳐도 반대쪽은 아무 영향을 받지 않는다 — 부모에 플래그 두 개를 두고
/// 헷갈리지 않게 넘기는 대신, 독립성을 구조로 보장한다.
///
/// 화면을 벗어나면 사라지는 **순수 UI 상태**다. Firestore에도, 파티·이벤트
/// 모델에도 펼침 여부를 적지 않는다(다시 들어오면 다시 접힌 상태로 시작한다).
///
/// ## 목록은 잘라서 받지 않는다
///
/// [total]은 **전체 개수**이고(머리에 붙는 숫자는 접혀 있어도 항상 이 값이다),
/// [builder]는 "지금 몇 장을 그릴지"를 받아 그 만큼만 그린다. 잘라 놓은 두
/// 번째 목록을 만들지 않으므로 개수의 출처는 부모가 읽어 온 목록 하나뿐이다.
class OfferingColumn extends StatefulWidget {
  const OfferingColumn({
    super.key,
    required this.offering,
    required this.total,
    required this.accent,
    required this.builder,
  });

  /// 무엇의 열인지 — 이모지·이름('파티'/'이벤트')의 정본.
  final HostOffering offering;

  /// 이 열이 가진 **전체** 개수. 머리의 숫자이자 더보기 계산의 기준이다.
  final int total;

  final Color accent;

  /// 앞에서부터 몇 장을 그릴지 받아 카드들을 만든다.
  final Widget Function(int visible) builder;

  @override
  State<OfferingColumn> createState() => _OfferingColumnState();
}

class _OfferingColumnState extends State<OfferingColumn> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final visible = _expanded
        ? widget.total
        : math.min(widget.total, kOfferingColumnInitialVisible);
    // 숨어 있는 **실제 개수** — 고정 문구가 아니라 남은 수를 그대로 말한다.
    final hidden = widget.total - visible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.offering.emoji, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
              Text(
                // 부르는 이름은 [HostOffering] 정본 그대로 — '파티' / '이벤트'.
                widget.offering.shortLabel,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                // 접혀 있어도 **전체 개수**다 — 머리의 숫자가 접힘 여부에 따라
                // 달라지면 이 매장에 몇 개가 있는지 알 길이 없어진다.
                '(${widget.total})',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: widget.accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        widget.builder(visible),
        if (widget.total > kOfferingColumnInitialVisible)
          _toggle(hidden: hidden),
      ],
    );
  }

  /// 열 맨 아래 한 줄 — 접혀 있으면 '이벤트 3개 더보기 >', 펼쳐져 있으면 '접기'.
  ///
  /// 반 폭 열이라 글자가 길어지면 넘친다 — 줄바꿈 대신 통째로 줄인다
  /// (카드 CTA·열 제목이 쓰는 것과 같은 방법).
  Widget _toggle({required int hidden}) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      onPressed: () => setState(() => _expanded = !_expanded),
      style: TextButton.styleFrom(
        foregroundColor: widget.accent,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _expanded ? '접기' : '${widget.offering.shortLabel} $hidden개 더보기',
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            Icon(
              _expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.chevron_right_rounded,
              size: 18,
            ),
          ],
        ),
      ),
    ),
  );
}

class _PlaceOfferingBoardState extends State<PlaceOfferingBoard> {
  /// 이벤트 스트림은 **한 번만** 만든다 — build 안에서 만들면 다시 그릴 때마다
  /// 구독이 새로 붙는다.
  late final Stream<List<PlacePromotion>> _promotions =
      PlacePromotionService.watchPublicForPlace(widget.placeId);

  @override
  Widget build(BuildContext context) {
    final isHost = PlaceOfferingHostActions.isHostOf(
      hostId: widget.hostId,
      placeCollection: widget.placeCollection,
    );
    final hostActions = PlaceOfferingHostActions(
      placeId: widget.placeId,
      accent: widget.accent,
      placeCollection: widget.placeCollection,
      hostId: widget.hostId,
      placeName: widget.placeName,
      placeData: widget.placeData,
      onPartyLinked: widget.onPartyLinked,
    );

    return StreamBuilder<List<PlacePromotion>>(
      stream: _promotions,
      builder: (context, eventSnap) {
        // 로딩/오류 때는 빈 목록으로 본다 — 이벤트는 부가 정보라 상세의 다른
        // 정보를 스피너로 가리지 않는다(기존 이벤트 섹션과 같은 방침).
        final events = eventSnap.data ?? const <PlacePromotion>[];
        return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
          future: widget.linkedPartiesFuture,
          builder: (context, partySnap) {
            // 파티 조회가 끝나기 전에는 **아무것도 그리지 않는다**. 0건으로
            // 보고 이벤트만 전체 폭으로 폈다가 파티가 도착해 2열로 접히면,
            // 손님 눈앞에서 레이아웃이 한 번 갈아끼워진다.
            if (partySnap.connectionState != ConnectionState.done) {
              return const SizedBox.shrink();
            }
            final parties = _visibleParties(partySnap.data);
            if (!hasAnyOffering(
              partyCount: parties.length,
              eventCount: events.length,
            )) {
              // 손님에게는 빈 열을 보여주지 않는다 — 영역째 사라진다.
              return isHost ? hostActions : const SizedBox.shrink();
            }

            final hasParties = parties.isNotEmpty;
            final hasEvents = events.isNotEmpty;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OfferingColumns(
                  // 열 하나가 받는 것은 **전체 목록의 길이와, 몇 개를 그릴지
                  // 물어보는 함수** 둘뿐이다. 몇 개를 보여줄지는 열이 스스로
                  // 정하고(더보기/접기), 목록 자체는 여기 그대로 있다 —
                  // 잘라 놓은 두 번째 목록을 따로 만들지 않는다.
                  party: hasParties
                      ? OfferingColumn(
                          offering: HostOffering.party,
                          total: parties.length,
                          accent: widget.accent,
                          builder: (visible) =>
                              _partyList(parties.take(visible)),
                        )
                      : null,
                  event: hasEvents
                      ? OfferingColumn(
                          offering: HostOffering.placeEvent,
                          total: events.length,
                          accent: widget.accent,
                          builder: (visible) =>
                              _eventList(events.take(visible).toList()),
                        )
                      : null,
                ),
                // 호스트 진입점은 두 열 아래 한 줄로 — 어느 쪽을 더하든 같은
                // 자리에서 시작한다.
                if (isHost) ...[const SizedBox(height: 4), hostActions],
              ],
            );
          },
        );
      },
    );
  }

  /// 지금 노출 가능한 파티만 — 목록·검색과 **같은 판정**을 그대로 쓰고
  /// ([ListingSources.isPartyVisible]), 거기에 [excludedPartyIds]만 더 뺀다.
  ///
  /// 예전에는 `isDeleted`만 봤다. 그러면 이미 끝난 파티와 남은 회차가 없는
  /// 정기 파티가 이 열에 계속 남아, 같은 화면 위쪽의 'With파티' 배지
  /// ([PlacePartyIndex] → 같은 판정 함수)와 개수가 어긋났다. 판정을 한 곳으로
  /// 모아 두 자리가 같은 파티 집합을 보게 한다.
  /// 다가오는 파티가 위로 오도록 시작 시각순 정렬(정기 파티는 다음 회차).
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _visibleParties(
    QuerySnapshot<Map<String, dynamic>>? snap,
  ) {
    final docs =
        snap?.docs
            .where((d) => ListingSources.isPartyVisible(d.data()))
            .where((d) => !widget.excludedPartyIds.contains(d.id))
            .toList() ??
        <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    docs.sort((a, b) {
      final da = PartyCard.parsePartyDateTime(a.data());
      final db = PartyCard.parsePartyDateTime(b.data());
      if (da != null && db != null) return da.compareTo(db);
      if (da != null) return -1;
      if (db != null) return 1;
      return 0;
    });
    return docs;
  }

  Widget _partyList(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final doc in docs)
        LinkedPartyCard(partyId: doc.id, party: doc.data()),
    ],
  );

  /// 이벤트 열 — **세로로 쌓는다.**
  ///
  /// 한 열 안에서는 가로 스크롤이 설 자리가 없다(반 폭에서 가로로 밀면 카드가
  /// 칸 밖으로 나간다). 전체 폭을 혼자 쓰는 경우에도 파티 열과 같은 모양으로
  /// 세로로 쌓아, 개수에 따라 배치가 달라지지 않게 한다.
  Widget _eventList(List<PlacePromotion> events) => PlacePromotionCardList(
    promotions: events,
    accent: widget.accent,
    hostName: placeEventHostNameOf(widget.placeData),
    axis: Axis.vertical,
  );
}
