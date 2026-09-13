import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:party_app/models/payment_method.dart';
import 'package:party_app/models/payment_status.dart';

/// 이용자 화면(내 신청·내 예약)에 붙는 **결제 상태 + 무통장입금 안내** 한 덩어리.
///
/// 파티 신청과 플레이스 방문예약이 같은 위젯을 쓴다 — 두 곳에 따로 그리면
/// "여기서는 계좌가 보이는데 저기서는 안 보인다" 같은 차이가 곧 생긴다.
/// 도메인마다 다른 것은 **'입금했어요'를 누르면 무엇을 부르는가**([onMarkSent])
/// 하나뿐이다.
///
/// 버튼은 [PaymentStatus.canMarkDepositSent]일 때만 뜬다 — 이미 알린 뒤
/// (입금확인중)에는 사라져서 두 번 누를 수 없고, 서버도 같은 조건을 다시
/// 확인한다(depositFlow.assertCanMarkSent).
class DepositPanel extends StatefulWidget {
  final PaymentInfo payment;

  /// '입금했어요'를 눌렀을 때 부를 서버 호출. null이면 버튼을 그리지 않는다
  /// (호스트 화면처럼 보기만 하는 자리).
  final Future<void> Function()? onMarkSent;

  /// 성공했을 때 띄울 문구.
  final String sentMessage;

  const DepositPanel({
    super.key,
    required this.payment,
    this.onMarkSent,
    this.sentMessage = '입금 확인을 요청했어요.',
  });

  @override
  State<DepositPanel> createState() => _DepositPanelState();
}

class _DepositPanelState extends State<DepositPanel> {
  bool _sending = false;

  PaymentInfo get _p => widget.payment;

  /// 12,000원 — 천 단위 구분.
  static String _formatWon(int won) {
    final s = won.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '$b원';
  }

  Future<void> _markSent() async {
    final call = widget.onMarkSent;
    if (call == null) return;
    setState(() => _sending = true);
    try {
      await call();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(widget.sentMessage)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(depositErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unpaid = _p.status.isUnpaid;
    final showBank = _p.method == PaymentMethod.bankTransfer && unpaid;
    // 승인 전에는 입금을 요구하지 않으므로 계좌도 버튼도 띄우지 않는다.
    final beforeApproval = _p.status == PaymentStatus.awaitingApproval;
    final canMarkSent =
        widget.onMarkSent != null &&
        _p.method == PaymentMethod.bankTransfer &&
        _p.status.canMarkDepositSent;
    final color = unpaid ? const Color(0xFFE2568A) : Colors.black45;
    // 안내 당시 계좌(스냅샷) 우선, 없으면 현재 상수로 폴백한다.
    final account = _p.bankAccount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_p.method.icon, size: 13, color: color),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                '${_p.status.label} · ${_p.method.label}'
                '${unpaid ? ' — ${_p.status.description}' : ''}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        if (showBank && !beforeApproval) ...[
          const SizedBox(height: 8),
          // 얼마를 넣어야 하는지가 가장 먼저 눈에 들어와야 한다 — 계좌만 있고
          // 금액이 없으면 사용자가 다른 화면을 뒤져 금액을 찾아와야 했다.
          if (_p.amount != null && _p.amount! > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Text(
                    '입금할 금액 ',
                    style: TextStyle(fontSize: 11.5, color: Colors.black54),
                  ),
                  Text(
                    _formatWon(_p.amount!),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFE2568A),
                    ),
                  ),
                ],
              ),
            ),
          // 계좌가 없는 건은 계좌 줄을 **아예 그리지 않는다.** 예전에는 없으면
          // 파티츄 공용 계좌를 대신 보여줬는데, 지금 참가비는 호스트가 직접
          // 받으므로 그 폴백은 곧 "엉뚱한 계좌로 송금"이 된다.
          if (account == null)
            Text(
              '입금 계좌를 불러오지 못했어요. 호스트에게 문의해주세요.'
              '${_p.depositDeadline == null ? '' : '\n${formatDeadline(_p.depositDeadline!)}까지'}',
              style: const TextStyle(
                fontSize: 11,
                height: 1.4,
                color: Colors.black54,
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    // 계좌는 **주문 당시 안내한 값(스냅샷)**이다 — 호스트가
                    // 나중에 계좌를 바꿔도 이 건은 그때 안내한 계좌 그대로다.
                    '${account.bank} ${account.number} (${account.holder})'
                    '${_p.depositDeadline == null ? '' : '\n${formatDeadline(_p.depositDeadline!)}까지'}',
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: Colors.black54,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    await Clipboard.setData(
                      ClipboardData(
                        text:
                            '${account.bank} '
                            '${account.number.replaceAll('-', '')}',
                      ),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('계좌번호를 복사했어요.')),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      '복사',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE2568A),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
        if (canMarkSent) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ElevatedButton(
              onPressed: _sending ? null : _markSent,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6FA0),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                _sending ? '요청 중…' : '입금했어요',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// '8월 15일(토) 오후 3:20' — 입금기한 표기.
String formatDeadline(DateTime d) {
  const week = ['월', '화', '수', '목', '금', '토', '일'];
  final ampm = d.hour < 12 ? '오전' : '오후';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${d.month}월 ${d.day}일(${week[d.weekday - 1]}) '
      '$ampm $h:${d.minute.toString().padLeft(2, '0')}';
}

/// Cloud Functions 오류에서 사용자에게 보여줄 문구만 뽑는다 — 서버가 이미
/// 사람이 읽을 한국어로 돌려주므로(예: '이미 입금 확인을 기다리고 있어요.')
/// 그대로 쓴다.
String depositErrorMessage(Object e, [String fallback = '요청에 실패했어요.']) {
  final msg = (e as dynamic);
  try {
    final m = msg.message;
    if (m is String && m.isNotEmpty) return m;
  } catch (_) {}
  return fallback;
}
