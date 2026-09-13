import 'package:flutter/material.dart';

import 'package:party_app/models/payment_policy.dart';
import 'package:party_app/widgets/payment_policy_section.dart';

/// 파티 등록·수정 화면의 **결제 방식** 바텀시트.
///
/// 파티 화면은 항목마다 요약 줄([SectionSummaryRow]) + 시트로 구성돼 있어
/// 다른 항목들과 같은 방식으로 연다. 시트 안의 내용은 장소대여·플레이스와
/// 공유하는 [PaymentPolicySection]이 그대로 그린다 — 계산 규칙과 저장 형태가
/// 세 도메인에서 갈라지지 않게 하기 위함이다.
///
/// [sampleTotal]은 계산 예시에 쓰는 참가비다. 참가비를 아직 안 넣었으면 null을
/// 넘기면 되고, 시트는 "금액을 먼저 입력하면 예시가 나와요"라고만 안내한다.
///
/// **무료 파티에서는 이 시트를 열지 않는다** — 호출부가 참가비 0원일 때
/// 요약 줄 자체를 숨긴다.
Future<PaymentPolicy?> showPaymentPolicySheet(
  BuildContext context, {
  required PaymentPolicy initial,
  required int? sampleTotal,
}) {
  return showModalBottomSheet<PaymentPolicy>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) =>
        _PaymentPolicySheetBody(initial: initial, sampleTotal: sampleTotal),
  );
}

class _PaymentPolicySheetBody extends StatefulWidget {
  final PaymentPolicy initial;
  final int? sampleTotal;

  const _PaymentPolicySheetBody({
    required this.initial,
    required this.sampleTotal,
  });

  @override
  State<_PaymentPolicySheetBody> createState() =>
      _PaymentPolicySheetBodyState();
}

class _PaymentPolicySheetBodyState extends State<_PaymentPolicySheetBody> {
  late PaymentPolicy _policy = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PaymentPolicySection.party(
                policy: _policy,
                sampleTotal: widget.sampleTotal,
                onChanged: (p) => setState(() => _policy = p),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  // 예약금을 켜 놓고 금액을 비워 둔 채로는 닫을 수 없다 —
                  // 그대로 저장되면 참가자가 신청할 때 서버가 거절한다.
                  onPressed: _policy.isComplete
                      ? () => Navigator.pop(context, _policy)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6FA0),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.black12,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '선택 완료',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
