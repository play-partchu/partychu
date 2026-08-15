import 'package:flutter/material.dart';

import 'package:party_app/screens/settlement_info_screen.dart';
import 'package:party_app/services/settlement_account_service.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 등록을 막 마친 호스트에게 **정산계좌 등록으로 바로 이어주는** 안내.
///
/// 파티·플레이스·장소대여가 모두 같은 함수를 부른다 — 등록 종류마다 다른
/// 안내를 만들면 어느 하나는 반드시 빠진다.
///
/// 정산계좌가 이미 있으면 **아무것도 띄우지 않고 그냥 지나간다**([hasAccount]).
/// 등록할 때마다 계좌를 다시 묻는 화면이 되면 안 된다.
///
/// 기본 액션은 '정산 계좌 등록하기'다 — 지금 등록해 두지 않으면 정산할 방법이
/// 없으므로, '나중에 하기'는 눈에 덜 띄는 보조 자리에 둔다.
Future<void> promptSettlementAccountIfMissing(
  BuildContext context, {

  /// '무엇을' 등록했는지 — 문구에 그대로 들어간다('파티', '플레이스', '장소').
  required String what,
}) async {
  if (await SettlementAccountService.hasAccount()) return;
  if (!context.mounted) return;

  final goRegister = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFFFF6FA0), size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$what 등록이 완료되었습니다',
              style: const TextStyle(
                fontFamily: 'SeoulHangang',
                fontSize: 17,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      content: const Text(
        '정산받을 계좌를 등록해주세요.\n'
        '계좌가 없으면 정산 대금을 보내드릴 수 없어요.',
        style: TextStyle(fontSize: 14, height: 1.5),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        // 보조 액션 — 텍스트 버튼으로 낮춰 둔다.
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom(foregroundColor: Colors.black45),
          child: const Text('나중에 하기'),
        ),
        // 기본 액션 — 가장 눈에 띄게.
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6FA0),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          child: const Text('정산 계좌 등록하기'),
        ),
      ],
    ),
  );

  if (goRegister != true || !context.mounted) return;
  await Navigator.push(
    context,
    webFramedRoute((_) => const SettlementInfoScreen()),
  );
}
