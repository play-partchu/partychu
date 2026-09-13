import 'package:flutter/material.dart';

import 'package:party_app/models/payment_method.dart';
import 'package:party_app/models/payment_order_summary.dart';
import 'package:party_app/models/payment_policy.dart';
import 'package:party_app/models/payment_status.dart';
import 'package:party_app/services/payout_account_service.dart';
import 'package:party_app/utils/format_utils.dart' as fmt;
import 'package:party_app/widgets/early_bird_price_line.dart';
import 'package:party_app/widgets/partychu_ui.dart';
import 'package:party_app/widgets/payment_breakdown_card.dart';

/// 파티 신청 · 플레이스 방문예약 · 장소대여 · 파티샵 주문이 **함께 쓰는**
/// 결제수단 선택 화면.
///
/// 도메인마다 다른 것은 맨 위 주문 정보([PaymentOrderSummary])뿐이고, 결제수단
/// 목록과 선택 후 안내는 네 곳이 완전히 같은 화면을 본다.
///
/// PG 계약 전이라 **무통장입금·현장결제만** 고를 수 있다. 나머지는 자물쇠와
/// '준비중'만 붙여 목록에 남겨두고, 누르면 안내 한 줄만 띄운다
/// ([PaymentMethod.notReadyMessage]) — 결제 로직도, 가짜 성공 응답도 만들지
/// 않는다. PG가 붙으면 [PaymentMethod]의 `available`만 켜면 이 화면은 그대로
/// 동작한다.
///
/// 돌려주는 값은 [PaymentInfo]이고, 취소하면 null이다. 실제 신청·예약·주문
/// 생성은 **호출한 도메인이** 이 값을 받아서 자기 방식대로 한다(이 화면은
/// 아무것도 저장하지 않는다).
class PaymentMethodScreen extends StatefulWidget {
  final PaymentOrderSummary summary;

  /// 무통장입금 입금자명의 기본값 — 보통 로그인한 사용자의 이름/닉네임.
  final String? defaultDepositorName;

  /// 호스트가 정한 결제 방식에 따른 금액 분해 — "지금 얼마 / 나중에 얼마".
  /// null이면 지금까지처럼 주문 정보의 총액만 보여준다(설정이 없는 기존
  /// 파티·장소).
  final PaymentBreakdown? breakdown;

  /// 이 예약에서 고를 수 있는 결제수단. null이면 지금까지처럼 열려 있는
  /// 수단을 모두 보여준다.
  ///
  /// 호스트가 "현장 전액결제"로 정했는데 무통장입금을 고르게 두면 서버가
  /// 거절하므로, 애초에 목록에서 빼서 헛걸음을 막는다(서버도 같은 규칙을
  /// 다시 확인한다 — paymentPolicy.assertMethodAllowed).
  final List<PaymentMethod>? allowedMethods;

  /// 돈을 **받을 사람**(파티 호스트 · 매장 업주 · 샵 판매자)의 uid.
  ///
  /// 무통장입금은 그 호스트가 **인증된 수취계좌를 갖고 있을 때만** 열린다 —
  /// 참가비는 파티츄가 아니라 호스트 계좌로 바로 들어가기 때문이다
  /// (functions/payoutAccounts.js). 판정은 이 화면이 한 번만 물어보고
  /// ([PayoutAccountService.hostCanReceiveBankTransfer]), 최종 확인은 주문을
  /// 만들 때 서버가 다시 한다.
  ///
  /// 도메인마다 이 판정을 따로 짜면 어느 하나는 반드시 빠지므로, 호출부는
  /// **호스트 uid만** 넘기고 규칙은 여기 한 곳에 둔다.
  final String hostId;

  const PaymentMethodScreen({
    super.key,
    required this.summary,
    required this.hostId,
    this.defaultDepositorName,
    this.breakdown,
    this.allowedMethods,
  });

  @override
  State<PaymentMethodScreen> createState() => _PaymentMethodScreenState();
}

