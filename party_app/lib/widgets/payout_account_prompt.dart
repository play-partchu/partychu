import 'package:flutter/material.dart';

import 'package:party_app/models/payout_account.dart';
import 'package:party_app/screens/payout_account_screen.dart';
import 'package:party_app/services/payout_account_service.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 무통장입금을 받으려면 **인증된 수취계좌**가 있어야 한다 — 없으면 안내하고
/// 계좌 화면으로 보낸다.
///
/// 파티·장소대여·플레이스 등록 화면이 "선결제/예약금"을 고르는 순간 부른다.
/// 참가비는 파티츄가 아니라 호스트 계좌로 바로 들어가므로, 계좌가 없으면
/// 참가자가 무통장입금을 아예 고를 수 없다 — 그 사실을 **등록할 때** 알려주는
/// 것이 목적이다(모집을 열고 나서 "왜 아무도 신청을 못 하지"가 되지 않게).
///
/// 이미 인증돼 있으면 아무것도 띄우지 않고 곧바로 true를 돌려준다.
///
/// 계좌 화면에 다녀오면 상태를 **다시 확인해서** 돌려준다 — 거기서 인증을
/// 마쳤다면 그대로 진행하고, 안 했다면 고르지 않은 상태로 남는다.
Future<bool> ensurePayoutAccountVerified(BuildContext context) async {
  final account = await PayoutAccountService.fetch();
  if (account.isVerified) return true;
  if (!context.mounted) return false;

  final goRegister = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        '입금받을 계좌를 먼저 등록해주세요',
        style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
      ),
      content: Text(
        account.status == PayoutAccountStatus.required
            ? '등록한 계좌가 아직 인증되지 않았어요.\n'
                  '인증을 마쳐야 참가자가 무통장입금으로 신청할 수 있어요.'
            : '참가비는 호스트 계좌로 바로 입금돼요.\n'
                  '계좌를 등록·인증해야 참가자가 무통장입금을 고를 수 있어요.',
        style: const TextStyle(fontSize: 13.5, height: 1.5),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom(foregroundColor: Colors.black45),
          child: const Text('나중에 하기'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFF6FA0),
          ),
          child: const Text('계좌 등록하기'),
        ),
      ],
    ),
  );

  if (goRegister != true || !context.mounted) return false;

  await Navigator.push(
    context,
    webFramedRoute((_) => const PayoutAccountScreen()),
  );
  // 다녀온 뒤의 상태가 정본이다 — 화면에서 인증을 마쳤을 수 있다.
  final after = await PayoutAccountService.fetch();
  return after.isVerified;
}

