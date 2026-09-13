import 'package:flutter/material.dart';
import 'package:party_app/utils/refund_policy.dart';
import 'package:party_app/widgets/refund_policy_editor.dart';

/// 환불 규정 편집 화면 — 기존 `RefundPolicyEditor`(수정하지 않음)를 감싼
/// 얇은 전체화면 래퍼. `RefundPolicyEditor.onChanged`가 매 변경마다 즉시
/// [onChanged]로 값을 흘려보내므로 별도 draft/완료 버튼이 필요 없다.
///
/// 다만 그 "매 변경마다 즉시 적용"이 상단 ← 하나로는 드러나지 않아, 값을
/// 바꾸고 나가도 취소한 것처럼 보였다. 그래서 뒤로가기 아이콘을
/// "← 적용 후 뒤로가기" 텍스트 액션으로 바꿔 의미를 드러낸다. 저장 경로는
/// 여전히 하나뿐이다 — 이 버튼이 하는 일도 pop 뿐이라, 안드로이드 시스템
/// 뒤로가기/제스처로 나가도 결과가 완전히 같다.
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
      appBar: AppBar(
        // ← 아이콘 대신 글자를 놓는다. 글자가 들어갈 폭이 필요해서
        // leadingWidth를 함께 늘린다(기본 56이면 잘린다).
        automaticallyImplyLeading: false,
        leadingWidth: 160,
        leading: Navigator.of(context).canPop()
            ? _ApplyAndBackAction(onTap: () => Navigator.maybePop(context))
            : null,
        title: const Text(
          '환불 규정',
          style: TextStyle(
            fontFamily: 'SeoulHangang',
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
              Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
            ],
          ),
        ),
        centerTitle: true,
      ),
      // 키보드가 올라오면 body 영역 자체가 그만큼 줄어든다(Flutter 기본값이지만
      // 이 화면에서는 잘림 방지가 핵심이라 의도를 분명히 적어둔다).
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        // 목록·여백을 전부 에디터가 직접 그린다 — 구간을 수십 개 추가해도
        // SliverList로 지연 생성돼 오버플로가 나지 않고, 키보드 높이만큼
        // 아래 여백이 늘어나 마지막 구간과 버튼까지 스크롤로 닿는다.
        child: RefundPolicyEditor(
          initialTiers: initialTiers,
          onChanged: onChanged,
          scrollable: true,
          padding: const EdgeInsets.all(16),
        ),
      ),
    );
  }
}

/// AppBar의 ← 자리를 대신하는 텍스트 액션. 눌러서 하는 일은 pop 하나뿐이고,
/// 값 적용은 편집 중에 이미 끝나 있다 — 저장 경로를 늘리지 않는다.
class _ApplyAndBackAction extends StatelessWidget {
  final VoidCallback onTap;

  const _ApplyAndBackAction({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.arrow_back, size: 18),
        label: const Text(
          '적용 후 뒤로가기',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
          minimumSize: const Size(0, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