class _PaymentMethodScreenState extends State<PaymentMethodScreen> {
  PaymentMethod? _selected;
  late final TextEditingController _depositor = TextEditingController(
    text: widget.defaultDepositorName ?? '',
  );

  /// 입금기한은 화면에 들어온 순간을 기준으로 계산해 그대로 보여주고, 그대로
  /// 넘긴다(보여준 시각과 저장되는 시각이 어긋나지 않게).
  final DateTime _openedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadHostBankTransfer();
  }

  Future<void> _loadHostBankTransfer() async {
    final ok = await PayoutAccountService.hostCanReceiveBankTransfer(
      widget.hostId,
    );
    if (!mounted) return;
    setState(() {
      _hostCanReceiveBankTransfer = ok;
      // 확인 전에 골라 둔 값이 사라진 수단이면 선택을 비운다.
      if (!ok && _selected == PaymentMethod.bankTransfer) _selected = null;
    });
  }

  @override
  void dispose() {
    _depositor.dispose();
    super.dispose();
  }

  DateTime get _deadline => DepositWindow.deadlineFrom(_openedAt);

  /// 이 호스트가 무통장입금을 받을 수 있는가. null이면 아직 확인 중이다.
  ///
  /// "모름"과 "못 받음"을 구분하는 이유는, 확인 전에 목록을 그리면 무통장입금이
  /// 잠깐 보였다 사라지기 때문이다 — 고르려던 수단이 눈앞에서 없어지는 것보다
  /// 잠깐 기다리는 쪽이 낫다.
  bool? _hostCanReceiveBankTransfer;

  /// 이 화면에서 실제로 고를 수 있는 수단.
  List<PaymentMethod> get _usableMethods {
    final allowed = widget.allowedMethods;
    final base = allowed == null
        ? PaymentMethod.usable
        : PaymentMethod.usable.where(allowed.contains).toList();
    // 호스트가 계좌를 인증하지 않았으면 무통장입금은 **아예 목록에 없다**.
    // 비활성으로 남겨 두면 "왜 못 고르지"를 설명해야 하고, 고르고 나서
    // 서버가 거절하면 그때는 이미 헛걸음이다.
    if (_hostCanReceiveBankTransfer == true) return base;
    return base.where((m) => m != PaymentMethod.bankTransfer).toList();
  }

  /// '8월 15일 (토) 오후 3:20까지' — 기한은 분 단위까지 분명히 적는다.
  String get _deadlineText {
    const week = ['월', '화', '수', '목', '금', '토', '일'];
    final d = _deadline;
    final ampm = d.hour < 12 ? '오전' : '오후';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${d.month}월 ${d.day}일(${week[d.weekday - 1]}) '
        '$ampm $h:${d.minute.toString().padLeft(2, '0')}까지';
  }

  void _pick(PaymentMethod method) {
    if (!method.available) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text(PaymentMethod.notReadyMessage),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      return;
    }
    setState(() => _selected = method);
  }

  void _submit() {
    final method = _selected;
    final status = method == null ? null : PaymentStatus.initialFor(method);
    if (method == null || status == null) return;
    Navigator.pop(
      context,
      PaymentInfo(
        method: method,
        status: status,
        depositorName: method == PaymentMethod.bankTransfer
            ? _depositor.text.trim()
            : null,
        depositDeadline: method == PaymentMethod.bankTransfer
            ? _deadline
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final domain = widget.summary.domain;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0.5,
        title: Text(
          domain.title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          _orderCard(),
          // 지금 낼 돈과 현장에서 낼 돈을 주문 정보 바로 아래에서 못 박는다.
          if (widget.breakdown != null) ...[
            const SizedBox(height: 12),
            PaymentBreakdownCard(
              breakdown: widget.breakdown!,
              totalLabel: widget.summary.amountLabel,
              // 결제 요약의 총액 줄에도 같은 "정상가 → 할인가"를 쓴다.
              originalTotal: widget.summary.originalAmount,
              discountLabel: widget.summary.discountLabel,
            ),
          ],
          const SizedBox(height: 14),
          _sectionTitle('결제수단'),
          const SizedBox(height: 8),
          // 지금 고를 수 있는 것 먼저, 준비중은 그 아래로 — 목록 순서만으로도
          // 무엇이 되는지 바로 보인다.
          if (_hostCanReceiveBankTransfer == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: PartyChuColors.primary,
                  ),
                ),
              ),
            )
          else ...[
            for (final m in _usableMethods) _methodTile(m),
            // 무통장입금이 빠진 이유를 적어 둔다 — 목록에서 조용히 사라지면
            // "왜 없지"를 묻게 되고, 그 답을 아는 사람이 아무도 없다.
            if (_hostCanReceiveBankTransfer == false)
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 4),
                child: Text(
                  '이 호스트는 아직 입금받을 계좌를 인증하지 않아 무통장입금을 받을 수 없어요.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: Colors.black45,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 10),
          _sectionTitle('준비중'),
          const SizedBox(height: 8),
          for (final m in PaymentMethod.preparing) _methodTile(m),
          if (_selected != null) ...[
            const SizedBox(height: 14),
            _guide(_selected!),
          ],
        ],
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  // ── 주문 정보(도메인마다 다른 유일한 부분) ───────────────────────────
  Widget _orderCard() {
    final s = widget.summary;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEFEFF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(s.domain.icon, size: 16, color: PartyChuColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  s.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final line in s.lines) _infoRow(line.label, line.value),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Color(0xFFF0F0F4)),
          ),
          Row(
            children: [
              Text(
                s.amountLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              // 얼리버드처럼 할인이 걸린 신청은 정상가를 취소선으로 함께
              // 보여준다 — 할인가만 있으면 그게 할인가인지 알 수 없다.
              // 할인 여부·금액은 호출부가 정본 로직으로 정해 넘긴 값이다.
              if (s.hasDiscount)
                Flexible(
                  child: EarlyBirdPriceLine(
                    originalAmount: s.originalAmount!,
                    discountedAmount: s.amount,
                    label: s.discountLabel ?? '할인',
                  ),
                )
              else
                Text(
                  // ⚠ formatPrice는 이미 '원'을 붙이고("5만원") 1만원 이상을
                  //   반올림한다 — 여기에 '원'을 또 붙여 "5만원원"이 나왔고,
                  //   바로 아래 금액 분해 카드의 정확한 금액과도 어긋났다.
                  //   실제로 결제하는 금액을 보여주는 자리이므로 원 단위로 적는다.
                  s.amount <= 0 ? '무료' : fmt.formatWon(s.amount),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: PartyChuColors.primary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: Colors.black45),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3A3A3A),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
  );

  // ── 결제수단 한 줄 ──────────────────────────────────────────────────
  Widget _methodTile(PaymentMethod m) {
    final selected = _selected == m;
    final ready = m.available;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _pick(m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: ready ? Colors.white : const Color(0xFFF3F3F6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? PartyChuColors.primary
                  : const Color(0xFFEFEFF3),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                m.icon,
                size: 20,
                color: !ready
                    ? Colors.black26
                    : selected
                    ? PartyChuColors.primary
                    : Colors.black54,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          m.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: ready ? Colors.black87 : Colors.black38,
                          ),
                        ),
                        if (!ready) ...[
                          const SizedBox(width: 6),
                          _preparingBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      m.description,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: ready ? Colors.black45 : Colors.black26,
                      ),
                    ),
                  ],
                ),
              ),
              if (ready)
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: selected ? PartyChuColors.primary : Colors.black26,
                )
              else
                const Icon(Icons.lock_rounded, size: 16, color: Colors.black26),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preparingBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xFFE9E9EE),
      borderRadius: BorderRadius.circular(6),
    ),
    child: const Text(
      '준비중',
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: Colors.black45,
      ),
    ),
  );

  // ── 고른 수단별 안내 ────────────────────────────────────────────────
  Widget _guide(PaymentMethod m) => switch (m) {
    PaymentMethod.bankTransfer => _bankGuide(),
    PaymentMethod.onSite => _onSiteGuide(),
    // 준비중인 수단은 고를 수 없으므로 안내도 없다.
    _ => const SizedBox.shrink(),
  };

  Widget _bankGuide() {
    final noun = widget.summary.domain.resultNoun;
    return _guideCard(
      title: '입금 안내',
      status: PaymentStatus.awaitingDeposit,
      children: [
        // 계좌는 **여기서 보여주지 않는다.**
        //
        // 참가비는 호스트 계좌로 바로 들어가는데, 그 계좌를 아직 주문도 하지
        // 않은 사람 모두에게 미리 뿌릴 이유가 없다. 계좌는 신청·예약·주문이
        // 실제로 만들어질 때 서버가 그 문서에 박아 주고([PaymentInfo]),
        // 당사자만 자기 내역에서 본다.
        _guideRow('입금 계좌', '$noun 완료 후 안내해 드려요'),
        _guideRow('입금기한', _deadlineText),
        const SizedBox(height: 10),
        // 입금자명이 다르면 확인이 늦어지므로 여기서 미리 받아 둔다.
        const Text(
          '입금자명',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _depositor,
          decoration: InputDecoration(
            hintText: '입금하실 분의 이름',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE5E5EA)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE5E5EA)),
            ),
          ),
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 10),
        _notice('입금 확인 후 $noun이 확정돼요. 기한까지 입금하지 않으면 자동 취소됩니다.'),
      ],
    );
  }

  Widget _onSiteGuide() {
    final noun = widget.summary.domain.resultNoun;
    return _guideCard(
      title: '현장결제 안내',
      status: PaymentStatus.onSiteScheduled,
      children: [
        _notice('현장에서 결제해주세요. 지금은 결제가 이뤄지지 않습니다.'),
        const SizedBox(height: 6),
        _notice('업주·호스트 승인 후 $noun이 확정될 수 있어요.'),
      ],
    );
  }

  Widget _guideCard({
    required String title,
    required PaymentStatus status,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PartyChuColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              // 결제완료로 오인되지 않도록 될 상태를 그대로 붙여 보여준다.
              _statusChip(status),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _statusChip(PaymentStatus status) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: PartyChuColors.surfaceTint,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: PartyChuColors.border),
    ),
    child: Text(
      status.label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: PartyChuColors.primaryDeep,
      ),
    ),
  );

  Widget _guideRow(String label, String value) => Padding(
    // 계좌 복사 버튼은 여기서 없앴다 — 이 화면은 더 이상 계좌를 보여주지
    // 않는다(주문이 만들어진 뒤 내 내역의 [DepositPanel]에 복사 버튼이 있다).
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: Colors.black45),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Widget _notice(String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.info_outline_rounded, size: 13, color: Colors.black38),
      const SizedBox(width: 5),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: Colors.black54,
          ),
        ),
      ),
    ],
  );

  // ── 하단 ────────────────────────────────────────────────────────────
  Widget _bottomBar() {
    final method = _selected;
    final status = method == null ? null : PaymentStatus.initialFor(method);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status != null) ...[
              Text(
                // 버튼을 누르면 무엇이 되는지 미리 말해준다 — '결제완료'가
                // 아니라는 것이 여기서 한 번 더 드러난다.
                '${widget.summary.domain.resultNoun} 상태: ${status.label}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.black45,
                ),
              ),
              const SizedBox(height: 6),
            ],
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: status == null ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: PartyChuColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE5E5EA),
                  disabledForegroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  status == null
                      ? '결제수단을 선택해주세요'
                      : widget.summary.domain.actionLabel,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