/// 콘텐츠 등록을 **막 마친 호스트**에게 수취계좌 등록을 이어 준다.
///
/// 파티·플레이스·장소대여가 모두 이 함수 하나를 부른다 — 등록 종류마다 다른
/// 안내를 만들면 어느 하나는 반드시 빠진다.
///
/// ── 왜 정산계좌가 아니라 수취계좌인가 ────────────────────────────────────
/// 예전에는 등록 직후 '정산 계좌 등록'을 띄웠다. 그 계좌(users/{uid}.
/// settlementInfo)는 **파티츄가 호스트에게 보낼** 계좌인데, 지금 구조에는 그
/// 송금 자체가 없다 — 참가비는 파티츄를 거치지 않고 호스트 계좌로 바로
/// 들어간다. 그래서 등록 직후 실제로 필요한 것은 **수취계좌**뿐이고, 정산계좌
/// 안내는 아직 오지 않은 흐름을 재촉하는 셈이라 없앴다.
/// (정산계좌 화면과 데이터는 그대로 있다 — 마이페이지에서 언제든 들어간다.)
///
/// ── 언제 띄우나 ──────────────────────────────────────────────────────────
///  · [usesBankTransfer]가 false면(무료 콘텐츠 등) **아무것도 띄우지 않는다.**
///    받을 돈이 없는데 계좌를 재촉할 이유가 없다.
///  · 이미 인증된 수취계좌가 있으면 그냥 지나간다.
/// 즉 "돈을 받는데 받을 계좌가 없는" 경우에만 뜬다.
Future<void> promptPayoutAccountAfterRegister(
  BuildContext context, {

  /// '무엇을' 등록했는지 — 문구에 그대로 들어간다('파티', '플레이스', '장소').
  required String what,

  /// 이 콘텐츠가 무통장입금(선결제·예약금 포함)을 받을 수 있는지.
  required bool usesBankTransfer,
}) async {
  if (!usesBankTransfer) return;
  final account = await PayoutAccountService.fetch();
  if (account.isVerified || !context.mounted) return;

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
      content: Text(
        account.status == PayoutAccountStatus.required
            ? '입금받을 계좌가 아직 인증되지 않았어요.\n'
                  '인증을 마쳐야 참가자가 무통장입금으로 신청할 수 있어요.'
            : '입금받을 계좌를 등록해주세요.\n'
                  '참가비는 파티츄를 거치지 않고 이 계좌로 바로 들어와요.\n'
                  '계좌가 없으면 참가자가 무통장입금을 고를 수 없어요.',
        style: const TextStyle(fontSize: 14, height: 1.5),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        // 보조 액션 — 텍스트 버튼으로 낮춰 둔다.
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom(foregroundColor: Colors.black45),
          child: const Text('나중에 하기'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFF6FA0),
          ),
          child: const Text('입금받을 계좌 등록하기'),
        ),
      ],
    ),
  );

  if (goRegister != true || !context.mounted) return;
  await Navigator.push(
    context,
    webFramedRoute((_) => const PayoutAccountScreen()),
  );
}

/// 사업자 인증을 **막 마친 호스트**에게 무통장입금 인증을 이어 준다.
///
/// [BusinessVerificationScreen]이 인증 성공 직후 부른다. 위
/// [promptPayoutAccountAfterRegister]와 같은 화면([PayoutAccountScreen])으로
/// 보내고 같은 정본([PayoutAccountService])을 본다 — 무통장입금 인증 경로를
/// 새로 만들지 않는다.
///
/// ── 사업자 인증과는 별개다 ───────────────────────────────────────────────
/// 이 안내를 건너뛰어도 사업자 인증 완료 상태는 그대로다. 현장결제는 수취계좌
/// 인증 없이 쓸 수 있고, **무통장입금을 결제수단으로 켤 때만** 인증이 필요하다
/// — 그 강제는 여기가 아니라 결제수단을 고르는 자리
/// ([ensurePayoutAccountVerified])와 서버
/// (`functions/payoutAccounts.js`의 `assertBankTransferPayable`)가 한다.
/// 그래서 '나중에 할게요'로 닫아도 나중에 무통장입금을 켜려는 순간 다시
/// 인증을 요구받는다.
///
/// 이미 수취계좌 인증을 마친 호스트에게는 **아무것도 띄우지 않는다.**
Future<void> promptBankTransferSetupAfterBusinessVerification(
  BuildContext context,
) async {
  final account = await PayoutAccountService.fetch();
  if (account.isVerified || !context.mounted) return;

  final goVerify = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        '무통장입금 설정도 완료해주세요',
        style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
      ),
      content: const Text(
        '현재 파티츄에서는 현장결제와 무통장입금을 이용할 수 있어요.\n\n'
        '무통장입금 기능을 사용하려면 무통장입금 인증을 필수로 완료해주세요.',
        style: TextStyle(fontSize: 13.5, height: 1.5),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom(foregroundColor: Colors.black45),
          child: const Text('나중에 할게요'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFF6FA0),
          ),
          child: const Text('무통장입금 인증하기'),
        ),
      ],
    ),
  );

  if (goVerify != true || !context.mounted) return;
  await Navigator.push(
    context,
    webFramedRoute((_) => const PayoutAccountScreen()),
  );
}
