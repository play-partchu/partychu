// 게스트 허브 📍 플레이스 탭의 **매장 이벤트 신청** 한 줄.
//
// 방문예약 카드([VisitReservationCard])·이용권 카드([VoucherCard])와 나란히
// 서는 자리라 그 둘의 생김새를 따른다 — 흰 카드, 제목 한 줄, 아래에 부가 정보,
// 오른쪽에 상태.
//
// ⚠️ 여기 뜨는 값(제목·장소명·일정)은 전부 **신청 문서에 서버가 베껴 둔
//    스냅샷**이다([PlaceEventApplication]). 이벤트 문서를 다시 읽지 않으므로
//    목록을 그리는 데 추가 읽기가 없고, 신청 당시에 무엇을 신청했는지가
//    그대로 남는다(파티 신청의 partyTitle·partyDateTime과 같은 취급).

import 'package:flutter/material.dart';

import 'package:party_app/models/place_event_application.dart';

class PlaceEventApplicationCard extends StatelessWidget {
  const PlaceEventApplicationCard({
    super.key,
    required this.application,
    required this.accent,
    this.onOpen,
    this.onCancel,
  });

  final PlaceEventApplication application;

  final Color accent;

  /// 이벤트 상세를 여는 동작. 이벤트가 사라졌으면 null이라 눌리지 않는다.
  final VoidCallback? onOpen;

  /// 신청을 무르는 동작. 이미 취소한 건은 null.
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final a = application;
    final sub = [
      if (a.placeName.isNotEmpty) a.placeName,
      if (a.scheduleLabel.isNotEmpty) a.scheduleLabel,
    ].join(' · ');
    final applied = a.isApplied;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0E2E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpen,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🎪', style: TextStyle(fontSize: 17)),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.eventTitle.isEmpty ? '(제목 없음)' : a.eventTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: applied ? Colors.black87 : Colors.black45,
                          ),
                        ),
                        if (sub.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            sub,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _statusPill(applied),
                ],
              ),
            ),
          ),
          if (onCancel != null) ...[
            const Divider(height: 1, color: Color(0xFFF6EEF2)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  '신청 취소',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _statusPill(bool applied) {
    final (bg, fg) = applied
        ? (accent.withValues(alpha: 0.12), accent)
        : (const Color(0xFFF1F1F4), Colors.black45);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        application.status.label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}
