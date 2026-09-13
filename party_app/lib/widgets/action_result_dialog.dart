import 'package:flutter/material.dart';
import 'package:party_app/widgets/partychu_ui.dart';

/// 호스트가 신청자의 상태를 **실제로 바꾼 뒤에** 띄우는 완료 팝업.
///
/// ── 왜 스낵바로는 부족한가 ─────────────────────────────────────────────────
///
/// 승인·거절·입금확인은 상대방의 참가 여부가 걸린 처리이고 되돌리기도 어렵다.
/// 화면 맨 아래에 몇 초 떴다 사라지는 안내로는 "정말 처리됐나?"가 남는다.
/// 그래서 뒤를 어둡게 깔고 화면 가운데 세워, 호스트가 확인을 눌러야 넘어간다.
///
/// ── 부르는 시점이 이 위젯의 절반이다 ───────────────────────────────────────
///
/// **서버가 성공으로 답한 뒤에만** 부른다. 버튼을 누른 순간에 미리 띄우면
/// 실패한 처리를 성공이라고 알리게 된다. 실패는 기존 오류 안내(스낵바)가
/// 그대로 맡고, 이 팝업은 뜨지 않는다.
///
/// 그리고 **같은 처리에 스낵바를 겹쳐 띄우지 않는다** — 성공 피드백은 이
/// 팝업 하나로 끝낸다.
///
/// 저장·수정 같은 가벼운 처리까지 이걸로 바꾸지는 않는다. 매번 확인을 눌러야
/// 하면 그 순간부터 아무도 읽지 않는 팝업이 된다.
Future<void> showActionResultDialog(
  BuildContext context, {
  required String title,
  required String message,

  /// 아이콘 배지 색. 승인·입금확인 같은 반가운 처리는 기본 핑크를 쓰고,
  /// 거절처럼 축하할 일이 아닌 처리는 차분한 색을 넘긴다 — 같은 자리에 같은
  /// 모양으로 뜨되, 색까지 축하하지는 않는다.
  Color accent = PartyChuColors.primary,
}) => showDialog<void>(
  context: context,
  // 바깥을 눌러 흘려보내지 못하게 한다 — 중요한 처리의 결과다.
  barrierDismissible: false,
  barrierColor: Colors.black.withValues(alpha: 0.55),
  builder: (context) => Dialog(
    backgroundColor: Colors.white,
    insetPadding: const EdgeInsets.symmetric(horizontal: 32),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_rounded, size: 34, color: accent),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: PartyChuColors.heading,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.6,
              color: PartyChuColors.subtleText,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: PartyChuColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                '확인',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);
