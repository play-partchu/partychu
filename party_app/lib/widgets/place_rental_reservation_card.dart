import 'package:flutter/material.dart';

import 'package:party_app/models/payment_status.dart';
import 'package:party_app/models/place_rental_reservation.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/widgets/check_in_qr_card.dart';
import 'package:party_app/widgets/deposit_panel.dart';
import 'package:party_app/widgets/partychu_ui.dart';

/// 장소대여 예약 한 건 카드 — 이용자 목록('내 장소대여 예약')과 업주 관리 화면이
/// **같은 카드**를 쓴다. 방문예약의 [VisitReservationCard]와 같은 구조이고,
/// 결제 부분은 아예 같은 위젯([DepositPanel])이다.
///
/// 보는 사람이 누구냐에 따라 위쪽 제목(장소 이름 ↔ 예약자 이름)과 아래 버튼
/// (취소 ↔ 승인·거절·입금확인)만 달라진다.
class PlaceRentalReservationCard extends StatelessWidget {
  final PlaceRentalReservation reservation;

  /// 업주 화면이면 true — 예약자 정보와 승인/거절·입금확인 버튼을 보여준다.
  final bool asHost;

  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onCancel;

  /// 이용자의 '입금했어요' — 무통장입금이고 입금대기일 때만 버튼이 뜬다.
  final Future<void> Function()? onMarkDepositSent;

  /// 업주의 '입금 확인'.
  final VoidCallback? onConfirmDeposit;

  const PlaceRentalReservationCard({
    super.key,
    required this.reservation,
    this.asHost = false,
    this.onApprove,
    this.onReject,
    this.onCancel,
    this.onMarkDepositSent,
    this.onConfirmDeposit,
  });

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    final now = DateTime.now();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PartyChuColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  asHost
                      ? '${r.requesterName} · ${r.peopleCount}명'
                      : r.placeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: PartyChuColors.heading,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _statusBadge(r.status),
            ],
          ),
          if (r.roomName != null && r.roomName!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              asHost ? '${r.placeName} · ${r.roomName}' : r.roomName!,
              style: const TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ],
          if (r.partyTitle != null && r.partyTitle!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '🎉 ${r.partyTitle}',
              style: const TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ],
          const SizedBox(height: 8),
          _line(Icons.event_rounded, r.useLabel),
          // 콤보는 방과 파티 자리가 한 덩어리로 잡혀 있다 — 취소하면 둘 다
          // 풀린다는 사실을 카드에서 미리 알려준다.
          if (r.isCombo)
            _line(Icons.link_rounded, '숙박+파티 패키지 — 취소하면 파티 참가도 함께 취소돼요'),
          if (asHost && r.requesterPhone.isNotEmpty)
            _line(Icons.phone_rounded, r.requesterPhone),
          if (r.requestMessage.isNotEmpty)
            _line(Icons.edit_note_rounded, r.requestMessage),
          if (r.hostMessage.isNotEmpty)
            _line(Icons.meeting_room_rounded, '장소: ${r.hostMessage}'),
          if (r.status == PlaceRentalStatus.requested &&
              r.respondBy != null &&
              r.respondBy!.isAfter(now))
            _line(
              Icons.hourglass_bottom_rounded,
              asHost
                  ? '${_remainingLabel(r.respondBy!, now)} 안에 응답해주세요'
                  : '업주 응답을 기다리는 중 (${_remainingLabel(r.respondBy!, now)} 남음)',
            ),
          const SizedBox(height: 6),
          Text(
            formatPrice(r.totalPrice),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: PartyChuColors.primary,
            ),
          ),
          // 결제 — 예약 진행 상태와 **다른 축**이라 따로 적는다. 확정
          // (confirmed)이어도 입금 전이면 '입금대기'가 그대로 보인다.
          if (r.payment != null) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: PartyChuColors.border),
            const SizedBox(height: 10),
            DepositPanel(
              payment: r.payment!,
              sentMessage: '입금 확인을 요청했어요. 업주가 확인하면 알려드려요.',
              // 이용자 화면에서만 '입금했어요'가 뜬다.
              onMarkSent: asHost ? null : onMarkDepositSent,
            ),
            // 업주는 여기서 바로 입금을 확인한다 — 예약 목록 하나로 끝난다.
            if (asHost && r.needsDepositCheck && onConfirmDeposit != null) ...[
              const SizedBox(height: 8),
              _button(
                label: '입금 확인',
                onTap: onConfirmDeposit,
                filled: r.payment!.status == PaymentStatus.depositPending,
              ),
            ],
          ],
          // 입장 QR — 예약이 확정되면 서버가 발급하고, 취소·거절·만료되면 그
          // 자리에서 걷어간다(functions/reservationCheckIn.js). 여기서는 토큰이
          // 있는지만 보고 유효성은 판단하지 않는다. 업주 화면에는 띄우지
          // 않는다 — 업주는 스캐너 쪽이다.
          if (!asHost && r.checkInToken.isNotEmpty) ...[
            const SizedBox(height: 12),
            CheckInQrButton(pass: r.checkInPass),
          ],
          if (_hasActions(r, now)) ...[const SizedBox(height: 12), _actions(r)],
        ],
      ),
    );
  }

  bool _hasActions(PlaceRentalReservation r, DateTime now) {
    if (asHost) {
      if (r.status == PlaceRentalStatus.requested) return true;
      return r.canCancel(now) && onCancel != null;
    }
    return r.canCancel(now) && onCancel != null;
  }

  Widget _actions(PlaceRentalReservation r) {
    if (asHost && r.status == PlaceRentalStatus.requested) {
      return Row(
        children: [
          Expanded(
            child: _button(label: '거절', onTap: onReject, filled: false),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _button(label: '승인', onTap: onApprove, filled: true),
          ),
        ],
      );
    }
    return _button(
      label: asHost ? '예약 취소하기' : '예약 취소',
      onTap: onCancel,
      filled: false,
    );
  }

  Widget _button({
    required String label,
    required VoidCallback? onTap,
    required bool filled,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? PartyChuColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: filled ? PartyChuColors.primary : PartyChuColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: filled ? Colors.white : PartyChuColors.primaryDeep,
          ),
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: Colors.black38),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Colors.black54,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _statusBadge(PlaceRentalStatus status) {
    final (bg, fg) = switch (status) {
      PlaceRentalStatus.confirmed => (
        const Color(0xFFE6F6EF),
        const Color(0xFF1F8A63),
      ),
      PlaceRentalStatus.requested || PlaceRentalStatus.pending => (
        const Color(0xFFFFF3E0),
        const Color(0xFFB97400),
      ),
      _ => (const Color(0xFFF2F2F5), Colors.black45),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  static String _remainingLabel(DateTime until, DateTime now) {
    final minutes = until.difference(now).inMinutes;
    if (minutes >= 60) return '${minutes ~/ 60}시간';
    return '$minutes분';
  }
}
