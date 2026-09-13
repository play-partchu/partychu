import 'package:flutter/material.dart';
import 'package:party_app/models/payment_status.dart';
import 'package:party_app/widgets/action_result_dialog.dart';
import 'package:party_app/widgets/partychu_ui.dart';

// 호스트가 **신청자의 상태를 실제로 바꾼 뒤**의 완료 팝업 문구.
//
// 같은 처리를 두 화면이 한다 — 파티별 신청자 목록(`party_applicants_screen`)과
// 호스트 허브의 신청자 시트(`my_host_hub_screen`). 문구를 각자 들고 있으면
// 같은 '승인'인데 화면마다 다른 말을 하게 되므로 여기 모아 둔다.
//
// 셋 다 **서버가 성공으로 답한 뒤에만** 부른다. 실패는 각 화면의 기존 오류
// 안내가 맡고, 이 팝업은 뜨지 않는다.

/// 승인/거절 완료.
///
/// 승인 문구는 **실제로 남은 다음 단계**에 맞춘다. 무통장입금처럼 아직 돈이
/// 들어오지 않은 신청은 승인만으로 확정이 아닌데, 거기에 "최종 확정"이라고
/// 적으면 호스트는 입금 확인이 남은 줄 모른 채 화면을 떠난다.
Future<void> showApplicationDecisionResult(
  BuildContext context, {
  required String personLabel,
  required String decision,

  /// 승인 직전의 결제 상태. 무료 파티나 옛 신청이면 null이다.
  PaymentStatus? paymentStatus,
}) {
  final approved = decision == 'approved';
  return showActionResultDialog(
    context,
    title: approved ? '신청 승인 완료!' : '신청 거절 처리 완료',
    message: approved
        ? '$personLabel님의 신청을 승인했어요.\n${_nextStep(paymentStatus)}'
        : '$personLabel님의 신청을 거절 처리했습니다.',
    // 거절도 같은 자리에 같은 모양으로 알리되, 색까지 축하하지는 않는다.
    accent: approved ? PartyChuColors.primary : PartyChuColors.muted,
  );
}

/// 입금 확인 완료 — 서버가 결제완료(paid)와 신청 확정을 함께 처리한 뒤다.
Future<void> showDepositConfirmedResult(
  BuildContext context, {
  required String personLabel,
}) => showActionResultDialog(
  context,
  title: '입금 확인 완료!',
  message: '$personLabel님의 입금을 확인했어요.\n신청이 최종 확정되었습니다.',
);

String _nextStep(PaymentStatus? status) {
  if (status == null || !status.isUnpaid) return '참가 신청이 최종 확정되었습니다.';
  if (status == PaymentStatus.onSiteScheduled) {
    return '현장에서 결제하면 최종 확정됩니다.';
  }
  return '입금 확인 후 최종 확정됩니다.';
}
