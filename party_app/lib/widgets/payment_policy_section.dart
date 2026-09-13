import 'package:flutter/material.dart';

import 'package:party_app/models/payment_method.dart';
import 'package:party_app/models/payment_policy.dart';
import 'package:party_app/utils/format_utils.dart';
import 'package:party_app/widgets/payout_account_prompt.dart';

/// 호스트가 **결제 방식**을 정하는 공용 설정 카드 — 파티 등록·수정, 장소대여
/// 등록·수정, 플레이스 등록·수정이 이 위젯 하나를 함께 쓴다.
///
/// 서비스마다 성격이 달라 **보여주는 선택지만** 다르고, 계산 규칙과 저장 형태는
/// 완전히 같다([PaymentPolicy] · 서버 `paymentPolicy.js`).
///
/// | 도메인 | 생성자 | 선택지 |
/// |---|---|---|
/// | 파티 | [PaymentPolicySection.party] | 전액 온라인 결제 / 현장 결제(+예약금 토글) |
/// | 장소대여·숙박 | [PaymentPolicySection.modes] | 전액 선결제 / 예약금 / (현장 전액) |
/// | 플레이스 좌석·룸 | [PaymentPolicySection.modes] | 현장 전액 / 전액 선결제 / 예약금 |
///
/// ## 총액이 확정되지 않는 예약
/// [totalKnown]이 false면 **비율(%) 예약금과 전액 선결제를 아예 띄우지 않는다.**
/// 총 이용금액을 모르는데 비율을 계산하는 구조는 만들지 않는다는 뜻이다
/// (좌석만 잡고 음식은 현장에서 주문하는 형태).
///
/// ## 무료
/// 참가비·이용요금이 0원이면 호출부가 이 위젯을 **아예 그리지 않는다** —
/// 받을 돈이 없으면 예약금이라는 개념이 성립하지 않는다.
class PaymentPolicySection extends StatelessWidget {
  final PaymentPolicy policy;
  final ValueChanged<PaymentPolicy> onChanged;

  /// 계산 예시의 기준 금액(참가비·1회 이용요금). 아직 입력 전이면 null.
  final int? sampleTotal;

  /// 총 이용금액이 예약 시점에 확정되는 도메인인지.
  final bool totalKnown;

  /// 파티식 표기 — "전액 온라인 결제 / 현장 결제" 2지선다 + 현장 결제일 때만
  /// 나타나는 '예약금 받기' 토글. 내부 저장값은 다른 도메인과 똑같이
  /// prepaid / partial / onsite 셋 중 하나로 정규화된다.
  final bool nestedUpfrontToggle;

  /// 평면 표기일 때 보여줄 방식들(순서 그대로 그린다).
  final List<PaymentMode> modes;

  final Color accent;
  final String title;
  final String description;

  const PaymentPolicySection._({
    required this.policy,
    required this.onChanged,
    required this.sampleTotal,
    required this.totalKnown,
    required this.nestedUpfrontToggle,
    required this.modes,
    required this.accent,
    required this.title,
    required this.description,
  });

  /// 파티 — 전액 온라인 결제가 기본이고, 현장 결제를 골랐을 때만 노쇼 방지용
  /// 예약금을 열어 준다(일반 유료 파티에 예약금 단계를 끼워 넣지 않는다).
  factory PaymentPolicySection.party({
    required PaymentPolicy policy,
    required ValueChanged<PaymentPolicy> onChanged,
    required int? sampleTotal,
    Color accent = const Color(0xFFFF6FA0),
  }) => PaymentPolicySection._(
    policy: policy,
    onChanged: onChanged,
    sampleTotal: sampleTotal,
    totalKnown: true,
    nestedUpfrontToggle: true,
    modes: const [PaymentMode.prepaid, PaymentMode.onsite],
    accent: accent,
    title: '결제 방식',
    description: '참가비를 언제 받을지 정해요. 지금은 무통장입금·현장결제만 받을 수 있어요.',
  );

  /// 장소대여·숙박 / 플레이스 좌석·룸 — 방식을 평면으로 고른다.
  factory PaymentPolicySection.modes({
    required PaymentPolicy policy,
    required ValueChanged<PaymentPolicy> onChanged,
    required int? sampleTotal,
    required bool totalKnown,
    required List<PaymentMode> modes,
    required String description,
    Color accent = const Color(0xFF2E9E7B),
    String title = '결제 방식',
  }) => PaymentPolicySection._(
    policy: policy,
    onChanged: onChanged,
    sampleTotal: sampleTotal,
    totalKnown: totalKnown,
    nestedUpfrontToggle: false,
    // 총액을 모르면 전액 선결제는 계산 자체가 불가능하다.
    modes: totalKnown
        ? modes
        : modes.where((m) => m != PaymentMode.prepaid).toList(),
    accent: accent,
    title: title,
    description: description,
  );

