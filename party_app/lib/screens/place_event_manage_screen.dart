// ─────────────────────────────────────────────────────────────────────────────
// 호스트용 "🎪 매장 이벤트 관리".
//
// 여기서 다루는 것은 **매장 이벤트**다([HostOffering.placeEvent]) — 매장이
// 주체가 되어 여는 행사·프로모션·혜택. 참가자를 모집하는 🎉 파티는 이 화면과
// 아무 관계가 없다(저장 컬렉션부터 다르다).
//
// 기존에 등록해 둔 플레이스/숙박을 **다시 등록하거나 전체를 수정하지 않고**
// 이벤트만 더하고 고치고 끝내는 화면이다. 손님 상세에서는 진행 중·예정만
// 보이지만, 여기서는 종료·숨김까지 전부 보인다.
//
// 쓰기 창구를 여기 하나로 모은 이유:
//   기존 등록/수정 폼은 [PlacePromotionService.syncForPlace]로 **목록 전체를
//   치환**한다(목록에 없는 문서는 지운다). 그래서 기존 장소의 수정 화면에서는
//   이벤트를 직접 편집하지 않고 이 화면으로 보낸다 — 두 곳에서 각자 들고 있던
//   낡은 목록으로 저장해 이벤트가 조용히 사라지는 사고를 구조적으로 막는다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/screens/place_event_applicants_screen.dart';
import 'package:party_app/screens/place_event_edit_screen.dart';
import 'package:party_app/services/place_event_application_service.dart';
import 'package:party_app/services/place_promotion_service.dart';
import 'package:party_app/utils/auto_delete_retention.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/past_content_retention_notice.dart';
import 'package:party_app/widgets/partychu_ui.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 기존 장소의 **수정 화면**에 놓는 진입 카드.
///
/// 수정 화면에서는 이벤트를 직접 편집하지 않는다([PlaceEventManageScreen] 주석
/// 참고) — 대신 이 카드로 관리 화면에 보낸다. 신규 등록 화면에서는 지금처럼
/// 폼 안에서 첫 이벤트를 함께 넣을 수 있으므로 이 카드를 쓰지 않는다.
class PlaceEventManageEntryCard extends StatelessWidget {
  const PlaceEventManageEntryCard({
    super.key,
    required this.placeId,
    required this.placeCollection,
    required this.hostId,
    required this.placeName,
    required this.accent,
  });

