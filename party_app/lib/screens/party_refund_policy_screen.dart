import 'package:flutter/material.dart';
import 'package:party_app/utils/refund_policy.dart';
import 'package:party_app/widgets/refund_policy_editor.dart';

/// 환불 규정 편집 화면 — 기존 `RefundPolicyEditor`(수정하지 않음)를 감싼
/// 얇은 전체화면 래퍼. `RefundPolicyEditor.onChanged`가 매 변경마다 즉시
/// [onChanged]로 값을 흘려보내므로 별도 draft/완료 버튼이 필요 없다.
class PartyRefundPolicyScreen extends StatelessWidget {
  final List<RefundTier> initialTiers;
  final ValueChanged<List<RefundTier>> onChanged;

  const PartyRefundPolicyScreen({
    super.key,
    required this.initialTiers,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('환불 규정', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: RefundPolicyEditor(
          initialTiers: initialTiers,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