  /// 이 도메인에서 고를 수 있는 예약금 방식.
  List<UpfrontType> get _upfrontTypes =>
      totalKnown ? UpfrontType.values : const [UpfrontType.fixed];

  /// 무통장입금이 필요한 방식을 고를 때 — **수취계좌부터 확인한다.**
  ///
  /// 선결제·예약금은 결국 무통장입금으로 받는다는 뜻이고(PG 계약 전),
  /// 참가비는 파티츄가 아니라 호스트 계좌로 바로 들어간다. 계좌가 인증돼
  /// 있지 않으면 참가자 화면에서 무통장입금이 아예 뜨지 않으므로, 모집을
  /// 열고 나서가 아니라 **여기서** 알려주고 등록으로 안내한다.
  ///
  /// 계좌를 준비하지 않으면 방식은 바뀌지 않는다 — 고른 것처럼 보였다가
  /// 신청이 안 되는 상태가 가장 나쁘다.
  Future<void> _selectNeedingAccount(
    BuildContext context,
    PaymentPolicy next,
  ) async {
    // 현장 전액결제는 계좌가 필요 없다(같은 함수를 지나가도 그대로 통과).
    if (!next.allowedMethods.contains(PaymentMethod.bankTransfer)) {
      onChanged(next);
      return;
    }
    if (await ensurePayoutAccountVerified(context)) onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.25), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payments_rounded, size: 20, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: Colors.black54,
            ),
          ),
          const Divider(height: 28),

          if (nestedUpfrontToggle)
            ..._buildPartyStyle(context)
          else
            ..._buildFlatStyle(context),

          if (policy.isPartial) ...[
            const SizedBox(height: 16),
            _label('예약금 방식'),
            const SizedBox(height: 6),
            for (final t in _upfrontTypes)
              _radioTile(
                label: _upfrontLabel(t),
                description: t == UpfrontType.percentage
                    ? '이용요금이 달라지면 예약금도 함께 달라져요.'
                    : '이용요금과 상관없이 늘 같은 금액을 받아요.',
                selected: policy.upfrontType == t,
                onTap: () => onChanged(policy.copyWith(upfrontType: t)),
              ),
            const SizedBox(height: 12),
            if (policy.upfrontType != null) _amountField(),
            _preview(),
          ],
        ],
      ),
    );
  }

  // ── 방식 선택 ────────────────────────────────────────────────────────

  /// 파티식 — 전액 온라인 / 현장 결제 + 예약금 토글.
  List<Widget> _buildPartyStyle(BuildContext context) {
    // 예약금을 받는 순간 내부 상태는 partial이므로, 화면의 '현장 결제'는
    // onsite와 partial 둘 다를 뜻한다.
    final isOnsiteBranch =
        policy.mode == PaymentMode.onsite || policy.mode == PaymentMode.partial;
    return [
      _radioTile(
        label: '전액 온라인 결제',
        description: '신청할 때 참가비 전액을 받아요.',
        selected: policy.mode == PaymentMode.prepaid,
        onTap: () => _selectNeedingAccount(
          context,
          const PaymentPolicy(mode: PaymentMode.prepaid),
        ),
      ),
      _radioTile(
        label: '현장 결제',
        description: '참가비를 현장에서 받아요.',
        selected: isOnsiteBranch,
        onTap: () => onChanged(const PaymentPolicy(mode: PaymentMode.onsite)),
      ),
      if (isOnsiteBranch) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '예약금 받기',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '일부를 미리 받아 노쇼를 줄여요. 나머지는 현장에서 받아요.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: policy.isPartial,
                activeThumbColor: accent,
                onChanged: (on) {
                  // 끄는 쪽(현장 전액)은 계좌가 필요 없다 — 바로 반영한다.
                  if (!on) {
                    onChanged(const PaymentPolicy(mode: PaymentMode.onsite));
                    return;
                  }
                  _selectNeedingAccount(
                    context,
                    PaymentPolicy(
                      mode: PaymentMode.partial,
                      upfrontType: policy.upfrontType ?? UpfrontType.fixed,
                      upfrontPercent: policy.upfrontPercent,
                      upfrontFixedAmount: policy.upfrontFixedAmount,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    ];
  }

  /// 평면 — 허용된 방식을 그대로 나열한다.
  List<Widget> _buildFlatStyle(BuildContext context) => [
    for (final m in modes)
      _radioTile(
        label: m.label,
        description: _modeDescription(m),
        selected: policy.mode == m,
        onTap: () => _selectNeedingAccount(
          context,
          m == PaymentMode.partial
              ? PaymentPolicy(
                  mode: m,
                  // 총액을 모르는 도메인은 고정 예약금만 되므로 기본값을 맞춰 둔다.
                  upfrontType:
                      policy.upfrontType ??
                      (totalKnown ? UpfrontType.percentage : UpfrontType.fixed),
                  upfrontPercent: policy.upfrontPercent,
                  upfrontFixedAmount: policy.upfrontFixedAmount,
                )
              : PaymentPolicy(mode: m),
        ),
      ),
  ];

  String _modeDescription(PaymentMode m) => switch (m) {
    PaymentMode.prepaid => '예약할 때 이용요금 100%를 받아요.',
    PaymentMode.partial => '예약금을 먼저 받고 잔금은 현장에서 받아요.',
    PaymentMode.onsite => '앱에서는 받지 않고 현장에서 전액 받아요.',
  };

  String _upfrontLabel(UpfrontType t) => switch (t) {
    // 도메인에 따라 부르는 말이 다르다 — 파티는 '참가비', 나머지는 '이용금액'.
    UpfrontType.percentage => nestedUpfrontToggle ? '참가비의 %' : '이용금액의 %',
    UpfrontType.fixed => '고정 예약금',
  };

  // ── 금액 입력 ────────────────────────────────────────────────────────

  Widget _amountField() {
    final isPercent = policy.upfrontType == UpfrontType.percentage;
    final value = isPercent
        ? (policy.upfrontPercent?.toString() ?? '')
        : (policy.upfrontFixedAmount?.toString() ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          key: ValueKey('upfront_${policy.upfrontType?.key}'),
          initialValue: value,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: isPercent ? '예) 20' : '예) 50000',
            hintStyle: const TextStyle(fontSize: 12, color: Colors.black38),
            suffixText: isPercent ? '%' : '원',
            filled: true,
            fillColor: const Color(0xFFF7F7F9),
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (v) {
            final n = int.tryParse(v.replaceAll(',', '').trim());
            onChanged(
              isPercent
                  ? PaymentPolicy(
                      mode: policy.mode,
                      upfrontType: policy.upfrontType,
                      upfrontPercent: n,
                      upfrontFixedAmount: policy.upfrontFixedAmount,
                    )
                  : PaymentPolicy(
                      mode: policy.mode,
                      upfrontType: policy.upfrontType,
                      upfrontPercent: policy.upfrontPercent,
                      upfrontFixedAmount: n,
                    ),
            );
          },
        ),
        if (policy.validationMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              policy.validationMessage!,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFFD9534F)),
            ),
          ),
      ],
    );
  }

  // ── 계산 예시 ────────────────────────────────────────────────────────

  /// 입력하는 즉시 "지금 얼마 / 나중에 얼마"를 보여준다. 가격이나 비율을
  /// 고치면 이 값도 함께 바뀐다.
  Widget _preview() {
    if (!policy.isComplete) return const SizedBox.shrink();

    // 총액을 모르는 예약은 잔금을 지어내지 않는다.
    if (!totalKnown) {
      return _previewBox([
        _previewRow(
          '지금 결제할 예약금',
          formatWon(policy.upfrontFixedAmount ?? 0),
          strong: true,
        ),
        _previewRow('잔금', '현장에서 주문한 만큼', muted: true),
      ]);
    }

    if (sampleTotal == null || sampleTotal! <= 0) {
      return _previewBox([
        _previewRow('계산 예시', '금액을 먼저 입력하면 예시가 나와요', muted: true),
      ]);
    }

    final b = PaymentBreakdown.of(policy, sampleTotal);
    final unit = nestedUpfrontToggle ? '참가비' : '이용요금';
    return _previewBox([
      _previewRow('$unit ${formatWon(sampleTotal!)} 기준', '', header: true),
      const SizedBox(height: 6),
      _previewRow('지금 결제할 예약금', formatWon(b.upfrontAmount ?? 0), strong: true),
      _previewRow('현장 결제 잔금', formatWon(b.remainingAmount ?? 0)),
    ]);
  }

  Widget _previewBox(List<Widget> children) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  Widget _previewRow(
    String label,
    String value, {
    bool strong = false,
    bool muted = false,
    bool header = false,
  }) {
    if (header) {
      return Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Colors.black54,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: muted ? Colors.black45 : Colors.black87,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: strong ? 14 : 12.5,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              color: strong
                  ? accent
                  : (muted ? Colors.black45 : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  // ── 부품 ────────────────────────────────────────────────────────────

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
  );

  Widget _radioTile({
    required String label,
    required String description,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? accent : Colors.black26,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