  final String placeId;
  final String placeCollection;
  final String hostId;
  final String placeName;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.28), width: 1.2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            webFramedRoute(
              (_) => PlaceEventManageScreen(
                placeId: placeId,
                placeCollection: placeCollection,
                hostId: hostId,
                placeName: placeName,
                accent: accent,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
            child: Row(
              children: [
                const Text('✨', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '매장 이벤트 관리',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        '새 매장 이벤트 추가·수정·종료는 여기서 따로 합니다.\n'
                        '장소를 저장하지 않아도 바로 반영돼요.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.black54,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.black38),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 끝난 이벤트 묶음이 처음 그려질 때 **자동 삭제 안내를 한 번** 띄우는,
/// 보이지 않는 조각.
///
/// 목록 자체([PlaceEventManageList])는 StatelessWidget이고 스트림이 올 때마다
/// 다시 그려진다 — 거기서 바로 띄우면 스냅샷이 올 때마다 안내가 다시 뜬다.
/// 상태를 가진 조각을 **끝난 묶음이 있을 때만** 목록에 끼워 두면, initState가
/// 한 번만 불리므로 화면을 여는 동안 안내도 한 번만 뜬다(같은 자리·같은 열쇠라
/// 다시 그려도 State가 살아 있다).
class _PastEventNoticeTrigger extends StatefulWidget {
  const _PastEventNoticeTrigger({super.key});

  @override
  State<_PastEventNoticeTrigger> createState() =>
      _PastEventNoticeTriggerState();
}

class _PastEventNoticeTriggerState extends State<_PastEventNoticeTrigger> {
  @override
  void initState() {
    super.initState();
    // 목록이 다 그려진 뒤에 띄운다 — build 도중에 다이얼로그를 열 수 없다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      PastContentRetentionNotice.maybeShow(context, PastContentKind.event);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// 한 플레이스의 매장 이벤트 **목록 본체** — 진행 중 · 진행 예정 · 종료·숨김
/// 묶음과 각 줄의 수정 · 종료/다시 노출 · 삭제 · 신청자 확인까지 전부 여기 있다.
///
/// 화면([PlaceEventManageScreen])과 **마이 > 파티츄 호스트의 '이벤트' 탭**이
/// 같은 위젯을 쓴다. 목록을 두 벌로 만들면 한쪽에만 상태 배지나 신청자 수가
/// 붙는 식으로 곧 갈라진다 — 이벤트를 다루는 규칙은 여기 하나뿐이다.
///
/// 데이터도 그대로다: [PlacePromotionService.watchForPlace] 하나와
/// [PlaceEventApplicationService.watchAppliedCountsForPlace] 하나. 새 컬렉션도
/// 새 쿼리도 만들지 않는다.
class PlaceEventManageList extends StatelessWidget {
  const PlaceEventManageList({
    super.key,
    required this.placeId,
    required this.placeCollection,
    required this.hostId,
    required this.placeName,
    required this.accent,
    this.shrinkWrap = false,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 110),
  });

  final String placeId;

  /// 'events'(플레이스) 또는 'places'(장소대여·숙박).
  final String placeCollection;

  /// 원본 장소 문서의 hostId — 화면을 연 사람이 정말 주인인지 여기서 한 번
  /// 거른다. 최종 방어선은 firestore.rules다(클라이언트는 우회될 수 있다).
  final String hostId;
  final String placeName;
  final Color accent;

  /// 바깥에 이미 스크롤이 있을 때(호스트 허브의 이벤트 탭은 플레이스가 여럿이면
  /// 이 목록을 여러 개 이어 붙인다) 스스로 스크롤하지 않게 한다.
  final bool shrinkWrap;

  final EdgeInsets padding;

  bool get _isOwner =>
      UserSession.userId.isNotEmpty && UserSession.userId == hostId;

  Future<void> _openEditor(
    BuildContext context, {
    PlacePromotion? existing,
  }) async {
    await Navigator.push(
      context,
      webFramedRoute(
        (_) => PlaceEventEditScreen(
          placeId: placeId,
          placeCollection: placeCollection,
          hostId: hostId,
          placeName: placeName,
          accent: accent,
          existing: existing,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, PlacePromotion p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('매장 이벤트를 삭제할까요?'),
        content: Text(
          "'${p.title}'을(를) 삭제합니다.\n"
          '장소 자체와 예약·상품에는 영향이 없어요.',
          style: const TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PlacePromotionService.deleteById(p.id);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('삭제에 실패했어요. 잠시 후 다시 시도해주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return !_isOwner
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  '이 장소의 호스트만 이벤트를 관리할 수 있어요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black45),
                ),
              ),
            )
          : StreamBuilder<List<PlacePromotion>>(
              stream: PlacePromotionService.watchForPlace(placeId),
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Center(
                    child: Text(
                      '이벤트를 불러오지 못했어요.',
                      style: TextStyle(color: Colors.black45),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data!;
                final now = DateTime.now();
                final running = <PlacePromotion>[];
                final scheduled = <PlacePromotion>[];
                final done = <PlacePromotion>[];
                for (final p in all) {
                  switch (p.statusAt(now)) {
                    case PromotionStatus.running:
                      running.add(p);
                    case PromotionStatus.scheduled:
                      scheduled.add(p);
                    case PromotionStatus.ended:
                    case PromotionStatus.hidden:
                      done.add(p);
                  }
                }

                // 이벤트별 **현재 신청자 수**. 장소 단위로 한 번만 듣고
                // 이벤트마다 나눠 쓴다 — 이벤트 수만큼 리스너를 열지 않는다.
                // 아직 못 읽었으면 빈 맵이라 "신청자 0명"으로 보이고, 곧 값이
                // 들어오면 그 줄만 갱신된다.
                return StreamBuilder<Map<String, int>>(
                  stream:
                      PlaceEventApplicationService.watchAppliedCountsForPlace(
                        placeId: placeId,
                        hostId: hostId,
                      ),
                  builder: (context, countSnap) {
                    final counts = countSnap.data ?? const <String, int>{};
                    return ListView(
                      padding: padding,
                      shrinkWrap: shrinkWrap,
                      physics: shrinkWrap
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      children: [
                        _placeBar(),
                        const SizedBox(height: 16),
                        if (all.isEmpty) _empty(),
                        if (running.isNotEmpty)
                          ..._group(context, '진행 중', running, now, counts),
                        if (scheduled.isNotEmpty)
                          ..._group(context, '진행 예정', scheduled, now, counts),
                        if (done.isNotEmpty) ...[
                          // 끝난 이벤트가 하나라도 보이는 순간 자동 삭제
                          // 안내를 한 번 띄운다(3일 유예는 안내 쪽이 기억한다).
                          const _PastEventNoticeTrigger(
                            key: ValueKey('past-event-notice'),
                          ),
                          ..._group(context, '종료 · 숨김', done, now, counts),
                        ],
                      ],
                    );
                  },
                );
              },
            );
  }

  /// 이 플레이스에 이벤트를 새로 만든다 — 목록을 품은 쪽(화면·탭)이 자기
  /// 자리에 맞는 버튼을 그리고 이 함수를 부른다.
  Future<void> openNewEditor(BuildContext context) => _openEditor(context);

  Widget _placeBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE8EBF2)),
    ),
    child: Row(
      children: [
        Icon(Icons.place_outlined, size: 17, color: accent),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            placeName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          placeCollection == 'places' ? '장소대여 · 숙박' : '플레이스',
          style: const TextStyle(fontSize: 11.5, color: Colors.black45),
        ),
      ],
    ),
  );

  Widget _empty() => Container(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE8EBF2)),
    ),
    child: const Column(
      children: [
        Text('✨', style: TextStyle(fontSize: 30)),
        SizedBox(height: 10),
        Text(
          '아직 등록한 매장 이벤트가 없어요',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 6),
        Text(
          '공연·DJ·시음처럼 매장에서 진행하는 소식이 생기면 여기서 추가해주세요.\n'
          '장소 정보를 다시 입력할 필요는 없어요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: Colors.black45, height: 1.55),
        ),
      ],
    ),
  );

  List<Widget> _group(
    BuildContext context,
    String title,
    List<PlacePromotion> items,
    DateTime now,
    Map<String, int> counts,
  ) => [
    Padding(
      padding: const EdgeInsets.only(bottom: 9, top: 4),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${items.length}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      ),
    ),
    for (final p in items) ...[
      _row(context, p, p.statusAt(now), counts[p.id] ?? 0),
      const SizedBox(height: 9),
    ],
    const SizedBox(height: 8),
  ];

  Widget _row(
    BuildContext context,
    PlacePromotion p,
    PromotionStatus status,
    int applicantCount,
  ) {
    final subtitle = [
      if (p.isAlways) '상시 진행',
      if (p.periodLabel != null) p.periodLabel!,
      if (p.weekdayLabel != null) p.weekdayLabel!,
      if (p.timeLabel != null) p.timeLabel!,
    ].join(' · ');

    // 끝난 이벤트의 자동 삭제 예정 — 지난 파티 카드와 **같은 정본**을 쓴다
    // ([AutoDeleteRetention], 14일). 기준점은 "손님에게 보이지 않게 된 시각"
    // ([PlacePromotion.goneAt])이고, 그것을 모르는 옛 숨김 이벤트는 null이라
    // 아무 말도 하지 않는다 — 서버도 그런 이벤트는 지우지 않는다.
    final autoDeleteLabel = AutoDeleteRetention.label(p.goneAt());
    final deleteSoon = AutoDeleteRetention.isUrgent(p.goneAt());

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.type.emoji, style: const TextStyle(fontSize: 17)),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.title.isEmpty ? '(제목 없음)' : p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black45,
                          ),
                        ),
                      ],
                      // 자동 삭제 예정 — 끝난 이벤트에만 붙는다.
                      if (autoDeleteLabel != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          autoDeleteLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: deleteSoon
                                ? Colors.redAccent
                                : const Color(0xFFE65100),
                          ),
                        ),
                      ],
                      // 출처 표시 — 파티가 지워져도 남는다(제목을 함께
                      // 적어 두는 이유다). 이벤트는 파티에 종속되지 않는다.
                      if ((p.sourcePartyTitle ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          "'${p.sourcePartyTitle!.trim()}' 파티에서 만든 이벤트",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black38,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _statusPill(status),
              ],
            ),
          ),
          // ── 신청자 ──────────────────────────────────────────────────
          //
          // 신청을 받기로 한 이벤트에만 나온다([EventApplyMode]). 카드·상세
          // 손님 화면에는 이 숫자가 없다 — 남의 신청 문서는 규칙상 읽을 수
          // 없고(호스트와 본인만), 공개하려면 서버가 관리하는 집계 필드가
          // 따로 있어야 한다. 호스트가 확인할 자리는 여기 하나다.
          if (p.applyMode.receivesApplications) ...[
            const Divider(height: 1, color: Color(0xFFF0F0F4)),
            InkWell(
              onTap: () => Navigator.push(
                context,
                webFramedRoute(
                  (_) => PlaceEventApplicantsScreen(
                    promotion: p,
                    accent: accent,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
                child: Row(
                  children: [
                    Icon(Icons.how_to_reg_outlined, size: 16, color: accent),
                    const SizedBox(width: 7),
                    Text(
                      '신청자 $applicantCount명',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Colors.black38,
                    ),
                  ],
                ),
              ),
            ),
          ],
          const Divider(height: 1, color: Color(0xFFF0F0F4)),
          Row(
            children: [
              _act(
                icon: Icons.edit_outlined,
                label: '수정',
                onTap: () => _openEditor(context, existing: p),
              ),
              _vline(),
              _act(
                icon: p.isVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                label: p.isVisible ? '종료' : '다시 노출',
                onTap: () =>
                    PlacePromotionService.setVisible(p.id, !p.isVisible),
              ),
              _vline(),
              _act(
                icon: Icons.delete_outline,
                label: '삭제',
                color: Colors.redAccent,
                onTap: () => _confirmDelete(context, p),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _vline() =>
      Container(width: 1, height: 22, color: const Color(0xFFF0F0F4));

  Widget _act({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) => Expanded(
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: color ?? Colors.black54),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color ?? Colors.black54,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _statusPill(PromotionStatus s) {
    final (bg, fg) = switch (s) {
      PromotionStatus.running => (
        const Color(0xFFE8F5E9),
        const Color(0xFF2E7D32),
      ),
      PromotionStatus.scheduled => (
        const Color(0xFFE3F0FB),
        const Color(0xFF3E7BD6),
      ),
      PromotionStatus.ended => (const Color(0xFFF1F1F4), Colors.black45),
      PromotionStatus.hidden => (const Color(0xFFF1F1F4), Colors.black45),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        s.label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

/// 한 플레이스의 매장 이벤트 관리 **화면** — 목록은 [PlaceEventManageList]가
/// 그대로 그리고, 여기서 더하는 것은 제목줄과 '매장 이벤트 추가' 버튼뿐이다.
///
/// 이 화면으로 오는 길은 예전과 같다(플레이스 수정 화면의 진입 카드, 등록 뒤
/// 이어지는 뒷길 — [PlaceEventEntry]). 마이 > 파티츄 호스트의 **이벤트 탭**은
/// 화면을 열지 않고 같은 목록 위젯을 그 자리에 편다.
class PlaceEventManageScreen extends StatelessWidget {
  const PlaceEventManageScreen({
    super.key,
    required this.placeId,
    required this.placeCollection,
    required this.hostId,
    required this.placeName,
    required this.accent,
  });

  final String placeId;
  final String placeCollection;
  final String hostId;
  final String placeName;
  final Color accent;

  bool get _isOwner =>
      UserSession.userId.isNotEmpty && UserSession.userId == hostId;

  @override
  Widget build(BuildContext context) {
    final list = PlaceEventManageList(
      placeId: placeId,
      placeCollection: placeCollection,
      hostId: hostId,
      placeName: placeName,
      accent: accent,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          '매장 이벤트 관리',
          style: TextStyle(
            fontFamily: PartyChuTitleFont.family,
            fontWeight: PartyChuTitleFont.medium,
            fontSize: 18,
            color: Colors.black87,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: list,
      bottomNavigationBar: !_isOwner
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => list.openNewEditor(context),
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text(
                    '매장 이벤트 추가',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
